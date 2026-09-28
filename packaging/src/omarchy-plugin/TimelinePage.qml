import QtQuick

// Port of TimelineView.swift - the journal as a vertical spine, each note
// flagged on it, with the original's time-proportional spacing and zoom bar.
Item {
    id: timeline

    // Newest first, as the original's @Query(sort: .reverse) provides.
    property var notes: []

    // The original's constants.
    readonly property var zoomLevels: [0.25, 0.5, 1, 2, 4, 8]
    property int zoomIdx: 2
    readonly property real zoom: zoomLevels[zoomIdx]
    readonly property real pxPerHour: 12
    readonly property real minGap: 44
    readonly property real lineX: 30

    readonly property var monthNames:
        ["JAN","FEB","MAR","APR","MAY","JUN","JUL","AUG","SEP","OCT","NOV","DEC"]

    function pad2(n) { return (n < 10 ? "0" : "") + n }

    function dateString(ms) {
        const d = new Date(ms)
        return monthNames[d.getMonth()] + " " + d.getDate()
    }

    function timeString(ms) {
        const d = new Date(ms)
        return pad2(d.getHours()) + ":" + pad2(d.getMinutes())
    }

    /** The original's displayItems(): first row gets a fixed 24pt, later rows
     *  are spaced proportionally to the gap since the note above them. */
    function topPadFor(index) {
        if (index === 0) return 24
        const newer = notes[index - 1]
        const gapSeconds = (newer.timestamp - notes[index].timestamp) / 1000
        const gapHours = Math.max(0, gapSeconds) / 3600
        return Math.max(minGap, gapHours * pxPerHour) * zoom
    }

    function zoomLabel() {
        return zoom < 1 ? zoom + "x" : String(Math.round(zoom)) + "x"
    }

    Rectangle {
        anchors.fill: parent
        visible: timeline.notes.length === 0
        color: "transparent"

        Text {
            anchors.centerIn: parent
            text: "NO NOTES"
            color: Qt.rgba(1, 1, 1, 0.4)
            font.family: "monospace"
            font.pixelSize: 12
            font.letterSpacing: 3
        }
    }

    Flickable {
        id: scroll
        anchors.fill: parent
        visible: timeline.notes.length > 0
        contentWidth: width
        contentHeight: body.height + 80
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Item {
            id: body
            width: scroll.width
            height: col.height

            // the spine
            Rectangle {
                x: timeline.lineX
                y: 0
                width: 1
                height: body.height
                color: Qt.rgba(1, 1, 1, 0.5)
            }

            Column {
                id: col
                width: body.width

                Repeater {
                    model: timeline.notes.length

                    delegate: Column {
                        required property int index
                        width: col.width

                        Item {
                            width: 1
                            height: timeline.topPadFor(index)
                        }

                        Row {
                            spacing: 0

                            // flag: node dot on the spine + a short tick
                            Item {
                                width: 54
                                height: 16

                                Rectangle {
                                    x: timeline.lineX - 3
                                    y: 2
                                    width: 7
                                    height: 7
                                    radius: 3.5
                                    color: "#ffffff"
                                }
                                Rectangle {
                                    x: timeline.lineX + 4
                                    y: 5
                                    width: 16
                                    height: 1
                                    color: Qt.rgba(1, 1, 1, 0.5)
                                }
                            }

                            Column {
                                spacing: 2
                                width: col.width - 74

                                Row {
                                    spacing: 6
                                    Text {
                                        text: timeline.dateString(timeline.notes[index].timestamp)
                                        color: Qt.rgba(1, 1, 1, 0.35)
                                        font.family: "monospace"
                                        font.pixelSize: 8
                                        font.letterSpacing: 1.5
                                    }
                                    Text {
                                        text: timeline.timeString(timeline.notes[index].timestamp)
                                        color: Qt.rgba(1, 1, 1, 0.55)
                                        font.family: "monospace"
                                        font.pixelSize: 9
                                    }
                                }

                                Text {
                                    width: parent.width
                                    text: timeline.notes[index].text === ""
                                        ? "\u2014" : timeline.notes[index].text
                                    color: Qt.rgba(1, 1, 1, 0.85)
                                    font.family: "monospace"
                                    font.pixelSize: 13
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── zoom bar ──
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.bottomMargin: 6
        anchors.rightMargin: 4
        width: zoomRow.width + 16
        height: 30
        radius: 15
        color: Qt.rgba(1, 1, 1, 0.05)
        visible: timeline.notes.length > 0

        Row {
            id: zoomRow
            anchors.centerIn: parent
            spacing: 10

            Rectangle {
                width: 26
                height: 26
                radius: 3
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.4)
                border.width: 0.5
                opacity: timeline.zoomIdx === 0 ? 0.25 : 1

                Text {
                    anchors.centerIn: parent
                    text: "\u2212"
                    color: "#ffffff"
                    font.family: "monospace"
                    font.pixelSize: 14
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (timeline.zoomIdx > 0) timeline.zoomIdx -= 1
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: timeline.zoomLabel()
                color: Qt.rgba(1, 1, 1, 0.55)
                font.family: "monospace"
                font.pixelSize: 9
                horizontalAlignment: Text.AlignHCenter
                width: 36
            }

            Rectangle {
                width: 26
                height: 26
                radius: 3
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.4)
                border.width: 0.5
                opacity: timeline.zoomIdx === timeline.zoomLevels.length - 1 ? 0.25 : 1

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: "#ffffff"
                    font.family: "monospace"
                    font.pixelSize: 14
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (timeline.zoomIdx < timeline.zoomLevels.length - 1)
                                   timeline.zoomIdx += 1
                }
            }
        }
    }
}