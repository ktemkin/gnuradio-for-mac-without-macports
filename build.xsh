#!/usr/bin/env xonsh
"""
Build scripts for creating GNURadio.app via a self-contained homebrew.
Highly experimental.
"""

import os
import sys
import pathlib
import logging
import subprocess

#
# Configuration.
#

# Path where we'll create the GNURadio application.
APP_PATH  = p"/Applications/GNURadioExperimental.app"

# Path where our internal Homebrew sysroot will live inside our application.
BREW_PATH = pf"{APP_PATH}/Contents/MacOS/"

# Flags passed to Homewbrew commands. These can be replaced with "--debug" to help debug
# building individual packages.
BREW_FLAGS = os.getenv('BREW_FLAGS', "-v")

# Controls whether we always rebuild GNURadio.
ALWAYS_REBUILD_GNURADIO = True

# Don't continue after any subprocess errors.
$RAISE_SUBPROC_ERROR = True

#
# Costmetic setup.
#

LOG_FORMAT_COLOR = "\u001b[37;1m%(levelname)-8s|\u001b[0m %(message)s"
LOG_FORMAT_PLAIN = "%(levelname)-8s:>%(message)s"

# Set up our logging / output.
if sys.stdout.isatty():
    log_format = LOG_FORMAT_COLOR
else:
    log_format = LOG_FORMAT_PLAIN

logging.basicConfig(level=logging.INFO, format=log_format)

# Announce ourselves.
logging.info("Starting GNURadio.app build.")


#
# Homebrew installation.
#

# If we haven't yet created a local copy of Homebrew, we'll create one.
# This will be an entirely-local copy of homebrew, contained inside the app.
if not pf'{BREW_PATH}'.exists():
    logging.info("Creating application folder and homebrew prefix.")

    # Create our application path; and then install Homebrew into it.
    $(mkdir -p @(BREW_PATH))
    curl -L https://github.com/Homebrew/brew/tarball/master | tar xz --strip 1 -C @(BREW_PATH)

else:
    logging.info("Using existing homebrew repository.")


# Set up our homebrew paths.
BREW=str(BREW_PATH) + "/bin/brew"

# Ensure we never grab bottles.
$HOMEBREW_SYSTEM="GNURadio"

#
# GNURadio installation.
#

# Ensure we're working from the directory this script is located in.
cd @(pathlib.Path().absolute())

# Ensure that we're restricted to libraries in our application root.
$DYLD_LIBRARY_PATH=str(BREW_PATH) + "/lib"

# If we're always rebuiling GNURadio, uninstall it first.
try:
    if ALWAYS_REBUILD_GNURADIO:
        @(BREW) uninstall gnuradio.rb
except subprocess.CalledProcessError:
    pass

# Finally, build and install GNURadio.
logging.info("Building and installing core GNURadio.")
@(BREW) install @(BREW_FLAGS) gnuradio.rb -s


#
# Application preparations.
#

logging.warn(".app logic not yet implemented!")
