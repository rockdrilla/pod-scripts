# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

FROM docker.io/rockdrilla/debian-minbase-unstable AS base

WORKDIR /tmp

RUN mkdir -p /usr/local/go ; \
    install -m 0777 -d /go ; \
    install -m 0777 -d /go/src /go/bin

RUN aptitude update ; aptitude -y install curl ca-certificates \
    build-essential fakeroot libc-devtools pkg-config \
    git openssh-client cvs subversion mercurial \
    netbase wget gnupg procps psmisc

RUN sh /.cleanup.sh

#################################################
FROM base AS buildbase

ARG GOLANG_VERSION=latest

RUN curl -qsSL https://golang.org/dl/ \
    | URI='https://golang.org' perl -ne 'while(m/(?<=href=)([\x22\x27])(.+?)\1(.*)$/){$_=$3;my $s=$2;$s="$ENV{URI}$s" if $s !~ m/^[[:alnum:]]+?:/;print "$s\n";}' \
    | grep -E '/go[^/]+\.src\.tar\.(gz|xz|bz2|zstd?)$' > list ; [ -s /tmp/list ] || exit 1
RUN if [ "${GOLANG_VERSION}" = latest ] ; then head -n 1 ; else grep -m 1 -F "/go${GOLANG_VERSION}.src" ; fi < list \
    | tee /tmp/uri ; [ -s /tmp/uri ] || exit 1
RUN xargs curl -qsSL < /tmp/uri > /tmp/go.tar.gz
RUN mkdir -p /tmp/go /usr/local/go

#################################################
FROM buildbase AS golang-dist

RUN aptitude update ; aptitude -y install golang-go

#################################################
FROM golang-dist AS env-common

RUN go env \
    | sed -En '/^GO((HOST|)(OS|ARCH)|ARM)=.*/{s##export \0#;p;}' \
    | tee /tmp/env

#################################################
FROM base AS env-stage1

RUN p="/tmp/go" ; export DEB_BUILD_MAINT_OPTIONS='hardening=-all' ; \
    mkdir -p $p ; cd $p/ ; \
    { \
        echo export CGO_ENABLED="1" ; \
        dpkg-buildflags --export=sh \
        | sed -En '/^(export )?([^=]+)=(.+)$/{s##export \2=\3\nexport CGO_\2=\3#;p;}' ; \
    } > /tmp/env.stage

#################################################
FROM base AS env-stage2

RUN p="/usr/local/go" ; export DEB_BUILD_MAINT_OPTIONS='hardening=+all' ; \
    mkdir -p $p ; cd $p/ ; \
    { \
        echo export CGO_ENABLED="1" ; \
        dpkg-buildflags --export=sh \
        | sed -En '/^(export )?([^=]+)=(.+)$/{s##export \2=\3\nexport CGO_\2=\3#;p;}' ; \
    } > /tmp/env.stage

#################################################
FROM golang-dist AS stage1

COPY --from=env-common  /tmp/env        /tmp/
COPY --from=env-stage1  /tmp/env.stage  /tmp/

RUN export GOROOT_BOOTSTRAP="$(go env GOROOT)" ; \
    . /tmp/env ; . /tmp/env.stage ; \
    p="/tmp" ; \
    tar -C "$p" -xf /tmp/go.tar.gz ; \
    cd "$p/go/src/" ; ./make.bash ; \
    export PATH="$p/go/bin:${PATH}" ; \
    go install std

#################################################
FROM buildbase AS stage2

COPY --from=env-common  /tmp/env        /tmp/
COPY --from=env-stage2  /tmp/env.stage  /tmp/
COPY --from=stage1      /tmp/go/        /tmp/go/

RUN export GOROOT_BOOTSTRAP="/tmp/go" ; \
    OLDPATH="${PATH}" ; export PATH="/tmp/go/bin:${PATH}" ; \
    . /tmp/env ; . /tmp/env.stage ; \
    p="/usr/local" ; \
    tar -C "$p" -xf /tmp/go.tar.gz ; \
    cd "$p/go/src/" ; ./make.bash ; \
    export PATH="$p/go/bin:${OLDPATH}" ; \
    go install std
RUN cd /usr/local/go/ ; \
    rm -vrf pkg/*/cmd pkg/bootstrap pkg/obj pkg/tool/*/api \
    pkg/tool/*/go_bootstrap src/cmd/dist/dist

RUN sh /.cleanup.sh

#################################################
FROM base

ENV PATH="/go/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ENV GOROOT="/usr/local/go"
ENV GOPATH="/go"

WORKDIR /go
CMD bash

COPY --from=stage2  /usr/local/go/  /usr/local/go/

RUN go version ; go env GOROOT

RUN sh /.cleanup.sh
