#!/bin/zsh
# Dağıtım için universal .app derler ve dist/IslemciIzleyici-<sürüm>.zip üretir.
# Kullanım: ./release.sh 1.0
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?Sürüm verin, örn. ./release.sh 1.0}"
VERSION="$VERSION" UNIVERSAL=1 ./build-app.sh

mkdir -p dist
ZIP="dist/IslemciIzleyici-$VERSION.zip"
rm -f "$ZIP"
# ditto, imzayı ve paket yapısını bozmadan sıkıştırır (zip -r bozabilir).
ditto -c -k --keepParent build/IslemciIzleyici.app "$ZIP"
echo "Hazır: $PWD/$ZIP"
