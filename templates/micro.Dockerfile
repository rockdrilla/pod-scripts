# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

ARG DISTRO=debian
ARG SUITE=unstable
FROM docker.io/rockdrilla/$DISTRO-minbase:$SUITE AS base

## NB: "base" image should contain relevant package lists!
RUN /opt/apt.sh

#################################################

FROM base AS stage

## NB: desired package list is also specified below
## in clause "RUN /opt/finalize.sh"
RUN /opt/apt.sh full-upgrade && \
    /opt/apt.sh install default-jre-headless git gcc

RUN /opt/cleanup.sh

#################################################

ARG DISTRO=debian
ARG SUITE=unstable
FROM docker.io/rockdrilla/$DISTRO-micro:$SUITE

COPY --from=stage  /  /

## use APT/DPkg information from "base"
RUN rm -rf /var/lib/dpkg \
           /var/lib/apt \
           /var/lib/aptitude \
           /var/cache/apt
COPY --from=base  /var/lib/dpkg/      /var/lib/dpkg/
COPY --from=base  /var/lib/apt/       /var/lib/apt/
COPY --from=base  /var/lib/aptitude/  /var/lib/aptitude/
COPY --from=base  /var/cache/apt/     /var/cache/apt/

## detect which packages are safe to remove
## when desired packages are to be installed
RUN /opt/finalize.sh default-jre-headless git gcc
