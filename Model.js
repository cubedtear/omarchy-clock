// Pure date and format math for the clock widget and its calendar panel.
// Everything here is locale- and Qt-free so it can be unit tested under node
// (test/shell.d/clock-test.sh); the QML owns month/weekday naming through
// Qt.locale().

var MS_PER_DAY = 86400000

// Weekday indices match both JS Date.getDay() and QML's Locale.Sunday…
// Locale.Saturday, so a locale's firstDayOfWeek can be passed straight in.
var WEEKDAY_NAMES = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

// ---- Bar label formats. Right-clicking the clock walks these in order and
//      writes the result back to shell.json, so the label the bar shows and
//      the format the config stores are always the same thing.
//
// The locale-shaped time presets are each followed by their 12-hour twin, so
// the walk from a 24-hour label to the same label in AM/PM is a single right
// click rather than a lap of the ring. The ISO preset is deliberately left
// without one: ISO 8601 writes time on a 24-hour clock, so an AM/PM variant
// would contradict the only thing that format is for.
var CLOCK_FORMATS = [
  "dddd HH:mm",
  "dddd h:mm AP",
  "HH:mm",
  "h:mm AP",
  "ddd d MMM HH:mm",
  "ddd d MMM h:mm AP",
  "d MMMM 'W'ww yyyy",
  "yyyy-MM-dd HH:mm"
]

// Vertical bars have room for a few stacked lines and nothing else, so the
// ring stays short. AM/PM costs a fourth line, which is why only the plain
// time carries it here.
var VERTICAL_CLOCK_FORMATS = [
  "HH\n—\nmm",
  "h\n—\nmm\nAP",
  "dd\nMMM\n'W'ww\n''yy",
  "HH\nmm"
]

function clockFormats(vertical) {
  return vertical ? VERTICAL_CLOCK_FORMATS.slice() : CLOCK_FORMATS.slice()
}

// The presets in a fixed order, plus the configured alternate and current
// format when they are something else. The order must not depend on which
// entry is current: cycling writes the result back to shell.json, and a ring
// that reshuffled itself around the current value would bounce between two
// entries instead of walking.
function clockFormatRing(configured, configuredAlt, presets) {
  var ring = []
  var candidates = (presets || []).concat([configuredAlt, configured])
  for (var i = 0; i < candidates.length; i++) {
    var format = String(candidates[i] === undefined || candidates[i] === null ? "" : candidates[i])
    if (format === "" || ring.indexOf(format) !== -1) continue
    ring.push(format)
  }
  return ring.length > 0 ? ring : ["HH:mm"]
}

// Next entry after `current`. An unknown current format (a hand-written one
// that is not in the ring) starts the walk at the top.
function nextClockFormat(ring, current) {
  if (!ring || ring.length === 0) return ""
  var index = ring.indexOf(String(current === undefined || current === null ? "" : current))
  return ring[(index + 1) % ring.length]
}

// Two-digit ISO week, substituted into a format's 'ww' token before Qt
// formats it -- Qt has no ISO week specifier of its own.
function isoWeekLiteral(year, month, day) {
  return pad2(isoWeek(year, month, day))
}

function pad2(value) {
  var n = Number(value)
  return (n < 10 ? "0" : "") + n
}

// Stable "yyyy-MM-dd" identity for a day, so a grid cell can be compared
// against today without dragging Date objects through bindings.
function dateKey(year, month, day) {
  return year + "-" + pad2(Number(month) + 1) + "-" + pad2(day)
}

function keyForDate(date) {
  return dateKey(date.getFullYear(), date.getMonth(), date.getDate())
}

function coerceWeekStart(value) {
  if (value === undefined || value === null) return null
  if (typeof value === "number")
    return isFinite(value) ? ((Math.round(value) % 7) + 7) % 7 : null

  var text = String(value).replace(/^\s+|\s+$/g, "").toLowerCase()
  if (text === "") return null

  for (var i = 0; i < WEEKDAY_NAMES.length; i++)
    if (WEEKDAY_NAMES[i] === text || WEEKDAY_NAMES[i].substr(0, 3) === text) return i

  var parsed = parseInt(text, 10)
  return isFinite(parsed) ? ((parsed % 7) + 7) % 7 : null
}

// Configured week start, falling back to the locale's own first day when
// the setting is missing or nonsense.
function normalizedWeekStart(value, fallback) {
  var configured = coerceWeekStart(value)
  if (configured !== null) return configured
  var fallbackStart = coerceWeekStart(fallback)
  return fallbackStart === null ? 1 : fallbackStart
}

