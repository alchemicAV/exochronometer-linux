import QtQuick
import QtCore

// Port of HarmonicAnalysisPage.swift - the live harmonic spectrum: which tones
// the timeframes are currently sounding, drawn as a frequency-axis chart with a
// composite-waveform scope beneath.
//
// The audio engine (`HarmonicAudio` / AVFoundation) is genuinely absent on this
// platform, so the AUDIO toggle, the volume row and the audio push are dropped.
// Everything visual is ported, and the SYNTH panel still edits `SynthParams`
// and persists them - the knobs are simply not heard.
import "core/timeFrame.mjs" as TF
import "core/geometry.mjs" as Geo
import "core/fadeMath.mjs" as Fade
import "core/frequencyMath.mjs" as Freq
import "core/synthParams.mjs" as SP

Item {
    id: page

    property var snapshot: null
    property bool fundamentalsOff: true

    // False unless this page is the one on screen.
    property bool live: true

    // 0 = lo (2^23), 1 = hi (2^26), 2 = merged. HarmonicAnalysisPage opens merged.
    property int scaleMode: 2
    property bool useLogScale: true
    property bool showSynth: false
    property var excluded: []

    property var params: SP.makeSynthParams()
    property string debugText: ""

    readonly property var orderedTimeframes: ["hour", "day", "quarterMoon", "moon", "year"]

    Settings {
        id: synthStore
        category: "exochronometer-synth"
        property string data: ""
    }

    Component.onCompleted: loadParams()

    // ── scale modes (ScaleMode in the original) ──────────────────────────────

    function assignments() {
        if (scaleMode === 0) {
            return [
                { timeframe: "hour", scale: 23 }, { timeframe: "day", scale: 23 },
                { timeframe: "quarterMoon", scale: 23 }, { timeframe: "moon", scale: 23 },
                { timeframe: "year", scale: 23 }
            ]
        }
        if (scaleMode === 1) {
            return [
                { timeframe: "hour", scale: 26 }, { timeframe: "day", scale: 26 },
                { timeframe: "quarterMoon", scale: 26 }, { timeframe: "moon", scale: 26 },
                { timeframe: "year", scale: 26 }
            ]
        }
        return [
            { timeframe: "hour", scale: 23 }, { timeframe: "day", scale: 26 },
            { timeframe: "quarterMoon", scale: 28 }, { timeframe: "moon", scale: 29 },
            { timeframe: "year", scale: 29 }
        ]
    }

    function scaleLabel() {
        return scaleMode === 0 ? "2^23" : (scaleMode === 1 ? "2^26" : "MERGED")
    }

    function minFreqHz() {
        return scaleMode === 0 ? 0.1 : (scaleMode === 1 ? 1 : 15)
    }

    function maxFreqHz() {
        return scaleMode === 0 ? 50000 : (scaleMode === 1 ? 200000 : 50000)
    }

    function headerSubtitle() {
        const t = scaleMode === 0 ? "\u00D7 2^23"
                : (scaleMode === 1 ? "\u00D7 2^26" : "HR:23 \u00B7 DY:26 \u00B7 QM:28 \u00B7 MN/YR:29")
        return t + "  \u00B7  minute excluded"
    }

    function cycleScale() {
        scaleMode = (scaleMode + 1) % 3
    }

    function isExcluded(tf) { return excluded.indexOf(tf) >= 0 }

    function toggleExcluded(tf) {
        const out = []
        for (let i = 0; i < excluded.length; i++) if (excluded[i] !== tf) out.push(excluded[i])
        if (out.length === excluded.length) out.push(tf)
        excluded = out
    }

    // ── tone generation (activeTones) ────────────────────────────────────────

    function toneState(amp, nextAmp) {
        if (amp > 0.95 && Math.abs(nextAmp - amp) < 0.02) return 1     // peak
        if (nextAmp > amp) return 0                                    // waxing
        if (nextAmp < amp) return 2                                    // waning
        return 1
    }

    function stateLabel(s) {
        return s === 0 ? "WAXING" : (s === 2 ? "WANING" : "PEAK")
    }

    function divisionLabel(t) {
        return t.skip === 1 ? String(t.divisions) : t.divisions + "/" + t.skip
    }

    function activeTones(date) {
        const out = []
        const asg = assignments()
        for (let a = 0; a < asg.length; a++) {
            const tf = asg[a].timeframe
            const sc = asg[a].scale
            const factor = Math.pow(2, sc)
            const fundamental = (1 / TF.cycleDuration(tf)) * factor
            const degree = TF.degree(tf, date)
            const nextDegree = degree + 1

            out.push({
                timeframe: tf, divisions: 1, skip: 1, octaves: sc,
                frequency: fundamental, amplitude: 1.0, state: 1
            })

            for (let div = 3; div <= 8; div++) {
                const amp = Fade.shapeOpacity(degree, div)
                if (amp > 0.01) {
                    const nextAmp = Fade.shapeOpacity(nextDegree, div)
                    out.push({
                        timeframe: tf, divisions: div, skip: 1, octaves: sc,
                        frequency: fundamental * div, amplitude: amp,
                        state: toneState(amp, nextAmp)
                    })
                }
            }

            // Winding tones ({7/3}, {8/3}) - distinct pitch classes.
            const state = Fade.timeframeState(tf, date)
            const nextDate = new Date(date.getTime() + (TF.cycleDuration(tf) / 360) * 1000)
            const nextState = Fade.timeframeState(tf, nextDate)
            for (let si = 0; si < Geo.defaultShapes.length; si++) {
                const shape = Geo.defaultShapes[si]
                if (Geo.oddPart(shape.skip) <= 1) continue
                let amp = 0.0
                let nextAmp = 0.0
                for (let v = 0; v < shape.divisions; v++) {
                    amp = Math.max(amp, Fade.nodeActivation(shape, v, state))
                    nextAmp = Math.max(nextAmp, Fade.nodeActivation(shape, v, nextState))
                }
                if (amp > 0.01) {
                    out.push({
                        timeframe: tf, divisions: shape.divisions, skip: shape.skip,
                        octaves: sc,
                        frequency: fundamental * shape.divisions / shape.skip,
                        amplitude: amp, state: toneState(amp, nextAmp)
                    })
                }
            }
        }
        return out
    }

    function displayedTones(date) {
        const all = activeTones(date)
        const active = []
        for (let i = 0; i < all.length; i++) {
            if (!isExcluded(all[i].timeframe)) active.push(all[i])
        }
        const out = []
        for (let i = 0; i < active.length; i++) {
            if (fundamentalsOff && active[i].divisions === 1) continue
            out.push(active[i])
        }
        return out
    }

    // ── axis helpers ─────────────────────────────────────────────────────────

    function decadeValues(lo, hi) {
        const h = Math.log(hi) / Math.LN10
        const values = []
        let n = Math.floor(Math.log(lo) / Math.LN10)
        while (Math.pow(10, n) < lo - 1e-12) n += 1
        while (n <= h + 1e-12) { values.push(Math.pow(10, n)); n += 1 }
        return values
    }

    function decadeLabel(v) {
        if (v >= 1000000) return String(Math.round(v / 1000000)) + "M"
        if (v >= 1000) return String(Math.round(v / 1000)) + "k"
        if (v >= 1) return String(Math.round(v))
        return String(v)
    }

    function linearTicks(lo, hi, count) {
        const n = Math.max(2, count)
        const step = (hi - lo) / (n - 1)
        const out = []
        for (let i = 0; i < n; i++) out.push(lo + i * step)
        return out
    }

    function compactName(tf) {
        if (tf === "year") return "YEAR"
        if (tf === "moon") return "MOON"
        if (tf === "quarterMoon") return "QTR"
        if (tf === "day") return "DAY"
        if (tf === "hour") return "HOUR"
        return "MIN"
    }

    function shortTimeframeLabel(tf) {
        if (tf === "year") return "YEAR"
        if (tf === "moon") return "MOON"
        if (tf === "quarterMoon") return "QTR"
        if (tf === "day") return "DAY"
        if (tf === "hour") return "HOUR"
        return "MIN"
    }

    // ── synth params ─────────────────────────────────────────────────────────

    function saveParams() {
        synthStore.data = JSON.stringify(params)
    }

    function loadParams() {
        if (synthStore.data === "") return
        try {
            const raw = JSON.parse(synthStore.data)
            const base = SP.makeSynthParams()
            for (const k in raw) base[k] = raw[k]
            params = base
        } catch (e) {
            debugText = "synth params unreadable"
        }
    }

    // Copy-on-write so QML notices the change (mutating a field of a `var`
    // property's object does not notify bindings).
    function setParam(key, value) {
        const next = SP.makeSynthParams()
        for (const k in params) next[k] = params[k]
        next[key] = value
        params = next
        saveParams()
    }

    function resetTimbre() {
        const next = SP.resetTimbre(params)
        params = next
        saveParams()
    }

    function reverbName() {
        const names = SP.reverbPresetNames
        const i = Math.min(Math.max(params.reverbPreset, 0), names.length - 1)
        return names[i]
    }

    function freqLabel(hz) {
        return hz >= 1000 ? Freq.printfFixed(hz / 1000, 1) + "k" : String(Math.round(hz)) + "Hz"
    }

    // ── layout ───────────────────────────────────────────────────────────────

    Column {
        anchors.fill: parent
        spacing: 10

        // header
        Column {
            width: parent.width
            spacing: 4
            Text {
                text: "HARMONIC SPECTRUM"
                color: Qt.rgba(1, 1, 1, 0.6)
                font.family: "monospace"
                font.pixelSize: 10
                font.letterSpacing: 3
            }
            Text {
                text: page.headerSubtitle()
                color: Qt.rgba(1, 1, 1, 0.35)
                font.family: "monospace"
                font.pixelSize: 9
            }
        }

        // controls
        Row {
            spacing: 10

            Repeater {
                model: [page.scaleLabel(), page.useLogScale ? "LOG" : "LINEAR", "SYNTH"]
                delegate: Rectangle {
                    required property int index
                    required property string modelData
                    readonly property bool active: index === 0 ? (page.scaleMode !== 0)
                                              : (index === 1 ? !page.useLogScale : page.showSynth)
                    width: ctlLabel.width + 24
                    height: 24
                    radius: 12
                    color: active ? Qt.rgba(1, 1, 1, 0.9) : "transparent"
                    border.color: Qt.rgba(1, 1, 1, 0.3)
                    border.width: 0.5

                    Text {
                        id: ctlLabel
                        anchors.centerIn: parent
                        text: parent.modelData
                        color: parent.active ? "#000000" : Qt.rgba(1, 1, 1, 0.7)
                        font.family: "monospace"
                        font.pixelSize: 9
                        font.letterSpacing: 2
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (parent.index === 0) page.cycleScale()
                            else if (parent.index === 1) page.useLogScale = !page.useLogScale
                            else page.showSynth = !page.showSynth
                        }
                    }
                }
            }
        }

        // timeframe filter
        Row {
            spacing: 6
            Repeater {
                model: page.orderedTimeframes.length
                delegate: Rectangle {
                    required property int index
                    readonly property string tf: page.orderedTimeframes[index]
                    readonly property bool ex: page.isExcluded(tf)
                    width: tfLabel.width + 16
                    height: 22
                    radius: 11
                    color: "transparent"
                    border.color: Qt.rgba(1, 1, 1, ex ? 0.12 : 0.4)
                    border.width: 0.5
                    Text {
                        id: tfLabel
                        anchors.centerIn: parent
                        text: page.shortTimeframeLabel(parent.tf)
                        color: Qt.rgba(1, 1, 1, parent.ex ? 0.25 : 0.8)
                        font.family: "monospace"
                        font.pixelSize: 8
                        font.letterSpacing: 2
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.toggleExcluded(parent.tf)
                    }
                }
            }
        }

        Text {
            visible: page.debugText !== ""
            text: page.debugText
            color: "#ff5555"
            font.family: "monospace"
            font.pixelSize: 9
        }

        // synth options replace the spectrum, exactly as the original does
        Flickable {
            id: synthFlick
            width: parent.width
            height: page.showSynth ? parent.height - y - 116 : 0
            visible: page.showSynth
            contentWidth: width
            contentHeight: synthCol.height + 10
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: synthCol
                width: parent.width
                spacing: 14

                Repeater {
                    model: [
                        { title: "ENVELOPE", rows: [
                            { k: "attackMs", label: "ATTACK", from: 0, to: 1000, unit: "ms" },
                            { k: "releaseMs", label: "RELEASE", from: 0, to: 3000, unit: "ms" }
                        ]},
                        { title: "TONE", rows: [
                            { k: "lowpassHz", label: "LOW-PASS", from: 500, to: 20000, hz: true }
                        ]},
                        { title: "SPACE", rows: [
                            { k: "reverbMix", label: "MIX", from: 0, to: 100, unit: "%" }
                        ]},
                        { title: "MOVEMENT", rows: [
                            { k: "tremoloRateHz", label: "TREMOLO", from: 0, to: 4, unit: "Hz", digits: 2 },
                            { k: "tremoloDepth", label: "DEPTH", from: 0, to: 1, pct: true },
                            { k: "width", label: "WIDTH", from: 0, to: 1, pct: true }
                        ]}
                    ]

                    delegate: Column {
                        required property int index
                        required property var modelData
                        width: synthCol.width
                        spacing: 9

                        Text {
                            text: parent.modelData.title
                            color: Qt.rgba(1, 1, 1, 0.4)
                            font.family: "monospace"
                            font.pixelSize: 8
                            font.letterSpacing: 2
                        }

                        Repeater {
                            model: modelData.rows
                            delegate: Row {
                                required property var modelData
                                width: synthCol.width
                                spacing: 10

                                Text {
                                    width: 72
                                    text: modelData.label
                                    color: Qt.rgba(1, 1, 1, 0.55)
                                    font.family: "monospace"
                                    font.pixelSize: 9
                                }
                                MiniSlider {
                                    width: 140
                                    anchors.verticalCenter: parent.verticalCenter
                                    from: modelData.from
                                    to: modelData.to
                                    value: page.params[modelData.k]
                                    onValueChanged: {
                                        if (page.params[modelData.k] !== value)
                                            page.setParam(modelData.k, value)
                                    }
                                }
                                Text {
                                    width: 52
                                    horizontalAlignment: Text.AlignRight
                                    text: {
                                        const v = page.params[modelData.k]
                                        if (modelData.hz) return page.freqLabel(v)
                                        if (modelData.pct) return Math.round(v * 100) + "%"
                                        if (modelData.digits !== undefined)
                                            return Freq.printfFixed(v, modelData.digits) + modelData.unit
                                        return Math.round(v) + (modelData.unit || "")
                                    }
                                    color: Qt.rgba(1, 1, 1, 0.7)
                                    font.family: "monospace"
                                    font.pixelSize: 9
                                }
                            }
                        }

                        // reverb preset row belongs to SPACE
                        Row {
                            visible: parent.modelData.title === "SPACE"
                            width: synthCol.width
                            spacing: 10
                            Text {
                                width: 72
                                text: "REVERB"
                                color: Qt.rgba(1, 1, 1, 0.55)
                                font.family: "monospace"
                                font.pixelSize: 9
                            }
                            Rectangle {
                                width: rvLabel.width + 24
                                height: 22
                                radius: 11
                                color: "transparent"
                                border.color: Qt.rgba(1, 1, 1, 0.3)
                                border.width: 0.5
                                Text {
                                    id: rvLabel
                                    anchors.centerIn: parent
                                    text: page.reverbName().toUpperCase()
                                    color: Qt.rgba(1, 1, 1, 0.85)
                                    font.family: "monospace"
                                    font.pixelSize: 9
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: page.setParam("reverbPreset",
                                        (page.params.reverbPreset + 1) % SP.reverbPresetNames.length)
                                }
                            }
                        }
                    }
                }

                // TIMBRE - the information-trading knobs, boxed and orange
                Rectangle {
                    width: synthCol.width
                    height: timbreCol.height + 20
                    radius: 8
                    color: Qt.rgba(1, 0.5, 0, 0.07)
                    border.color: Qt.rgba(1, 0.5, 0, 0.22)
                    border.width: 0.5

                    Column {
                        id: timbreCol
                        x: 10
                        y: 10
                        width: parent.width - 20
                        spacing: 10

                        Row {
                            width: timbreCol.width
                            Text {
                                text: "TIMBRE \u00B7 ALTERS THE CHORD"
                                color: Qt.rgba(1, 0.5, 0, 0.9)
                                font.family: "monospace"
                                font.pixelSize: 8
                                font.letterSpacing: 2
                            }
                            Item { width: parent.width - 320; height: 1 }
                            Text {
                                text: "RESET"
                                color: "#ff8800"
                                font.family: "monospace"
                                font.pixelSize: 8
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: page.resetTimbre()
                                }
                            }
                        }

                        Repeater {
                            model: [
                                { k: "unisonVoices", label: "UNISON", lo: 1, hi: 3 },
                                { k: "partials", label: "PARTIALS", lo: 2, hi: 6 }
                            ]
                            delegate: Row {
                                required property var modelData
                                width: timbreCol.width
                                spacing: 10
                                Text {
                                    width: 72
                                    text: modelData.label
                                    color: Qt.rgba(1, 1, 1, 0.55)
                                    font.family: "monospace"
                                    font.pixelSize: 9
                                }
                                Item { width: parent.width - 220; height: 1 }
                                Text {
                                    text: "\u2212"
                                    color: Qt.rgba(1, 1, 1, 0.8)
                                    font.pixelSize: 13
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -6
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            const v = page.params[modelData.k]
                                            if (v > modelData.lo) page.setParam(modelData.k, v - 1)
                                        }
                                    }
                                }
                                Text {
                                    width: 22
                                    horizontalAlignment: Text.AlignHCenter
                                    text: String(page.params[modelData.k])
                                    color: Qt.rgba(1, 1, 1, 0.85)
                                    font.family: "monospace"
                                    font.pixelSize: 10
                                }
                                Text {
                                    text: "+"
                                    color: Qt.rgba(1, 1, 1, 0.8)
                                    font.pixelSize: 13
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -6
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            const v = page.params[modelData.k]
                                            if (v < modelData.hi) page.setParam(modelData.k, v + 1)
                                        }
                                    }
                                }
                            }
                        }

                        Repeater {
                            model: [
                                { k: "detuneCents", label: "DETUNE", from: 0, to: 25, digits: 1 },
                                { k: "enrichment", label: "ENRICH", from: 0, to: 1, pct: true },
                                { k: "partialTilt", label: "TILT", from: 0, to: 3, digits: 1 }
                            ]
                            delegate: Row {
                                required property var modelData
                                width: timbreCol.width
                                spacing: 10
                                Text {
                                    width: 72
                                    text: modelData.label
                                    color: Qt.rgba(1, 1, 1, 0.55)
                                    font.family: "monospace"
                                    font.pixelSize: 9
                                }
                                MiniSlider {
                                    width: 140
                                    anchors.verticalCenter: parent.verticalCenter
                                    from: modelData.from
                                    to: modelData.to
                                    value: page.params[modelData.k]
                                    onValueChanged: {
                                        if (page.params[modelData.k] !== value)
                                            page.setParam(modelData.k, value)
                                    }
                                }
                                Text {
                                    width: 52
                                    horizontalAlignment: Text.AlignRight
                                    text: modelData.pct
                                        ? Math.round(page.params[modelData.k] * 100) + "%"
                                        : Freq.printfFixed(page.params[modelData.k], modelData.digits)
                                              + (modelData.k === "detuneCents" ? "\u00A2" : "")
                                    color: Qt.rgba(1, 1, 1, 0.7)
                                    font.family: "monospace"
                                    font.pixelSize: 9
                                }
                            }
                        }
                    }
                }
            }
        }

        // spectrum
        Canvas {
            id: spectrum
            width: parent.width
            height: page.showSynth ? 0 : parent.height - y - 106
            visible: !page.showSynth

            Connections {
                target: page
                // Only the displayed page repaints; a hidden Canvas still runs
                // onPaint when requestPaint() is called on it.
                function onSnapshotChanged() {
                    if (page.live) spectrum.requestPaint()
                }
                function onLiveChanged() {
                    if (page.live) spectrum.requestPaint()
                }
            }
            Component.onCompleted: requestPaint()

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const snap = page.snapshot
                if (!snap) return
                const date = new Date(snap.timestamp)
                const tones = page.displayedTones(date)

                const minF = page.minFreqHz()
                const maxF = page.useLogScale ? page.maxFreqHz()
                                              : Math.min(page.maxFreqHz(), 20000)
                const logRange = Math.log(maxF) / Math.LN10 - Math.log(minF) / Math.LN10
                const linRange = maxF - minF
                const activeRange = page.useLogScale ? logRange : linRange
                if (!(activeRange > 0)) return

                const W = width, H = height
                const axisWidth = 38
                const baselineX = axisWidth + 6
                const maxBarWidth = 140
                const labelX = baselineX + maxBarWidth + 8

                function mapY(f) {
                    if (page.useLogScale) {
                        const frac = (Math.log(f) / Math.LN10 - Math.log(minF) / Math.LN10) / logRange
                        return H * (1 - frac)
                    }
                    const frac = (f - minF) / linRange
                    return H * (1 - frac)
                }

                const ticks = page.useLogScale ? page.decadeValues(minF, maxF)
                                               : page.linearTicks(minF, maxF, 6)

                // audible band
                const yLo = mapY(20), yHi = mapY(20000)
                ctx.fillStyle = "rgba(255,255,255,0.04)"
                ctx.fillRect(baselineX, yHi, W - baselineX, yLo - yHi)

                // grid + spine
                ctx.strokeStyle = "rgba(255,255,255,0.06)"
                ctx.lineWidth = 0.5
                for (let i = 0; i < ticks.length; i++) {
                    const y = mapY(ticks[i])
                    ctx.beginPath(); ctx.moveTo(baselineX, y); ctx.lineTo(W, y); ctx.stroke()
                }
                ctx.strokeStyle = "rgba(255,255,255,0.3)"
                ctx.beginPath(); ctx.moveTo(baselineX, 0); ctx.lineTo(baselineX, H); ctx.stroke()

                // axis labels
                ctx.font = "8px monospace"
                ctx.textAlign = "center"
                ctx.textBaseline = "middle"
                for (let i = 0; i < ticks.length; i++) {
                    const y = mapY(ticks[i])
                    const label = (i === 0 ? page.decadeLabel(ticks[i]) + " Hz"
                                           : page.decadeLabel(ticks[i]))
                    ctx.fillStyle = "rgba(255,255,255,0.45)"
                    ctx.fillText(label, 18, y)
                }

                // tones
                const showScaleSuffix = page.scaleMode === 2
                for (let i = 0; i < tones.length; i++) {
                    const tone = tones[i]
                    if (tone.frequency < minF || tone.frequency > maxF) continue
                    const y = mapY(tone.frequency)
                    const length = maxBarWidth * tone.amplitude
                    const isFund = tone.divisions === 1

                    ctx.strokeStyle = isFund ? "rgba(255,255,255,1)"
                                             : "rgba(255,255,255,0.85)"
                    ctx.lineWidth = isFund ? 1.5 : 0.8
                    ctx.beginPath()
                    ctx.moveTo(baselineX, y)
                    ctx.lineTo(baselineX + length, y)
                    ctx.stroke()

                    const dotR = 1.5 + tone.amplitude * 2
                    ctx.beginPath()
                    ctx.arc(baselineX + length - dotR, y, dotR, 0, Math.PI * 2)
                    ctx.fillStyle = ctx.strokeStyle
                    ctx.fill()

                    const name = page.compactName(tone.timeframe)
                    const prefix = isFund ? name : name + "\u00D7" + page.divisionLabel(tone)
                    const suffix = showScaleSuffix ? " @" + tone.octaves : ""
                    const freqText = Freq.format(tone.frequency)
                    const stateText = isFund ? "" : "  \u00B7  " + page.stateLabel(tone.state)
                    ctx.font = "8px monospace"
                    ctx.textAlign = "left"
                    ctx.fillStyle = "rgba(255,255,255," + (isFund ? 0.75 : 0.55) + ")"
                    ctx.fillText(prefix + suffix + "  \u00B7  " + freqText + stateText, labelX, y)
                }
                ctx.textBaseline = "alphabetic"
            }
        }

        // composite waveform scope
        Item {
            width: parent.width
            height: page.showSynth ? 0 : parent.height - y - 16
            visible: !page.showSynth

            Rectangle {
                anchors.fill: parent
                radius: 4
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.15)
                border.width: 0.5
            }

            Text {
                x: 4
                y: 4
                text: "COMPOSITE WAVEFORM"
                color: Qt.rgba(1, 1, 1, 0.35)
                font.family: "monospace"
                font.pixelSize: 8
                font.letterSpacing: 2
            }

            Canvas {
                id: scope
                anchors.fill: parent
                anchors.topMargin: 14
                anchors.bottomMargin: 4
                anchors.leftMargin: 4
                anchors.rightMargin: 4

                Connections {
                    target: page
                    function onSnapshotChanged() {
                        if (page.live) scope.requestPaint()
                    }
                    function onLiveChanged() {
                        if (page.live) scope.requestPaint()
                    }
                }
                Component.onCompleted: requestPaint()

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const snap = page.snapshot
                    if (!snap) return
                    const tones = page.displayedTones(new Date(snap.timestamp))

                    const W = width, H = height
                    ctx.strokeStyle = "rgba(255,255,255,0.1)"
                    ctx.lineWidth = 0.5
                    ctx.beginPath(); ctx.moveTo(0, H / 2); ctx.lineTo(W, H / 2); ctx.stroke()

                    if (tones.length === 0) return

                    const windowSeconds = 0.030
                    const samples = Math.max(2, Math.floor(W))
                    const values = []
                    let peak = 0
                    for (let i = 0; i < samples; i++) {
                        const t = (i / samples) * windowSeconds
                        let s = 0
                        for (let j = 0; j < tones.length; j++) {
                            s += Math.sin(2 * Math.PI * tones[j].frequency * t) * tones[j].amplitude
                        }
                        values.push(s)
                        if (Math.abs(s) > peak) peak = Math.abs(s)
                    }
                    if (!(peak > 0)) return

                    const scale = (H / 2 - 4) / peak
                    ctx.strokeStyle = "rgba(255,255,255,0.85)"
                    ctx.lineWidth = 1
                    ctx.beginPath()
                    for (let i = 0; i < samples; i++) {
                        const x = i
                        const y = H / 2 - values[i] * scale
                        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                    }
                    ctx.stroke()
                }
            }
        }
    }
}