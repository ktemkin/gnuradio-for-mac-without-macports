#!/bin/sh

export APP_DIR="$(cd "$(dirname "${0}")"/../../../../; pwd)"

source "${APP_DIR}"/Contents/MacOS/usr/bin/grenv.sh

gnuradio-companion ${@} &

exit 0
