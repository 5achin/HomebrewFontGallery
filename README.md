# Homebrew Font Gallery
Native macOS SwiftUI gallery for browsing, previewing and installing Homebrew font casks

## What it does

- Lists every `font-*` cask Homebrew knows about, with search and filters for installed and not-installed fonts.
- Renders a live preview of each font with your own sample text, size and weight.
- Installs and uninstalls fonts with one click by running `brew install --cask` and `brew uninstall --cask`.
- Shows cask details (version, homepage, description) from `brew info --json`.

The app never touches `~/Library/Fonts` directly. Homebrew owns every install and uninstall, so `brew list` always matches what the app shows.

## Requirements

- macOS 14 Sonoma or later
- [Homebrew](https://brew.sh) installed at `/opt/homebrew` or `/usr/local`
- A recent Xcode to build

## Install

1. Download the latest `HomebrewFontGallery-….zip` from the [Releases page](https://github.com/5achin/HomebrewFontGallery/releases/latest).
2. Unzip it and drag **HomebrewFontGallery** into your Applications folder.
3. Open it.

### The first time you open it

Homebrew Font Gallery is not signed with an Apple Developer ID, so macOS blocks it the first time with a message that it could not be verified. To allow it:

1. Try to open the app once, then dismiss the warning.
2. Open **System Settings › Privacy & Security**.
3. Scroll down to the message about HomebrewFontGallery and click **Open Anyway**.
4. Confirm with your password or Touch ID.

You only need to do this once.

## Building from source

```bash
git clone https://github.com/5achin/HomebrewFontGallery.git
cd HomebrewFontGallery
scripts/build.sh --open
```

The app is written to `build/Release/HomebrewFontGallery.app`. Add `--test` to run the unit tests first, and `--zip` to also produce `build/Release/HomebrewFontGallery.zip`. You can also open `HomebrewFontGallery.xcodeproj` in Xcode and press Run.

Every push to `main` runs the tests, builds the app with GitHub Actions and publishes it as a new release. Pushing a tag like `v1.0` publishes a release under that tag instead.

## How it's put together

- **SwiftUI** for the whole interface.
- **`BrewService`** is the only place that runs shell commands. It wraps `brew` calls and parses their JSON output into model types, and its parsing is covered by unit tests.

## Status

Early development. The app is not scaffolded yet.
