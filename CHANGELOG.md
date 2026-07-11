# Changelog

## 1.2.0 (2026-07-11)

- Localized into Turkish, German, French, Spanish, Japanese and Simplified
  Chinese (string catalogs under `Localization/`, contributions welcome)
- In-app language picker in Settings, General (or use the macOS per-app
  language setting)

## 1.1.1 (2026-07-11)

- Background removal reworked as a hybrid: flat backgrounds (logos, screenshots,
  graphics) use a pixel-exact flood fill with color decontamination and speck
  cleanup; photographic subjects keep using Apple's Vision model
- Fixed white fringe on extracted edges

## 1.1.0 (2026-07-11)

- Background removal (right-click): subject extraction to a transparent sibling
  PNG, automatically optimized afterwards
- Click-to-sort on all table columns (state, name, original size, savings
  percentage, status)
- Status bar shows resolution and a clickable reveal-in-Finder path for the
  selected file; count and total size for multi-selection
- Settings hint only shows for an empty list; a finished list without savings
  reports "Already optimized"
- Releases are built on the macos-26 runner so the app links against the
  macOS 26 SDK (restores the current system appearance)

## 1.0.1 (2026-07-11)

- New app icon from designed artwork (photo frame and feather)
- Table columns fit the default window: no premature horizontal scrollbar
- Column widths and order persist across launches

## 1.0.0 (2026-07-11)

- First release: in-place optimization for PNG, JPEG, GIF, SVG and WebP with
  bundled engines (oxipng, pngquant, MozJPEG, jpegoptim, gifsicle, libwebp)
- Lossy and lossless modes, quality sliders, four optimization levels
- Convert to WebP, HEIC and AVIF; resize on optimize; Trash and sidecar backups
  with session-wide revert
- `hafif` CLI, Finder Services entry, drag and drop, Sparkle auto-updates
