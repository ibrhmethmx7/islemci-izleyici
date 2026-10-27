#!/bin/zsh
# Paketi derler ve build/IslemciIzleyici.app oluşturur. Xcode projesi gerekmez.
set -euo pipefail
cd "$(dirname "$0")"

NAME=IslemciIzleyici
APP="build/$NAME.app"
VERSION="${VERSION:-1.0}"

# UNIVERSAL=1: Apple Silicon + Intel için tek dosya (dağıtım için). Varsayılan: yalnızca bu Mac'in mimarisi.
ARCHS=()
[[ "${UNIVERSAL:-}" == 1 ]] && ARCHS=(--arch arm64 --arch x86_64)

swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/$NAME"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/$NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$NAME</string>
    <key>CFBundleIdentifier</key><string>local.islemci-izleyici</string>
    <key>CFBundleName</key><string>İşlemci İzleyici</string>
    <key>CFBundleDisplayName</key><string>İşlemci İzleyici</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleDevelopmentRegion</key><string>tr</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Hazır: $PWD/$APP"

# --install: ~/Applications'a kopyalar. Açılışta başlatma için kalıcı bir yer gerekir;
# build/ her derlemede silinir.
if [[ "${1:-}" == "--install" ]]; then
    DEST="$HOME/Applications/$NAME.app"
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    ditto "$APP" "$DEST"
    echo "Kuruldu: $DEST"
fi
