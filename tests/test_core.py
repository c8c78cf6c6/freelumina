"""Adversarial fixtures: the committee has finally supplied a negative case."""

import ctypes as ct
import random
import struct
import sys
import unittest

from bindings import ARM64, SYSV, WINDOWS, X64, Core, Region, Result


CORE = Core(sys.argv.pop(1))
CODE_ADDRESS = 0x100000
DATA_ADDRESS = 0x200000
TARGET_ADDRESS = CODE_ADDRESS + 0x100
LICENSE_ADDRESS = CODE_ADDRESS + 0x180


def word(value):
    return struct.pack("<I", value & 0xFFFFFFFF)


def relative_call(address, target):
    return b"\xe8" + struct.pack("<i", target - address - 5)


def arm_branch(address, target, link=False):
    return word((0x94000000 if link else 0x14000000) | (((target - address) // 4) & 0x3FFFFFF))


def fixture(arch, abi, *, clobber=False, ambiguous=False, indirect=False):
    """Construct code with an argument trail and an independent license edge."""
    filler = b"\xcc" if arch == X64 else word(0)
    code = bytearray(filler * (0x200 // len(filler)))
    if arch == X64:
        argument = 1 if abi == WINDOWS else 7
        trail = b"\x48\x8d" + bytes([5 | (argument << 3)])
        trail += struct.pack("<i", DATA_ADDRESS - CODE_ADDRESS - 7)
        if clobber:
            trail += b"\x31\xc9" if abi == WINDOWS else b"\x31\xff"
        if indirect:
            trail += b"\xff\x15" + struct.pack("<i", DATA_ADDRESS + 16 - (CODE_ADDRESS + len(trail) + 6))
        else:
            trail += relative_call(CODE_ADDRESS + len(trail), TARGET_ADDRESS)
        trail += b"\xc3"
        body = b"\x55\x48\x89\xe5" + relative_call(TARGET_ADDRESS + 4, LICENSE_ADDRESS) + b"\x5d\xc3"
        code[0x180:0x181] = b"\xc3"
    else:
        pages = (DATA_ADDRESS >> 12) - (CODE_ADDRESS >> 12)
        trail = word(0x90000000 | ((pages & 3) << 29) | (((pages >> 2) & 0x7FFFF) << 5))
        trail += word(0x91000000)  # ADD x0,x0,#0
        if clobber:
            trail += word(0xD2800000)  # MOV x0,#0
        trail += arm_branch(CODE_ADDRESS + len(trail), TARGET_ADDRESS, link=True)
        trail += word(0xD65F03C0)
        body = word(0xA9BF7BFD) + arm_branch(TARGET_ADDRESS + 4, LICENSE_ADDRESS, link=True) + word(0xD65F03C0)
        code[0x180:0x184] = word(0xD65F03C0)
    code[:len(trail)] = trail
    code[0x100:0x100 + len(body)] = body
    if ambiguous:
        other = TARGET_ADDRESS + 0x40
        if arch == X64:
            second = trail[:7] + relative_call(CODE_ADDRESS + 0x40 + 7, other) + b"\xc3"
            # Re-encode the second LEA at its actual address.
            second = second[:3] + struct.pack("<i", DATA_ADDRESS - (CODE_ADDRESS + 0x40 + 7)) + second[7:]
            second_body = b"\x55\x48\x89\xe5" + relative_call(other + 4, LICENSE_ADDRESS) + b"\xc3"
        else:
            second = trail[:8] + arm_branch(CODE_ADDRESS + 0x40 + 8, other, True) + word(0xD65F03C0)
            second_body = word(0xA9BF7BFD) + arm_branch(other + 4, LICENSE_ADDRESS, True) + word(0xD65F03C0)
        code[0x40:0x40 + len(second)] = second
        code[0x140:0x140 + len(second_body)] = second_body
    data = b"LUMINA\x00\xa5" + b"\x00" * 8 + struct.pack("<Q", TARGET_ADDRESS)
    return [(CODE_ADDRESS, bytes(code), 1), (DATA_ADDRESS, data, 0)]


class DiscoveryTests(unittest.TestCase):
    def test_argument_tracking_in_all_six_configurations(self):
        for arch in (X64, ARM64):
            for platform, abi in (("macOS", SYSV), ("Linux", SYSV), ("Windows", WINDOWS)):
                with self.subTest(arch=arch, platform=platform):
                    found = CORE.analyze(arch, abi, fixture(arch, abi), license_address=LICENSE_ADDRESS)
                    self.assertEqual((found.status, found.target, found.candidates), (2, TARGET_ADDRESS, 1))

    def test_clobbered_argument_is_not_evidence(self):
        for arch in (X64, ARM64):
            for abi in (SYSV, WINDOWS):
                with self.subTest(arch=arch, abi=abi):
                    found = CORE.analyze(arch, abi, fixture(arch, abi, clobber=True), license_address=LICENSE_ADDRESS)
                    self.assertEqual(found.status, 0)
                    self.assertEqual(found.references, 0)

    def test_aslr_does_not_change_argument_evidence(self):
        for arch in (X64, ARM64):
            for abi in (SYSV, WINDOWS):
                for slide in (0x500000, 0x100000000):
                    spans = fixture(arch, abi)
                    shifted = [(address + slide, content, executable) for address, content, executable in spans]
                    data = shifted[1][1]
                    shifted[1] = (shifted[1][0], data[:16] + struct.pack("<Q", TARGET_ADDRESS + slide), 0)
                    found = CORE.analyze(arch, abi, shifted, license_address=LICENSE_ADDRESS + slide)
                    self.assertEqual((found.status, found.target), (2, TARGET_ADDRESS + slide))

    def test_ambiguity_is_rejected(self):
        for arch in (X64, ARM64):
            found = CORE.analyze(arch, SYSV, fixture(arch, SYSV, ambiguous=True), license_address=LICENSE_ADDRESS)
            self.assertEqual((found.status, found.candidates, found.reason), (0, 2, 6))

    def test_missing_independent_anchor_is_rejected(self):
        for arch in (X64, ARM64):
            found = CORE.analyze(arch, SYSV, fixture(arch, SYSV))
            self.assertEqual((found.status, found.reason), (0, 5))

    def test_indirect_call_reads_snapshot_pointer(self):
        for abi in (SYSV, WINDOWS):
            found = CORE.analyze(X64, abi, fixture(X64, abi, indirect=True), license_address=LICENSE_ADDRESS)
            self.assertEqual((found.status, found.target), (2, TARGET_ADDRESS))

    def test_export_requires_executable_snapshot(self):
        spans = [(TARGET_ADDRESS, b"\x55\x48\x89\xe5\xc3", 0)]
        self.assertEqual(CORE.analyze(X64, SYSV, spans, exported=TARGET_ADDRESS).status, 0)

    def test_cyclic_export_thunks_are_rejected(self):
        spans = [(CODE_ADDRESS, b"\xe9\xfb\xff\xff\xff", 1)]
        self.assertEqual(CORE.analyze(X64, SYSV, spans, exported=CODE_ADDRESS).status, 0)

    def test_truncated_inputs_do_not_read_past_snapshot(self):
        for size in range(16):
            for arch in (X64, ARM64):
                spans = [(CODE_ADDRESS, b"\x0f" * size, 1)]
                CORE.analyze(arch, SYSV, spans, exported=CODE_ADDRESS)

    def test_invalid_region_lengths_are_rejected(self):
        region = Region(CODE_ADDRESS, -1, None, 1, 0)
        found = Result()
        CORE.library.fl_analyze(X64, SYSV, ct.byref(region), 1, 0, 0, ct.byref(found))
        self.assertEqual((found.status, found.reason), (0, 1))

    def test_nonterminated_literal_is_rejected(self):
        spans = fixture(X64, SYSV)
        spans[1] = (DATA_ADDRESS, b"LUMINAX" + spans[1][1][7:], 0)
        self.assertEqual(CORE.analyze(X64, SYSV, spans, license_address=LICENSE_ADDRESS).status, 0)


class RelocationTests(unittest.TestCase):
    def test_supported_prologues(self):
        for arch, prefix in ((X64, b"\x55\x48\x89\xe5\x53"), (ARM64, word(0xA9BF7BFD))):
            for abi in (SYSV, WINDOWS):
                success, code, patch = CORE.plan(arch, abi, prefix)
                self.assertEqual(success, 1)
                self.assertGreater(len(code), len(prefix))
                self.assertEqual(len(patch), len(prefix))

    def test_x64_rip_relative_target_is_preserved(self):
        prefix = b"\x48\x8b\x05" + struct.pack("<i", 0x1234)
        success, code, _ = CORE.plan(X64, SYSV, prefix)
        self.assertEqual(success, 1)
        replay_offset = 85
        relocated = code[replay_offset:replay_offset + len(prefix)]
        displacement = struct.unpack_from("<i", relocated, 3)[0]
        self.assertEqual(0x110000 + replay_offset + 7 + displacement, 0x100000 + 7 + 0x1234)

    def test_arm_pc_relative_targets_are_preserved(self):
        for instruction in (0x90000000, 0x10000800, 0x58000801, 0xD8000800):
            with self.subTest(instruction=hex(instruction)):
                success, code, _ = CORE.plan(ARM64, SYSV, word(instruction))
                self.assertEqual(success, 1)
                before = CORE.decode(ARM64, word(instruction), 0x100000)
                after = CORE.decode(ARM64, code[96:100], 0x110000 + 96)
                self.assertEqual(before.target, after.target)

    def test_control_flow_in_stolen_bytes_is_rejected(self):
        for prefix in (b"\xff\xd0" + b"\x90" * 8, b"\xeb\x00" + b"\x90" * 8, b"\xc3" + b"\x90" * 8):
            self.assertEqual(CORE.plan(X64, SYSV, prefix)[0], 0)
        for instruction in (0x14000001, 0x94000001, 0x54000020, 0xB4000020, 0x36000020, 0xD65F03C0):
            self.assertEqual(CORE.plan(ARM64, SYSV, word(instruction))[0], 0)

    def test_out_of_range_branches_are_rejected(self):
        self.assertEqual(CORE.plan(X64, SYSV, b"\x90" * 5, trampoline=0x100000000)[0], 0)
        self.assertEqual(CORE.plan(ARM64, SYSV, word(0xD503201F), trampoline=0x100000000)[0], 0)

    def test_direct_call_relocation_preserves_callee(self):
        prefix = b"\x41\x54\x55\x53" + relative_call(0x100004, 0x101000)
        success, code, patch = CORE.plan(X64, SYSV, prefix)
        self.assertEqual(success, 1)
        self.assertEqual(len(patch), 9)
        relocated_call = 85 + 4
        displacement = struct.unpack_from("<i", code, relocated_call + 1)[0]
        self.assertEqual(0x110000 + relocated_call + 5 + displacement, 0x101000)

    def test_instruction_pointer_observers_are_rejected(self):
        self.assertEqual(CORE.plan(X64, SYSV, bytes.fromhex("e80000000058"))[0], 0)
        self.assertEqual(CORE.plan(X64, SYSV, bytes.fromhex("67488b0500000000"))[0], 0)

    def test_address_overflow_becomes_unknown(self):
        decoded = CORE.decode(X64, bytes.fromhex("e9ffffff7f"), (1 << 63) - 32)
        self.assertEqual(decoded.target, 0)

    def test_arm_misalignment_is_rejected(self):
        self.assertEqual(CORE.plan(ARM64, SYSV, word(0xD503201F), address=0x100001)[0], 0)

    def test_truncated_prefixes_are_rejected(self):
        for size in range(5):
            self.assertEqual(CORE.plan(X64, SYSV, b"\x48\x8b\x05\x00"[:size])[0], 0)
        for size in range(4):
            self.assertEqual(CORE.plan(ARM64, SYSV, word(0xA9BF7BFD)[:size])[0], 0)

    def test_seeded_mutation_never_returns_inconsistent_sizes(self):
        generator = random.Random(0xF0A7)
        for arch in (X64, ARM64):
            for _ in range(500):
                prefix = generator.randbytes(32)
                success, code, patch = CORE.plan(arch, SYSV, prefix)
                if success:
                    self.assertLessEqual(len(patch), 32)
                    self.assertLessEqual(len(code), 512)
                    self.assertGreaterEqual(len(patch), 5 if arch == X64 else 4)


if __name__ == "__main__":
    unittest.main(verbosity=2)
