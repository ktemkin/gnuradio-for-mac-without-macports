#!/bin/sh

# XXX: @CF: if we are a tagged release then do not use GIT
# Otherwise, tack on the contents of 'git rev-parse --short HEAD'
GRFMWM_GIT_REVISION="-94ee402"
GNURADIO_BRANCH=3.7.10.1

# default os x path minus /usr/local/bin, which could have pollutants
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

EXTS="zip tar.gz tgz tar.bz2 tbz2 tar.xz"

SKIP_FETCH=true
SKIP_AUTORECONF=
SKIP_LIBTOOLIZE=

DEBUG=true

function top_srcdir() {
  local r
  pushd "$(dirname "${0}")" > /dev/null
  r="$(pwd -P)"
  popd > /dev/null
  echo "${r}"
}

function I() {
  echo "I: ${@}"
}

function E() {
  local r
  r=$?
  if [ 0 -eq $r ]; then
    r=1;
  fi
  echo "E: ${@}" > /dev/stderr
  exit 1;
}

function D() {
  if [ "" != "$DEBUG" ]; then
    echo "D: ${@}"
  fi
}

[[ "$(uname)" = "Darwin" ]] \
  || E "This script is only intended to be run on Mac OS X"

XQUARTZ_APP_DIR=/Applications/Utilities/XQuartz.app

BUILD_DIR="$(top_srcdir)"
TMP_DIR=${BUILD_DIR}/tmp
APP_DIR="${APP_DIR:-"/Applications/GNURadio.app"}"
CONTENTS_DIR=${APP_DIR}/Contents
RESOURCES_DIR=${CONTENTS_DIR}/Resources
INSTALL_DIR=${CONTENTS_DIR}/MacOS

function xpath_contains() {
  local x=${1}
  local y=${2}

  for p in ${x/:/ }; do
    if [ "${y}" = "${p}" ]; then
      return 0
    fi
  done
  return 1
}

function path_contains() {
  xpath_contains ${PATH} ${1}
}

function dyldlibpath_contains() {
  xpath_contains ${DYLD_LIBRARY_PATH} ${1}
}

function prefix_dyldlibpath_if_not_contained() {
  local x=${1}
  dyldlibpath_contains ${1}
  if [ $? -eq 0 ]; then
    return
  fi
  export DYLD_LIBRARY_PATH=${1}:${DYLD_LIBRARY_PATH}
}

function prefix_path_if_not_contained() {
  local x=${1}
  path_contains ${1}
  if [ $? -eq 0 ]; then
    return
  fi
  export PATH=${1}:${PATH}
}

function ncpus() {
  sysctl -n hw.ncpu
}

function verify_sha256() {
  #local FILENAME="${1}"
  #local CKSUM="${2}"
  test "$(shasum -a 256 -- "${1}" | cut -d' ' -f1)" = "${2}" \
    && D "File '${1}' matches '${2}'" \
    || E "File '${1}' does not match '${2}'"
}

function verify_git() {
  #local FILENAME="${1}"
  #local CKSUM="${2}"
  # Verify the hash refers to a commit.
  #    http://stackoverflow.com/questions/18515488/how-to-check-if-the-commit-exists-in-a-git-repository-by-its-sha-1
  test "$( git -C "${1}" cat-file -t "${2}" 2>/dev/null )" = commit \
    || E "Repository '${1}' does not match '${2}'"
  # Then verify the hash is in the current branch.  (The branch may have newer commits.)
  #    http://stackoverflow.com/questions/4127967/validate-if-commit-exists
  test "$( git -C "${1}" rev-list HEAD.."${2}" | wc -l )" -eq 0 \
    || E "Repository '${1}' does not match '${2}'"
}

function verify_checksum() {
  #local FILENAME="${1}"
  #local CKSUM="${2}"
  test -e "${1}" || E "Missing: '${1}'"
  if [ -z "${2}" ]; then
    # Nag someone to get a checksum for this thing.
    I "No checksum: '${1}'"
    return 0
  fi
  # CKSUM is in the form of "format:data"
  # (We allow additional colons in data for future whatever, format:data0:data1:...)
  # Check the leading "format:" portion
  case "${2%%:*}" in
    "sha256")
      # Remove leading "sha256:", and invoke the correct function:
      verify_sha256 "${1}" "${2#*:}"
      ;;
    "git")
      # Remove leading "git:", and invoke the correct function:
      verify_git "${1}" "${2#*:}"
      ;;
    *)
      E "Unrecognized checksum format: ${2}"
      ;;
  esac
}

# XXX: @CF: use hash-checking for compressed archives
function fetch() {
  local P=${1}
  local URL=${2}
  local T=${3}
  local BRANCH=${4}
  local CKSUM=${5}

  I "fetching ${P} from ${URL}"

  if [ "git" = "${URL:0:3}" -o "" != "${BRANCH}" ]; then
    D "downloading to ${TMP_DIR}/${T}"
    if [ -d ${TMP_DIR}/${T} ]; then
      D "already downloaded ${P}"
      verify_checksum "${TMP_DIR}/${T}" "${CKSUM}"
      return
    fi
    git clone ${URL} ${TMP_DIR}/${T} \
      ||  ( rm -Rf ${TMP_DIR}/${T}; E "failed to clone from ${URL}" )
    if [ "" != "${BRANCH}" ]; then
      cd ${TMP_DIR}/${T} \
        && git checkout -b local-${BRANCH} ${BRANCH} \
        || ( rm -Rf ${TMP_DIR}/${T}; E "failed to checkout ${BRANCH}" )
    fi
    verify_checksum "${TMP_DIR}/${T}" "${CKSUM}"
  else
    if [ "" != "${SKIP_FETCH}" ]; then
      local Z=
      for zz in $EXTS; do
        D "checking for ${TMP_DIR}/${P}.${zz}"
        if [ -f ${TMP_DIR}/${P}.${zz} ]; then
          Z=${P}.${zz}
          D "already downloaded ${Z}"
          verify_checksum "${TMP_DIR}/${Z}" "${CKSUM}"
          return
        fi
      done
    fi
    cd ${TMP_DIR} \
    && curl -L --insecure -k -O ${URL} \
      || E "failed to download from ${URL}"
    verify_checksum "${URL##*/}" "${CKSUM}"
  fi
}

function unpack() {
  local P=${1}
  local URL=${2}
  local T=${3}

  if [ "" = "${T}" ]; then
    T=${P}
  fi

  if [ "git" = "${URL:0:3}" -o "" != "${BRANCH}" ]; then
    I "resetting and checking out files from git"
    cd ${TMP_DIR}/${T} \
      && git reset \
      && git checkout . \
      || E "failed to git checkout in ${T}"
  else
    local opts=
    local cmd=
    local Z=
    if [ 1 -eq 0 ]; then
      echo 
    elif [ -e ${TMP_DIR}/${P}.zip ]; then
      Z=${P}.zip
      cmd=unzip
    elif [ -e ${TMP_DIR}/${P}.tar.gz ]; then
      Z=${P}.tar.gz
      cmd=tar
      opts=xpzf
    elif [ -e ${TMP_DIR}/${P}.tgz ]; then
      Z=${P}.tgz
      cmd=tar
      opts=xpzf
    elif [ -e ${TMP_DIR}/${P}.tar.bz2 ]; then
      Z=${P}.tar.bz2
      cmd=tar
      opts=xpjf
    elif [ -e ${TMP_DIR}/${P}.tbz2 ]; then
      Z=${P}.tbz2
      cmd=tar
      opts=xpjf
    elif [ -e ${TMP_DIR}/${P}.tar.xz ]; then
      Z=${P}.tar.xz
      cmd=tar
      opts=xpJf
    fi
    
    I "Extracting ${Z} to ${T}"
    rm -Rf ${TMP_DIR}/${T}
    cd ${TMP_DIR} \
    && echo "${cmd} ${opts} ${Z}" \
    && ${cmd} ${opts} ${Z} \
      || E "failed to extract ${Z}"

  fi
  
  local PATCHES="$(ls -1 ${BUILD_DIR}/patches/${P}-*.patch 2>/dev/null)"
  if [ "" != "${PATCHES}" ]; then
    
    if [ ! -d ${TMP_DIR}/${T}/.git ]; then
      cd ${TMP_DIR}/${T} \
      && git init \
      && git add . \
      && git commit -m 'initial commit' \
      || E "failed to initialize local git (to make patching easier)"
    fi
    
    for PP in $PATCHES; do
      if [ "${PP%".sh.patch"}" != "${PP}" ]; then
        # This ends with .sh.patch, so source it:
        I "applying script ${PP}"
        cd ${TMP_DIR}/${T} \
          && . ${PP} \
          || E "sh ${PP} failed"
      else
        I "applying patch ${PP}"
        cd ${TMP_DIR}/${T} \
          && git apply ${PP} \
          || E "git apply ${PP} failed"
      fi
    done
  fi
}

