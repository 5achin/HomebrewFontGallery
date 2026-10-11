#!/bin/bash
# Rewrites the list of fonts the widget chooses from each day, in
# HomebrewFontGalleryWidget/WidgetFonts.json, from the fonts Homebrew offers today.
#
#   scripts/update-widget-fonts.sh
#
# It builds the app, then has the app ask Homebrew for its fonts and keep the
# ones whose font file downloads by itself. Commit the changed file afterwards,
# and run scripts/build.sh to put it in the app.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Homebrew Fonts Gallery"
OUT="$PWD/HomebrewFontGalleryWidget/WidgetFonts.json"

scripts/build.sh
"build/Release/$APP_NAME.app/Contents/MacOS/$APP_NAME" --export-widget-fonts "$OUT"
echo "Updated $OUT"
