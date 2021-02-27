#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin
set -e

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


ts=$(date '+%s')
export SOURCE_DATE_EPOCH=$ts

tag=$(date '+%Y%m%d%H%M%S' -d @$ts)

tarball=$(mktemp -u)'.tar'

## hack for libpam-tmpdir : we need 'shared' /tmp not per-user one :)
orig_tmp=$TMPDIR ; TMPDIR=/tmp TEMPDIR=/tmp TMP=/tmp TEMP=/tmp

chroot_postsetup_script=$(mktemp)
{
cat <<-'EOZ'
	#!/bin/sh
	set -e

	export DEBIAN_FRONTEND=noninteractive

EOZ
## setup repositories and their priorities
comp='main contrib non-free'
prio=500 ; aux_repo=''
case "$suite" in
stable)
	aux_repo='stable-updates stable-proposed-updates stable-backports'
	cat <<-EOZ
		## setup repositories
		{
		for i in $suite $aux_repo ; do
		    echo "deb http://deb.debian.org/debian \$i $comp"
		done
		echo "deb http://security.debian.org/debian-security stable/updates $comp"
		} > "\$1/etc/apt/sources.list"
		chmod 0644 "\$1/etc/apt/sources.list"

	EOZ
	aux_repo=''
;;
testing)      prio=550 ; aux_repo='stable unstable' ;;
unstable)     prio=600 ; aux_repo='testing stable experimental' ;;
experimental) prio=650 ; aux_repo='unstable testing stable' ;;
esac
if [ -n "$aux_repo" ] ; then
	cat <<-EOZ
		## setup repositories
		for i in $suite $aux_repo ; do
		    echo "deb http://deb.debian.org/debian \$i $comp"
		done > "\$1/etc/apt/sources.list"
		chmod 0644 "\$1/etc/apt/sources.list"
	EOZ
	cat <<-'EOZ'
		## setup repo priorities
		set +f
		cat >"$1/etc/apt/preferences.d/00-local" <<EOF
	EOZ
	set +f
	for i in $suite $aux_repo ; do
		cat <<-EOZ
			Package: *
			Pin: release o=debian, a=$i
			Pin-Priority: $prio

		EOZ
		prio=$(( prio - 50 ))
	done
	set -f
	cat <<-'EOZ'
		EOF
		set -f
		chmod 0644 "$1/etc/apt/preferences.d/00-local"

	EOZ
fi
## generic configuration
cat <<-'EOZ'
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
		man-db  man-db/auto-update  boolean false
		tzdata  tzdata/Areas        select  Etc
		tzdata  tzdata/Zones/Etc    select  UTC
	EOF
	} | chroot "$1" debconf-set-selections
	rm -f "$1/var/lib/man-db/auto-update"

EOZ
## mark most non-essential packages as auto-installed
{ cat <<-EOF
	--schedule-only hold $pkg_aux
	--schedule-only markauto '~i!~E!~M'
	--schedule-only unmarkauto $pkg_aux
	--schedule-only unhold $pkg_aux
	--assume-yes install
EOF
} | sed -E 's/^/aptitude /' | paste -sd';' \
  | sed -E 's/^(.*)$/chroot "$1" sh -e -c "\1"/'
## configure apt/dpkg
set +f
cat <<-'EOZ'
	set +f

	## remove mmdebstrap artifacts
	rm \
	  "$1/etc/apt/apt.conf.d/99mmdebstrap" \
	  "$1/etc/dpkg/dpkg.cfg.d/99mmdebstrap"

	## setup dpkg configuration
	cat > "$1/etc/dpkg/dpkg.cfg.d/00-base" <<-'EOF'
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
	EOF

	## setup apt configuration
	cat > "$1/etc/apt/apt.conf.d/00-base" <<-'EOF'
		APT::Sandbox::User "root";

		APT::Install-Recommends "false";

		Acquire::Languages "none";

		aptitude::UI::InfoAreaTabs "true";
	EOF

	set -f

EOZ
set -f
## base image cleanup
cat <<-'EOZ'
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
	find "$1/usr/share/aptitude/" -mindepth 1 -print0 | \
	grep -zE '/((aptitude-defaults|README)\.|(help|mine-help)-).*' | \
	xargs -0 -r rm -rf

	## force package reconfigure
	chroot "$1" sh -c "aptitude --display-format '%p' search '~i' | xargs -r dpkg-reconfigure --force"

