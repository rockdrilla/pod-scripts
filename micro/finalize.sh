#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

[ -x /usr/bin/aptitude ] || exit 1

## bad, really bad things are done here...

{
	echo /var/lib/dpkg/status
	find /var/lib/apt/lists/ -type f
} | xargs -r sed -i -E 's/^(Priority:) (important|required)$/\1 standard/;'

list() { aptitude --schedule-only --disable-columns -F '%p' search "$@" 2>/dev/null ; }
batch() { aptitude --schedule-only "$@" >/dev/null 2>/dev/null ;  }
remove() { batch remove "$@" ; }

if [ $# -ne 0 ] ; then
	batch keep "$@"
	batch install "$@"
fi

dangling='~i~M!~aremove?and(~Rdepends:~aremove,!~Rdepends:!~aremove)'

remove '~i~e^(apt|aptitude|dpkg|less|nano|vim)$'
remove '~i~n^(adduser|debconf|dialog|login|mount|ncurses-term|passwd|sensible-utils|whiptail)$'

if [ $# -ne 0 ] ; then
	batch keep "$@"
	batch install "$@"
fi

while : ; do
	n=$(list "${dangling}" | wc -l)
	[ "$n" = "0" ] && break
	echo "dangling: " $(list "${dangling}")
	remove $(list "${dangling}")
done

victims=$(list '~aremove' | xargs -r)

echo "decided to remove: ${victims}"
echo "decided to keep:" $(list '?or(~i~akeep,~ainstall)' | xargs -r)

echo "generic cleanup:"
/opt/cleanup.sh

echo "finalize image:"

## filesystem usage before wipe
du -xs /

## remove files/symlinks
echo ${victims} | tr ' ' '\n' \
| xargs -r -I {} find /var/lib/dpkg/info/ \
    -name '{}.conffiles' \
    -o -name '{}.list' \
    -o -name '{}:*conffiles' \
    -o -name '{}:*list' \
| xargs -r -n 1 cat \
| sort -uV \
| xargs -r -d '\n' -n 1 ls -1d 2>/dev/null \
| sort -uV \
| xargs -r -d '\n' -n 1 stat -c '%F|%n' 2>/dev/null \
| grep -Ev '^directory\|' \
| cut -d '|' -f 2 \
| xargs -r -d '\n' -n 1 rm -f

## remove dangling symlinks
find -L / -xdev -type l -delete

## remove directories
rm -rf \
	/etc/apt \
	/etc/dpkg \
	/var/lib/dpkg \
	/var/cache/debconf \
	/var/cache/apt \
	/var/lib/apt \
	/var/lib/aptitude \

## remove non-working scripts
rm -rf \
	/opt/cleanup.d \
	/opt/cleanup.sh \
	/opt/interactive.sh

## remove empty directories
/opt/tree-opt.sh /lib
/opt/tree-opt.sh /usr/lib
/opt/tree-opt.sh /usr/share

## filesystem usage after wipe
du -xs /
