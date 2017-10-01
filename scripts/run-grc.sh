#!/bin/sh

XQUARTZ_APP_DIR=/Applications/Utilities/XQuartz.app
PYTHON_FRAMEWORK_DIR=/System/Library/Frameworks/Python.framework/Versions/2.7

set -e

show_fail_message () {
	osascript -e 'display notification "Failed to start GNU Radio Companion.\nDetail: '"$*"'" with title "GNU Radio Companion"' > /dev/null 2>&1 || true
	return 0
}

# If the exec fails for some reason, then our EXIT handler will get invoked.
# At exit, run cleanup_script but let the exit status still be whatever the
# shell was going to exit with:
trap 'show_fail_message "exit status $?"' EXIT

# If we get a signal such as SIGINT SIGQUIT or SIGTERM, then mask signal,
# show_fail_message, restore default handler, and raise signal again to let it
# propagate to whatever process started this script:
trap '{ trap - EXIT ; trap "" INT  ; show_fail_message "received signal INT"  ; trap - INT  ; kill -s INT  $$ ; }' INT
trap '{ trap - EXIT ; trap "" QUIT ; show_fail_message "received signal QUIT" ; trap - QUIT ; kill -s QUIT $$ ; }' QUIT
trap '{ trap - EXIT ; trap "" TERM ; show_fail_message "received signal TERM" ; trap - TERM ; kill -s TERM $$ ; }' TERM
# The leading "trap - EXIT" disables the EXIT signal handler or otherwise
# show_fail_message gets called twice.

# Uncomment one at a time to test each exit condition:
#kill -s INT -- $$
#kill -s QUIT -- $$
#kill -s TERM -- $$
#exit 2

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

if ! test -d ${XQUARTZ_APP_DIR} ; then
    osascript \
        -e 'on run(argv)' \
        -e 'display dialog ("XQuartz is not installed. Download it at http://www.xquartz.org/") buttons {"OK"} default button 1 with icon stop with title "GNU Radio Companion"' \
        -e 'end run' \
        > /dev/null 2>&1 || true
    printf 'XQuartz is not installed. Download it at http://www.xquartz.org/\n' 1>&2
fi

if ! test -d ${PYTHON_FRAMEWORK_DIR} ; then
    osascript \
        -e 'on run(argv)' \
        -e 'display dialog ("Python 2.7 is not installed. Download it here: https://www.python.org/downloads/") buttons {"OK"} default button 1 with icon stop with title "GNU Radio Companion"' \
        -e 'end run' \
        > /dev/null 2>&1 || true
    printf 'Python 2.7 is not installed. Download it here: https://www.python.org/downloads/\n' 1>&2
fi

if ! test -e "${grenv_path}" ; then
	osascript \
		-e 'on run(argv)' \
		-e 'display dialog ("Unable to find grenv.sh at " & item 1 of argv) buttons {"OK"} default button 1 with icon stop with title "GNU Radio Companion"' \
		-e 'end run' \
		-- "${grenv_path}" \
		> /dev/null 2>&1 || true
	printf 'Unable to find grenv.sh at %s\n' "${grenv_path}" 1>&2
	exit 1
fi
. "${grenv_path}"

# Strip out the -psn_... argument added by the OS.
if [ "x${1#-psn_}" != "x${1}" ]; then
	shift 1
fi

if command -v xset >/dev/null 2>&1 ; then
	# If xset is available, then we'll use that to silently launch the X server.
	# While we wait, use osascript to tell the user what we're up to.
	osascript -e 'display notification "Starting X server..." with title "GNU Radio Companion"' > /dev/null 2>&1 || true
	if xset q >/dev/null 2>&1 ; then
		osascript \
			-e 'on run(argv)' \
			-e 'display notification ("exec gnuradio-companion " & item 1 of argv) with title "GNU Radio Companion" subtitle "Launching GNU Radio Companion..."' \
			-e 'end run' \
			-- "$*" \
			> /dev/null 2>&1 || true
	else
		osascript -e 'display notification "Unable to verify running X server.  Will attempt anyway..." with title "GNU Radio Companion"' > /dev/null 2>&1 || true
	fi
else
	osascript \
		-e 'on run(argv)' \
		-e 'display notification ("exec gnuradio-companion " & item 1 of argv) with title "GNU Radio Companion" subtitle "Launching GNU Radio Companion..."' \
		-e 'end run' \
		-- "$*" \
		> /dev/null 2>&1 || true
fi

# Prime the exit status with "( exit 127 ) || " in case exec fails.  Otherwise,
# $? is 0 during trap EXIT.
( exit 127 ) || exec gnuradio-companion "${@}"
# Without the "trap ... EXIT", then we wouldn't need the "( exit 127 ) || ",
# since the shell would automatically return the appropriate error number from
# exec's failure.  Is this a glitch in bash since sh is symlinked to bash on my
# system?  Note that exec can return other exit status beside 127, so this
# stunt is suboptimal, but an optimally pedantic solution would require exec to
# interact better wirth trap EXIT.
