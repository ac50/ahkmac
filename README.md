# ahkmac

A tiny AutoHotkey-style key remapper and text expander for macOS.
Single binary, no dependencies, configured by one text file.

## Features

- **Key remapping** — `opt+j :: down`; targets may carry modifiers
  (`opt+e :: cmd+right`). Extra modifiers pass through, so with
  `opt+j :: down` pressing `opt+shift+j` yields `shift+down`.
- **Text expansion** — `"btw" => "by the way"` fires after a
  space/enter/punctuation; `*"@@" => "you@example.com"` fires immediately.
- **App scoping** — `[com.google.Chrome]` restricts the rules below it to
  that app; `apps name = id, id` names a reusable set for a `[name]`
  section; `[!name]` inverts (everywhere except); `[*]` returns to global.
- **Macros** — `macro name { key/text/sleep/run }` defines a named action
  sequence; bind it from a keymap (`:: macro name`) or a hotstring
  (`=> macro name`).

## Install

**Apple Silicon (arm64):** Download `ahkmac-arm64` from [Releases](../../releases):

```sh
chmod +x ahkmac-arm64
xattr -d com.apple.quarantine ahkmac-arm64   # unsigned binary
```

For app bundle, download `ahkmac.app.zip` from Releases, unzip, and drop `ahkmac.app` into `/Applications`.

**Intel:** Build from source on a Mac: `swift build -c release`.

## Usage

```sh
cp examples/ahkmac.conf ~/.config/ahkmac.conf
./ahkmac                  # uses ~/.config/ahkmac.conf
./ahkmac my.conf          # explicit config path
./ahkmac --check my.conf  # just validate the config
./ahkmac --apps           # list running apps and their bundle IDs
```

ahkmac needs the **Accessibility** permission
(System Settings → Privacy & Security → Accessibility). When run from a
terminal, the permission is attached to the terminal app; to avoid that,
use the app bundle below.

Reload the config without restarting: `pkill -HUP ahkmac`.

## Run as an app (no terminal)

Download `ahkmac.app.zip` from Releases, unzip, and drop `ahkmac.app` into
`/Applications`. Double-click to run — it stays in the background (no Dock
icon) and the Accessibility permission is granted to **ahkmac** itself,
not your terminal.

- First launch: the app is unsigned, so right-click → Open (on macOS 15
  you may also need System Settings → Privacy & Security → Open Anyway).
- Grant the Accessibility prompt; ahkmac starts working within a couple
  of seconds — no relaunch needed.
- Config errors show up as dialog boxes instead of terminal output.
- Start at login: System Settings → General → Login Items → add ahkmac.
- Quit: Activity Monitor, or `pkill ahkmac`.

### Nothing happens after launch?

Almost always a stale Accessibility grant: the entry in the list no
longer matches the binary (typical after an upgrade — the ad-hoc code
signature changes between releases, and macOS also relocates unsigned
apps launched straight from Downloads). ahkmac then waits silently for
a permission that never arrives.

**Fix: in System Settings → Privacy & Security → Accessibility, remove
ahkmac with the "−" button and add it back** (toggling the checkbox is
not always enough), then relaunch. To see what ahkmac is doing, run it
from a terminal — it prints whether it is running or still waiting:

```sh
/Applications/ahkmac.app/Contents/MacOS/ahkmac
```

## Config reference

```
# comment
source :: target                 key remap, chord = [mod+]*key
"trigger" => "replacement"       hotstring, fires on end char (kept)
*"trigger" => "replacement"      hotstring, fires immediately

apps name = id, id, ...          named set of bundle IDs
[bundle.id]                      section: rules below apply only in that app
[name]                           section: rules below apply only in that apps set
[!name]                          section: rules below apply everywhere except that set
[*]                              section: back to global scope (the default)

macro name {                     named, reusable action sequence
    key chord                      synthesize a key chord
    text "…"                       type literal text
    sleep ms                       pause 0–10000 ms
    run "shell command"            run via /bin/sh -c, async, fire-and-forget
}
source :: macro name             keymap bound to a macro
"trigger" => macro name          hotstring bound to a macro
```

- Modifiers: `cmd` `opt`/`alt` `ctrl` `shift` `fn`
- Keys: `a`–`z` `0`–`9` `up` `down` `left` `right` `space` `tab`
  `enter`/`return` `esc` `delete` `forwarddelete` `home` `end` `pageup`
  `pagedown` `f1`–`f20` `minus` `equal` `leftbracket` `rightbracket`
  `backslash` `semicolon` `quote` `comma` `period` `slash` `grave`
- String escapes: `\"` `\\` `\n` `\t`, plus `\-` `\.` `\!` … for any
  end character (see below)
- Errors are reported with line numbers; duplicate sources/triggers are
  rejected.

### Scoping

- A `[…]` header sets the scope for every rule after it, until the next
  header or end of file. Bundle IDs match case-insensitively; find them
  with `ahkmac --apps`.
- `apps` sets and `macro` blocks are global declarations — they take
  effect regardless of which section they're written in.
- Two rules for the same key/trigger conflict only if their scopes could
  both match the same app. Same-tier conflicts (e.g. two overlapping
  `[name]` sections) are rejected at parse time; cross-tier overrides are
  legal. At runtime, among rules matching the current app, the one with
  more modifiers (or, for hotstrings, the longer trigger) wins; scope tier
  (`[bundle.id]`/`[name]` > `[!name]` > global) only breaks ties on that —
  a global `cmd+opt+r :: X` still beats an app-scoped `opt+r :: Y`.

### Macros

- A macro-bound keymap or hotstring runs the named `macro` block instead
  of emitting a chord or replacement text.
- Holding a macro-bound hotkey down does not re-run the macro — key
  autorepeat is ignored.
- A macro-bound hotstring in end-char mode swallows the end character
  (it is not retyped), unlike a text hotstring, which reposts it.

### End characters and escaping

These characters end a word and make default-mode hotstrings fire:

```
space  tab  enter    - ( ) [ ] { } ' : ; " / \ , . ? !
```

Because they *mean* "fire now", writing one **unescaped** inside a trigger
is almost always a mistake, so the parser rejects it:

```
"e-mail" => "…"     error: unescaped end character '-' in trigger (write '\-')
"e\-mail" => "…"    OK — fires after e-mail + end char
*"btw\." => "…"     OK — fires the moment you type the final '.'
```

Whitespace can never appear in a trigger. A default-mode trigger that
*ends* with punctuation (like `"btw\."`) still needs one more end char
after it to fire — if you want it to fire on the `.` itself, use the
immediate `*` form as shown above.
