# Third-Party Software

HafifPix bundles the following open-source tools and libraries. Each remains
under its own license; full texts are available at the linked projects.

## Optimization engines (separate executables in `Contents/Resources/bin`)

| Tool | License | Source |
|------|---------|--------|
| pngquant | GPLv3 (or commercial) | https://pngquant.org |
| oxipng | MIT | https://github.com/oxipng/oxipng |
| MozJPEG (jpegtran) | BSD-3-Clause / IJG | https://github.com/mozilla/mozjpeg |
| jpegoptim | GPLv3 | https://github.com/tjko/jpegoptim |
| Gifsicle | GPLv2 | https://www.lcdf.org/gifsicle |
| libwebp (cwebp, gif2webp) | BSD-3-Clause | https://chromium.googlesource.com/webm/libwebp |

## Bundled libraries (`Contents/Frameworks`)

| Library | License |
|---------|---------|
| Sparkle (updates) | MIT (https://sparkle-project.org) |
| libpng | libpng/zlib |
| libjpeg-turbo | BSD / IJG / zlib |
| Little-CMS 2 | MIT |
| libtiff | libtiff (MIT-like) |
| giflib | MIT |
| zstd | BSD |
| xz (liblzma) | 0BSD |

Because GPL-licensed engines are distributed inside the app bundle, HafifPix
itself is distributed under the GNU GPL v3 (see LICENSE). The engines run as
separate processes; their sources are unmodified and available at the links
above.

HafifPix is a from-scratch rebuild inspired by [ImageOptim](https://imageoptim.com)
by Kornel Lesiński (GPL), whose UI concept and engine-racing approach it follows.
