#!/bin/sh
set -e

## $1 - chroot path
## $2 - suite name
## $3 - packages
## $4 - uid
## $5 - gid

## fix ownership:
## mmdebstrap's actions 'sync-in' and 'copy-in' preserves source user/group
chroot "$1" find / -xdev -uid $4 -exec chown 0:0 {} +
chroot "$1" find / -xdev -gid $5 -exec chown 0:0 {} +

## setup debconf frontend via environment
export DEBIAN_FRONTEND=noninteractive

## setup repositories and their priorities
comp='main contrib non-free'
prio=500 ; aux_repo=''
case "$2" in
stable)
	aux_repo='$2-updates $2-proposed-updates $2-backports'
	## setup repositories
	{
	for i in $2 $aux_repo ; do
		echo "deb http://deb.debian.org/debian $i $comp"
	done
	echo "deb http://security.debian.org/debian-security $2/updates $comp"
	} > "$1/etc/apt/sources.list"
	chmod 0644 "$1/etc/apt/sources.list"

	aux_repo=''
;;
testing)      prio=550 ; aux_repo='stable unstable' ;;
unstable)     prio=600 ; aux_repo='testing stable experimental' ;;
experimental) prio=650 ; aux_repo='unstable testing stable' ;;
esac

if [ -n "$aux_repo" ] ; then
	## setup repositories
	for i in $2 $aux_repo ; do
		echo "deb http://deb.debian.org/debian $i $comp"
	done > "$1/etc/apt/sources.list"
	chmod 0644 "$1/etc/apt/sources.list"

	set +f

	## setup repo priorities
	for i in $2 $aux_repo ; do
		cat <<-EOF
			Package: *
			Pin: release o=debian, a=$i
			Pin-Priority: $prio

		EOF
		prio=$(( prio - 50 ))
	done > "$1/etc/apt/preferences.d/00-local"
	chmod 0644 "$1/etc/apt/preferences.d/00-local"

	set -f
fi

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

## mark most non-essential packages as auto-installed
apti_cmd() { echo "aptitude $@ ;" ; }
c="$c "$(apti_cmd --schedule-only hold $3)
c="$c "$(apti_cmd --schedule-only markauto '~i!~E!~M')
c="$c "$(apti_cmd --schedule-only unmarkauto $3)
c="$c "$(apti_cmd --schedule-only unhold $3)
c="$c "$(apti_cmd --assume-yes install)
chroot "$1" sh -e -c "$c"

## remove mmdebstrap artifacts
rm \
  "$1/etc/apt/apt.conf.d/99mmdebstrap" \
  "$1/etc/dpkg/dpkg.cfg.d/99mmdebstrap"

## run cleanup
chroot "$1" sh /.cleanup.sh
