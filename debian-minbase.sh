#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin
set -e

if [ -n "$SOURCE_DATE_EPOCH" ] ; then
	ts="$SOURCE_DATE_EPOCH"
else
	ts=$(date '+%s')
	export SOURCE_DATE_EPOCH=$ts
fi

dir0=$(dirname "$0")
name0=$(basename "$0")

suite=unstable
if [ -n "$1" ] ; then
	x=$(printf '%s' "$1"  | tr -d '[a-z]' | wc -c)
	if [ "$x" = "0" ] ; then
		suite=$1
	else
		echo "parameter '$1' looks spoiled, defaulting to '$suite'" 1>&2
	fi
fi

pkg_aux='apt-utils aptitude e-wrapper less lsof vim-tiny'
pkg_auto='dialog whiptail'
image="debian-minbase-$suite"

arch=$(dpkg --print-architecture)

repo_base='https://github.com/rockdrilla/pod-scripts'
repo_contact="$repo_base/issues/new/choose"
self_upstream="$repo_base.git /$name0"

sha256() { sha256sum -b "$1" | grep -Eio '^[0-9a-f]+' | tr '[A-F]' '[a-f]' ; }

self_sha256=$(sha256 "$0")

own_ver() {
	git -C "$dir0" log -n 1 --format=%h -- "$name0" 2>/dev/null || true
}
self_version=$(own_ver "$0")

pkg_ver() { dpkg-query --showformat='${Version}' --show "$1"; }
mmdebstrap_version=$(pkg_ver mmdebstrap)
buildah_version=$(pkg_ver buildah)
podman_version=$(pkg_ver podman)


tag=$(date '+%Y%m%d%H%M%S' -d @$ts)

tarball=$(mktemp -u)'.tar'

## hack for libpam-tmpdir : we need 'shared' /tmp not per-user one :)
orig_tmp=$TMPDIR ; TMPDIR=/tmp TEMPDIR=/tmp TMP=/tmp TEMP=/tmp

name0=$(echo "$name0" | sed -E 's/\.[^.]+$//')
dir0="$dir0/$name0.d"

uid=$(ps -n -o euid= -p $$)
gid=$(ps -n -o egid= -p $$)

mmdebstrap \
  --verbose \
  --format=tar \
  --variant=minbase \
  --include="$pkg_aux $pkg_auto" \
  --aptopt="$dir0/apt.conf" \
  --dpkgopt="$dir0/dpkg.cfg" \
  --customize-hook='mkdir -p "$1/.cleanup.d"' \
  --customize-hook="sync-in '$dir0/apt.conf.d' /etc/apt/apt.conf.d" \
  --customize-hook="sync-in '$dir0/dpkg.cfg.d' /etc/dpkg/dpkg.cfg.d" \
  --customize-hook="sync-in '$dir0/cleanup.d' /.cleanup.d" \
  --customize-hook="copy-in '$dir0/cleanup.sh' /" \
  --customize-hook='mv "$1/cleanup.sh" "$1/.cleanup.sh"' \
  --customize-hook="'$dir0/mmdebstrap.sh' \"\$1\" $suite '$pkg_aux' $uid $gid" \
  --skip=cleanup/apt \
  $suite "$tarball" || true

if ! tar -tf "$tarball" >/dev/null ; then
	rm "$tarball"
	exit 1
fi

tar_sha256=$(sha256 "$tarball")

k=$(podman import "$tarball" "$image-temporary:$tag" || true)

rm -f "$tarball" ; unset tarball

[ -n "$k" ]

export BUILDAH_FORMAT=docker

c=$(buildah from --pull-never "$k" || true)
if [ -z "$c" ] ; then
	podman image rm "$k" || true
	exit 1
fi

f=$(printf 'bc() { buildah config "$@" %s ; }' "$c") ; eval "$f"

bc --hostname debian
bc --comment "basic Debian image"
bc --label "build.script.commit=${self_version:-none}"
bc --label "build.script.contact=$repo_contact"
bc --label "build.script.hash=$self_sha256"
bc --label "build.script.source=$self_upstream"
bc --label "build.ts=$ts"
bc --label "debian.buildah=$buildah_version"
bc --label "debian.mmdebstrap=$mmdebstrap_version"
bc --label "debian.podman=$podman_version"
bc --label "tarball.hash=$tar_sha256"
bc --env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
bc --env LANG=C.UTF8
bc --env LC_ALL=C.UTF-8
bc --env VISUAL=/usr/bin/sensible-editor
bc --env EDITOR=/usr/bin/sensible-editor
bc --env TERM=xterm
bc --env TMPDIR=/tmp
bc --env TMP=/tmp
bc --env TEMPDIR=/tmp
bc --env TEMP=/tmp
bc --env PAGER=less
bc --env LESS=FRS

buildah commit --squash --timestamp $ts "$c" "$image:$tag" || true

buildah rm "$c"
podman image rm "$k"

echo "$image:$tag has been built successfully"
