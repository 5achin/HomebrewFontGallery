#!/bin/bash
# Redraws the thumbnails that ship inside the app, in
# HomebrewFontGallery/Thumbnails.bundle, from the fonts Homebrew offers today.
#
#   scripts/update-thumbnails.sh
#
# It builds the app, then has the app draw every thumbnail the way it does
# while you scroll: each font is downloaded, drawn and deleted. Expect it to
# take several minutes and to download a gigabyte or two. Commit the changed
# pictures afterwards, and run scripts/build.sh to put them in the app.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Homebrew Fonts Gallery"
OUT="$PWD/HomebrewFontGallery/Thumbnails.bundle"

scripts/build.sh
"build/Release/$APP_NAME.app/Contents/MacOS/$APP_NAME" --export-thumbnails "$OUT"
echo "Updated $OUT"
