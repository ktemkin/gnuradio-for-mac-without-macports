#!/bin/sh

CFLAGS="-I/Applications/GNURadio.app/Contents/MacOS/usr/include"

INPUT=""
OUTPUT=""
T=""

while [ $# -gt 0 ]; do
  if [ 0 -eq 1 ]; then
    touch /dev/null
  elif [ "-c" = "$1" ]; then
    shift
    INPUT="$1"
  elif [ "-o" = "$1" ]; then
    shift
    OUTPUT="$1"
  fi
  shift
done

if [ "" = "${INPUT}" ]; then
  exit 1
fi
T=${INPUT/.f/.c}

if [ "" = "${OUTPUT}" ]; then
  OUTPUT="${T/.c/.o}"
fi

f2c ${INPUT} > ${T} 2>/dev/null \
&& clang ${CFLAGS} -c ${T} -o ${OUTPUT}

R=$?

rm -f ${T}

exit $R
