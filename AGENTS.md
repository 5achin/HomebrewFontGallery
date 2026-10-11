# Homebrew Font Gallery: notes for agents

Sachin's rules for every Mac app live in `~/Developer/AGENTS.md` on his Mac, with
[DiskFlasher](https://github.com/5achin/DiskFlasher) as the reference
implementation. Read that file first. This one records how those rules apply to
this app, and the few places where it differs.

## What the app is

A native SwiftUI app that lists Homebrew `font-*` casks, previews them, and
installs or uninstalls them by running `brew`. It never edits `~/Library/Fonts`
directly: Homebrew owns every install and uninstall.

## Workflow

- Work on `main` and push to `main`. Open a pull request only when Sachin asks.
- Several sessions may share the checkout in `~/Developer/HomebrewFontGallery`.
  Stage only the files you changed, by name, and don't switch branches, stash,
  reset or create worktrees there.
- Keep each feature in its own commit so it is easy to take out.
- Run `scripts/build.sh --test` after every code change and before saying a
  change is ready. Sachin tests the copy in `build/Release`.
- Launch the rebuilt app and check the change yourself. Show UI changes with a
  window screenshot that keeps the shadow (`screencapture -l <windowID>`, no
  `-o`). README screenshots use the same style and live in `docs/`.
- The cloud can't build macOS apps. Builds, tests and screenshots run on
  Sachin's Mac.

## Xcode project

- Scheme `HomebrewFontGallery`, signing "Sign to Run Locally" (no team), and a
  unit test target. CI and `scripts/build.sh` depend on all three.
- Deployment target: macOS 14.
- App Sandbox off, because the app runs `/opt/homebrew/bin/brew` (or
  `/usr/local/bin/brew`), which writes outside any sandbox container. Hardened
  Runtime on.
- App icon: a layered `AppIcon.icon` made in Icon Composer. Flat vector glyph in
  two or three layers on a gradient. No baked-in glass, shadow or mask, and
  nothing 3D or illustrative. Show it at the top of the README.

## Running brew

- `BrewService` is the only type that runs external commands. It launches `brew`
  directly with `Process`: no shell, no wrapper script, no AppleScript.
- Font casks install into `~/Library/Fonts` and need no administrator rights. Never
  use `osascript ... with administrator privileges`.
- Parse `brew` output in pure functions and cover them with unit tests, using
  captured `brew` JSON as fixtures.
- Log every command, its exit status and its error output to
  `~/Library/Logs/HomebrewFontGallery/HomebrewFontGallery.log`, rotated at about
  1 MB (copy DiskFlasher's `RunLog.swift`). Add **Help > Show Logs in Finder**.
  Read the log first when Sachin reports a failure.
- Show errors to the user in plain words with a next step. Raw `brew` output
  goes in the log, never in the main window.

## Design

Follow the Design section of `~/Developer/AGENTS.md` and Apple's Human Interface
Guidelines: system controls, colours, fonts and spacing only, and no visible
`brew` commands in the interface. Points specific to this app:

- One `Window` scene, titled "Homebrew Font Gallery", that quits when closed.
  Unlike DiskFlasher, a gallery of hundreds of fonts needs a resizable window
  and a scrolling list, so the size-to-content rule doesn't apply to the font
  list. Sheets, settings and detail panes still follow it.
- Search with `.searchable`. Filters for installed and not-installed fonts use a
  standard control, not custom chips.
- The cask list loads by itself on launch. No refresh button.
- Install and uninstall are the primary action in the toolbar for the selected
  font, titled with an SF Symbol and disabled while `brew` is busy. While it runs,
  the same toolbar item becomes Cancel.
- Uninstalling is destructive: confirm with a `confirmationDialog` that names
  the font ("Uninstall “Fira Code”?"), with an **Uninstall** button in the
  destructive role and **Cancel**. Re-check that the cask is still installed
  before running it.
- Status and progress appear inline (a coloured SF Symbol, a title and a
  message), not in alerts.
- Use the user's words: "Font", "Installed", not "cask" or "formula", except as
  secondary detail. Title Case for buttons, menus and row titles; sentence case
  with a full stop for messages; "…" and curly quotes in interface text.
- Sample text, size and similar preview settings persist with `@AppStorage`.
