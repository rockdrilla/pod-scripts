#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

pkg_d='/var/cache/apt/archives'

find "${pkg_d}/" -mindepth 1 -delete

aptitude update

## hacky approach to speed up "aptitude reinstall '~i'":
## 1) extract all
## 2) reconfigure all

	aptitude -y --download-only reinstall '~i'
	## don't bother with "base-files"
	find "${pkg_d}/" -name 'base-files_*.deb' -type f -delete

	find "${pkg_d}/" -name '*.deb' -type f \
	| xargs -r -I '{}' dpkg-deb -x '{}' /

	dpkg-query --show --showformat='${binary:Package}\n' \
	| xargs -r dpkg-reconfigure -f

## install useful packages :)
aptitude -y --with-recommends install bash-completion curl file info less \
                              man-db manpages manpages-dev nano ncurses-term \
                              psmisc sensible-utils vim wget

find "${pkg_d}/" -mindepth 1 -delete

## install e-wrapper directly from GitHub
e_url='https://raw.githubusercontent.com/kilobyte/e/master/e'
curl -sSL -o /usr/local/bin/e "${e_url}" && chmod 0755 /usr/local/bin/e

## configure editor and pager (less)
cat >>/etc/profile <<-EOF

	VISUAL=/usr/bin/sensible-editor
	EDITOR=/usr/bin/sensible-editor
	PAGER=less
	LESS=FRS
	export VISUAL EDITOR PAGER LESS
EOF

cat <<EOF
now issue command

	exec bash -l

to run your session in more interactive way
EOF
