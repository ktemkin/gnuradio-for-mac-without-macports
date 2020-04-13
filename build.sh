#!/bin/sh

set -e
trap 'echo E: build failed with error on ${LINENO}; exit 1' ERR

# Ensure our subshells inherit our "set -e".
export SHELLOPTS

# Currently, we build gnuradio 3.8.1.0 for Python3.7.
GNURADIO_BRANCH=maint-3.8
GNURADIO_COMMIT_HASH=git:867b0ab9191ff6c6d5d8f49b5b95fdd884e92a07

GENTOO_MIRROR=https://mirrors.evowise.com/gentoo/distfiles

# default os x path minus /usr/local/bin, which could have pollutants
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

# Provide a list of the extensions we consider archives.
EXTS="zip tar.gz tgz tar.bz2 tbz2 tar.xz"

# Provide some basic defaults.
SKIP_FETCH=true
SKIP_AUTORECONF=
SKIP_LIBTOOLIZE=
KEEP_ON_MISMATCH=
COPY_HASH_ON_MISMATCH=true

# Uncomment the following line to enable more verbose build output.
DEBUG=true

function top_srcdir() {
  local r
  pushd "$(dirname "${0}")" > /dev/null
  r="$(pwd -P)"
  popd > /dev/null
  echo "${r}"
}

function I() {
  echo "I: ${@}" || true
}

function E() {
  echo "E: ${@}" > /dev/stderr
  exit 1;
}

function F() {
  E Failed to build package.
}

function D() {
  if [ "" != "$DEBUG" ]; then
    echo "D: ${@}"
  fi
}

function ncpus() {
  sysctl -n hw.ncpu
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

MAKE="${MAKE:-"make -j$(ncpus)"}"

PYTHON_VERSION=3.7
PYTHON_FRAMEWORK_DIR="/Library/Frameworks/Python.framework/Versions/${PYTHON_VERSION}"
PYTHON="${PYTHON_FRAMEWORK_DIR}/Resources/Python.app/Contents/MacOS/Python"
PYTHON_CONFIG="${PYTHON_FRAMEWORK_DIR}/lib/python3.7/config-3.7m-darwin/python-config.py"
INSTALL_LIB_DIR="${INSTALL_DIR}/usr/lib"
INSTALL_LIB_DIR="${INSTALL_DIR}/usr/lib"
INSTALL_PYTHON_DIR="${INSTALL_LIB_DIR}/python${PYTHON_VERSION}/site-packages"
INSTALL_GNURADIO_PYTHON_DIR="${INSTALL_DIR}/usr/share/gnuradio/python/site-packages"


export PYTHONPATH=${INSTALL_DIR}/usr/lib/python${PYTHON_VERSION}/site-packages
export SDLDIR=${INSTALL_DIR}/usr

function check_prerequisites() {
  
  XCODE_DEVELOPER_DIR_CMD="xcode-select -p"
  [[ "" = "$(${XCODE_DEVELOPER_DIR_CMD} 2>/dev/null)" ]] \
    && E "Xcode command-line developer tools are not installed. You can install them with 'xcode-select --install'"
  
  [[ -d ${XQUARTZ_APP_DIR} ]] \
    || E "XQuartz is not installed. Download it at http://www.xquartz.org/"

  [[ -d ${PYTHON_FRAMEWORK_DIR} ]] \
    || E "Python 3.7 is not installed. Download it here: https://www.python.org/downloads/"
}

function gen_version() {
  local dirty
  local last_tag
  local last_tag_commit
  local last_commit
  local short_last_commit
  local ver
  
  cd ${BUILD_DIR}

  last_commit="$(git rev-parse --verify HEAD)"    
  short_last_commit="$(git rev-parse --short HEAD)"
  last_tag="$(git describe --abbrev=0 --tags)"

  if git diff-index --quiet HEAD --; then
    dirty=""
  else
    dirty="-dirty"
  fi

  if [ "" = "${last_tag}" ]; then
    ver="${short_last_commit}"
  else
    last_tag_commit="$(git rev-list -n 1 ${last_tag})"
    if [ "${last_tag_commit}" = "${last_commit}" -a "" = "${dirty}" ]; then
      ver="${last_tag}"
    else
      ver="${short_last_commit}"
    fi
  fi

  ver+=${dirty}
  
  echo "${ver}"
}

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
  dyldlibpath_contains ${1} && return 0
  export DYLD_LIBRARY_PATH=${1}:${DYLD_LIBRARY_PATH}
}

function prefix_path_if_not_contained() {
  local x=${1}
  path_contains ${1} && return 0 
  export PATH=${1}:${PATH}
}

function handle_hash_mismatch() {
  local FILETYPE=$(file "${1}")

  # Remove the mismatching file, unless we're explicitly keeping it.
  [ ${KEEP_ON_MISMATCH} ] || rm -f "${1}"

  # For convenience, copy the hash line to the clipboard, if desired.
  [ ${COPY_HASH_ON_MISMATCH} ] && (echo "CKSUM=sha256:${3}" | pbcopy)

  # And error out.
  E "File '${1}' does not match '${2}'.\nActual sha256 is '${3}'.\nFile is of type '${FILETYPE}'." 
}


function verify_sha256() {
  #local FILENAME="${1}"
  #local CKSUM="${2}"
  local CKSUM="$(shasum -a 256 -- "${1}" | cut -d' ' -f1)"
  test "${CKSUM}" = "${2}" \
    && D "File '${1}' matches '${2}'" \
    || handle_hash_mismatch "${1}" "${2}" "${CKSUM}" "sha256"
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
  local MVFROM=${6}

  I "fetching ${P} from ${URL}"

  if [ "git" = "${URL:0:3}" -o "" != "${BRANCH}" ]; then
    D "downloading to ${TMP_DIR}/${T}"
    if [ ! -d ${TMP_DIR}/${T} ]; then
      git clone ${URL} ${TMP_DIR}/${T} \
        ||  ( rm -Rf ${TMP_DIR}/${T}; E "failed to clone from ${URL}" )
    fi
    cd ${TMP_DIR}/${T} \
      && git reset \
      && git checkout . \
      && git checkout master \
      && git fetch \
      && git pull \
      && git ls-files --others --exclude-standard | xargs rm -Rf \
      ||  ( rm -Rf ${TMP_DIR}/${T}; E "failed to pull from ${URL}" )
    if [ "" != "${BRANCH}" ]; then
      git branch -D local-${BRANCH} &> /dev/null || true
      git checkout -b local-${BRANCH} ${BRANCH} \
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
  local MVFROM="${4}"
  local NAME="${5}"

  if [ "" = "${T}" ]; then
    T=${P}
  fi

  if [ "" = "${NAME}" ]; then
    if [ "" = "${MVFROM}" ]; then
      NAME=${P} 
    else
      NAME=${MVFROM}
    fi
  fi

  D "Looking for an archive matching '${NAME}'"

  if [ "git" = "${URL:0:3}" -o "" != "${BRANCH}" ]; then
    I "git repository has been refreshed"
  else
    local opts=
    local cmd=
    local Z=

    if [ 1 -eq 0 ]; then
      echo 
    elif [ -e ${TMP_DIR}/${NAME}.zip ]; then
      Z=${NAME}.zip
      cmd=unzip
    elif [ -e ${TMP_DIR}/${NAME}.tar.gz ]; then
      Z=${NAME}.tar.gz
      cmd=tar
      opts=xpzf
    elif [ -e ${TMP_DIR}/${NAME}.tgz ]; then
      Z=${NAME}.tgz
      cmd=tar
      opts=xpzf
    elif [ -e ${TMP_DIR}/${NAME}.tar.bz2 ]; then
      Z=${NAME}.tar.bz2
      cmd=tar
      opts=xpjf
    elif [ -e ${TMP_DIR}/${NAME}.tbz2 ]; then
      Z=${NAME}.tbz2
      cmd=tar
      opts=xpjf
    elif [ -e ${TMP_DIR}/${NAME}.tar.xz ]; then
      Z=${NAME}.tar.xz
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

  if [ z"${MVFROM}" != z"" ]; then
    mv "${TMP_DIR}/${MVFROM}" "${TMP_DIR}/${T}"
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
  set -e

  local P=${1}
  local URL=${2}
  local CKSUM=${3}
  local T=${4}
  local BRANCH=${5}
  local MVFROM=${6}
  local NAME=${7}

  export -n SHELLOPTS

  if [ "" = "${T}" ]; then
    T=${P}
  fi

  if [ -f ${TMP_DIR}/.${P}.done ]; then
    I "already installed ${P}"    
  else 
    fetch "${P}" "${URL}" "${T}" "${BRANCH}" "${CKSUM}"
    unpack ${P} ${URL} "${T}" "${MVFROM}" "${NAME}"
  
    # Create our working directory, and build things there.
    (
      set -e

      rm -Rf ${TMP_DIR}/${T}-build
      mkdir ${TMP_DIR}/${T}-build
      cd ${TMP_DIR}/${T}-build

      # Configure and make.
      cmake ${EXTRA_OPTS}
      ${MAKE}
      ${MAKE} install
    ) || E "failed to build ${P}"
  
    I "finished building and installing ${P}"

    touch ${TMP_DIR}/.${P}.done
  fi
}


function build_and_install_meson() {
  set -e

  local P=${1}
  local URL=${2}
  local CKSUM=${3}
  local T=${4}
  local BRANCH=${5}
  local PATHNAME=${6}

  export -n SHELLOPTS
  export AR="/usr/bin/ar"

  if [ "" = "${T}" ]; then
    T=${P}
  fi

  if [ -f ${TMP_DIR}/.${P}.done ]; then
    I "already installed ${P}"    
  else 
    fetch "${P}" "${URL}" "${T}" "${BRANCH}" "${CKSUM}" "${PATHNAME}"
    unpack ${P} ${URL} ${T} ${BRANCH} "${PATHNAME}"

  
    rm -Rf ${TMP_DIR}/${T}-build
    mkdir ${TMP_DIR}/${T}-build
    cd ${TMP_DIR}/${T}

    meson --prefix="${INSTALL_DIR}/usr" --buildtype=plain ${TMP_DIR}/${T}-build ${EXTRA_OPTS} && \
	    ninja -v -C ${TMP_DIR}/${T}-build  && \
	    ninja -C ${TMP_DIR}/${T}-build install \
    || E "failed to build ${P}"
  
    I "finished building and installing ${P}"

    touch ${TMP_DIR}/.${P}.done
  
  fi
}


