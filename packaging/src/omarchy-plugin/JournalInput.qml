import QtQuick

// Port of JournalInput.swift - the snapshot-note capsule that sits under the
// circles. Submitting captures an ExoSnapshot at the current instant and files
// it in the journal; the parent owns storage.
Item {
    id: input

    signal submitted(string text)

    implicitHeight: 42

    function submit() {
        const trimmed = field.text.replace(/^\s+|\s+$/g, "")
        input.submitted(trimmed)
        field.text = ""
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.06)
        border.color: Qt.rgba(1, 1, 1, 0.15)
        border.width: 0.5

        Row {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 12
            spacing: 10

            Item {
                width: parent.width - 44
                height: parent.height
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: field.text === ""
                    text: "SNAPSHOT NOTE  \u00B7  OPTIONAL"
                    color: Qt.rgba(1, 1, 1, 0.35)
                    font.family: "monospace"
                    font.pixelSize: 11
                }

                TextInput {
                    id: field
                    anchors.fill: parent
                    verticalAlignment: TextInput.AlignVCenter
                    color: "#ffffff"
                    font.family: "monospace"
                    font.pixelSize: 13
                    selectionColor: Qt.rgba(1, 1, 1, 0.25)
                    clip: true

                    Keys.onReturnPressed: input.submit()
                    Keys.onEnterPressed: input.submit()
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\u25C9"
                color: captureArea.containsMouse
                    ? "#ffffff" : Qt.rgba(1, 1, 1, 0.8)
                font.pixelSize: 20

                MouseArea {
                    id: captureArea
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: input.submit()
                }
            }
        }
    }
}