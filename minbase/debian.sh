#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

set -e

if [ -n "${TARBALL_ONLY}" ] ; then
	[ -n "$2" ]
	[ -w "$2" ] || touch "$2"
fi

if [ -n "${SOURCE_DATE_EPOCH}" ] ; then
	ts="${SOURCE_DATE_EPOCH}"
else
	ts=$(date -u '+%s')
	export SOURCE_DATE_EPOCH=${ts}
fi

dir0=$(dirname "$0")
name0=$(basename "$0")

distro=$(echo "${name0}" | sed -E 's/\.[^.]+$//')
image="${distro}-minbase"

## resolve real file
name0=$(readlink -e "$0")
name0=$(basename "${name0}")

arch=$(dpkg --print-architecture)

repo_base='https://github.com/rockdrilla/pod-scripts'
repo_contact="${repo_base}/issues/new/choose"
self_upstream="${repo_base}.git /${name0}"

sha256() { sha256sum -b "$1" | grep -Eio '^[0-9a-f]+' | tr '[A-F]' '[a-f]' ; }

self_sha256=$(sha256 "$0")

own_ver() {
	git -C "${dir0}" log -n 1 --format=%h -- "${name0}" 2>/dev/null || true
}
self_version=$(own_ver "$0")

pkg_ver() { dpkg-query --showformat='${Version}' --show "$1"; }
mmdebstrap_version=$(pkg_ver mmdebstrap)
buildah_version=$(pkg_ver buildah)
podman_version=$(pkg_ver podman)


suite_from_meta() { cut -d ',' -f 1 | cut -d ' ' -f 1 ; }
meta=
suite=
case "${distro}" in
debian)
	suite=unstable
	meta=$("${dir0}/../distro-info/tool.sh" "${distro}" "${suite}")
	;;
ubuntu)
	meta=$("${dir0}/../distro-info/tool.sh" "${distro}" | tail -n 1)
	suite=$(echo "${meta}" | suite_from_meta)
	;;
esac
[ -n "${meta}" ]
[ -n "${suite}" ]

if [ -n "$1" ] ; then
	x=$("${dir0}/../distro-info/tool.sh" "${distro}" "$1" | tail -n 1)
	y=$(echo "$x" | suite_from_meta)
	if [ -n "$x" ] ; then
		meta="$x"
		suite="$y"
	else
		echo "parameter '$1' looks spoiled, defaulting to '${suite}'" 1>&2
	fi
fi

reldate=$(echo "${meta}" | cut -d ',' -f 2)
reldate=$(date -u -d "${reldate}" '+%s')
export SOURCE_DATE_EPOCH=${reldate}

tag="${suite}-"$(date '+%Y%m%d%H%M%S' -d @${ts})

tarball=$(mktemp -u)'.tar'

## hack for libpam-tmpdir : we need 'shared' /tmp not per-user one :)
orig_tmp="${TMPDIR}" ; TMPDIR=/tmp TEMPDIR=/tmp TMP=/tmp TEMP=/tmp

uid=$(ps -n -o euid= -p $$)
gid=$(ps -n -o egid= -p $$)

comps=''
case "${distro}" in
debian) comps='main,contrib,non-free' ;;
ubuntu) comps='main,restricted,universe,multiverse' ;;
esac

mmdebstrap \
  --verbose \
  --format=tar \
  --variant=apt \
  ${comps:+"--components=${comps}"} \
  --aptopt="${dir0}/setup/apt.conf" \
  --dpkgopt="${dir0}/setup/dpkg.cfg" \
  --customize-hook="sync-in '${dir0}/opt' /opt" \
  --customize-hook="sync-in '${dir0}/setup/apt.conf.d' /etc/apt/apt.conf.d" \
  --customize-hook="sync-in '${dir0}/setup/dpkg.cfg.d' /etc/dpkg/dpkg.cfg.d" \
  --customize-hook="'${dir0}/setup/mmdebstrap.sh' \"\$1\" ${image} ${suite} ${uid} ${gid}" \
  --skip=cleanup/apt \
  ${suite} "${tarball}" || true

if ! tar -tf "${tarball}" >/dev/null 2>/dev/null ; then
	rm "${tarball}"
	exit 1
fi

if [ -n "${TARBALL_ONLY}" ] ; then
	cat < "${tarball}" > "$2"
	rm -f "${tarball}"
	exit
fi

tar_sha256=$(sha256 "${tarball}")

k=$(podman import "${tarball}" "${image}-temporary:${tag}" || true)

rm -f "${tarball}" ; unset tarball

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
bc --label "build.script.contact=${repo_contact}"
bc --label "build.script.hash=${self_sha256}"
bc --label "build.script.source=${self_upstream}"
bc --label "build.ts=${ts}"
bc --label "debian.buildah=${buildah_version}"
bc --label "debian.mmdebstrap=${mmdebstrap_version}"
bc --label "debian.podman=${podman_version}"
bc --label "tarball.hash=${tar_sha256}"

t_env=$(mktemp)
grep -Ev '^(#|$)' < "${dir0}/env.sh" > "${t_env}"
while read L ; do bc --env "$L" ; done < "${t_env}"
rm -f "${t_env}"

buildah commit --squash --timestamp ${ts} "$c" "${image}:${tag}" || true

buildah rm "$c"
podman image rm "$k"

echo "${image}:${tag} has been built successfully"
