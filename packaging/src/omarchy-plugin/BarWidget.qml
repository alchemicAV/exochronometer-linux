import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "core/timeFrame.mjs" as TF

// Exochronometer bar widget.
//
// Shows the CURRENT DEGREE of one timeframe - the same number the CIRCLES page
// draws its indicator at, straight from the ported core, so the bar and the app
// can never disagree. Left click opens the full instrument as a panel; right
// click steps the timeframe; middle click launches the standalone window.
//
// The open/close/opened shape below is the shell's popout contract: the bar's
// popout coordinator looks the slot up by these on the bar-widget root, so they
// must exist even though the panel they drive is a separate file.
BarWidget {
  id: root
  moduleName: "alchemicav.exochronometer"

  readonly property var timeframes: ["year", "moon", "quarterMoon", "day", "hour", "minute"]
  readonly property var shortLabels: ["YR", "MN", "QM", "DY", "HR", "MIN"]

  // Which timeframe the label reads. Persisted like any other widget setting,
  // so it survives a shell restart.
  property int tfIndex: {
    const v = Number(setting("tfIndex", 0))
    return isNaN(v) ? 0 : v
  }
  readonly property int tfWrapped: ((tfIndex % timeframes.length) + timeframes.length) % timeframes.length
  readonly property string timeframe: timeframes[tfWrapped]
  readonly property string shortLabel: shortLabels[tfWrapped]

  // Degrees are UTC (TimeFrame.ts): two machines in different zones show the
  // same number, which is the whole point of the instrument.
  property date now: new Date()
  readonly property real deg: TF.degree(timeframe, now)

  readonly property string displayText: shortLabel + " " + deg.toFixed(1) + "\u00B0"
  readonly property var verticalLines: [shortLabel, deg.toFixed(0) + "\u00B0"]

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.now = new Date()
  }

  function cycleTimeframe() {
    var next = (tfWrapped + 1) % timeframes.length
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry["tfIndex"] = next
    // Applied locally first so the label changes on the click itself; the
    // shell.json write comes back through the bar as the same value.
    root.tfIndex = next
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

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