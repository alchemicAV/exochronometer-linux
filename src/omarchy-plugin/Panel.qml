import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "core/theme.mjs" as Theme

// The Exochronometer as an Omarchy panel.
//
// This hosts the SAME AppShell.qml the standalone desktop window hosts - one
// instrument, two hosts. The plugin directory is generated from the app source
// by scripts/build-omarchy-plugin.mjs, so the panel, the bar widget and the
// window can never drift apart.
//
// allowQuit is false: the shell's own q/Esc shortcuts would otherwise quit
// Quickshell and take the user's whole desktop shell down with it.
Panel {
  id: root
  moduleName: "alchemicav.exochronometer"
  ipcTarget: "alchemicav.exochronometer"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // The shell has already loaded the theme, so the panel takes the palette
  // straight from it rather than parsing files. Configured before the instrument
  // loads, because the theme module's exports are not observable.
  Component.onCompleted: {
    Theme.configure({
      background: Color.background.toString(),
      backgroundDark: Color.background.toString(),
      surface: Color.popups.background.toString(),
      foreground: Color.foreground.toString(),
      muted: Color.muted.toString(),
      accent: Color.accent.toString(),
      urgent: Color.urgent.toString(),
      onAccent: Color.background.toString(),
    })
    instrument.active = true
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    // The instrument is a wide, tall layout; give it as much as the screen
    // allows and let AppShell's responsive grid reflow into whatever it gets.
    contentWidth: panel.fittedContentWidth(Style.space(1020))
    contentHeight: panel.fittedContentHeight(Style.space(760))

    // Declared before the instrument so AppShell stacks above it and keeps the
    // mouse (its tab chips are MouseAreas).
    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
    }

    Loader {
      id: instrument
      active: false
      anchors.fill: parent
      source: Qt.resolvedUrl("AppShell.qml")
      onLoaded: {
        item.objectName = "exochronometerShell"
        item.allowQuit = false
        // The widget owns the BAR ANGLE preference: it can persist it in
        // shell.json, which QtCore Settings cannot do inside the shell.
        item.preferredBridge = root.hostWidget
      }
    }
  }
}