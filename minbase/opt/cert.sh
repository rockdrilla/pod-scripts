#!/bin/sh
set -f

dst='/usr/local/share/ca-certificates'

[ $# -gt 1 ] || exit 1

d="${dst}/$1" ; shift
[ -d "$d" ] || mkdir -p "$d"

find "${dst}/" -xdev -type d -exec chmod 0755 {} +

/opt/apt.sh install ca-certificates

find "$d/" -xdev -mindepth 1 -delete

t=$(mktemp)

for uri ; do
	: > "$t"

	if printf '%s' "${uri}" | grep -Eiq '^(file|https?)://' ; then
		if ! command -V curl ; then
			/opt/apt.sh install curl
		fi
		curl -sSL -o "$t" "${uri}" || continue
	else
		cat < "${uri}" > "$t" || continue
	fi

	## received file is empty - nothing to do
	[ -s "$t" ] || continue

	x=$(grep -En '^-----(BEGIN|END) ' "$t" \
		| cut -d ':' -f 1 \
		| xargs -r -n 2 \
		| tr ' ' ':' )
	if [ -n "$x" ] ; then
		## received file looks like PEM
		while IFS=':' read -r start end ; do
			f=$(mktemp -p "$d" "XXXXXXXX.pem")
			sed -En "${start},${end}p" < "$t" > "$f"
			chmod 0644 "$f"
		done <<-EOF
		$x
		EOF
	else
		## received file looks doesn't look like PEM
		f=$(mktemp -p "$d" "XXXXXXXX.crt")
		cat < "$t" > "$f"
		chmod 0644 "$f"
	fi
done

rm -f "$t"

update-ca-certificates --fresh
