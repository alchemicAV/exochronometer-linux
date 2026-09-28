import QtQuick
import QtQuick.Window
import "core/theme.mjs" as Theme

// Thin host: the standalone desktop window. All the app lives in AppShell.qml so
// the Omarchy shell panel can host exactly the same instrument.
//
// The palette is configured HERE, before the instrument is loaded: a JS module's
// exports are not observable, so every view must read a palette that is already
// final. That is why AppShell goes through a Loader instead of being a direct
// child - the Loader is only activated once the colours are in place.
Window {
    id: window

    width: 1180
    height: 940
    visible: true
    color: Theme.background()
    title: "Exochronometer"

    Component.onCompleted: {
        // The launcher reads the Omarchy theme and passes it in; QML cannot read
        // files here. Falls back to Theme's own defaults with no theme present.
        Theme.configureFromArgs(Qt.application.arguments)
        color = Theme.background()
        shell.active = true
    }

    Loader {
        id: shell
        anchors.fill: parent
        active: false
        source: "AppShell.qml"
    }
}