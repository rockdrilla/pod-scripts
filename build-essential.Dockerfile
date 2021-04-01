# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

ARG FLAVOUR=unstable:latest
FROM docker.io/rockdrilla/debian-minbase-$FLAVOUR

RUN aptitude update ; aptitude -y install build-essential bzr curl dwarves \
    dwz gfortran git gnupg mercurial pkg-config procps subversion unzip wget \
    autoconf-archive+M automake+M bison+M ca-certificates+M fakeroot+M \
    flex+M libc-devtools+M libfl-dev+M libltdl-dev+M libtool+M netbase+M \
    openssh-client+M psmisc+M zip+M

RUN sh /.cleanup.sh
