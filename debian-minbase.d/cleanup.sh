#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021, Konstantin Demin
set -e

run-parts --verbose --exit-on-error /.cleanup.d
