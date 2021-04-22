#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

set -e

[ -n "$1" ]

IFS=/ read area zone <<EOF
$1
EOF

[ -n "${area}" ]
[ -n "${zone}" ]

file="/usr/share/zoneinfo/$1"

[ -f "${file}" ]
[ -s "${file}" ]

echo "$1" > /etc/timezone
ln -fs "${file}" /etc/localtime

debconf-set-selections -c < /dev/null 2>/dev/null

{ cat <<-EOF
	tzdata  tzdata/Areas          select  ${area}
	tzdata  tzdata/Zones/${area}  select  ${zone}
EOF
} | debconf-set-selections
