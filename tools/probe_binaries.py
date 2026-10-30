#!/usr/bin/env python3
"""Read-only corpus validation. Existing images are evidence, not scratch space."""

import argparse
import hashlib
import json
import struct
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "legacy"))
sys.path.insert(0, str(ROOT / "tests"))
from bindings import ARM64, SYSV, WINDOWS, X64, Core
from freelumina_patch import load_binary


def resolve_local_elf_relocations(binary, spans):
    """Model the loader's local ELF bindings in private snapshot copies.

    External imports stay unresolved. This is relocation simulation, not a
    claim that an on-disk GOT is already a runtime address table.
    """
    data = binary.image.bytes(0, binary.image.size)
    section_offset = struct.unpack_from("<Q", data, 0x28)[0]
    entry_size, section_count = struct.unpack_from("<HH", data, 0x3A)
    sections = [struct.unpack_from("<IIQQQQIIQQ", data, section_offset + index * entry_size)
                for index in range(section_count)]
    owners = [(address, bytearray(content), executable) for address, content, executable in spans]
    count = 0
    for section in sections:
        if section[1] != 4:  # SHT_RELA
            continue
        symbols = sections[section[6]]
        for offset in range(section[4], section[4] + section[5], section[9]):
            slot, information, addend = struct.unpack_from("<QQq", data, offset)
            symbol_index, kind = information >> 32, information & 0xFFFFFFFF
            value = None
            if kind == (1027 if binary.arch == "arm64" else 8):
                value = addend  # R_*_RELATIVE; modeled load bias is zero.
            elif kind in ((257, 1025, 1026) if binary.arch == "arm64" else (1, 6, 7)):
                symbol = struct.unpack_from("<IBBHQQ", data, symbols[4] + symbol_index * symbols[9])
                if symbol[3] != 0:  # A defined local binding, not an external import.
                    value = symbol[4] + addend
            if value is None:
                continue
            for address, content, _ in owners:
                relative = slot - address
                if 0 <= relative <= len(content) - 8:
                    struct.pack_into("<Q", content, relative, value & 0xFFFFFFFFFFFFFFFF)
                    count += 1
                    break
    return [(address, bytes(content), executable) for address, content, executable in owners], count


def probe(core, path, deep):
    binary = load_binary(str(path))
    if binary is None:
        raise ValueError(f"unsupported image: {path}")
    if binary.macho_slices:
        raise ValueError("select a thin image for this validation")
    arch = {"x86-64": X64, "arm64": ARM64}[binary.arch]
    abi = WINDOWS if binary.fmt == "PE" else SYSV
    symbols = {
        symbol.name: symbol.value
        for symbol in binary.symbols
        if symbol.defined
    }
    exported = symbols.get("has_valid_add_on", 0)
    license_address = symbols.get("is_license_valid", 0)
    spans = []
    for segment in binary.segments:
        if segment.filesize:
            data = binary.image.bytes(segment.offset, segment.filesize)
            if len(data) != segment.filesize:
                raise ValueError(f"truncated segment {segment.name}")
            spans.append((segment.vaddr, data, int(segment.exec)))
    relocation_count = 0
    if binary.fmt == "ELF":
        spans, relocation_count = resolve_local_elf_relocations(binary, spans)
    found = core.analyze(arch, abi, spans, exported=exported, license_address=license_address)
    report = {
        "path": str(path),
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "format": binary.fmt,
        "architecture": binary.arch,
        "exported": hex(exported),
        "license_anchor": hex(license_address),
        "target": hex(found.target),
        "status": found.status,
        "reason": found.reason,
        "simulated_local_relocations": relocation_count,
    }
    if found.target:
        offset = binary.va_to_off(found.target)
        prefix = binary.image.bytes(offset, 32)
        # Match the lifecycle's landing-pad preservation.
        skip = 0
        if arch == X64 and prefix.startswith(bytes.fromhex("f30f1efa")):
            skip = 4
        if arch == ARM64 and int.from_bytes(prefix[:4], "little") & 0xFFFFFF1F == 0xD503241F:
            skip = 4
        address = found.target + skip
        success, code, patch = core.plan(
            arch, abi, binary.image.bytes(offset + skip, 32),
            address=address, trampoline=(address + 0x10000 + 3) & ~3,
        )
        report["plan"] = {"success": success, "code_bytes": len(code), "patch_bytes": len(patch)}
    if deep:
        hidden = core.analyze(arch, abi, spans, license_address=license_address)
        report["without_target_symbol"] = {
            "target": hex(hidden.target), "status": hidden.status,
            "candidates": hidden.candidates, "references": hidden.references,
            "reason": hidden.reason,
            "agrees_with_export": bool(exported and exported == hidden.target),
        }
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("library", type=Path)
    parser.add_argument("paths", nargs="*", type=Path)
    parser.add_argument("--deep", action="store_true", help="also hide the target symbol")
    parser.add_argument("--output", type=Path)
    arguments = parser.parse_args()
    paths = arguments.paths or sorted(
        path for path in (ROOT / "unpacked").rglob("*")
        if path.name in {"ida.dll", "ida32.dll", "libida.so", "libida32.so", "libida.dylib", "libida32.dylib"}
    )
    if not arguments.paths:
        # The working armmac copies were modified before this port. Prefer
        # the supplied pristine copies when establishing independent evidence.
        paths = [
            ROOT / "pristine_armmac" / path.relative_to(ROOT / "unpacked" / "armmac")
            if path.is_relative_to(ROOT / "unpacked" / "armmac")
            and (ROOT / "pristine_armmac" / path.relative_to(ROOT / "unpacked" / "armmac")).exists()
            else path
            for path in paths
        ]
    core = Core(arguments.library.resolve())
    reports = []
    for path in paths:
        report = probe(core, path, arguments.deep)
        reports.append(report)
        print(json.dumps(report), flush=True)
    if arguments.output:
        arguments.output.write_text(json.dumps(reports, indent=2) + "\n")


if __name__ == "__main__":
    main()
