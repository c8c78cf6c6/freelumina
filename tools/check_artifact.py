#!/usr/bin/env python3
"""Validate the loadable library's public ABI and runtime dependencies."""
import argparse
import ctypes
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def output(*command):
    return subprocess.check_output(command, text=True, stderr=subprocess.STDOUT)


def inspect(path):
    path = Path(path).resolve(strict=True)
    if sys.platform == 'darwin':
        exports = {line.split()[-1].removeprefix('_') for line in output('/usr/bin/nm', '-gU', str(path)).splitlines() if line.split()}
        dependencies = [line.strip().split(' (')[0] for line in output('otool', '-L', str(path)).splitlines()[1:]]
        # The first load command is the library's own install name.
        dependencies = dependencies[1:]
        unexpected = [name for name in dependencies if not name.startswith(('/usr/lib/', '/System/Library/'))]
    elif sys.platform == 'win32':
        table = output('objdump', '-p', str(path))
        names = table.split('[Ordinal/Name Pointer] Table', 1)
        if len(names) != 2:
            raise ValueError('PE export table is missing')
        exports = set(re.findall(r'^\s*\[\s*\d+\]\s+(\w+)\s*$', names[1], re.M))
        dependencies = re.findall(r'DLL Name:\s*(\S+)', table)
        system_dlls = {'kernel32.dll', 'ntdll.dll', 'user32.dll', 'advapi32.dll', 'winmm.dll',
                       'msvcrt.dll', 'ucrtbase.dll', 'bcrypt.dll', 'shell32.dll', 'ole32.dll',
                       'oleaut32.dll', 'ws2_32.dll', 'gdi32.dll', 'msvcp_win.dll', 'crypt32.dll',
                       'version.dll', 'comdlg32.dll'}
        unexpected = [name for name in dependencies if name.lower() not in system_dlls
                      and not name.lower().startswith(('api-ms-win-', 'ext-ms-win-'))]
    else:
        exports = {line.split()[-1].split('@')[0] for line in output('nm', '-D', '--defined-only', str(path)).splitlines() if line.split()}
        dynamic = output('readelf', '-d', str(path))
        dependencies = re.findall(r'\(NEEDED\).*?\[(.*?)\]', dynamic)
        system_library = re.compile(r'^(?:lib(?:c|m|pthread|dl|rt|tinfo|ncursesw?|gcc_s)\.so(?:\.\d+)*|ld-linux[^/]*\.so(?:\.\d+)*)$')
        unexpected = [name for name in dependencies if not system_library.fullmatch(name)]
        if re.search(r'\((?:RPATH|RUNPATH)\)', dynamic):
            raise ValueError('Release library contains a runtime search path')
    expected = set((ROOT / 'src/exports.txt').read_text().split())
    if exports != expected:
        raise ValueError(f'Export mismatch: missing={sorted(expected - exports)}, unexpected={sorted(exports - expected)}')
    if unexpected:
        raise ValueError(f'Non-system runtime dependencies: {unexpected}')
    library = ctypes.CDLL(str(path))
    library.fl_native_arch.restype = ctypes.c_int
    if library.fl_native_arch() not in (1, 2):
        raise ValueError('Invalid architecture response from loaded library')
    return {'exports': sorted(exports), 'dependencies': dependencies}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('library', type=Path)
    args = parser.parse_args()
    result = inspect(args.library)
    print(f'Artifact verified: {len(result["exports"])} public symbols; system dependencies only; loads successfully')


if __name__ == '__main__':
    main()
