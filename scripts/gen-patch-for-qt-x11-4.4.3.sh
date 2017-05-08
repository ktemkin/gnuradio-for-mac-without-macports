#!/bin/sh

# This script was used to automatically generate 
# qt-x11-opensource-src-4.4.3-00-macports.patch .
# The remainder of the patches were generated via manual edits and git diff.

ORIGDIR="${PWD}"

. /Applications/GNURadio.app/Contents/MacOS/usr/bin/grenv.sh

PN="qt-x11-opensource-src-4.4.3"
A="${PN}.tar.gz"

SRCDIR=${HOME}/workspace/${PN}
GIT_BRANCH="macports-qt4"

PATCH="${ORIGDIR}/qt-x11-opensource-src-4.4.3-00-macports.patch"

prefix=/Applications/GNURadio.app/Contents/MacOS/usr
xprefix=/opt/X11
worksrcpath=${SRCDIR}
configure_cc=${clang}
configure_cxx=${clang++}

function die() {
  local r
  r=$?
  if [ 0 -eq $r ]; then
    r=1
  fi
  echo "$*"
  exit $r
}

function extract_archive() {
  if [ ! -d ${SRCDIR}/ ]; then
    cd $(dirname ${SRCDIR}) && tar xpvzf ${DLDIR}/${A} || die "failed to extract "
  fi
}

function git_init() {
  if [ ! -e ${SRCDIR}/.git ]; then
    cd ${SRCDIR} && git init . && git add . && git commit -m 'initial commit' || die "git init failed"
  fi
}

function git_reset() {
  if [ "" != "$(cd ${SRCDIR}/ && git branch | grep "${GIT_BRANCH}")" ]; then
    cd ${SRCDIR} && \
      git reset && git checkout . && \
      git checkout ${GIT_BRANCH} && \
      git reset && git checkout . \
    || die "git branch -D failed" 
  else
    cd ${SRCDIR} && \
      git reset && git checkout . && \
      git checkout -b ${GIT_BRANCH} \
    || die "git branch -D failed" 
  fi
}

function apply_patch_compile_test_diff() {
  local url='https://raw.githubusercontent.com/macports/macports-ports/master/x11/qt4-x11/files/patch-compile.test.diff'
  
  echo "applying patch-compile.test.diff.."
  
  cd ${SRCDIR} && curl -s --insecure ${URL} 2>/dev/null | patch -p0 || die "failed to apply patch-compile.test.diff"
}

function reinplace() {
  local re=${1}
  local f=${2}
  
  echo "applying '${re}' to ${f}.."
  
  sed \
    -e "${re}" ${f} > /tmp/foo.txt && \
    mv /tmp/foo.txt ${f} \
  || die "failed to apply '${re}' to ${f}"
}

