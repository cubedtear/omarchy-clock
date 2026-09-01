<div align="center">

# Better Clock for Omarchy

**An enhanced clock bar widget for [Omarchy](https://omarchy.org/) — everything the built-in clock does, plus a seconds toggle and world clocks.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2FAROICE-HQ%2Fomarchy-clock%2Fmain%2Fmanifest.json&query=%24.version&label=version&color=informational)](manifest.json)
[![Omarchy plugin](https://img.shields.io/badge/omarchy-plugin-6d4aff)](https://omarchy.org/)

*Part of [OMARCHY100](https://github.com/AROICE-HQ/omarchy100) — a 100-plugin suite for Omarchy.*

</div>

Omarchy's built-in clock is already good: a bar pill with cyclable formats,
a calendar popup with ISO week numbers, year progress, and a hidden
memento-mori life bar. This plugin starts from that exact code (cloned, not
rebuilt) and adds the two things it doesn't have: a seconds display and a
short list of other cities' current time.

It installs as its own independent plugin — both it and the built-in clock
can be enabled at once, so you can compare them side by side before
deciding which stays on your bar.

## Contents

- [Features](#features)
- [Install](#install)
- [Usage](#usage)
- [How it works](#how-it-works)
- [Settings storage](#settings-storage)
- [Uninstalling](#uninstalling)
- [Changelog](#changelog)
- [License](#license)
- [Author](#author)

## Features

Everything the built-in `omarchy.clock` already has:

- Bar pill with a cyclable label format (right click walks presets: `dddd
  HH:mm`, 12-hour, `HH:mm`, `ddd d MMM`, ISO `yyyy-MM-dd`, and their
  vertical-bar equivalents).
- Middle click opens the system timezone picker.
- Calendar popup: a fixed six-row month grid, ISO week numbers down the
  left gutter (click **W** to switch Monday/Sunday start), keyboard and
  scroll-wheel month navigation, and a year-progress rail.
- Double-tap the year rail to set a birth year and a life-expectancy —
  it's the same easter egg, unchanged.

New in this plugin:

- **Show seconds** — a toggle in the popup's Preferences section. Appends
  `:ss` to the bar label and switches the clock to second-precision
  ticking only while it's on.
- **World clocks** — add any number of other cities to the popup by IANA
  timezone name (`Europe/London`, `Asia/Tokyo`, ...), each with an
  optional custom label. Rows show that zone's live time and flag when
  it's already tomorrow or still yesterday there relative to here.

![Better Clock panel preview](preview.png)

## Install

```
omarchy plugin add https://github.com/AROICE-HQ/omarchy-clock.git --enable
```

Or, to develop/inspect it locally first:

```
omarchy plugin clone io.github.aryan-techie.clock --edit
```

(swap in this repo's contents, or copy this folder to
`~/.config/omarchy/plugins/io.github.aryan-techie.clock/` directly and run
`omarchy-shell shell rescanPlugins` if it doesn't pick up right away).

## Usage

| Action | Effect |
|---|---|
| Left click | Open the calendar popup |
| Right click | Cycle the bar label format |
| Middle click | Open the system timezone picker |
| `[` / `]` (popup open) | Previous / next month |
| `{` / `}` (popup open) | Previous / next year |
| `t` (popup open) | Jump back to today |
| `w` (popup open) | Toggle Monday/Sunday week start |
| Double-tap year rail | Set/clear birth year + life expectancy |

### Adding a world clock

Open the popup, scroll to **World Clocks**, click **Add city**, and enter
an IANA timezone name — the same identifiers `timedatectl list-timezones`
prints (e.g. `America/New_York`, `Asia/Kolkata`). An optional label
replaces the raw zone name in the row. An unrecognized zone name shows an
inline error instead of being added.

## How it works

- **Seconds toggle**: `Model.withSeconds()` inserts `:ss` right after the
  first `mm` token in whichever format is currently active, so both the
  24-hour and AM/PM presets gain seconds in the position you'd expect.
  `BarWidget.qml`'s `SystemClock` only switches to second precision while
  the toggle is on — otherwise it stays at minute precision, same as the
  built-in widget, so it isn't repainting every second for nothing.
- **World clocks**: plain QML `Date` carries no timezone information of
  its own, so each row's time comes from
  `Intl.DateTimeFormat(..., { timeZone })`, re-evaluated once a minute by
  a dedicated `SystemClock`. A zone name is validated the same way before
  being saved — if `Intl` rejects it, it isn't added.
- **Settings** live in the same place the built-in clock's do: inline in
  the widget's own entry in `~/.config/omarchy/shell.json`, written back
  through the shell's `updateEntryInline` call whenever you flip the
  seconds toggle or add/remove a city — no separate state file.

## Settings storage

Nothing this plugin adds writes anywhere outside
`~/.config/omarchy/shell.json` (the same file every bar widget's layout
and settings already live in). No network calls, no other state files.

## Uninstalling

```
omarchy plugin remove io.github.aryan-techie.clock
```

This removes the plugin and its bar entry. The built-in clock (if you
still have it enabled) is unaffected.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

MIT — see [LICENSE](LICENSE).

## Author

**Aryan Techie** ([Aryan Jangra](https://aryan.aroice.in))

- 🌐 Website: [aryan.aroice.in](https://aryan.aroice.in)
- 📧 Email: [aryan@aroice.in](mailto:aryan@aroice.in)
- 🐙 GitHub: [@Aryan-Techie](https://github.com/Aryan-Techie)
- 🏢 Organization: [AROICE](https://aroice.in)

---

<div align="center">

**Made with ❤️ by [AROICE](https://github.com/AROICE-HQ)**

</div>
