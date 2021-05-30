#!/usr/bin/env gawk
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

## input:  series version,release,is-release-sane,x-created[,x-release[,x-eol[,x-eol-lts[,x-eol-elts]]]]
## output: series version,release,is-release-sane,x-created[,x-release[,x-eol[,x-eol-lts[,x-eol-elts]]]]

function try_env(param, default,     x) {
	x = ENVIRON[param];
	return (x != "") ? x : default;
}

BEGIN {
	OFS = FS = ",";
	act = try_env("FILT", "active");
	split(act, A, " ");
	act = A[1];
}

## line parser
{
	switch (act) {
		case "lts" : {
			if ($7 == "") next;
			## implicit fallthrough
		}
		case "active" : {
			## skip entries with expired last support date
			if ($NF == 1) next;

			if ($7 == 1) next;
			if ($5 == 0) next;
			break;
		}
		case "stable" : {
			if ($8 != "") next;
			if ($3$4$5$6 == "1110") break;
			next;
		}
		case "testing" : {
			if ($4$6 != "10") next;
			if ($3$5 == "01") break;
			if ($3$5 == "10") break;
			next;
		}
	}

	print $0;
}
