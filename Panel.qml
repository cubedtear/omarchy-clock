import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The clock's calendar popup: a month grid with ISO week numbers, built to
// sit beside the weather panel — same hero-over-detail composition, same
// spacing scale, same small-caps labels.
//
// The grid is a read-out rather than a picker: today is the only marked
// day, and the only thing that moves is which month is on screen —
// chevrons, the scroll wheel, and the arrow keys all step it.
//
// BarWidget.qml owns the bar label and hands this panel the button to
// anchor against.
Panel {
  id: root
  moduleName: "io.github.aryan-techie.clock"
  ipcTarget: "io.github.aryan-techie.clock"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Today. SystemClock keeps this honest across midnight so the
  //      highlight rolls over without the panel being reopened.
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)

  // The month on screen. Stepping moves this and nothing else: the grid is
  // a read-out, not a picker, so there is no per-day cursor to keep in sync.
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()

  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  // Pinned to today, not to the month being browsed — stepping through the
  // calendar does not change how much of the year is gone.
  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

  // Memento mori, for anyone who goes looking: double-tapping the year bar
  // asks for a birth year and a life expectancy, and a second bar tracks one
  // against the other. A birth year rather than an age, so it keeps counting
  // on its own. Without one the bar stays hidden.
  readonly property int birthYear: Model.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  readonly property int age: Model.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
  readonly property real lifeDone: Model.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: Model.lifeProgressPercent(age, lifeExpectancy)
  property bool editingLife: false

  // Unset falls through to the locale's own first day, so a fresh install
  // starts out matching the rest of the desktop rather than a hardcoded
  // convention. Clicking the grid's "W" heading writes the choice back to
  // shell.json.
  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  // The interface is English throughout, so day names are not taken from the
  // system locale. Where the week starts still is: that is a regional
  // convention rather than a translation, and it stays overridable above.
  readonly property var labelLocale: Qt.locale("en_US")
  readonly property string nextWeekStartLabel: labelLocale.dayName(Model.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey)

  // ---- World clocks + preferences. showSeconds lives here too (not just
  //      BarWidget) so the panel's own toggle and the bar pill read from —
  //      and write to — the same settings entry.
  readonly property bool showSeconds: setting("showSeconds", false) === true
  readonly property var worldClocks: Model.parseWorldClocks(setting("worldClocks", []))
  property date worldNow: new Date()
  // { [tz]: { time: "HH:MM", dateKey: "YYYY-MM-DD" } }, refreshed by
  // worldClockTimesProc every minute and whenever the list changes.
  property var worldClockTimes: ({})
  property bool addingWorldClock: false
  property string worldClockError: ""
  property string pendingWorldClockTz: ""
  // Fetched once (lazily, on first "Add city") from `timedatectl
  // list-timezones` -- the same source omarchy-menu-timezone reads from --
  // and cached for the rest of the panel's life.
  property var timezoneOptions: []
  // tzdata's own zone1970.tab, for short country-code labels (BarWidget's
  // bar-pill segments need these immediately, so this is fetched eagerly
  // rather than lazily like the searchable timezone list above).
  property var countryCodes: ({})

  // ---- Home row + scrubber (angelv.clock-inspired). homeTz is the
  //      machine's own zone, detected once via `timedatectl` -- pinned as
  //      the first, non-removable row so every other zone has a fixed
  //      reference point to compare against.
  property string homeTz: ""
  // null while not dragging (rows show live time); 0..1 (fraction of the
  // home row's day) while the scrubber is held, snapped to 15-minute marks.
  property var scrubFraction: null
  readonly property bool scrubbing: scrubFraction !== null

  // Home row + configured zones, each enriched with live (or scrubbed)
  // time/day-offset and sorted west-to-east by UTC offset. Built fresh on
  // every dependency change rather than cached -- the underlying arrays are
  // always small (a handful of cities).
  readonly property var zoneRows: {
    var rows = []
    if (root.homeTz !== "") {
      var homeEntry = root.worldClockTimes[root.homeTz]
      rows.push({
        tz: root.homeTz,
        label: "Home",
        isHome: true,
        offsetMinutes: homeEntry ? homeEntry.offsetMinutes : null,
        liveTime: homeEntry ? homeEntry.time : "—",
        liveDateKey: homeEntry ? homeEntry.dateKey : ""
      })
    }
    for (var i = 0; i < root.worldClocks.length; i++) {
      var wc = root.worldClocks[i]
      var entry = root.worldClockTimes[wc.tz]
      rows.push({
        tz: wc.tz,
        label: Model.worldClockShortLabel(wc, root.countryCodes),
        isHome: false,
        offsetMinutes: entry ? entry.offsetMinutes : null,
        liveTime: entry ? entry.time : "—",
        liveDateKey: entry ? entry.dateKey : ""
      })
    }
    var sorted = Model.sortZoneRows(rows)
    var referenceOffset = null
    for (var k = 0; k < sorted.length; k++) {
      if (sorted[k].isHome) { referenceOffset = sorted[k].offsetMinutes; break }
    }
    if (referenceOffset === null && sorted.length > 0) referenceOffset = sorted[0].offsetMinutes

    for (var j = 0; j < sorted.length; j++) {
      var row = sorted[j]
      if (root.scrubbing) {
        var scrubbed = Model.scrubbedClock(root.scrubFraction, referenceOffset, row.offsetMinutes)
        row.time = scrubbed.time
        row.dayOffset = scrubbed.dayOffset
      } else {
        row.time = row.liveTime
        row.dayOffset = Model.worldClockDayOffset(root.todayKey, row.liveDateKey)
      }
      row.period = Model.dayPeriod(row.time)
      row.fraction = Model.dayFraction(row.time)
    }
    return sorted
  }

  readonly property var todayMoonPhase: Model.moonPhase(root.today.getFullYear(), root.today.getMonth(), root.today.getDate())

  // Guarded so the widget renders before the bar is injected (the bar-widget
  // contract instantiates it bare).
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)

  function open() {
    refresh()
    root.controller.show()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    // Dismissing the panel mid-edit would otherwise leave the inputs up,
    // waiting behind a closed popup for the next time it opens.
    if (root.editingLife) root.cancelEditingLife()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    root.today = new Date()
    root.goToToday()
    root.refreshWorldClockTimes()
  }

  function goToToday() {
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  // Applied locally first so the panel redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. With no
  // writable entry (the widget is not in the layout) it stays a session-only
  // preference rather than doing nothing. The host widget builds its own
  // entry when the label format is cycled, so it has to be kept in step or
  // it would write this key straight back out from a stale copy.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setWeekStart(day) {
    var next = Model.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persistSettings({ weekStartDay: Model.weekStartSettingName(next) })
  }

  function startEditingLife() {
    root.editingLife = true
    Qt.callLater(function() {
      bornField.text = root.birthYear > 0 ? String(root.birthYear) : ""
      expectancyField.text = String(root.lifeExpectancy)
      bornField.selectAll()
      bornField.forceActiveFocus()
    })
  }

  function cancelEditingLife() {
    root.editingLife = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // Shared by both fields: Tab hops to the other one, Enter commits the pair,
  // Escape drops the lot.
  function handleLifeKey(event, other) {
    if (event.key === Qt.Key_Escape) {
      root.cancelEditingLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      other.selectAll()
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  // Double-tapping the life bar puts it away again. The expectancy stays in
  // the config so setting a birth year again brings your own number back
  // rather than the default.
  function clearLife() {
    if (root.birthYear <= 0) return
    persistSettings({ birthYear: 0 })
  }

  function commitLife() {
    var born = Model.parseBirthYear(bornField.text, today.getFullYear())
    var span = Model.parseLifeExpectancy(expectancyField.text)
    if (born !== root.birthYear || span !== root.lifeExpectancy)
      persistSettings({ birthYear: born, lifeExpectancy: span })
    cancelEditingLife()
  }

  function toggleWeekStart() {
    setWeekStart(Model.toggledWeekStart(root.weekStart))
  }

  function setShowSeconds(value) {
    persistSettings({ showSeconds: !!value })
  }

  // By tz rather than position: zoneRows is sorted by UTC offset, so its
  // index into that list is not the same as the index in the unsorted
  // settings array this actually needs to splice.
  function removeWorldClock(tz) {
    var list = root.worldClocks.slice()
    for (var i = 0; i < list.length; i++) {
      if (list[i].tz === tz) { list.splice(i, 1); break }
    }
    persistSettings({ worldClocks: list })
    root.refreshWorldClockTimes()
  }

  function refreshWorldClockTimes() {
    var zones = []
    if (root.homeTz !== "") zones.push(root.homeTz)
    for (var i = 0; i < root.worldClocks.length; i++) zones.push(root.worldClocks[i].tz)
    if (zones.length === 0) { root.worldClockTimes = {}; return }
    worldClockTimesProc.command = Model.worldClockCommand(zones)
    worldClockTimesProc.running = true
  }

  function startScrub(fraction) {
    root.scrubFraction = Model.snapToQuarterHour(fraction)
  }

  function updateScrub(fraction) {
    root.scrubFraction = Model.snapToQuarterHour(fraction)
  }

  function endScrub() {
    root.scrubFraction = null
  }

  function startAddingWorldClock() {
    root.addingWorldClock = true
    root.worldClockError = ""
    root.pendingWorldClockTz = ""
    if (root.timezoneOptions.length === 0) timezoneListProc.running = true
    Qt.callLater(function() {
      worldClockLabelField.text = ""
    })
  }

  function cancelAddingWorldClock() {
    root.addingWorldClock = false
    root.worldClockError = ""
    root.pendingWorldClockTz = ""
  }

  function commitWorldClock() {
    var tz = String(root.pendingWorldClockTz || "").replace(/^\s+|\s+$/g, "")
    if (tz === "") { root.worldClockError = "Search and pick a city first"; return }
    var label = String(worldClockLabelField.text || "").replace(/^\s+|\s+$/g, "")
    var list = root.worldClocks.slice()
    list.push({ tz: tz, label: label !== "" ? label : tz })
    persistSettings({ worldClocks: list })
    root.addingWorldClock = false
    root.worldClockError = ""
    root.pendingWorldClockTz = ""
    root.refreshWorldClockTimes()
  }

  // English short day names, matching the rest of the interface.
  function weekdayLabel(weekday) {
    return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (Model.keyForDate(clock.date) === String(root.todayKey)) return
      var followToday = root.viewingCurrentMonth
      root.today = clock.date
      if (followToday) root.goToToday()
    }
  }

  // Separate from `clock` above: that one only updates `today` on a day
  // rollover (it drives the grid's highlight, not a live readout), so world
  // clock rows need their own minute-precision tick to stay current.
  SystemClock {
    id: worldClockTicker
    precision: SystemClock.Minutes
    onDateChanged: {
      root.worldNow = date
      root.refreshWorldClockTimes()
    }
  }

  // Same source omarchy-menu-timezone reads from. Run once per panel
  // lifetime (lazily, on first "Add city"), not on every open.
  Process {
    id: timezoneListProc
    command: ["timedatectl", "list-timezones"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var options = []
        for (var i = 0; i < lines.length; i++) {
          var tz = lines[i].replace(/^\s+|\s+$/g, "")
          if (tz === "") continue
          options.push({ value: tz, label: tz })
        }
        root.timezoneOptions = options
      }
    }
  }

  // Batched per-tick lookup for every configured world clock at once (see
  // Model.worldClockCommand for why this replaces an Intl-based approach).
  Process {
    id: worldClockTimesProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.worldClockTimes = Model.parseWorldClockOutput(text)
    }
  }

  Process {
    id: countryCodeProc
    command: ["cat", "/usr/share/zoneinfo/zone1970.tab"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.countryCodes = Model.parseZoneCountryCodes(text)
    }
  }

  // Same detection omarchy-menu-timezone's "current" state relies on.
  // One-shot: the machine's zone doesn't change under a running session.
  Process {
    id: homeTzProc
    command: ["timedatectl", "show", "--property=Timezone", "--value"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var tz = String(text || "").replace(/^\s+|\s+$/g, "")
        if (tz !== "") {
          root.homeTz = tz
          root.refreshWorldClockTimes()
        }
      }
    }
  }

  Component.onCompleted: {
    root.refreshWorldClockTimes()
    countryCodeProc.running = true
    homeTzProc.running = true
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(calendarColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLife
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveMonth(dx)
        if (dy !== 0) root.moveYear(dy)
      }
      onActivateRequested: root.goToToday()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "{") root.moveYear(-1)
        else if (t === "}") root.moveYear(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "w" || t === "W") root.toggleWeekStart()
      }

      Flickable {
        id: calendarScroll
        anchors.fill: parent
        contentWidth: calendarColumn.width
        contentHeight: calendarColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height || contentWidth > width

        Column {
          id: calendarColumn
          // Never narrower than the grid. The popup width is capped to what
          // the screen allows, and a fixed seven-column grid would otherwise
          // lose its last days off the edge instead of scrolling.
          width: Math.max(calendarScroll.width, gridColumn.width)
          spacing: Style.space(8)

          // ---- Hero: today, centered. Once the view has stepped back
          //      it is also the way home — clicking the date you are
          //      looking for beats hunting for a reset button.
          Item {
            width: parent.width
            height: heroRow.height

            Row {
              id: heroRow
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(22)

              Text {
                // Baseline-aligned, not center-aligned: "July 26" carries a
                // descender, so centering the two boxes leaves the icon
                // sitting visibly low against the digits.
                anchors.baseline: heroDate.baseline
                text: "󰃭"
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                // Decorative, and deliberately outside the Style.font.*
                // scale. Sized so the glyph reads at the cap height of the
                // date beside it rather than towering over it.
                font.pixelSize: 48
              }

              Text {
                id: heroDate
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(root.today, "MMMM d")
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 52
                font.bold: true
              }

              // Small, unobtrusive -- today's moon phase, not a whole
              // section. A pure-math approximation (Model.moonPhase), not
              // an API call.
              Text {
                id: moonGlyph
                textFormat: Text.PlainText
                anchors.baseline: heroDate.baseline
                text: root.todayMoonPhase.glyph
                font.pixelSize: 22

                MouseArea {
                  id: moonMouse
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  hoverEnabled: true
                  acceptedButtons: Qt.NoButton

                  PanelToolTip {
                    visible: moonMouse.containsMouse
                    text: root.todayMoonPhase.name
                    fontFamily: root.contentFontFamily
                  }
                }
              }
            }

            MouseArea {
              id: heroMouse
              x: heroRow.x
              y: heroRow.y
              width: heroRow.width
              height: heroRow.height
              enabled: !root.viewingCurrentMonth
              hoverEnabled: enabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToToday()

              PanelToolTip {
                visible: heroMouse.containsMouse
                text: "Back to today"
                fontFamily: root.contentFontFamily
              }
            }
          }

          // ---- Year progress, doubling as the rule under the hero:
          //      a plain hairline said nothing, and whole days done
          //      over days in the year says the same thing louder.
          Item {
            width: parent.width
            height: yearBlock.y + yearBlock.height

            Item {
              id: yearBlock
              y: Style.space(6)
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(yearLabel.implicitHeight, Style.space(10))

              TapHandler {
                enabled: !root.editingLife
                onDoubleTapped: root.startEditingLife()
              }

              Row {
                visible: root.editingLife
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "BORN"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: bornField
                  width: Style.space(70)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "year"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, expectancyField) }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.verticalCenterOffset: 0
                  leftPadding: Style.space(6)
                  text: "LIVE TO"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: expectancyField
                  width: Style.space(60)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "90"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, bornField) }
                }
              }

              Text {
                id: yearLabel
                textFormat: Text.PlainText
                visible: !root.editingLife
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.today.getFullYear()
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: yearPercent
                textFormat: Text.PlainText
                visible: !root.editingLife
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.yearDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                id: yearTrack
                visible: !root.editingLife
                anchors.left: yearLabel.right
                anchors.right: yearPercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.yearDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }
            }
          }

          // ---- Memento mori. Only here once someone has gone looking and
          //      given an age; the same rail as the year above it, measured
          //      against a nominal lifetime.
          Item {
            visible: root.birthYear > 0
            width: parent.width
            height: visible ? lifeBlock.height : 0

            Item {
              id: lifeBlock
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(lifeLabel.implicitHeight, Style.space(10))

              Text {
                id: lifeLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "LIFE"
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: lifePercent
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.lifeDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                anchors.left: lifeLabel.right
                anchors.right: lifePercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.lifeDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }

              TapHandler {
                onDoubleTapped: root.clearLife()
              }

              MouseArea {
                id: lifeMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton

                PanelToolTip {
                  visible: lifeMouse.containsMouse
                  text: "Memento Mori"
                  fontFamily: root.contentFontFamily
                }
              }
            }
          }

          // ---- Month grid: week numbers down a gutter on the left, then
          //      the seven day columns. Always six rows, so the popup is
          //      exactly as tall in February as it is in August.
          Item {
            width: parent.width
            height: gridColumn.y + gridColumn.height

            WheelHandler {
              onWheel: function(event) {
                // Horizontal wheels and touchpad side-scrolls report y === 0;
                // without this they would every one read as "next month".
                if (event.angleDelta.y === 0) return
                root.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
              }
            }

            Column {
              id: gridColumn
              // The meter above is a solid rule; the grid needs room to
              // read as its own block rather than hanging off it.
              y: Style.space(18)
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(3)

              Row {
                id: headerRow
                spacing: root.cellSpacing

                // The week-number heading doubles as the week-start toggle.
                // It is the one control in the panel whose meaning is not
                // self-evident, so it carries a tooltip naming the day the
                // click will switch to.
                Rectangle {
                  width: root.weekColumnWidth
                  height: Style.space(16)
                  radius: Style.cornerRadius
                  color: weekStartMouse.containsMouse
                    ? Style.hoverFillFor(root.contentForeground, Color.accent)
                    : "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: "W"
                    color: weekStartMouse.containsMouse
                      ? Style.hoverStateColor(root.contentForeground, Color.accent)
                      : Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }

                  MouseArea {
                    id: weekStartMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleWeekStart()
                  }

                  PanelToolTip {
                    visible: weekStartMouse.containsMouse
                    text: "Start weeks on " + root.nextWeekStartLabel
                    fontFamily: root.contentFontFamily
                  }
                }

                Item {
                  width: root.gutterWidth
                  height: Style.space(16)
                }

                Repeater {
                  model: root.weekdays

                  Text {
                    textFormat: Text.PlainText
                    required property var modelData
                    width: root.cellWidth
                    height: Style.space(16)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.weekdayLabel(modelData)
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }
                }
              }

              Repeater {
                model: root.weeks

                Row {
                  required property var modelData
                  spacing: root.cellSpacing

                  Text {
                    textFormat: Text.PlainText
                    width: root.weekColumnWidth
                    height: root.cellHeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.week
                    color: Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Item {
                    width: root.gutterWidth
                    height: root.cellHeight
                  }

                  Repeater {
                    model: modelData.days

                    Rectangle {
                      required property var modelData

                      width: root.cellWidth
                      height: root.cellHeight
                      radius: Style.cornerRadius
                      // Today is outlined, not filled: a lit-up block shouts
                      // over a grid this quiet.
                      color: "transparent"
                      border.width: modelData.today ? Style.spacing.hairline : 0
                      border.color: Style.normalBorderFor(root.contentForeground, Color.accent)

                      Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: modelData.day
                        color: modelData.inMonth
                          ? (modelData.weekend ? Qt.darker(root.contentForeground, 1.45) : root.contentForeground)
                          : Qt.darker(root.contentForeground, 2.2)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                        font.bold: modelData.today
                      }
                    }
                  }
                }
              }
            }

            // Hairline down the week-number gutter, drawn only beside the
            // day rows so it does not cut through the header band.
            Rectangle {
              x: gridColumn.x + root.weekColumnWidth + root.cellSpacing + Math.round((root.gutterWidth - width) / 2)
              y: gridColumn.y + headerRow.height + gridColumn.spacing
              width: Style.spacing.hairline
              height: gridColumn.height - headerRow.height - gridColumn.spacing
              color: root.contentForeground
              opacity: 0.1
            }
          }

          // ---- Month stepping, spanning the grid it drives. The chevrons
          //      sit on the grid's outer bounds, the same edges the year
          //      rail above uses, so the row reads as the panel's other
          //      full-width rail instead of a cluster floating in space.
          //      The label is centered and fixed-width, so it holds still
          //      from "MAY" to "SEPTEMBER".
          Item {
            width: parent.width
            height: monthNav.height

            Item {
              id: monthNav
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: monthLabel.implicitHeight + Style.space(10)

              Text {
                id: monthLabel
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                // Fixed width so the chevrons hold still between a
                // "MAY 2026" and a "SEPTEMBER 2026".
                width: Style.space(130)
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDate(root.viewDate, "MMMM yyyy").toUpperCase()
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.letterSpacing: 1
              }

              PanelActionButton {
                // Pulled out by the button's own padding so the glyph, not
                // its hit box, lines up with the "2026" on the year rail.
                anchors.left: parent.left
                anchors.leftMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅁"
                tooltipText: "Previous month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(-1)
              }

              PanelActionButton {
                anchors.right: parent.right
                anchors.rightMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅂"
                tooltipText: "Next month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(1)
              }
            }
          }

          // ---- World clocks: a short, user-picked list of other cities,
          //      each showing that zone's current time via Intl (plain QML
          //      Date carries no timezone of its own). Secondary to the
          //      grid above by design, but the header + "Add city" row must
          //      always render — they're the only way to add the first one.
          Item {
            width: parent.width
            height: worldClocksColumn.implicitHeight

            Column {
              id: worldClocksColumn
              width: gridColumn.width
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(6)

              PanelSeparator {
                foreground: root.contentForeground
              }

              PanelSectionHeader {
                text: "WORLD CLOCKS"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
              }

              Repeater {
                model: root.zoneRows

                Item {
                  id: zoneRow
                  required property var modelData
                  width: worldClocksColumn.width
                  height: Style.space(34)

                  Text {
                    id: periodGlyph
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: zoneRow.modelData.period === "day" ? "☀" : "☾"
                    font.pixelSize: Style.font.body
                  }

                  Text {
                    id: rowLabel
                    textFormat: Text.PlainText
                    anchors.left: periodGlyph.right
                    anchors.leftMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    text: zoneRow.modelData.label
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    font.bold: zoneRow.modelData.isHome
                    elide: Text.ElideRight
                    width: Style.space(70)
                  }

                  // Compact 24h night/day rail with a marker at this row's
                  // current (or scrubbed) position -- the same instant every
                  // row is showing, just each at its own point in the cycle.
                  Rectangle {
                    id: rail
                    anchors.left: rowLabel.right
                    anchors.leftMargin: Style.space(8)
                    anchors.right: timeLabel.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    height: Style.space(6)
                    radius: height / 2
                    gradient: Gradient {
                      orientation: Gradient.Horizontal
                      GradientStop { position: 0.0; color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08) }
                      GradientStop { position: 0.25; color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.28) }
                      GradientStop { position: 0.5; color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.28) }
                      GradientStop { position: 0.75; color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08) }
                      GradientStop { position: 1.0; color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08) }
                    }

                    Rectangle {
                      width: Style.space(8)
                      height: Style.space(8)
                      radius: width / 2
                      color: Style.selectedStateColor(root.contentForeground, Color.accent)
                      anchors.verticalCenter: parent.verticalCenter
                      x: Math.round(rail.width * zoneRow.modelData.fraction - width / 2)
                    }
                  }

                  Text {
                    id: timeLabel
                    textFormat: Text.PlainText
                    anchors.right: zoneRow.modelData.isHome ? parent.right : removeButton.left
                    anchors.rightMargin: zoneRow.modelData.isHome ? 0 : Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    text: zoneRow.modelData.time + (zoneRow.modelData.dayOffset !== 0 ? (zoneRow.modelData.dayOffset < 0 ? " (yst)" : " (tmrw)") : "")
                    color: Qt.darker(root.contentForeground, 1.3)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                  }

                  PanelActionButton {
                    id: removeButton
                    visible: !zoneRow.modelData.isHome
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: "󰅖"
                    tooltipText: "Remove"
                    foreground: root.contentForeground
                    hoverColor: root.bar ? root.bar.urgent : Color.urgent
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.caption
                    onClicked: root.removeWorldClock(parent.modelData.tz)
                  }
                }
              }

              // ---- Scrubber: drag anywhere along the rail to preview every
              //      row above at that same hour at once, snapped to 15-
              //      minute marks ("magnetic"). Only shown once there is a
              //      home row plus at least one other zone to compare it
              //      against.
              Item {
                visible: root.homeTz !== "" && root.worldClocks.length > 0
                width: worldClocksColumn.width
                height: visible ? Style.space(26) : 0

                Rectangle {
                  id: scrubTrack
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  height: Style.space(4)
                  radius: height / 2
                  color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.15)

                  Rectangle {
                    width: Style.space(10)
                    height: Style.space(10)
                    radius: width / 2
                    color: root.scrubbing ? Style.selectedStateColor(root.contentForeground, Color.accent) : Qt.darker(root.contentForeground, 1.3)
                    anchors.verticalCenter: parent.verticalCenter
                    // Home's own live time when idle -- not zoneRows[0],
                    // which is the westmost row after sorting and is only
                    // home when home happens to be the westmost zone.
                    x: Math.round(parent.width * (root.scrubbing ? root.scrubFraction : Model.dayFraction(root.worldClockTimes[root.homeTz] ? root.worldClockTimes[root.homeTz].time : "")) - width / 2)
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onPressed: function(mouse) { root.startScrub(mouse.x / width) }
                  onPositionChanged: function(mouse) { if (pressed) root.updateScrub(mouse.x / width) }
                  onReleased: root.endScrub()
                  onCanceled: root.endScrub()
                }

                PanelToolTip {
                  visible: root.scrubbing
                  text: "Drag to preview other hours"
                  fontFamily: root.contentFontFamily
                }
              }

              // Collapsed to a single action until clicked — the common
              // case (a short fixed list set up once) shouldn't carry two
              // empty fields around forever.
              Item {
                visible: !root.addingWorldClock
                width: worldClocksColumn.width
                height: Style.space(28)

                PanelActionButton {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "󰐕"
                  tooltipText: "Add a city"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.startAddingWorldClock()
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(28)
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Add city"
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.startAddingWorldClock()
                  }
                }
              }

              Column {
                visible: root.addingWorldClock
                width: worldClocksColumn.width
                spacing: Style.space(6)

                Row {
                  width: parent.width
                  spacing: Style.space(6)

                  SearchableDropdown {
                    id: worldClockTzDropdown
                    width: (parent.width - Style.space(6)) * 0.6
                    showLabel: false
                    placeholderText: "Search city or timezone..."
                    emptyText: root.timezoneOptions.length === 0 ? "Loading…" : "No matches"
                    foreground: root.contentForeground
                    accent: Color.accent
                    fontFamily: root.contentFontFamily
                    options: root.timezoneOptions
                    value: root.pendingWorldClockTz
                    onChanged: function(v) { root.pendingWorldClockTz = v }
                  }

                  TextField {
                    id: worldClockLabelField
                    width: parent.width - worldClockTzDropdown.width - Style.space(6)
                    placeholderText: "Label (optional)"
                    foreground: root.contentForeground
                    verticalPadding: Style.space(4)
                    Keys.onReturnPressed: root.commitWorldClock()
                    Keys.onEscapePressed: root.cancelAddingWorldClock()
                  }
                }

                Text {
                  visible: root.worldClockError !== ""
                  textFormat: Text.PlainText
                  text: root.worldClockError
                  color: root.bar ? root.bar.urgent : Color.urgent
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                  width: parent.width
                }

                Row {
                  spacing: Style.space(8)

                  Text {
                    textFormat: Text.PlainText
                    text: "Add"
                    color: Style.selectedStateColor(root.contentForeground, Color.accent)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.commitWorldClock()
                    }
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: "Cancel"
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.cancelAddingWorldClock()
                    }
                  }
                }
              }
            }
          }

          // Seconds toggle. No section header/separator of its own — it
          // reads as one more low-key control under World Clocks rather
          // than a whole labeled section.
          Item {
            width: parent.width
            height: secondsToggle.implicitHeight

            Toggle {
              id: secondsToggle
              width: gridColumn.width
              anchors.horizontalCenter: parent.horizontalCenter
              label: "Show seconds"
              description: "Adds :ss to the bar label"
              checked: root.showSeconds
              foreground: root.contentForeground
              accent: Color.accent
              fontFamily: root.contentFontFamily
              onClicked: root.setShowSeconds(!root.showSeconds)
            }
          }
        }
      }
    }
  }
}
