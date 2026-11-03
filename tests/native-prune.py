# SPDX-License-Identifier: MIT
"""Exercise native removal policy: never force removal of required store objects."""
import subprocess
import sys

command = sys.argv[1:]
def objects():
    result = subprocess.check_output(command + ['list-installed'], text=True)
    return sorted(line.split()[0] for line in result.splitlines() if line.startswith('nix-store-'))

while True:
    before = objects()
    if not before:
        break
    failures = []
    for package in before:
        # opkg itself rejects objects retained by another installed package.
        result = subprocess.run(command + ['--autoremove', 'remove', package],
                                capture_output=True, text=True, check=False)
        if result.returncode:
            failures.append(result.stdout + result.stderr)
    if objects() == before:
        installed = subprocess.check_output(command + ['list-installed'], text=True).splitlines()
        if all(line.startswith('nix-store-') for line in installed):
            raise RuntimeError('Native orphan removal failed:\n' + '\n'.join(failures))
        break
