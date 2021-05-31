# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

ARG DISTRO=debian
ARG SUITE=unstable
FROM rockdrilla/$DISTRO-minbase:$SUITE

## please issue '/opt/cleanup.sh' as last RUN command in your images

## remove next line if package management is not required
RUN /opt/apt.sh

## further configuration

## must be latest RUN statement
RUN /opt/cleanup.sh
