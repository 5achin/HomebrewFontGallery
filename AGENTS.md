# Homebrew Fonts Gallery: notes for agents

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

## Performance

- The grid is an `NSCollectionView` (`FontCollection.swift`), not a SwiftUI
  `LazyVGrid`. Profiling showed the lazy grid walking its list from the first
  font to the visible ones on every layout pass, about 100 ms a time. Don't
  move it back to SwiftUI.
- The grid watches `GalleryModel` itself with `withObservationTracking`, so it
  doesn't depend on SwiftUI calling `updateNSView`.
- The details pane shows and hides without animation, and the window is resized
  in the same turn (`ContentView.resizeWindow`). Sliding the pane re-laid out
  the window on every frame.
- To profile, run `sample "Homebrew Fonts Gallery" 5 1 -file out.txt` while
  resizing the window or toggling the pane, and read the main thread's tree.

## Thumbnails

- The grid's thumbnails ship inside the app, in `HomebrewFontGallery/Thumbnails.bundle`,
  one PNG per font named by its Homebrew token. The app only draws a thumbnail
  itself for a font that isn't in that folder.
- Run `scripts/update-thumbnails.sh` to redraw them, then commit the changed
  pictures. Do it after changing how a thumbnail is drawn or its size, and now
  and then to pick up fonts Homebrew has added.

## Widget

- `HomebrewFontGalleryWidget` is a WidgetKit extension embedded in the app: one
  widget, "Font Gallery", in four sizes. It is sandboxed, as macOS requires of
  a widget, with outgoing network access and nothing else.
- App Groups don't work here. With "Sign to Run Locally" macOS creates the group
  folder but refuses the widget access to it, so the app can't hand the widget
  files. Don't add an App Group or a sandbox exception; it needs a signing team.
- So the widget looks after itself. The fonts it may choose from ship inside it
  as `HomebrewFontGalleryWidget/WidgetFonts.json`. Run
  `scripts/update-widget-fonts.sh` to rewrite that from Homebrew, then commit it.
- `Shared/DailyFonts.swift` belongs to both the app and the widget, so the unit
  tests can reach it. It picks the day's fonts from the date alone, so every
  redraw of the day shows the same set.
- `Shared/FontPairing.swift` chooses which fonts the extra large widget shows
  together. Its header lists the rules it follows: a paragraph needs a plain
  sans or serif of ordinary weight, width and x-height; pair by contrast (serif
  with sans, or an expressive heading over plain text); prefer pairs whose
  lowercase is about the same height and width; code takes the monospaced font
  nearest the paragraph's x-height. Each font's kind comes from Google Fonts'
  category, which `scripts/update-widget-fonts.sh` writes into the list, and
  its proportions are measured from the downloaded file.
- `DailyFontCache` downloads the day's fonts into the widget's own caches folder
  on the first drawing of the day and removes the day before's. The back and
  forward buttons are `RotateFontIntent`, which counts presses for each size.
- Clicking a widget opens `homebrewfontgallery://font/<token>` (`Shared/FontLink.swift`).
  The app's `Info.plist` registers the scheme, and `ContentView.onOpenURL` selects the
  font, clearing any search or filter that hides it. To try it without a widget, run
  `open -n -a "build/Release/Homebrew Fonts Gallery.app" homebrewfontgallery://font/font-lobster`.
- To see the widget without placing it on the desktop, build, open the app once,
  then open `/System/Library/CoreServices/WidgetKit Simulator.app` and choose
  Homebrew Fonts Gallery. It draws every size through the real widget pipeline.
  Its buttons don't respond there: test those on a widget placed on the desktop.

## Updates

- The app updates itself from this repository's GitHub releases (`UpdateService`,
  `UpdateModel`, `UpdateSheet`). It asks GitHub for the latest release when it
  opens and once a day, and from **Check for Updates…** in the app menu.
- The release workflow stamps each build with its run number (`BUILD_NUMBER` in
  `scripts/build.sh`), which is also the number in the release tag,
  `v1.0-build.N`. The updater offers a release whose number is higher than the
  running app's. A build made on this Mac keeps build number 1, which the
  updater takes for a local build: it never checks by itself, though Check for
  Updates… still works. To try the updater, build with `BUILD_NUMBER=2` and
  run a copy from outside `build/Release`.
- Before replacing the app it checks the zip against the SHA-256 GitHub records
  for the release asset, then that the unpacked app has this bundle identifier,
  the promised build number and an intact signature. The app is ad-hoc signed,
  so none of this proves who built it; that rests on GitHub's HTTPS. Sparkle
  and notarization need a Developer ID, so don't add them.
- It unpacks the zip with `/usr/bin/ditto`, the one command besides `brew` the
  app runs, launched with `Process` and logged the same way. It swaps the app
  bundle with `FileManager` and reopens it with `NSWorkspace`: no shell, no
  helper script.
- Downloads made by the app carry no quarantine flag, so Gatekeeper doesn't
  stop the updated app. An app still running from the Downloads folder under
  App Translocation can't be replaced; the updater says to move it first.
- Parse GitHub's answer in `UpdateParsing`, pure functions with unit tests.

## Running brew

- `BrewService` is the only type that runs `brew`, and besides the updater's
  `ditto` (see Updates) nothing else runs an external command. It launches `brew`
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

- One `Window` scene, titled "Homebrew Fonts Gallery", that quits when closed.
  Unlike DiskFlasher, a gallery of hundreds of fonts needs a resizable window
  and a scrolling list, so the size-to-content rule doesn't apply to the font
  list. Sheets, settings and detail panes still follow it.
- Sachin asked for these, as deliberate exceptions to the toolbar rules in
  `~/Developer/AGENTS.md`: Install is a green prominent button and Uninstall a
  red one, centred above the details pane; the toolbar ends at the edge of
  the grid, with the pane full height beside it; the All, Installed and Not
  Installed filters are rows in the sidebar, under All Fonts; the search field
  lives in the sidebar; while Homebrew works the action button shows a spinner
  and stays in place (clicking it offers to stop), then fades to red. When the
  details pane is hidden, the same button sits in the toolbar beside the pane's
  toggle, and the pane stays hidden until Sachin shows it again, with the
  toggle or by double-clicking a card.
- The grid allows multiple selection (Command-click, Shift-click). The button
  then installs every selected font that isn't installed, one `brew` run after
  another, and becomes Uninstall only when all of them are installed. The pane
  shows a summary of the selection (`SelectionSummaryView`).
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
