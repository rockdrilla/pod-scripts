#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

curl -qsSL 'https://golang.org/dl/' \
| URI='https://golang.org' perl -ne 'while(m/(?<=href=)([\x22\x27])(.+?)\1(.*)$/){$_=$3;my $s=$2;$s="$ENV{URI}$s" if $s !~ m/^[[:alnum:]]+?:/;print "$s\n";}' \
| sed -En '/^.+\/go([^/]+)\.src\.[^/]+$/{s//\1/;p;}' \
| head -n 1
