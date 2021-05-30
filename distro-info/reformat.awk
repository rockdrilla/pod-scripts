#!/usr/bin/env gawk
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

## input:  version,codename,series,created[,release[,eol[,eol-lts[,eol-elts]]]]
## output: series version,created[,release[,eol[,eol-lts[,eol-elts]]]]

BEGIN {
	OFS = FS = ",";
}

function push(A, v) {
	A[length(A) + 1] = v;
}

function join(A, sep,     n, r, i) {
	n = length(A);
	r = "";
	for (i = 1; i <= n; i++) {
		if (i > 1) r = r sep;
		r = r A[i];
	}
	return r;
}

## line parser
{
	## init Tag list with series as 1st tag
	split($3, T);
	## Debian specific:
	## "virtual" releases don't have version
	if ($1 != "") {
		## Ubuntu specific:
		## select 1st word from version
		split($1, A, " ");
		push(T, A[1]);
	}

	## init output list with "created" (4th field) as 1st field
	split($4, L);
	## push remaining fields
	for (i = 5; i <= NF; i++ ) { push(L, $i); }

	## output list
	print join(T, " "), join(L, OFS);
}
