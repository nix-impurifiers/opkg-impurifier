# SPDX-License-Identifier: MIT
"""Compile native-owned closure objects into portable gzip/tar IPK envelopes."""
import gzip
import hashlib
import json
from pathlib import Path
import re
import sys
import tarfile
import tempfile

collection, destination = map(Path, sys.argv[1:3])
architecture = sys.argv[3]
destination.mkdir()
def normalized(info):
    info.uid = info.gid = 0
    info.uname = info.gname = ''
    info.mtime = 1
    return info

def archive(path, entries):
    with path.open('wb') as raw, gzip.GzipFile(fileobj=raw, mode='wb', filename='', mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode='w', format=tarfile.GNU_FORMAT) as output:
            for source, name in entries:
                output.add(source, arcname=name, filter=normalized)

for package in json.loads((collection / 'packages.json').read_text()):
    record = json.loads((collection / package / 'metadata.json').read_text())
    if not re.fullmatch(r'[0-9][A-Za-z0-9.+:~_\-]*', record['version']):
        raise ValueError('unsupported native IPK version: ' + record['version'])
    source = collection / package / 'tree'
    with tempfile.TemporaryDirectory() as temporary:
        work = Path(temporary)
        control = work / 'control'
        control.mkdir()
        text = (f'Package: {record["name"]}\nVersion: {record["version"]}-1\nArchitecture: {architecture}\n'
                'Maintainer: Nix Impurifiers <root@localhost>\nDescription: Native-owned Nix-built payload\n'
                'License: LicenseRef-Unknown\n')
        if record['dependencies']:
            text += 'Depends: ' + ', '.join(name + ' (= 1-1)' for name in record['dependencies']) + '\n'
        (control / 'control').write_text(text)
        checksums = []
        for entry in sorted(source.rglob('*')):
            if entry.is_file() and not entry.is_symlink():
                with entry.open('rb') as stream:
                    digest = hashlib.file_digest(stream, 'md5').hexdigest()
                checksums.append(digest + '  ' + entry.relative_to(source).as_posix())
        (control / 'md5sums').write_text('\n'.join(checksums) + ('\n' if checksums else ''))
        (work / 'debian-binary').write_text('2.0\n')
        archive(work / 'control.tar.gz', [(control / 'control', 'control'), (control / 'md5sums', 'md5sums')])
        archive(work / 'data.tar.gz', [(source, '.')])
        archive(destination / f'{record["name"]}_{record["version"]}-1_{architecture}.ipk',
                [(work / name, name) for name in ['debian-binary', 'control.tar.gz', 'data.tar.gz']])
