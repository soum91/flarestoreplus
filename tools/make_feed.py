"""Create a version-correct AltStore/FlareStore JSON feed for an already hosted IPA.

The download URL must serve the actual IPA without a browser session or
authorization headers. A private GitHub release URL does not qualify.
"""

from __future__ import annotations

import argparse
import json
import plistlib
import zipfile
from pathlib import Path
from urllib.parse import urlparse


INFO = "Payload/FlareStore iOS.app/Info.plist"


def validate_download_url(raw: str) -> str:
    parsed = urlparse(raw)
    if parsed.scheme != "https" or not parsed.hostname or not parsed.path.lower().endswith(".ipa"):
        raise ValueError("A direct HTTPS URL ending in .ipa is required")
    if parsed.username or parsed.password or parsed.fragment:
        raise ValueError("Do not embed credentials or fragments in the IPA URL")
    if parsed.hostname in {"example.com", "example.org", "example.net", "localhost"}:
        raise ValueError("Placeholder and localhost URLs cannot publish an installable IPA")
    return raw


def make_feed(info: dict, ipa_size: int, url: str, date: str) -> dict:
    url = validate_download_url(url)
    if info.get("CFBundleVersion") != "57":
        raise ValueError("This preview feed must point to FlareStorePlus build 57")
    if info.get("CFBundleIdentifier") != "com.Flare.FlareStore-iOS":
        raise ValueError("Bundle identifier mismatch")
    return {
        "name": "FlareStorePlus Private Preview",
        "subtitle": "Unlisted testing feed",
        "description": "Unofficial, experimental patch preview. Critical direct-install and Update-status fixes are not yet included.",
        "tintColor": "#A848DD",
        "apps": [
            {
                "name": "FlareStorePlus (preview)",
                "bundleIdentifier": info["CFBundleIdentifier"],
                "developerName": "Independent test build",
                "subtitle": "Test build, requires re-signing",
                "localizedDescription": "b55 repository sort/refresh experiments; b56 auto-install-prompt default; b57 display name. Not an official FlareStore release.",
                "iconURL": "https://github.com/soum91.png",
                "tintColor": "#A848DD",
                "category": "utilities",
                "versions": [
                    {
                        "version": info["CFBundleShortVersionString"],
                        "buildVersion": info["CFBundleVersion"],
                        "date": date,
                        "localizedDescription": "Preview only. Does not fix direct installation or false Update labels.",
                        "downloadURL": url,
                        "size": ipa_size,
                        "minOSVersion": info.get("MinimumOSVersion", "16.0"),
                    }
                ],
            }
        ],
        "news": [],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", required=True, type=Path)
    parser.add_argument("--url", required=True)
    parser.add_argument("--date", required=True, help="Release date in YYYY-MM-DD format")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    with zipfile.ZipFile(args.ipa) as ipa:
        if ipa.testzip() is not None:
            raise ValueError("Corrupt IPA archive")
        info = plistlib.loads(ipa.read(INFO))
    feed = make_feed(info, args.ipa.stat().st_size, args.url, args.date)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(feed, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote {args.output} for build {info['CFBundleVersion']}")


if __name__ == "__main__":
    main()
