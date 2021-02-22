#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin
set -e

suite=sid
pkg_aux='apt-utils aptitude e-wrapper gawk less lsof vim-tiny'
pkg_auto='bash-completion dialog'
image="debian-minbase-$suite"

arch=$(dpkg --print-architecture)

repo_base='https://github.com/rockdrilla/pod-scripts'
repo_contact="$repo_base/issues/new/choose"
self_upstream="$repo_base.git /debian-minbase.sh"

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

	## install vim-tiny as variant for vim
	vim=/usr/bin/vim
	chroot "$1" update-alternatives --install $vim vim $vim.tiny 1

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
		set -x -v

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
{ cat <<-EOF
	update
	forget-new
	--schedule-only hold $pkg_aux
	--schedule-only markauto '~i!~E!~M'
	--schedule-only unmarkauto $pkg_aux
	--schedule-only unhold $pkg_aux
	--assume-yes install
EOF
} | sed -E 's/^/aptitude /' | paste -sd';' \
  | sed -E 's/^(.*)$/\1;apt-cache gencaches/' \
  | sed -E 's/^(.*)$/chroot "$1" sh -e -c "\1"/'
## cleanup
cat <<-'EOZ'
	## run cleanup
	chroot "$1" sh /.cleanup.sh
EOZ
} > "$chroot_postsetup_script"
chmod 0755 "$chroot_postsetup_script"

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

	APT::Install-Recommends "false";

	Acquire::Languages "none";

	aptitude::UI::InfoAreaTabs "true";
EOZ
chmod 0644 "$apt_opt_script"

mmdebstrap \
  --verbose \
  --format=tar \
  --variant=minbase \
  --include="$pkg_aux $pkg_auto" \
  --aptopt="$apt_opt_script" \
  --dpkgopt="$dpkg_opt_script" \
  --customize-hook="$chroot_postsetup_script \"\$1\" \"$image\"" \
  $suite "$tarball" || true

rm -f "$dpkg_opt_script" "$apt_opt_script" "$chroot_postsetup_script"
unset dpkg_opt_script apt_opt_script chroot_postsetup_script

tar -tf "$tarball" >/dev/null

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
bc --author "contact @ $repo_contact"
bc --created-by "$self_upstream${self_version:+ @$self_version}"
bc --label "unix_timestamp=$ts"
bc --label "mmdebstrap=$mmdebstrap_version"
bc --label "podman=$podman_version"
bc --label "buildah=$buildah_version"
bc --onbuild="RUN : please issue 'sh /.cleanup.sh'"
bc --onbuild="RUN : as last RUN command in your images"
bc --onbuild="RUN : and consider keeping these hints"
bc --onbuild="RUN : within ONBUILD RUN further"
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

if buildah commit --squash --timestamp $ts "$c" "$image:$tag" ; then
	podman image rm "$image:latest" || true
	podman image tag "$image:$tag" "$image"
fi

buildah rm "$c"
podman image rm "$k"

echo "$image has been built successfully"
