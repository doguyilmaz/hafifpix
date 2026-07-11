#!/bin/bash
# Assembles dist/HafifPix.app: app binary + CLI + optimizer engines with their
# dylibs re-linked into the bundle, then ad-hoc codesigned. Apple Silicon only.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)
APP="$ROOT/dist/HafifPix.app"
CONTENTS="$APP/Contents"
BIN_DIR="$CONTENTS/Resources/bin"
FW_DIR="$CONTENTS/Frameworks"

# "-" = ad-hoc (local use). For distribution:
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" make app
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SIGN_FLAGS=()
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    SIGN_FLAGS=(--options runtime --timestamp)
fi

TOOLS=(
    /opt/homebrew/bin/pngquant
    /opt/homebrew/bin/oxipng
    /opt/homebrew/bin/jpegoptim
    /opt/homebrew/opt/mozjpeg/bin/jpegtran
    /opt/homebrew/bin/gifsicle
    /opt/homebrew/bin/cwebp
    /opt/homebrew/bin/gif2webp
)
# Optional: bundled only if present (not in homebrew-core today).
OPTIONAL_TOOLS=(/opt/homebrew/bin/cjpegli)

echo "==> Building release binaries"
swift build -c release --product HafifPixApp
swift build -c release --product hafif

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$BIN_DIR" "$FW_DIR"

cp .build/release/HafifPixApp "$CONTENTS/MacOS/HafifPix"
cp .build/release/hafif "$BIN_DIR/hafif"
cp Resources/Info.plist "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

if [[ ! -f Resources/AppIcon.icns ]]; then
    echo "==> Generating icon"
    swift scripts/make-icon-from-art.swift Resources/icon-art.png "$ROOT/.build/AppIcon.iconset"
    iconutil -c icns "$ROOT/.build/AppIcon.iconset" -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"
cp LICENSE THIRD_PARTY_LICENSES.md "$CONTENTS/Resources/"

echo "==> Embedding Sparkle"
SPARKLE_FW=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$SPARKLE_FW" ]]; then
    echo "ERROR: Sparkle artifact missing — run 'swift build' first" >&2
    exit 1
fi
ditto "$SPARKLE_FW" "$FW_DIR/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$CONTENTS/MacOS/HafifPix" 2>/dev/null || true

# --- Dylib bundling -----------------------------------------------------
# Copies every non-system dylib a binary needs into Contents/Frameworks and
# rewrites load commands. Tools live in Resources/bin, so their deps resolve
# via @executable_path/../../Frameworks; dylib-to-dylib deps via @loader_path.
# Deps of copied dylibs are resolved against the dylib's ORIGINAL location,
# where @loader_path / @rpath still mean something.

rpaths_of() {
    otool -l "$1" | awk '/LC_RPATH/{f=3} f&&/path /{print $2; f=0}'
}

nonsystem_deps() {
    otool -L "$1" | tail -n +2 | awk '{print $1}' \
        | grep -vE '^(/usr/lib|/System)' || true
}

resolve_dep() { # dep-string, context-binary -> absolute path (or empty)
    local dep="$1" binary="$2"
    case "$dep" in
        @rpath/*)
            local rel="${dep#@rpath/}"
            while IFS= read -r rp; do
                rp="${rp/@loader_path/$(dirname "$binary")}"
                if [[ -f "$rp/$rel" ]]; then echo "$rp/$rel"; return; fi
            done < <(rpaths_of "$binary")
            ;;
        @loader_path/*)
            local candidate="$(dirname "$binary")/${dep#@loader_path/}"
            [[ -f "$candidate" ]] && echo "$candidate"
            ;;
        /*)
            [[ -f "$dep" ]] && echo "$dep"
            ;;
    esac
    return 0
}

# name -> original source path, for resolving transitive deps.
# (file-based map: macOS ships bash 3.2, which lacks associative arrays)
MAP_DIR=$(mktemp -d)
trap 'rm -rf "$MAP_DIR"' EXIT
set_source() { echo "$2" > "$MAP_DIR/$1"; }
get_source() { cat "$MAP_DIR/$1"; }
PENDING=()

rewrite_deps() { # binary-to-rewrite, resolve-context-binary, new-prefix
    local target="$1" context="$2" prefix="$3"
    while IFS= read -r dep; do
        [[ -z "$dep" ]] && continue
        [[ "$(basename "$dep")" == "$(basename "$target")" ]] && continue
        local resolved
        resolved=$(resolve_dep "$dep" "$context")
        if [[ -z "$resolved" ]]; then
            echo "    WARNING: cannot resolve $dep (needed by $(basename "$target"))"
            continue
        fi
        local name
        name=$(basename "$resolved")
        if [[ ! -f "$FW_DIR/$name" ]]; then
            cp -L "$resolved" "$FW_DIR/$name"
            chmod u+w "$FW_DIR/$name"
            set_source "$name" "$resolved"
            PENDING+=("$name")
        fi
        install_name_tool -change "$dep" "$prefix/$name" "$target" 2>/dev/null
    done < <(nonsystem_deps "$target")
}

echo "==> Bundling engines"
for tool in "${TOOLS[@]}" "${OPTIONAL_TOOLS[@]}"; do
    if [[ ! -x "$tool" ]]; then
        if [[ " ${OPTIONAL_TOOLS[*]} " == *" $tool "* ]]; then
            echo "    (skipping optional $(basename "$tool") — not installed)"
            continue
        fi
        echo "ERROR: required tool missing: $tool (brew install it first)" >&2
        exit 1
    fi
    name=$(basename "$tool")
    cp -L "$tool" "$BIN_DIR/$name"
    chmod u+w "$BIN_DIR/$name"
    echo "    $name"
    rewrite_deps "$BIN_DIR/$name" "$(realpath "$tool")" "@executable_path/../../Frameworks"
done

# Transitive dylib deps until fixpoint.
while ((${#PENDING[@]} > 0)); do
    QUEUE=("${PENDING[@]}")
    PENDING=()
    for name in "${QUEUE[@]}"; do
        copy="$FW_DIR/$name"
        install_name_tool -id "@loader_path/$name" "$copy" 2>/dev/null
        rewrite_deps "$copy" "$(get_source "$name")" "@loader_path"
    done
done

echo "==> Code signing ($SIGN_IDENTITY)"
sign() { codesign --force --sign "$SIGN_IDENTITY" ${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"} "$@"; }

# Sparkle: nested executables first, then the framework (per Sparkle docs).
SPARKLE_B="$FW_DIR/Sparkle.framework/Versions/B"
sign "$SPARKLE_B/XPCServices/Downloader.xpc" 2>/dev/null || true
sign "$SPARKLE_B/XPCServices/Installer.xpc"
sign "$SPARKLE_B/Autoupdate"
sign "$SPARKLE_B/Updater.app"
sign "$FW_DIR/Sparkle.framework"

while IFS= read -r -d '' dylib; do
    sign "$dylib"
done < <(find "$FW_DIR" -name '*.dylib' -print0)
while IFS= read -r -d '' bin; do
    sign "$bin"
done < <(find "$BIN_DIR" -type f -print0)
sign "$CONTENTS/MacOS/HafifPix"
sign "$APP"

echo "==> Verifying bundled engines run"
for tool in "$BIN_DIR"/*; do
    name=$(basename "$tool")
    [[ "$name" == "hafif" ]] && continue
    if ! "$tool" --version >/dev/null 2>&1 && ! "$tool" -version >/dev/null 2>&1 && ! "$tool" --help >/dev/null 2>&1; then
        echo "ERROR: bundled $name failed to execute" >&2
        exit 1
    fi
done

echo "==> Done: $APP"
