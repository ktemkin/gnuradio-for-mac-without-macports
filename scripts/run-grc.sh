#!/bin/sh

# Figure out where this script is located:
case "$0" in
	/*)
		# $0 is absolute path since it starts with /
		argv0_path="$0"
		;;
	*)
		# Assume $0 is relative path:
		argv0_path="$PWD/$0"
		;;
esac
# This script is in GNURadio.app/Contents/MacOS/usr/bin with grenv.sh
grenv_path="${argv0_path%/*}/grenv.sh"

if ! test -e "${grenv_path}" ; then
	printf 'Unable to find grenv.sh at %s\n' "${grenv_path}" 1>&2
	exit 1
fi
. "${grenv_path}"

exec gnuradio-companion "${@}"