function build_and_install_waf() {
  set -e

  local P=${1}
  local URL=${2}
  local CKSUM=${3}
  local T=${4}
  local BRANCH=${5}

  export -n SHELLOPTS

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
    && cd ${TMP_DIR}/${T} \
    && ${PYTHON} ./waf configure --prefix="${INSTALL_DIR}" \
    && ${PYTHON} ./waf build \
    && ${PYTHON} ./waf install \
    || E "failed to build ${P}"
  
    I "finished building and installing ${P}"

    touch ${TMP_DIR}/.${P}.done
  
  fi
}


function build_and_install_setup_py() {
  set -e

  local P=${1}
  local URL=${2}
  local CKSUM=${3}
  local T=${4}
  local BRANCH=${5}

  export -n SHELLOPTS

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
  set -e

  local P=${1}
  local URL=${2}
  local CKSUM=${3}
  local T=${4}
  local BRANCH=${5}
  local CONFIGURE_CMD=${6}
  local MVFROM=${7}

  export -n SHELLOPTS
  
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
    unpack ${P} ${URL} ${T} ${MVFROM}
  
    if [[ ( "" = "${SKIP_AUTORECONF}" && "" != "$(which autoreconf)"  ) || ! -f ${TMP_DIR}/${T}/configure ]]; then
      I "Running autoreconf in ${T}"
      (
        cd ${TMP_DIR}/${T}
        autoreconf -if
      ) || E "autoreconf failed for ${P}"
    fi

    if [[ "" = "${SKIP_LIBTOOLIZE}" && "" != "$(which libtoolize)" ]]; then
      I "Running libtoolize in ${T}"
      (
        cd ${TMP_DIR}/${T}
        libtoolize -if 
      ) || E "libtoolize failed for ${P}"
    fi

    I "Configuring and building in ${T}"
    (
      cd ${TMP_DIR}/${T}
      I "${CONFIGURE_CMD} ${EXTRA_OPTS}"
      ${CONFIGURE_CMD} ${EXTRA_OPTS}
      ${MAKE} 
      ${MAKE} install
    ) || E "failed to configure, make, and install ${P}"
  
    I "finished building and installing ${P}"
    touch ${TMP_DIR}/.${P}.done
    
  fi
}


function build_and_install_qmake() {
  set -e

  local P=${1}
  local URL=${2}
  local CKSUM=${3}
  local T=${4}
  local BRANCH=${5}

  export -n SHELLOPTS
  
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
}

#
# Function that builds and installs a given SoapySDR plugin as needed.
#
function install_soapy_plugin_if_needed() {
  P=Soapy${1}
  COMMIT=${2}
  EXTRA_ARGS=${3}
  URL="git://github.com/pothosware/${P}.git"

  EXTRA_OPTS="\
    -DCMAKE_MACOSX_RPATH=OLD \
    -DCMAKE_INSTALL_NAME_DIR=${INSTALL_DIR}/usr/lib \
    -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/usr \
    -DPYTHON3_EXECUTABLE=$(which ${PYTHON}) \
    -DPYTHON3_CONFIG_EXECUTABLE=${PYTHON_CONFIG} \
    -DPYTHON_EXECUTABLE=$(which ${PYTHON}) \
    -DCMAKE_IGNORE_PATH=/usr/local/lib;/usr/local/include \
    ${EXTRA_ARGS} \
    ${TMP_DIR}/${P}" \
  build_and_install_cmake \
    ${P} \
    ${URL} \
    git:${COMMIT} \
    ${P} \
    ${COMMIT}
}

#
# Function that installs a bladeRF FPGA bitstream to the appropriate target location.
#
function install_bladerf_bitstream_if_needed() {
  P=bladeRF-bitstream-${1}
  T="hosted${1}-latest.rbf"
  URL="https://www.nuand.com/fpga/${T}"
  CKSUM="sha256:${2}"

  # Install to a location where libbladerf will look.
  INSTALL_TO="${INSTALL_DIR}/usr/share/Nuand/bladeRF"

  if [ -f ${TMP_DIR}/.${P}.done ]; then
    I already installed ${P}
  else
    I installing bladeRF bitstream ${P}

    # Fetch the bitstream, and install it.
    fetch "${P}" "${URL}" "${P}" "" "${CKSUM}"
    mkdir -p "${INSTALL_TO}"
    cp "${TMP_DIR}/${T}" "${INSTALL_TO}/hosted${1}.rbf"

    # Mark the package as installed.
    touch ${TMP_DIR}/.${P}.done
  fi
}


#
# Function that replaces malformed/bad dylib paths with fully-resolved one.
# Many of these tools require extensive patching to get @rpaths to be generated
# correctly on macOS. Instead of carrying around a huge patch weight, we'll taken
# on the Cursed (TM) solution of manually resolving the dylib paths ourselves.
#
function replace_bad_dylib_paths() {
(	
  set -e

  local new_working_directory=${1}


  # If we have a directory to apply to, CD to it first.
  if [ "" != "${new_working_directory}" ]; then
    cd ${new_working_directory}
  fi


  # Grab a set of files that could be our messed-up libraries.
  potential_files=$(find . -name '*.dylib' -o -name '*.so' -o \( -perm "+111" -type f \))

  # Iterate over our files... 
  for file in $potential_files; do

      # Grab the file's type...
      file_type=$(file ${file})

      # ... and skip the file if it's not a Mach-O library.
      if [[ ${file_type} != *"Mach-O 64-bit"* ]]; then
        continue
      fi

      # Grab a list of library paths that may have issues.
      # Note that this works even for files that aren't libraries; as they just report "not an object file".
      otool_paths=$(otool -L ${file} || true)

      # Check each of the paths for @rpath, and then replace it accordingly.
      IFS=$'\n'
      for path in $otool_paths; do
        name=$(basename ${path})

        # Grab the path section of the otool output.
        original_path=$(echo $path | cut -d ' ' -f 1 | tr -d '[:space:]:')

        # Replace the problematic section of any @rpath-containing lines with a correct prefix.
        if [[ $path == *"@rpath"* ]] || [[ $path == "@rpath"* ]]; then
          new_path=${original_path/@rpath/"${INSTALL_DIR}/usr/lib"}
          D Replacing @rpath references in "${name} (${original_path} -> ${new_path}"
          install_name_tool -change "${original_path}" "${new_path}" ${file}
        fi

        # If the path doesn't start with "/", it's relative. We'll assueme the relevant
        # library is in our standard library path, and add that as a prefix.
        if [[ ${original_path} != "/"* ]]; then
          new_path="${INSTALL_DIR}/usr/lib/${original_path}"
          
          # Remove a leading "./" in the relevant path, for cleanliness.
          new_path=$(echo ${new_path} | sed "s|\\./||")

          D Replacing relative references in "${name} (${original_path} -> ${new_path}"
          install_name_tool -change "${original_path}" "${new_path}" ${file}
        fi

      done
  done
)
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
# main
#

I "BUILD_DIR = '${BUILD_DIR}'"
I "INSTALL_DIR = '${INSTALL_DIR}'"
I "TMP_DIR = '${TMP_DIR}'"

check_prerequisites

#rm -Rf ${TMP_DIR}

mkdir -p ${BUILD_DIR} ${TMP_DIR} ${INSTALL_DIR}

cd ${TMP_DIR}

prefix_path_if_not_contained ${INSTALL_DIR}/usr/bin

# Update our general compiler flags to reference our local include paths.
export CFLAGS="-I${INSTALL_DIR}/usr/include -I/opt/X11/include"
export CPPFLAGS=${CFLAGS}
export CXXFLAGS=${CFLAGS}

export CC="clang -mmacosx-version-min=10.7"
export CXX="clang++ -mmacosx-version-min=10.7 -stdlib=libc++"
export LDFLAGS="-Wl,-undefined,error -L${INSTALL_DIR}/usr/lib -L/opt/X11/lib -Wl,-rpath,${INSTALL_DIR}/usr/lib -Wl,-rpath,/opt/X11/lib"
export PKG_CONFIG_PATH="${INSTALL_DIR}/usr/lib/pkgconfig:/opt/X11/lib/pkgconfig"

unset DYLD_LIBRARY_PATH

#
# Provide several optional tools for debugging.
# build.sh can be invoked with these to help debug our output.
#

if [ "${1}" == "setup-environment" ]; then
  I "Environment set up; aborting now."
  return
fi

if [ "${1}" == "shell" ]; then
  I "Running an in-envrionment shell."

  # Set up our environment, a little.
  export PYTHONPATH="${PYTHONPATH}:${INSTALL_DIR}/usr/share/gnuradio/python/site-packages/"
  export XDG_DATA_DIRS="${INSTALL_DIR}/usr/share"

  export -n SHELLOPTS

  cd ${TMP_DIR}
  bash
  exit 0
fi

if [ "${1}" == "python" ]; then
  I "Running an in-environment python shell."
  shift
  ${PYTHON} "$@"
  exit 0
fi


if [ "${1}" == "grc" ]; then
  I "Attempting to start gnuradio-companion from the build tree."

  # Set up our environment, a little.
  export PYTHONPATH="${PYTHONPATH}:${INSTALL_DIR}/usr/share/gnuradio/python/site-packages/"
  export XDG_DATA_DIRS="${INSTALL_DIR}/usr/share"
  gnuradio-companion
  exit 0
fi


if [ "${1}" == "post-build" ]; then
  I "Clearing the completion status of our post-build tasks."
  rm -f ${TMP_DIR}/.post-build-fixes.done
fi


if [ "${1}" == "rebuild" ]; then
  I "Rebuilding any packages called ${2}."
  rm -f ${TMP_DIR}/.${2}.done
fi


if [ "${1}" == "hard-rebuild" ]; then
  I "Clean rebuilding any packages called ${2}."
  rm -f  ${TMP_DIR}/.${2}.done
  rm -rf ${TMP_DIR}/${2}
  rm -rf ${TMP_DIR}/${2}-build
fi

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


# Create symlinks that ensure we only ever build with the user-installed python3;
# and put python3 where things expect it to be.
ln -sf ${PYTHON} ${INSTALL_DIR}/usr/bin/python
ln -sf ${PYTHON} ${INSTALL_DIR}/usr/bin/python3
ln -sf ${PYTHON_CONFIG} ${INSTALL_DIR}/usr/bin/python-config

#
# Install autoconf
# 
(
  P=autoconf-2.69
  URL=http://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.gz
  CKSUM=sha256:954bd69b391edc12d6a4a51a2dd1476543da5c6bbf05a95b59dc0dd6fd4c2969

  SKIP_AUTORECONF=yes \
  SKIP_LIBTOOLIZE=yes \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)

#
# Install automake
# 
(
  P=automake-1.16
  URL=http://ftp.gnu.org/gnu/automake/${P}.tar.gz
  CKSUM=sha256:80da43bb5665596ee389e6d8b64b4f122ea4b92a685b1dbd813cd1f0e0c2d83f

  SKIP_AUTORECONF=yes
  SKIP_LIBTOOLIZE=yes

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)

#
# Install libtool
# 

(
  P=libtool-2.4.6
  URL="http://gnu.spinellicreations.com/libtool/${P}.tar.xz"
  CKSUM=sha256:7c87a8c2c8c0fc9cd5019e402bed4292462d00a718a7cd5f11218153bf28b26f

  SKIP_AUTORECONF=yes
  SKIP_LIBTOOLIZE=yes

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM} \
    "" \
    "" \
    "./configure --prefix=${INSTALL_DIR}/usr"
)


