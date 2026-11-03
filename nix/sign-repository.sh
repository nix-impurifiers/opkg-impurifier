#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
[ "$#" -eq 2 ] || { echo 'usage: sign-repository REPOSITORY PRIVATE-KEY' >&2; exit 2; }
usign -S -m "$1/Packages" -s "$2" -x "$1/Packages.sig"