function weekStartSettingName(index) {
  return WEEKDAY_NAMES[normalizedWeekStart(index, 1)]
}

// The toggle flips between the two conventions people actually switch
// between. A calendar configured to any other start (Saturday, say) is
// shown as-is and lands on Monday the first time it is toggled.
function toggledWeekStart(index) {
  return normalizedWeekStart(index, 1) === 1 ? 0 : 1
}

function weekdayOrder(weekStart) {
  var start = normalizedWeekStart(weekStart, 1)
  var out = []
  for (var i = 0; i < 7; i++) out.push((start + i) % 7)
  return out
}

// ISO-8601 week number: the week owning the Thursday of that date's
// Monday-based week. Mirrors the clock widget's 'ww' format token.
function isoWeek(year, month, day) {
  var date = new Date(Date.UTC(year, month, day))
  var weekday = date.getUTCDay() || 7
  date.setUTCDate(date.getUTCDate() + 4 - weekday)
  var yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1))
  return Math.ceil(((date.getTime() - yearStart.getTime()) / MS_PER_DAY + 1) / 7)
}

function dayOfYear(year, month, day) {
  return Math.round((Date.UTC(year, month, day) - Date.UTC(year, 0, 1)) / MS_PER_DAY) + 1
}

function daysInYear(year) {
  return dayOfYear(year, 11, 31)
}

// Share of the year already behind you: whole days completed over days in
// the year, so January 1 reads 0% and December 31 reads 100%.
function yearProgress(year, month, day) {
  var total = daysInYear(year)
  if (total <= 0) return 0
  return Math.max(0, Math.min(1, (dayOfYear(year, month, day) - 1) / total))
}

function yearProgressPercent(year, month, day) {
  return Math.round(yearProgress(year, month, day) * 100)
}

// Memento mori. The default span is a round number rather than anything from
// an actuarial table: the point of the bar is the reminder, not the
// arithmetic, and whoever wants a different number can say so.
var DEFAULT_LIFE_EXPECTANCY = 90

// A birth year rather than an age, so the bar keeps counting on its own
// instead of going stale the moment it is entered. 0 means "not set", which
// is also what a blank, malformed, future, or implausibly distant year means.
function parseBirthYear(value, currentYear) {
  var now = Math.round(Number(currentYear))
  if (!isFinite(now)) return 0
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d{4}$/.test(text)) return 0
  var year = parseInt(text, 10)
  if (!isFinite(year) || year > now || year < now - 120) return 0
  return year
}

// Whole years, the way people say their age: born in 1979 makes you 47 for
// all of 2026, whichever side of your birthday today falls.
function ageFromBirthYear(birthYear, currentYear) {
  var born = parseBirthYear(birthYear, currentYear)
  if (born <= 0) return 0
  return Math.round(Number(currentYear)) - born
}

// 0 means "not set", which is also what a blank, negative, fractional, or
// absurd entry means — the life bar simply stays hidden.
function parseAge(value) {
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d+$/.test(text)) return 0
  var years = parseInt(text, 10)
  if (!isFinite(years) || years <= 0 || years > 120) return 0
  return years
}

// Unset or nonsense falls back to the default rather than to zero, so the
// bar always has something to measure against.
function parseLifeExpectancy(value) {
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d+$/.test(text)) return DEFAULT_LIFE_EXPECTANCY
  var years = parseInt(text, 10)
  if (!isFinite(years) || years <= 0 || years > 150) return DEFAULT_LIFE_EXPECTANCY
  return years
}

function lifeProgress(age, expectancy) {
  var years = parseAge(age)
  var span = parseLifeExpectancy(expectancy)
  if (years <= 0 || span <= 0) return 0
  return Math.max(0, Math.min(1, years / span))
}

function lifeProgressPercent(age, expectancy) {
  return Math.round(lifeProgress(age, expectancy) * 100)
}

