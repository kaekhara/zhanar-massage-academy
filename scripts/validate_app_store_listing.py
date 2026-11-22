#!/usr/bin/env python3
"""Check App Store listing copy and required legal links before archiving."""

from __future__ import annotations

import plistlib
import re
import sys
import ipaddress
from pathlib import Path
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1]
LISTING = ROOT / "APP_STORE_LISTING.md"
LOCALES = {"English (U.K.)", "Russian"}


def fail(message: str) -> None:
    raise SystemExit(message)


def main() -> int:
    legal_links_path = ROOT / "Massage app/LegalLinks.plist"
    try:
        legal_links = plistlib.loads(legal_links_path.read_bytes())
    except (OSError, plistlib.InvalidFileException) as error:
        fail(f"cannot read {legal_links_path.relative_to(ROOT)}: {error}")
    invalid_links: list[str] = []
    required_link_keys = {"PrivacyPolicyURL", "SupportURL"}
    for key in ("PrivacyPolicyURL", "SupportURL", "TermsOfUseURL"):
        value = legal_links.get(key)
        if key not in required_link_keys and (not isinstance(value, str) or not value.strip()):
            continue
        try:
            parsed = urlsplit(value) if isinstance(value, str) else None
            hostname = parsed.hostname.lower().rstrip(".") if parsed and parsed.hostname else ""
            port = parsed.port if parsed else None
            is_ip_address = bool(hostname and _is_ip_address(hostname))
        except ValueError:
            hostname = ""
            is_ip_address = True
            port = None
            parsed = None
        placeholder_suffixes = (".example", ".invalid", ".test", ".localhost", ".local")
        placeholder_domains = (
            "example.com", "example.org", "example.net",
            "yourdomain.com", "your-domain.com", "domain.com", "website.com",
        )
        if (
            not parsed
            or parsed.scheme.lower() != "https"
            or not hostname
            or "." not in hostname
            or is_ip_address
            or hostname.endswith(placeholder_suffixes)
            or any(hostname == domain or hostname.endswith(f".{domain}") for domain in placeholder_domains)
            or any(character.isspace() for character in value)
            or parsed.username is not None
            or parsed.password is not None
            or (port is not None and not 1 <= port <= 65535)
        ):
            invalid_links.append(key)
    text = LISTING.read_text(encoding="utf-8")
    sections = re.split(r"^## (English \(U\.K\.\)|Russian)\s*$", text, flags=re.MULTILINE)
    localized: dict[str, str] = {
        sections[index]: sections[index + 1]
        for index in range(1, len(sections) - 1, 2)
    }
    if set(localized) != LOCALES:
        fail(f"expected English (U.K.) and Russian listing sections, found {sorted(localized)}")

    for locale, body in localized.items():
        fields: dict[str, str] = {}
        for key in ("Name", "Subtitle", "Promotional text", "Keywords"):
            match = re.search(rf"^- \*\*{re.escape(key)}:\*\*\s*(.+?)\s*$", body, re.MULTILINE)
            if not match:
                fail(f"{locale}: missing {key}")
            fields[key] = match.group(1)

        description_match = re.search(
            r"^- \*\*Description:\*\*\s*\n(.*?)\n- \*\*Keywords:\*\*",
            body,
            re.MULTILINE | re.DOTALL,
        )
        if not description_match:
            fail(f"{locale}: missing Description")
        fields["Description"] = description_match.group(1).strip()

        limits = {
            "Name": 30,
            "Subtitle": 30,
            "Promotional text": 170,
            "Description": 4000,
        }
        for key, limit in limits.items():
            length = len(fields[key])
            if key == "Name" and length < 2:
                fail(f"{locale}: {key} must contain at least 2 characters")
            if length > limit:
                fail(f"{locale}: {key} is {length} characters; maximum is {limit}")

        keyword_bytes = len(fields["Keywords"].encode("utf-8"))
        if keyword_bytes > 100:
            fail(f"{locale}: Keywords use {keyword_bytes} UTF-8 bytes; maximum is 100")

        print(
            f"{locale}: name {len(fields['Name'])}/30, subtitle {len(fields['Subtitle'])}/30, "
            f"promotion {len(fields['Promotional text'])}/170, description {len(fields['Description'])}/4000, "
            f"keywords {keyword_bytes}/100 bytes"
        )

    if invalid_links:
        details = "\n".join(
            f"Massage app/LegalLinks.plist must contain a public-looking, non-placeholder HTTPS {key}"
            for key in invalid_links
        )
        fail(details)

    return 0


def _is_ip_address(hostname: str) -> bool:
    try:
        ipaddress.ip_address(hostname)
        return True
    except ValueError:
        return False


if __name__ == "__main__":
    sys.exit(main())
