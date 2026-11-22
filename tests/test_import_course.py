"""Unit tests for local course manifest validation (no Supabase credentials/network)."""

from __future__ import annotations

import importlib.util
from io import BytesIO
import json
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("import_course", ROOT / "scripts" / "import_course.py")
assert SPEC and SPEC.loader
import_course = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(import_course)


class ImportCourseManifestTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "lesson.mp4").write_bytes(b"course-video")
        self.manifest = {
            "course": {
                "id": "com.example.course",
                "store_product_id": "com.example.course",
                "title": "Курс",
                "title_ru": "Курс на русском",
                "subtitle_ru": "Кратко",
                "description_ru": "Описание курса",
                "category": "Емдік массаж",
                "category_ru": "Лечебный массаж",
                "instructor_name": "Жанар Иманбаева",
                "instructor_title": "Массаж маманы",
                "instructor_title_ru": "Специалист по массажу",
                "instructor_bio": "Оқытушы туралы қысқаша ақпарат",
                "instructor_bio_ru": "Краткая информация о преподавателе",
                "sort_order": 1,
                "sections": [{
                    "id": "section-1",
                    "title": "Раздел",
                    "title_ru": "Раздел по-русски",
                    "description_ru": "Описание раздела",
                    "sort_order": 1,
                    "lessons": [{
                        "id": "lesson-1",
                        "title": "Урок",
                        "title_ru": "Урок по-русски",
                        "description_ru": "Описание урока",
                        "video_file": "lesson.mp4",
                        "sort_order": 1,
                    }],
                }],
            }
        }

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write_manifest(self) -> Path:
        path = self.root / "course.json"
        path.write_text(json.dumps(self.manifest), encoding="utf-8")
        return path

    def test_valid_manifest_builds_content_hashed_storage_path(self) -> None:
        course, sections, lessons = import_course.read_manifest(self.write_manifest())
        self.assertEqual(course["id"], course["store_product_id"])
        self.assertEqual(sections[0]["course_id"], course["id"])
        self.assertEqual(course["title_ru"], "Курс на русском")
        self.assertEqual(course["category"], "Емдік массаж")
        self.assertEqual(course["category_ru"], "Лечебный массаж")
        self.assertEqual(course["instructor_name"], "Жанар Иманбаева")
        self.assertEqual(course["instructor_title_ru"], "Специалист по массажу")
        self.assertEqual(course["instructor_bio_ru"], "Краткая информация о преподавателе")
        self.assertEqual(sections[0]["title_ru"], "Раздел по-русски")
        self.assertEqual(lessons[0]["title_ru"], "Урок по-русски")
        self.assertRegex(lessons[0]["video_path"], r"^com\.example\.course/lesson-1-[0-9a-f]{64}\.mp4$")

    def test_publish_gate_rejects_missing_russian_copy_before_upload(self) -> None:
        self.manifest["course"]["subtitle"] = "Қысқаша"
        self.manifest["course"]["description"] = "Толық сипаттама"
        self.manifest["course"]["sections"][0]["lessons"][0]["title_ru"] = " "
        course, sections, lessons = import_course.read_manifest(self.write_manifest())
        with self.assertRaisesRegex(import_course.ImportFailure, r"lesson lesson-1\.title_ru"):
            import_course.validate_publish_copy(course, sections, lessons)

    def test_publish_gate_uses_preserved_existing_translations(self) -> None:
        self.manifest["course"]["subtitle"] = "Қысқаша"
        self.manifest["course"]["description"] = "Толық сипаттама"
        self.manifest["course"].pop("title_ru")
        self.manifest["course"]["sections"][0].pop("title_ru")
        self.manifest["course"]["sections"][0]["lessons"][0].pop("title_ru")
        course, sections, lessons = import_course.read_manifest(self.write_manifest())
        import_course.validate_publish_copy(
            course, sections, lessons,
            existing_course={"title_ru": "Курс на русском"},
            existing_sections={"section-1": {"title_ru": "Раздел на русском"}},
            existing_lessons={"lesson-1": {"title_ru": "Урок на русском"}},
        )

    def test_course_id_must_match_store_product_id(self) -> None:
        self.manifest["course"]["id"] = "other-course"
        with self.assertRaisesRegex(import_course.ImportFailure, "must match"):
            import_course.read_manifest(self.write_manifest())

    def test_instructor_fields_are_optional_and_blank_values_become_none(self) -> None:
        self.manifest["course"].pop("instructor_name")
        self.manifest["course"]["instructor_bio_ru"] = "  "
        course, _, _ = import_course.read_manifest(self.write_manifest())
        self.assertIsNone(course["instructor_name"])
        self.assertIsNone(course["instructor_bio_ru"])

    def test_instructor_metadata_must_be_text(self) -> None:
        self.manifest["course"]["instructor_name"] = ["not", "text"]
        with self.assertRaisesRegex(import_course.ImportFailure, "course.instructor_name must be a string"):
            import_course.read_manifest(self.write_manifest())

    def test_optional_categories_preserve_existing_values_on_import(self) -> None:
        self.manifest["course"].pop("category")
        self.manifest["course"]["category_ru"] = "  "
        course, _, _ = import_course.read_manifest(self.write_manifest())
        self.assertIsNone(course["category"])
        self.assertIsNone(course["category_ru"])

    def test_category_metadata_must_be_text(self) -> None:
        self.manifest["course"]["category_ru"] = ["invalid"]
        with self.assertRaisesRegex(import_course.ImportFailure, "course.category_ru must be a string"):
            import_course.read_manifest(self.write_manifest())

    def test_duplicate_section_ids_are_rejected(self) -> None:
        self.manifest["course"]["sections"].append(self.manifest["course"]["sections"][0].copy())
        with self.assertRaisesRegex(import_course.ImportFailure, "duplicate section id"):
            import_course.read_manifest(self.write_manifest())

    def test_video_paths_cannot_escape_package_directory(self) -> None:
        self.manifest["course"]["sections"][0]["lessons"][0]["video_file"] = "../outside.mp4"
        with self.assertRaisesRegex(import_course.ImportFailure, "must stay inside"):
            import_course.read_manifest(self.write_manifest())

    def test_video_symlink_cannot_escape_package_directory(self) -> None:
        outside = self.root.parent / f"{self.root.name}-outside.mp4"
        outside.write_bytes(b"outside-video")
        try:
            (self.root / "linked.mp4").symlink_to(outside)
            self.manifest["course"]["sections"][0]["lessons"][0]["video_file"] = "linked.mp4"
            with self.assertRaisesRegex(import_course.ImportFailure, "must stay inside"):
                import_course.read_manifest(self.write_manifest())
        finally:
            outside.unlink(missing_ok=True)

    def test_missing_video_is_rejected(self) -> None:
        self.manifest["course"]["sections"][0]["lessons"][0]["video_file"] = "missing.mp4"
        with self.assertRaisesRegex(import_course.ImportFailure, "does not exist"):
            import_course.read_manifest(self.write_manifest())

    def test_duplicate_lesson_sort_order_is_rejected(self) -> None:
        section = self.manifest["course"]["sections"][0]
        section["lessons"].append({
            **section["lessons"][0],
            "id": "lesson-2",
        })
        with self.assertRaisesRegex(import_course.ImportFailure, "duplicate lesson sort_order"):
            import_course.read_manifest(self.write_manifest())

    def test_upload_refuses_external_resumable_url_before_sending_credentials(self) -> None:
        admin = object.__new__(import_course.SupabaseAdmin)
        admin.storage_url = "https://project.storage.supabase.co"
        admin.api_key = "test-publishable-key"
        admin.service_role_jwt = "test-service-role-key"
        lesson = {
            "_video_file": self.root / "lesson.mp4",
            "_content_type": "video/mp4",
            "video_path": "com.example.course/lesson.mp4",
        }
        with patch.object(admin, "request", return_value=(
            201,
            {"Location": "https://attacker.example/upload/123", "Upload-Offset": "0"},
            None,
        )) as request:
            with self.assertRaisesRegex(import_course.ImportFailure, "unexpected host"):
                admin._upload_video_snapshot(lesson, quiet=True)
        request.assert_called_once()

    def test_resumable_upload_continues_from_server_offset_after_timeout(self) -> None:
        admin = object.__new__(import_course.SupabaseAdmin)
        admin.storage_url = "https://project.storage.supabase.co"
        admin.api_key = "test-publishable-key"
        admin.service_role_jwt = "test-service-role-key"
        lesson = {
            "_video_file": self.root / "lesson.mp4",
            "_content_type": "video/mp4",
            "video_path": "com.example.course/lesson.mp4",
        }
        (self.root / "lesson.mp4").write_bytes(b"abcdefghijkl")
        calls = []

        class Response:
            def __init__(self, offset: str) -> None:
                self.headers = {"Upload-Offset": offset}

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

        def fake_urlopen(request, timeout):
            calls.append(request)
            if request.get_method() == "PATCH" and len(calls) == 1:
                raise URLError("simulated connection reset after partial write")
            if request.get_method() == "HEAD":
                return Response("4")
            if request.get_method() == "PATCH" and len(calls) == 3:
                return Response("8")
            if request.get_method() == "PATCH" and len(calls) == 4:
                return Response("12")
            self.fail(f"unexpected request: {request.get_method()} #{len(calls)}")

        with (
            patch.object(admin, "request", return_value=(
                201,
                {"Location": "https://project.storage.supabase.co/upload/123", "Upload-Offset": "0"},
                None,
            )),
            patch.object(import_course, "open_authenticated", side_effect=fake_urlopen),
            patch.object(import_course, "CHUNK_SIZE", 8),
        ):
            admin._upload_video_snapshot(lesson, quiet=True)

        self.assertEqual([request.get_method() for request in calls], ["PATCH", "HEAD", "PATCH", "PATCH"])
        self.assertEqual([calls[index].data for index in (0, 2, 3)], [b"abcdefgh", b"efgh", b"ijkl"])

    def test_authenticated_http_opener_rejects_all_redirects(self) -> None:
        handler = import_course.RejectRedirectHandler()
        request = Request(
            "https://project.storage.supabase.co/storage/v1/upload/resumable",
            headers={"Authorization": "Bearer test-secret"},
            method="POST",
        )
        self.assertIn(handler.__class__, [type(item) for item in import_course.AUTHENTICATED_OPENER.handlers])
        for status in (301, 302, 303, 307, 308):
            with self.subTest(status=status), self.assertRaises(HTTPError) as context:
                handler.redirect_request(request, BytesIO(), status, "Redirect", {}, "https://attacker.example/collect")
            try:
                self.assertEqual(context.exception.code, status)
            finally:
                context.exception.close()


if __name__ == "__main__":
    unittest.main()
