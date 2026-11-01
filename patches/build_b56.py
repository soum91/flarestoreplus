"""Reproducible, narrowly scoped follow-up to the supplied FlareStore b55 IPA.

This adjusts only the four SwiftUI AppStorage defaults for the existing
"Auto Install When Signed" preference. It does not remove the iOS install
confirmation, fix version-aware Update detection, or add new UI screens.
The resulting IPA must be re-signed with the user's existing certificate.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import struct
import zipfile
from pathlib import Path

import capstone
import lief


SOURCE_SHA256 = "491788ad61ec5989e184e64ab0ca48582754b1fbf117a897e2af4c13f0b0d4f4"
EXECUTABLE = "Payload/FlareStore iOS.app/FlareStore iOS"
PLIST = "Payload/FlareStore iOS.app/Info.plist"
BASE = 0x100000000

# Four compiler-generated AppStorage initializers reference the same
# `autoInstallWhenSigned` field. Change their fallback value from false to true.
# An explicitly saved user preference still takes priority.
DEFAULT_INSTRUCTIONS = [0x5FDD8C, 0xA85D50, 0xB1BD74, 0xB46604]
OLD_OPCODE = 0x52800000  # mov w0, #0
NEW_OPCODE = 0x52800020  # mov w0, #1


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def patch_executable(original: bytes) -> tuple[bytes, list[dict[str, str]]]:
    macho = lief.MachO.parse(list(original)).at(0)
    assert macho.get_segment("__FSPATCH") is not None, "Expected b55 refresh/sort hooks"
    result = bytearray(original)
    records: list[dict[str, str]] = []
    decoder = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)
    for relative_address in DEFAULT_INSTRUCTIONS:
        address = BASE + relative_address
        offset = macho.virtual_address_to_offset(address)
        old = struct.unpack_from("<I", result, offset)[0]
        assert old == OLD_OPCODE, f"Unexpected instructions at {address:#x}: {old:#x}"
        struct.pack_into("<I", result, offset, NEW_OPCODE)
        decoded = list(decoder.disasm(result[offset : offset + 4], address))
        assert len(decoded) == 1 and decoded[0].mnemonic == "mov"
        assert decoded[0].op_str == "w0, #1"
        records.append({"address": hex(address), "before": hex(old), "after": hex(NEW_OPCODE)})
    for index, (old, new) in enumerate(zip(original, result)):
        if old != new:
            assert index in {
                macho.virtual_address_to_offset(BASE + address) for address in DEFAULT_INSTRUCTIONS
            }, f"Unexpected Mach-O byte modification at {index:#x}"
    assert len(result) == len(original)
    return bytes(result), records


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True, help="Lawfully supplied b55 IPA")
    parser.add_argument("--output", type=Path, required=True, help="Patched IPA (not pre-signed)")
    args = parser.parse_args()
    source_path, output_path = args.input, args.output
    assert sha256(source_path.read_bytes()) == SOURCE_SHA256, "Wrong b55 source IPA"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(source_path, "r") as source:
        assert source.testzip() is None
        for name in source.namelist():
            parts = name.replace("\\", "/").split("/")
            assert not name.startswith("/") and ".." not in parts, "Unsafe input archive path"
        executable, patches = patch_executable(source.read(EXECUTABLE))
        with zipfile.ZipFile(output_path, "w") as destination:
            for member in source.infolist():
                data = source.read(member.filename)
                if member.filename == EXECUTABLE:
                    data = executable
                elif member.filename == PLIST:
                    info = plistlib.loads(data)
                    assert info["CFBundleVersion"] == "55"
                    info["CFBundleVersion"] = "56"
                    data = plistlib.dumps(info, fmt=plistlib.FMT_BINARY)
                destination.writestr(member, data)
            manifest = {
                "input_sha256": SOURCE_SHA256,
                "version": "1.5.0 (56)",
                "patches": patches,
                "scope": "Default Auto Install When Signed to on, retaining b55 refresh/sort hooks",
                "limitations": [
                    "Not tested on a physical iPhone",
                    "A saved disabled preference is not overridden",
                    "iOS OTA installation confirmation still required",
                    "Installed version/update listings and Zeus-style details not fixed",
                    "Executable must be re-signed before installation",
                ],
            }
            destination.writestr("PatchSource/patch_manifest_b56.json", json.dumps(manifest, indent=2))
    with zipfile.ZipFile(output_path, "r") as rebuilt:
        assert rebuilt.testzip() is None
        assert plistlib.loads(rebuilt.read(PLIST))["CFBundleVersion"] == "56"
        assert rebuilt.read(EXECUTABLE) == executable
    print(json.dumps({"output": str(output_path), "sha256": sha256(output_path.read_bytes()), "patches": patches}, indent=2))


if __name__ == "__main__":
    main()