#
# Install sed
# 
(
  P=sed-4.7
  URL=http://ftp.gnu.org/pub/gnu/sed/${P}.tar.xz
  CKSUM=sha256:2885768cd0a29ff8d58a6280a270ff161f6a3deb5690b2be6c49f46d4c67bd6a

  SKIP_AUTORECONF=true
  SKIP_LIBTOOLIZE=true

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)

#
# Install libunistring
#
(
  V=0.9.10
  P=libunistring-${V}
  URL=http://ftp.gnu.org/pub/gnu/libunistring/${P}.tar.xz
  CKSUM=sha256:eb8fb2c3e4b6e2d336608377050892b54c3c983b646c561836550863003c05d7

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)



#
# Install gettext
# 
(
  P=gettext-0.20.1
  URL=http://ftp.gnu.org/pub/gnu/gettext/${P}.tar.xz
  CKSUM=sha256:53f02fbbec9e798b0faaf7c73272f83608e835c6288dd58be6c9bb54624a3800

  SKIP_AUTORECONF=true
  SKIP_LIBTOOLIZE=true

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install xz-utils
# 
(
  P=xz-5.2.4
  URL=https://tukaani.org/xz/${P}.tar.bz2
  CKSUM=sha256:3313fd2a95f43d88e44264e6b015e7d03053e681860b0d5d3f9baca79c57b7bf

  SKIP_AUTORECONF=true
  SKIP_LIBTOOLIZE=true

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install GNU tar
# 
(
  P=tar-1.29
  URL=http://ftp.gnu.org/gnu/tar/tar-1.29.tar.bz2
  CKSUM=sha256:236b11190c0a3a6885bdb8d61424f2b36a5872869aa3f7f695dea4b4843ae2f2

  SKIP_AUTORECONF=true
  SKIP_LIBTOOLIZE=true

  EXTRA_OPTS="--with-lzma=`which xz`"
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)

#
# Install pkg-config
# 

(
  P=pkg-config-0.29.2
  URL=https://pkg-config.freedesktop.org/releases/${P}.tar.gz
  CKSUM=sha256:6fc69c01688c9458a57eb9a1664c9aba372ccda420a02bf4429fe610e7e7d591

  SKIP_LIBTOOLIZE=true

  EXTRA_OPTS="--with-internal-glib" \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install CMake
#
(
  V=3.15
  VV=${V}.3
  P=cmake-${VV}
  URL="https://github.com/Kitware/CMake/releases/download/v${VV}/${P}.tar.gz"
  CKSUM=sha256:13958243a01365b05652fa01b21d40fa834f70a9e30efa69c02604e64f58b8f5
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
)

#
# Install Boost
# 
(
  P=boost_1_71_0
  URL="$GENTOO_MIRROR/${P}.tar.bz2"
  CKSUM=sha256:d73a8da01e8bf8c7eda40b4c84915071a8c8a0df4a6734537ddde4a8580524ee
  T=${P}

  if [ ! -f ${TMP_DIR}/.${P}.done ]; then

    export -n SHELLOPTS

    fetch "${P}" "${URL}" "" "" "${CKSUM}"
    unpack ${P} ${URL}

    export CFLAGS="${CFLAGS} $(${PYTHON_CONFIG} --includes)"
    export LDFLAGS="${LDFLAGS} $(${PYTHON_CONFIG} --ldflags)"

    cd ${TMP_DIR}/${T} \
      && sh bootstrap.sh --with-python-version=${PYTHON_VERSION} \
      && ./b2 \
        -j $(ncpus)                                  \
        -sLZMA_LIBRARY_PATH="${INSTALL_DIR}/usr/lib" \
        -sLZMA_INCLUDE="${INSTALL_DIR}/usr/include"  \
	cflags='${CFLAGS}' \
	cxxflags='${CFLAGS}' \
        stage \
      && rsync -avr stage/lib/ ${INSTALL_DIR}/usr/lib/ \
      && rsync -avr boost ${INSTALL_DIR}/usr/include \
      || E "building boost failed"
    
    touch ${TMP_DIR}/.${P}.done

  fi
)


#
# Install PCRE
# 
(
  P=pcre-8.40
  URL=http://pilotfiber.dl.sourceforge.net/project/pcre/pcre/8.40/pcre-8.40.tar.gz
  CKSUM=sha256:1d75ce90ea3f81ee080cdc04e68c9c25a9fb984861a0618be7bbf676b18eda3e

  SKIP_AUTORECONF=true
  SKIP_LIBTOOLIZE=true

  EXTRA_OPTS="--enable-utf" \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install Swig
# 
(
  P=swig-4.0.1
  URL="https://downloads.sourceforge.net/project/swig/swig/${P}/${P}.tar.gz"
  CKSUM=sha256:7a00b4d0d53ad97a14316135e2d702091cd5f193bb58bcfcd8bc59d41e7887a9

  SKIP_AUTORECONF=yes
  SKIP_LIBTOOLIZE=yes

  build_and_install_autotools \
      ${P} \
      ${URL} \
      ${CKSUM}
)


#
# Install ffi
# 
(
  P=libffi-3.2.1
  URL=ftp://sourceware.org/pub/libffi/libffi-3.2.1.tar.gz
  CKSUM=sha256:d06ebb8e1d9a22d19e38d63fdb83954253f39bedc5d46232a05645685722ca37

  SKIP_AUTORECONF=true
  SKIP_LIBTOOLIZE=true

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)



#
# Install ninja
#
(
  V=1.9.0
  P=ninja-${V}
  URL="https://github.com/ninja-build/ninja/archive/v${V}/${P}.tar.gz"
  CKSUM=sha256:5d7ec75828f8d3fd1a0c2f31b5b0cea780cdfe1031359228c428c1a48bfcd5b9

  export -n SHELLOPTS

  if [ -f ${TMP_DIR}/.${P}.done ]; then
    I "already installed ${P}"
  else

    fetch "${P}" "${URL}" "" "" "${CKSUM}"
    unpack ${P} ${URL}
  
    # Ninja only produces a single binary; and doesn't really support "installing".
    # We'll just copy it to /usr/bin.
    cd ${TMP_DIR}/${P} \
      && ./configure.py --bootstrap \
      && cp ninja ${INSTALL_DIR}/usr/bin/ \
      || E "failed to build ${P}"
  
    touch ${TMP_DIR}/.${P}.done
    I "built and installed ${P}"

  fi
)


#
# Install meson
# 
(
  V=0.51.2
  P=meson-${V}
  URL="https://github.com/mesonbuild/meson/releases/download/${V}/${P}.tar.gz"
  CKSUM=sha256:23688f0fc90be623d98e80e1defeea92bbb7103bf9336a5f5b9865d36e892d76

  build_and_install_setup_py \
    ${P} \
    ${URL} \
    ${CKSUM}
)



#
# Install glib
# 
(
  V=2.62
  VV=${V}.0
  P=glib-2.62.0
  URL="http://gensho.acc.umu.se/pub/gnome/sources/glib/${V}/${P}.tar.xz"
  CKSUM=sha256:6c257205a0a343b662c9961a58bb4ba1f1e31c82f5c6b909ec741194abc3da10
      
  # Build a dynamic version..
  build_and_install_meson \
    ${P} \
    ${URL} \
    ${CKSUM}
)


# ... and a static one?
#P=glib-static-${VV}
#EXTRA_OPTS="--default-library static"
#build_and_install_meson \
#  ${P} \
#  ${URL} \
#  ${CKSUM} \
#  "" \
#  "" \
#  "glib-${VV}"


#
# Install cppunit
# 
(
  P=cppunit-1.12.1
  URL='http://iweb.dl.sourceforge.net/project/cppunit/cppunit/1.12.1/cppunit-1.12.1.tar.gz'
  CKSUM=sha256:ac28a04c8e6c9217d910b0ae7122832d28d9917fa668bcc9e0b8b09acb4ea44a

  SKIP_AUTORECONF=true
  SKIP_LIBTOOLIZE=true

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install mako
#
(
  P=Mako-1.0.3
  URL="${GENTOO_MIRROR}/${P}.tar.gz"
  CKSUM=sha256:7644bc0ee35965d2e146dde31827b8982ed70a58281085fac42869a09764d38c

  LDFLAGS="${LDFLAGS} $(${PYTHON_CONFIG} --ldflags)"
  build_and_install_setup_py \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install bison
# 
(
  P=bison-3.4.2
  URL="http://ftp.gnu.org/gnu/bison/${P}.tar.xz"
  CKSUM=sha256:27d05534699735dc69e86add5b808d6cb35900ad3fd63fa82e3eb644336abfa0

  SKIP_AUTORECONF=yes \
  SKIP_LIBTOOLIZE=true \
  build_and_install_autotools \
   ${P} \
   ${URL} \
   ${CKSUM}
)


#
# Install OpenSSL
#
(
  P=openssl-1.1.1f
  URL="https://www.openssl.org/source/${P}.tar.gz"
  CKSUM=sha256:186c6bfe6ecfba7a5b48c47f8a1673d0f3b0e5ba2e25602dd23b629975da3f35

  SKIP_AUTORECONF=yes \
  SKIP_LIBTOOLIZE=yes \
  EXTRA_OPTS="darwin64-x86_64-cc" \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install thrift
#
(
  V=0.12.0
  P=thrift-${V}
  URL="http://apache.mirror.gtcomm.net/thrift/${V}/${P}.tar.gz"
  CKSUM=sha256:c336099532b765a6815173f62df0ed897528a9d551837d627c1f87fadad90428

  if [ -f ${TMP_DIR}/.${P}.done ]; then
    I "already installed ${P}"
  else

    export PY_PREFIX="${INSTALL_DIR}/usr"
    export LDFLAGS="${LDFLAGS} $(${PYTHON_CONFIG} --ldflags)"
    export CFLAGS="${CFLAGS}"
    export CXXFLAGS="${CPPFLAGS}"

    EXTRA_OPTS="--with-c_glib --without-cpp --with-libevent --with-python --without-csharp --without-d --without-erlang"
    EXTRA_OPTS="${EXTRA_OPTS} --without-go --without-haskell --without-java --without-lua --without-nodejs --without-perl"
    EXTRA_OPTS="${EXTRA_OPTS} --without-php --without-ruby --without-zlib --without-qt4 --without-qt5"
    EXTRA_OPTS="${EXTRA_OPTS} --prefix=${INSTALL_DIR}/usr --includedir=${INSTALL_DIR}/usr/include"
    #EXTRA_OPTS="${EXTRA_OPTS} --enable-boostthreads --with-openssl=${INSTALL_DIR}/usr/ssl"

    SKIP_AUTORECONF=true
    SKIP_LIBTOOLIZE=true


    build_and_install_autotools \
      ${P} \
      ${URL} \
      ${CKSUM}

    # Copy the relevant c++ compatiblity header from the build directory to our include path.
    mkdir -p ${INSTALL_DIR}/usr/include/thrift
    cp ${TMP_DIR}/${P}/lib/cpp/src/thrift/stdcxx.h ${INSTALL_DIR}/usr/include/thrift/stdcxx.h

  fi

)



#
# Install orc
# 
(
  P=orc-0.4.30
  URL="https://gstreamer.freedesktop.org/src/orc/${P}.tar.xz"
  CKSUM=sha256:ba41b92146a5691cd102eb79c026757d39e9d3b81a65810d2946a1786a1c4972

  build_and_install_meson \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install Cheetah
# 
(
  V=3.2.4
  P=cheetah3-${V}
  URL="https://github.com/CheetahTemplate3/cheetah3/archive/${V}/${P}.tar.gz"
  CKSUM=sha256:32780a2729b7acf1ab4df9b9325b33e4a1aaf7dcae8c2c66e6e83c70499db863

  LDFLAGS="${LDFLAGS} $(${PYTHON_CONFIG} --ldflags)"

  build_and_install_setup_py \
    ${P} \
    ${URL} \
    ${CKSUM} \
  && ln -sf ${PYTHONPATH}/${P}-py3.7.egg ${PYTHONPATH}/Cheetah.egg
)


#
# Install Cython
# 

(
  V=0.29.13
  P=cython-${V}
  URL="https://github.com/cython/cython/archive/${V}/${P}.tar.gz"
  CKSUM=sha256:af71d040fa9fa1af0ea2b7a481193776989ae93ae828eb018416cac771aef07f

  LDFLAGS="${LDFLAGS} $(${PYTHON_CONFIG} --ldflags)"
  build_and_install_setup_py \
    ${P} \
    ${URL} \
    ${CKSUM} \
)


#
# Install lxml
# 

(
  P=lxml-4.4.1
  T="${P}"
  URL="https://github.com/lxml/lxml/archive/${P}.tar.gz"
  CKSUM=sha256:a735879b25331bb0c8c115e8aff6250469241fbce98bba192142cd767ff23408

  SKIP_AUTORECONF=true
  SKIP_LIBTOOLIZE=true

  LDFLAGS="${LDFLAGS} $(${PYTHON_CONFIG} --ldflags)" \
  build_and_install_setup_py \
    ${P} \
    ${URL} \
    ${CKSUM} \
    "lxml-${P}"
)



#
# Install libtiff
#
(
  P=tiff-4.0.10
  URL="https://download.osgeo.org/libtiff/${P}.tar.gz"
  CKSUM=sha256:2c52d11ccaf767457db0c46795d9c7d1a8d8f76f68b0b800a3dfe45786b996e4

  SKIP_AUTORECONF=true
  SKIP_LIBTOOLIZE=true

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install png
# 
(
  P=libpng-1.6.37
  URL="${GENTOO_MIRROR}/${P}.tar.xz"
  CKSUM=sha256:505e70834d35383537b6491e7ae8641f1a4bed1876dbfe361201fc80868d88ca

  SKIP_AUTORECONF=true \
  SKIP_LIBTOOLIZE=true \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install jpeg
#
(
  V=9c
  P=jpegsrc.v${V}
  URL=http://ijg.org/files/jpegsrc.v${V}.tar.gz
  CKSUM=sha256:650250979303a649e21f87b5ccd02672af1ea6954b911342ea491f351ceb7122
  T=jpeg-${V}

  SKIP_AUTORECONF=yes \
  SKIP_LIBTOOLIZE=yes \

  EXTRA_OPTS="--mandir=${INSTALL_DIR}/usr/share/man" \

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM} \
    ${T}
)


#
# Install pixman
# 
(
  P='pixman-0.38.4'
  URL="https://www.cairographics.org/releases/${P}.tar.gz"
  CKSUM=sha256:da66d6fd6e40aee70f7bd02e4f8f76fc3f006ec879d346bae6a723025cfbdde7

  SKIP_AUTORECONF=true
  SKIP_LIBTOOLIZE=true

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install freetype
# 
(
  P=freetype-2.10.1
  URL="${GENTOO_MIRROR}/${P}.tar.xz"
  CKSUM=sha256:16dbfa488a21fe827dc27eaf708f42f7aa3bb997d745d31a19781628c36ba26f

  SKIP_AUTORECONF=yes
  SKIP_LIBTOOLIZE=yes

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install harfbuzz
# 
(
  P=harfbuzz-2.6.1
  URL="https://www.freedesktop.org/software/harfbuzz/release/${P}.tar.xz"
  CKSUM=sha256:c651fb3faaa338aeb280726837c2384064cdc17ef40539228d88a1260960844f

  SKIP_AUTORECONF=true
  SKIP_LIBTOOLIZE=true

  EXTRA_OPTS="--with-coretext=yes "

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install fontconfig
# 
(
  P=fontconfig-2.13.1
  URL="https://www.freedesktop.org/software/fontconfig/release/${P}.tar.gz"
  CKSUM=sha256:9f0d852b39d75fc655f9f53850eb32555394f36104a044bb2b2fc9e66dbbfa7f

  SKIP_AUTORECONF=true
  SKIP_LIBTOOLIZE=true

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install cairo
# 
(
  P=zlib-1.2.11
  URL="https://www.zlib.net/${P}.tar.xz"
  CKSUM=sha256:4ff941449631ace0d4d203e3483be9dbc9da454084111f97ea0a2114e19bf066

  EXTRA_OPTS="" \
  SKIP_AUTORECONF=true \
  SKIP_LIBTOOLIZE=true \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install cairo
# 
(
  P=cairo-1.16.0
  URL="https://www.cairographics.org/releases/${P}.tar.xz"
  CKSUM=sha256:5e7b29b3f113ef870d1e3ecf8adf21f923396401604bda16d44be45e66052331

  SKIP_AUTORECONF=true \
  SKIP_LIBTOOLIZE=true \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install pycairo
# 
(
  V=1.18.1
  P=pycairo-${V}
  URL="https://github.com/pygobject/pycairo/releases/download/v${V}/${P}.tar.gz"
  CKSUM=sha256:70172e58b6bad7572a3518c26729b074acdde15e6fee6cbab6d3528ad552b786

  export CFLAGS="${CFLAGS} $(${PYTHON_CONFIG} --includes)"
  export LDFLAGS="${LDFLAGS} $(${PYTHON_CONFIG} --ldflags)"

  build_and_install_meson \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install pygobject-introspection
# 
(
  V=1.62
  VV=1.62.0
  P=gobject-introspection-${VV}
  URL="http://ftp.gnome.org/pub/gnome/sources/gobject-introspection/${V}/gobject-introspection-${VV}.tar.xz"
  CKSUM=sha256:b1ee7ed257fdbc008702bdff0ff3e78a660e7e602efa8f211dc89b9d1e7d90a2

  export CFLAGS="${CFLAGS} $(${PYTHON_CONFIG} --includes)"
  export LDFLAGS="${LDFLAGS} $(${PYTHON_CONFIG} --ldflags)"

  build_and_install_meson \
    ${P} \
    ${URL} \
    ${CKSUM}
)

#
# Install pygobject
# 
(
  V=3.34.0
  P=pygobject-${V}
  URL="https://github.com/GNOME/pygobject/archive/${V}/pygobject-${V}.tar.gz"
  CKSUM=sha256:fe05538639311fe3105d6afb0d7dfa6dbd273338e5dea61354c190604b85cbca

  export CFLAGS="${CFLAGS} $(${PYTHON_CONFIG} --includes)"
  export LDFLAGS="${LDFLAGS} $(${PYTHON_CONFIG} --ldflags)"

  if [ -f ${TMP_DIR}/.${P}.done ]; then
    I "already installed ${P}"
  else 

    build_and_install_meson \
      ${P} \
      ${URL} \
      ${CKSUM}
    rm ${TMP_DIR}/.${P}.done
    build_and_install_setup_py \
      ${P} \
      ${URL} \
      ${CKSUM}
  fi
)


#
# Install gdk-pixbuf
# 
(
  V=2.36
  VV=${V}.6
  P=gdk-pixbuf-${VV}
  URL="http://muug.ca/mirror/gnome/sources/gdk-pixbuf/${V}/${P}.tar.xz"
  CKSUM=sha256:455eb90c09ed1b71f95f3ebfe1c904c206727e0eeb34fc94e5aaf944663a820c

  SKIP_AUTORECONF=true \
  SKIP_LIBTOOLIZE=true \
  EXTRA_OPTS="--without-libtiff --without-libjpeg" \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install libatk
# 
(
  V=2.34
  VV=${V}.1
  P=atk-${VV}
  URL="http://ftp.gnome.org/pub/gnome/sources/atk/${V}/${P}.tar.xz"
  CKSUM=sha256:d4f0e3b3d21265fcf2bc371e117da51c42ede1a71f6db1c834e6976bb20997cb

  build_and_install_meson \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install pango
# 
(
  V=1.44
  VV=${V}.6
  P=pango-${VV}
  URL="http://ftp.gnome.org/pub/GNOME/sources/pango/${V}/${P}.tar.xz"
  CKSUM=sha256:3e1e41ba838737e200611ff001e3b304c2ca4cdbba63d200a20db0b0ddc0f86c

  build_and_install_meson \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install libepoxy
# 

(
  V=1.5.3
  P=libepoxy-${V}
  URL="https://github.com/anholt/libepoxy/releases/download/${V}/${P}.tar.xz"
  CKSUM=sha256:002958c5528321edd53440235d3c44e71b5b1e09b9177e8daf677450b6c4433d

  EXTRA_OPTS="-Dglx=yes"
  build_and_install_meson \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install libxkbcommon
# 
(
  P=libxkbcommon-0.8.4
  URL="https://xkbcommon.org/download/${P}.tar.xz"
  CKSUM=sha256:60ddcff932b7fd352752d51a5c4f04f3d0403230a584df9a2e0d5ed87c486c8b

  EXTRA_OPTS="-Denable-wayland=false -Denable-docs=false"
  build_and_install_meson \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install iso-codes
# 
(
  P=iso-codes-4.1
  URL="https://salsa.debian.org/iso-codes-team/iso-codes/uploads/049ce6aac94d842be809f4063950646c/${P}.tar.xz"
  CKSUM=sha256:67117fb76f32c8fb5e37d2d60bce238f1f8e865cc7b569a57cbc3017ca15488a

  SKIP_AUTORECONF=true
  SKIP_LIBTOOLIZE=true

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install gtk+
# 
(
  V=3.24
  VV=${V}.11
  P=gtk+-${VV}
  URL="http://gemmei.acc.umu.se/pub/gnome/sources/gtk+/${V}/${P}.tar.xz"
  CKSUM=sha256:dba7658d0a2e1bfad8260f5210ca02988f233d1d86edacb95eceed7eca982895

  build_and_install_meson \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install intltool, which is necessary to install GTK3 themes.
# 
(
  V=0.40
  VV=${V}.0
  P=intltool-${VV}
  URL="http://ftp.gnome.org/pub/gnome/sources/intltool/${V}/${P}.tar.gz"
  CKSUM=sha256:386cc0c23ef629c7c0679f6ddc6f0f4df9baa6c4fdf1ca75b2c12ea233e6f152

  SKIP_AUTORECONF=true \
  SKIP_LIBTOOLIZE=true \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install icon-naming-utils, which is necessary to install GTK3 themes.
# 
(
  V=0.8.90
  P=icon-naming-utils-${V}
  URL="http://tango.freedesktop.org/releases/${P}.tar.bz2"
  CKSUM=sha256:b1378679df4485b4459f609a3304238b3e92d91e43744c47b70abbe690d883d5

  SKIP_AUTORECONF=true \
  SKIP_LIBTOOLIZE=true \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install the hicolor GTK icon theme.
# 
(
  V=0.17
  P=hicolor-icon-theme-${V}
  URL="https://icon-theme.freedesktop.org/releases/hicolor-icon-theme-${V}.tar.xz"
  CKSUM=sha256:317484352271d18cbbcfac3868eab798d67fff1b8402e740baa6ff41d588a9d8

  SKIP_AUTORECONF=true \
  SKIP_LIBTOOLIZE=true \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)



#
# Install the Adwaita GTK icon theme.
#
(
  set -e

  # Note: building the Adwaita theme currently requires SVG rendering capabilities,
  # and we don't want to carry around some of the tools it prefers to use (e.g. Inkscape).
  # Instead, we'll grab pre-rendered images from the Arch package.

  V=3.34.0-1
  P=adwaita-icon-theme-${V}
  FILENAME=${P}-any.pkg.tar.xz
  URL="http://archive.virtapi.org/packages/a/adwaita-icon-theme/${FILENAME}"
  CKSUM=sha256:0fc25d5b4c345ac2ccc90dbbcd17bcabe4344f35f10d2eac372d7fa86b067749

  if [ ! -f ${TMP_DIR}/.${P}.done ]; then
    I "Installing the Adwaita icon theme."

    # Grab the archive, and extract it directly into our sysroot.
    fetch "${P}" "${URL}" "${T}" "${BRANCH}" "${CKSUM}"
    tar -xvf ${TMP_DIR}/${FILENAME} -C ${INSTALL_DIR}

    # Remove the Arch metadata files.
    for i in .PKGINFO .BUILDINFO .MTREE; do
      rm -f ${INSTALL_DIR}/${i}
    done

    # And mark our install as complete.
    touch ${TMP_DIR}/.${P}.done
  fi

)


#
# Install the primary gnome GTK icon theme.
# 
(
  V=3.12
  VV=${V}.0
  P=gnome-icon-theme-${VV}
  URL="https://ftp.gnome.org/pub/GNOME/sources/gnome-icon-theme/${V}/${P}.tar.xz"
  CKSUM=sha256:359e720b9202d3aba8d477752c4cd11eced368182281d51ffd64c8572b4e503a

  SKIP_AUTORECONF=true \
  SKIP_LIBTOOLIZE=true \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install numpy
# 
(
  V=1.17.2
  P=numpy-${V}
  URL="https://github.com/numpy/numpy/releases/download/v${V}/${P}.tar.gz"
  CKSUM=sha256:81a4f748dcfa80a7071ad8f3d9f8edb9f8bc1f0a9bdd19bfd44fd42c02bd286c

  export CFLAGS="${CFLAGS} $(${PYTHON_CONFIG} --includes)"
  export LDFLAGS="${LDFLAGS} $(${PYTHON_CONFIG} --ldflags)"

  build_and_install_setup_py \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install fftw
# 
(
  P=fftw-3.3.8
  URL="http://www.fftw.org/${P}.tar.gz"
  CKSUM=sha256:6113262f6e92c5bd474f2875fa1b01054c4ad5040f6b0da7c03c98821d9ae303

  SKIP_AUTORECONF=true \
  SKIP_LIBTOOLIZE=true \
  EXTRA_OPTS="--enable-single --enable-sse --enable-sse2 --enable-avx --enable-avx2 --enable-avx-128-fma --enable-generic-simd128 --enable-generic-simd256 --enable-threads" \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install f2c
#
(
  P=f2c
  URL=http://github.com/barak/f2c.git
  CKSUM=git:fa8ccce5c4ab11d08b875379c5f0629098261f32
  T=${P}
  BRANCH=master

  if [ ! -f ${TMP_DIR}/.${P}.done ]; then

    fetch "${P}" "${URL}" "${T}" "${BRANCH}" "${CKSUM}"
    unpack ${P} ${URL} ${T}
    
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
)


#
# Install libf2c
#
(
  P=libf2c-20130927
  URL="${GENTOO_MIRROR}/${P}.zip"
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
)

#
# Install blas
#
(
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
    && /usr/bin/libtool -static -o libblas.a *.o \
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
)


#
# Install cblas
# 
# XXX: @CF: requires either f2c or gfortran, both of which I don't care for right now
(
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
    && /usr/bin/libtool -static -o ../libcblas.a *.o \
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
)


#
# Install gnu scientific library
# 
# XXX: @CF: required by gr-wavelet, depends on cblas
(
  P=gsl-2.6
  URL="http://ftp.wayne.edu/gnu/gsl/${P}.tar.gz"
  CKSUM=sha256:b782339fc7a38fe17689cb39966c4d821236c28018b6593ddb6fd59ee40786a8

  SKIP_AUTORECONF=true \
  SKIP_LIBTOOLIZE=true \
  LDFLAGS="${LDFLAGS} -lcblas -lblas -lf2c" \
  EXTRA_OPTS="" \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install libusb
# 
(
  V=1.0.23
  P=libusb-${V}
  URL="https://github.com/libusb/libusb/releases/download/v${V}/${P}.tar.bz2"
  CKSUM=sha256:db11c06e958a82dac52cf3c65cb4dd2c3f339c8a988665110e0d24d19312ad8d

  SKIP_AUTORECONF=true \
  SKIP_LIBTOOLIZE=true \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install gmp
# 
(
  V=6.1.2
  P=gmp-${V}
  URL="https://gmplib.org/download/gmp/${P}.tar.xz"
  CKSUM=sha256:87b565e89a9a684fe4ebeeddb8399dce2599f9c9049854ca8c0dfbdea0e21912

  EXTRA_OPTS=" --enable-cxx" \
  SKIP_AUTORECONF=true \
  SKIP_LIBTOOLIZE=true \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install python requests
#
(
  V=2.22.0
  P=requests-${V}
  URL="https://github.com/psf/requests/archive/v${V}/${P}.tar.gz"
  CKSUM=sha256:dcacea1b6a7bfd2cbb6c6a05743606b428f2739f37825e41fbf79af3cc2fd240

  build_and_install_setup_py \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install uhd (the USRP driver).
# Note that we need to build from git, as the latest release doesn't have python3 support.
#
(
  P=uhd
  URL=git://github.com/EttusResearch/uhd.git
  CKSUM=git:aea0e2de34803d5ea8f25d7cf2fb08f4ab9d43f0
  BRANCH=aea0e2de34803d5ea8f25d7cf2fb08f4ab9d43f0  # 3.15.0

  EXTRA_OPTS="\
    -DENABLE_E300=ON \
    -DENABLE_X300=OFF \
    -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/usr \
    -DPYTHON_EXECUTABLE=${PYTHON} \
    '-DCMAKE_C_FLAGS=-framework Python' \
    '-DCMAKE_CXX_FLAGS=-framework Python' \
    -DCMAKE_IGNORE_PATH=/usr/local/lib;/usr/local/include \
    -DUHD_SYS_CONF_FILE=${INSTALL_DIR}/etc/uhd/uhd.conf
    -DBoost_NO_BOOST_CMAKE=ON \
    ${TMP_DIR}/${P}/host" \
  build_and_install_cmake \
    ${P} \
    ${URL} \
    ${CKSUM} \
    ${P} \
    ${BRANCH}
)


#
# install SDL
#
(
  P=SDL-1.2.15
  URL=https://www.libsdl.org/release/SDL-1.2.15.tar.gz
  CKSUM=sha256:d6d316a793e5e348155f0dd93b979798933fb98aa1edebcc108829d6474aad00
  T=${P}

  LDFLAGS="${LDFLAGS} -framework CoreFoundation -framework CoreAudio -framework CoreServices -L/usr/X11R6/lib -lX11" \
  SKIP_AUTORECONF="yes" \
  SKIP_LIBTOOLIZE="yes" \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM} \
    ${T}
)


#
# Install libzmq
#
(
  P=libzmq
  URL=git://github.com/zeromq/libzmq.git
  CKSUM=git:d17581929cceceda02b4eb8abb054f996865c7a6
  T=${P}

  EXTRA_OPTS="-DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/usr ${TMP_DIR}/${T}" \
  build_and_install_cmake \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install cppzmq
#
(
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
)


#
# Install rtl-sdr
#
(
  V=0.6.0
  P=rtl-sdr-"${V}"
  URL="https://github.com/osmocom/rtl-sdr/archive/${V}/${P}.tar.gz"
  CKSUM=sha256:ee10a76fe0c6601102367d4cdf5c26271e9442d0491aa8df27e5a9bf639cff7c

  EXTRA_OPTS="" \
  LDFLAGS="${LDFLAGS} $(${PYTHON_CONFIG} --ldflags)" \
  SKIP_AUTORECONF=true \
  SKIP_LIBTOOLIZE=true \
  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install QT
#
(
  V=5.13
  VV=${V}.1
  P=qt-everywhere-src-${VV}
  URL="https://download.qt.io/official_releases/qt/${V}/${VV}/single/${P}.tar.xz"
  CKSUM=sha256:adf00266dc38352a166a9739f1a24a1e36f1be9c04bf72e16e142a256436974e
  T=${P}
  BRANCH=""

  export -n SHELLOPTS

  if [ -f ${TMP_DIR}/.${P}.done ]; then
      I "already installed ${P}"
  else
    #INSTALL_QGL="yes"
    rm -Rf ${INSTALL_DIR}/usr/lib/libQt*
    rm -Rf ${INSTALL_DIR}/usr/include/Qt*

    fetch "${P}" "${URL}" "${T}" "${BRANCH}" "${CKSUM}"
    unpack ${P} ${URL} ${T} ${BRANCH}

    I configuring ${P} \
    && cd ${TMP_DIR}/${T} \
    && export OPENSOURCE_CXXFLAGS=" -D__USE_WS_X11__ " \
    && sh configure                                              \
      -v                                                         \
      -opensource                                                \
      -confirm-license                                           \
      -continue                                                  \
      -release                                                   \
      -system-zlib                                               \
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
      || E "failed to install qgl$"
    fi

    touch ${TMP_DIR}/.${P}.done
    true
  fi
)

#
# Install qwt
#

(
  V=6.1.4
  P=qwt-${V}
  URL="https://github.com/opencor/qwt/archive/v${V}/${P}.tar.gz"
  CKSUM=sha256:0dd17f246f448c13659d10eb895bb52848c5e77c9c005ba9d47b55e3877d688c

  export INSTALL_ROOT="${INSTALL_DIR}/usr"
  export QMAKE_CXX="${CXX}"
  export QMAKE_CXXFLAGS="${CPPFLAGS}"
  export QMAKE_LFLAGS="${LDFLAGS}"
  EXTRA_OPTS="qwt.pro"

  build_and_install_qmake \
    ${P} \
    ${URL} \
    ${CKSUM} \
)

#
# Install sip
#

(
  V=4.19.19
  P=sip-${V}
  URL="https://www.riverbankcomputing.com/static/Downloads/sip/${V}/${P}.tar.gz"
  CKSUM=sha256:5436b61a78f48c7e8078e93a6b59453ad33780f80c644e5f3af39f94be1ede44
  T=${P}
  BRANCH=""

  export -n SHELLOPTS

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
      --sip-module=PyQt5.sip \
    && ${MAKE} \
    && ${MAKE} install \
    || E failed to build sip
      
    touch ${TMP_DIR}/.${P}.done
  fi
)

#
# Install PyQt5
#

(
  # For now, we'll need to use a development snapshot until issues with PyQt5 and SIP are resolved
  # in a stable release.
  V=5.13.1
  P=PyQt5_gpl-${V}
  URL="https://www.riverbankcomputing.com/static/Downloads/PyQt5/${V}/${P}.tar.gz"
  CKSUM=sha256:54b7f456341b89eeb3930e786837762ea67f235e886512496c4152ebe106d4af
  T=${P}
  BRANCH=""

  export -n SHELLOPTS


  if [ -f ${TMP_DIR}/.${P}.done ]; then
    I already installed ${P}
  else
    fetch "${P}" "${URL}" "${T}" "${BRANCH}" "${CKSUM}"
    unpack ${P} ${URL} ${T} ${BRANCH}

    ## Build and install PyQt5. Note that install fails if parallel'd, due to an
    ## install / metadata generation race condition.
      cd ${TMP_DIR}/${T}
      set -e

      # Set up our basic build environment...
      export CFLAGS="${CFLAGS} $(pkg-config --cflags Qt5Core Qt5Designer Qt5Gui Qt5OpenGL)" 
      export CXXFLAGS="${CPPFLAGS} $(pkg-config --cflags Qt5Core Qt5Designer Qt5Gui Qt5OpenGL)"
      export LDFLAGS="$(pkg-config --libs Qt5Core Qt5Designer Qt5Gui Qt5OpenGL)"
      export INSTALL_ROOT=""

      # ... and add Python extension support.
      export CFLAGS="${CFLAGS} $(${PYTHON_CONFIG} --cflags)"
      export CXXFLAGS="${CXXFLAGS} $(${PYTHON_CONFIG} --cflags)"
      export LDFLAGS="${LDFLAGS} $(${PYTHON_CONFIG} --ldflags)"

      # Configure the build, and generate the relevant makefiles.
      ${PYTHON} configure.py \
        INSTALL_ROOT="" \
        --confirm-license \
        -b ${INSTALL_DIR}/usr/bin \
        -d ${PYTHONPATH} \
        -v ${INSTALL_DIR}/usr/share/sip \
        --sysroot ${INSTALL_DIR} \

      ${MAKE}
      make install -j1

      touch ${TMP_DIR}/.${P}.done

fi
) || E "failed to build PyQt5"

#
# Install six
#
(
  V=1.12.0
  P=six-${V}
  URL="https://github.com/benjaminp/six/archive/${V}/${P}.tar.gz"
  CKSUM=sha256:0ce7aef70d066b8dda6425c670d00c25579c3daad8108b3e3d41bef26003c852

  build_and_install_setup_py \
    ${P} \
    ${URL} \
    ${CKSUM}
)


#
# Install pyyaml
#

# TODO: do we want to install libyaml?
# (grc doesn't parse much, so it's probably fine to rely on the pure python)
(
  V=5.1.2
  P=PyYAML-${V}
  URL="https://pyyaml.org/download/pyyaml/${P}.tar.gz"
  CKSUM=sha256:01adf0b6c6f61bd11af6e10ca52b7d4057dd0be0343eb9283c878cf3af56aee4

  build_and_install_setup_py \
    ${P} \
    ${URL} \
    ${CKSUM}
)

#
# Install libidn
#
(
  P=libidn2-2.2.0
  URL="https://ftp.gnu.org/gnu/libidn/${P}.tar.gz"
  CKSUM=sha256:fc734732b506d878753ec6606982bf7b936e868c25c30ddb0d83f7d7056381fe

  SKIP_AUTORECONF=true
  SKIP_LIBTOOLIZE=true

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM}
)



#
# Install log4cpp
#
(
  V=1.1.3
  P=log4cpp-${V}
  URL="https://downloads.sourceforge.net/log4cpp/${P}.tar.gz"
  CKSUM=sha256:2cbbea55a5d6895c9f0116a9a9ce3afb86df383cd05c9d6c1a4238e5e5c8f51d
  T=log4cpp

  SKIP_AUTORECONF=true
  SKIP_LIBTOOLIZE=true

  build_and_install_autotools \
    ${P} \
    ${URL} \
    ${CKSUM} \
    ${T}
)


#
# Install gnuradio
#
(
  P=gnuradio
  URL=git://github.com/gnuradio/gnuradio.git

  BRANCH=v${GNURADIO_BRANCH}
  CKSUM=${GNURADIO_COMMIT_HASH}
  T=${P}

  # Use Boost smart pointers over c++11 ones, for intercompatiblity.
  export CXXFLAGS="${CXXFLAGS} -DFORCE_BOOST_SMART_PTR"

  if [ ! -f ${TMP_DIR}/.${P}.done ]; then

    export -n SHELLOPTS

    fetch "${P}" "${URL}" "${T}" "${BRANCH}" "${CKSUM}"
    unpack ${P} ${URL} ${T}

    # Pull down the relevant version of Volk.
    git submodule update --init  

    PYTHONPATH=${PYTHONPATH} \
    EXTRA_OPTS="\
      -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/usr \
      -DFFTW3F_INCLUDE_DIRS=${INSTALL_DIR}/usr/include \
      -DZEROMQ_INCLUDE_DIRS=${INSTALL_DIR}/usr/include \
      -DTHRIFT_INCLUDE_DIRS=${INSTALL_DIR}/usr/include \
      -DCPPUNIT_INCLUDE_DIRS=${INSTALL_DIR}/usr/include/cppunit \
      -DPYTHON_EXECUTABLE=${PYTHON} \
      '-DCMAKE_C_FLAGS=-framework Python' \
      '-DCMAKE_CXX_FLAGS=-framework Python' \
      -DSPHINX_EXECUTABLE=${INSTALL_DIR}/usr/bin/rst2html-2.7.py \
      -DCMAKE_FIND_ROOT_PATH=${INSTALL_DIR};${INSTALL_DIR}/usr;${PYTHON_FRAMEWORK_DIR}  \
      -DGR_PYTHON_DIR=${INSTALL_DIR}/usr/share/gnuradio/python/site-packages \
      -DBoost_NO_BOOST_CMAKE=ON \
      -DPKG_CONFIG_USE_CMAKE_PREFIX_PATH=ON \
      -DQWT_LIBRARIES=${INSTALL_DIR}/usr/lib/qwt.framework/Versions/6/qwt \
      -DQWT_INCLUDE_DIRS=${INSTALL_DIR}/usr/lib/qwt.framework/Versions/6/Headers \
      -DCMAKE_IGNORE_PATH=/usr/local/lib;/usr/local/include \
      ${TMP_DIR}/${T} \
    " \
    build_and_install_cmake \
      ${P} \
      ${URL} \
      ${CKSUM} \
      ${T} \
      ${BRANCH} \

    touch ${TMP_DIR}/.${P}.done
  fi
)


#
# Install SoapySDR
#
(
  V=0.7.1
  P=soapy-sdr-${V}
  URL="https://github.com/pothosware/SoapySDR/archive/${P}/${P}.tar.gz"
  CKSUM=sha256:5445fbeb92f1322448bca3647f8cf12cc53d31ec6e0f11e0a543bacf43c8236d
  MVFROM="SoapySDR-${P}"
  
  export LDFLAGS="${LDFLAGS} $(${PYTHON_CONFIG} --ldflags)"

  EXTRA_OPTS="\
    -DCMAKE_MACOSX_RPATH=OLD \
    -DCMAKE_INSTALL_NAME_DIR=${INSTALL_DIR}/usr/lib \
    -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/usr \
    -DPYTHON3_EXECUTABLE=$(which ${PYTHON}) \
    -DPYTHON3_CONFIG_EXECUTABLE=${PYTHON_CONFIG} \
    -DPYTHON_EXECUTABLE=$(which ${PYTHON}) \
    -DCMAKE_IGNORE_PATH=/usr/local/lib;/usr/local/include \
    ${TMP_DIR}/${P}"

  build_and_install_cmake \
    ${P} \
    ${URL} \
    ${CKSUM} \
    ${P} \
    "" \
    ${MVFROM} \
    ${P}
)


#
# Install LimeSuite
#
(
  V=19.04.0
  P=limesuite-${V}
  URL="https://github.com/myriadrf/LimeSuite/archive/v${V}/${P}.tar.gz"
  CKSUM=sha256:353862493acb5a3d889202bcb251e182cc8a877bb54472b8b163c57ad1aaf0ce

  export LDFLAGS="${LDFLAGS} $(${PYTHON_CONFIG} --ldflags)"

  EXTRA_OPTS="\
    -DCMAKE_MACOSX_RPATH=OLD \
    -DCMAKE_INSTALL_NAME_DIR=${INSTALL_DIR}/usr/lib \
    -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/usr \
    -DPYTHON_EXECUTABLE=$(which ${PYTHON}) \
    -DENABLE_GUI=off \
    -DENABLE_QUICKTEST=off \
    -DCMAKE_IGNORE_PATH=/usr/local/lib;/usr/local/include \
    ${TMP_DIR}/${P}" \
  build_and_install_cmake \
    ${P} \
    ${URL} \
    ${CKSUM} \
)

#
# Install osmo-sdr
#
(
  P=osmo-sdr
  URL=git://git.osmocom.org/osmo-sdr
  CKSUM=git:ba4fd96622606620ff86141b4d0aa564712a735a
  T=${P}
  BRANCH=ba4fd96622606620ff86141b4d0aa564712a735a

  export LDFLAGS="${LDFLAGS} $(${PYTHON_CONFIG} --ldflags)"

  EXTRA_OPTS="\
    -DCMAKE_MACOSX_RPATH=OLD \
    -DCMAKE_INSTALL_NAME_DIR=${INSTALL_DIR}/usr/lib \
    -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/usr \
    -DPYTHON_EXECUTABLE=$(which ${PYTHON}) \
    -DCMAKE_IGNORE_PATH=/usr/local/lib;/usr/local/include \
    ${TMP_DIR}/${T}" \
  build_and_install_cmake \
    ${P} \
    ${URL} \
    ${CKSUM} \
    ${T} \
    ${BRANCH}
)

#
# Install libhackrf
#
(
  V=2018.01.1
  P=hackrf-${V}
  URL="https://github.com/mossmann/hackrf/releases/download/v${V}/${P}.tar.xz"
  CKSUM=sha256:a89badc09a1d2fa18367b3b2c974580ad5f6ce93aaa4e54557dc3d013c029d14
  T=${P}/host

  EXTRA_OPTS="\
    -DCMAKE_MACOSX_RPATH=OLD \
    -DCMAKE_INSTALL_NAME_DIR=${INSTALL_DIR}/usr/lib \
    -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/usr \
    -DCMAKE_C_FLAGS=\"-I${INSTALL_DIR}/usr/include\" \
    -DCMAKE_IGNORE_PATH=/usr/local/lib;/usr/local/include \
    ${TMP_DIR}/${T}"
  build_and_install_cmake \
    ${P} \
    ${URL} \
    ${CKSUM} \
    ${T}
)

#
# Install libbladerf
#
(
  P=bladeRF-2019.07
  URL="git://github.com/Nuand/bladeRF.git"
  CKSUM=git:991bba2f9c4d000f000077cc465878d303417e26
  T=${P}/host
  BRANCH=2019.07

  EXTRA_OPTS="\
    -DCMAKE_MACOSX_RPATH=OLD \
    -DCMAKE_INSTALL_NAME_DIR=${INSTALL_DIR}/usr/lib \
    -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/usr \
    -DCMAKE_C_FLAGS=\"-I${INSTALL_DIR}/usr/include\" \
    -DCMAKE_IGNORE_PATH=/usr/local/lib;/usr/local/include \
    ${TMP_DIR}/${T}" \

  build_and_install_cmake \
    ${P} \
    ${URL} \
    ${CKSUM} \
    ${T} \
    ${BRANCH}
)


#
# Install the relevant bladeRF bitstreams, so bladeRF devices can be used from GRC without user intervention.
#
install_bladerf_bitstream_if_needed "xA4"  "c172e35c4a92cf1e0ca3b37347a84d8376b275ece16cb9c5142b72b82b16fe8e"
install_bladerf_bitstream_if_needed "xA9"  "99f60e91598ea5b998873922eba16cbab60bfd5812ebc1438f49b420ba79d7e1"
install_bladerf_bitstream_if_needed "x40"  "a26e07b8ad0b4c20327f97ae89a89dbe2e00c7f90e70dae36902e62e233bd290"
install_bladerf_bitstream_if_needed "x115" "604b12af77ce4f34db061e9eca4a38d804f676b8ad73ceacf49b6de3473a86f7"


#
# Install libairspy
#
(
  V=1.0.9
  P=airspy-${V}
  URL="https://github.com/airspy/airspyone_host/archive/v${V}/${P}.tar.gz"
  CKSUM=sha256:967ef256596d4527b81f007f77b91caec3e9f5ab148a8fec436a703db85234cc
  MVFROM="airspyone_host-${V}"

  EXTRA_OPTS="\
    -DCMAKE_INSTALL_NAME_DIR=${INSTALL_DIR}/usr/lib \
    -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/usr \
    -DCMAKE_C_FLAGS=\"-I${INSTALL_DIR}/usr/include\" \
    -DCMAKE_IGNORE_PATH=/usr/local/lib;/usr/local/include \
    ${TMP_DIR}/${P}" \
  build_and_install_cmake \
    ${P} \
    ${URL} \
    ${CKSUM} \
    ${P} \
    "" \
    ${MVFROM} \
    ${P}
)


#
# Install libairspy
#
(
  V=1.1.5
  P=airspyhf-${V}
  URL="https://github.com/airspy/airspyhf/archive/${V}/${P}.tar.gz"
  CKSUM=sha256:270c332e16677469d7644053e4905106ef0aa52f0da10fd9f22cca05fe1dd2ef

  EXTRA_OPTS="\
    -DCMAKE_INSTALL_NAME_DIR=${INSTALL_DIR}/usr/lib \
    -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/usr \
    -DCMAKE_C_FLAGS=\"-I${INSTALL_DIR}/usr/include\" \
    -DCMAKE_IGNORE_PATH=/usr/local/lib;/usr/local/include \
    ${TMP_DIR}/${P}" \
  build_and_install_cmake \
    ${P} \
    ${URL} \
    ${CKSUM} \
    ${P}
)


#
# Install libiio
#
(
  V=0.18
  P=libiio-${V}
  URL="https://github.com/analogdevicesinc/libiio/archive/v${V}/${P}.tar.gz"
  CKSUM=sha256:bc2c5299974b65cfe9aa4a06d8c74d7651594e026bce416db48a2c5aa7ba2554

  export DESTDIR=""

  EXTRA_OPTS="\
    -DCMAKE_INSTALL_NAME_DIR=${INSTALL_DIR}/usr/lib \
    -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/usr \
    -DCMAKE_C_FLAGS=\"-I${INSTALL_DIR}/usr/include\" \
    -DCMAKE_IGNORE_PATH=/usr/local/lib;/usr/local/include \
    -DOSX_PACKAGE=OFF \
    -DENABLE_PACKAGING=OFF \
    -DWITH_DOC=OFF \
    -DWITH_TESTS=OFF \
    ${TMP_DIR}/${P}" \
  build_and_install_cmake \
    ${P} \
    ${URL} \
    ${CKSUM} \
    ${P}
)




##
## Install libmirisdr
## FIXME: should this be uprev'd?
##
#(
#  P=libmirisdr
#  URL=git://git.osmocom.org/libmirisdr.git
#  CKSUM=git:59ba3721b1cb7c746503d8de9c918f54fe7e8399
#  T=${P}
#  BRANCH=master
#
#  SKIP_AUTORECONF=true \
#  SKIP_LIBTOOLIZE=true \
#  build_and_install_autotools \
#    ${P} \
#    ${URL} \
#    ${CKSUM} \
#    ${T} \
#    ${BRANCH}
#)

#
# Install gr-osmosdr
#
(
  P=gr-osmosdr
  URL=https://github.com/osmocom/gr-osmosdr.git
  CKSUM=git:af2fda22b3b3745520ef38e9aaa757484871ee0c
  BRANCH=af2fda22b3b3745520ef38e9aaa757484871ee0c
  T=${P}

  LDFLAGS="${LDFLAGS} $(${PYTHON_CONFIG} --ldflags)" \
  EXTRA_OPTS="\
    -DCMAKE_MACOSX_RPATH=OLD \
    -DCMAKE_INSTALL_NAME_DIR=${INSTALL_DIR}/usr/lib \
    -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/usr \
    -DPYTHON_EXECUTABLE=$(which ${PYTHON}) \
    -DBoost_NO_BOOST_CMAKE=ON \
    -DPKG_CONFIG_USE_CMAKE_PREFIX_PATH=ON \
    -DCMAKE_PREFIX_PATH=${INSTALL_DIR} \
    -DCMAKE_IGNORE_PATH=/usr/local/lib;/usr/local/include \
    ${TMP_DIR}/${T}" \
  build_and_install_cmake \
    ${P} \
    ${URL} \
    ${CKSUM} \
    ${T} \
    ${BRANCH}
)


#
# Install gr-fosphor
#
(
  P=gr-fosphor
  URL=https://github.com/osmocom/gr-fosphor.git
  CKSUM=git:2d4fe78b43bb67907722f998feeb4534ecb1efa8
  BRANCH=2d4fe78b43bb67907722f998feeb4534ecb1efa8
  T=${P}

  LDFLAGS="${LDFLAGS} $(${PYTHON_CONFIG} --ldflags)" \
  EXTRA_OPTS="\
    -DCMAKE_MACOSX_RPATH=OLD \
    -DCMAKE_INSTALL_NAME_DIR=${INSTALL_DIR}/usr/lib \
    -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/usr \
    -DPYTHON_EXECUTABLE=$(which ${PYTHON}) \
    -DBoost_NO_BOOST_CMAKE=ON \
    -DPKG_CONFIG_USE_CMAKE_PREFIX_PATH=ON \
    -DCMAKE_PREFIX_PATH=${INSTALL_DIR} \
    -DCMAKE_IGNORE_PATH=/usr/local/lib;/usr/local/include \
    ${TMP_DIR}/${T}" \
  build_and_install_cmake \
    ${P} \
    ${URL} \
    ${CKSUM} \
    ${T} \
    ${BRANCH}
)


#
# Install our supported Soapy plugins.
#
install_soapy_plugin_if_needed "BladeRF"   "1c1e8aaba5e8ee154b34c6c3b17743d1c9b9a1ea"
install_soapy_plugin_if_needed "HackRF"    "3c514cecd3dd2fdf4794aebc96c482940c11d7ff"
install_soapy_plugin_if_needed "RTLSDR"    "5c5d9503337c6d1c34b496dec6f908aab9478b0f"
install_soapy_plugin_if_needed "UHD"       "7371e688fa3b0b444df948d5492ab93d0988eda8"
install_soapy_plugin_if_needed "Airspy"    "99756be5c3413a2d447baf70cb5a880662452655"
install_soapy_plugin_if_needed "AirspyHF"  "a76abd9f16458513fa8aebfae58a09a4b8daaf1e"
install_soapy_plugin_if_needed "NetSDR"    "11f80b326c9ae23536f5246dffa8320f7dafbcb7"
install_soapy_plugin_if_needed "RedPitaya" "3d576f83b3bde52104b2a88150516ca8c9a78c7a"
install_soapy_plugin_if_needed "PlutoSDR" "e28e4f5c68c16a38c0b50b9606035f3267a135c8" \
  "-DLIBIIO_INCLUDE_DIR=${INSTALL_DIR}/usr/lib/iio.framework/Versions/0.18/Headers"


#
# Install gr-soapy
#
(
  P=gr-soapy
  URL=https://gitlab.com/librespacefoundation/gr-soapy.git
  CKSUM=git:a68d05c1f4d069deb7c0efe2a73137ad6cb91c73
  BRANCH=a68d05c1f4d069deb7c0efe2a73137ad6cb91c73
  T=${P}

  # -DCMAKE_PREFIX_PATH=${INSTALL_DIR} \
  LDFLAGS="${LDFLAGS} $(${PYTHON_CONFIG} --ldflags)" \
  EXTRA_OPTS="\
    -DCMAKE_MACOSX_RPATH=OLD \
    -DCMAKE_INSTALL_NAME_DIR=${INSTALL_DIR}/usr/lib \
    -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/usr \
    -DPYTHON_EXECUTABLE=$(which ${PYTHON}) \
    -DBoost_INCLUDE_DIR=${INSTALL_DIR}/usr/include \
    -DCMAKE_IGNORE_PATH=/usr/local/lib;/usr/local/include \
    ${TMP_DIR}/${T}" \
  build_and_install_cmake \
    ${P} \
    ${URL} \
    ${CKSUM} \
    ${T} \
    ${BRANCH}
)


#
# Install gr-limesdr
#
(
  P=gr-limesdr
  URL=https://github.com/myriadrf/gr-limesdr.git
  CKSUM=git:ca01a641a527342ee80c21439923be85c11793df
  BRANCH=ca01a641a527342ee80c21439923be85c11793df
  T=${P}

  # -DCMAKE_PREFIX_PATH=${INSTALL_DIR} \
  LDFLAGS="${LDFLAGS} $(${PYTHON_CONFIG} --ldflags)" \
  EXTRA_OPTS="\
    -DCMAKE_MACOSX_RPATH=OLD \
    -DCMAKE_INSTALL_NAME_DIR=${INSTALL_DIR}/usr/lib \
    -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/usr \
    -DPYTHON_EXECUTABLE=$(which ${PYTHON}) \
    -DBoost_INCLUDE_DIR=${INSTALL_DIR}/usr/include \
    -DCMAKE_IGNORE_PATH=/usr/local/lib;/usr/local/include \
    ${TMP_DIR}/${T}" \
  build_and_install_cmake \
    ${P} \
    ${URL} \
    ${CKSUM} \
    ${T} \
    ${BRANCH}
)


#
# Finish off the installation by correcting any issues produced by e.g.
# incompatibilities in our various install scripts. These hacks are a bit
# cursed, but they make things work without having an Even More Cursed weight
# of dozens of patches.
#
(
  P=post-build-fixes
  DONE=${TMP_DIR}/.${P}.done

  if [ ! -f ${DONE} ]; then

    I Performing post-build fixups...

    # If any of our libraries have wound up installed with library references that
    # aren't compatibile with MacOS (e.g. @rpath references or relative paths), fix them
    # up using the MacOS utility that exists 
    I "Fixing up any broken dylib references that exist... "
    replace_bad_dylib_paths ${INSTALL_DIR}

    # Mark this package as complete.
    touch ${DONE}

  fi
)

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
(
  P=scripts

  I creating grenv.sh script
cat > ${INSTALL_DIR}/usr/bin/grenv.sh <<- EOF
PYTHON=${PYTHON}
INSTALL_DIR=${INSTALL_DIR}
ULPP=${INSTALL_PYTHON_DIR}
PYTHONPATH=\${ULPP}:\${PYTHONPATH}
GRSHARE=\${INSTALL_DIR}/usr/share/gnuradio
GRPP=${INSTALL_GNURADIO_PYTHON_DIR}
PYTHONPATH=\${GRPP}:\${PYTHONPATH}
PATH=\${INSTALL_DIR}/usr/bin:/opt/X11/bin:\${PATH}
XDG_DATA_DIRS=\${INSTALL_DIR}/usr/share
BLADERF_SEARCH_DIR=\${INSTALL_DIR}/usr/share/Nuand/bladeRF
EOF

  if [ $? -ne 0 ]; then
    E unable to create grenv.sh script
  fi

  cd ${INSTALL_PYTHON_DIR} \
  && \
    for j in $(for i in $(find * -name '*.so'); do dirname $i; done | sort -u); do \
      echo "DYLD_LIBRARY_PATH=\"\${ULPP}/${j}:\${DYLD_LIBRARY_PATH}\"" >> ${INSTALL_DIR}/usr/bin/grenv.sh; \
    done \
    && echo "" >> ${INSTALL_DIR}/usr/bin/grenv.sh \
  || E failed to create grenv.sh;

  cd ${INSTALL_GNURADIO_PYTHON_DIR} \
  && \
    for j in $(for i in $(find * -name '*.so'); do dirname $i; done | sort -u); do \
      echo "DYLD_LIBRARY_PATH=\"\${GRPP}/${j}:\${DYLD_LIBRARY_PATH}\"" >> ${INSTALL_DIR}/usr/bin/grenv.sh; \
      echo "PYTHONPATH=\"\${GRPP}/${j}:\${PYTHONPATH}\"" >> ${INSTALL_DIR}/usr/bin/grenv.sh; \
    done \
  && echo "export DYLD_LIBRARY_PATH" >> ${INSTALL_DIR}/usr/bin/grenv.sh \
  && echo "export PYTHONPATH" >> ${INSTALL_DIR}/usr/bin/grenv.sh \
  && echo "export PATH" >> ${INSTALL_DIR}/usr/bin/grenv.sh \
  && echo "export XDG_DATA_DIRS" >> ${INSTALL_DIR}/usr/bin/grenv.sh \
  && echo "export BLADERF_SEARCH_DIR" >> ${INSTALL_DIR}/usr/bin/grenv.sh \
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
)


#
# Create the GNURadio.app bundle
# 
(
  P=gr-logo
  URL=http://github.com/gnuradio/gr-logo.git
  CKSUM=git:8f51887761b88b8c4facda0970ae121b61a0d905
  T=${P}
  BRANCH="master"


  #if [ ! -f ${TMP_DIR}/.${P}.done ]; then

  I "Installing support scripts..."

  fetch "${P}" "${URL}" "${T}" "${BRANCH}" "${CKSUM}"
  unpack ${P} ${URL} ${T}

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
)

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

#
# Create .dmg file
#
(
  P=create-dmg
  URL=https://github.com/beaugunderson/create-dmg.git
  CKSUM=git:2ca05eb08f852b07c4e9e15feda257deaf45fba3
  T=${P}
  BRANCH=master

  #if [ ! -f ${TMP_DIR}/${P}.done ]; then

    fetch "${P}" "${URL}" "${T}" "${BRANCH}" "${CKSUM}"
    unpack ${P} ${URL} ${T}
    
    #XXX: @CF: add --eula option with GPLv3. For now, just distribute LICENSE in dmg
    
    VERSION="$(gen_version)"
    
    I creating GNURadio-${VERSION}.dmg
    
    cd ${TMP_DIR}/${P} \
    && I "copying GNURadio.app to temporary folder (this can take some time)" \
    && rm -Rf ${TMP_DIR}/${P}/temp \
    && rm -f ${BUILD_DIR}/*GNURadio-${VERSION}.dmg \
    && mkdir -p ${TMP_DIR}/${P}/temp \
    && rsync -ar ${APP_DIR} ${TMP_DIR}/${P}/temp \
    && cp ${BUILD_DIR}/LICENSE ${TMP_DIR}/${P}/temp \
    && I "executing create-dmg.. (this can take some time)" \
    && I "create-dmg \
      --volname "GNURadio-${VERSION}" \
      --volicon ${BUILD_DIR}/gnuradio.icns \
      --background ${BUILD_DIR}/gnuradio-logo-noicon.png \
      --window-pos 200 120 \
      --window-size 550 400 \
      --icon LICENSE 137 190 \
      --icon GNURadio.app 275 190 \
      --hide-extension GNURadio.app \
      --app-drop-link 412 190 \
      --icon-size 100 \
      ${BUILD_DIR}/GNURadio-${VERSION}.dmg \
      ${TMP_DIR}/${P}/temp \
    " \
    && ./create-dmg \
      --volname "GNURadio-${VERSION}" \
      --volicon ${BUILD_DIR}/gnuradio.icns \
      --background ${BUILD_DIR}/gnuradio-logo-noicon.png \
      --window-pos 200 120 \
      --window-size 550 400 \
      --icon LICENSE 137 190 \
      --icon GNURadio.app 275 190 \
      --hide-extension GNURadio.app \
      --app-drop-link 412 190 \
      --icon-size 100 \
      --skip-jenkins \
      ${BUILD_DIR}/GNURadio-${VERSION}.dmg \
      ${TMP_DIR}/${P}/temp \
    || E "failed to create GNURadio-${VERSION}.dmg"

  I "finished creating GNURadio-${VERSION}.dmg"

    touch ${TMP_DIR}/.${P}.done 
  #fi
)


I ============================================================================
I finding broken .dylibs and .so files in ${INSTALL_DIR}
I ============================================================================
export -n SHELLOPTS
${INSTALL_DIR}/usr/bin/find-broken-dylibs
I ============================================================================

I '!!!!!! DONE !!!!!!'