function build_and_install_cmake() {

  local P=${1}
  local URL=${2}
  local CKSUM=${3}
  local T=${4}
  local BRANCH=${5}

  if [ "" = "${T}" ]; then
    T=${P}
  fi

  if [ -f ${TMP_DIR}/.${P}.done ]; then
    I "already installed ${P}"    
  else 
    fetch "${P}" "${URL}" "${T}" "${BRANCH}" "${CKSUM}"
    unpack ${P} ${URL} ${T} ${BRANCH}
  
    rm -Rf ${TMP_DIR}/${T}-build \
    && mkdir ${TMP_DIR}/${T}-build \
    && cd ${TMP_DIR}/${T}-build \
    && cmake ${EXTRA_OPTS} \
    && ${MAKE} \
    && ${MAKE} install \
    || E "failed to build ${P}"
  
    I "finished building and installing ${P}"

    touch ${TMP_DIR}/.${P}.done
  
  fi
}

function build_and_install_setup_py() {

  local P=${1}
  local URL=${2}
  local CKSUM=${3}
  local T=${4}
  local BRANCH=${5}

  if [ "" = "${T}" ]; then
    T=${P}
  fi

  if [ -f ${TMP_DIR}/.${P}.done ]; then
    I "already installed ${P}"    
  else 
  
    fetch "${P}" "${URL}" "${T}" "${BRANCH}" "${CKSUM}"
    unpack ${P} ${URL} ${T}
  
    if [ ! -d ${PYTHONPATH} ]; then
      mkdir -p ${PYTHONPATH} \
        || E "failed to mkdir -p ${PYTHONPATH}"
    fi
  
    I "Configuring and building in ${T}"
    cd ${TMP_DIR}/${T} \
      && \
        ${PYTHON} setup.py install --prefix=${INSTALL_DIR}/usr \
      || E "failed to configure and install ${P}"
  
    I "finished building and installing ${P}"
    
    touch ${TMP_DIR}/.${P}.done
    
  fi
}

function build_and_install_autotools() {

  local P=${1}
  local URL=${2}
  local CKSUM=${3}
  local T=${4}
  local BRANCH=${5}
  local CONFIGURE_CMD=${6}
  
  if [ "" = "${CONFIGURE_CMD}" ]; then
    CONFIGURE_CMD="./configure --prefix=${INSTALL_DIR}/usr"
  fi

  if [ "" = "${T}" ]; then
    T=${P}
  fi

  if [ -f ${TMP_DIR}/.${P}.done ]; then
    I "already installed ${P}"
  else 
  
    fetch "${P}" "${URL}" "${T}" "${BRANCH}" "${CKSUM}"
    unpack ${P} ${URL} ${T}
  
    if [[ ( "" = "${SKIP_AUTORECONF}" && "" != "$(which autoreconf)"  ) || ! -f ${TMP_DIR}/${T}/configure ]]; then
      I "Running autoreconf in ${T}"
      cd ${TMP_DIR}/${T} \
        && autoreconf -if  \
        || E "autoreconf failed for ${P}"
    fi
  
    if [[ "" = "${SKIP_LIBTOOLIZE}" && "" != "$(which libtoolize)" ]]; then
      I "Running libtoolize in ${T}"
      cd ${TMP_DIR}/${T} \
        && libtoolize -if \
        || E "libtoolize failed for ${P}"
    fi

    I "Configuring and building in ${T}"
    cd ${TMP_DIR}/${T} \
      && I "${CONFIGURE_CMD} ${EXTRA_OPTS}" \
      && ${CONFIGURE_CMD} ${EXTRA_OPTS} \
      && ${MAKE} \
      && ${MAKE} install \
      || E "failed to configure, make, and install ${P}"
  
    I "finished building and installing ${P}"
    
    touch ${TMP_DIR}/.${P}.done
    
  fi
  
  unset SKIP_AUTORECONF
  unset SKIP_LIBTOOLIZE
}

function build_and_install_qmake() {

  local P=${1}
  local URL=${2}
  local CKSUM=${3}
  local T=${4}
  local BRANCH=${5}
  
  if [ "" = "${T}" ]; then
    T=${P}
  fi

  if [ -f ${TMP_DIR}/.${P}.done ]; then
    I "already installed ${P}"
  else 
  
    fetch "${P}" "${URL}" "${T}" "${BRANCH}" "${CKSUM}"
    unpack ${P} ${URL} ${T} ${BRANCH}
  
    I "Configuring and building in ${T}"
    cd ${TMP_DIR}/${T} \
      && I "qmake ${EXTRA_OPTS}" \
      && qmake ${EXTRA_OPTS} \
      && ${MAKE} \
      && ${MAKE} install \
      || E "failed to make and install ${P}"
  
    I "finished building and installing ${P}"
    
    touch ${TMP_DIR}/.${P}.done
    
  fi
  
  unset SKIP_AUTORECONF
  unset SKIP_LIBTOOLIZE
}

#function create_icns_via_cairosvg() {
#  local input="${1}"
#  local output="${2}"
#  local T="$(dirname ${output})/iconbuilder.iconset"
#  
#  mkdir -p ${T} \
#  && cd ${T} \
#  && for i in 16 32 128 256 512; do
#    j=$((2*i)) \
#    && I creating icon_${i}x${i}.png \
#    && cairosvg ${input} -W ${i} -H ${i} -o ${T}/icon_${i}x${i}.png \
#    && I creating icon_${i}x${i}@2x.png \
#    && cairosvg ${input} -W ${j} -H ${j} -o ${T}/icon_${i}x${i}@2x.png \
#    || E failed to create ${i}x${i} or ${i}x${i}@2x icons; \
#  done \
#  && iconutil -c icns -o ${output} ${T} \
#  && I done creating ${output} \
#  || E failed to create ${output} from ${input}
#}

#function create_icns_via_rsvg() {
#  local input="${1}"
#  local output="${2}"
#  local T="$(dirname ${output})/iconbuilder.iconset"
#  
#  mkdir -p ${T} \
#  && cd ${T} \
#  && for i in 16 32 128 256 512; do
#    j=$((2*i)) \
#    && I creating icon_${i}x${i}.png \
#    && rsvg-convert ${input} -W ${i} -H ${i} -o ${T}/icon_${i}x${i}.png \
#    && I creating icon_${i}x${i}@2x.png \
#    && rsvg-convert ${input} -W ${j} -H ${j} -o ${T}/icon_${i}x${i}@2x.png \
#    || E failed to create ${i}x${i} or ${i}x${i}@2x icons; \
#  done \
#  && iconutil -c icns -o ${output} ${T} \
#  && I done creating ${output} \
#  || E failed to create ${output} from ${input}
#}

#
# misc
# 

MAKE="${MAKE:-"make -j$(ncpus)"}"
PYTHON=python2.7
export PYTHONPATH=${INSTALL_DIR}/usr/lib/${PYTHON}/site-packages

#
# main
#

I "BUILD_DIR = '${BUILD_DIR}'"
I "INSTALL_DIR = '${INSTALL_DIR}'"

#rm -Rf ${TMP_DIR}

mkdir -p ${BUILD_DIR} ${TMP_DIR} ${INSTALL_DIR}

cd ${TMP_DIR}

prefix_path_if_not_contained ${INSTALL_DIR}/usr/bin

#prefix_dyldlibpath_if_not_contained ${INSTALL_DIR}/usr/lib

CPPFLAGS="-I${INSTALL_DIR}/usr/include -I/opt/X11/include"
#CPPFLAGS="${CPPFLAGS} -I${INSTALL_DIR}/usr/include/gdk-pixbuf-2.0 -I${INSTALL_DIR}/usr/include/cairo -I${INSTALL_DIR}/usr/include/pango-1.0 -I${INSTALL_DIR}/usr/include/atk-1.0"
export CPPFLAGS
export CC="clang -mmacosx-version-min=10.7"
export CXX="clang++ -mmacosx-version-min=10.7 -stdlib=libc++"
export LDFLAGS="-Wl,-undefined,error -L${INSTALL_DIR}/usr/lib -L/opt/X11/lib -Wl,-rpath,${INSTALL_DIR}/usr/lib -Wl,-rpath,/opt/X11/lib"
export PKG_CONFIG_PATH="${INSTALL_DIR}/usr/lib/pkgconfig:/opt/X11/lib/pkgconfig"

unset DYLD_LIBRARY_PATH

#
# Check for Xcode Command-Line Developer tools (Prerequisite)
#

[[ -d ${XQUARTZ_APP_DIR} ]] \
  || E "XQuartz is not installed. Download it at http://www.xquartz.org/"

XCODE_DEVELOPER_DIR_CMD="xcode-select -p"
[[ "" = "$(${XCODE_DEVELOPER_DIR_CMD} 2>/dev/null)" ]] \
  && E "Xcode command-line developer tools are not installed. You can install them with 'xcode-select --install'"

# install wrappers for ar and ranlib, which prevent autotools from working
mkdir -p ${INSTALL_DIR}/usr/bin \
 && cp ${BUILD_DIR}/scripts/ar-wrapper.sh ${INSTALL_DIR}/usr/bin/ar \
  && chmod +x ${INSTALL_DIR}/usr/bin/ar \
  && \
cp ${BUILD_DIR}/scripts/ranlib-wrapper.sh ${INSTALL_DIR}/usr/bin/ranlib \
  && chmod +x ${INSTALL_DIR}/usr/bin/ranlib \
  || E "failed to install ar and ranlib wrappers"

[[ $(which ar) = ${INSTALL_DIR}/usr/bin/ar ]] \
  || E "sanity check failed. ar-wrapper is not in PATH"

#
# Check for Python 2.7 (Prerequisite)
#

