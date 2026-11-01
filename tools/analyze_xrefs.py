"""Read-only AArch64 string-reference locator for a user-supplied Mach-O IPA.

Outputs potential functions that materialize given UTF-8 strings using ADRP
and ADD. No application content is written or included in this script.
"""

from __future__ import annotations

import argparse
import bisect
import re
import zipfile

import capstone
import lief


APP = "Payload/FlareStore iOS.app/FlareStore iOS"
BASE = 0x100000000
ADRP = re.compile(r"^(x\d+), #(0x[0-9a-f]+)$")
ADD = re.compile(r"^(x\d+), (x\d+), #(0x[0-9a-f]+)$")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa")
    parser.add_argument("strings", nargs="+")
    args = parser.parse_args()
    with zipfile.ZipFile(args.ipa) as archive:
        raw = archive.read(APP)
    binary = lief.MachO.parse(list(raw)).at(0)
    section = binary.get_section("__text")
    assert section is not None
    sought = {}
    for term in args.strings:
        needle = term.encode() + b"\0"
        pos = raw.find(needle)
        if pos < 0:
            print(f"missing: {term}")
            continue
        while pos >= 0:
            sought[BASE + pos] = term
            print(f"literal {term!r} at {BASE+pos:#x}")
            pos = raw.find(needle, pos + 1)
    target_pages = {addr & ~0xfff for addr in sought}
    decoder = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)
    start = section.virtual_address
    off = binary.virtual_address_to_offset(start)
    code = raw[off : off + section.size]
    function_starts = binary.function_starts.functions
    candidates = []
    page_registers = {}
    for ins in decoder.disasm(code, start):
        if ins.mnemonic == "adrp":
            match = ADRP.fullmatch(ins.op_str)
            if match:
                reg, page = match.group(1), int(match.group(2), 16)
                if page in target_pages:
                    page_registers[reg] = (page, ins.address)
                else:
                    page_registers.pop(reg, None)
        elif ins.mnemonic == "add":
            match = ADD.fullmatch(ins.op_str)
            if match:
                dst, src, imm = match.group(1), match.group(2), int(match.group(3), 16)
                if src in page_registers:
                    page, at = page_registers[src]
                    address = page + imm
                    if address in sought and ins.address - at <= 48:
                        index = bisect.bisect_right(function_starts, ins.address - BASE) - 1
                        candidates.append((sought[address], ins.address, BASE + function_starts[index]))
                page_registers.pop(dst, None)
        if ins.mnemonic in ("ret", "b", "br", "blr"):
            page_registers.clear()
    for term, address, function in candidates:
        print(f"xref {term!r} at {address:#x} function~{function:#x}")


if __name__ == "__main__":
    main()
