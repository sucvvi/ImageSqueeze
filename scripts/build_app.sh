#!/bin/zsh
# Builds dist/ImageSqueeze.app: compiles the SwiftUI app, bundles the compression engines
# (with their dylibs rewritten to load from inside the app), SVGO, the icon, and ad-hoc signs it.
# Requires: Xcode, Homebrew packages: oxipng pngquant mozjpeg webp gifsicle pngcrush dylibbundler; node (for svgo bundle).
set -euo pipefail
cd "${0:A:h}/.."
ROOT=$PWD
# Assemble and sign outside the project: iCloud-synced folders add Finder info that breaks codesign.
STAGE=$(mktemp -d)
APP="$STAGE/ImageSqueeze.app"
BUILD="$STAGE/build"
DEST="$ROOT/dist/ImageSqueeze.app"

echo "==> 编译"
swift build -c release
BIN=$(swift build -c release --show-bin-path)/ImageSqueeze

echo "==> 组装 .app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin" "$APP/Contents/Frameworks" "$BUILD"
cp "$BIN" "$APP/Contents/MacOS/ImageSqueeze"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp -R "$ROOT"/Resources/*.lproj "$APP/Contents/Resources/"
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"

echo "==> SVGO"
if [[ ! -f "$ROOT/vendor/svgo/svgo.js" ]]; then
  (cd "$ROOT/vendor/svgo" && npm i --silent && npx esbuild entry.js --bundle --format=iife --platform=browser --minify --target=safari15 --outfile=svgo.js)
fi
cp "$ROOT/vendor/svgo/svgo.js" "$APP/Contents/Resources/svgo.js"

echo "==> 压缩引擎"
HB=$(brew --prefix)
for t in "$HB/opt/mozjpeg/bin/cjpeg" "$HB/opt/mozjpeg/bin/jpegtran" "$HB/bin/pngquant" "$HB/bin/oxipng" \
         "$HB/bin/pngcrush" "$HB/bin/cwebp" "$HB/bin/gifsicle"; do
  cp -L "$t" "$APP/Contents/Resources/bin/"
  chmod u+w "$APP/Contents/Resources/bin/${t:t}"
done
ARGS=()
for f in "$APP"/Contents/Resources/bin/*; do ARGS+=(-x "$f"); done
dylibbundler -of -b "${ARGS[@]}" -d "$APP/Contents/Frameworks" -p @executable_path/../../Frameworks/ \
  -s "$HB/opt/mozjpeg/lib" -s "$HB/opt/webp/lib" -s "$HB/lib" >/dev/null

echo "==> 图标"
swift "$ROOT/scripts/make_icon.swift" "$BUILD/icon.png"
ICONSET="$BUILD/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$BUILD/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$BUILD/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> 签名"
xattr -cr "$APP"
for f in "$APP"/Contents/Frameworks/*.dylib "$APP"/Contents/Resources/bin/*; do
  codesign --force --sign - "$f" 2>/dev/null
done
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"

rm -rf "$DEST"
mkdir -p "${DEST:h}"
ditto "$APP" "$DEST"
rm -rf "$STAGE"
echo "==> 完成：$DEST"
