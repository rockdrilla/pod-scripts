# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

ARG DISTRO=debian
ARG SUITE=latest
FROM rockdrilla/$DISTRO-minbase:$SUITE

RUN /opt/apt.sh --with-recommends install \
        autoconf autoconf-archive automake bison build-essential bzr curl \
        debhelper dwarves dwz flex gettext gfortran git gnulib gnupg libtool \
        mercurial pkg-config psmisc subversion unzip wget zip

RUN /opt/cleanup.sh
