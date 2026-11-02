"""Package the b56 patch as a distinctly labelled FlareStorePlus preview.

This is a branding/build-number change only. It retains the existing bundle
identifier so that users who deliberately update the same signed app can keep
their data, provided the signing team is unchanged. It does not fix direct
installation, update detection, or Apple's OS-managed installation prompt.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import zipfile
from pathlib import Path


SOURCE_SHA256 = "ddd97b5dd4814193c0f47ae99b8f274bca275eb70e024d924ad3a09275d9003c"
PLIST = "Payload/FlareStore iOS.app/Info.plist"
EXECUTABLE = "Payload/FlareStore iOS.app/FlareStore iOS"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if sha256(args.input.read_bytes()) != SOURCE_SHA256:
        raise ValueError("Expected exactly the previously verified b56 test IPA")
    with zipfile.ZipFile(args.input) as source:
        if source.testzip() is not None:
            raise ValueError("Corrupt source archive")
        names = set(source.namelist())
        if PLIST not in names or EXECUTABLE not in names:
            raise ValueError("Missing FlareStore main app")
        source_executable_sha = sha256(source.read(EXECUTABLE))
        original_plist = plistlib.loads(source.read(PLIST))
        if (original_plist.get("CFBundleVersion"), original_plist.get("CFBundleIdentifier")) != (
            "56", "com.Flare.FlareStore-iOS"
        ):
            raise ValueError("Unexpected source app identity")
        updated_plist = dict(original_plist)
        updated_plist["CFBundleVersion"] = "57"
        updated_plist["CFBundleDisplayName"] = "FlareStorePlus"
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(args.output, "w") as target:
            for member in source.infolist():
                parts = member.filename.replace("\\", "/").split("/")
                if member.filename.startswith("/") or ".." in parts:
                    raise ValueError("Unsafe archive member")
                content = source.read(member.filename)
                if member.filename == PLIST:
                    content = plistlib.dumps(updated_plist, fmt=plistlib.FMT_BINARY)
                target.writestr(member, content)
            manifest = {
                "name": "FlareStorePlus preview",
                "version": "1.5.0",
                "build": "57",
                "input_sha256": SOURCE_SHA256,
                "scope": "Display name and build number only; previous b55/b56 patches retained",
                "limitations": [
                    "Not tested on a physical iPhone",
                    "Update badges and direct install not fixed",
                    "iOS OTA installation prompt remains",
                    "Must be re-signed before installation",
                    "Not original publisher source or official FlareStore release",
                ],
            }
            target.writestr("PatchSource/patch_manifest_b57.json", json.dumps(manifest, indent=2))
    with zipfile.ZipFile(args.output) as result:
        if result.testzip() is not None:
            raise AssertionError("Built archive fails CRC validation")
        after = plistlib.loads(result.read(PLIST))
        assert after["CFBundleVersion"] == "57"
        assert after["CFBundleDisplayName"] == "FlareStorePlus"
        assert after["CFBundleIdentifier"] == original_plist["CFBundleIdentifier"]
        assert sha256(result.read(EXECUTABLE)) == source_executable_sha
    print(json.dumps({"output": str(args.output), "sha256": sha256(args.output.read_bytes())}))


if __name__ == "__main__":
    main()
