import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

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

    AppShell {
      objectName: "exochronometerShell"
      anchors.fill: parent
      allowQuit: false
    }
  }
}