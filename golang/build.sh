#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

set -e -f

tar -C "$1" -xf "$2"
cd "$1/go/src/"
./make.bash
[ -x "$1/go/bin/go" ]
export PATH="$1/go/bin:${PATH}"
go install std
XGLOB_DIRS=1 /opt/xglob.sh "$1/go/" <<-EOF
	delete=pkg/**/cmd
	delete=pkg/bootstrap
	delete=pkg/obj
	delete=pkg/tool/**/api
	delete=pkg/tool/**/go_bootstrap
	delete=src/cmd/dist/dist
EOF
