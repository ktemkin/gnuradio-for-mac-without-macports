# GNURadio.app

This project is here to simplify installation of [GNURadio](http://gnuradio.org/) for Mac OS X; and provides a standalone
application that's intended to be usable on modern MacOS systems and a variety of common SDR hardware. This branch provides
GNURadio v3.8, which is configured to run on top of Python3, and with GTK3 and Qt5 for UI.

Note that this version contains some major changes from GNURadio 3.7: the WX UI has been removed following its deprecation;
and, per the end-of-life of Python 2.x, we now are intended to run off of GNURadio 3.8.

Built with backend support for:

* Airspy (via osmosdr and soapy)
* AirspyHF (via soapy)
* BladeRF (via osmosdr and soapy; bitstreams included)
* HackRF (via osmosdr and soapy)
* LimeSDR (via gr-limesdr and soapy)
* NetSDR (via soapy)
* Pluto SDR (via soapy)
* Red Pitaya (via osmosdr and soapy)
* RTLSDR (via osmosdr and soapy)
* UHD/USRP (via osmosdr and soapy)

Currently tested platforms include:

* BladeRF
* HackRF
* LimeSDR
* RTLSDR
* UHD


If you've successfully tested one of the other backends, feel free to PR an addition to this list. :)


## Requirements

This distribution is meant to run on modern versions of macOS; technically, it should support releases as old as 10.7;
but this is untested. It should support modern processor features (e.g. AVX512), but shouldn't require them.

There are two software requirements you'll need to install first:

<a href="https://www.python.org/downloads/" target="_blank"><img src="https://www.python.org/static/img/python-logo.png" /></a>
<a href="https://www.xquartz.org/" target="_blank"><img src="https://www.xquartz.org/Xlogo.png" /></a>

You must install Python 3.7 using the python.org installer; GNURadio.app can't use the version installed with macOS (or MacPorts or Homebrew).



## Installation

Following Apple conventions, installation is easy.

Simply [download a release](https://github.com/ktemkin/gnuradio-for-mac-without-macports/releases), open the DMG file, and then drag & drop GNURadio into your Applications directory.

<a href="https://github.com/cfriedt/gnuradio-for-mac-without-macports/releases" target="_blank"><img src="https://raw.githubusercontent.com/ktemkin/gnuradio-for-mac-without-macports/master/screenshot.png" /></a>

## Additional steps for specific platforms

### UHD

You'll need to download the USRP firmware images with the `uhd_images_downloader.py` tool.

```bash
$ /Library/Frameworks/Python.framework/Versions/3.7/bin/pip install six requests
$ /Applications/GNURadio.app/Contents/MacOS/usr/lib/uhd/utils/uhd_images_downloader.py
```

### Trackpad users

If you're using a trackpad you'll need a way to emulate a middle-click, especially for configuring the GUI blocks. One such tool is [MiddleClick](https://github.com/DaFuqtor/MiddleClick-Catalina).


## Motivation

Some users just do not want to install [MacPorts](https://www.macports.org) only to use GNURadio. We get it. To each their own.



## Getting Started

After you have installed GNURadio, check out the [Tutorials](https://wiki.gnuradio.org/index.php/Tutorials).

Once you are confident with using some basic blocks, and if you don't already have an [SDR](https://en.wikipedia.org/wiki/Software-defined_radio) you might want to consider purchasing one. [RTL-SDR](http://www.rtl-sdr.com/) has a good [roundup of SDR devices](http://www.rtl-sdr.com/roundup-software-defined-radios/).



## Advanced Usage: Out of Tree Modules

There are only a few extra steps to use before following [Out of Tree Module Guide](https://wiki.gnuradio.org/index.php/OutOfTreeModules).

TODO: write #exactsteps [Issue #9](https://github.com/cfriedt/gnuradio-for-mac-without-macports/issues/9)



## DIY

For those who desperately want to build GNURadio for Mac from scratch using our method, you will only need two requirements listed above and to run [build.sh](https://github.com/cfriedt/gnuradio-for-mac-without-macports/blob/master/build.sh).

Keep in mind, that building most dependencies from scratch will take some amount of time, but it should work without any errors.

If you encounter any errors, or if there is a particular runtime bug or feature that you would like to see, please create a new [Issue](https://github.com/cfriedt/gnuradio-for-mac-without-macports/issues).

Pull Requests are welcome!



## License

Our shell script is released under the same [LICENSE](https://github.com/cfriedt/gnuradio-for-mac-without-macports/blob/master/LICENSE) that GNURadio is released under, namely the [GPLv3](https://raw.githubusercontent.com/cfriedt/gnuradio-for-mac-without-macports/master/LICENSE).

GNURadio graphics are freely available under the [CC BY-ND 2.0 license](https://creativecommons.org/licenses/by-nd/2.0/)<sup><a href="#1">1</a></sup>

<div class="footnote"><p>
<small>
<sup><a href="#1">1</a></sup>
Note, we have not transformed <a href="https://github.com/gnuradio/gr-logo/blob/master/gnuradio_logo_icon-square.svg">gnuradio_logo_icon-square.svg</a> when building <a href="https://github.com/cfriedt/gnuradio-for-mac-without-macports/blob/master/gnuradio.icns">gnuradio.icns</a>. It is identical to the original graphic in every way, sampled at various resolutions. See <a href="http://applehelpwriter.com/2012/12/16/make-your-own-icns-icons-for-free/">here</a> for the #exactsteps followed. Also note that <a href="https://github.com/cfriedt/gnuradio-for-mac-without-macports/issues/8">Issue #8</a> exists to simplify that process.
</small>
</div>
