# HafifPix

*hafif* (Turkish: lightweight) + *pix*. A native macOS image optimizer, built as a modern
Swift 6 / SwiftUI successor to [ImageOptim](https://imageoptim.com). Apple Silicon only.

Drop images or folders on the window and they are compressed **in place**: losslessly by
default, or lossy at your chosen quality. Files are never made larger and never corrupted.

## Features

- **Formats**: PNG, JPEG, GIF (incl. animated), SVG, WebP
- **Keep-smallest engine racing**: every optimizer pass is adopted only if the result is
  smaller *and* still decodes with identical dimensions and frame count
- **Modern engines**: oxipng (replaces OptiPNG/PNGCrush/AdvPNG/Zopfli), pngquant,
  MozJPEG, jpegoptim, gifsicle and cwebp, all bundled inside the app with no dependencies
- **Convert to modern formats**: WebP / HEIC / AVIF, written as sibling files.
  Animated GIF becomes animated WebP
- **Resize on optimize**: fit images within a max dimension before compression
- **Background removal**: extract the subject to a transparent PNG (right-click),
  powered by Apple's on-device Vision model; the result is optimized automatically
- **Safety**: atomic same-volume swaps, optional Trash or sidecar backups and per-file
  *Revert to Original* for the whole session regardless of backup setting
- **`hafif` CLI** for scripts and CI, sharing the app's engine and settings
- **Finder integration**: Open With, Services menu ("Optimize with HafifPix"), dock drops

## Build

Requires Xcode (CLI tools) and Homebrew-installed engines:

```sh
brew install oxipng pngquant mozjpeg jpegoptim gifsicle webp
make app          # builds dist/HafifPix.app (self-contained)
make run          # build + open
make install      # copy to /Applications
make install-cli  # symlink hafif into /usr/local/bin
make test         # unit tests
```

The bundling script copies the engine binaries and their dylibs into the app and
re-links them, so the built app runs on Macs without Homebrew.

## CLI

```sh
hafif ~/Desktop/screenshots            # optimize a folder in place
hafif --lossless photo.png             # never change pixels
hafif --quality 70 --level insane .    # crunch hard
hafif --convert webp --resize 2048 img.png
hafif --backup trash *.jpg             # originals go to Trash
```

## Architecture

```
Sources/
  HafifPixCore/          # engine library (no UI)
    Models/              # formats (magic-byte sniffing), settings, job states
    Engine/              # actor job queue, per-format chains, process runner,
                         # ImageIO codec, native SVG minifier, convert pipeline
    Safety/              # atomic replacement, backups, session revert cache
  HafifPixApp/           # SwiftUI app (drop zone, live table, settings)
  hafif/                 # CLI
```

Optimization chains. Each step's output is kept only if smaller and valid:

| Format | Chain |
|--------|-------|
| PNG    | pngquant (lossy), then oxipng (Zopfli at Insane) |
| JPEG   | jpegli* (lossy), then jpegoptim, then MozJPEG jpegtran |
| GIF    | gifsicle (per-level optimization, optional lossy) |
| SVG    | built-in minifier (comments, editor metadata, whitespace) |
| WebP   | cwebp re-encode (lossless sources stay lossless) |

\* jpegli is picked up automatically if a `cjpegli` binary is on the system.
Homebrew doesn't ship one today.

## License

GPL v3, see [LICENSE](LICENSE). HafifPix bundles GPL-licensed engines
(pngquant, gifsicle, jpegoptim), which makes GPL the natural license for the
distributed bundle. See [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)
for all attributions. Inspired by [ImageOptim](https://imageoptim.com) (GPL).
