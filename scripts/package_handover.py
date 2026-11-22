#!/usr/bin/env python3
"""Create a source-only ZHANAR handover archive from an explicit allowlist."""

from __future__ import annotations

import hashlib
import re
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "artifacts" / "ZHANAR-Massage-Academy-source.zip"
PACKAGE_ROOT = "ZHANAR-Massage-Academy"

ROOT_FILES = (
    ".gitignore",
    "APP_STORE_IAP_METADATA.md",
    "APP_STORE_LISTING.md",
    "AppStoreExportOptions.plist",
    "CONTENT_GUIDE_RU.md",
    "HANDOVER.md",
    "Package.swift",
    "PRIVACY_POLICY_DRAFT.md",
    "README.md",
    "SECURITY_REVIEW_ORIGINAL.md",
    "TECHNICAL_PLAN.md",
    "TERMS_OF_USE_DRAFT.md",
)
SOURCE_DIRS = (
    "Config",
    "Massage app",
    "Massage app.xcodeproj",
    "scripts",
    "supabase",
    "tests",
    "tests-swift",
)
EXCLUDED_PARTS = {".git", ".build", ".swiftpm", "__pycache__", "xcuserdata", ".temp"}


def included(path: Path) -> bool:
    relative = path.relative_to(ROOT)
    return (
        path.is_file()
        and not path.is_symlink()
        and not any(part in EXCLUDED_PARTS for part in relative.parts)
        and not any(part.startswith(".env") for part in relative.parts)
        and path.suffix not in {".xcarchive", ".xcresult"}
        and path.name != ".DS_Store"
    )


def main() -> None:
    paths = [ROOT / filename for filename in ROOT_FILES]
    paths.extend(path for directory in SOURCE_DIRS for path in (ROOT / directory).rglob("*"))
    paths.append(ROOT / "artifacts" / "zhanar-latest-ios26-launch.png")
    paths.append(ROOT / "artifacts" / "zhanar-current-ios26-launch.png")
    paths.append(ROOT / "artifacts" / "zhanar-current-ios27-launch.png")
    paths.append(ROOT / "artifacts" / "zhanar-course-ru-preview-verified.png")
    paths.append(ROOT / "artifacts" / "zhanar-paywall-product-unavailable-ru.png")
    paths.append(ROOT / "artifacts" / "zhanar-current-launch.png")
    paths.append(ROOT / "artifacts" / "zhanar-ios26-kazakh-launch.png")
    paths.append(ROOT / "artifacts" / "zhanar-signin-contrast-fixed.png")
    paths.append(ROOT / "artifacts" / "debug-launch-current.png")
    missing = [str(path.relative_to(ROOT)) for path in paths if not path.exists()]
    if missing:
        raise SystemExit(f"Required handover files are missing: {', '.join(missing)}")

    files = sorted((path for path in paths if included(path)), key=lambda path: str(path.relative_to(ROOT)))
    packaged_paths = {path.relative_to(ROOT).as_posix() for path in files}
    referenced_images = set()
    for path in files:
        if path.suffix == ".md":
            referenced_images.update(re.findall(
                r"artifacts/[A-Za-z0-9_./-]+\.(?:png|jpg|jpeg)",
                path.read_text(encoding="utf-8"),
            ))
    missing_images = referenced_images - packaged_paths
    if missing_images:
        raise SystemExit("Documented screenshots are not packaged: " + ", ".join(sorted(missing_images)))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(OUTPUT, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
        for path in files:
            archive.write(path, arcname=f"{PACKAGE_ROOT}/{path.relative_to(ROOT).as_posix()}")

    digest = hashlib.sha256(OUTPUT.read_bytes()).hexdigest()
    print(f"Created {OUTPUT} ({len(files)} files, {OUTPUT.stat().st_size:,} bytes)")
    print(f"SHA-256: {digest}")


if __name__ == "__main__":
    main()
