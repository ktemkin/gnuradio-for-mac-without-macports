#!/bin/sh

DEBUG=1

function D() {
  if [ "" != "${DEBUG}" ]; then
    echo "D: $@"
  fi
}

function find_bad_deps() {
  local dylib="$1"
  local deps="$(otool -L ${dylib} | grep -v ":" | awk '{print $1}')"
  local bad_deps=""

  for d in ${deps}; do

    # begins with @rpath
    # apparently solved by running 'install_name_tool'
    if [ "${d:0:6}" = "@rpath" ]; then
      bad_deps+="${d} "
      continue
    fi

    # not an absolute path
    # needs to be linked with -install_name ${INSTALL_DIR}/usr/lib/libfoo.dylib
    if [ "/" != "${d:0:1}" ]; then
      bad_deps+="${d} "
      continue
    fi
  done
  
  echo "${bad_deps}"
}

function find_bad_libs() {
  local dir="${1}"
  local bad_deps=""
  
  cd ${dir}
  for dy in $(find * -name '*.dylib' -o -name '*.so'); do
  
    if [ -h ${dy} ]; then
      continue
    fi
  
    bad_deps="$(find_bad_deps ${dy})"
    if [ "" != "${bad_deps}" ]; then
      echo $dy: $bad_deps
    fi
  done
}

# main

find_bad_libs @INSTALL_DIR@/usr