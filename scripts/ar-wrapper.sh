#!/bin/sh

# ar [--plugin name] [-X32_64] [-]p[mod [relpos] [count]] archive [member...]

# On OS X, static libraries (even convenience libraries) cannot be created
# properly unless created with 'libtool -static'. So rather than fix 1M or so
# autoconf scripts, we just create a wrapper for Apple's libtool.

X=""
AR_FILE=""
O_FILES=""

while [ $# -gt 0 ]; do
  if [ "$(basename ${1} .a)" != "$(basename ${1})" ]; then
    if [ "" = "${AR_FILE}" ]; then
      AR_FILE="${1}"
    fi
  elif [ "$(basename ${1} .o)" != "$(basename ${1})" ]; then
    O_FILES+=" ${1}"
  elif [ "x" = "${1}" ]; then
    X="yes"
  fi
  shift
done

if [ "${X}" = "yes" ]; then
#  echo "/usr/bin/ar x ${AR_FILE}" > /dev/stderr
  exec /usr/bin/ar x ${AR_FILE}
else
#  echo "libtool -static -o ${AR_FILE} ${O_FILES}" > /dev/stderr
  exec /usr/bin/libtool -static -o ${AR_FILE} ${O_FILES}
fi
