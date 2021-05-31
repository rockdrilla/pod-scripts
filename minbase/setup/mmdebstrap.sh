#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

set -e

chroot "$1" /opt/cleanup.d/dpkg-path-filter

## auxiliary packages to be installed
pkg_aux='lsof ncurses-base procps tzdata vim-tiny whiptail'

## script parameters:
## $1 - chroot path
## $2 - distro name
## $3 - suite name
## $4 - uid
## $5 - gid

## read environment from file (except PATH)
f_env=$(dirname "$0")'/../env.sh'
t_env=$(mktemp)
grep -Ev '^(#|$)' < "${f_env}" > "${t_env}"
while read -r L ; do
	case "$L" in
	PATH=*) ;;
	*) export "$L" ;;
	esac
done < "${t_env}"
rm -f "${t_env}"

## strip apt keyrings from sources.list:
sed -E -i 's/ \[[^]]+]//' "$1/etc/apt/sources.list"

## generic configuration

## prevent services from auto-starting
cat > "$1/usr/sbin/policy-rc.d" <<-'EOF'
	#!/bin/sh
	exit 101
EOF
chmod 0755 "$1/usr/sbin/policy-rc.d"

## always report that we're in chroot (oh God, who's still using ischroot?..)
chroot "$1" dpkg-divert --divert /usr/bin/ischroot.debianutils --rename /usr/bin/ischroot
ln -s /bin/true "$1/usr/bin/ischroot"

## man-db:
## - disable auto-update
## - disable install setuid
{ cat <<-EOF
	man-db  man-db/auto-update     boolean  false
	man-db  man-db/install-setuid  boolean  false
EOF
} | chroot "$1" debconf-set-selections
rm -f "$1/var/lib/man-db/auto-update"


## perform full upgrade
chroot "$1" /opt/apt.sh full-upgrade

## install auxiliary packages (aptitude is installed too)
chroot "$1" /opt/apt.sh install ${pkg_aux}

## mark most non-essential packages as auto-installed
c=':'
c="$c ; aptitude --schedule-only hold ${pkg_aux}"
c="$c ; aptitude --schedule-only markauto '~i!~E!~M'"
c="$c ; aptitude --schedule-only unmarkauto ${pkg_aux}"
c="$c ; aptitude --schedule-only unhold ${pkg_aux}"
c="$c ; aptitude -y install"
chroot "$1" sh -e -c "$c"



## timezone
chroot "$1" /opt/tz.sh "${TZ}"

## install vim-tiny as variant for vim
vim=/usr/bin/vim
chroot "$1" update-alternatives --install ${vim} vim ${vim}.tiny 1



## run cleanup (aptitude is to be removed)
chroot "$1" /opt/cleanup.sh

## remove mmdebstrap artifacts
rm -f \
  "$1/etc/apt/apt.conf.d/99mmdebstrap" \
  "$1/etc/dpkg/dpkg.cfg.d/99mmdebstrap"

## eliminate empty directories under certain paths
for i in \
/usr/share/doc/ \
/usr/share/help/ \
/usr/share/info/ \
/usr/share/man/ \
/usr/share/locale/ \
; do
	[ -d "$1/$i" ] || continue
	chroot "$1" \
	find "$i" -xdev -mindepth 1 -maxdepth 1 -type d -exec /opt/tree-opt.sh '{}' ';'
done

## fix ownership:
## mmdebstrap's actions 'sync-in' and 'copy-in' preserves source user/group
chroot "$1" find / -xdev -uid $4 -exec chown 0:0 {} +
chroot "$1" find / -xdev -gid $5 -exec chown 0:0 {} +
