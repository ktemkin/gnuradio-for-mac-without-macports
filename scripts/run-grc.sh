#!/bin/sh

export APP_DIR="$(cd "$(dirname "${0}")"/../../../../; pwd)"

source "${APP_DIR}"/Contents/MacOS/usr/bin/grenv.sh

if [ ! -f "${APP_DIR}"/Contents/MacOS/usr/bin/${PYTHON} ]; then
  cp $(which ${PYTHON}) "${APP_DIR}"/Contents/MacOS/usr/bin || exit 1
fi

cd "${APP_DIR}"/Contents/MacOS/usr/bin
install_name_tool -add_rpath "${PWD}" ${PYTHON}  2>/dev/null
find "${APP_DIR}" -name '*.so' -type f > /tmp/run-grc.sh.solist
while read line; do
  install_name_tool -add_rpath "${PWD}" "${line}" 2>/dev/null
done < /tmp/run-grc.sh.solist
rm -f /tmp/run-grc.sh.solist
cd "${OLDPWD}"

gnuradio-companion ${@} &

exit 0
