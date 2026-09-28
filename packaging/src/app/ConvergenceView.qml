import QtQuick
import "core/theme.mjs" as Theme
import QtCore

// Port of `ConvergenceView` in MiscPage.swift - chord detection across
// timeframes: what chord is sounding now, and what cross-timeframe
// convergences are coming in the next 30 days.
//
// Two departures from the original, both forced by the platform:
//
//  1. The scan is cooperatively sliced (see `stepScan`) because QML's JS is
//     single-threaded and V4 runs this projection ~10x slower than V8 - a
//     straight port froze the UI for 7 seconds.
//  2. The result is cached in QtCore `Settings` (category
//     `exochronometer-convergence`), keyed by the original's recompute key.
//     A restart inside the same 5-minute bucket reuses it, and a rescan keeps
//     the previous results on screen instead of blanking to "…computing".
import "core/chordProjector.mjs" as CP
import "core/chordCatalog.mjs" as CAT
import "core/frequencyMath.mjs" as Freq

Item {
    id: conv

    property var now: new Date()
    property bool fundamentalsOff: true

    // False unless this view is the one on screen. The 30-day chord scan is the
    // single most expensive computation in the app, so it must not run while
    // hidden.
    property bool live: true
    property bool prepared: false

    // The original's ConvergenceView constants.
    readonly property real lookahead: 30 * 86400
    readonly property int maxResults: 40
    readonly property real sampleInterval: 60
    readonly property int scaling: 23

    property var currentMatches: []
    property var events: []
    property bool computing: true
    property string bucket: ""
    property real scanMs: 0
    property bool fromCache: false

    // Resumable scan, advanced a few ms per frame so the UI never blocks.
    property var scan: null
    property real scanStartMs: 0

    // Progress must live in a QML property: mutating `scan.i` inside the JS
    // object does not notify bindings, so a binding reading scan.i would stay
    // frozen at its initial value.
    property real progress: 0
    property string debugText: ""

    // A repeating Timer with interval 0 never fires in this Qt build.
    property int sliceBudgetMs: 25

    Settings {
        id: cache
        category: "exochronometer-convergence"
        // The original's recomputeKey: bucket | fundamentalsOff.
        property string cacheKey: ""
        property string cacheEvents: ""
        property int cacheHits: 0
    }

    // Nothing is scanned until the view is actually shown.
    Component.onCompleted: if (conv.live) prepare()
    onLiveChanged: {
        if (conv.live) {
            prepare()
        } else {
            // Stop mid-scan work when the page is left; results already on
            // screen stay there.
            startTimer.stop()
            sliceTimer.stop()
        }
    }

    // First-run setup, deferred so the loading state paints first.
    function prepare() {
        conv.now = new Date()
        if (prepared) return
        prepared = true
        if (!tryRestore()) recompute()
    }

    // TimelineView(.periodic(1.0)) - drives the "time until" countdown.
    Timer {
        interval: 1000
        running: conv.live
        repeat: true
        onTriggered: {
            conv.now = new Date()
            // Compare against the composite recompute key, not the bare bucket.
            if (conv.currentKey() !== conv.bucket) conv.recompute()
        }
    }

    // Deferred so the loading state paints before the scan starts.
    Timer {
        id: startTimer
        interval: 50
        running: false
        repeat: false
        onTriggered: conv.beginScan()
    }

    // One time slice per event-loop turn.
    Timer {
        id: sliceTimer
        interval: 1
        running: false
        repeat: true
        onTriggered: conv.stepScan()
    }

    // --- cache ---------------------------------------------------------------

    function currentKey() {
        const b = Math.floor(now.getTime() / 1000 / 300)
        return b + "|" + (fundamentalsOff ? 1 : 0)
    }

    function serialize(evs) {
        const out = []
        for (let i = 0; i < evs.length; i++) {
            const e = evs[i]
            const sig = []
            for (let j = 0; j < e.toneSignature.length; j++) {
                const s = e.toneSignature[j]
                sig.push(s.timeframe + "|" + s.divisions + "|" + s.skip)
            }
            out.push({
                a: e.pattern.abbreviation,
                s: sig,
                t0: e.startTime.getTime(),
                t1: e.endTime.getTime(),
                f: e.fitCents
            })
        }
        return JSON.stringify(out)
    }

    function revive(json) {
        const raw = JSON.parse(json)
        const out = []
        for (let i = 0; i < raw.length; i++) {
            const r = raw[i]
            const sig = []
            for (let j = 0; j < r.s.length; j++) {
                const p = r.s[j].split("|")
                sig.push({
                    timeframe: p[0],
                    divisions: parseInt(p[1], 10),
                    skip: parseInt(p[2], 10)
                })
            }
            out.push({
                pattern: { abbreviation: r.a },
                toneSignature: sig,
                startTime: new Date(r.t0),
                endTime: new Date(r.t1),
                fitCents: r.f
            })
        }
        return out
    }

    function tryRestore() {
        const k = currentKey()
        if (cache.cacheKey !== k || cache.cacheEvents === "") return false
        try {
            events = revive(cache.cacheEvents)
        } catch (e) {
            debugText = "cache unreadable, rescanning"
            return false
        }
        currentMatches = CP.current(
            now, 0.3, scaling, !fundamentalsOff, false, true, CAT.chords
        )
        bucket = k
        fromCache = true
        computing = false
        progress = 100
        return true
    }

    // --- scan ----------------------------------------------------------------

    function recompute() {
        // Must record the bucket, or the 1s timer sees a different value every
        // tick and restarts the scan forever.
        bucket = currentKey()
        // Keep any existing results on screen while re-scanning; only the
        // very first run has nothing to show.
        computing = true
        fromCache = false
        scan = null
        startTimer.start()
    }

    function beginScan() {
        const includeFundamentals = !fundamentalsOff
        scanStartMs = Date.now()
        try {
            scan = CP.beginUpcoming(
                now, lookahead, 0.3, sampleInterval, scaling,
                includeFundamentals, true, true, true, CAT.chords, maxResults
            )
        } catch (e) {
            debugText = "beginScan failed: " + e
            computing = false
            return
        }
        progress = 0
        if (scan.done) { finishScan(); return }
        sliceTimer.start()
    }

    function stepScan() {
        if (scan === null) { sliceTimer.stop(); return }
        try {
            if (CP.stepUpcoming(scan, sliceBudgetMs)) {
                sliceTimer.stop()
                finishScan()
            } else {
                const p = scan.nSamples > 0
                    ? Math.min(100, Math.round((scan.i / scan.nSamples) * 100)) : 0
                if (p !== progress) progress = p
            }
        } catch (e) {
            sliceTimer.stop()
            debugText = "stepScan failed: " + e
            computing = false
        }
    }

    function finishScan() {
        try {
            events = CP.finishUpcoming(scan)
            currentMatches = CP.current(
                now, 0.3, scaling, !fundamentalsOff, false, true, CAT.chords
            )
            cache.cacheKey = currentKey()
            cache.cacheEvents = serialize(events)
        } catch (e) {
            debugText = "finishScan failed: " + e
        }
        progress = 100
        scanMs = Date.now() - scanStartMs
        computing = false
    }

    // --- the original's helpers ----------------------------------------------

    function compactTF(tf) {
        if (tf === "year") return "YR"
        if (tf === "moon") return "MN"
        if (tf === "quarterMoon") return "QM"
        if (tf === "day") return "DY"
        if (tf === "hour") return "HR"
        return "MIN"
    }

    function sigLabel(s) {
        return s.skip === 1 ? String(s.divisions) : s.divisions + "/" + s.skip
    }

    function signatureText(sig) {
        const parts = []
        for (let i = 0; i < sig.length; i++) {
            parts.push(compactTF(sig[i].timeframe) + ":" + sigLabel(sig[i]))
        }
        return parts.join(" \u00B7 ")
    }

    function durationText(s) {
        if (s < 60) return Freq.printfFixed(s, 0) + "s"
        if (s < 3600) return Freq.printfFixed(Math.floor(s / 60), 0) + "m"
        if (s < 86400) {
            return Freq.printfFixed(Math.floor(s / 3600), 0) + "h"
                 + Freq.printfFixed(Math.floor((s % 3600) / 60), 0) + "m"
        }
        return Freq.printfFixed(Math.floor(s / 86400), 0) + "d"
             + Freq.printfFixed(Math.floor((s % 86400) / 3600), 0) + "h"
    }

    function timeUntil(d, from) {
        return durationText(Math.max(0, (d.getTime() - from.getTime()) / 1000))
    }

    function progressPercent() {
        return Math.round(progress)
    }

    // --- rendering -----------------------------------------------------------

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.height + 20
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            spacing: 14

            Text {
                visible: conv.debugText !== ""
                width: col.width
                text: conv.debugText
                color: Theme.urgent()
                font.family: "monospace"
                font.pixelSize: 9
                wrapMode: Text.Wrap
            }

            Text {
                visible: conv.computing && conv.events.length > 0
                text: "refreshing\u2026  showing previous results  "
                      + conv.progressPercent() + "%"
                color: Qt.rgba(1, 0.8, 0.4, 0.8)
                font.family: "monospace"
                font.pixelSize: 8
                font.letterSpacing: 1
            }

            // ── NOW ──
            Column {
                width: col.width
                spacing: 6

                Text {
                    text: "NOW"
                    color: Theme.fg(0.55)
                    font.family: "monospace"
                    font.pixelSize: 9
                    font.letterSpacing: 2
                }

                Text {
                    visible: conv.computing
                    text: "\u2026computing  " + conv.progressPercent() + "%"
                    color: Theme.fg(0.35)
                    font.family: "monospace"
                    font.pixelSize: 10
                }

                Text {
                    visible: !conv.computing && conv.currentMatches.length === 0
                    text: "no recognized chord active"
                    color: Theme.fg(0.4)
                    font.family: "monospace"
                    font.pixelSize: 10
                }

                Repeater {
                    model: conv.computing ? 0 : Math.min(5, conv.currentMatches.length)

                    delegate: Row {
                        required property int index
                        width: col.width
                        spacing: 8

                        Text {
                            text: conv.currentMatches[index].pattern.abbreviation
                            color: Theme.fg(1)
                            font.family: "monospace"
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }
                        Text {
                            text: {
                                const m = conv.currentMatches[index]
                                const sig = []
                                for (let i = 0; i < m.tones.length; i++) {
                                    const t = m.tones[i]
                                    sig.push({ timeframe: t.timeframe, divisions: t.divisions, skip: t.skip })
                                }
                                return conv.signatureText(sig)
                            }
                            color: Theme.fg(0.7)
                            font.family: "monospace"
                            font.pixelSize: 10
                        }
                        Item { width: parent.width - 340; height: 1 }
                        Text {
                            text: "fit " + Freq.printfFixed(conv.currentMatches[index].fitCents, 1) + "\u00A2"
                            color: Theme.fg(0.55)
                            font.family: "monospace"
                            font.pixelSize: 9
                        }
                    }
                }
            }

            // ── upcoming ──
            Column {
                width: col.width
                spacing: 6

                Column {
                    spacing: 2
                    Text {
                        text: "CROSS-TIMEFRAME CONVERGENCES"
                        color: Theme.fg(0.55)
                        font.family: "monospace"
                        font.pixelSize: 9
                        font.letterSpacing: 2
                    }
                    Text {
                        text: "next 30 days  \u00B7  nearest first"
                        color: Theme.fg(0.4)
                        font.family: "monospace"
                        font.pixelSize: 8
                        font.letterSpacing: 1.5
                    }
                }

                Text {
                    visible: conv.computing && conv.events.length === 0
                    text: "\u2026computing  " + conv.progressPercent() + "%"
                    color: Theme.fg(0.35)
                    font.family: "monospace"
                    font.pixelSize: 10
                }

                Text {
                    visible: !conv.computing && conv.events.length === 0
                    text: "none predicted in window"
                    color: Theme.fg(0.4)
                    font.family: "monospace"
                    font.pixelSize: 10
                }

                Repeater {
                    model: conv.events.length

                    delegate: Column {
                        required property int index
                        width: col.width
                        spacing: 2

                        Row {
                            width: col.width
                            spacing: 8

                            Text {
                                text: conv.events[index].pattern.abbreviation
                                color: Theme.fg(1)
                                font.family: "monospace"
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                            Text {
                                text: conv.signatureText(conv.events[index].toneSignature)
                                color: Theme.fg(0.7)
                                font.family: "monospace"
                                font.pixelSize: 10
                            }
                            Item { width: parent.width - 360; height: 1 }
                            Text {
                                text: conv.timeUntil(conv.events[index].startTime, conv.now)
                                color: Theme.fg(0.85)
                                font.family: "monospace"
                                font.pixelSize: 11
                            }
                        }

                        Row {
                            spacing: 10
                            Text {
                                text: "fit " + Freq.printfFixed(conv.events[index].fitCents, 1) + "\u00A2"
                                color: Theme.fg(0.35)
                                font.family: "monospace"
                                font.pixelSize: 8
                            }
                            Text {
                                text: "dur " + conv.durationText(
                                    (conv.events[index].endTime.getTime() - conv.events[index].startTime.getTime()) / 1000)
                                color: Theme.fg(0.35)
                                font.family: "monospace"
                                font.pixelSize: 8
                            }
                        }
                    }
                }
            }

            Text {
                visible: !conv.computing
                text: {
                    if (conv.fromCache) {
                        return conv.events.length + " convergences \u00B7 "
                             + conv.currentMatches.length + " active \u00B7 restored from cache"
                    }
                    return conv.events.length + " convergences \u00B7 "
                         + conv.currentMatches.length + " active \u00B7 scan "
                         + Freq.printfFixed(conv.scanMs, 0) + " ms"
                }
                color: Theme.fg(0.25)
                font.family: "monospace"
                font.pixelSize: 8
                font.letterSpacing: 1
            }
        }
    }
}