"""Execute both generated instruction sets with an independent emulator.

No target binary is executed. Unicorn is a test dependency, never a plugin
dependency. Passing this suite establishes finite fixture behavior only.
"""

import struct
import sys
import unittest

from unicorn import Uc, UC_ARCH_ARM64, UC_ARCH_X86, UC_MODE_64, UC_MODE_ARM
from unicorn.arm64_const import UC_ARM64_REG_LR, UC_ARM64_REG_SP, UC_ARM64_REG_X0, UC_ARM64_REG_X16
from unicorn.x86_const import UC_X86_REG_RAX, UC_X86_REG_RCX, UC_X86_REG_RDI, UC_X86_REG_RSP

from bindings import ARM64, SYSV, WINDOWS, X64, Core


CORE = Core(sys.argv.pop(1))
ENTRY = 0x100000
TRAMPOLINE = 0x110000
DATA = 0x200000
STACK = 0x300000
SENTINEL = 0x400000
PAGE_SIZE = 4096


def execute(arch, abi, name, *, page_edge=False, prefix=None, extra_data=None):
    if prefix is None:
        prefix = bytes.fromhex("b800000000c3") if arch == X64 else bytes.fromhex("00008052c0035fd6")
    success, code, patch = CORE.plan(arch, abi, prefix, ENTRY, TRAMPOLINE)
    if not success:
        raise AssertionError("fixture plan rejected")
    machine = Uc(UC_ARCH_X86 if arch == X64 else UC_ARCH_ARM64, UC_MODE_64 if arch == X64 else UC_MODE_ARM)
    for address, size in ((ENTRY, PAGE_SIZE), (TRAMPOLINE, PAGE_SIZE), (DATA, PAGE_SIZE),
                          (STACK, 0x10000), (SENTINEL, PAGE_SIZE)):
        machine.mem_map(address, size)
    machine.mem_write(ENTRY, prefix)
    machine.mem_write(ENTRY, patch)
    machine.mem_write(TRAMPOLINE, code)
    if extra_data:
        machine.mem_write(*extra_data)
    pointer = 0
    if name is not None:
        pointer = DATA + PAGE_SIZE - len(name) if page_edge else DATA
        machine.mem_write(pointer, name)
    if arch == X64:
        machine.reg_write(UC_X86_REG_RSP, STACK + 0xFFF0)
        machine.mem_write(STACK + 0xFFF0, struct.pack("<Q", SENTINEL))
        machine.reg_write(UC_X86_REG_RCX, 0xDEAD0000)
        machine.reg_write(UC_X86_REG_RDI, 0xDEAD1000)
        machine.reg_write(UC_X86_REG_RCX if abi == WINDOWS else UC_X86_REG_RDI, pointer)
    else:
        machine.reg_write(UC_ARM64_REG_SP, STACK + 0xFFF0)
        machine.reg_write(UC_ARM64_REG_LR, SENTINEL)
        machine.reg_write(UC_ARM64_REG_X0, pointer)
        machine.reg_write(UC_ARM64_REG_X16, 0xA5A5A5A5)
    machine.emu_start(ENTRY, SENTINEL, count=500)
    result = machine.reg_read(UC_X86_REG_RAX if arch == X64 else UC_ARM64_REG_X0)
    return result & 0xFFFFFFFF


class ExecutionTests(unittest.TestCase):
    def test_dispatch_on_all_six_configurations(self):
        for arch in (X64, ARM64):
            for platform, abi in (("macOS", SYSV), ("Linux", SYSV), ("Windows", WINDOWS)):
                for name, expected in ((b"LUMINA\0", 1), (b"LUMINA\0X", 1), (b"LUMINAX\0", 0),
                                       (b"BOGUS\0", 0), (b"\0", 0), (None, 0)):
                    with self.subTest(arch=arch, platform=platform, name=name):
                        self.assertEqual(execute(arch, abi, name), expected)

    def test_every_terminated_prefix_at_an_unmapped_page_boundary(self):
        for arch in (X64, ARM64):
            for abi in (SYSV, WINDOWS):
                for length in range(7):
                    with self.subTest(arch=arch, abi=abi, length=length):
                        self.assertEqual(execute(arch, abi, b"LUMINA"[:length] + b"\0", page_edge=True), int(length == 6))

    def test_rip_relative_original_behavior_survives_replay(self):
        location = ENTRY + 0x200
        prefix = b"\x8b\x05" + struct.pack("<i", location - ENTRY - 6) + b"\xc3"
        for abi in (SYSV, WINDOWS):
            self.assertEqual(execute(X64, abi, b"OTHER\0", prefix=prefix,
                                     extra_data=(location, struct.pack("<I", 0x12345678))), 0x12345678)

    def test_direct_call_original_behavior_survives_replay(self):
        # Four bytes of stack setup force the CALL into the stolen prefix.
        helper = ENTRY + 0x200
        prefix = b"\x48\x83\xec\x28\xe8" + struct.pack("<i", helper - ENTRY - 9)
        prefix += b"\x48\x83\xc4\x28\xc3"
        for abi in (SYSV, WINDOWS):
            self.assertEqual(execute(X64, abi, b"OTHER\0", prefix=prefix,
                                     extra_data=(helper, bytes.fromhex("b878563412c3"))), 0x12345678)


if __name__ == "__main__":
    unittest.main(verbosity=2)
