#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

set -e

tar -C "$1" -xf "$2"
cd "$1/go/src/"
./make.bash
[ -x "$1/go/bin/go" ]
export PATH="$1/go/bin:${PATH}"
go install std
cd "$1/go/"
rm -rf \
    pkg/*/cmd \
    pkg/bootstrap \
    pkg/obj \
    pkg/tool/*/api \
    pkg/tool/*/go_bootstrap \
    src/cmd/dist/dist
