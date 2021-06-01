#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

set -f

dir0=$(dirname "$0")
name0=$(basename "$0")

export SOURCE_DATE_EPOCH=$(date -u '+%s')

distro_info() { "${dir0}/distro-info/tool.sh" "$@" ; }
distro_chan() { tac | cut -d ',' -f 1 | cut -d ' ' -f 1 | xargs -r ; }

debian_channels='unstable '$(distro_info debian | distro_chan)
ubuntu_channels=$(distro_info ubuntu | distro_chan)

## prepare to work

cleanup() {
	podman stop -ai
	buildah rm -a
	podman rmi -af
	[ -z "${WORKDIR}" ] && return
	cd /
	rm -rf "${WORKDIR}"
}

user=$(docker-login.sh | sed -En '/^docker.io\|(\S+)$/{s//\1/;p;}')
REG="docker://${user}"

list_images() {
	podman images --format '{{.Id}}|{{.Repository}}|{{.Tag}}' \
	| grep -Ei "$1"
}

image_rm() { podman image rm "$1" ; }

image_push() {
	podman push "$1" "$2"
	podman pull "$2"
}

## $1 - hash image id
## $2 - tag
## $3 - printf formatted image name
image_1_push() {
	i="${REG}/"$(printf "$3" "$2")
	image_push "$1" "$i"
}

## $1 - hash image id
## $2 - tag
## $3 - printf formatted image name
image_2_push() {
	for k in "$2" latest ; do
		image_1_push "$1" "$k" "$3"
	done
}

## $1 - hash image id
## $2 - distro
## $3 - suite
## $4 - printf formatted image name
image_3_push() {
	for k in $(meta_query "$2" "$3") ; do
		image_1_push "$1" "$k" "$4"
	done
}

x_latest() { printf '%s\n' "$2" | grep -qE "^$1( |\$)" ; }
is_latest_debian() { x_latest "$1" "${debian_channels}" ; }
is_latest_ubuntu() { x_latest "$1" "${ubuntu_channels}" ; }
is_latest() { is_latest_debian "$1" || is_latest_ubuntu "$1" ; }

bud() { buildah bud --isolation chroot --network host --format docker -f "$@" ; }

image_ts() {
	{
		echo 1
		skopeo inspect "$1" \
		| jq -r 'select(has("Created")) | ."Created"' \
		| xargs -r -L 1 date -u '+%s' -d
	} 2>/dev/null \
	| tail -n 1
}

json_tarball_hash() {
	jq -r '.Labels | select(has("tarball.hash")) | ."tarball.hash"'
}

tarball_hash_local() {
	podman inspect "$1" \
	| jq -r '.[]' \
	| json_tarball_hash
}

tarball_hash_remote() {
	skopeo inspect "$1" \
	| json_tarball_hash
}

chan_altname() {
	distro_info "$1" "$2" \
	| cut -d ',' -f 1 \
	| tr -s ' ' '\n' \
	| grep -Fxv "$2"
}

chan_tag() {
	distro_info "$1" "$2" \
	| cut -d ',' -f 3 \
	| grep -Fxv "$2"
}

true_tag() {
	distro_info "$1" "$2" \
	| tail -n 1 \
	| cut -d ',' -f 1 \
	| tr -s ' ' '\n' \
	| grep -Fx "$3"
}

## work

WORKDIR=''
cleanup

WORKDIR=$(mktemp -d)
cd "${WORKDIR}"

echo ${debian_channels} | xargs -r -n 1 > debian.chan
echo ${ubuntu_channels} | xargs -r -n 1 > ubuntu.chan

meta_refill() {
	while read -r suite ; do
		r="${suite}"

		for k in $(chan_altname "$1" "${suite}") ; do
			r="$r $k"
		done

		tag=$(chan_tag "$1" "${suite}")
		k=$(true_tag "$1" "${tag}" "${suite}")
		if [ -n "$k" ] ; then
			r="$r ${tag}"
		fi

		is_latest "${suite}" && r="$r latest"

		echo "$r"
	done < "$1.chan" > "$1.meta"
}

meta_query() {
	grep -E "^$2( |\$)" "$1.meta"
}

meta_refill debian
meta_refill ubuntu

## build base images

