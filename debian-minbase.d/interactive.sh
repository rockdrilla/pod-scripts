#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

pkg_d='/var/cache/apt/archives'

find "${pkg_d}/" -mindepth 1 -delete

aptitude update

## hacky approach to speed up "aptitude reinstall '~i'":
## 1) extract all
## 2) reconfigure all

	aptitude --download-only reinstall '~i'
	## don't bother with "base-files"
	find "${pkg_d}/" -name 'base-files_*.deb' -type f -delete

	find "${pkg_d}/" -name '*.deb' -type f \
	| xargs -r -I '{}' dpkg-deb -x '{}' /

	dpkg-query --show --showformat='${binary:Package}\n' \
	| xargs -r dpkg-reconfigure -f

## install useful packages :)
aptitude -y install bash-completion file info man-db manpages manpages-dev vim

find "${pkg_d}/" -mindepth 1 -delete

cat <<EOF
now issue command
	exec bash -l
to run your session in more interactive way
EOF
