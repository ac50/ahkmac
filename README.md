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
(System Settings → Privacy & Security → Accessibility). The permission is
attached to the app that launches ahkmac — your terminal, typically.

Reload the config without restarting: `pkill -HUP ahkmac`.

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
- String escapes: `\"` `\\` `\n` `\t`
- Errors are reported with line numbers; duplicate sources/triggers are
  rejected.