// Always six rows of seven days. A fixed grid keeps the popup exactly the
// same height in every month, so stepping through the year never makes the
// panel jump under the pointer.
function monthGrid(year, month, weekStart, todayKey) {
  var start = normalizedWeekStart(weekStart, 1)
  var leading = (new Date(year, month, 1).getDay() - start + 7) % 7
  var cursor = new Date(year, month, 1 - leading)
  var today = String(todayKey || "")
  var weeks = []

  for (var w = 0; w < 6; w++) {
    var days = []
    var thursday = null
    for (var d = 0; d < 7; d++) {
      var cellYear = cursor.getFullYear()
      var cellMonth = cursor.getMonth()
      var cellDay = cursor.getDate()
      var weekday = cursor.getDay()
      var key = dateKey(cellYear, cellMonth, cellDay)
      if (weekday === 4) thursday = { year: cellYear, month: cellMonth, day: cellDay }
      days.push({
        key: key,
        year: cellYear,
        month: cellMonth,
        day: cellDay,
        weekday: weekday,
        inMonth: cellMonth === month && cellYear === year,
        weekend: weekday === 0 || weekday === 6,
        today: key === today
      })
      cursor.setDate(cursor.getDate() + 1)
    }
    // Number every row by the ISO week owning its Thursday. That is the
    // definition itself for Monday-start weeks, and the only answer that
    // stays stable for the other starts, where a row straddles two ISO
    // weeks but shares all of Monday through Thursday with one of them.
    var anchor = thursday || days[0]
    weeks.push({
      week: isoWeek(anchor.year, anchor.month, anchor.day),
      days: days
    })
  }
  return weeks
}

function stepMonth(year, month, delta) {
  var target = new Date(year, Number(month) + Number(delta), 1)
  return { year: target.getFullYear(), month: target.getMonth() }
}

// ---- Seconds toggle. Inserted after the first minutes token so both the
//      24-hour and AM/PM presets gain seconds in the same place a person
//      would read them ("HH:mm" -> "HH:mm:ss", "h:mm AP" -> "h:mm:ss AP").
//      Vertical (stacked) formats are left untouched -- there is no room
//      for a fourth line in a bar slot sized for three.
function withSeconds(format, enabled) {
  var text = String(format || "")
  if (!enabled) return text
  if (text.indexOf("ss") !== -1) return text
  var idx = text.indexOf("mm")
  if (idx === -1) return text
  return text.slice(0, idx + 2) + ":ss" + text.slice(idx + 2)
}

// ---- World clocks. Each entry is { tz, label }; tz is an IANA zone name
//      (the same identifiers `timedatectl list-timezones` prints, which is
//      what the add-row's picker is seeded from).
//
// Per-zone time comes from a `date`/TZ subprocess, not Intl: this shell's
// JS engine accepts Intl.DateTimeFormat's `timeZone` option syntactically
// but silently fails to resolve real zone names with it (confirmed against
// "Asia/Tokyo" -- about as canonical an IANA name as exists), so relying on
// it would make every row read as invalid. `date` reading `TZ` is the same
// mechanism `timedatectl`/`omarchy-menu-timezone` already depend on, so the
// underlying tzdata is known-good on this system even though Intl can't
// reach it from here.

// Builds the argv for a single batched `date` call covering every
// configured zone at once (one subprocess per tick, not one per row).
// Zone names travel as real argv entries, never interpolated into a shell
// string, so there is nothing to escape. `%z` (numeric UTC offset, e.g.
// "+0900") rides along so rows can be sorted west-to-east and the scrubber
// can compute other zones' hypothetical time without another subprocess.
function worldClockCommand(zones) {
  var script = 'for tz in "$@"; do printf "%s\\t" "$tz"; TZ="$tz" date "+%H:%M|%Y-%m-%d|%z"; done'
  return ["bash", "-c", script, "_"].concat(zones)
}

// Parses that command's stdout ("tz\tHH:MM|YYYY-MM-DD|+HHMM" per line) into
// { [tz]: { time, dateKey, offsetMinutes } }. A line for a zone `date`
// couldn't resolve (renamed/removed from tzdata since it was saved) is
// skipped, not fatal.
function parseWorldClockOutput(text) {
  var lines = String(text || "").split("\n")
  var out = {}
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line === "") continue
    var tab = line.indexOf("\t")
    if (tab === -1) continue
    var tz = line.slice(0, tab)
    var rest = line.slice(tab + 1).split("|")
    if (rest.length !== 3) continue
    out[tz] = { time: rest[0], dateKey: rest[1], offsetMinutes: parseUtcOffsetMinutes(rest[2]) }
  }
  return out
}

// -1 / 0 / 1 for yesterday/today/tomorrow *relative to the zone this shell
// is running in*, from two already-computed "YYYY-MM-DD" keys.
function worldClockDayOffset(hereKey, thereKey) {
  if (!thereKey || thereKey === hereKey) return 0
  return thereKey < hereKey ? -1 : 1
}

