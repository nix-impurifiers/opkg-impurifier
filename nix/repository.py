# SPDX-License-Identifier: MIT
"""Index native IPK metadata and exact artifact checksums for opkg feeds."""
import hashlib
import io
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile

output = Path(sys.argv[1])
output.mkdir(parents=True)
records = []
for artifact in map(Path, sys.argv[2:]):
    with artifact.open("rb") as stream:
        is_ar = stream.read(8) == b"!<arch>\n"
    if is_ar:
        control_archive = subprocess.check_output(["ar", "p", str(artifact), "control.tar.gz"])
    else:
        with tarfile.open(artifact) as envelope:
            control_archive = envelope.extractfile("control.tar.gz").read()
    with tarfile.open(fileobj=io.BytesIO(control_archive)) as archive:
        member = next(m for m in archive if m.name.removeprefix("./") == "control")
        control = archive.extractfile(member).read().decode().strip()
    fields = dict(line.split(": ", 1) for line in control.splitlines() if ": " in line and not line.startswith(" "))
    filename = f'{fields["Package"]}_{fields["Version"]}_{fields["Architecture"]}.ipk'
    if "/" in filename or "\n" in filename or (output / filename).exists():
        raise ValueError("invalid or duplicate IPK repository filename")
    shutil.copyfile(artifact, output / filename)
    with artifact.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    with artifact.open("rb") as stream:
        legacy_digest = hashlib.file_digest(stream, "md5").hexdigest()
    records.append(f"{control}\nFilename: {filename}\nSize: {artifact.stat().st_size}\nSHA256sum: {digest}\nMD5sum: {legacy_digest}\n")
(output / "Packages").write_text("\n".join(sorted(records)))
