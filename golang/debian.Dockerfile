# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

ARG GOLANG_VERSION=latest
ARG DEBIAN_VERSION=latest

#################################################

FROM docker.io/rockdrilla/golang:pure-$GOLANG_VERSION AS pure

FROM docker.io/rockdrilla/debian-minbase:$DEBIAN_VERSION

ENV GOROOT="/usr/local/go"
ENV GOPATH="/go"

ENV PATH="/go/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

WORKDIR /go

CMD bash

COPY --from=pure  /  /