[[ -d /Library/Frameworks/Python.framework/Versions/2.7 ]] \
  || [[ -d /System/Library/Frameworks/Python.framework/Versions/2.7 ]] \
  || E "Python 2.7 is not installed. Download it here: https://www.python.org/downloads/"


#
# Install autoconf
# 

P=autoconf-2.69
URL=http://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.gz
CKSUM=sha256:954bd69b391edc12d6a4a51a2dd1476543da5c6bbf05a95b59dc0dd6fd4c2969

  SKIP_AUTORECONF=yes \
  SKIP_LIBTOOLIZE=yes \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}

#
# Install automake
# 

P=automake-1.15
URL=http://ftp.gnu.org/gnu/automake/automake-1.15.tar.gz
CKSUM=sha256:7946e945a96e28152ba5a6beb0625ca715c6e32ac55f2e353ef54def0c8ed924

SKIP_AUTORECONF=yes \
SKIP_LIBTOOLIZE=yes \
build_and_install_autotools \
  ${P} \
  ${URL} \
  ${CKSUM}

#
# Install libtool
# 

  P=libtool-2.4
  URL=http://mirror.frgl.pw/gnu/libtool/libtool-2.4.tar.xz
  CKSUM=sha256:afcce660d3dc54c63a0a5ba3cf05272239dc3c54bbeba20f6bad250f9dc007ae

  SKIP_AUTORECONF=yes \
  SKIP_LIBTOOLIZE=yes \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}

if [ -f ${INSTALL_DIR}/usr/bin/libtool ]; then
  
  # we want libtoolize, but not libtool
  # we need Apple libtool for creating static libraries that work on Mac OS X
  mv \
    ${INSTALL_DIR}/usr/bin/libtool \
    ${INSTALL_DIR}/usr/bin/.gnu.libtool \
    || ( rm ${TMP_DIR}/.${P}.done; E "failed to replace GNU libtool" )
      
fi

#
# Install gettext
# 

  P=gettext-0.19.8
  URL=http://ftp.gnu.org/pub/gnu/gettext/gettext-0.19.8.tar.xz
  CKSUM=sha256:9c1781328238caa1685d7bc7a2e1dcf1c6c134e86b42ed554066734b621bd12f
    
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}

#
# Install xz-utils
# 

P=xz-5.2.3
URL=https://tukaani.org/xz/xz-5.2.3.tar.bz2
CKSUM=sha256:fd9ca16de1052aac899ad3495ad20dfa906c27b4a5070102a2ec35ca3a4740c1

build_and_install_autotools \
  ${P} \
  ${URL} \
  ${CKSUM}

#
# Install GNU tar
# 

P=tar-1.29
URL=http://ftp.gnu.org/gnu/tar/tar-1.29.tar.bz2
CKSUM=sha256:236b11190c0a3a6885bdb8d61424f2b36a5872869aa3f7f695dea4b4843ae2f2

EXTRA_OPTS="--with-lzma=`which xz`"
build_and_install_autotools \
  ${P} \
  ${URL} \
  ${CKSUM}

#
# Install pkg-config
# 

P=pkg-config-0.29.1
URL=https://pkg-config.freedesktop.org/releases/pkg-config-0.29.1.tar.gz
CKSUM=sha256:beb43c9e064555469bd4390dcfd8030b1536e0aa103f08d7abf7ae8cac0cb001

EXTRA_OPTS="--with-internal-glib" \
build_and_install_autotools \
  ${P} \
  ${URL} \
  ${CKSUM}


#
# Install CMake
#

P=cmake-3.7.2
URL=http://cmake.org/files/v3.7/cmake-3.7.2.tar.gz
CKSUM=sha256:dc1246c4e6d168ea4d6e042cfba577c1acd65feea27e56f5ff37df920c30cae0
T=${P}

if [ ! -f ${TMP_DIR}/.${P}.done ]; then

 fetch "${P}" "${URL}" "" "" "${CKSUM}"
 unpack ${P} ${URL}

 cd ${TMP_DIR}/${T} \
   && ./bootstrap \
   && ${MAKE} \
   && \
     ./bin/cmake \
       -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/usr \
       -P cmake_install.cmake \
   || E "failed to build cmake"

 touch ${TMP_DIR}/.${P}.done

fi

#
# Install Boost
# 

  P=boost_1_63_0
  URL=https://mirror.csclub.uwaterloo.ca/gentoo-distfiles/distfiles/boost_1_63_0.tar.bz2
  CKSUM=sha256:beae2529f759f6b3bf3f4969a19c2e9d6f0c503edcb2de4a61d1428519fcb3b0
  T=${P}

if [ ! -f ${TMP_DIR}/.${P}.done ]; then

  fetch "${P}" "${URL}" "" "" "${CKSUM}"
  unpack ${P} ${URL}

  cd ${TMP_DIR}/${T} \
    && sh bootstrap.sh \
    && ./b2 \
      -j $(ncpus) \
      stage \
    && rsync -avr stage/lib/ ${INSTALL_DIR}/usr/lib/ \
    && rsync -avr boost ${INSTALL_DIR}/usr/include \
    || E "building boost failed"
  
  touch ${TMP_DIR}/.${P}.done

fi

#
# Install PCRE
# 

  P=pcre-8.40
  URL=http://pilotfiber.dl.sourceforge.net/project/pcre/pcre/8.40/pcre-8.40.tar.gz
  CKSUM=sha256:1d75ce90ea3f81ee080cdc04e68c9c25a9fb984861a0618be7bbf676b18eda3e

  EXTRA_OPTS="--enable-utf" \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}

#
# Install Swig
# 

P=swig-3.0.12
URL=http://pilotfiber.dl.sourceforge.net/project/swig/swig/${P}/${P}.tar.gz
CKSUM=sha256:7cf9f447ae7ed1c51722efc45e7f14418d15d7a1e143ac9f09a668999f4fc94d

SKIP_AUTORECONF=yes \
SKIP_LIBTOOLIZE=yes \
build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}

#
# Install ffi
# 

P=libffi-3.2.1
URL=ftp://sourceware.org/pub/libffi/libffi-3.2.1.tar.gz
CKSUM=sha256:d06ebb8e1d9a22d19e38d63fdb83954253f39bedc5d46232a05645685722ca37

build_and_install_autotools \
  ${P} \
  ${URL} \
  ${CKSUM}

#
# Install glib
# 

P=glib-2.51.1
URL='http://gensho.acc.umu.se/pub/gnome/sources/glib/2.51/glib-2.51.1.tar.xz'
CKSUM=sha256:1f8e40cde43ac0bcf61defb147326d038310d75d4e50f728f6becfd2a36ac0ac
    
# mac os x linker seems to grab the /usr/lib version of libpcre rather than ${INSTALL_DIR}/usr/lib
# hopefully this is just a glib bug and not a systematic failure with
# the mac linker

SKIP_AUTORECONF=yes \
SKIP_LIBTOOLIZE=yes \
EXTRA_OPTS="--with-pcre=internal" \
build_and_install_autotools \
  ${P} \
  ${URL} \
  ${CKSUM}

#
# Install cppunit
# 

  P=cppunit-1.12.1
  URL='http://iweb.dl.sourceforge.net/project/cppunit/cppunit/1.12.1/cppunit-1.12.1.tar.gz'
  CKSUM=sha256:ac28a04c8e6c9217d910b0ae7122832d28d9917fa668bcc9e0b8b09acb4ea44a

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}

#
# Install mako
# 

  P=Mako-1.0.3
  URL=https://mirror.csclub.uwaterloo.ca/gentoo-distfiles/distfiles/Mako-1.0.3.tar.gz
  CKSUM=sha256:7644bc0ee35965d2e146dde31827b8982ed70a58281085fac42869a09764d38c

LDFLAGS="${LDFLAGS} $(python-config --ldflags)" \
build_and_install_setup_py \
   ${P} \
   ${URL} \
   ${CKSUM}

#
# Install bison
# 

    P=bison-3.0.4
    URL='http://ftp.gnu.org/gnu/bison/bison-3.0.4.tar.xz'
    CKSUM=sha256:a72428c7917bdf9fa93cb8181c971b6e22834125848cf1d03ce10b1bb0716fe1

  SKIP_AUTORECONF=yes \
  build_and_install_autotools \
   ${P} \
   ${URL} \
   ${CKSUM}

#
# Install OpenSSL
# 
    P=openssl-1.1.0d
    URL='https://www.openssl.org/source/openssl-1.1.0d.tar.gz'
    CKSUM=sha256:7d5ebb9e89756545c156ff9c13cf2aa6214193b010a468a3bc789c3c28fe60df

  SKIP_AUTORECONF=yes \
  SKIP_LIBTOOLIZE=yes \
  EXTRA_OPTS="darwin64-x86_64-cc" \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}

#
# Install thrift
# 
    P=thrift-0.10.0
    URL='http://apache.mirror.gtcomm.net/thrift/0.10.0/thrift-0.10.0.tar.gz'
    CKSUM=sha256:2289d02de6e8db04cbbabb921aeb62bfe3098c4c83f36eec6c31194301efa10b

  PY_PREFIX="${INSTALL_DIR}/usr" \
  CXXFLAGS="${CPPFLAGS}" \
  EXTRA_OPTS="--without-perl --without-php" \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}

