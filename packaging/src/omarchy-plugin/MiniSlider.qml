import QtQuick

// Port of MiniSlider in HarmonicAnalysisPage.swift - a slim horizontal
// slider used by the synth options.
Item {
    id: slider

    property real value: 0
    property real from: 0
    property real to: 1
    property bool integer: false

    implicitHeight: 18
    implicitWidth: 140

    function clamp(v) {
        if (v < from) return from
        if (v > to) return to
        return integer ? Math.round(v) : v
    }

    function setFromX(x) {
        const frac = track.width > 0 ? Math.max(0, Math.min(1, x / track.width)) : 0
        slider.value = slider.clamp(slider.from + frac * (slider.to - slider.from))
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 3
        radius: 1.5
        color: Qt.rgba(1, 1, 1, 0.15)

        Rectangle {
            width: {
                const span = slider.to - slider.from
                const frac = span > 0 ? (slider.value - slider.from) / span : 0
                return parent.width * Math.max(0, Math.min(1, frac))
            }
            height: parent.height
            radius: 1.5
            color: Qt.rgba(1, 1, 1, 0.7)
        }

        Rectangle {
            x: {
                const span = slider.to - slider.from
                const frac = span > 0 ? (slider.value - slider.from) / span : 0
                return parent.width * Math.max(0, Math.min(1, frac)) - width / 2
            }
            y: (parent.height - height) / 2
            width: 9
            height: 9
            radius: 4.5
            color: "#ffffff"
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.topMargin: -6
        anchors.bottomMargin: -6
        cursorShape: Qt.PointingHandCursor
        onPressed: slider.setFromX(mouse.x)
        onPositionChanged: if (pressed) slider.setFromX(mouse.x)
    }
}