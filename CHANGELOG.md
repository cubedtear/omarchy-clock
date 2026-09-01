# Changelog

All notable user-facing changes to this plugin. Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## v0.1.0 — Initial release

### Added

- Everything Omarchy's built-in clock already does, unchanged: the bar
  date/time pill with cyclable formats (right click), a calendar popup with
  a six-row month grid, ISO week numbers, year progress, and the
  double-tap-to-set memento mori life bar.
- **Show seconds** — a Preferences toggle in the popup that adds `:ss` to
  the bar label (24-hour and AM/PM formats both supported). Off by default;
  only ticks at second precision while it's on.
- **World clocks** — an optional list of other cities in the popup, each
  showing that zone's live time via `Intl`, with a same different-day flag
  when a city has already rolled into tomorrow or hasn't reached today yet.
  Add one with any IANA timezone name (e.g. `Asia/Tokyo`); the section
  itself stays out of the way until you've added at least one.
- Independent plugin id (`io.github.aryan-techie.clock`) — installs
  alongside the built-in clock rather than replacing it, so both can run
  side by side while you decide which one to keep on the bar.
