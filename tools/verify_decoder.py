#!/usr/bin/env python3
"""Compare the supported decoder subset with Capstone, strictly as test data."""

import argparse
import json
from pathlib import Path
import random
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))
import capstone
from bindings import ARM64, X64, Core


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("library", type=Path)
    parser.add_argument("--samples", type=int, default=100000)
    arguments = parser.parse_args()
    core = Core(arguments.library.resolve())
    generator = random.Random(0xDEC0DE)
    report = {}
    for architecture, reference_arch, mode in ((X64, capstone.CS_ARCH_X86, capstone.CS_MODE_64),
                                               (ARM64, capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)):
        reference = capstone.Cs(reference_arch, mode)
        accepted = 0
        reserved = 0
        mismatches = []
        for _ in range(arguments.samples):
            data = generator.randbytes(15)
            decoded = core.decode(architecture, data)
            if decoded is None:
                continue
            accepted += 1
            expected = next(reference.disasm_lite(data, 0x100000, count=1), None)
            if expected is None:
                reserved += 1
            elif decoded.size != expected[1]:
                if len(mismatches) < 20:
                    mismatches.append({"bytes": data.hex(), "actual": decoded.size, "expected": expected})
        report[architecture] = {"samples": arguments.samples, "accepted": accepted,
                                "reserved_or_unsupported_by_reference": reserved, "length_mismatches": mismatches}
    print(json.dumps(report, indent=2))
    return int(any(item["length_mismatches"] for item in report.values()))


if __name__ == "__main__":
    raise SystemExit(main())
