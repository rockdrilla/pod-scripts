#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

## reset locale to default one
unset LANGUAGE LC_CTYPE LC_NUMERIC LC_TIME LC_COLLATE LC_MONETARY LC_MESSAGES
unset LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT LC_IDENTIFICATION
export LANG=C.UTF8
export LC_ALL=C.UTF-8

## setup various environment variables representing temporary directory
export TMPDIR=/tmp
export TMP=/tmp
export TEMPDIR=/tmp
export TEMP=/tmp

## setup debconf frontend via environment
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
## setup debconf priority via environment
export DEBIAN_PRIORITY=critical

du -xsh /

run-parts ${VERBOSE:+--verbose} --exit-on-error /.cleanup.d
r=$?

## cleanup /tmp
find /tmp -mindepth 1 ${VERBOSE:+-ls} -delete

du -xsh /

exit $r