function post_patch() {
   
   echo "in post_patch()"
  
    reinplace "s|^I_FLAGS=\$|I_FLAGS=-isystem${prefix}/include|" \
        ${worksrcpath}/configure

    # macosx seems to be a special architecture to accommodate universal builds, but here is no
    #    ${worksrcpath}/include/QtCore/qatomic_macosx.h file, which causes an error
    reinplace "s|CFG_HOST_ARCH=macosx|CFG_HOST_ARCH=x86_64|g" ${worksrcpath}/configure

    # Ensure the correct MacPorts X11 is used
    reinplace "s|/usr/X11R6|${xprefix}|g" ${worksrcpath}/mkspecs/darwin-g++/qmake.conf

    # Avoid having to call "install_name_tool -change" after destroot.
    reinplace \
        "s|install_name\$\${LITERAL_WHITESPACE\}|install_name\$\${LITERAL_WHITESPACE}\$\$[QT_INSTALL_LIBS]|g" \
        ${worksrcpath}/mkspecs/darwin-g++/qmake.conf

    # ensure that MacPorts compilers are used
#    reinplace "s| cc\$| ${configure_cc}|"  ${worksrcpath}/mkspecs/darwin-g++/qmake.conf
#    reinplace "s| c++\$| ${configure_cxx}|" ${worksrcpath}/mkspecs/darwin-g++/qmake.conf

    # Q_OS_MAC, Q_OS_MACX, and Q_OS_DARWIN is set for all Mac systems.
    # Q_WS_MAC is NOT set for the X11 version of QT.
    # It is not clear why so many of these had to be changed.
    #
    # Excluded:
    #        ${worksrcpath}/src/corelib/global/qglobal.h
    #        ${worksrcpath}/src/network/kernel/qhostinfo_unix.cpp
    for file in \
        qmake/generators/mac/pbuilder_pbx.cpp \
        src/3rdparty/webkit/WebKit/qt/Api/qwebpage.cpp \
        src/corelib/global/qglobal.cpp \
        src/corelib/io/qfile.cpp \
        src/corelib/io/qfsfileengine_unix.cpp \
        src/corelib/plugin/qlibrary.cpp \
        src/corelib/thread/qthread_unix.cpp \
        src/corelib/tools/qlocale.cpp \
        src/network/ssl/qsslsocket_openssl_symbols.cpp \
        tools/porting/src/qt3headers1.resource \
        tools/qvfb/qlock.cpp
    do
        reinplace "s|Q_OS_DARWIN|Q_WS_MAC|g" ${worksrcpath}/${file}
    done
    # Excluded:
    #        ${worksrcpath}/src/corelib/global/qglobal.h
    for file in \
        src/corelib/tools/qdumper.cpp \
        src/qt3support/other/q3accel.cpp \
        src/qt3support/other/q3process_unix.cpp \
        tools/porting/src/qt3headers1.resource \
        tools/porting/src/qt3headers3.resource
    do
        reinplace "s|Q_OS_MACX|Q_WS_MAC|g" ${worksrcpath}/${file}
    done
    # Edited from command:
    # grep -rl "\(Q_OS_MAC\$\|Q_OS_MAC[^X]\)" * | grep -v \.resource\$ | grep -v ^doc/ | grep -v src/corelib/global/qglobal.h
    # Excluded:
    #        ${worksrcpath}/src/corelib/global/qglobal.h
    #        ${worksrcpath}/tools/assistant/lib/fulltextsearch/qclucene-config_p.h
    #        ${worksrcpath}/src/script/qscriptengine_p.cpp
    #        ${worksrcpath}/src/corelib/io/qprocess.cpp
    #        ${worksrcpath}/src/corelib/io/qfilesystemwatcher.cpp
    #        ${worksrcpath}/src/corelib/concurrent/qtconcurrentiteratekernel.cpp
    for file in \
        demos/mediaplayer/mediaplayer.cpp \
        demos/qtdemo/colors.cpp \
        demos/qtdemo/menumanager.cpp \
        examples/dialogs/standarddialogs/dialog.cpp \
        examples/help/remotecontrol/remotecontrol.cpp \
        examples/help/simpletextviewer/assistant.cpp \
        examples/tools/echoplugin/echowindow/echowindow.cpp \
        examples/tools/plugandpaint/mainwindow.cpp \
        qmake/main.cpp \
        qmake/option.cpp \
        src/corelib/codecs/qiconvcodec.cpp \
        src/corelib/codecs/qiconvcodec_p.h \
        src/corelib/global/qglobal.cpp \
        src/corelib/global/qlibraryinfo.cpp \
        src/corelib/global/qnamespace.h \
        src/corelib/io/qdir.cpp \
        src/corelib/io/qfsfileengine_unix.cpp \
        src/corelib/io/qprocess_unix.cpp \
        src/corelib/io/qsettings.cpp \
        src/corelib/io/qsettings_p.h \
        src/corelib/kernel/qcoreapplication.cpp \
        src/corelib/kernel/qcoreapplication_p.h \
        src/corelib/plugin/qlibrary.cpp \
        src/corelib/plugin/qlibrary_unix.cpp \
        src/corelib/thread/qthread_unix.cpp \
        src/corelib/thread/qthread.cpp \
        src/corelib/tools/qlocale.cpp \
        src/corelib/tools/qpoint.h \
        src/corelib/tools/qrect.h \
        src/corelib/tools/qstring.cpp \
        src/corelib/xml/qxmlstream.h \
        src/gui/dialogs/qfilesystemmodel.cpp \
        src/gui/dialogs/qprintdialog.h \
        src/gui/itemviews/qdirmodel.cpp \
        src/gui/itemviews/qfileiconprovider.cpp \
        src/gui/kernel/qapplication.h \
        src/gui/kernel/qapplication_p.h \
        src/gui/text/qfont.cpp \
        src/gui/text/qfontdatabase.cpp \
        src/gui/widgets/qdockwidget.cpp \
        src/plugins/accessible/widgets/simplewidgets.cpp \
        src/qt3support/other/q3polygonscanner.cpp \
        src/qt3support/text/q3textedit.cpp \
        src/sql/drivers/odbc/qsql_odbc.h \
        src/tools/uic/cpp/cppwriteinitialization.cpp \
        src/tools/uic/cpp/cppwriteinitialization.h \
        tools/assistant/compat/lib/qassistantclient.cpp \
        tools/assistant/lib/qhelpsearchresultwidget.cpp \
        tools/assistant/tools/assistant/bookmarkmanager.cpp \
        tools/assistant/tools/assistant/centralwidget.cpp \
        tools/assistant/tools/assistant/indexwindow.cpp \
        tools/assistant/tools/assistant/mainwindow.cpp \
        tools/designer/src/designer/assistantclient.cpp \
        tools/designer/src/designer/qdesigner_actions.cpp \
        tools/designer/src/lib/uilib/abstractformbuilder.cpp \
        tools/linguist/linguist/trwindow.cpp \
        tools/linguist/shared/proparserutils.h \
        tools/shared/findwidget/findwidget.cpp
    do
      reinplace "s|Q_OS_MAC|Q_WS_MAC|g" ${worksrcpath}/${file}
    done
}