build_minbase() {
	for suite in $(xargs -r -n 1 < "$1.chan") ; do
		"${dir0}/minbase/$1.sh" "${suite}"

		hash0=$(tarball_hash_remote "${REG}/$1-minbase:${suite}")

		list_images "\|[^|]+/$1-minbase\|${suite}" \
		| while IFS='|' read -r h p t ; do
			c=$(basename "$p")

			hash1=$(tarball_hash_local "$h")

			if [ "${hash0}" = "${hash1}" ] ; then
				## tags may change even image itself doesn't change 
				for t in $(chan_tag "${suite}") latest ; do
					hashT=${hash1}
					if [ -n "$t" ] ; then
						hashT=$(tarball_hash_remote "${REG}/$1-minbase:$t")
					fi

					if [ "${hashT}" != "${hash1}" ] ; then
						image_1_push "$h" "$t" "$c:%s"
					fi
				done

				sed -E -i "/^${suite}/d" "$1.chan"
				image_rm "$h"
				continue
			fi

			image_3_push "$h" "$1" "${suite}" "$c:%s"
		done
	done
}

build_minbase debian
build_minbase ubuntu

## build derivative images

build_micro() {
	while read -r suite ; do
		bud "${dir0}/micro/Dockerfile" -t "$1-micro:${suite}" \
			--build-arg "DISTRO=$1" \
			--build-arg "SUITE=${suite}" \
		"${dir0}/micro"
	done < "$1.chan"

	list_images "\|[^|]+/$1-micro\|" \
	| while IFS='|' read -r h p t ; do
		c=$(basename "$p")
		image_3_push "$h" "$1" "$t" "$c:%s"
	done
}

build_micro debian
build_micro ubuntu

## build 'build-essential'

build_essential() {
	while read -r suite ; do
		bud "${dir0}/build-essential/Dockerfile" \
			-t "build-essential:$1-${suite}" \
			--build-arg "DISTRO=$1" \
			--build-arg "SUITE=${suite}" \
		"${dir0}/build-essential"

		list_images "\|[^|]+/build-essential\|$1-${suite}" \
		| while IFS='|' read -r h p t ; do
			c=$(basename "$p")
			image_3_push "$h" "$1" "${suite}" "$c:$1-%s"
		done
	done < "$1.chan"
}

build_essential debian
build_essential ubuntu

## build 'golang'

t='golang-latest'
curl -qsSL 'https://golang.org/dl/' \
| URI='https://golang.org' perl -ne 'while(m/(?<=href=)([\x22\x27])(.+?)\1(.*)$/){$_=$3;my $s=$2;$s="$ENV{URI}$s" if $s !~ m/^[[:alnum:]]+?:/;print "$s\n";}' \
| sed -En '/^.+\/go([^/]+)\.src\.[^/]+$/{s//\1/;p;}' \
| head -n 1 > "$t"
golang_ver=$(cat "$t")
rm -f "$t"

if ! skopeo inspect "${REG}/golang:pure-${golang_ver}" >/dev/null 2>/dev/null ; then
	bud "${dir0}/golang/Dockerfile.pure" \
		-t golang:pure \
		${golang_ver:+--build-arg GOLANG_VERSION=${golang_ver}} \
	"${dir0}/golang"

	if [ -z "${golang_ver}" ] ; then
		golang_ver=$(podman run --rm golang:pure version \
		| sed -En '/^go version go([0-9.]+) .*$/{s##\1#;p;}')
	fi

	list_images '\|[^|]+/golang\|pure$' \
	| while IFS='|' read -r h p t ; do
		c=$(basename "$p")
		image_2_push "$h" "${golang_ver}" "$c:$t-%s"
	done
fi

build_golang_blend() {
	ts_curr=$(image_ts "${REG}/golang:$2-$1")
	ts_pure=$(image_ts "${REG}/golang:pure-$1")
	ts_base=$(image_ts "$3")

	rebuild=0
	[ ${ts_curr} -le ${ts_pure} ] && rebuild=1
	[ ${ts_curr} -le ${ts_base} ] && rebuild=1
	[ ${rebuild} -eq 0 ] && return

	bud "${dir0}/golang/Dockerfile.$2" \
		-t "golang:$2" \
		--build-arg "GOLANG_VERSION=$1" \
	"${dir0}/golang"

	list_images "\|[^|]+/golang\|$2\$" \
	| while IFS='|' read -r h p t ; do
		c=$(basename "$p")
		image_2_push "$h" "$1" "$c:$2-%s"
	done
}

build_golang_blend "${golang_ver}" alpine 'docker://alpine:latest'
for distro in debian ubuntu ; do
	## keep in sync with /golang/Dockerfile.*
	build_golang_blend "${golang_ver}" "${distro}" "${REG}/${distro}-minbase:latest"
done

## cleanup

cleanup
