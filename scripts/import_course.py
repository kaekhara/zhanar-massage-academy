#!/usr/bin/env python3
"""Upload a ZHANAR course package, public cover image, and catalog to Supabase."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import mimetypes
import os
import re
import sys
import tempfile
import time
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode, urljoin, urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener


BUCKET = "course-videos"
COVER_BUCKET = "course-covers"
CHUNK_SIZE = 6 * 1024 * 1024
MAX_FREE_PLAN_FILE_SIZE = 50_000_000
MAX_COVER_FILE_SIZE = 5_000_000
ID_PATTERN = re.compile(r"^[A-Za-z0-9._-]+$")
VIDEO_EXTENSIONS = {".mp4", ".mov", ".m4v"}
COVER_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}


class ImportFailure(RuntimeError):
    pass


class RejectRedirectHandler(HTTPRedirectHandler):
    """Never forward authenticated API or Storage credentials to a redirect target."""

    def redirect_request(self, req: Request, fp: Any, code: int, msg: str, headers: Any, newurl: str) -> Request:
        raise HTTPError(req.full_url, code, msg, headers, fp)


AUTHENTICATED_OPENER = build_opener(RejectRedirectHandler())


def open_authenticated(request: Request, timeout: float):
    return AUTHENTICATED_OPENER.open(request, timeout=timeout)


def fail(message: str) -> None:
    raise ImportFailure(message)


def required_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        fail(f"{label} must be a non-empty string")
    return value.strip()


def valid_id(value: Any, label: str) -> str:
    result = required_string(value, label)
    if not ID_PATTERN.fullmatch(result):
        fail(f"{label} may contain only letters, numbers, dots, underscores, and hyphens")
    return result


def positive_int(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        fail(f"{label} must be a positive integer")
    return value


def optional_text(value: Any, label: str) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str):
        fail(f"{label} must be a string when provided")
    return value.strip() or None

def file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def read_manifest(manifest_path: Path) -> tuple[dict[str, Any], list[dict[str, Any]], list[dict[str, Any]]]:
    try:
        root = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read manifest: {error}")
    if not isinstance(root, dict) or not isinstance(root.get("course"), dict):
        fail("manifest must contain a course object")

    course_source = root["course"]
    course = {
        "id": valid_id(course_source.get("id"), "course.id"),
        "store_product_id": valid_id(course_source.get("store_product_id"), "course.store_product_id"),
        "title": required_string(course_source.get("title"), "course.title"),
        "subtitle": str(course_source.get("subtitle", "")).strip(),
        "description": str(course_source.get("description", "")).strip(),
        "title_ru": optional_text(course_source.get("title_ru"), "course.title_ru"),
        "subtitle_ru": optional_text(course_source.get("subtitle_ru"), "course.subtitle_ru"),
        "description_ru": optional_text(course_source.get("description_ru"), "course.description_ru"),
        "category": optional_text(course_source.get("category"), "course.category"),
        "category_ru": optional_text(course_source.get("category_ru"), "course.category_ru"),
        "instructor_name": optional_text(course_source.get("instructor_name"), "course.instructor_name"),
        "instructor_title": optional_text(course_source.get("instructor_title"), "course.instructor_title"),
        "instructor_title_ru": optional_text(course_source.get("instructor_title_ru"), "course.instructor_title_ru"),
        "instructor_bio": optional_text(course_source.get("instructor_bio"), "course.instructor_bio"),
        "instructor_bio_ru": optional_text(course_source.get("instructor_bio_ru"), "course.instructor_bio_ru"),
        "sort_order": positive_int(course_source.get("sort_order"), "course.sort_order"),
        "is_published": False,
    }
    if course["id"] != course["store_product_id"]:
        fail("course.id must match course.store_product_id so future imports update the same course")
    sections_source = course_source.get("sections")
    if not isinstance(sections_source, list) or not sections_source:
        fail("course.sections must be a non-empty array")

    sections: list[dict[str, Any]] = []
    lessons: list[dict[str, Any]] = []
    section_ids: set[str] = set()
    lesson_ids: set[str] = set()
    section_orders: set[int] = set()
    lesson_orders: dict[str, set[int]] = {}
    manifest_root = manifest_path.resolve().parent

    cover_relative = course_source.get("cover_image_file")
    if cover_relative is not None:
        cover_relative = required_string(cover_relative, "course.cover_image_file")
        cover_file = (manifest_root / cover_relative).resolve()
        if os.path.commonpath((str(manifest_root), str(cover_file))) != str(manifest_root):
            fail("course.cover_image_file must stay inside the package directory")
        if not cover_file.is_file():
            fail(f"cover image file does not exist: {cover_relative}")
        if cover_file.suffix.lower() not in COVER_EXTENSIONS:
            fail(f"unsupported cover image extension for {cover_relative}; use jpg, png, or webp")
        cover_size = cover_file.stat().st_size
        if cover_size == 0 or cover_size > MAX_COVER_FILE_SIZE:
            fail(f"cover image must be between 1 byte and {MAX_COVER_FILE_SIZE:,} bytes: {cover_relative}")
        with cover_file.open("rb") as image_file:
            signature = image_file.read(12)
        extension = cover_file.suffix.lower()
        valid_signature = (
            (extension in {".jpg", ".jpeg"} and signature.startswith(b"\xff\xd8\xff"))
            or (extension == ".png" and signature.startswith(b"\x89PNG\r\n\x1a\n"))
            or (extension == ".webp" and signature[:4] == b"RIFF" and signature[8:12] == b"WEBP")
        )
        if not valid_signature:
            fail(f"cover image format does not match its extension: {cover_relative}")
        cover_digest = file_digest(cover_file)
        cover_extension = ".jpg" if extension == ".jpeg" else extension
        course["cover_path"] = f"{course['store_product_id']}/cover-{cover_digest}{cover_extension}"
        course["_cover_file"] = cover_file
        course["_cover_sha256"] = cover_digest
        course["_cover_content_type"] = mimetypes.guess_type(cover_file.name)[0] or "image/jpeg"

    for section_index, section_source in enumerate(sections_source, start=1):
        if not isinstance(section_source, dict):
            fail(f"sections[{section_index - 1}] must be an object")
        section_id = valid_id(section_source.get("id"), f"sections[{section_index - 1}].id")
        if section_id in section_ids:
            fail(f"duplicate section id: {section_id}")
        section_ids.add(section_id)
        section_order = positive_int(section_source.get("sort_order"), f"section {section_id}.sort_order")
        if section_order in section_orders:
            fail(f"duplicate section sort_order: {section_order}")
        section_orders.add(section_order)
        sections.append({
            "id": section_id,
            "course_id": course["id"],
            "title": required_string(section_source.get("title"), f"section {section_id}.title"),
            "description": str(section_source.get("description", "")).strip(),
            "title_ru": optional_text(section_source.get("title_ru"), f"section {section_id}.title_ru"),
            "description_ru": optional_text(section_source.get("description_ru"), f"section {section_id}.description_ru"),
            "sort_order": section_order,
        })

        lesson_sources = section_source.get("lessons")
        if not isinstance(lesson_sources, list) or not lesson_sources:
            fail(f"section {section_id} must contain at least one lesson")
        lesson_orders[section_id] = set()
        for lesson_index, lesson_source in enumerate(lesson_sources, start=1):
            if not isinstance(lesson_source, dict):
                fail(f"lessons[{lesson_index - 1}] in {section_id} must be an object")
            lesson_id = valid_id(lesson_source.get("id"), f"lesson in {section_id}.id")
            if lesson_id in lesson_ids:
                fail(f"duplicate lesson id: {lesson_id}")
            lesson_ids.add(lesson_id)
            lesson_order = positive_int(lesson_source.get("sort_order"), f"lesson {lesson_id}.sort_order")
            if lesson_order in lesson_orders[section_id]:
                fail(f"duplicate lesson sort_order {lesson_order} in section {section_id}")
            lesson_orders[section_id].add(lesson_order)
            video_relative = required_string(lesson_source.get("video_file"), f"lesson {lesson_id}.video_file")
            video_path = (manifest_root / video_relative).resolve()
            if os.path.commonpath((str(manifest_root), str(video_path))) != str(manifest_root):
                fail(f"lesson {lesson_id}.video_file must stay inside the package directory")
            if not video_path.is_file():
                fail(f"video file does not exist: {video_relative}")
            extension = video_path.suffix.lower()
            if extension not in VIDEO_EXTENSIONS:
                fail(f"unsupported video extension for {video_relative}; use mp4, mov, or m4v")
            video_size = video_path.stat().st_size
            if video_size == 0:
                fail(f"video file is empty: {video_relative}")
            if video_size > MAX_FREE_PLAN_FILE_SIZE:
                fail(
                    f"video {video_relative} is {video_size / 1_000_000:.1f} MB; "
                    "Supabase Free allows at most 50 MB (50,000,000 bytes) per file. Compress or split it before import"
                )
            duration = lesson_source.get("duration_seconds")
            if duration is not None:
                duration = positive_int(duration, f"lesson {lesson_id}.duration_seconds")
            is_preview = lesson_source.get("is_preview", False)
            if not isinstance(is_preview, bool):
                fail(f"lesson {lesson_id}.is_preview must be true or false")

            digest = file_digest(video_path)
            object_name = f"{lesson_id}-{digest}{extension}"
            object_path = f"{course['store_product_id']}/{object_name}"
            lessons.append({
                "id": lesson_id,
                "section_id": section_id,
                "title": required_string(lesson_source.get("title"), f"lesson {lesson_id}.title"),
                "description": str(lesson_source.get("description", "")).strip(),
                "title_ru": optional_text(lesson_source.get("title_ru"), f"lesson {lesson_id}.title_ru"),
                "description_ru": optional_text(lesson_source.get("description_ru"), f"lesson {lesson_id}.description_ru"),
                "video_path": object_path,
                "duration_seconds": duration,
                "sort_order": lesson_order,
                "is_preview": is_preview,
                "_video_file": video_path,
                "_video_sha256": digest,
                "_content_type": mimetypes.guess_type(video_path.name)[0] or "video/mp4",
            })

    return course, sections, lessons


class SupabaseAdmin:
    def __init__(self) -> None:
        self.api_url = required_string(os.environ.get("SUPABASE_URL"), "SUPABASE_URL").rstrip("/")
        parsed = urlparse(self.api_url)
        if parsed.scheme != "https" or not parsed.hostname:
            fail("SUPABASE_URL must be a valid HTTPS project URL")
        self.service_role_jwt = required_string(os.environ.get("SUPABASE_SERVICE_ROLE_KEY"), "SUPABASE_SERVICE_ROLE_KEY")
        self.api_key = os.environ.get("SUPABASE_API_KEY", "").strip() or self.service_role_jwt
        storage_url = os.environ.get("SUPABASE_STORAGE_URL", "").strip().rstrip("/")
        if storage_url:
            storage_host = urlparse(storage_url).hostname
            if urlparse(storage_url).scheme != "https" or not storage_host:
                fail("SUPABASE_STORAGE_URL must be a valid HTTPS URL")
            self.storage_url = storage_url
        elif parsed.hostname.endswith(".supabase.co"):
            project_ref = parsed.hostname.split(".", 1)[0]
            self.storage_url = f"https://{project_ref}.storage.supabase.co"
        else:
            fail("set SUPABASE_STORAGE_URL when using a custom Supabase domain")

    def request(self, base: str, method: str, path: str, body: Any = None, extra_headers: dict[str, str] | None = None) -> tuple[int, Any, Any]:
        data = None if body is None else bytes(body) if isinstance(body, (bytes, bytearray)) else json.dumps(body, ensure_ascii=False).encode("utf-8")
        headers = {
            "apikey": self.api_key,
            "Authorization": f"Bearer {self.service_role_jwt}",
            "Accept": "application/json",
        }
        if data is not None and not isinstance(body, (bytes, bytearray)):
            headers["Content-Type"] = "application/json"
        if extra_headers:
            headers.update(extra_headers)
        request = Request(f"{base}{path}", data=data, headers=headers, method=method)
        try:
            with open_authenticated(request, timeout=120) as response:
                raw = response.read()
                parsed: Any = json.loads(raw) if raw else None
                return response.status, response.headers, parsed
        except HTTPError as error:
            detail = error.read(1000).decode("utf-8", errors="replace")
            raise ImportFailure(f"Supabase request failed ({error.code}): {detail}") from None
        except (URLError, TimeoutError) as error:
            raise ImportFailure(f"Supabase request failed: {error}") from None

    def rest(self, method: str, table_path: str, body: Any = None, prefer: str | None = None) -> Any:
        headers = {"Prefer": prefer} if prefer else None
        _, _, response = self.request(self.api_url, method, f"/rest/v1/{table_path}", body, headers)
        return response

    def upload_video(self, lesson: dict[str, Any], quiet: bool = False) -> None:
        source: Path = lesson["_video_file"]
        snapshot_fd, snapshot_name = tempfile.mkstemp(prefix="zhanar-video-", suffix=source.suffix)
        snapshot = Path(snapshot_name)
        digest = hashlib.sha256()
        try:
            with os.fdopen(snapshot_fd, "wb") as snapshot_file:
                with source.open("rb") as original:
                    while chunk := original.read(1024 * 1024):
                        digest.update(chunk)
                        snapshot_file.write(chunk)
            if digest.hexdigest() != lesson["_video_sha256"]:
                fail(f"video changed after manifest validation: {source.name}; run the import again")
            snapshot_lesson = {**lesson, "_video_file": snapshot}
            self._upload_video_snapshot(snapshot_lesson, quiet)
        finally:
            snapshot.unlink(missing_ok=True)

    def upload_cover(self, course: dict[str, Any]) -> None:
        source: Path | None = course.get("_cover_file")
        if source is None:
            return
        snapshot_fd, snapshot_name = tempfile.mkstemp(prefix="zhanar-cover-", suffix=source.suffix)
        snapshot = Path(snapshot_name)
        digest = hashlib.sha256()
        try:
            with os.fdopen(snapshot_fd, "wb") as snapshot_file, source.open("rb") as original:
                while chunk := original.read(1024 * 1024):
                    digest.update(chunk)
                    snapshot_file.write(chunk)
            if digest.hexdigest() != course["_cover_sha256"]:
                fail(f"cover image changed after manifest validation: {source.name}; run the import again")
            object_path = quote(course["cover_path"], safe="/")
            self.request(
                self.storage_url,
                "POST",
                f"/storage/v1/object/{COVER_BUCKET}/{object_path}",
                snapshot.read_bytes(),
                {
                    "Content-Type": course["_cover_content_type"],
                    "Cache-Control": "public, max-age=31536000, immutable",
                    "x-upsert": "true",
                },
            )
        finally:
            snapshot.unlink(missing_ok=True)

    def _upload_video_snapshot(self, lesson: dict[str, Any], quiet: bool = False) -> None:
        source: Path = lesson["_video_file"]
        size = source.stat().st_size
        metadata = {
            "bucketName": BUCKET,
            "objectName": lesson["video_path"],
            "contentType": lesson["_content_type"],
            "cacheControl": "3600",
        }
        encoded = ",".join(f"{key} {base64.b64encode(value.encode()).decode()}" for key, value in metadata.items())
        endpoint = f"{self.storage_url}/storage/v1/upload/resumable"
        status, headers, _ = self.request(
            self.storage_url,
            "POST",
            "/storage/v1/upload/resumable",
            b"",
            {
                "Tus-Resumable": "1.0.0",
                "Upload-Length": str(size),
                "Upload-Metadata": encoded,
                "x-upsert": "true",
                "Content-Length": "0",
            },
        )
        if status != 201:
            fail(f"Storage did not start upload for {source.name} (HTTP {status})")
        location = headers.get("Location")
        if not location:
            fail(f"Storage did not return an upload URL for {source.name}")
        upload_url = urljoin(endpoint, location)
        upload_parts = urlparse(upload_url)
        if (
            upload_parts.scheme != "https" or
            upload_parts.hostname != urlparse(self.storage_url).hostname or
            upload_parts.port not in (None, 443)
        ):
            fail("Storage returned an upload URL on an unexpected host; refusing to send credentials")
        offset = int(headers.get("Upload-Offset", "0"))
        if not quiet:
            print(f"Uploading {source.name} ({size / (1024 * 1024):.1f} MiB)")
        with source.open("rb") as video:
            while offset < size:
                video.seek(offset)
                chunk = video.read(min(CHUNK_SIZE, size - offset))
                if not chunk:
                    fail(f"unexpected end of file while uploading {source.name}")
                starting_offset = offset
                chunk_end = starting_offset + len(chunk)
                for attempt in range(5):
                    request_offset = offset
                    remaining_chunk = chunk[request_offset - starting_offset:]
                    if not remaining_chunk:
                        break
                    request = Request(
                        upload_url,
                        data=remaining_chunk,
                        headers={
                            "apikey": self.api_key,
                            "Authorization": f"Bearer {self.service_role_jwt}",
                            "Tus-Resumable": "1.0.0",
                            "Upload-Offset": str(request_offset),
                            "Content-Type": "application/offset+octet-stream",
                        },
                        method="PATCH",
                    )
                    try:
                        with open_authenticated(request, timeout=300) as response:
                            next_offset = response.headers.get("Upload-Offset")
                            expected_offset = request_offset + len(remaining_chunk)
                            if next_offset is None:
                                fail(f"Storage omitted Upload-Offset after uploading {source.name}")
                            try:
                                response_offset = int(next_offset)
                            except ValueError:
                                fail(f"Storage returned an invalid upload offset for {source.name}")
                            if response_offset != expected_offset:
                                fail(f"Storage acknowledged offset {response_offset}, expected {expected_offset}, for {source.name}")
                            offset = response_offset
                            break
                    except (HTTPError, URLError, TimeoutError) as error:
                        # A timed-out PATCH may have reached Storage. Resume from the exact server offset.
                        try:
                            head = Request(
                                upload_url,
                                headers={
                                    "apikey": self.api_key,
                                    "Authorization": f"Bearer {self.service_role_jwt}",
                                    "Tus-Resumable": "1.0.0",
                                },
                                method="HEAD",
                            )
                            with open_authenticated(head, timeout=60) as response:
                                server_offset = int(response.headers.get("Upload-Offset", str(request_offset)))
                            if server_offset < request_offset or server_offset > chunk_end:
                                fail(f"Storage returned an invalid upload offset for {source.name}")
                            offset = server_offset
                            if offset == chunk_end:
                                break
                            if attempt == 4:
                                fail(f"upload failed for {source.name}: {error}")
                            time.sleep(min(2 ** attempt, 16))
                        except (HTTPError, URLError, TimeoutError, ValueError) as resume_error:
                            if attempt == 4:
                                fail(f"upload failed for {source.name}: {resume_error}")
                            time.sleep(min(2 ** attempt, 16))
                if offset > size:
                    fail(f"Storage returned an invalid upload offset for {source.name}")
                if not quiet:
                    print(f"  {offset * 100 // size}%")
        if offset != size:
            fail(f"Storage upload did not complete for {source.name}")


def validate_publish_copy(
    course: dict[str, Any],
    sections: list[dict[str, Any]],
    lessons: list[dict[str, Any]],
    existing_course: dict[str, Any] | None = None,
    existing_sections: dict[str, dict[str, Any]] | None = None,
    existing_lessons: dict[str, dict[str, Any]] | None = None,
) -> None:
    """Match the database's bilingual publication gate before uploading videos."""
    existing_course = existing_course or {}
    existing_sections = existing_sections or {}
    existing_lessons = existing_lessons or {}

    def effective(incoming: dict[str, Any], existing: dict[str, Any], key: str) -> str | None:
        value = incoming.get(key)
        return value if value is not None else existing.get(key)

    def require(value: str | None, label: str) -> None:
        if not isinstance(value, str) or not value.strip():
            fail(f"publishing requires {label}")

    def has_text(value: str | None) -> bool:
        return isinstance(value, str) and bool(value.strip())

    for key in ("title", "subtitle", "description", "title_ru", "subtitle_ru", "description_ru"):
        require(effective(course, existing_course, key), f"course.{key}")
    for key in ("category", "instructor_title", "instructor_bio"):
        if has_text(effective(course, existing_course, key)):
            require(effective(course, existing_course, f"{key}_ru"), f"course.{key}_ru")

    for section in sections:
        previous = existing_sections.get(section["id"], {})
        require(effective(section, previous, "title_ru"), f"section {section['id']}.title_ru")
        if has_text(effective(section, previous, "description")):
            require(effective(section, previous, "description_ru"), f"section {section['id']}.description_ru")

    for lesson in lessons:
        previous = existing_lessons.get(lesson["id"], {})
        require(effective(lesson, previous, "title_ru"), f"lesson {lesson['id']}.title_ru")
        if has_text(effective(lesson, previous, "description")):
            require(effective(lesson, previous, "description_ru"), f"lesson {lesson['id']}.description_ru")