function fix_this_version_of_mac_os_x_is_unsupported() {
  reinplace "s|\\(#    error \\\"This version of Mac OS X is unsupported\\\"\\)|//\1|" \
    src/corelib/global/qglobal.h
}

function do_not_prebind() {
  reinplace "s|-prebind||g" mkspecs/darwin-g++/qmake.conf
}

function fix_bidirectional_iterator_tag() {
  reinplace '45,49d;41i\'$'\n#include <iterator>' src/corelib/tools/qiterator.h
  reinplace "45d;48d;" src/corelib/tools/qlist.h
  #reinplace "41i#include <iterator>" src/corelib/tools/qset.h
  #reinplace "45d;46d;45i#include <iterator>" src/corelib/tools/qmap.h
  #reinplace "45d;46d;45i#include <iterator>" src/corelib/tools/qhash.h
}

function fix_illegal_png_info_accesses() {
  
}

function gen_patch() {
  
  echo "generating $(basename ${PATCH})"
  
  cd ${SRCDIR} && \
    git diff > ${PATCH} \
  || die "failed to generate patch"

  dlines=""
  for lineno in $(grep -n "^Binary files" ${PATCH} | awk '{split($0,a,":"); print a[1];}'); do
    dlines="${dlines}$((lineno-2)),$((lineno+1))d;"
  done
  
  sed -e "${dlines}" ${PATCH} > ${PATCH}.tmp && 
    mv ${PATCH}.tmp ${PATCH} \
  || die "failed to delete 'Binary files' lines"
}

function main() {
  extract_archive
  git_init
  git_reset
  
  apply_patch_compile_test_diff
  post_patch
  
  fix_this_version_of_mac_os_x_is_unsupported
  
  do_not_prebind
  fix_bidirectional_iterator_tag
  
  gen_patch
}

main

echo "SUCCESS!!!"
