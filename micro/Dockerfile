# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

#################################################
ARG DISTRO=debian
ARG SUITE=unstable
FROM docker.io/rockdrilla/$DISTRO-minbase:$SUITE AS base

#################################################

FROM scratch

COPY --from=base / /

ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ENV LANG="C.UTF-8"
ENV LC_ALL="C.UTF-8"
ENV TERM="xterm"
ENV TMPDIR="/tmp"
ENV TMP="/tmp"
ENV TEMPDIR="/tmp"
ENV TEMP="/tmp"
ENV TZ="Etc/UTC"

COPY finalize.sh /opt/
RUN /opt/apt.sh
RUN /opt/finalize.sh
