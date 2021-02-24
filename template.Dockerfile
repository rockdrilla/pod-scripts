# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin

FROM docker.io/rockdrilla/debian-minbase-unstable

ONBUILD RUN : please issue 'sh /.cleanup.sh'
ONBUILD RUN : as last RUN command in your images
ONBUILD RUN : and consider keeping these hints
ONBUILD RUN : within ONBUILD RUN further

# remove next line if package management is not required
RUN apt update

# further configuration

# must be latest RUN statement
RUN sh /.cleanup.sh