// ---- Home row + offset-aware sorting/scrubbing (angelv.clock-inspired).

// "+0930" / "-0500" -> signed minutes from UTC. Null on anything that
// doesn't parse, so a bad reading sorts last instead of breaking the
// comparison.
function parseUtcOffsetMinutes(raw) {
  var text = String(raw || "").replace(/^\s+|\s+$/g, "")
  var m = /^([+-])(\d{2})(\d{2})$/.exec(text)
  if (!m) return null
  var sign = m[1] === "-" ? -1 : 1
  return sign * (parseInt(m[2], 10) * 60 + parseInt(m[3], 10))
}

// Ascending by UTC offset -- west (most negative) to east (most positive).
// Rows with no resolvable offset sort after every row that has one.
function sortZoneRows(rows) {
  var withOffset = []
  var withoutOffset = []
  for (var i = 0; i < rows.length; i++) {
    var v = rows[i].offsetMinutes
    if (v === null || v === undefined) withoutOffset.push(rows[i])
    else withOffset.push(rows[i])
  }
  withOffset.sort(function(a, b) { return a.offsetMinutes - b.offsetMinutes })
  return withOffset.concat(withoutOffset)
}

// "day" for a hand-wavy 6am-6pm window, "night" otherwise -- a glance-level
// indicator, not a sunrise/sunset calculation.
function dayPeriod(hhmm) {
  var hour = parseInt(String(hhmm || "").split(":")[0], 10)
  if (!isFinite(hour)) return "day"
  return (hour >= 6 && hour < 18) ? "day" : "night"
}

// Fraction (0..1) of the 24h rail a "HH:MM" string falls at.
function dayFraction(hhmm) {
  var parts = String(hhmm || "").split(":")
  var hour = parseInt(parts[0], 10)
  var minute = parseInt(parts[1], 10)
  if (!isFinite(hour)) return 0
  if (!isFinite(minute)) minute = 0
  return (((hour * 60 + minute) % 1440) + 1440) % 1440 / 1440
}

// The scrubber's position is a fraction of the day in the *reference*
// row's (home's) local time. Every other row's hypothetical time at that
// same instant is just its own UTC offset away from the reference's --
// pure arithmetic, no subprocess call needed while dragging.
function scrubbedClock(scrubFraction, referenceOffsetMinutes, rowOffsetMinutes) {
  var refMinutes = Math.round((((scrubFraction % 1) + 1) % 1) * 1440)
  var delta = (rowOffsetMinutes === null || rowOffsetMinutes === undefined
    || referenceOffsetMinutes === null || referenceOffsetMinutes === undefined)
    ? 0
    : rowOffsetMinutes - referenceOffsetMinutes
  var total = refMinutes + delta
  var dayOffset = Math.floor(total / 1440)
  var normalized = ((total % 1440) + 1440) % 1440
  return {
    time: pad2(Math.floor(normalized / 60)) + ":" + pad2(normalized % 60),
    dayOffset: dayOffset
  }
}

// Snaps a raw 0..1 drag fraction to the nearest 15-minute mark -- the
// "magnetic" part; dragging lands on :00/:15/:30/:45, not an arbitrary
// minute.
function snapToQuarterHour(fraction) {
  var minutes = Math.round((((fraction % 1) + 1) % 1) * 1440 / 15) * 15
  return (minutes % 1440) / 1440
}

// ---- Moon phase. A pure synodic-month approximation (no ephemeris/network
//      dependency), accurate to roughly a day -- the right precision for a
//      small panel decoration, not an almanac.
var MOON_PHASES = [
  { name: "New Moon", glyph: "🌑" },
  { name: "Waxing Crescent", glyph: "🌒" },
  { name: "First Quarter", glyph: "🌓" },
  { name: "Waxing Gibbous", glyph: "🌔" },
  { name: "Full Moon", glyph: "🌕" },
  { name: "Waning Gibbous", glyph: "🌖" },
  { name: "Last Quarter", glyph: "🌗" },
  { name: "Waning Crescent", glyph: "🌘" }
]
var SYNODIC_MONTH_DAYS = 29.530588853
var KNOWN_NEW_MOON_JULIAN_DAY = 2451550.1 // 2000-01-06 18:14 UTC

