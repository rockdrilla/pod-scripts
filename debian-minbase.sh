#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin
set -e

suite=sid
pkg_aux='apt-utils aptitude gawk less lsof vim-tiny'
image="debian-minbase-$suite"

arch=$(dpkg --print-architecture)

self_upstream='https://github.com/rockdrilla/pod-scripts/debian-minbase.sh'
own_ver() {
	local d=$(dirname "$0")
	git -C "$d" rev-parse --short HEAD 2>/dev/null || return 0
}
self_version=$(own_ver "$0")

pkg_ver() { dpkg-query --showformat='${Version}' --show "$1"; }
mmdebstrap_version=$(pkg_ver mmdebstrap)
buildah_version=$(pkg_ver buildah)
podman_version=$(pkg_ver podman)


ts=$(date '+%s')
export SOURCE_DATE_EPOCH=$ts

tag=$(date '+%Y%m%d%H%M%S' -d @$ts)

tarball=$(mktemp -u)'.tar'

## hack for libpam-tmpdir : we need 'shared' /tmp not per-user one :)
orig_tmp=$TMPDIR ; TMPDIR=/tmp TEMPDIR=/tmp TMP=/tmp TEMP=/tmp

chroot_postsetup_script=$(mktemp)
{
## generic setup
cat <<-'EOZ'
	#!/bin/sh
	set -e

	## setup additional repositories
	for i in stable testing unstable experimental ; do
		echo "deb http://deb.debian.org/debian $i main contrib non-free"
	done > "$1/etc/apt/sources.list"
	chmod 0644 "$1/etc/apt/sources.list"

	## setup repo priorities
	cat >"$1/etc/apt/preferences.d/00-local" <<EOF
	Package: *
	Pin: release o=debian, a=unstable
	Pin-Priority: 700

	Package: *
	Pin: release o=debian, a=testing
	Pin-Priority: 650

	Package: *
	Pin: release o=debian, a=stable
	Pin-Priority: 600

	Package: *
	Pin: release o=debian, a=experimental
	Pin-Priority: 550
	EOF
	chmod 0644 "$1/etc/apt/preferences.d/00-local"

	## prevent services from auto-starting
	cat > "$1/usr/sbin/policy-rc.d" <<-'EOF'
	#!/bin/sh
	exit 101
	EOF
	chmod 0755 "$1/usr/sbin/policy-rc.d"

	## always report that we're in chroot (oh God, who's still using ischroot?..)
	chroot "$1" dpkg-divert --divert /usr/bin/ischroot.debianutils --rename /usr/bin/ischroot
	ln -s /bin/true "$1/usr/bin/ischroot"

	## configure debconf:
	## - never update man-db
	## - set TZ to UTC
	{
	cat <<EOF
		man-db  man-db/auto-update  false
		tzdata  tzdata/Areas        select  Etc
		tzdata  tzdata/Zones/Etc    select  UTC
	EOF
	} | chroot "$1" debconf-set-selections

	## ensure that there's no traces after dpkg's option "path-exclude"
	for i in "$1/usr/share/doc" "$1/usr/share/info" "$1/usr/share/man" "$1/usr/share/help" ; do
	    [ -d "$i" ] || continue
	    find "$i/" -xdev -mindepth 1 \
	      -delete
	done ; unset i
	i="$1/usr/share/locale" ; if [ -d "$i" ] ; then
	    find "$i/" -xdev -mindepth 1 \
	      '!' -iname locale.alias    \
	      -delete
	fi ; unset i

	## setup image cleanup scripts
	cat >"$1/.cleanup.sh" <<-'EOF'
		#!/bin/sh
		# SPDX-License-Identifier: BSD-3-Clause
		# (c) 2021, Konstantin Demin
		set -e
		run-parts --verbose --exit-on-error /.cleanup.d
	EOF
	chmod 0755 "$1/.cleanup.sh"

	mkdir -p "$1/.cleanup.d"
	chmod 0755 "$1/.cleanup.d"

	cat >"$1/.cleanup.d/$2" <<-'EOF'
		#!/bin/sh
		# SPDX-License-Identifier: BSD-3-Clause
		# (c) 2021, Konstantin Demin
		set -e

		## remove apt cache and lists
		for i in /var/lib/apt/lists /var/cache/apt/archives ; do
		    find $i/ -xdev -mindepth 1 -type f -delete
		    touch $i/lock
		    chown 0:0 $i/lock
		    chmod 0640 $i/lock
		done

		## truncate log files
		truncate -s 0 \
		  /var/log/faillog \
		  /var/log/lastlog

		## remove python cache
		find / -xdev -mindepth 1 -name '*.pyc' -type f -delete

		## remove stale files
		rm -f \
		  /var/cache/debconf/config.dat-old \
		  /var/cache/debconf/templates.dat-old \
		  /var/lib/aptitude/pkgstates.old \
		  /var/lib/dpkg/diversions-old \
		  /var/lib/dpkg/status-old \
		  /var/log/aptitude
	EOF
	chmod 0755 "$1/.cleanup.d/$2"

EOZ
## refresh aptitude/apt data
cat <<-EOZ
	## mark almost all packages as auto-installed and remove unneeded
	chroot "\$1" aptitude update
	chroot "\$1" aptitude forget-new
	chroot "\$1" aptitude --schedule-only hold $pkg_aux
	chroot "\$1" aptitude --schedule-only markauto '~i!~E!~M'
	chroot "\$1" aptitude --schedule-only unmarkauto $pkg_aux
	chroot "\$1" aptitude --schedule-only unhold $pkg_aux
	chroot "\$1" aptitude --assume-yes install
	chroot "\$1" aptitude clean

EOZ
## cleanup
cat <<-'EOZ'
	## run cleanup
	chroot "$1" sh -x -v /.cleanup.sh
EOZ
} > "$chroot_postsetup_script"
chmod 0755 "$chroot_postsetup_script"

