#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin
set -f

######################################################################
## script internals

## special magic with separator for sed "s" command
## char 027 (0x17) seems to be safe separator for sed "s" command;
## idea taken from Debian src:nginx/debian/dh_nginx
X=$(command printf '\027')

## $1 - match
## $2 - replacement
## $3 - flags (optional)
repl() { command printf "s${X}%s${X}%s${X}%s" "$1" "$2" "$3" ; }

esc_dots=$( repl '\.' '\\.' g )
esc_qmarks=$( repl '([^\]|^)\?' '\1.' g )

esc_head=$( repl '^\*{2}/' '.+/' g )
esc_tail=$( repl '/\*{2}$' '(/.+)?' g )
esc_mid=$( repl '(/|^)\*{2}(/|$)' '\1(.+\2)?' g )
esc_any=$( repl '([^*]|^)\*{2}([^*]|$)' '\1.+\2' g )
esc_double_star="${esc_head};${esc_tail};${esc_mid};${esc_any}"

esc_mid=$( repl '(/|^)\*(/|$)' '\1[^/]+\2' g )
esc_any=$( repl '([^*]|^)\*([^*]|$)' '\1[^/]*\2' g )
esc_single_star="${esc_mid};${esc_any}"

esc_stars="${esc_double_star};${esc_single_star}"

trim_dup_slashes=$(repl '//+' '/' g)

## TODO: discover more cases

esc_all="${esc_dots};${esc_qmarks};${esc_stars};${trim_dup_slashes}"

rx_glob_esc() { printf '%s' "$1" | sed -E "${esc_all};" ; }

add_anchors=$( repl '^(.+)$' '^\1$' g )

## set sail... or not :D
rx_glob_moor() { printf '%s' "$1" | sed -E "${add_anchors};" ; }

rx_glob() { printf '%s' "$1" | sed -E "${esc_all};${add_anchors};" ; }

test_regex() { sed -En "\\#$1#p" </dev/null ; }

######################################################################
## script itself

sysroot_skiplist='^/(sys|proc|dev)$'
cfg_stanza='^(delete|keep)=(.+)$'

## recursion: turn glob to regex and then into file list 
## (symlinks are listed too!)
case "$1" in
--delete|--keep)
	## $1 - action (delete / keep)
	## $2 - path glob (one argument!)

	action="${1#--}"
	path_glob="$2"

	x=$(printf '%s' "$2" | cut -c 1)
	if [ "$x" != '/' ] ; then
		path_glob="${TOPMOST_D}/${path_glob}"
	fi

	path_regex=$(rx_glob "${path_glob}")
	if ! test_regex "${path_regex}" ; then
		cat 1>&2 <<-EOF
		Bad regex was produced from glob:
		  directory: ${TOPMOST_D}
		  glob: $2
		  regex: ${path_regex}

		Please report this case to developers.
		EOF
		exit 1
	fi

	result=$(mktemp -p "${RESULT_D}" "${action}.XXXXXXXX")

	if [ "$x" = '/' ] ; then
		## absolute glob is searched FS-wide
		find / -mindepth 1 -maxdepth 1 -type d -print0 \
		| grep -zEv "${sysroot_skiplist}" \
		| xargs -0 -r -I'^^' \
		  find '^^' -mindepth 1 -regextype egrep \
		  -regex "${path_regex}" '!' -type d
	else
		## relative glob is searched under topmost directory
		find "${TOPMOST_D}" -mindepth 1 -regextype egrep \
		-regex "${path_regex}" '!' -type d
	fi > "${result}"

	exit 0
;;
esac

# topmost="$1"
conf="/dev/stdin"
case "$#" in
1) ;;
2) [ "$2" != '-' ] && conf="$2" ;;
*) exit 1 ;;
esac

if ! [ -r "${conf}" ] ; then
	exit 1
fi

## reformat rules them like "--(delete|keep)\0selector\0"
trun=$(mktemp)
grep -E "${cfg_stanza}" \
< "${conf}" \
| sort -uV \
| sed -En "/${cfg_stanza}/{s//--\\1\\n\\2/;p;}" \
| tr '\n' '\0' \
> "${trun}"

## nothing to filter at all
if ! [ -s "${trun}" ] ; then
	rm -f "${trun}"
	exit 0
fi

## run ourself recursively and store results in directory
if [ -z "${NPROC}" ] ; then
	NPROC=$(nproc)
	NPROC=$(( NPROC + (NPROC+1)/2 ))
fi

tparts=$(mktemp -d)

env TOPMOST_D="$1" RESULT_D="${tparts}" \
xargs -0 -n 2 -P "${NPROC}" "$0" \
< "${trun}"

rm -f "${trun}" ; unset trun

## merge results to "save list"
tKEEP=$(mktemp)
find "${tparts}/" -mindepth 1 -name 'keep.*' -exec cat '{}' '+' \
| sort -uV > "${tKEEP}"

## merge results to "remove list"
tDELETE=$(mktemp)
find "${tparts}/" -mindepth 1 -name 'delete.*' -exec cat '{}' '+' \
| sort -uV > "${tDELETE}"

rm -rf "${tparts}" ; unset tparts

## nothing to filter at all (again)
if ! [ -s "${tDELETE}" ] ; then
	rm -f "${tKEEP}" "${tDELETE}"
	exit 0
fi

## filter out files in "save list"
tremove=$(mktemp)
if [ -s "${tKEEP}" ]
then grep -Fxv -f "${tKEEP}"
else cat
fi < "${tDELETE}" \
| tr '\n' '\0' \
> "${tremove}"

rm -f "${tKEEP}" "${tDELETE}" ; unset tKEEP tDELETE

## nothing to filter at all (again?)
if ! [ -s "${tremove}" ] ; then
	rm -f "${tremove}"
	exit 0
fi

## remove files already!
## ... or not if env DRY is not empty :)
if [ -n "${DRY}" ] ; then
	cat <<-EOF
	## ENV DRY=${DRY} was specified, no files are removed!
	matched files:
	EOF
	tr '\0' '\n'
else
	if [ -n "${PIPELINE}" ] ; then
		cat
	else
		xargs -0 -r rm -f
	fi
fi < "${tremove}"

rm -f "${tremove}" ; unset tremove