def run(args: argparse.Namespace) -> None:
    manifest_path = Path(args.manifest).expanduser().resolve()
    course, sections, lessons = read_manifest(manifest_path)
    total_bytes = sum(lesson["_video_file"].stat().st_size for lesson in lessons)
    print(f"Course: {course['title']} ({course['store_product_id']})")
    print(f"Sections: {len(sections)} · lessons/videos: {len(lessons)} · total: {total_bytes / (1024 * 1024):.1f} MiB")
    if course.get("cover_path"):
        print(f"Cover: {course['cover_path']} ({course['_cover_file'].stat().st_size / 1_000_000:.1f} MB)")
    if args.dry_run:
        if args.publish:
            validate_publish_copy(course, sections, lessons)
        for lesson in lessons:
            print(f"  {lesson['id']} → course-videos/{lesson['video_path']}")
        if course.get("cover_path"):
            print(f"  cover → {COVER_BUCKET}/{course['cover_path']}")
        print("Dry run only; no files or catalog records were changed.")
        return

    admin = SupabaseAdmin()
    query = urlencode({
        "select": "id,store_product_id,is_published,title_ru,subtitle_ru,description_ru,category,category_ru,instructor_title,instructor_title_ru,instructor_bio,instructor_bio_ru",
        "store_product_id": f"eq.{course['store_product_id']}",
    })
    current = admin.rest("GET", f"courses?{query}") or []
    if current:
        if current[0]["id"] != course["id"]:
            fail("course.id does not match the existing record for this store_product_id")
        if current[0]["is_published"] and not args.publish:
            fail("this course is already published; pass --publish to stage changes and republish it explicitly")

    section_query = urlencode({"select": "id,sort_order,title_ru,description_ru", "course_id": f"eq.{course['id']}"})
    current_sections = admin.rest("GET", f"course_sections?{section_query}") or []
    section_id_set = {section["id"] for section in sections}
    sections_by_id = {section["id"]: section for section in sections}
    current_sections_by_order = {section["sort_order"]: section["id"] for section in current_sections}
    for section in sections:
        prior = next((row for row in current_sections if row["id"] == section["id"]), None)
        if prior and prior["sort_order"] != section["sort_order"]:
            fail(f"section order changes are not supported by this importer: {section['id']}")
        order_owner = current_sections_by_order.get(section["sort_order"])
        if order_owner and order_owner != section["id"]:
            fail(f"section sort_order {section['sort_order']} is already used by {order_owner}")
    if current_sections and section_id_set:
        ids_filter = "in.(" + ",".join(section["id"] for section in current_sections) + ")"
        lesson_query = urlencode({"select": "id,section_id,sort_order,video_path,title_ru,description_ru", "section_id": ids_filter})
        current_lessons = admin.rest("GET", f"lessons?{lesson_query}") or []
    else:
        current_lessons = []
    current_lessons_by_id = {lesson["id"]: lesson for lesson in current_lessons}
    current_lesson_orders = {(lesson["section_id"], lesson["sort_order"]): lesson["id"] for lesson in current_lessons}
    for lesson in lessons:
        prior = current_lessons_by_id.get(lesson["id"])
        if prior and (prior["section_id"] != lesson["section_id"] or prior["sort_order"] != lesson["sort_order"]):
            fail(f"moving or reordering an existing lesson is not supported by this importer: {lesson['id']}")
        order_owner = current_lesson_orders.get((lesson["section_id"], lesson["sort_order"]))
        if order_owner and order_owner != lesson["id"]:
            fail(f"lesson sort_order {lesson['sort_order']} is already used by {order_owner}")
    if args.publish:
        validate_publish_copy(
            course, sections, lessons,
            existing_course=current[0] if current else None,
            existing_sections={row["id"]: row for row in current_sections},
            existing_lessons=current_lessons_by_id,
        )
        missing_sections = {section["id"] for section in current_sections} - section_id_set
        manifest_lesson_ids = {lesson["id"] for lesson in lessons}
        missing_lessons = {lesson["id"] for lesson in current_lessons} - manifest_lesson_ids
        if missing_sections or missing_lessons:
            fail(
                "publishing requires a complete manifest for the existing course; "
                f"missing sections={sorted(missing_sections)}, lessons={sorted(missing_lessons)}"
            )

    for lesson in lessons:
        admin.upload_video(lesson, quiet=args.quiet)

    admin.upload_cover(course)
    course = {key: value for key, value in course.items() if not key.startswith("_")}
    public_lessons = [{key: value for key, value in lesson.items() if not key.startswith("_")} for lesson in lessons]
    result = admin.rest("POST", "rpc/import_course_bundle", {
        "p_course": course,
        "p_sections": sections,
        "p_lessons": public_lessons,
        "p_publish": bool(args.publish),
    })
    if (
        not isinstance(result, dict)
        or result.get("course_id") != course["id"]
        or result.get("is_published") is not bool(args.publish)
        or result.get("sections_applied") != len(sections)
        or result.get("lessons_applied") != len(public_lessons)
    ):
        fail("Supabase did not confirm that the complete course catalog was applied")

    if args.publish:
        print("Course content imported and publication requested. Verify its App Store product is available for sale.")
    else:
        print("Course content imported as a draft. It remains hidden from learners.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", help="path to the course-package JSON manifest")
    parser.add_argument("--dry-run", action="store_true", help="validate all files and print object paths without contacting Supabase")
    parser.add_argument("--publish", action="store_true", help="explicitly publish after the full course has been uploaded")
    parser.add_argument("--quiet", action="store_true", help="hide per-chunk upload progress")
    args = parser.parse_args()
    try:
        run(args)
    except ImportFailure as error:
        print(f"Import failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
