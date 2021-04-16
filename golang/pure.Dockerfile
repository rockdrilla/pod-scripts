# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

#################################################
FROM docker.io/rockdrilla/build-essential:unstable AS base

WORKDIR /tmp

RUN mkdir -p /usr/local/go /tmp/go ; \
    install -m 0777 -d /go ; \
    install -m 0777 -d /go/src /go/bin /go/tmp

#################################################
FROM base AS buildbase

ARG GOLANG_VERSION=latest

RUN if [ "$GOLANG_VERSION" = 'latest' ] ; then \
        curl -qsSL 'https://golang.org/dl/' \
        | URI='https://golang.org' perl -ne 'while(m/(?<=href=)([\x22\x27])(.+?)\1(.*)$/){$_=$3;my $s=$2;$s="$ENV{URI}$s" if $s !~ m/^[[:alnum:]]+?:/;print "$s\n";}' \
        | grep -m 1 -E '/go[^/]+\.src\.tar\.(gz|xz|bz2|zstd?)$' ; \
    else \
        echo "https://golang.org/dl/go$GOLANG_VERSION.src.tar.gz" ; \
    fi \
    | tee /dev/stderr \
    | xargs -r curl -sSL > /tmp/go.tar.gz ; \
    tar -tf /tmp/go.tar.gz >/dev/null

#################################################
FROM buildbase AS golang-dist

RUN aptitude update && aptitude -y install golang-go

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
        echo 'export CGO_ENABLED="1"' ; \
        dpkg-buildflags --export=sh \
        | sed -En '/^(export )?([^=]+)=(.+)$/{s##export \2=\3\nexport CGO_\2=\3#;p;}' ; \
    } > /tmp/env.stage1

#################################################
FROM base AS env-stage2

RUN p="/usr/local/go" ; export DEB_BUILD_MAINT_OPTIONS='hardening=+all' ; \
    mkdir -p $p ; cd $p/ ; \
    { \
        echo 'export CGO_ENABLED="0"' ; \
        dpkg-buildflags --export=sh \
        | sed -En '/^(export )?([^=]+)=(.+)$/{s##export \2=\3\nexport CGO_\2=\3#;p;}' ; \
    } > /tmp/env.stage2

#################################################
FROM golang-dist AS stage1

COPY --from=env-common  /tmp/env        /tmp/
COPY --from=env-stage1  /tmp/env.stage1 /tmp/env.stage1

RUN export GOROOT_BOOTSTRAP="$(go env GOROOT)" ; \
    . /tmp/env ; . /tmp/env.stage1 ; \
    p="/tmp" ; \
    tar -C "$p" -xf /tmp/go.tar.gz ; \
    cd "$p/go/src/" ; ./make.bash ; \
    [ -x "$p/go/bin/go" ]
RUN p="/tmp" ; \
    export PATH="$p/go/bin:${PATH}" ; \
    go install std
RUN cd /tmp/go/ ; \
    rm -rf pkg/*/cmd pkg/bootstrap pkg/obj pkg/tool/*/api \
    pkg/tool/*/go_bootstrap src/cmd/dist/dist

#################################################
FROM buildbase AS stage2

COPY --from=env-common  /tmp/env        /tmp/
COPY --from=env-stage2  /tmp/env.stage2 /tmp/env.stage2
COPY --from=stage1      /tmp/go/        /tmp/go/

RUN export GOROOT_BOOTSTRAP="/tmp/go" ; \
    export PATH="/tmp/go/bin:${PATH}" ; \
    . /tmp/env ; . /tmp/env.stage2 ; \
    p="/usr/local" ; \
    tar -C "$p" -xf /tmp/go.tar.gz ; \
    cd "$p/go/src/" ; ./make.bash ; \
    [ -x "$p/go/bin/go" ]
RUN p="/usr/local" ; \
    export PATH="$p/go/bin:${PATH}" ; \
    go install std
RUN cd /usr/local/go/ ; \
    rm -vrf pkg/*/cmd pkg/bootstrap pkg/obj pkg/tool/*/api \
    pkg/tool/*/go_bootstrap src/cmd/dist/dist

RUN /opt/cleanup.sh

RUN tar -C / -cf - /go /usr/local/go | tar -C /mnt -xf -

#################################################

FROM scratch

ENV GOROOT="/usr/local/go"
ENV GOPATH="/go"

ENV PATH="/go/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ENV LANG="C.UTF8"
ENV LC_ALL="C.UTF-8"
ENV TERM="xterm"
ENV TMPDIR="/go/tmp"
ENV TMP="/go/tmp"
ENV TEMPDIR="/go/tmp"
ENV TEMP="/go/tmp"

WORKDIR /go

COPY --from=stage2  /mnt  /

RUN [ "/usr/local/go/bin/go", "version" ]