EOZ
## image cleanup infrastructure
set +f
cat <<-'EOZ'
	set +f

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

	cat >"$1/.cleanup.d/apt-dpkg-related" <<-'EOF'
		#!/bin/sh
		# SPDX-License-Identifier: BSD-3-Clause
		# (c) 2021, Konstantin Demin
		set -e -x -v

		## remove apt cache and lists
		for i in /var/lib/apt/lists /var/cache/apt/archives ; do
		    find $i/ -mindepth 1 -type f -delete
		    install -o 0 -g 0 -m 0640 /dev/null $i/lock
		done
		apt-get clean

		## remove directories
		rm -rf \
		  /var/lib/apt/lists/auxfiles

		## remove files
		rm -f \
		  /var/cache/apt/pkgcache.bin \
		  /var/cache/apt/srcpkgcache.bin \
		  /var/lib/aptitude/pkgstates
	EOF

	cat >"$1/.cleanup.d/ldconfig-auxcache" <<-'EOF'
		#!/bin/sh
		# SPDX-License-Identifier: BSD-3-Clause
		# (c) 2021, Konstantin Demin
		set -e -x -v

		## remove files
		rm -f /var/cache/ldconfig/aux-cache
	EOF

	cat >"$1/.cleanup.d/logs" <<-'EOF'
		#!/bin/sh
		# SPDX-License-Identifier: BSD-3-Clause
		# (c) 2021, Konstantin Demin
		set -e -x -v

		## remove apt logs
		find /var/log/apt/ -mindepth 1 -delete

		## remove stale logs
		find /var/log/ -mindepth 1 -type f -print0 | \
		grep -zE '\.([0-9]+|old|gz|bz2|xz|zst)$' | \
		xargs -0 -r rm -rf

		## remove files
		rm -f \
		  /var/log/alternatives.log \
		  /var/log/aptitude \
		  /var/log/dpkg.log

		## truncate files
		truncate -s 0 \
		  /var/log/btmp \
		  /var/log/faillog \
		  /var/log/lastlog \
		  /var/log/wtmp
	EOF

	cat >"$1/.cleanup.d/machine-id" <<-'EOF'
		#!/bin/sh
		# SPDX-License-Identifier: BSD-3-Clause
		# (c) 2021, Konstantin Demin
		set -e -x -v

		## remove files
		rm -f \
		  /etc/machine-id \
		  /var/lib/dbus/machine-id

		## install empty files
		install -o 0 -g 0 -m 0444 /dev/null /etc/machine-id
	EOF

	cat >"$1/.cleanup.d/python-cache" <<-'EOF'
		#!/bin/sh
		# SPDX-License-Identifier: BSD-3-Clause
		# (c) 2021, Konstantin Demin
		set -e -x -v

		## treewide remove python bytecode cache
		find / -mindepth 1 -maxdepth 1 -type d -print0 | \
		grep -zEv '^/(sys|proc|dev)$' | \
		xargs -t -0 -r -I'{}' \
		  find '{}' -mindepth 1 -name '*.pyc' -type f -delete
	EOF

	cat >"$1/.cleanup.d/stale" <<-'EOF'
		#!/bin/sh
		# SPDX-License-Identifier: BSD-3-Clause
		# (c) 2021, Konstantin Demin
		set -e -x -v

		## remove files
		rm -f \
		  /var/cache/debconf/config.dat-old \
		  /var/cache/debconf/templates.dat-old \
		  /var/lib/aptitude/pkgstates.old \
		  /var/lib/dpkg/diversions-old \
		  /var/lib/dpkg/status-old
	EOF

	cat >"$1/.cleanup.d/tmp" <<-'EOF'
		#!/bin/sh
		# SPDX-License-Identifier: BSD-3-Clause
		# (c) 2021, Konstantin Demin
		set -e -x -v

		## list before unlinking
		find /tmp -mindepth 1 -ls -delete
	EOF

	## mark directory and all scripts as executable
	find "$1/.cleanup.d/" -exec chmod 0755 '{}' '+'

	set -f

EOZ
set -f
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
EOZ
chmod 0644 "$dpkg_opt_script"

apt_opt_script=$(mktemp)
cat >"$apt_opt_script" <<-'EOZ'
	APT::Sandbox::User "root";

	APT::Install-Recommends "false";

	Acquire::Languages "none";
EOZ
chmod 0644 "$apt_opt_script"

mmdebstrap \
  --verbose \
  --format=tar \
  --variant=minbase \
  --include="$pkg_aux $pkg_auto" \
  --aptopt="$apt_opt_script" \
  --dpkgopt="$dpkg_opt_script" \
  --customize-hook="$chroot_postsetup_script" \
  --skip=cleanup/apt \
  $suite "$tarball" || true

rm -f "$dpkg_opt_script" "$apt_opt_script" "$chroot_postsetup_script"
unset dpkg_opt_script apt_opt_script chroot_postsetup_script

tar -tf "$tarball" >/dev/null

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
bc --env PAGER=less
bc --env LESS=FRS

if buildah commit --squash --timestamp $ts "$c" "$image:$tag" ; then
	podman image rm "$image:latest" || true
	podman image tag "$image:$tag" "$image"
fi

buildah rm "$c"
podman image rm "$k"

echo "$image has been built successfully"
