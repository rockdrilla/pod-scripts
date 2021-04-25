# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

ARG DISTRO=debian
ARG SUITE=unstable
FROM docker.io/rockdrilla/$DISTRO-minbase:$SUITE

RUN aptitude update ; aptitude -y install build-essential bzr curl dwarves \
    dwz gfortran git gnupg mercurial pkg-config procps subversion unzip wget \
    autoconf-archive+M automake+M bison+M ca-certificates+M fakeroot+M \
    flex+M libfl-dev+M libltdl-dev+M libtool+M netbase+M \
    openssh-client+M psmisc+M zip+M
RUN aptitude -y install libc-devtools+M || true

RUN /opt/cleanup.sh
