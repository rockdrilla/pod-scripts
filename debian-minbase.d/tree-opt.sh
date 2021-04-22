#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

[ -d "$1" ] || exit 0

find "$1" -mindepth 1 -maxdepth 1 -type d -print0 \
| xargs -0 -r -P 2 -n 1 "$0"

t=$(mktemp)

find "$1" -mindepth 1 -maxdepth 1 >"$t"
[ -s "$t" ] || rmdir ${VERBOSE:+-v} "$1"

rm -f "$t"
