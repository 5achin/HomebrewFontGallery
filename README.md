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

## Building

Open the project in Xcode and run the `HomebrewFontGallery` scheme, or build from the command line:

```sh
xcodebuild -scheme HomebrewFontGallery build
xcodebuild -scheme HomebrewFontGallery test
```

## How it's put together

- **SwiftUI** for the whole interface.
- **`BrewService`** is the only place that runs shell commands. It wraps `brew` calls and parses their JSON output into model types, and its parsing is covered by unit tests.

## Status

Early development. The app is not scaffolded yet.
