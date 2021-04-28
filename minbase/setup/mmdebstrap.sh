#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

set -e

## auxiliary packages to be installed
pkg_manual='lsof ncurses-base procps tzdata'
pkg_auto='whiptail'

## script parameters:
## $1 - chroot path
## $2 - image name
## $3 - suite name
## $4 - uid
## $5 - gid

## read environment from file (except PATH)
f_env=$(dirname "$0")'/../env.sh'
t_env=$(mktemp)
grep -Ev '^(#|$)' < "${f_env}" > "${t_env}"
while read L ; do
	case "$L" in
	PATH=*) ;;
	*) export "$L" ;;
	esac
done < "${t_env}"
rm -f "${t_env}"

## strip apt keyrings from sources.list:
sed -E -i 's/ \[[^]]+]//' "$1/etc/apt/sources.list"

## setup repositories and their priorities
case "$2" in
ubuntu*)
	comp='main restricted universe multiverse'
	aux_repo="$3-updates $3-proposed"
	## setup repositories
	{
	for i in $3 ${aux_repo} ; do
		echo "deb http://archive.ubuntu.com/ubuntu $i ${comp}"
	done
	echo "deb http://security.ubuntu.com/ubuntu $3-security ${comp}"
	} > "$1/etc/apt/sources.list"
	chmod 0644 "$1/etc/apt/sources.list"

	aux_repo=''
;;
debian*)
	comp='main contrib non-free'
	prio=500 ; aux_repo=''
	case "$3" in
	testing)      prio=550 ; aux_repo='stable unstable' ;;
	unstable)     prio=600 ; aux_repo='testing stable experimental' ;;
	experimental) prio=650 ; aux_repo='unstable testing stable' ;;
	*)
		aux_repo="$3-updates $3-proposed-updates"
		## setup repositories
		{
		for i in $3 ${aux_repo} ; do
			echo "deb http://deb.debian.org/debian $i ${comp}"
		done
		echo "deb http://security.debian.org/debian-security $3/updates ${comp}"
		} > "$1/etc/apt/sources.list"
		chmod 0644 "$1/etc/apt/sources.list"

		aux_repo=''
	;;
	esac

	if [ -n "${aux_repo}" ] ; then
		## setup repositories
		for i in $3 ${aux_repo} ; do
			echo "deb http://deb.debian.org/debian $i ${comp}"
		done > "$1/etc/apt/sources.list"
		chmod 0644 "$1/etc/apt/sources.list"

		set +f

		## setup repo priorities
		for i in $3 ${aux_repo} ; do
			cat <<-EOF
				Package: *
				Pin: release o=debian, a=$i
				Pin-Priority: ${prio}

			EOF
			prio=$(( prio - 50 ))
		done > "$1/etc/apt/preferences.d/00-local"
		chmod 0644 "$1/etc/apt/preferences.d/00-local"

		set -f
	fi
;;
esac

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



## update package lists; may fail sometimes,
## e.g. soon-to-release channels like Debian "bullseye" @ 22.04.2021
chroot "$1" apt update || :

## install apt-utils first, then aptitude
chroot "$1" apt -y install apt-utils
chroot "$1" apt -y install aptitude

## perform full upgrade
chroot "$1" aptitude -y full-upgrade

## install auxiliary packages
chroot "$1" aptitude -y install ${pkg_manual} ${pkg_auto}

## mark most non-essential packages as auto-installed
c=':'
c="$c ; aptitude --schedule-only hold ${pkg_manual}"
c="$c ; aptitude --schedule-only markauto '~i!~E!~M'"
c="$c ; aptitude --schedule-only unmarkauto ${pkg_manual}"
c="$c ; aptitude --schedule-only unhold ${pkg_manual}"
c="$c ; aptitude -y install"
chroot "$1" sh -e -c "$c"



## timezone
chroot "$1" /opt/tz.sh "${TZ}"



## run cleanup
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
	chroot "$1" find "$i" -xdev -mindepth 1 -maxdepth 1 -type d -exec /opt/tree-opt.sh '{}' ';'
done

## fix ownership:
## mmdebstrap's actions 'sync-in' and 'copy-in' preserves source user/group
chroot "$1" find / -xdev -uid $4 -exec chown 0:0 {} +
chroot "$1" find / -xdev -gid $5 -exec chown 0:0 {} +
