"""Repackage the owner's ORIGINAL FlareStorePlus 1.5.0 b59 as refresh-status preview b62.

No proprietary IPA bytes, user data, certificates or provisioning files belong in GitHub.
Output must be fully re-signed, including the embedded runtime dylib.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import struct
import zipfile
from pathlib import Path

SOURCE_SHA256 = "d5d5f44fd7677c418c887067f48fd54444d510e62970134c4e3baaa0a31f9cf8"
APP = "Payload/FlareStore iOS.app/"
PLIST = APP + "Info.plist"
EXEC = APP + "FlareStore iOS"
RUNTIME = APP + "Frameworks/FlareStorePlusRuntime.dylib"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def build(source: Path, dylib: Path, dest: Path) -> dict:
    original = source.read_bytes()
    if sha(original) != SOURCE_SHA256:
        raise ValueError("Use the exact verified original b61 IPA; unknown variants are rejected")
    lib = dylib.read_bytes()
    if len(lib) < 4000:
        raise ValueError("Missing or too-small runtime")
    magic, cpu, _subtype, filetype = struct.unpack_from("<IIII", lib)
    if (magic, cpu, filetype) != (0xfeedfacf, 0x0100000c, 6):
        raise ValueError("Expected 64-bit arm64 Mach-O dynamic library")
    with zipfile.ZipFile(source) as old:
        if old.testzip() is not None:
            raise ValueError("Original ZIP CRC validation failed")
        names = old.namelist()
        if RUNTIME not in names or PLIST not in names or EXEC not in names:
            raise ValueError("Original b61 package incomplete")
        info = plistlib.loads(old.read(PLIST))
        if info.get("CFBundleIdentifier") != "com.Flare.FlareStore-iOS" or str(info.get("CFBundleVersion")) != "61":
            raise ValueError("Wrong original app identity/version")
        info["CFBundleVersion"] = "62"
        rewritten_plist = plistlib.dumps(info, fmt=plistlib.FMT_BINARY)
        dest.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(dest, "w") as new:
            for item in old.infolist():
                if item.filename.startswith("/") or ".." in item.filename.split("/"):
                    raise ValueError("Unsafe input path")
                payload = old.read(item.filename)
                if item.filename == PLIST:
                    payload = rewritten_plist
                elif item.filename == RUNTIME:
                    payload = lib
                new.writestr(item, payload)
            new.writestr("PatchSource/patch_manifest_b62.json", json.dumps({
                "bundle": "com.Flare.FlareStore-iOS", "version": "1.5.0", "build": "62",
                "feature": "Library-only cache timestamp and background task run readout; no Repositories label",
                "preserved": ["original executable", "original refresh scheduler", "per-app auto-update settings",
                              "signing certificate preferences", "install ledger"],
                "limitations": ["iOS schedules tasks opportunistically", "UI requires device verification",
                                "requires re-signing of all code", "does not fix false Update badge"]
            }, indent=2))
        old_exec = old.read(EXEC)
    with zipfile.ZipFile(dest) as final:
        if final.testzip() is not None:
            raise ValueError("Output ZIP CRC validation failed")
        actual = plistlib.loads(final.read(PLIST))
        assert actual["CFBundleIdentifier"] == "com.Flare.FlareStore-iOS"
        assert actual["CFBundleVersion"] == "62"
        assert final.read(RUNTIME) == lib
        assert final.read(EXEC) == old_exec
    return {"output": str(dest), "sha256": sha(dest.read_bytes()), "size": dest.stat().st_size}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--dylib", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    print(json.dumps(build(arguments.input, arguments.dylib, arguments.output), indent=2))
