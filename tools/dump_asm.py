"""Read-only disassembly around exact virtual addresses of a supplied IPA."""

import argparse
import bisect
import zipfile

import capstone
import lief


BASE = 0x100000000
APP = "Payload/FlareStore iOS.app/FlareStore iOS"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa")
    parser.add_argument("address", type=lambda s: int(s, 0))
    parser.add_argument("--before", type=int, default=100)
    parser.add_argument("--after", type=int, default=180)
    args = parser.parse_args()
    with zipfile.ZipFile(args.ipa) as z:
        raw = z.read(APP)
    binary = lief.MachO.parse(list(raw)).at(0)
    starts = binary.function_starts.functions
    index = bisect.bisect_right(starts, args.address - BASE) - 1
    begin = BASE + starts[index]
    end = BASE + starts[index + 1]
    print(f"function {begin:#x}..{end:#x} size {end-begin:#x}")
    start = max(begin, args.address - args.before * 4) & ~3
    stop = min(end, args.address + args.after * 4) & ~3
    off = binary.virtual_address_to_offset(start)
    decoder = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)
    for ins in decoder.disasm(raw[off : off + (stop - start)], start):
        print(f"{'>' if ins.address == args.address else ' '} {ins.address:#x} {ins.mnemonic:7} {ins.op_str}")


if __name__ == "__main__":
    main()
