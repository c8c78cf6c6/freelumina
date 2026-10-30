#!/usr/bin/env python3
"""Renumber BASIC statements by tens, preserving numeric GOTO destinations."""
import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [ROOT / 'src/basic' / name for name in (
    'freelumina.bas', 'helpers.bas', 'fl_bytes.bas', 'fl_decode.bas',
    'fl_search.bas', 'fl_patch.bas', 'fl_platform.bas', 'fl_lifecycle.bas')]


def uppercase_code(line):
    # Keep case-sensitive filenames, external symbol aliases, and text intact.
    return ''.join(part if i % 2 else part.upper()
                   for i, part in enumerate(re.split(r'("(?:[^"]|"")*")', line)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Check formatting without rewriting files')
    args = parser.parse_args()
    changed = []
    number = 10
    for path in SOURCES:
        rows = []
        destinations = {}
        for line in path.read_text().splitlines():
            match = re.match(r'\s*(\d+)\s+(.*)', line)
            old, text = (match[1], match[2]) if match else (None, line.strip())
            if not text or text.startswith('#'):
                rows.append((None, text))
                continue
            if old:
                destinations[old] = number
            if text.lower() == 'macho_cleanup:':
                destinations['macho_cleanup'] = number
                text = 'REM RELEASE MACHO COMMAND BUFFER'
            rows.append((number, text))
            number += 10
        output = []
        depth = 0
        for label, text in rows:
            def retarget(match):
                target = match[1]
                if target.isdecimal() and target not in destinations:
                    raise ValueError(f'{path.name}: GOTO references missing line {target}')
                return 'GOTO ' + str(destinations.get(target, target))
            text = ''.join(part if i % 2 else re.sub(r'(?i)\bgoto\s+(\w+)', retarget, part)
                           for i, part in enumerate(re.split(r'("(?:[^"]|"")*")', text)))
            text = uppercase_code(text)
            closing = text.startswith(('END FUNCTION', 'END SUB', 'END IF', 'NEXT', 'WEND', 'LOOP', 'ELSE'))
            if closing:
                depth = max(0, depth - 1)
            if label is None:
                output.append(text)
            else:
                output.append(f'{label} ' + '    ' * depth + text)
            if (text.startswith(('FUNCTION ', 'SUB ', 'FOR ', 'WHILE ', 'ELSE'))
                    or text == 'DO' or (text.startswith('IF ') and text.endswith(' THEN'))):
                depth += 1
        formatted = '\n'.join(output) + '\n'
        if formatted != path.read_text():
            changed.append(path.name)
            if not args.check:
                path.write_text(formatted)
    if args.check and changed:
        raise SystemExit('Run tools/renumber_basic.py: ' + ', '.join(changed))


if __name__ == '__main__':
    main()
