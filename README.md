# ahkmac

A tiny AutoHotkey-style key remapper and text expander for macOS.
Single binary, no dependencies, configured by one text file.

## Features

- **Key remapping** — `opt+j :: down`; targets may carry modifiers
  (`opt+e :: cmd+right`). Extra modifiers pass through, so with
  `opt+j :: down` pressing `opt+shift+j` yields `shift+down`.
- **Text expansion** — `"btw" => "by the way"` fires after a
  space/enter/punctuation; `*"@@" => "you@example.com"` fires immediately.

## Install

Download the binary from [Releases](../../releases) (universal, arm64 + x86_64):

```sh
chmod +x ahkmac
xattr -d com.apple.quarantine ahkmac   # unsigned binary
```

Or build from source on a Mac: `swift build -c release`.

## Usage

```sh
cp examples/ahkmac.conf ~/.config/ahkmac.conf
./ahkmac                  # uses ~/.config/ahkmac.conf
./ahkmac my.conf          # explicit config path
./ahkmac --check my.conf  # just validate the config
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
- After upgrading, re-tick ahkmac in the Accessibility list if hotkeys
  stop working (the ad-hoc code signature changes between releases).

## Config reference

```
# comment
source :: target                 key remap, chord = [mod+]*key
"trigger" => "replacement"       hotstring, fires on end char (kept)
*"trigger" => "replacement"      hotstring, fires immediately
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