#
# Install orc
# 

    P=orc-0.4.26
    URL='https://mirror.csclub.uwaterloo.ca/gentoo-distfiles/distfiles/orc-0.4.26.tar.xz'
    CKSUM=sha256:7d52fa80ef84988359c3434e1eea302d077a08987abdde6905678ebcad4fa649

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}

#
# Install Cheetah
# 

    P=Cheetah-2.4.4
    URL='https://mirror.csclub.uwaterloo.ca/gentoo-distfiles/distfiles/Cheetah-2.4.4.tar.gz'
    CKSUM=sha256:be308229f0c1e5e5af4f27d7ee06d90bb19e6af3059794e5fd536a6f29a9b550

  LDFLAGS="${LDFLAGS} $(python-config --ldflags)" \
  build_and_install_setup_py \
    ${P} \
    ${URL} \
    ${CKSUM} \
  && ln -sf ${PYTHONPATH}/${P}-py2.7.egg ${PYTHONPATH}/Cheetah.egg

#
# Install lxml
# 

    P=lxml-3.7.3
    URL='https://mirror.csclub.uwaterloo.ca/gentoo-distfiles/distfiles/lxml-3.7.3.tar.gz'
    CKSUM=sha256:aa502d78a51ee7d127b4824ff96500f0181d3c7826e6ee7b800d068be79361c7

LDFLAGS="${LDFLAGS} $(python-config --ldflags)" \
  build_and_install_setup_py \
    ${P} \
    ${URL} \
    ${CKSUM}

#
# Install pygobject-introspection
# 

    P=gobject-introspection-1.40.0
    URL='http://ftp.gnome.org/pub/gnome/sources/gobject-introspection/1.40/gobject-introspection-1.40.0.tar.xz'
    CKSUM=sha256:96ea75e9679083e7fe39a105e810e2ead2d708abf189a5ba420bfccfffa24e98

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}

#
# Install libtiff
#

P=tiff-3.8.2
URL='http://dl.maptools.org/dl/libtiff/tiff-3.8.2.tar.gz'
CKSUM=sha256:be88f037080b93ce0a337b2b3ca5e8195f76885deb6c558cc3aa872ee848fc76

  SKIP_AUTORECONF=yes \
  SKIP_LIBTOOLIZE=yes \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}

unset SKIP_AUTORECONF
unset SKIP_LIBTOOLIZE

#
# Install png
# 

P=libpng-1.6.28
URL='https://mirror.csclub.uwaterloo.ca/gentoo-distfiles/distfiles/libpng-1.6.28.tar.xz'
CKSUM=sha256:d8d3ec9de6b5db740fefac702c37ffcf96ae46cb17c18c1544635a3852f78f7a

build_and_install_autotools \
  ${P} \
  ${URL} \
  ${CKSUM}

#
# Install jpeg
#

P=jpegsrc.v6b
URL=http://mirror.csclub.uwaterloo.ca/slackware/slackware-8.1/source/ap/ghostscript/jpegsrc.v6b.tar.gz
CKSUM=sha256:75c3ec241e9996504fe02a9ed4d12f16b74ade713972f3db9e65ce95cd27e35d
T=jpeg-6b

  SKIP_AUTORECONF=yes \
  SKIP_LIBTOOLIZE=yes \
  EXTRA_OPTS="--mandir=${INSTALL_DIR}/usr/share/man" \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM} \
    ${T}


#
# Install pixman
# 

    P='pixman-0.34.0'
    URL='https://mirror.csclub.uwaterloo.ca/gentoo-distfiles/distfiles/pixman-0.34.0.tar.bz2'
    CKSUM=sha256:39ba3438f3d17c464b0cb8be006dacbca0ab5aee97ebde69fec7ecdbf85794a0

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}

#
# Install freetype
# 

    P=freetype-2.7
    URL='http://mirror.csclub.uwaterloo.ca/nongnu//freetype/freetype-2.7.tar.gz'
    CKSUM=sha256:7b657d5f872b0ab56461f3bd310bd1c5ec64619bd15f0d8e08282d494d9cfea4

  SKIP_AUTORECONF=yes \
  SKIP_LIBTOOLIZE=yes \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}


#
# Install harfbuzz
# 

  P=harfbuzz-1.4.3
  URL='https://mirror.csclub.uwaterloo.ca/gentoo-distfiles/distfiles/harfbuzz-1.4.3.tar.bz2'
  CKSUM=sha256:838c17400a88a3a451eb401573ef94cdd50919730d98255547c459fef1d85321

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}

#
# Install fontconfig
# 

  P=fontconfig-2.12.1
  URL='https://mirror.csclub.uwaterloo.ca/gentoo-distfiles/distfiles/fontconfig-2.12.1.tar.bz2'
  CKSUM=sha256:b449a3e10c47e1d1c7a6ec6e2016cca73d3bd68fbbd4f0ae5cc6b573f7d6c7f3

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}

#
# Install cairo
# 

    P=cairo-1.14.8
    URL='https://mirror.csclub.uwaterloo.ca/gentoo-distfiles/distfiles/cairo-1.14.8.tar.xz'
    CKSUM=sha256:d1f2d98ae9a4111564f6de4e013d639cf77155baf2556582295a0f00a9bc5e20

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}

#
# Install pycairo
# 

    P=py2cairo-1.10.0
    URL='https://mirror.csclub.uwaterloo.ca/gentoo-distfiles/distfiles/py2cairo-1.10.0.tar.bz2'
    CKSUM=sha256:d30439f06c2ec1a39e27464c6c828b6eface3b22ee17b2de05dc409e429a7431

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}

#
# Install pygobject
# 

    P=pygobject-2.28.6
    URL='http://ftp.gnome.org/pub/GNOME/sources/pygobject/2.28/pygobject-2.28.6.tar.xz'
    CKSUM=sha256:fb8a1d4f665130a125011659bd347c7339c944232163dbb9a34fd0686577adb8

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}

#
# Install gdk-pixbuf
# 

  P=gdk-pixbuf-2.36.4
  URL='http://muug.ca/mirror/gnome/sources/gdk-pixbuf/2.36/gdk-pixbuf-2.36.4.tar.xz'
  CKSUM=sha256:0b19901c3eb0596141d2d48ddb9dac79ad1524bdf59366af58ab38fcb9ee7463

  EXTRA_OPTS="--without-libtiff --without-libjpeg" \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}

#
# Install libatk
# 

  P=ATK_2_22
  URL='http://git.gnome.org/browse/atk/snapshot/ATK_2_22.tar.xz'
  CKSUM=sha256:27d4dc33283787e77935ac725aaf4d1bd283feb18898072bfecf61183b71a1b9

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}

#
# Install pango
# 

# this is unfortunately the only stage of the build that I have not
# fully automated.
# encountering this bug
# http://groups.google.com/forum/#!topic/bugzillagnometelconnect4688-bugzillagnometelconnect4688/gcf7EtF9icA

#  P=pango-1.40.3
#  URL=http://ftp.gnome.org/pub/GNOME/sources/pango/1.40/pango-1.40.3.tar.xz

  P=pango-1.39.0
  URL='http://ftp.gnome.org/pub/GNOME/sources/pango/1.39/pango-1.39.0.tar.xz'
  CKSUM=sha256:13072ad9e49372d6d7ba7bb3b9b025faef04de3552b745e92d7880eb15d6ee7e

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}

#
# Install gtk+
# 
  P=gtk+-2.24.31
  URL='http://gemmei.acc.umu.se/pub/gnome/sources/gtk+/2.24/gtk+-2.24.31.tar.xz'
  CKSUM=sha256:68c1922732c7efc08df4656a5366dcc3afdc8791513400dac276009b40954658

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}

#
# Install pygtk
# 

    P=pygtk-2.24.0
    URL='http://ftp.gnome.org/pub/GNOME/sources/pygtk/2.24/pygtk-2.24.0.tar.gz'
    CKSUM=sha256:6e3e54fa6e65a69ac60bd58cb2e60a57f3346ac52efe995f3d10b6c38c972fd8

build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}

  #ln -sf ${INSTALL_DIR}/usr/lib/${PYTHON}/site-packages/{py,}gtk.py

#
# Install numpy
# 

  P=numpy-1.11.1
  URL='http://superb-sea2.dl.sourceforge.net/project/numpy/NumPy/1.11.1/numpy-1.11.1.tar.gz'
  CKSUM=sha256:dc4082c43979cc856a2bf352a8297ea109ccb3244d783ae067eb2ee5b0d577cd

  build_and_install_setup_py \
    ${P} \
    ${URL} \
    ${CKSUM}

#
# Install fftw
# 

  P=fftw-3.3.6-pl1
  URL='http://www.fftw.org/fftw-3.3.6-pl1.tar.gz'
  CKSUM=sha256:1ef4aa8427d9785839bc767f3eb6a84fcb5e9a37c31ed77a04e7e047519a183d

  EXTRA_OPTS="--enable-single --enable-sse --enable-sse2 --enable-avx --enable-avx2 --enable-avx-128-fma --enable-generic-simd128 --enable-generic-simd256 --enable-threads" \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}

#
# Install f2c
#

P=f2c
URL=http://github.com/barak/f2c.git
CKSUM=git:fa8ccce5c4ab11d08b875379c5f0629098261f32
T=${P}
BRANCH=master

