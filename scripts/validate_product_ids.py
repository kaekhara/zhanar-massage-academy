#!/usr/bin/env python3
"""Check that iOS, StoreKit, and seeded course product IDs agree."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read_text(path: str) -> str:
    try:
        return (ROOT / path).read_text(encoding="utf-8")
    except OSError as error:
        raise SystemExit(f"cannot read {path}: {error}") from None


def main() -> int:
    swift = read_text("Massage app/PurchaseManager.swift")
    swift_ids = set(re.findall(r'static let \w+CourseID\s*=\s*"([^"]+)"', swift))
    if len(swift_ids) != 2:
        raise SystemExit(f"expected two course IDs in PurchaseManager.swift, found {sorted(swift_ids)}")
    expected_demo_ids = {"com.zhanar.course.standard", "com.zhanar.course.selfmassage"}
    if swift_ids != expected_demo_ids:
        raise SystemExit(f"demo course IDs must use the approved ZHANAR namespace: {sorted(swift_ids)}")

    manifest_paths = (
        "supabase/course-package.example.json",
        "supabase/course-package.selfmassage.example.json",
    )
    try:
        storekit = json.loads(read_text("Massage app.xcodeproj/ZhanarProducts.storekit"))
        manifests = {path: json.loads(read_text(path)) for path in manifest_paths}
    except json.JSONDecodeError as error:
        raise SystemExit(f"invalid JSON in StoreKit config or course manifests: {error}") from None

    products = storekit.get("products", [])
    storekit_ids = [product.get("productID") for product in products]
    if any(product.get("type") != "NonConsumable" for product in products):
        raise SystemExit("all course products in ZhanarProducts.storekit must be NonConsumable")
    if len(storekit_ids) != len(set(storekit_ids)):
        raise SystemExit("ZhanarProducts.storekit contains duplicate product IDs")
    for product in products:
        localizations = product.get("localizations")
        if not isinstance(localizations, list) or not localizations:
            raise SystemExit(f"{product.get('productID')}: add at least one StoreKit product localization")
        for localization in localizations:
            if not isinstance(localization, dict):
                raise SystemExit(f"{product.get('productID')}: invalid StoreKit localization entry")
            display_name = localization.get("displayName", "")
            description = localization.get("description", "")
            locale = localization.get("locale", "unknown")
            if not isinstance(display_name, str) or not 2 <= len(display_name) <= 30:
                raise SystemExit(f"{product.get('productID')} ({locale}): display name must be 2–30 characters")
            if not isinstance(description, str) or len(description) > 45:
                raise SystemExit(f"{product.get('productID')} ({locale}): description must be at most 45 characters")

    iap_metadata_rows = 0
    for line in read_text("APP_STORE_IAP_METADATA.md").splitlines():
        if not line.startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip("|").split("|")]
        if len(cells) != 3 or cells[0] not in {"English (U.K.)", "Russian"}:
            continue
        locale, display_name, description = cells
        if not 2 <= len(display_name) <= 30:
            raise SystemExit(f"App Store IAP metadata ({locale}): display name must be 2–30 characters")
        if len(description) > 45:
            raise SystemExit(f"App Store IAP metadata ({locale}): description must be at most 45 characters")
        iap_metadata_rows += 1
    if iap_metadata_rows != 4:
        raise SystemExit(f"APP_STORE_IAP_METADATA.md must contain four English (U.K.) and Russian product localizations; found {iap_metadata_rows}")

    seed_sql = read_text("supabase/seed.sql")
    seed_prefix = seed_sql.split("with section_seed", 1)[0]
    seed_rows = re.findall(r"\(\s*'([^']+)'\s*,\s*'([^']+)'\s*,", seed_prefix)
    seed_ids = {store_product_id for course_id, store_product_id in seed_rows if course_id == store_product_id}
    if len(seed_ids) != 2 or any(course_id != store_product_id for course_id, store_product_id in seed_rows):
        raise SystemExit("supabase/seed.sql must seed two courses whose id matches store_product_id")

    section_source = seed_sql.split("with section_seed", 1)[1].split("), section_rows", 1)[0]
    seed_sections = re.findall(
        r"\(\s*'([^']+)'\s*,\s*'([a-z_]+)'\s*,\s*'([^']*)'\s*,\s*(\d+)\s*,\s*(\d+)\s*\)",
        section_source,
    )
    expected_sections: dict[str, list[tuple[str, str, int, int]]] = {}
    for course_id, key, title, order, lesson_count in seed_sections:
        expected_sections.setdefault(course_id, []).append((key, title, int(order), int(lesson_count)))
    if set(expected_sections) != seed_ids:
        raise SystemExit("could not match the seeded section structure to both course product IDs")

    manifest_ids: set[str] = set()
    for path, manifest in manifests.items():
        course = manifest.get("course", {})
        course_id = course.get("id")
        product_id = course.get("store_product_id")
        if course_id != product_id or product_id not in swift_ids:
            raise SystemExit(f"{path} must use a course ID declared in PurchaseManager.swift")
        if product_id in manifest_ids:
            raise SystemExit(f"multiple example manifests use product ID {product_id}")
        manifest_ids.add(product_id)

        actual_sections = course.get("sections")
        expected = expected_sections.get(product_id, [])
        if not isinstance(actual_sections, list) or len(actual_sections) != len(expected):
            raise SystemExit(f"{path} does not contain all {len(expected)} seeded sections")
        for section, (key, title, order, lesson_count) in zip(actual_sections, expected):
            section_id = f"{product_id}.{key}"
            if section.get("id") != section_id or section.get("sort_order") != order:
                raise SystemExit(f"{path} has an unexpected ID or order for section {key}")
            if section.get("title") != title:
                raise SystemExit(f"{path} section {key} title no longer matches supabase/seed.sql")
            lessons = section.get("lessons")
            if not isinstance(lessons, list) or len(lessons) != lesson_count:
                raise SystemExit(f"{path} section {key} must contain {lesson_count} seeded lessons")
            for lesson_order, lesson in enumerate(lessons, start=1):
                expected_lesson_id = f"{section_id}.{lesson_order:02d}"
                if lesson.get("id") != expected_lesson_id or lesson.get("sort_order") != lesson_order:
                    raise SystemExit(f"{path} has an unexpected ID or order for lesson {expected_lesson_id}")

    if manifest_ids != swift_ids:
        raise SystemExit(f"example manifests do not cover all course products: {sorted(swift_ids - manifest_ids)}")

    expected = swift_ids
    sources = {
        "PurchaseManager.swift": swift_ids,
        "ZhanarProducts.storekit": set(storekit_ids),
        "supabase/seed.sql": seed_ids,
    }
    mismatches = {name: ids for name, ids in sources.items() if ids != expected}
    if mismatches:
        details = "; ".join(f"{name}: {sorted(ids)}" for name, ids in mismatches.items())
        raise SystemExit(f"course product IDs do not match PurchaseManager.swift ({details})")

    print("Course manifests, section/lesson IDs, StoreKit products, and Supabase seed match:")
    for product_id in sorted(expected):
        print(f"  {product_id}")
    print("StoreKit product localization display names and descriptions fit Apple's field limits.")
    print("App Store IAP metadata drafts contain four in-limit English (U.K.) and Russian localizations.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
