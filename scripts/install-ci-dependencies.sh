#!/usr/bin/env bash

set -e

brew uninstall parallel  # conflicts with moreutils

brew install moreutils
brew install wget

brew cask install xquartz

PYTHON_VERSION="python-3.7.7-macosx10.9.pkg"

wget "https://www.python.org/ftp/python/3.7.7/$PYTHON_VERSION"

sudo installer -pkg "$PYTHON_VERSION" -target /

# Works around an issue with the submodule defined in the bladeRF repository;
# git fails to fetch it with a trailing slash but works fine without it.
git config --global url."https://github.com/analogdevicesinc/no-OS".insteadOf "https://github.com/analogdevicesinc/no-OS/"