if [ ! -f ${TMP_DIR}/.${P}.done ]; then

  fetch "${P}" "${URL}" "${T}" "${BRANCH}" "${CKSUM}"
  unpack ${P} ${URL} ${T} ${BRANCH}
  
  cd ${TMP_DIR}/${T}/src \
  && rm -f Makefile \
  && cp makefile.u Makefile \
  && I building f2c \
  && ${MAKE} \
  && I installing f2c \
  && cp f2c ${INSTALL_DIR}/usr/bin \
  && cp f2c.h ${INSTALL_DIR}/usr/include \
  && sed -e 's,^\([[:space:]]*CFLAGS[[:space:]]*=\).*$,\1"-I'"${INSTALL_DIR}"'/usr/include",' < "${BUILD_DIR}/scripts/gfortran-wrapper.sh" > "${INSTALL_DIR}/usr/bin/gfortran" \
  && chmod +x ${INSTALL_DIR}/usr/bin/gfortran \
    || E "failed to build and install f2c"  

  touch ${TMP_DIR}/.${P}.done
fi

#
# Install libf2c
#

P=libf2c-20130927
URL=http://mirror.csclub.uwaterloo.ca/gentoo-distfiles/distfiles/libf2c-20130927.zip
CKSUM=sha256:5dff29c58b428fa00cd36b1220e2d71b9882a658fdec1aa094fb7e6e482d6765
T=${P}
BRANCH=""

if [ ! -f ${TMP_DIR}/.${P}.done ]; then

  fetch "${P}" "${URL}" "${T}" "${BRANCH}" "${CKSUM}"
  
  rm -Rf ${TMP_DIR}/${T} \
  && mkdir -p ${TMP_DIR}/${T} \
  && cd ${TMP_DIR}/${T} \
  && unzip ${TMP_DIR}/${P}.zip \
  || E "failed to extract ${P}.zip"
  
  cd ${TMP_DIR}/${T}/ \
  && rm -f Makefile \
  && cp makefile.u Makefile \
  && I building ${P} \
  && ${MAKE} \
  && I installing ${P} \
  && cp libf2c.a ${INSTALL_DIR}/usr/lib \
  || E "failed to build and install libf2c"

#  && mkdir -p foo \
#  && cd foo \
#  && ar x ../libf2c.a \
#  && rm main.o getarg_.o iargc_.o \
#  && \
#  ${CC} \
#    ${LDFLAGS} \
#    -dynamiclib \
#    -install_name ${INSTALL_DIR}/usr/lib/libf2c.dylib \
#    -o ../libf2c.dylib \
#    *.o \
#  && cd .. \

  touch ${TMP_DIR}/.${P}.done
fi

#
# Install blas
#

P=blas-3.7.0
URL=http://www.netlib.org/blas/blas-3.7.0.tgz
CKSUM=sha256:55415f901bfc9afc19d7bd7cb246a559a748fc737353125fcce4c40c3dee1d86
T=BLAS-3.7.0
BRANCH=""

if [ ! -f ${TMP_DIR}/.${P}.done ]; then

  fetch "${P}" "${URL}" "${T}" "${BRANCH}" "${CKSUM}"
  unpack ${P} ${URL} ${T} ${BRANCH}
  
  cd ${TMP_DIR}/${T}/ \
  && I building ${P} \
  && \
    for i in *.f; do \
      j=${i/.f/.c} \
      && k=${j/.c/.o} \
      && I "f2c ${i} > ${j}" \
      && f2c ${i} > ${j} 2>/dev/null \
      && I "[CC] ${k}" \
      && \
        ${CC} \
          -I${INSTALL_DIR}/usr/include \
          -c ${j} \
          -o ${k} \
      || E "build of ${P} failed"; \
    done \
  && I creating libblas.a \
  && libtool -static -o libblas.a *.o \
  && cp libblas.a ${INSTALL_DIR}/usr/lib/ \
  || E "failed to build and install libblas"  

#  && I creating libblas.dylib \
#  && \
#    ${CC} \
#      ${LDFLAGS} \
#      -dynamiclib \
#      -install_name ${INSTALL_DIR}/usr/lib/libblas.dylib \
#      -o libblas.dylib \
#      *.o \
#      -lf2c \
  
  touch ${TMP_DIR}/.${P}.done
fi

#
# Install cblas
# 
# XXX: @CF: requires either f2c or gfortran, both of which I don't care for right now
  P=cblas
  URL='http://www.netlib.org/blas/blast-forum/cblas.tgz'
  CKSUM=sha256:0f6354fd67fabd909baf57ced2ef84e962db58fae126e4f41b21dd4fec60a2a3
  T=CBLAS
  BRANCH=""