cat >/dev/null <<-'EOZ'
EOZ
dpkg_opt_script=$(mktemp)
cat >"$dpkg_opt_script" <<-'EOZ'
	force-unsafe-io

	path-exclude=/usr/share/doc/*
	path-exclude=/usr/share/help/*
	path-exclude=/usr/share/info/*
	path-exclude=/usr/share/man/*

	path-include=/usr/share/locale/locale.alias
	path-exclude=/usr/share/locale/*

	path-exclude=/usr/share/aptitude/aptitude-defaults.*
	path-exclude=/usr/share/aptitude/help-*
	path-exclude=/usr/share/aptitude/mine-help-*
	path-exclude=/usr/share/aptitude/README.*
EOZ
chmod 0644 "$dpkg_opt_script"

apt_opt_script=$(mktemp)
cat >"$apt_opt_script" <<-'EOZ'
	APT::Sandbox::User "root";

	APT::Install-Recommends "0";

	Acquire::Languages "none";

	aptitude::UI::InfoAreaTabs "true";
EOZ
chmod 0644 "$apt_opt_script"

mmdebstrap \
  --verbose \
  --format=tar \
  --variant=minbase \
  --include="$pkg_aux" \
  --aptopt="$apt_opt_script" \
  --dpkgopt="$dpkg_opt_script" \
  --customize-hook="$chroot_postsetup_script \"\$1\" \"$image\"" \
  $suite "$tarball" || true

rm -f "$dpkg_opt_script" "$apt_opt_script" "$chroot_postsetup_script"
unset dpkg_opt_script apt_opt_script chroot_postsetup_script

tar -tf "$tarball" >/dev/null

## populate image name with arch
image="$image-$arch"

k=$(podman import "$tarball" "$image-temporary:$tag" || true)

rm -f "$tarball" ; unset tarball

[ -n "$k" ]

c=$(buildah from --format docker --pull-never --net host --uts container --security-opt=label=disable,seccomp=unconfined,apparmor=unconfined "$k" || true)
if [ -z "$c" ] ; then
	podman image rm "$k" || true
	exit 1
fi

buildah config --hostname debian "$c"
buildah config --comment "basic Debian image" "$c"
buildah config --label "unix_timestamp=$ts" "$c"
buildah config --label "script=$self_upstream${self_version:+@$self_version}" "$c"
buildah config --label "mmdebstrap=$mmdebstrap_version" "$c"
buildah config --label "podman=$podman_version" "$c"
buildah config --label "buildah=$buildah_version" "$c"
buildah config --onbuild="RUN sh /.cleanup.sh" "$c"
buildah config --env LANG=C.UTF-8 "$c"
buildah config --env LC_ALL=C.UTF8 "$c"
buildah config --env TERM=xterm-256color "$c"
buildah config --env TMPDIR=/tmp "$c"
buildah config --env TMP=/tmp "$c"
buildah config --env TEMPDIR=/tmp "$c"
buildah config --env TEMP=/tmp "$c"

if buildah commit --format docker --squash --timestamp $ts "$c" "$image:$tag" ; then
	podman image rm "$image:latest" || true
	podman image tag "$image:$tag" "$image"
fi

buildah rm "$c"
podman image rm "$k"

echo "$image has been built successfully"
