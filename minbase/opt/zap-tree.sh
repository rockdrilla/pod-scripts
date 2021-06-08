#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin
set -f

for i ; do
	[ -d "$i" ] || continue

	find "$i" -mindepth 1 -maxdepth 1 -type d -print0 \
	| ZAP=1 xargs -0 -r -n 1 "$0"

	[ "${ZAP}" != '1' ] && continue
	n=$(find "$i" -mindepth 1 -maxdepth 1 -printf '%y\n' | wc -l)
	[ "$n" = '0' ] && rmdir "$i"
done
