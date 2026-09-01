# Changelog

All notable user-facing changes to this plugin. Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## v0.1.0 — Initial release

### Added

- Everything Omarchy's built-in clock already does, unchanged: the bar
  date/time pill with cyclable formats (right click), a calendar popup with
  a six-row month grid, ISO week numbers, year progress, and the
  double-tap-to-set memento mori life bar.
- **Show seconds** — a toggle that adds `:ss` to the bar label. Off by
  default; only ticks at second precision while it's on.
- **World clocks** — add any number of other cities to the popup by
  searching a real list of IANA timezones, with an optional custom label.
  Configured clocks also show as short country-code segments in the bar
  pill itself (e.g. `IN 21:47`).
- **Home row** — your system's own timezone, auto-detected and pinned
  first in the World Clocks list.
- **West-to-east sorting** — every row (home included) orders by UTC
  offset rather than by the order cities were added.
- **Day/night indicators** — a ☀/☾ glyph and a compact 24-hour rail per
  row, marking that zone's current position in its day.
- **Magnetic scrubber** — drag to preview every zone at a chosen hour at
  once, snapped to 15-minute marks.
- **Moon phase** — a small badge next to the hero date, computed locally.
- Independent plugin id (`io.github.aryan-techie.clock`) — installs
  alongside the built-in clock rather than replacing it, so both can run
  side by side while you decide which one to keep on the bar.
