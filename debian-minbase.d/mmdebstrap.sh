#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin
set -e

## $1 - chroot path
## $2 - image name
## $3 - suite name
## $4 - packages
## $5 - uid
## $6 - gid

## read environment from file (except PATH)
f_env=$(dirname "$0")'/env.sh'
t_env=$(mktemp)
grep -Ev '^(#|$)' < "${f_env}" > "${t_env}"
while read L ; do
	case "$L" in
	PATH=*) ;;
	*) export "$L" ;;
	esac
done < "${t_env}"
rm -f "${t_env}"

## fix ownership:
## mmdebstrap's actions 'sync-in' and 'copy-in' preserves source user/group
chroot "$1" find / -xdev -uid $5 -exec chown 0:0 {} +
chroot "$1" find / -xdev -gid $6 -exec chown 0:0 {} +

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

## install vim-tiny as variant for vim
vim=/usr/bin/vim
chroot "$1" update-alternatives --install ${vim} vim ${vim}.tiny 1

## install e-wrapper directly from GitHub
curl -sSL https://raw.githubusercontent.com/kilobyte/e/master/e > "$1/usr/local/bin/e"
chroot "$1" chmod 0755 /usr/local/bin/e

## man-db:
## - disable auto-update
## - disable install setuid
{ cat <<-EOF
	man-db  man-db/auto-update     boolean  false
	man-db  man-db/install-setuid  boolean  false
EOF
} | chroot "$1" debconf-set-selections
rm -f "$1/var/lib/man-db/auto-update"

## timezone
chroot "$1" /opt/tz.sh "${TZ}"

## perform full upgrade
c=':'
c="$c ; aptitude update || :"
c="$c ; aptitude -y full-upgrade"
chroot "$1" sh -e -c "$c"

## remove (unnecessary) e2fs packages
chroot "$1" dpkg --force-all --purge e2fsprogs libext2fs2 libss2 logsave || :

## remove (unnecessary) fdisk packages
chroot "$1" dpkg --force-all --purge fdisk libfdisk1 || :

## mark most non-essential packages as auto-installed
c=':'
c="$c ; aptitude --schedule-only hold $4"
c="$c ; aptitude --schedule-only markauto '~i!~E!~M'"
c="$c ; aptitude --schedule-only unmarkauto $4"
c="$c ; aptitude --schedule-only unhold $4"
c="$c ; aptitude -y install"
chroot "$1" sh -e -c "$c"

## remove mmdebstrap artifacts
rm \
  "$1/etc/apt/apt.conf.d/99mmdebstrap" \
  "$1/etc/dpkg/dpkg.cfg.d/99mmdebstrap"

## run cleanup
chroot "$1" /opt/cleanup.sh

## eliminate empty directories under certain paths
for i in \
/usr/share/doc/ \
/usr/share/help/ \
/usr/share/info/ \
/usr/share/man/ \
/usr/share/locale/ \
; do [ -d "$1/$i" ] || continue ; \
chroot "$1" find "$i" -xdev -mindepth 1 -maxdepth 1 -type d -exec /opt/tree-opt.sh '{}' ';' ; done
