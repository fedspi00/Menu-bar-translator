# Lingo

A small macOS menu bar translator. Click the menu bar icon (or press ⌥⌘T),
type or paste, and the translation appears as you type. Set up for English ⇄
French out of the box, with every other Google Translate language available
from the two pickers.

Translations come from the same free Google Translate endpoints the web app
and the Chrome translate extension use — no API key, no account, no quota to
configure.

## Install

```sh
./install.sh
```

That builds the app, puts it in `/Applications`, and launches it. It needs
only the Xcode Command Line Tools (`xcode-select --install`), not Xcode.

To build without installing:

```sh
./build.sh          # produces build.noindex/Lingo.app
```

The build directory is named `.noindex` so Spotlight skips it — otherwise the
staged copy shows up alongside the installed one in Launchpad and Spotlight.

The app has no dock icon and no window — it lives entirely in the menu bar.
The first launch may show a Gatekeeper warning because the build is ad-hoc
signed rather than notarized; right-click the app and choose **Open** once, or
allow it under **System Settings → Privacy & Security**.

## Using it

| Action | Shortcut |
| --- | --- |
| Open / close the panel | ⌥⌘T (or click the menu bar icon) |
| Translate now | ⌘⏎ |
| Copy the translation | ⇧⌘C |
| Paste and translate | ⇧⌘V |
| Swap the two languages | ⌘S |
| Clear | ⌘K |
| Close | esc |

Typing translates automatically after a short pause, so ⌘⏎ is only needed if
you turn that off.

### Direction

The two pickers describe a **pair**, not a fixed direction. With
`English ⇄ French` selected, Lingo detects which of the two you wrote and
translates into the other one — English in gives French, French in gives
English. Text in some third language goes to the right-hand language. The
badge in the bottom-left always shows the direction actually used, e.g.
`FR → EN`.

Detection runs on-device (Apple's `NLLanguageRecognizer`), so choosing a
direction costs no extra network round trip. If Google disagrees with the
local guess and hands back text in the language you were translating *into*,
Lingo flips and asks again rather than showing your input back unchanged.

If you want a strict one-way direction, turn off **Translate either
direction** in the `⋯` menu. The arrow becomes `→`, and the left picker gains
a **Detect language** option.

## Options

In the `⋯` menu inside the panel:

- **Translate as you type** — live translation with a short debounce (on)
- **Translate either direction** — the pair behaviour described above (on)
- **Clear text when opened** — start empty every time (off)
- **Global shortcut (⌥⌘T)** — system-wide hot key (on)
- **Open at login**

Right-clicking the menu bar icon gives you Open and Quit.

## Layout

| Path | What it is |
| --- | --- |
| `Sources/main.swift` | Entry point |
| `Sources/AppDelegate.swift` | Status item, popover, keyboard shortcuts, login item |
| `Sources/ContentView.swift` | The panel UI |
| `Sources/Store.swift` | State, preferences, debounce, direction resolution |
| `Sources/GoogleTranslate.swift` | The two Google endpoints and their parsing |
| `Sources/Languages.swift` | Language list and code normalisation |
| `Sources/HotKey.swift` | Global shortcut via the Carbon hot key API |
| `Tools/make-icon.sh` | Draws the app icon at build time |
| `Tools/Preview/main.swift` | Renders the panel to a PNG for design iteration |

`Tools/Preview` is a development aid — it hosts the real `ContentView`
offscreen and writes a screenshot, which is handy for checking layout and
dark mode without opening the menu bar:

```sh
xcrun --sdk macosx swiftc -swift-version 5 -target arm64-apple-macos13.0 \
    Sources/*.swift Tools/Preview/main.swift -o /tmp/preview   # exclude Sources/main.swift
DARK=1 /tmp/preview /tmp/panel.png "Some text to translate" 4
```

## Caveats

The Google endpoints are the free, undocumented ones. They are what every
similar tool uses and they are fine for interactive use, but they can
rate-limit a burst of requests — Lingo shows a message and you can retry a
moment later. It falls back to a second endpoint automatically when the first
one refuses.

## Renaming

`APP_NAME` and `BUNDLE_ID` at the top of `build.sh` control the app name and
bundle identifier; the visible strings are in `ContentView.swift` and
`AppDelegate.swift`.
