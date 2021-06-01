#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

set -e -f

dir0=$(dirname "$0")

ver=
case "$1" in
latest) ver=$("${dir0}/latest.sh") ;;
*)      ver=$1 ;;
esac
[ -n "${ver}" ]

curl -sSL -o "$2" "https://golang.org/dl/go${ver}.src.tar.gz"
tar -tf "$2" >/dev/null
