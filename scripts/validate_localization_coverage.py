#!/usr/bin/env python3
"""Check that Kazakh UI literals have Russian translations."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Massage app"
RUSSIAN_STRINGS = SOURCE / "ru.lproj" / "Localizable.strings"
KAZAKH_LETTERS = re.compile(r"[ӘәІіҢңҒғҮүҰұҚқӨөҺһ]")
STRING_ENTRY = re.compile(r'^"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;', re.M)
SWIFT_LITERAL = re.compile(r'"((?:\\.|[^"\\])*)"')

# SwiftUI interpolated strings lower to printf-style localization keys.
INTERPOLATED_KEYS = {
    "Жаңа кодты %lld секундтан кейін сұрауға болады.",
    "Оқуды жалғастыру (%lld)",
    "Сәлем, %@ 👋",
    "%lld/%lld сабақ",
    "%lld сабақ",
    "Кіріспе сабақ №%lld",
    "%lld бөлім · %lld сабақ",
    "Каталогтағы орны: %lld",
    "Реті: %lld",
    "Ұзақтығы: %lld сек",
    "%@, бөлім %lld",
}


def main() -> int:
    entries = STRING_ENTRY.findall(RUSSIAN_STRINGS.read_text(encoding="utf-8"))
    translations = dict(entries)
    duplicate_keys = sorted(key for key in translations if sum(k == key for k, _ in entries) > 1)
    missing = set()

    for source_file in SOURCE.glob("*.swift"):
        content = source_file.read_text(encoding="utf-8")
        for match in SWIFT_LITERAL.finditer(content):
            key = match.group(1)
            if not KAZAKH_LETTERS.search(key):
                continue
            # Interpolated phrases are checked as normalized format keys below.
            if r"\(" in key:
                continue
            if key not in translations:
                missing.add(key)

    missing_interpolated = sorted(key for key in INTERPOLATED_KEYS if key not in translations)
    if duplicate_keys:
        print("Duplicate Russian localization keys:")
        print("\n".join(f"  {key}" for key in duplicate_keys))
    if missing:
        print("Kazakh UI strings missing Russian translations:")
        print("\n".join(f"  {key}" for key in sorted(missing)))
    if missing_interpolated:
        print("Interpolated UI strings missing Russian translations:")
        print("\n".join(f"  {key}" for key in missing_interpolated))
    if duplicate_keys or missing or missing_interpolated:
        return 1

    print(f"Russian localization coverage OK ({len(translations)} keys).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
