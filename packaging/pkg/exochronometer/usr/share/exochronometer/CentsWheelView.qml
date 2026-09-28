import QtQuick

// Port of CentsWheelView in MiscPage.swift - the live tones placed on a
// 1200-cent wheel against A4 = 432 Hz, with JI name labels, radial anti-
// overlap stacking, and a time-until-fade suffix on overtones.
import "core/harmonicAnalysis.mjs" as HA
import "core/justIntonation.mjs" as JI
import "core/fadeMath.mjs" as Fade

Item {
    id: wheel

    property var snapshot: null

    // False unless this view is the one on screen. Gates every repaint and
    // derived binding, so hidden views cost nothing.
    property bool live: true
    onLiveChanged: if (live) canvas.requestPaint()
    property bool fundamentalsOff: true
    property var excluded: []

    readonly property int scaling: 23
    readonly property real reference: 432.0

    // Computed once per snapshot rather than once per paint.
    readonly property var liveTones: {
        if (!live) return []
        const snap = wheel.snapshot
        if (!snap) return []
        return filteredTones(new Date(snap.timestamp))
    }

    function filteredTones(date) {
        const all = HA.activeTonesForScales(date, [scaling])
        const out = []
        for (let i = 0; i < all.length; i++) {
            const t = all[i]
            if (excluded.indexOf(t.timeframe) >= 0) continue
            if (fundamentalsOff && HA.isFundamental(t)) continue
            out.push(t)
        }
        return out
    }

    function toneLabel(tone) {
        const name = shortTF(tone.timeframe)
        return HA.isFundamental(tone) ? name : name + HA.divisionLabel(tone)
    }

    function shortTF(tf) {
        if (tf === "year") return "YR"
        if (tf === "moon") return "MN"
        if (tf === "quarterMoon") return "QM"
        if (tf === "day") return "DY"
        if (tf === "hour") return "HR"
        return "MIN"
    }

    function formatRemaining(seconds) {
        const s = Math.max(0, seconds)
        if (s < 60) return String(Math.round(s)) + "s"
        if (s < 3600) return String(Math.floor(s / 60)) + "m"
        if (s < 86400) return String(Math.floor(s / 3600)) + "h"
        if (s < 31557600) return String(Math.floor(s / 86400)) + "d"
        return String(Math.floor(s / 31557600)) + "y"
    }

    function angleDistance(a, b) {
        let d = Math.abs(a - b)
        if (d > Math.PI) d = 2 * Math.PI - d
        return d
    }

    function layoutTones(tones, now) {
        const raws = []
        for (let i = 0; i < tones.length; i++) {
            const tone = tones[i]
            if (!(tone.frequency > 0)) continue
            const cents = 1200 * Math.log2(tone.frequency / reference)
            const pitchClass = ((cents % 1200) + 1200) % 1200
            const angle = (pitchClass / 1200) * 2 * Math.PI - Math.PI / 2
            let remaining = null
            try {
                remaining = Fade.timeUntilOvertoneExit(tone.timeframe, tone.divisions, tone.skip, now)
            } catch (e) {
                remaining = null
            }
            raws.push({ tone: tone, angle: angle, remaining: remaining })
        }
        raws.sort(function (a, b) { return a.angle - b.angle })

        const occupied = []
        const out = []
        const clusterThreshold = 0.14   // ~8 degrees
        for (let i = 0; i < raws.length; i++) {
            const raw = raws[i]
            let level = 0
            let clash = true
            while (clash) {
                clash = false
                for (let j = 0; j < occupied.length; j++) {
                    if (occupied[j].level === level
                        && angleDistance(occupied[j].angle, raw.angle) < clusterThreshold) {
                        clash = true
                        break
                    }
                }
                if (clash) level += 1
            }
            occupied.push({ angle: raw.angle, level: level })
            out.push({
                tone: raw.tone,
                angle: raw.angle,
                stackLevel: level,
                remainingLabel: raw.remaining === null ? null : formatRemaining(raw.remaining)
            })
        }
        return out
    }

    Canvas {
        id: canvas
        anchors.fill: parent

        Connections {
            target: wheel
            // Only the displayed view repaints; a hidden Canvas still runs
            // onPaint when requestPaint() is called on it.
            function onSnapshotChanged() {
                if (wheel.live) canvas.requestPaint()
            }
        }
        Component.onCompleted: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const snap = wheel.snapshot
            if (!snap) return
            const now = new Date(snap.timestamp)
            const tones = wheel.liveTones
            const positioned = wheel.layoutTones(tones, now)

            const cx = width / 2
            const cy = height / 2
            const r = Math.min(width, height) / 2 - 30

            ctx.strokeStyle = "rgba(255,255,255,0.3)"
            ctx.lineWidth = 0.6
            ctx.beginPath()
            ctx.arc(cx, cy, r, 0, Math.PI * 2)
            ctx.stroke()

            // JI labels + ticks
            const labels = JI.labels
            ctx.textAlign = "center"
            ctx.textBaseline = "middle"
            ctx.font = "9px monospace"
            for (let i = 0; i < labels.length; i++) {
                const angle = (labels[i].cents / 1200) * 2 * Math.PI - Math.PI / 2
                const ca = Math.cos(angle)
                const sa = Math.sin(angle)

                ctx.strokeStyle = "rgba(255,255,255,0.2)"
                ctx.lineWidth = 0.5
                ctx.beginPath()
                ctx.moveTo(cx + (r - 4) * ca, cy + (r - 4) * sa)
                ctx.lineTo(cx + (r + 1) * ca, cy + (r + 1) * sa)
                ctx.stroke()

                ctx.fillStyle = "rgba(255,255,255,0.55)"
                ctx.fillText(labels[i].name, cx + (r + 14) * ca, cy + (r + 14) * sa)
            }

            // tones
            for (let i = 0; i < positioned.length; i++) {
                const entry = positioned[i]
                const tone = entry.tone
                const angle = entry.angle
                const isFund = HA.isFundamental(tone)
                const dotR = isFund ? 5 : 3 + tone.amplitude * 2
                const x = cx + r * Math.cos(angle)
                const y = cy + r * Math.sin(angle)
                const alpha = isFund ? 0.95 : tone.amplitude * 0.9

                ctx.beginPath()
                ctx.arc(x, y, dotR, 0, Math.PI * 2)
                ctx.fillStyle = "rgba(255,255,255," + alpha.toFixed(3) + ")"
                ctx.fill()

                const labelDist = r - 14 - entry.stackLevel * 12
                if (!(labelDist > 8)) continue
                const lx = cx + labelDist * Math.cos(angle)
                const ly = cy + labelDist * Math.sin(angle)

                // Anchor the text on the side nearest the dot so the body
                // always extends inward, never outward past the dot.
                const ca = Math.cos(angle)
                const sa = Math.sin(angle)
                ctx.textAlign = ca > 0.05 ? "right" : (ca < -0.05 ? "left" : "center")
                ctx.textBaseline = sa > 0.05 ? "bottom" : (sa < -0.05 ? "top" : "middle")

                let text = wheel.toneLabel(tone)
                if (entry.remainingLabel !== null) text += " \u00B7 " + entry.remainingLabel
                ctx.font = "7px monospace"
                ctx.fillStyle = "rgba(255,255,255," + Math.min(0.85, alpha + 0.1).toFixed(3) + ")"
                ctx.fillText(text, lx, ly)
            }
            ctx.textBaseline = "alphabetic"
        }
    }
}