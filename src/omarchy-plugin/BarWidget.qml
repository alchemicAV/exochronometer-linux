import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "core/timeFrame.mjs" as TF
import "core/peakCalendar.mjs" as PC

// Exochronometer bar widget.
//
// Shows the instrument's own date and the angle of one timeframe. The date is
// the year's 22 Farey-peak months, read straight off the ported peak calendar,
// so today reads "Quartis 7" - month 18, day 7 of 19. The angle is the same
// number the CIRCLES page draws its indicator at, straight from the ported
// core, so the bar and the app can never disagree.
//
// The widget OWNS the preferred timeframe. The panel's CIRCLES page sets it
// through setPreferredTF(), because the shell cannot persist QtCore Settings
// (Quickshell leaves organizationName/organizationDomain unset) while
// shell.json settings do survive a restart.
//
// Left click opens the full instrument as a panel; right click steps the
// timeframe; middle click launches the standalone window.
//
// The open/close/opened shape below is the shell's popout contract: the bar's
// popout coordinator looks the slot up by these on the bar-widget root, so they
// must exist even though the panel they drive is a separate file.
BarWidget {
  id: root
  moduleName: "alchemicav.exochronometer"

  readonly property var timeframes: ["year", "moon", "quarterMoon", "day", "hour", "minute"]
  readonly property var shortLabels: ["YR", "MN", "QM", "DY", "HR", "MIN"]

  // Which timeframe's angle the label reads - hour by default, matching the
  // CIRCLES page's BAR ANGLE chips. Persisted like any other widget setting.
  // The name matters: AppShell binds to `preferredBridge.preferredTF`, so a
  // different name here reads back as undefined and the chips go dead.
  property int preferredTF: {
    const v = Number(setting("preferredTF", 4))
    return isNaN(v) ? 4 : v
  }
  readonly property int tfWrapped: ((preferredTF % timeframes.length) + timeframes.length) % timeframes.length
  readonly property string timeframe: timeframes[tfWrapped]
  readonly property string shortLabel: shortLabels[tfWrapped]

  // Degrees are UTC (TimeFrame.ts): two machines in different zones show the
  // same number, which is the whole point of the instrument.
  property date now: new Date()
  readonly property real deg: TF.degree(timeframe, now)

  // The exochronometer's date. The calendar's months are the gaps between the
  // year's geometric peaks, pos 0 is the December solstice.
  readonly property var exoDate: {
    const pos = PC.position(root.now)
    const month = PC.months[pos.monthIndex]
    return { name: month.name, day: pos.dayOfMonth }
  }
  readonly property string dateText: exoDate.name + " " + exoDate.day
  readonly property string angleText: shortLabel + " " + deg.toFixed(1) + "\u00B0"

  readonly property string displayText: dateText + "  " + angleText
  readonly property var verticalLines: [dateText, deg.toFixed(0) + "\u00B0"]

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.now = new Date()
  }

  function persistTF(i) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry["preferredTF"] = i
    // Applied locally first so the label changes on the click itself; the
    // shell.json write comes back through the bar as the same value.
    root.preferredTF = i
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // Called by the panel's CIRCLES page: the widget owns the preference so it can
  // live in shell.json, where it outlives the session.
  function setPreferredTF(i) { root.persistTF(i) }

  function cycleTimeframe() { root.persistTF((tfWrapped + 1) % timeframes.length) }

  // ---- panel lifecycle -----------------------------------------------------

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "alchemicav.exochronometer"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function cycleTimeframe(): void { root.cycleTimeframe() }
    function preferredTF(): string { return String(root.tfWrapped) }
    function setPreferredTF(i: int): void { root.setPreferredTF(i) }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : root.displayText
    labelVisible: !root.vertical
    hasVisualContent: root.vertical ? root.verticalLines.length > 0 : text !== ""
    fixedHeight: root.vertical ? root.verticalLines.length * Style.bar.iconSlot : -1
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function(b) {
      if (b === Qt.RightButton) root.cycleTimeframe()
      else if (b === Qt.MiddleButton) { if (root.bar) root.bar.run("exochronometer") }
      else root.togglePanel()
    }

    Column {
      visible: root.vertical
      anchors.fill: parent

      Repeater {
        model: root.verticalLines

        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: button.fontSize
          color: button.foreground
        }
      }
    }
  }
}