if [ ! -f ${TMP_DIR}/.${P}.done ]; then

  fetch "${P}" "${URL}" "${T}" "${BRANCH}" "${CKSUM}"
  unpack ${P} ${URL} ${T} ${BRANCH}

  cd ${TMP_DIR}/${T}/src \
  && cd ${TMP_DIR}/${T}/src \
  && I compiling.. \
  && ${MAKE} CFLAGS="${CPPFLAGS} -DADD_" all \
  && I building static library \
  && mkdir -p ${TMP_DIR}/${T}/libcblas \
  && cd ${TMP_DIR}/${T}/libcblas \
  && ar x ${TMP_DIR}/${T}/lib/cblas_LINUX.a \
  && libtool -static -o ../libcblas.a *.o \
  && cd ${TMP_DIR}/${T} \
  && I installing ${P} to ${INSTALL_DIR}/usr/lib \
  && cp ${TMP_DIR}/${T}/libcblas.* ${INSTALL_DIR}/usr/lib \
  && cp ${TMP_DIR}/${T}/include/*.h ${INSTALL_DIR}/usr/include \
  || E failed to make cblas

#  && I building dynamic library \
#  && cd ${TMP_DIR}/${T}/lib/ \
#  && mkdir foo \
#  && cd foo \
#  && ar x ../*.a \
#  && ${CC} \
#    ${LDFLAGS} \
#    -dynamiclib \
#    -install_name ${INSTALL_DIR}/usr/lib/libcblas.dylib \
#    -o ${TMP_DIR}/${T}/lib/libcblas.dylib \
#    *.o \
#    -lf2c \
#    -lblas \


#  && \
#  for i in *.f; do \
#    j=${i/.f/.c} \
#    && I converting ${i} to ${j} using f2c \
#    && f2c ${i} | tee ${j} \
#    && mv ${i}{,_ignore} \
#    || E f2c ${i} failed; \
#  done \
#  && I done converting .f to .c \

  touch ${TMP_DIR}/.${P}.done
fi

#
# Install gnu scientific library
# 
# XXX: @CF: required by gr-wavelet, depends on cblas

  P=gsl-2.3
  URL='http://mirror.frgl.pw/gnu/gsl/gsl-2.3.tar.gz'
  CKSUM=sha256:562500b789cd599b3a4f88547a7a3280538ab2ff4939504c8b4ac4ca25feadfb

  LDFLAGS="${LDFLAGS} -lcblas -lblas -lf2c" \
  EXTRA_OPTS="" \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}

#
# Install libusb
# 

  P=libusb-1.0.21
  URL='http://fco.it.distfiles.macports.org/mirrors/macports-distfiles/libusb/libusb-1.0.21.tar.gz'
  CKSUM=sha256:acb5ca3379cecf7bf53901b8e98192723909f696af04bd63fca0cfafec5b057c
  T=libusb-libusb-09e75e9

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM} \
    ${T}

#
# Install uhd
#

  P=uhd
  URL=git://github.com/EttusResearch/uhd.git
  CKSUM=git:c705922a08e32c8b0ec7ef6af6137835f87b2f42
  T=${P}
  BRANCH=release_003_010_001_001

  EXTRA_OPTS="-DENABLE_E300=ON -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/usr ${TMP_DIR}/${T}/host" \
  build_and_install_cmake \
    ${P} \
    ${URL} \
    ${CKSUM} \
    ${T} \
    ${BRANCH}

# XXX: seems to cause some compile errors in gr-video-sdl atm
#if [ 1 -eq 1 ]; then

#
# install SDL
#

#build_and_install_autotools \
#  SDL2-2.0.5 \
#  'http://www.libsdl.org/release/SDL2-2.0.5.tar.gz' \
#  sha256:442038cf55965969f2ff06d976031813de643af9c9edc9e331bd761c242e8785

#fi

#
# Install libzmq
#

  P=libzmq
  URL=git://github.com/zeromq/libzmq.git
  CKSUM=git:d17581929cceceda02b4eb8abb054f996865c7a6
  T=${P}

  EXTRA_OPTS="-DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/usr ${TMP_DIR}/${T}" \
  build_and_install_cmake \
    ${P} \
    ${URL} \
    ${CKSUM}

#
# Install cppzmq
#

  P=cppzmq
  URL=git://github.com/zeromq/cppzmq.git
  CKSUM=git:178a910ae1abaad59467ee38884289b8a29c5710
  T=${P}
  BRANCH=v4.2.1

  EXTRA_OPTS="-DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/usr ${TMP_DIR}/${T}" \
  build_and_install_cmake \
    ${P} \
    ${URL} \
    ${CKSUM} \
    ${T} \
    ${BRANCH}


#
# Get wx widgets
#

P=wxWidgets-3.0.2
URL='http://pkgs.fedoraproject.org/repo/pkgs/wxGTK3/wxWidgets-3.0.2.tar.bz2/md5/ba4cd1f3853d0cd49134c5ae028ad080/wxWidgets-3.0.2.tar.bz2'
CKSUM=sha256:346879dc554f3ab8d6da2704f651ecb504a22e9d31c17ef5449b129ed711585d
T=${P}

  SKIP_AUTORECONF=yes \
  SKIP_LIBTOOLIZE=yes \
  EXTRA_OPTS="--with-gtk --enable-utf8only" \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}

#
# install wxpython
#

  P=wxPython-src-3.0.2.0
  URL=http://svwh.dl.sourceforge.net/project/wxpython/wxPython/3.0.2.0/wxPython-src-3.0.2.0.tar.bz2
  CKSUM=sha256:d54129e5fbea4fb8091c87b2980760b72c22a386cb3b9dd2eebc928ef5e8df61
  T=${P}
  BRANCH=""

  if [ -f ${TMP_DIR}/.${P}.done ]; then
    I "already installed ${P}"    
  else 

  fetch "${P}" "${URL}" "${T}" "${BRANCH}" "${CKSUM}"
  unpack ${P} ${URL} ${T}

  _extra_cflags="$(pkg-config --cflags gtk+-2.0) $(pkg-config --cflags libgdk-x11) $(pkg-config --cflags x11)"
  _extra_libs="$(pkg-config --libs gtk+-2.0) $(pkg-config --libs gdk-x11-2.0) $(pkg-config --libs x11)"

  D "Configuring and building in ${T}"
  cd ${TMP_DIR}/${T}/wxPython \
    && \
      CC=${CXX} \
      CFLAGS="${CPPFLAGS} ${_extra_cflags} ${CFLAGS}" \
      CXXFLAGS="${CPPFLAGS} ${_extra_cflags} ${CXXFLAGS}" \
      LDFLAGS="${LDFLAGS} ${_extra_libs}" \
      ${PYTHON} setup.py WXPORT=gtk2 ARCH=x86_64 build \
    && \
      CC=${CXX} \
      CFLAGS="${CPPFLAGS} ${_extra_cflags} ${CFLAGS}" \
      CXXFLAGS="${CPPFLAGS} ${_extra_cflags} ${CXXFLAGS}" \
      LDFLAGS="${LDFLAGS} ${_extra_libs}" \
      ${PYTHON} setup.py WXPORT=gtk2 ARCH=x86_64 install \
        --prefix="${INSTALL_DIR}/usr" \
    && D "copying wx.pth to ${PYTHONPATH}/wx.pth" \
    && cp \
       ${TMP_DIR}/${T}/wxPython/src/wx.pth \
       ${PYTHONPATH} \
    || E "failed to build and install ${P}"

  I "finished building and installing ${P}"
  
  touch ${TMP_DIR}/.${P}.done

fi

#
# Install rtl-sdr
#

  P=rtl-sdr
  URL=git://git.osmocom.org/rtl-sdr
  CKSUM=git:df9596b2d1ebd36cdb14549cfdd76c25092e14d0
  T=${P}
  BRANCH=v0.5.3

  LDFLAGS="${LDFLAGS} $(python-config --ldflags)" \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM} \
    ${T} \
    ${BRANCH}

#
# Install QT
#

P=qt-x11-opensource-src-4.4.3
URL=http://mirror.csclub.uwaterloo.ca/qtproject/archive/qt/4.4/qt-x11-opensource-src-4.4.3.tar.gz
CKSUM=sha256:79ea9fb46d75c3759e3e98ab0064a47eaa5bdbbc2a53d923d60bd8e9cd0bc5c6
T=${P}
BRANCH=""

if [ -f ${TMP_DIR}/.${P}.done ]; then
    I "already installed ${P}"
else
  INSTALL_QGL="yes"
  rm -Rf ${INSTALL_DIR}/usr/lib/libQt*
  rm -Rf ${INSTALL_DIR}/usr/include/Qt*

  fetch "${P}" "${URL}" "${T}" "${BRANCH}" "${CKSUM}"
  unpack ${P} ${URL} ${T} ${BRANCH}
  
  I configuring ${P} \
  && cd ${TMP_DIR}/${T} \
  && export OPENSOURCE_CXXFLAGS="-D__USE_WS_X11__" \
  && sh configure                                              \
    -v                                                         \
    -confirm-license                                           \
    -continue                                                  \
    -release                                                   \
    -prefix          ${INSTALL_DIR}/usr                                 \
    -docdir          ${INSTALL_DIR}/usr/share/doc/${name}               \
    -examplesdir     ${INSTALL_DIR}/usr/share/${name}/examples          \
    -demosdir        ${INSTALL_DIR}/usr/share/${name}/demos             \
    -stl \
    -no-qt3support \
    -no-xmlpatterns \
    -no-phonon \
    -no-phonon-backend \
    -no-webkit \
    -no-libmng \
    -nomake demos \
    -nomake examples \
    -system-libpng \
    -no-gif \
    -system-libtiff \
    -no-nis \
    -no-openssl \
    -no-dbus \
    -no-cups \
    -no-iconv \
    -no-pch \
    -arch x86_64 \
    -L${INSTALL_DIR}/usr/lib                                            \
    -liconv                                                    \
    -lresolv                                                   \
    -I${INSTALL_DIR}/usr/include \
    -I${INSTALL_DIR}/usr/include/glib-2.0                               \
    -I${INSTALL_DIR}/usr/lib/glib-2.0/include                           \
    -I${INSTALL_DIR}/usr/include/libxml2 \
  || E failed to configure ${P}
  
  # qmake obviously still has some Makefile generation issues..
  for i in $(find * -name 'Makefile*'); do
    j=${i}.tmp
    cat ${i} \
      | sed \
        -e 's|-framework\ -framework||g' \
        -e 's|-framework\ -prebind||g' \
      > ${j}
    mv ${j} ${i}    
  done 
  
  I building ${P} \
  && ${MAKE} \
  || E failed to build ${P}
  
  I installing ${P} \
  && ${MAKE} install \
  || E failed to install ${P}


  if [ "yes" = "${INSTALL_QGL}" ]; then
    cd ${TMP_DIR}/${T} \
    && cd src/opengl \
    && ${MAKE} \
    && ${MAKE} install \
    || E "failed to install qgl"
  fi

  touch ${TMP_DIR}/.${P}.done

fi

#
# Install qwt
#

P=qwt-6.1.3
URL=http://cytranet.dl.sourceforge.net/project/qwt/qwt/6.1.3/qwt-6.1.3.tar.bz2
CKSUM=sha256:f3ecd34e72a9a2b08422fb6c8e909ca76f4ce5fa77acad7a2883b701f4309733
T=${P}
BRANCH=""

QMAKE_CXX="${CXX}" \
QMAKE_CXXFLAGS="${CPPFLAGS}" \
QMAKE_LFLAGS="${LDFLAGS}" \
EXTRA_OPTS="qwt.pro" \
build_and_install_qmake \
  ${P} \
  ${URL} \
  ${CKSUM} \
  ${T} \
  ${BRANCH}

#
# Install sip
#

P=sip-4.19.1
URL=http://svwh.dl.sourceforge.net/project/pyqt/sip/sip-4.19.1/sip-4.19.1.tar.gz
CKSUM=sha256:501852b8325349031b769d1c03d6eab04f7b9b97f790ec79f3d3d04bf065d83e
T=${P}
BRANCH=""

if [ -f ${TMP_DIR}/.${P}.done ]; then
  I already installed ${P}
else
  fetch "${P}" "${URL}" "${T}" "${BRANCH}" "${CKSUM}"
  unpack ${P} ${URL} ${T} ${BRANCH}
  
  cd ${TMP_DIR}/${T} \
  && ${PYTHON} configure.py \
    --arch=x86_64 \
    -b ${INSTALL_DIR}/usr/bin \
    -d ${PYTHONPATH} \
    -e ${INSTALL_DIR}/usr/include \
    -v ${INSTALL_DIR}/usr/share/sip \
    --stubsdir=${PYTHONPATH} \
  && ${MAKE} \
  && ${MAKE} install \
  || E failed to build
    
  touch ${TMP_DIR}/.${P}.done
fi

#
# Install PyQt4
#

P=PyQt4_gpl_x11-4.12
URL=http://superb-sea2.dl.sourceforge.net/project/pyqt/PyQt4/PyQt-4.12/PyQt4_gpl_x11-4.12.tar.gz
CKSUM=sha256:3c1d4b55314adb3e1132de8fc2a92eed216d37e58aceed41294dbca210ca88db
T=${P}
BRANCH=""

if [ -f ${TMP_DIR}/.${P}.done ]; then
  I already installed ${P}
else
  fetch "${P}" "${URL}" "${T}" "${BRANCH}" "${CKSUM}"
  unpack ${P} ${URL} ${T} ${BRANCH}
  
  cd ${TMP_DIR}/${T} \
  && \
  CFLAGS="${CPPFLAGS} $(pkg-config --cflags QtCore QtDesigner QtGui QtOpenGL)" \
  CXXFLAGS="${CPPFLAGS} $(pkg-config --cflags QtCore QtDesigner QtGui QtOpenGL)" \
  LDFLAGS="$(pkg-config --libs QtCore QtDesigner QtGui QtOpenGL)" \
  ${PYTHON} configure.py \
    --confirm-license \
    -b ${INSTALL_DIR}/usr/bin \
    -d ${PYTHONPATH} \
    -v ${INSTALL_DIR}/usr/share/sip \
  && ${MAKE} \
  && ${MAKE} install \
  || E failed to build
    
  touch ${TMP_DIR}/.${P}.done
fi

#
# Install gnuradio
#

P=gnuradio
URL=git://github.com/gnuradio/gnuradio.git
CKSUM=git:59daaff0d9d04373d3a6b14ea7b46e080bad7a1e
T=${P}
BRANCH=v${GNURADIO_BRANCH}

if [ ! -f ${TMP_DIR}/.${P}.done ]; then

  fetch "${P}" "${URL}" "${T}" "${BRANCH}" "${CKSUM}"
  unpack ${P} ${URL} ${T} ${BRANCH}
  
  rm -Rf ${TMP_DIR}/${T}/volk
  
  fetch volk git://github.com/gnuradio/volk.git gnuradio/volk v1.3 git:4465f9b26354e555e583a7d654710cb63cf914ce
  unpack volk git://github.com/gnuradio/volk.git gnuradio/volk v1.3

EXTRA_OPTS="\
  -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/usr \
  -DFFTW3F_INCLUDE_DIRS=${INSTALL_DIR}/usr/include \
  -DZEROMQ_INCLUDE_DIRS=${INSTALL_DIR}/usr/include \
  -DTHRIFT_INCLUDE_DIRS=${INSTALL_DIR}/usr/include \
  -DCPPUNIT_INCLUDE_DIRS=${INSTALL_DIR}/usr/include/cppunit \
  -DPYTHON_EXECUTABLE=$(which ${PYTHON}) \
  '-DCMAKE_C_FLAGS=-framework Python' \
  '-DCMAKE_CXX_FLAGS=-framework Python' \
  -DSPHINX_EXECUTABLE=${INSTALL_DIR}/usr/bin/rst2html-2.7.py \
  -DGR_PYTHON_DIR=${INSTALL_DIR}/usr/share/gnuradio/python/site-packages \
  ${TMP_DIR}/${T} \
" \
build_and_install_cmake \
  ${P} \
  ${URL} \
  ${CKSUM} \
  ${T} \
  ${BRANCH}
#&& \
#for i in $(find ${INSTALL_DIR}/usr/share/gnuradio/python/site-packages -name '*.so'); do \
#  ln -sf ${i} ${INSTALL_DIR}/usr/lib; \
#done

  touch ${TMP_DIR}/.${P}.done
fi


#      -DSDL_INCLUDE_DIR=${INSTALL_DIR}/usr/include/SDL2 \
#      -DSDL_LIBRARY=${INSTALL_DIR}/usr/lib/libSDL2-2.0.0.dylib \
#

#
# Install osmo-sdr
#

P=osmo-sdr-0.1
URL=http://cgit.osmocom.org/osmo-sdr/snapshot/osmo-sdr-0.1.tar.xz
CKSUM=sha256:ac488768ad735dd6ca0ba594643f831e2b62747244da9a233264c11a96bc1f96
T=${P}/software/libosmosdr

EXTRA_OPTS="" \
build_and_install_autotools \
  ${P} \
  ${URL} \
  ${CKSUM} \
  ${T}

#
# Install libhackrf
#

P=hackrf-2017.02.1
URL=http://mirror.csclub.uwaterloo.ca/gentoo-distfiles/distfiles/hackrf-2017.02.1.tar.xz
CKSUM=sha256:1dd1fbec98bf2fa56c92f82fd66eb46801a2248c019c4707b3971bc187cb973a
T=${P}/host

EXTRA_OPTS="-DCMAKE_MACOSX_RPATH=OLD -DCMAKE_INSTALL_NAME_DIR=${INSTALL_DIR}/usr/lib -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/usr -DCMAKE_C_FLAGS=\"-I${INSTALL_DIR}/usr/include\" ${TMP_DIR}/${T}" \
build_and_install_cmake \
  ${P} \
  ${URL} \
  ${CKSUM} \
  ${T}

#
# Install libbladerf
#

P=bladeRF-2016.06
URL=http://mirror.csclub.uwaterloo.ca/gentoo-distfiles/distfiles/bladerf-2016.06.tar.gz
CKSUM=sha256:6e6333fd0f17e85f968a6180942f889705c4f2ac16507b2f86c80630c55032e8
T=${P}/host

EXTRA_OPTS="-DCMAKE_MACOSX_RPATH=OLD -DCMAKE_INSTALL_NAME_DIR=${INSTALL_DIR}/usr/lib -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/usr -DCMAKE_C_FLAGS=\"-I${INSTALL_DIR}/usr/include\" ${TMP_DIR}/${T}" \
build_and_install_cmake \
  ${P} \
  ${URL} \
  ${CKSUM} \
  ${T}

#
# Install libairspy
#

P=airspy
URL=http://github.com/airspy/host.git
CKSUM=git:5c86e53c484140a4a5038a24e4f40f4fb8e6240d
T=${P}
BRANCH=v1.0.9

EXTRA_OPTS="-DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/usr -DCMAKE_C_FLAGS=\"-I${INSTALL_DIR}/usr/include\" ${TMP_DIR}/${T}" \
build_and_install_cmake \
  ${P} \
  ${URL} \
  ${CKSUM} \
  ${T} \
  ${BRANCH}

#
# Install libmirisdr
#

P=libmirisdr
URL=git://git.osmocom.org/libmirisdr
CKSUM=git:59ba3721b1cb7c746503d8de9c918f54fe7e8399
T=${P}
BRANCH=master

EXTRA_OPTS="" \
build_and_install_autotools \
  ${P} \
  ${URL} \
  ${CKSUM} \
  ${T} \
  ${BRANCH}

#
# Install gr-osmosdr
#

P=gr-osmosdr
URL=git://git.osmocom.org/gr-osmosdr
CKSUM=git:a45968f3381f33b86ca344bb76bd62c131d98d93
T=${P}
BRANCH=v0.1.4

LDFLAGS="${LDFLAGS} $(python-config --ldflags)" \
EXTRA_OPTS="-DCMAKE_MACOSX_RPATH=OLD -DCMAKE_INSTALL_NAME_DIR=${INSTALL_DIR}/usr/lib -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/usr -DPYTHON_EXECUTABLE=$(which ${PYTHON}) ${TMP_DIR}/${T}" \
build_and_install_cmake \
  ${P} \
  ${URL} \
  ${CKSUM} \
  ${T} \
  ${BRANCH}

## XXX: @CF: requires librsvg which requires Rust... meh!
##
## Install CairoSVG
## 
#
#  P=CairoSVG
#  URL=http://github.com/Kozea/CairoSVG.git
#  CKSUM=git:d7305b7f7239b51908688ad0c36fdf4ddd8f3dc9
#  T=${P}
#  BRANCH=1.0.22
#
#LDFLAGS="${LDFLAGS} $(python-config --ldflags)" \
#build_and_install_setup_py \
#  ${P} \
#  ${URL} \
#  ${CKSUM} \
#  ${T} \
#  ${BRANCH}

## XXX: @CF requires rust... FML!!
##
## Get rsvg-convert
##
#
#P=librsvg
#URL=git://git.gnome.org/librsvg
#CKSUM=git:e7aec5151543573c2f18484d4134959e219dc4a4
#T=${P}
#BRANCH=2.41.0
#
#  EXTRA_OPTS="" \
#  build_and_install_autotools \
#    ${P} \
#    ${URL} \
#    ${CKSUM} \
#    ${T} \
#    ${BRANCH}

#
# Install some useful scripts
#

P=scripts

# always recreate scripts
if [ 1 -eq 1 ]; then

  I creating grenv.sh script
  cat > ${INSTALL_DIR}/usr/bin/grenv.sh << EOF
PYTHON=${PYTHON}
INSTALL_DIR=${INSTALL_DIR}
ULPP=\${INSTALL_DIR}/usr/lib/\${PYTHON}/site-packages
PYTHONPATH=\${ULPP}:\${PYTHONPATH}
GRSHARE=\${INSTALL_DIR}/usr/share/gnuradio
GRPP=\${GRSHARE}/python/site-packages
PYTHONPATH=\${GRPP}:\${PYTHONPATH}
PATH=\${INSTALL_DIR}/usr/bin:/opt/X11/bin:\${PATH}

EOF

  if [ $? -ne 0 ]; then
    E unable to create grenv.sh script
  fi

  cd ${INSTALL_DIR}/usr/lib/${PYTHON}/site-packages \
  && \
    for j in $(for i in $(find * -name '*.so'); do dirname $i; done | sort -u); do \
      echo "DYLD_LIBRARY_PATH=\"\${ULPP}/${j}:\${DYLD_LIBRARY_PATH}\"" >> ${INSTALL_DIR}/usr/bin/grenv.sh; \
    done \
    && echo "" >> ${INSTALL_DIR}/usr/bin/grenv.sh \
  || E failed to create grenv.sh;
  
  cd ${INSTALL_DIR}/usr/share/gnuradio/python/site-packages \
  && \
    for j in $(for i in $(find * -name '*.so'); do dirname $i; done | sort -u); do \
      echo "DYLD_LIBRARY_PATH=\"\${GRPP}/${j}:\${DYLD_LIBRARY_PATH}\"" >> ${INSTALL_DIR}/usr/bin/grenv.sh; \
      echo "PYTHONPATH=\"\${GRPP}/${j}:\${PYTHONPATH}\"" >> ${INSTALL_DIR}/usr/bin/grenv.sh; \
    done \
  && echo "export DYLD_LIBRARY_PATH" >> ${INSTALL_DIR}/usr/bin/grenv.sh \
  && echo "export PYTHONPATH" >> ${INSTALL_DIR}/usr/bin/grenv.sh \
  && echo "export PATH" >> ${INSTALL_DIR}/usr/bin/grenv.sh \
  || E failed to create grenv.sh
  
  I installing find-broken-dylibs script \
  && mkdir -p ${INSTALL_DIR}/usr/bin \
  && cat ${BUILD_DIR}/scripts/find-broken-dylibs.sh \
      | sed -e "s|@INSTALL_DIR@|${INSTALL_DIR}|g" \
      > ${INSTALL_DIR}/usr/bin/find-broken-dylibs \
  && chmod +x ${INSTALL_DIR}/usr/bin/find-broken-dylibs \
  || E "failed to install 'find-broken-dylibs' script"

  I installing run-grc script \
  && mkdir -p ${INSTALL_DIR}/usr/bin \
  && cat ${BUILD_DIR}/scripts/run-grc.sh \
      > ${INSTALL_DIR}/usr/bin/run-grc \
  && chmod +x ${INSTALL_DIR}/usr/bin/run-grc \
  || E "failed to install 'run-grc' script"

fi

#
# Create the GNURadio.app bundle
# 

  P=gr-logo
  URL=http://github.com/gnuradio/gr-logo.git
  CKSUM=git:8f51887761b88b8c4facda0970ae121b61a0d905
  T=${P}
  BRANCH="master"

#if [ ! -f ${TMP_DIR}/.${P}.done ]; then

  fetch "${P}" "${URL}" "${T}" "${BRANCH}" "${CKSUM}"
  unpack ${P} ${URL} ${T} ${BRANCH} 

  # create the gnuradio.icns

#  create_icns_via_rsvg \
#    ${TMP_DIR}/${P}/gnuradio_logo_icon_square.svg \
#    ${TMP_DIR}/${P}/gnuradio.icns \
#  || E failed to create gnuradio.icns

#  create_icns_via_cairosvg \
#    ${TMP_DIR}/${P}/gnuradio_logo_icon_square.svg \
#    ${TMP_DIR}/${P}/gnuradio.icns \
#  || E failed to create gnuradio.icns

#  mkdir -p ${RESOURCES_DIR}/ \
#  && cp ${TMP_DIR}/${P}/gnuradio.icns ${RESOURCES_DIR}/ \
#  && I copied gnuradio.icns to ${RESOURCES_DIR} \
#  || E failed to install gnuradio.icns

  mkdir -p ${RESOURCES_DIR}/ \
  && cp ${BUILD_DIR}/gnuradio.icns ${RESOURCES_DIR}/ \
  && I copied gnuradio.icns to ${RESOURCES_DIR} \
  || E failed to install gnuradio.icns

  # create Info.plist

mkdir -p ${CONTENTS_DIR} \
&& I creating Info.plist \
&& cat > ${CONTENTS_DIR}/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleGetInfoString</key>
  <string>GNURadio</string>
  <key>CFBundleExecutable</key>
  <string>usr/bin/run-grc</string>
  <key>CFBundleIdentifier</key>
  <string>org.gnuradio.gnuradio-companion</string>
  <key>CFBundleName</key>
  <string>GNURadio</string>
  <key>CFBundleIconFile</key>
  <string>gnuradio.icns</string>
  <key>CFBundleShortVersionString</key>
  <string>${GNURADIO_BRANCH}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeExtensions</key>
      <array>
        <string>grc</string>
        <string>GRC</string>
        <string>grc.xml</string>
        <string>GRC.XML</string>
      </array>
      <key>CFBundleTypeIconFile</key>
      <string>gnuradio.icns</string>
      <key>CFBundleTypeMIMETypes</key>
      <array>
        <string>application/gnuradio-grc</string>
      </array>
      <key>CFBundleTypeName</key>
      <string>GNU Radio Companion Flow Graph</string>
      <key>CFBundleTypeOSTypes</key>
      <array>
        <string>GRC </string>
      </array>
      <key>CFBundleTypeRole</key>
      <string>Editor</string>
      <key>LSIsAppleDefaultForType</key>
      <true />
      <key>LSItemContentTypes</key>
      <array>
        <string>org.gnuradio.grc</string>
      </array>
    </dict>
  </array>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.xml</string>
      </array>
      <key>UTTypeDescription</key>
      <string>GNU Radio Companion Flow Graph</string>
      <key>UTTypeIconFile</key>
      <string>gnuradio.icns</string>
      <key>UTTypeIdentifier</key>
      <string>org.gnuradio.grc</string>
      <key>UTTypeReferenceURL</key>
      <string>http://www.gnuradio.org/</string>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>com.apple.ostype</key>
        <string>GRC </string>
        <key>public.filename-extension</key>
        <array>
          <string>grc</string>
          <string>GRC</string>
          <string>grc.xml</string>
          <string>GRC.XML</string>
        </array>
        <key>public.mime-type</key>
        <array>
          <string>application/gnuradio-grc</string>
        </array>
      </dict>
    </dict>
  </array>
</dict>
</plist>
EOF
if [ $? -ne 0 ]; then
  E failed to create Info.plist
fi
I created Info.plist

#  touch ${TMP_DIR}/.${P}.done 
#fi

I ============================================================================
I finding broken .dylibs and .so files in ${INSTALL_DIR}
I ============================================================================
"${INSTALL_DIR}/usr/bin/find-broken-dylibs"
I ============================================================================

I ============================================================================
I fixing library references to use @loader_path under ${INSTALL_DIR}
I ============================================================================
"${BUILD_DIR}/scripts/fix_library_references.py" "${INSTALL_DIR}"
I ============================================================================

#
# Create .dmg file
#

P=create-dmg
URL=http://github.com/andreyvit/create-dmg.git
CKSUM=git:5acf22fa87e1b751701f377efddc7429877ecb0a
T=${P}
BRANCH=master

#if [ ! -f ${TMP_DIR}/${P}.done ]; then

  fetch "${P}" "${URL}" "${T}" "${BRANCH}" "${CKSUM}"
  unpack ${P} ${URL} ${T} ${BRANCH}
  
  #XXX: @CF: add --eula option with GPLv3. For now, just distribute LICENSE in dmg
  
  cd ${TMP_DIR}/${P} \
  && I "copying GNURadio.app to temporary folder (this can take some time)" \
  && rm -Rf ${TMP_DIR}/${P}/temp \
  && rm -f ${BUILD_DIR}/*GNURadio-${GNURADIO_BRANCH}${GRFMWM_GIT_REVISION}.dmg \
  && mkdir -p ${TMP_DIR}/${P}/temp \
  && rsync -ar ${APP_DIR} ${TMP_DIR}/${P}/temp \
  && cp ${BUILD_DIR}/LICENSE ${TMP_DIR}/${P}/temp \
  && I "executing create-dmg.. (this can take some time)" \
  && I "create-dmg \
    --volname "GNURadio-${GNURADIO_BRANCH}${GRFMWM_GIT_REVISION}" \
    --volicon ${BUILD_DIR}/gnuradio.icns \
    --background ${BUILD_DIR}/gnuradio-logo-noicon.png \
    --window-pos 200 120 \
    --window-size 550 400 \
    --icon LICENSE 137 190 \
    --icon GNURadio.app 275 190 \
    --hide-extension GNURadio.app \
    --app-drop-link 412 190 \
    --icon-size 100 \
    ${BUILD_DIR}/GNURadio-${GNURADIO_BRANCH}${GRFMWM_GIT_REVISION}.dmg \
    ${TMP_DIR}/${P}/temp \
  " \
  && ./create-dmg \
    --volname "GNURadio-${GNURADIO_BRANCH}${GRFMWM_GIT_REVISION}" \
    --volicon ${BUILD_DIR}/gnuradio.icns \
    --background ${BUILD_DIR}/gnuradio-logo-noicon.png \
    --window-pos 200 120 \
    --window-size 550 400 \
    --icon LICENSE 137 190 \
    --icon GNURadio.app 275 190 \
    --hide-extension GNURadio.app \
    --app-drop-link 412 190 \
    --icon-size 100 \
    ${BUILD_DIR}/GNURadio-${GNURADIO_BRANCH}${GRFMWM_GIT_REVISION}.dmg \
    ${TMP_DIR}/${P}/temp \
  || E "failed to create GNURadio-${GNURADIO_BRANCH}${GRFMWM_GIT_REVISION}.dmg"

I "finished creating GNURadio-${GNURADIO_BRANCH}${GRFMWM_GIT_REVISION}.dmg"

#  touch ${TMP_DIR}/.${P}.done 
#fi

I '!!!!!! DONE !!!!!!'
