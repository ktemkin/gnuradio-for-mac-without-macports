# GNURadio.app

This project is here to simplify installation of [GNURadio](http://gnuradio.org/) for Mac OS X. 

## Requirements

We only have two requirements that you need to install first

<a href="https://www.python.org/downloads/" target="_blank"><img src="https://www.python.org/static/img/python-logo.png" /></a>
<a href="https://www.xquartz.org/" target="_blank"><img src="https://www.xquartz.org/Xlogo.png" /></a>

## Installation

Following Apple conventions, installation is easy.

Simply [download a release](https://github.com/cfriedt/gnuradio-for-mac-without-macports/releases), open the DMG file, and then drag & drop GNURadio into your Applications directory.

<a href="https://github.com/cfriedt/gnuradio-for-mac-without-macports/releases" target="_blank"><img src="https://raw.githubusercontent.com/cfriedt/gnuradio-for-mac-without-macports/master/screenshot.png" /></a>

## Motivation

Some users just do not want to install [MacPorts](https://www.macports.org) just to use GNURadio. We get it. To each their own.

## Getting Started

After you have installed GNURadio, check out the [Tutorials](http://gnuradio.org/redmine/projects/gnuradio/wiki/Tutorials).

Once you are confident with using some basic blocks, and if you don't already have an [SDR](https://en.wikipedia.org/wiki/Software-defined_radio) you might want to consider purchasing one. [RTL-SDR](http://www.rtl-sdr.com/) has a good [roundup of SDR devices](http://www.rtl-sdr.com/roundup-software-defined-radios/).

## Advanced Usage: Out of Tree Modules

There are only a few extra steps to use before following [Out of Tree Module Guide](http://gnuradio.org/redmine/projects/gnuradio/wiki/OutOfTreeModules).

TODO: write #exactsteps [Issue #9](https://github.com/cfriedt/gnuradio-for-mac-without-macports/issues/9)

## DIY

For those who desperately want to build GNURadio for Mac from scratch using our method, you will only need two requirements listed above and to run [build.sh](https://github.com/cfriedt/gnuradio-for-mac-without-macports/blob/master/build.sh).

TODO: #exactsteps for building DIY [Issue #10](https://github.com/cfriedt/gnuradio-for-mac-without-macports/issues/10)

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
