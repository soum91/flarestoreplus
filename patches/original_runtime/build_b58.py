"""Repackage the ORIGINAL b57 FlareStorePlus with a Library status extension.

Requires the exact user-supplied b57 IPA and a separately cross-compiled arm64
iOS dylib. Preserves the original bundle identifier, signing ledger, and files.
The result must be signed, including its embedded Frameworks dylib, before use.

This does NOT claim to fix the app's existing false Update badge logic.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import tempfile
import zipfile
from pathlib import Path

import lief


EXPECTED_SOURCES = {
    "0a8749444d1b6763124f41cb0e3ad30a807a73366b7ef704d6fdcc42bca24bb6": "b57 unsigned preview",
    "14087556d9109005f940c841bc1b15546b4daefdcde030906fc3384ab1ad4ad9": "user-supplied b57 signed IPA",
}
EXPECTED_ID = "com.Flare.FlareStore-iOS"
MAIN_EXECUTABLE = "Payload/FlareStore iOS.app/FlareStore iOS"
MAIN_PLIST = "Payload/FlareStore iOS.app/Info.plist"
LIBRARY = "Payload/FlareStore iOS.app/Frameworks/FlareStorePlusRuntime.dylib"
DEPENDENCY = "@executable_path/Frameworks/FlareStorePlusRuntime.dylib"

# Hooks already installed by the original b55 patch must stay unchanged.
PATCHED_ANCHORS = (0x100B9DBE0, 0x100B946D8, 0x1002B6300, 0x1002B426C, 0x1003D5CF0)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def validate_name(name: str) -> None:
    parts = name.replace("\\", "/").split("/")
    if name.startswith("/") or ".." in parts:
        raise ValueError(f"Unsafe ZIP member: {name!r}")


def patch_executable(original: bytes) -> bytes:
    binary = lief.MachO.parse(list(original)).at(0)
    if binary.get_segment("__FSPATCH") is None:
        raise ValueError("Missing original b55/b56 code hooks")
    if any(lib.name == DEPENDENCY for lib in binary.libraries):
        raise ValueError("Runtime already injected")
    preserved = {
        address: bytes(binary.get_content_from_virtual_address(address, 16))
        for address in PATCHED_ANCHORS
    }
    binary.add_library(DEPENDENCY)
    binary.remove_signature()
    # The program will be signed by the user's own IPA signing tool.
    with tempfile.TemporaryDirectory(prefix="flarestoreplus-b58-") as temp:
        output = Path(temp) / "patched-mach-o"
        binary.write(str(output))
        rebuilt = output.read_bytes()
    verified = lief.MachO.parse(list(rebuilt)).at(0)
    if verified.find_library(DEPENDENCY) is None:
        raise AssertionError("Injected load command missing")
    if verified.get_segment("__FSPATCH") is None:
        raise AssertionError("Original patch hooks were removed")
    for address, value in preserved.items():
        after = bytes(verified.get_content_from_virtual_address(address, len(value)))
        if after != value:
            raise AssertionError(f"Existing patch hook changed at {address:#x}")
    return rebuilt


def build(source: Path, dylib: Path, destination: Path) -> dict:
    original = source.read_bytes()
    source_digest = digest(original)
    if source_digest not in EXPECTED_SOURCES:
        raise ValueError("Use one of the two exact verified b57 FlareStorePlus IPA sources")
    payload = dylib.read_bytes()
    library = lief.MachO.parse(list(payload)).at(0)
    if not library.header.is_64bit or library.header.cpu_type != lief.MachO.Header.CPU_TYPE.ARM64:
        raise ValueError("Expected a 64-bit arm64 iOS dynamic library")
    with zipfile.ZipFile(source) as old:
        if old.testzip() is not None:
            raise ValueError("Original IPA has a bad CRC")
        for name in old.namelist():
            validate_name(name)
        if LIBRARY in old.namelist():
            raise ValueError("Target IPA already has this runtime")
        info = plistlib.loads(old.read(MAIN_PLIST))
        if (info.get("CFBundleVersion"), info.get("CFBundleIdentifier")) != ("57", EXPECTED_ID):
            raise ValueError("Original app identity is not b57")
        updated = dict(info)
        updated["CFBundleVersion"] = "58"
        patched = patch_executable(old.read(MAIN_EXECUTABLE))
        destination.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(destination, "w") as new:
            for item in old.infolist():
                data = old.read(item.filename)
                if item.filename == MAIN_EXECUTABLE:
                    data = patched
                elif item.filename == MAIN_PLIST:
                    data = plistlib.dumps(updated, fmt=plistlib.FMT_BINARY)
                new.writestr(item, data)
            new.writestr(LIBRARY, payload, compress_type=zipfile.ZIP_DEFLATED)
            new.writestr("PatchSource/patch_manifest_b58.json", json.dumps({
                "original_ipa_sha256": source_digest,
                "source": EXPECTED_SOURCES[source_digest],
                "original_bundle_id": EXPECTED_ID,
                "version": "1.5.0",
                "build": "58",
                "feature": "Show original stored background refresh timestamp on Library tab",
                "does_not_change": ["original app signer", "installation ledger", "background task scheduler", "version comparison"],
                "limitations": ["Device UI unverified", "False Update badge not yet fixed", "Original code signature becomes invalid and requires full re-signing"],
            }, indent=2))
    with zipfile.ZipFile(destination) as tested:
        assert tested.testzip() is None
        final = plistlib.loads(tested.read(MAIN_PLIST))
        assert final["CFBundleIdentifier"] == EXPECTED_ID
        assert final["CFBundleVersion"] == "58"
        assert tested.read(LIBRARY) == payload
    return {"source": str(source), "source_type": EXPECTED_SOURCES[source_digest], "output": str(destination), "output_sha256": digest(destination.read_bytes()), "build": 58}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--dylib", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(build(args.input, args.dylib, args.output), indent=2))
