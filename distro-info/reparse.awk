#!/usr/bin/env gawk
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

## input:  series version,created[,release[,eol[,eol-lts[,eol-elts]]]]
## output: series version,release,is-release-sane,x-created[,x-release[,x-eol[,x-eol-lts[,x-eol-elts]]]]

function try_env(param, default,     x) {
	x = ENVIRON[param];
	return (x != "") ? x : default;
}

function date_numeric(ts) {
	return strftime("%Y%m%d", ts, 1);
}

BEGIN {
	OFS = FS = ",";

	now = try_env("SOURCE_DATE_EPOCH", systime());
	now = date_numeric(now);
}

function push(A, v) {
	A[length(A) + 1] = v;
}

function join(A, sep,     n, r, i) {
	n = length(A);
	r = "";
	for(i = 1; i <= n; i++) {
		if (i > 1) r = r sep;
		r = r A[i];
	}
	return r;
}

## line parser
{
	## init Lifecycle list with stub value (instead of release date)
	split("1", L); ## is release date sane?
	## push remaining dates to Lifecycle list
	## now Lifecycle is filled like "0,created,release,..."
	for (i = 2; i <= NF; i++ ) { push(L, $i); }

	## Debian specific:
	## approximate release/eof dates on creation date if empty:
	## release date is beginning of the year and eol date is end of the year
	split(L[2], A, "-");
	A[1] = A[1] + 2; ## add 2 years to creation date
	if (L[3] == "") {
		L[1] = 0;
		L[3] = A[1] "-01-01";
	}
	if (L[4] == "") {
		L[4] = A[1] "-12-31";
	}

	## preserve release date
	reldate = L[3];

	## remove dashes from dates, make them "numeric",
	## and compare with (current) date
	n = length(L);
	for (i = 2; i <= n; i++ ) {
		gsub("-", "", L[i]);
		if (L[i] == "") {
			L[i] = 0;
			continue;
		}
		## process all dates except "released" normally
		if (i != 3) {
			L[i] = (now >= L[i]) ? 1 : 0;
			continue;
		}
		## process "released" normally if it was before "now"
		if (now >= L[i]) {
			L[i] = 1;
			continue;
		}
		## mark channel as "released" when it's less than 2 months
		## before actual release
		if ((L[i] - now) < 200) {
			L[1] = 0;
			L[i] = 1;
		} else {
			L[i] = 0;
		}
	}

	print $1, reldate, join(L, OFS);
}
