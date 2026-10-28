# Third-party software

ImageSqueeze's own source code is MIT-licensed (see `LICENSE`). The packaged app
(`ImageSqueeze.app`) additionally ships the following independent programs and
libraries, unmodified, built by Homebrew. They run as separate processes or are
loaded as separate libraries, and each remains under its own license.

| Component | Version | License | Source |
|---|---|---|---|
| MozJPEG (`cjpeg`, `jpegtran`, `libjpeg`) | 4.1.5 | IJG AND Zlib AND BSD-3-Clause | https://github.com/mozilla/mozjpeg |
| pngquant | 3.0.3 | GPL-3.0-or-later AND HPND AND BSD-2-Clause | https://github.com/kornelski/pngquant |
| OxiPNG | 10.2.1 | MIT | https://github.com/oxipng/oxipng |
| pngcrush | 1.8.13 | pngcrush license (zlib-style) | https://pmt.sourceforge.io/pngcrush/ |
| libwebp (`cwebp`, `libwebp`, `libwebpdemux`, `libsharpyuv`) | 1.6.0 | BSD-3-Clause | https://chromium.googlesource.com/webm/libwebp |
| Gifsicle | 1.98 | GPL-2.0-only | https://github.com/kohler/gifsicle |
| SVGO (bundled as `svgo.js`) | 4.1.0 | MIT | https://github.com/svg/svgo |
| libpng | 1.6.59 | libpng-2.0 | https://www.libpng.org/pub/png/libpng.html |
| Little CMS | 2.19.1 | MIT | https://www.littlecms.com/ |
| libjpeg-turbo (used by `cwebp`) | 3.2.0 | IJG AND Zlib AND BSD-3-Clause | https://github.com/libjpeg-turbo/libjpeg-turbo |

pngquant and Gifsicle are distributed under the GNU GPL. Their complete
corresponding source code is available at the links above, for the exact
versions listed. ImageSqueeze invokes them as separate command-line programs.

AVIF, HEIC and TIFF encoding uses Apple's ImageIO framework, part of macOS.