function julianDayNumber(year, month, day) {
  var a = Math.floor((14 - month) / 12)
  var y = year + 4800 - a
  var m = month + 12 * a - 3
  return day + Math.floor((153 * m + 2) / 5) + 365 * y + Math.floor(y / 4) - Math.floor(y / 100) + Math.floor(y / 400) - 32045
}

// month is 0-indexed (JS Date convention), matching every other date
// helper in this file.
function moonPhase(year, month, day) {
  var jd = julianDayNumber(year, month + 1, day)
  var cycles = (jd - KNOWN_NEW_MOON_JULIAN_DAY) / SYNODIC_MONTH_DAYS
  var fraction = cycles - Math.floor(cycles)
  var index = Math.floor(fraction * 8 + 0.5) % 8
  return { fraction: fraction, name: MOON_PHASES[index].name, glyph: MOON_PHASES[index].glyph }
}

// Maps an IANA zone name to its primary ISO 3166-1 country code, from
// tzdata's own zone1970.tab -- e.g. "Asia/Kolkata" -> "IN". First code wins
// for zones shared by several countries ("GB,GG,IM,JE" -> "GB").
function parseZoneCountryCodes(text) {
  var lines = String(text || "").split("\n")
  var out = {}
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line === "" || line.charAt(0) === "#") continue
    var cols = line.split("\t")
    if (cols.length < 3) continue
    var codes = cols[0].split(",")
    var tz = cols[2]
    if (tz && codes[0]) out[tz] = codes[0]
  }
  return out
}

// Short label for a world clock, for contexts too tight for a full city
// name (the bar pill). A custom label the person actually typed always
// wins; the auto-assigned fallback (parseWorldClocks defaults an unlabeled
// entry's label to its raw tz name) is swapped for the zone's country code
// instead, or a cleaned-up zone-name tail as a last resort.
function worldClockShortLabel(entry, countryCodes) {
  if (entry.label && entry.label !== entry.tz) return entry.label
  var code = countryCodes && countryCodes[entry.tz]
  if (code) return code
  var slash = entry.tz.lastIndexOf("/")
  return slash === -1 ? entry.tz : entry.tz.slice(slash + 1).replace(/_/g, " ")
}

// Settings round-trip through shell.json as whatever JSON produces; accept
// either an already-parsed array or (defensively) a JSON string, and drop
// individual malformed entries rather than failing the whole list.
function parseWorldClocks(raw) {
  var list = raw
  if (typeof list === "string") {
    try { list = JSON.parse(list) } catch (e) { return [] }
  }
  if (!Array.isArray(list)) return []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var entry = list[i]
    if (!entry || typeof entry.tz !== "string" || entry.tz === "") continue
    out.push({
      tz: entry.tz,
      label: (typeof entry.label === "string" && entry.label !== "") ? entry.label : entry.tz
    })
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    dateKey: dateKey,
    keyForDate: keyForDate,
    normalizedWeekStart: normalizedWeekStart,
    weekStartSettingName: weekStartSettingName,
    toggledWeekStart: toggledWeekStart,
    weekdayOrder: weekdayOrder,
    isoWeek: isoWeek,
    dayOfYear: dayOfYear,
    daysInYear: daysInYear,
    yearProgress: yearProgress,
    yearProgressPercent: yearProgressPercent,
    parseAge: parseAge,
    parseBirthYear: parseBirthYear,
    ageFromBirthYear: ageFromBirthYear,
    parseLifeExpectancy: parseLifeExpectancy,
    lifeProgress: lifeProgress,
    lifeProgressPercent: lifeProgressPercent,
    monthGrid: monthGrid,
    stepMonth: stepMonth,
    clockFormats: clockFormats,
    clockFormatRing: clockFormatRing,
    nextClockFormat: nextClockFormat,
    isoWeekLiteral: isoWeekLiteral,
    withSeconds: withSeconds,
    worldClockCommand: worldClockCommand,
    parseWorldClockOutput: parseWorldClockOutput,
    worldClockDayOffset: worldClockDayOffset,
    parseWorldClocks: parseWorldClocks,
    parseZoneCountryCodes: parseZoneCountryCodes,
    worldClockShortLabel: worldClockShortLabel,
    parseUtcOffsetMinutes: parseUtcOffsetMinutes,
    sortZoneRows: sortZoneRows,
    dayPeriod: dayPeriod,
    dayFraction: dayFraction,
    scrubbedClock: scrubbedClock,
    snapToQuarterHour: snapToQuarterHour,
    moonPhase: moonPhase
  }
}
