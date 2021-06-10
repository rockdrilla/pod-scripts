#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

set -e

if ! [ -x /usr/bin/aptitude ] ; then
	## update package lists; may fail sometimes,
	## e.g. soon-to-release channels like Debian "bullseye" @ 22.04.2021
	apt -qq update || :

	## install apt-utils and aptitude
	apt -qq -y install apt-utils aptitude
fi

if [ $# -ne 0 ] ; then
	## perform requested operation
	exec aptitude -y "$@"
fi
