import QtQuick
import QtQuick.Window
import QtCore

// The ported core, loaded as ES modules by the QML JS engine.
import "core/exoSnapshot.mjs" as Exo
import "core/timeFrame.mjs" as TF
import "core/geometry.mjs" as Geo
import "core/fadeMath.mjs" as Fade
import "core/timeLabels.mjs" as TL
import "core/peakCalendar.mjs" as PC
import "core/frequencyMath.mjs" as Freq
import "core/intervalNames.mjs" as IN
import "core/justIntonation.mjs" as JI
import "core/noteSnap.mjs" as NS

// The whole instrument, host-agnostic.
//
// Two hosts drive this component: the standalone desktop window (main.qml) and
// the Omarchy shell panel (generated into the plugin). Everything that is app
// rather than window lives here, so both hosts share one implementation. The
// only host-specific behaviour is `allowQuit`: Qt.quit() inside the shell panel
// would take the user's entire shell down with it.
Item {
    id: root

    // Standalone hosts leave this true; the shell panel sets it false.
    property bool allowQuit: true

    // 0 = Circles, 1 = Peak Calendar, 2 = Geometry Harmonics, 3 = Misc,
    // 4 = Timeline
    property int page: 0

    property var snapshot: null
    readonly property var shapes: Geo.defaultShapes

    // Swift defaults from GeometryOverlayView.
    readonly property real fadeFraction: 0.03
    readonly property real baselineMax: 0.35

    // Matches TimeCircleView.labelInset - reserves the outer ring so node date
    // labels have somewhere to sit outside the circle.
    readonly property real labelInset: 24

    readonly property real tabBarHeight: 46

    // Geometry Harmonics state (GeometryHarmonicsPage defaults to .day).
    property int harmonicsTimeframe: 3
    property bool showAllHarmonics: false

    // ── journal ────────────────────────────────────────────────────────────
    // A note is an ExoSnapshot capture: a timestamp plus the degree of every
    // timeframe at that instant, which is exactly what NoteSnap consumes. The
    // original also stores the full snapshot JSON on each note; that is omitted
    // here to keep the settings file small, since nothing reads it back.
    property var journalNotes: []

    // Snapped nodes per timeframe. Recomputed on a slow timer rather than on
    // every canvas repaint, because the circles redraw at 15 Hz.
    property var snappedNodes: []

    function journalSnapshots() {
        const out = []
        for (let i = 0; i < journalNotes.length; i++) {
            const n = journalNotes[i]
            out.push({ id: n.id, timestamp: new Date(n.timestamp), degrees: n.degrees })
        }
        return out
    }

    function recomputeSnapped() {
        const s = root.snapshot
        if (!s) return
        const notes = journalSnapshots()
        if (notes.length === 0) { snappedNodes = []; return }
        const now = new Date(s.timestamp)
        const out = []
        for (let t = 0; t < TF.allCases.length; t++) {
            out.push(NS.snap(notes, TF.allCases[t], root.shapes, 6, now))
        }
        snappedNodes = out
    }

    function saveJournal() {
        const out = []
        for (let i = 0; i < journalNotes.length; i++) {
            const n = journalNotes[i]
            out.push({ id: n.id, timestamp: n.timestamp, text: n.text, degrees: n.degrees })
        }
        journalStore.data = JSON.stringify(out)
    }

    function addNote(text) {
        const now = new Date()
        const snap = Exo.capture(now)
        const degrees = {}
        for (let i = 0; i < snap.timeframes.length; i++) {
            const e = snap.timeframes[i]
            degrees[e.timeframe] = e.degree
        }
        const note = {
            id: "n" + now.getTime() + "-" + journalNotes.length,
            timestamp: now.getTime(),
            text: text,
            degrees: degrees
        }
        journalNotes = [note].concat(journalNotes)
        saveJournal()
        recomputeSnapped()
    }

    function loadJournal() {
        try {
            journalNotes = journalStore.data === "" ? [] : JSON.parse(journalStore.data)
        } catch (e) {
            journalNotes = []
        }
        recomputeSnapped()
    }

    Settings {
        id: journalStore
        category: "exochronometer-journal"
        property string data: ""
    }

    // CirclesPage's @AppStorage("circlesPage.useSelectors"): one page-level
    // switch between the circle view and each timeframe's convergence chart.
    Settings {
        id: circlesStore
        category: "exochronometer-circles"
        property bool useSelectors: false
    }
    readonly property bool useSelectors: circlesStore.useSelectors

    // CirclesPage.refreshInterval(for:). Each indicator moves at a rate set by
    // its own cycle, so redrawing every circle at the minute hand's 15 Hz is
    // wasted work -- the year hand advances 0.033 degrees per second. These are
    // the original's own numbers.
    // CirclesPage.timeframeLabel: the selector panels' own short labels.
    function selectorTimeframeLabel(tf) {
        if (tf === "year") return "YEAR"
        if (tf === "moon") return "MOON"
        if (tf === "quarterMoon") return "QUARTER MOON"
        if (tf === "day") return "DAY"
        if (tf === "hour") return "HOUR"
        return "MINUTE"
    }

    function circleIntervalMs(tf) {
        if (tf === "minute") return 1000 / 15   // 15 Hz  - 0.4 deg/frame
        if (tf === "hour") return 500           // 2 Hz   - 0.05 deg/frame
        if (tf === "day") return 2000           // 0.5 Hz - 0.008 deg/frame
        if (tf === "quarterMoon") return 5000   // 0.2 Hz
        if (tf === "moon") return 10000         // 0.1 Hz
        return 30000                            // year   - 0.033 Hz
    }

    function refresh() {
        snapshot = Exo.capture(new Date())
    }

    Component.onCompleted: { refresh(); loadJournal() }

    // Snapping sees "now" only through the 6-cycle lookback window, and the
    // snapped nodes are drawn only on the circles page, so this runs only while
    // that page is up.
    Timer {
        interval: 1000
        running: root.page === 0
        repeat: true
        onTriggered: root.recomputeSnapped()
    }

    // The clock runs at the rate the VISIBLE page actually needs. Hidden pages
    // are gated by their own `live` property, so a static readout costs nothing.
    //   circles (0)  - minute-hand animation
    //   geometry (2) - static table, no clock
    //   timeline (4) - static journal, no clock
    readonly property int refreshMs: {
        if (page === 0) return Math.round(1000 / 15)   // circles: smooth hands
        if (page === 3) return 200                     // misc: animated views
        if (page === 5) return 500                     // spectrum: slow readout
        return 0                                       // calendar/geometry/timeline
    }

    Timer {
        interval: Math.max(1, root.refreshMs)
        running: root.refreshMs > 0
        repeat: true
        onTriggered: root.refresh()
    }

    // Arriving on a page shows current data at once, not up to a tick later.
    onPageChanged: { refresh(); recomputeSnapped() }

    // ─────────────────────────── tab bar ───────────────────────────
    // Horizontally scrollable: the bar outgrows a narrow window, and a clipped
    // tab silently loses navigation.
    Flickable {
        id: tabScroll
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 14
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        height: 24
        contentWidth: tabBar.width
        contentHeight: height
        clip: true
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds

    Row {
        id: tabBar
        spacing: 8

        Repeater {
            model: ["CIRCLES", "PEAK CALENDAR", "GEOMETRY HARMONICS", "MISC", "TIMELINE", "SPECTRUM"]
            delegate: Rectangle {
                required property int index
                required property string modelData

                width: tabLabel.width + 20
                height: 24
                radius: 12
                color: root.page === index ? Qt.rgba(1, 1, 1, 0.9) : "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.3)
                border.width: 0.5

                Text {
                    id: tabLabel
                    anchors.centerIn: parent
                    text: modelData
                    font.family: "monospace"
                    font.pixelSize: 9
                    font.letterSpacing: 2
                    color: root.page === index ? "#0d0d11" : Qt.rgba(1, 1, 1, 0.6)
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.page = index
                }
            }
        }
    }
    }

    // ─────────────────────── page: circles ────────────────────────
    Flickable {
        id: flick
        anchors.fill: parent
        anchors.topMargin: root.tabBarHeight + 14
        contentWidth: width
        contentHeight: grid.height + 100
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: root.page === 0

        // CirclesPage.modeToggle: CIRCLES | SELECTORS.
        Row {
            id: circlesMode
            x: 20
            y: 0
            spacing: 8

            Repeater {
                model: ["CIRCLES", "SELECTORS"]
                delegate: Rectangle {
                    id: modeChip
                    required property int index
                    required property string modelData
                    readonly property bool active: (index === 1) === root.useSelectors
                    width: modeChipText.width + 20
                    height: 24
                    radius: 12
                    color: active ? Qt.rgba(1, 1, 1, 0.9) : "transparent"
                    border.color: Qt.rgba(1, 1, 1, 0.3)
                    border.width: 0.5

                    Text {
                        id: modeChipText
                        anchors.centerIn: parent
                        text: modeChip.modelData
                        font.family: "monospace"
                        font.pixelSize: 9
                        font.letterSpacing: 2
                        color: modeChip.active ? "#0d0d11" : Qt.rgba(1, 1, 1, 0.6)
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: circlesStore.useSelectors = (modeChip.index === 1)
                    }
                }
            }
        }

        // Six SEPARATE circles, one per timeframe.
        Grid {
            id: grid
            x: 20
            y: circlesMode.height + 14
            width: flick.width - 40
            spacing: 24
            // SELECTORS panels are the same size as the circles and sit in the
            // same grid, so all six are visible at once. (The original stacks
            // them vertically one per row; this keeps the grid instead.)
            columns: width >= 560 ? 3 : (width >= 380 ? 2 : 1)
            readonly property real cellW: (width - spacing * (columns - 1)) / columns

            Repeater {
                model: TF.allCases.length

                delegate: Item {
                    id: cell
                    width: grid.cellW
                    height: grid.cellW + 40

                    readonly property string tf: TF.allCases[index]

                    Text {
                        id: circleLabel
                        visible: !root.useSelectors
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: Qt.rgba(1, 1, 1, 0.85)
                        font.family: "monospace"
                        font.pixelSize: 11
                        font.letterSpacing: 3
                        text: TF.label(cell.tf)
                    }

                    Text {
                        id: circleSublabel
                        visible: !root.useSelectors
                        anchors.top: circleLabel.bottom
                        anchors.topMargin: 3
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: Qt.rgba(1, 1, 1, 0.4)
                        font.family: "monospace"
                        font.pixelSize: 9
                        text: TF.sublabel(cell.tf)
                    }

                    Canvas {
                        id: circleCanvas
                        visible: !root.useSelectors
                        property real lastPaintMs: 0
                        anchors.top: circleSublabel.bottom
                        anchors.topMargin: 8
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(cell.width, cell.height - 40)
                        height: width

                        Connections {
                            target: root
                            function onSnapshotChanged() {
                                if (root.page !== 0 || root.useSelectors) return
                                // Honour this timeframe's own redraw rate: the
                                // page clock runs at the minute hand's 15 Hz.
                                const now = Date.now()
                                if (now - circleCanvas.lastPaintMs
                                        < root.circleIntervalMs(cell.tf)) return
                                circleCanvas.lastPaintMs = now
                                circleCanvas.requestPaint()
                            }
                            function onPageChanged() {
                                if (root.page === 0) circleCanvas.requestPaint()
                            }
                            function onUseSelectorsChanged() {
                                if (root.page === 0 && !root.useSelectors) {
                                    circleCanvas.requestPaint()
                                }
                            }
                        }

                        Component.onCompleted: requestPaint()

                        function pointAt(cx, cy, r, deg) {
                            const a = (deg - 90) * Math.PI / 180
                            return { x: cx + r * Math.cos(a), y: cy + r * Math.sin(a) }
                        }

                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset()

                            const snap = root.snapshot
                            if (!snap) return

                            const tfs = snap.timeframes[index]
                            const now = new Date(snap.timestamp)

                            const cx = width / 2
                            const cy = height / 2
                            const r = Math.min(width, height) / 2
                                      - Math.min(root.labelInset, width * 0.09)

                            ctx.lineCap = "round"

                            ctx.beginPath()
                            ctx.arc(cx, cy, r, 0, Math.PI * 2)
                            ctx.strokeStyle = "rgba(255,255,255,0.55)"
                            ctx.lineWidth = 1
                            ctx.stroke()

                            // inscribed {n/k} geometry, breathing
                            const state = Fade.timeframeState(cell.tf, now)

                            for (let s = 0; s < root.shapes.length; s++) {
                                const shape = root.shapes[s]
                                const n = shape.divisions

                                const act = []
                                let peak = 0
                                for (let v = 0; v < n; v++) {
                                    const a = Fade.nodeActivation(shape, v, state, root.fadeFraction)
                                    act[v] = a
                                    if (a > peak) peak = a
                                }
                                if (peak <= 0.001) continue

                                const base = root.baselineMax * peak

                                for (let e = 0; e < shape.path.length; e++) {
                                    const edge = shape.path[e]
                                    const alpha = Math.max(base, Math.max(act[edge.from], act[edge.to]))
                                    if (alpha <= 0.002) continue

                                    const a0 = (edge.from / n) * Math.PI * 2 - Math.PI / 2
                                    const a1 = (edge.to / n) * Math.PI * 2 - Math.PI / 2
                                    ctx.beginPath()
                                    ctx.moveTo(cx + r * Math.cos(a0), cy + r * Math.sin(a0))
                                    ctx.lineTo(cx + r * Math.cos(a1), cy + r * Math.sin(a1))
                                    ctx.strokeStyle = "rgba(232,184,75," + alpha.toFixed(3) + ")"
                                    ctx.lineWidth = 0.6 + 0.8 * alpha
                                    ctx.stroke()
                                }

                                for (let v = 0; v < n; v++) {
                                    if (act[v] <= 0.01) continue
                                    const p = pointAt(cx, cy, r, (v / n) * 360)
                                    ctx.beginPath()
                                    ctx.arc(p.x, p.y, 1.5 + 2.5 * act[v], 0, Math.PI * 2)
                                    ctx.fillStyle = "rgba(232,184,75," + act[v].toFixed(3) + ")"
                                    ctx.fill()
                                }
                            }

                            // indicator dot
                            const dp = pointAt(cx, cy, r, tfs.degree)
                            ctx.beginPath()
                            ctx.arc(dp.x, dp.y, 8, 0, Math.PI * 2)
                            ctx.strokeStyle = "rgba(255,255,255,0.6)"
                            ctx.lineWidth = 1
                            ctx.stroke()
                            ctx.beginPath()
                            ctx.arc(dp.x, dp.y, 4, 0, Math.PI * 2)
                            ctx.fillStyle = "#ffffff"
                            ctx.fill()

                            // Journal note nodes (NoteSnap): a black disc with a
                            // white ring, holding either the note count or a
                            // single dot, faded by the breathing node opacity.
                            if (root.snappedNodes.length > index) {
                                const sNodes = root.snappedNodes[index]
                                for (let si = 0; si < sNodes.length; si++) {
                                    const node = sNodes[si]
                                    const op = NS.nodeOpacity(
                                        node.degree, tfs.degree,
                                        root.shapes, root.fadeFraction)
                                    if (op <= 0.001) continue

                                    const np = pointAt(cx, cy, r, node.degree)
                                    ctx.beginPath()
                                    ctx.arc(np.x, np.y, 6, 0, Math.PI * 2)
                                    ctx.fillStyle = "rgba(0,0,0," + op.toFixed(3) + ")"
                                    ctx.fill()
                                    ctx.beginPath()
                                    ctx.arc(np.x, np.y, 6, 0, Math.PI * 2)
                                    ctx.strokeStyle = "rgba(255,255,255," + (0.95 * op).toFixed(3) + ")"
                                    ctx.lineWidth = 1
                                    ctx.stroke()

                                    if (node.noteIDs.length > 1) {
                                        ctx.textAlign = "center"
                                        ctx.textBaseline = "middle"
                                        ctx.font = "bold 7px monospace"
                                        ctx.fillStyle = "rgba(255,255,255," + op.toFixed(3) + ")"
                                        ctx.fillText(String(node.noteIDs.length), np.x, np.y)
                                    } else {
                                        ctx.beginPath()
                                        ctx.arc(np.x, np.y, 1.5, 0, Math.PI * 2)
                                        ctx.fillStyle = "rgba(255,255,255," + op.toFixed(3) + ")"
                                        ctx.fill()
                                    }
                                }
                            }

                            // traditionalLabel centred
                            ctx.textAlign = "center"
                            ctx.font = "14px monospace"
                            ctx.fillStyle = "rgba(255,255,255,0.7)"
                            ctx.fillText(tfs.traditionalLabel, cx, cy + 5)

                            ctx.font = "9px monospace"
                            ctx.fillStyle = "rgba(255,255,255,0.35)"
                            ctx.fillText(tfs.degree.toFixed(2) + "\u00B0", cx, cy + 22)

                            // node date labels outside the circle
                            const nodes = TL.activeNodeDegrees(tfs.degree, root.fadeFraction)
                            const labelRadius = Math.min(width, height) / 2 - 9
                            ctx.font = "8px monospace"
                            ctx.textAlign = "center"
                            ctx.textBaseline = "middle"
                            for (let ni = 0; ni < nodes.length; ni++) {
                                const node = nodes[ni]
                                const nd = TL.nodeDateMs(node.degree, cell.tf, now)
                                const text = TL.nodeLabel(cell.tf, new Date(Math.round(nd)))
                                const np = pointAt(cx, cy, labelRadius, node.degree)
                                ctx.fillStyle = "rgba(255,255,255," + (node.opacity * 0.85).toFixed(3) + ")"
                                ctx.fillText(text, np.x, np.y)
                            }
                            ctx.textBaseline = "alphabetic"
                        }
                    }

                    // CirclesPage.selectorPanel: this timeframe's convergence
                    // chart, in place of its circle.
                    Column {
                        anchors.fill: parent
                        spacing: 6
                        visible: root.useSelectors

                        Text {
                            width: parent.width
                            text: root.selectorTimeframeLabel(cell.tf) + "  \u00B7  CONVERGENCE"
                            // A narrow cell cannot fit the longest label; elide
                            // rather than let it run into the neighbouring panel.
                            elide: Text.ElideRight
                            color: Qt.rgba(1, 1, 1, 0.85)
                            font.family: "monospace"
                            font.pixelSize: 10
                            font.letterSpacing: 3
                        }

                        SelectorView {
                            width: parent.width
                            height: parent.height - 24
                            selectedTimeframe: cell.tf
                            snapshot: root.snapshot
                            live: root.page === 0 && root.useSelectors
                        }
                    }
                }
            }
        }

        // JournalInput() - the snapshot-note capsule, under the circles.
        JournalInput {
            id: journalInput
            x: 20
            width: flick.width - 40
            y: grid.y + grid.height + 18
            onSubmitted: root.addNote(text)
        }
    }

    // ──────────────────── page: peak calendar ─────────────────────
    Flickable {
        id: peakFlick
        anchors.fill: parent
        anchors.topMargin: root.tabBarHeight + 14
        contentWidth: width
        contentHeight: peakGrid.height + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: root.page === 1

        // Open on the current month rather than at the top of a 22-month
        // scroll: centre the current card, clamped so it never scrolls past
        // the end (a month near the bottom then lands at the bottom instead).
        function scrollToCurrentMonth() {
            const s = root.snapshot
            if (!s) return
            const pos = PC.position(new Date(s.timestamp))
            const card = peakRepeater.itemAt(pos.monthIndex)
            if (!card) return
            const maxY = Math.max(0, contentHeight - height)
            const target = card.y + card.height / 2 - height / 2
            contentY = Math.max(0, Math.min(target, maxY))
        }

        onVisibleChanged: if (visible) settleTimer.start()

        // The grid has not been laid out on the same turn the page appears.
        Timer {
            id: settleTimer
            interval: 1
            running: false
            repeat: false
            onTriggered: peakFlick.scrollToCurrentMonth()
        }

        Column {
            id: peakHeaderCol
            x: 20
            y: 0
            width: peakFlick.width - 40

            Text {
                color: Qt.rgba(1, 1, 1, 0.6)
                font.family: "monospace"
                font.pixelSize: 10
                font.letterSpacing: 3
                text: "PEAK CALENDAR"
            }

            Text {
                color: Qt.rgba(1, 1, 1, 0.35)
                font.family: "monospace"
                font.pixelSize: 9
                text: {
                    const s = root.snapshot
                    if (!s) return ""
                    const pos = PC.position(new Date(s.timestamp))
                    const cur = PC.months[pos.monthIndex]
                    return cur.name.toUpperCase() + " \u00B7 DAY " + pos.dayOfMonth
                           + " OF " + cur.dayCount
                           + "  \u00B7  22 months between geometric peaks"
                }
            }
        }

        Grid {
            id: peakGrid
            x: 20
            y: peakHeaderCol.height + 12
            width: peakFlick.width - 40
            spacing: 14
            columns: width >= 900 ? 3 : (width >= 560 ? 2 : 1)
            readonly property real cardW: (width - spacing * (columns - 1)) / columns

            Repeater {
                id: peakRepeater
                model: PC.months.length

                delegate: Rectangle {
                    id: card
                    required property int index

                    readonly property var month: PC.months[index]
                    // Gated on the page: the cards only track "today" while
                    // the calendar is actually on screen.
                    readonly property var pos: (root.page === 1 && root.snapshot)
                        ? PC.position(new Date(root.snapshot.timestamp))
                        : null
                    readonly property bool isCurrent: pos ? pos.monthIndex === index : false
                    readonly property int highlightedDay: isCurrent ? pos.dayOfMonth : -1

                    readonly property real pad: 10
                    readonly property real gap: 3
                    readonly property real dayCell: (width - 2 * pad - 6 * gap) / 7
                    readonly property int rows: Math.ceil(month.dayCount / 7)

                    width: peakGrid.cardW
                    height: pad + 20 + 4 + 14 + 6 + rows * dayCell + (rows - 1) * gap + pad

                    radius: 10
                    color: isCurrent ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.02)
                    border.color: isCurrent ? Qt.rgba(1, 1, 1, 0.5) : Qt.rgba(1, 1, 1, 0.12)
                    border.width: isCurrent ? 1 : 0.5

                    Text {
                        x: card.pad
                        y: card.pad
                        text: card.month.number
                        color: Qt.rgba(1, 1, 1, 0.3)
                        font.family: "monospace"
                        font.pixelSize: 11
                    }
                    Text {
                        x: card.pad + 22
                        y: card.pad - 3
                        text: card.month.name
                        color: Qt.rgba(1, 1, 1, card.isCurrent ? 0.95 : 0.7)
                        font.family: "monospace"
                        font.pixelSize: 16
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: card.pad
                        y: card.pad + 2
                        text: card.month.shorthand
                        color: Qt.rgba(1, 1, 1, 0.45)
                        font.family: "monospace"
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }
                    Text {
                        x: card.pad
                        y: card.pad + 20 + 4
                        text: card.month.lengthDays.toFixed(1) + " d   opens "
                              + card.month.fractionLabel + " \u00B7 "
                              + Math.round(card.month.openingDegree) + "\u00B0"
                        color: Qt.rgba(1, 1, 1, 0.35)
                        font.family: "monospace"
                        font.pixelSize: 9
                    }

                    Grid {
                        x: card.pad
                        y: card.pad + 20 + 4 + 14 + 6
                        columns: 7
                        spacing: card.gap

                        Repeater {
                            model: card.month.dayCount

                            delegate: Rectangle {
                                required property int index
                                readonly property int day: index + 1
                                readonly property bool isToday: day === card.highlightedDay

                                width: card.dayCell
                                height: card.dayCell
                                radius: 3
                                color: isToday ? Qt.rgba(1, 1, 1, 1) : Qt.rgba(1, 1, 1, 0.06)

                                Text {
                                    anchors.centerIn: parent
                                    text: parent.day
                                    color: parent.isToday ? "#0d0d11" : Qt.rgba(1, 1, 1, 0.5)
                                    font.family: "monospace"
                                    font.pixelSize: Math.max(6, card.dayCell * 0.55)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ─────────────── page: geometry harmonics ─────────────────────
    // Mirrors GeometryHarmonicsPage: a timeframe selector, an ALL HARMONICS
    // toggle, then one row per shape showing its polygon, ratio, period and
    // named interval - or, with the toggle on, the full frequency/period/JI
    // table for every timeframe.
    Flickable {
        id: harmFlick
        anchors.fill: parent
        anchors.topMargin: root.tabBarHeight + 14
        contentWidth: width
        contentHeight: harmCol.height + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: root.page === 2

        Column {
            id: harmCol
            x: 20
            y: 0
            width: harmFlick.width - 40
            spacing: 12

            // --- timeframe selector (3-column capsule grid) ---
            Grid {
                width: parent.width
                columns: 3
                spacing: 6

                Repeater {
                    model: TF.allCases.length
                    delegate: Rectangle {
                        required property int index
                        readonly property string tf: TF.allCases[index]

                        width: (harmCol.width - 12) / 3
                        height: 26
                        radius: 13
                        color: root.harmonicsTimeframe === index
                            ? Qt.rgba(1, 1, 1, 1) : "transparent"
                        border.color: Qt.rgba(1, 1, 1, 0.3)
                        border.width: 0.5

                        Text {
                            anchors.centerIn: parent
                            text: TF.label(parent.tf)
                            font.family: "monospace"
                            font.pixelSize: 9
                            font.letterSpacing: 2
                            color: root.harmonicsTimeframe === index
                                ? "#0d0d11" : Qt.rgba(1, 1, 1, 0.7)
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.harmonicsTimeframe = parent.index
                        }
                    }
                }
            }

            // --- ALL HARMONICS toggle ---
            Rectangle {
                x: harmCol.width - width
                width: allLabel.width + 24
                height: 24
                radius: 12
                color: root.showAllHarmonics ? Qt.rgba(1, 1, 1, 0.9) : "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.4)
                border.width: 0.5

                Text {
                    id: allLabel
                    anchors.centerIn: parent
                    text: "ALL HARMONICS"
                    font.family: "monospace"
                    font.pixelSize: 9
                    font.letterSpacing: 2
                    color: root.showAllHarmonics ? "#0d0d11" : Qt.rgba(1, 1, 1, 0.85)
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showAllHarmonics = !root.showAllHarmonics
                }
            }

            // --- caption (only in the ALL HARMONICS view) ---
            Text {
                visible: root.showAllHarmonics
                color: Qt.rgba(1, 1, 1, 0.45)
                font.family: "monospace"
                font.pixelSize: 9
                text: "frequency \u00B7 period \u00B7 closest 5-limit JI note vs A=432 Hz"
            }

            // --- single-timeframe rows ---
            Column {
                width: parent.width
                spacing: 12
                visible: !root.showAllHarmonics

                Repeater {
                    model: root.shapes.length

                    delegate: Item {
                        id: hrow
                        required property int index
                        readonly property var shape: root.shapes[index]
                        // harmonicPeriodSeconds, as in HarmonicRow
                        readonly property real period:
                            TF.cycleDuration(TF.allCases[root.harmonicsTimeframe])
                            * shape.skip / shape.divisions

                        width: harmCol.width
                        height: 64

                        Canvas {
                            id: poly
                            x: 0
                            y: 4
                            width: 56
                            height: 56
                            property var shp: hrow.shape

                            onShpChanged: poly.requestPaint()
                            Component.onCompleted: requestPaint()

                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.reset()
                                const s = poly.shp
                                if (!s) return

                                const c = width / 2
                                const rad = Math.min(width, height) / 2

                                ctx.beginPath()
                                ctx.arc(c, c, rad, 0, Math.PI * 2)
                                ctx.strokeStyle = "rgba(255,255,255,0.35)"
                                ctx.lineWidth = 0.6
                                ctx.stroke()

                                const pt = (i) => {
                                    const a = (i / s.divisions) * Math.PI * 2 - Math.PI / 2
                                    return { x: c + rad * Math.cos(a), y: c + rad * Math.sin(a) }
                                }
                                ctx.beginPath()
                                ctx.strokeStyle = "rgba(255,255,255,0.9)"
                                ctx.lineWidth = 1
                                for (let e = 0; e < s.path.length; e++) {
                                    const a = pt(s.path[e].from)
                                    const b = pt(s.path[e].to)
                                    ctx.moveTo(a.x, a.y)
                                    ctx.lineTo(b.x, b.y)
                                }
                                ctx.stroke()
                            }
                        }

                        Column {
                            x: 72
                            y: 4
                            spacing: 5

                            Row {
                                spacing: 10
                                Text {
                                    text: hrow.shape.divisions + ":" + hrow.shape.skip
                                    color: "#ffffff"
                                    font.family: "monospace"
                                    font.pixelSize: 18
                                    font.weight: Font.Medium
                                }
                                Text {
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 4
                                    text: IN.shapeName(hrow.shape.divisions, hrow.shape.skip)
                                    color: Qt.rgba(1, 1, 1, 0.5)
                                    font.family: "monospace"
                                    font.pixelSize: 9
                                    font.letterSpacing: 2
                                }
                            }

                            Text {
                                text: "period: " + Freq.formatDuration(hrow.period)
                                color: Qt.rgba(1, 1, 1, 0.7)
                                font.family: "monospace"
                                font.pixelSize: 11
                            }

                            Text {
                                text: "interval: "
                                      + IN.intervalName(hrow.shape.divisions, hrow.shape.skip)
                                      + " (" + hrow.shape.divisions + ":" + hrow.shape.skip + ")"
                                color: Qt.rgba(1, 1, 1, 0.55)
                                font.family: "monospace"
                                font.pixelSize: 10
                            }
                        }
                    }
                }
            }

            // --- ALL HARMONICS: every timeframe x every shape ---
            Column {
                width: parent.width
                spacing: 22
                visible: root.showAllHarmonics

                Repeater {
                    model: TF.allCases.length

                    delegate: Column {
                        id: tfSection
                        required property int index
                        readonly property string tf: TF.allCases[index]
                        width: harmCol.width
                        spacing: 0

                        Row {
                            width: parent.width
                            Text {
                                text: TF.label(tfSection.tf)
                                color: Qt.rgba(1, 1, 1, 0.7)
                                font.family: "monospace"
                                font.pixelSize: 10
                                font.letterSpacing: 3
                            }
                            Item {
                                width: tfSection.width - TF.label(tfSection.tf).length * 8 - 120
                                height: 1
                            }
                            Text {
                                text: TF.sublabel(tfSection.tf)
                                color: Qt.rgba(1, 1, 1, 0.4)
                                font.family: "monospace"
                                font.pixelSize: 8
                            }
                        }

                        Repeater {
                            model: root.shapes.length

                            delegate: Item {
                                id: arow
                                required property int index
                                readonly property var shape: root.shapes[index]
                                readonly property real period:
                                    TF.cycleDuration(tfSection.tf) * shape.skip / shape.divisions
                                readonly property real frequency: period > 0 ? 1 / period : 0
                                readonly property var ji: JI.closestNote(frequency)
                                readonly property string cents:
                                    (ji.centsDelta >= 0 ? "+" : "")
                                    + ji.centsDelta.toFixed(1) + "\u00A2"

                                width: tfSection.width
                                height: 34

                                Text {
                                    x: 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 44
                                    text: arow.shape.divisions + ":" + arow.shape.skip
                                    color: "#ffffff"
                                    font.family: "monospace"
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                }

                                Column {
                                    x: 56
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    Text {
                                        text: Freq.format(arow.frequency)
                                        color: Qt.rgba(1, 1, 1, 0.85)
                                        font.family: "monospace"
                                        font.pixelSize: 11
                                    }
                                    Text {
                                        text: "period: " + Freq.formatDuration(arow.period)
                                        color: Qt.rgba(1, 1, 1, 0.5)
                                        font.family: "monospace"
                                        font.pixelSize: 9
                                    }
                                }

                                Column {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    Text {
                                        anchors.right: parent.right
                                        text: arow.ji.noteName
                                        color: "#ffffff"
                                        font.family: "monospace"
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                    }
                                    Text {
                                        anchors.right: parent.right
                                        text: arow.cents
                                        color: Qt.rgba(1, 1, 1, 0.55)
                                        font.family: "monospace"
                                        font.pixelSize: 9
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 1
                                    anchors.bottom: parent.bottom
                                    color: Qt.rgba(1, 1, 1, 0.08)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ──────────────────────── page: misc ──────────────────────────
    // Dissonance meters (MiscPage's Dissonance mode). Lives in its own
    // component file to keep this one readable.
    MiscPage {
        id: miscPage
        anchors.fill: parent
        anchors.topMargin: root.tabBarHeight + 14
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.bottomMargin: 44
        visible: root.page === 3
        live: root.page === 3
        snapshot: root.snapshot
    }

    // ──────────────────────── page: timeline ──────────────────────
    TimelinePage {
        id: timelinePage
        anchors.fill: parent
        anchors.topMargin: root.tabBarHeight + 14
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.bottomMargin: 44
        visible: root.page === 4
        notes: root.journalNotes
    }

    // ──────────────────────── page: spectrum ──────────────────────
    HarmonicSpectrumPage {
        id: spectrumPage
        anchors.fill: parent
        anchors.topMargin: root.tabBarHeight + 14
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.bottomMargin: 44
        visible: root.page === 5
        live: root.page === 5
        snapshot: root.snapshot
    }

    // ─────────────────────────── footer ───────────────────────────
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: 14
        width: legend.width + 24
        height: legend.height + 12
        radius: 6
        // QML color properties do not parse CSS rgba() strings - use Qt.rgba().
        color: Qt.rgba(1, 1, 1, 0.04)
        border.color: Qt.rgba(1, 1, 1, 0.08)

        Text {
            id: legend
            anchors.centerIn: parent
            color: Qt.rgba(0.87, 0.89, 0.92, 0.6)
            font.family: "monospace"
            font.pixelSize: 11
            text: {
                const s = root.snapshot
                const tz = s ? s.timezoneIdentifier : "\u2014"
                return "A432 JI  \u2022  [tab] page  \u2022  " + tz
            }
        }
    }

    Shortcut { sequence: "Tab"; onActivated: root.page = (root.page + 1) % 6 }
    Shortcut { sequence: "1"; onActivated: root.page = 0 }
    Shortcut { sequence: "2"; onActivated: root.page = 1 }
    Shortcut { sequence: "3"; onActivated: root.page = 2 }
    Shortcut { sequence: "4"; onActivated: root.page = 3 }
    Shortcut { sequence: "5"; onActivated: root.page = 4 }
    Shortcut { sequence: "6"; onActivated: root.page = 5 }
    Shortcut { sequence: "q"; enabled: root.allowQuit; onActivated: Qt.quit() }
    Shortcut { sequence: "Escape"; enabled: root.allowQuit; onActivated: Qt.quit() }
}
