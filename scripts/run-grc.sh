#!/bin/sh

. '@INSTALL_DIR@/usr/bin/grenv.sh'

exec gnuradio-companion "${@}"
