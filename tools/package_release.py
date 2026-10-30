#!/usr/bin/env python3
"""Verify and package a Release build with checksums and dependency metadata."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

from check_artifact import ROOT, inspect


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('build', type=Path)
    parser.add_argument('--output', type=Path, default=ROOT / 'dist')
    args = parser.parse_args()
    build = args.build.resolve(strict=True)
    metadata = json.loads((build / 'release-Release.json').read_text())
    if metadata['configuration'] != 'Release':
        raise ValueError('Only Release builds can be packaged')
    if not (build / 'CTestTestfile.cmake').is_file():
        raise ValueError('Configure with BUILD_TESTING=ON before packaging')
    # Never let an old test log certify a newly built binary.
    subprocess.run(['ctest', '--test-dir', str(build), '-C', 'Release', '--output-on-failure', '--no-tests=error'], check=True)
    candidates = [build / metadata['library'], build / 'Release' / metadata['library']]
    library = next((path for path in candidates if path.is_file()), None)
    if library is None:
        raise FileNotFoundError(metadata['library'])
    metadata.update(inspect(library))
    metadata['sha256'] = hashlib.sha256(library.read_bytes()).hexdigest()
    metadata['source_sha256'] = {
        str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted((ROOT / 'src').rglob('*'))
        if path.is_file() and path.suffix in {'.bas', '.bi', '.c', '.h', '.txt'}
    }
    stem = f'freelumina-{metadata["version"]}-{metadata["system"].lower()}-{metadata["architecture"]}'
    args.output.mkdir(parents=True, exist_ok=True)
    archive = args.output / f'{stem}.zip'
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as package:
        package.write(library, f'{stem}/{library.name}')
        for path in [ROOT / 'README.md', *sorted((ROOT / 'licenses').glob('*.txt'))]:
            package.write(path, f'{stem}/{path.relative_to(ROOT)}')
        package.writestr(f'{stem}/manifest.json', json.dumps(metadata, indent=2) + '\n')
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix('.zip.sha256').write_text(f'{checksum}  {archive.name}\n')
    print(archive)
    print(f'SHA-256: {checksum}')


if __name__ == '__main__':
    main()
