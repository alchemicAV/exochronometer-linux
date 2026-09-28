import QtQuick

// Port of ConvergenceSelectorChart (ExochronometerCore/ConvergenceSelectorView.swift)
// - the (divisions x degrees) integer-convergence lattice. Grey background dots
// mark every cell where (deg * div) % 360 == 0; the active geometry lights cells
// white with a halo. Irregular polygons (7-gon family) whose angles miss the
// 10-degree grid get off-grid dots at their exact angle plus a faint guide tick.
import "core/geometry.mjs" as Geo
import "core/fadeMath.mjs" as Fade

Item {
    id: sel

    property var snapshot: null

    // False unless this view is the one on screen. Gates every repaint and
    // derived binding, so hidden views cost nothing.
    property bool live: true
    onLiveChanged: if (live) canvas.requestPaint()
    property var excluded: []

    // ConvergenceSelectorChart's `selectedTimeframe`: null merges every
    // timeframe (the MISC SELECTOR mode), a name scopes the chart to that
    // single frame (the circles page's selector panels).
    property string selectedTimeframe: ""

    readonly property int maxDivisions: 35
    readonly property real degreeStep: 10
    readonly property real backgroundOpacity: 0.225
    readonly property var timeframeOrder: ["year", "moon", "quarterMoon", "day", "hour", "minute"]

    /** Pre-enumerated background dot coordinates - the same (div, deg) pairs
     *  every frame regardless of canvas size. Computed once. */
    readonly property var backgroundCoords: {
        const maxDiv = 35
        const step = 10
        const degRows = Math.floor(360.0 / step) - 1
        const coords = []
        for (let div = 3; div <= maxDiv; div++) {
            for (let i = 1; i <= degRows; i++) {
                const deg = i * step
                if ((deg * div) % 360 === 0) coords.push({ div: div, deg: deg })
            }
        }
        // Off-grid: each valid (n, k) shape's angle plus its 360 complement.
        const shapes = Geo.defaultShapes
        for (let s = 0; s < shapes.length; s++) {
            const shape = shapes[s]
            const primary = shape.skip * 360.0 / shape.divisions
            const snapped = Math.round(primary / step) * step
            if (Math.abs(primary - snapped) < 0.01) continue
            const angles = [primary, 360.0 - primary]
            for (let ai = 0; ai < angles.length; ai++) {
                let mult = 1
                while (shape.divisions * mult <= maxDiv) {
                    coords.push({ div: shape.divisions * mult, deg: angles[ai] })
                    mult += 1
                }
            }
        }
        return coords
    }

    function quantize(deg) { return Math.round(deg * 100) }

    function isOnDegreeGrid(angle) {
        const snapped = Math.round(angle / degreeStep) * degreeStep
        return Math.abs(angle - snapped) < 0.01
    }

    function shapeOpacityFor(shape, state) {
        if (shape.skip === 1) {
            return Fade.shapeOpacity(state.currentDegree, shape.divisions)
        }
        let best = 0
        for (let v = 0; v < shape.divisions; v++) {
            const a = Fade.nodeActivation(shape, v, state)
            if (a > best) best = a
        }
        return best
    }

    function contributingTimeframes() {
        if (selectedTimeframe !== "") return [selectedTimeframe]
        const out = []
        for (let i = 0; i < timeframeOrder.length; i++) {
            if (excluded.indexOf(timeframeOrder[i]) < 0) out.push(timeframeOrder[i])
        }
        return out
    }

    function computeActivations(date) {
        const byCell = {}
        const activeLimit = maxDivisions - 1
        const tfs = contributingTimeframes()
        const shapes = Geo.defaultShapes

        for (let ti = 0; ti < tfs.length; ti++) {
            const tf = tfs[ti]
            const state = Fade.timeframeState(tf, date)
            for (let si = 0; si < shapes.length; si++) {
                const shape = shapes[si]
                const op = shapeOpacityFor(shape, state)
                if (!(op > 0.001)) continue

                const primary = shape.skip * 360.0 / shape.divisions
                const conjugate = 360.0 - primary
                const angles = [primary, conjugate]

                for (let ai = 0; ai < angles.length; ai++) {
                    const angle = angles[ai]
                    if (isOnDegreeGrid(angle)) {
                        const degInt = Math.round(angle)
                        if (!(degInt > 0 && degInt < 360)) continue
                        for (let div = 3; div <= activeLimit; div++) {
                            if ((degInt * div) % 360 !== 0) continue
                            const key = div + "|" + quantize(angle)
                            const prior = byCell[key] === undefined ? 0 : byCell[key].glow
                            byCell[key] = { div: div, deg: degInt, onGrid: true,
                                            glow: Math.max(prior, op) }
                        }
                    } else {
                        let mult = 1
                        while (shape.divisions * mult <= activeLimit) {
                            const div = shape.divisions * mult
                            const key = div + "|" + quantize(angle)
                            const prior = byCell[key] === undefined ? 0 : byCell[key].glow
                            byCell[key] = { div: div, deg: angle, onGrid: false,
                                            glow: Math.max(prior, op) }
                            mult += 1
                        }
                    }
                }
            }
        }

        const out = []
        for (const k in byCell) out.push(byCell[k])
        return out
    }

    Canvas {
        id: canvas
        anchors.fill: parent

        Connections {
            target: sel
            // Only the displayed view repaints; a hidden Canvas still runs
            // onPaint when requestPaint() is called on it.
            function onSnapshotChanged() {
                if (sel.live) canvas.requestPaint()
            }
        }
        Component.onCompleted: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const snap = sel.snapshot
            if (!snap) return
            const date = new Date(snap.timestamp)

            // layout
            const leftMargin = 28, topMargin = 18, rightMargin = 6, bottomMargin = 6
            const cols = sel.maxDivisions - 2
            const rows = Math.floor(360.0 / sel.degreeStep) - 1
            const w = Math.max(0, width - leftMargin - rightMargin)
            const h = Math.max(0, height - topMargin - bottomMargin)
            const cellWidth = w / cols
            const cellHeight = h / rows
            const plotMinX = leftMargin
            const plotMinY = topMargin

            function position(div, deg) {
                return {
                    x: plotMinX + (div - 3 + 0.5) * cellWidth,
                    y: plotMinY + (deg / 360.0) * h
                }
            }

            // axes
            ctx.font = "7px monospace"
            ctx.textAlign = "center"
            ctx.textBaseline = "middle"
            ctx.fillStyle = "rgba(255,255,255,0.5)"
            for (let div = 5; div <= sel.maxDivisions; div += 5) {
                const p = position(div, 0)
                ctx.fillText(String(div), p.x, plotMinY - 8)
            }
            for (let degInt = 30; degInt <= 330; degInt += 30) {
                const p = position(3, degInt)
                ctx.fillText(degInt + "\u00B0", plotMinX - 14, p.y)
            }

            // background lattice
            const dotRadius = Math.max(1.0, Math.min(cellWidth, cellHeight) * 0.22)
            ctx.fillStyle = "rgba(255,255,255," + sel.backgroundOpacity + ")"
            const coords = sel.backgroundCoords
            for (let i = 0; i < coords.length; i++) {
                if (coords[i].div > sel.maxDivisions) continue
                const p = position(coords[i].div, coords[i].deg)
                ctx.beginPath()
                ctx.arc(p.x, p.y, dotRadius, 0, Math.PI * 2)
                ctx.fill()
            }

            // active layer
            const activations = sel.computeActivations(date)
            const actDotRadius = Math.max(1.5, Math.min(cellWidth, cellHeight) * 0.28)
            const haloRadius = actDotRadius * 2.6

            // faint guide ticks for off-grid angles
            const offGrid = {}
            for (let i = 0; i < activations.length; i++) {
                if (!activations[i].onGrid) offGrid[sel.quantize(activations[i].deg)] = true
            }
            for (const q in offGrid) {
                const p = position(3, Number(q) / 100.0)
                ctx.strokeStyle = "rgba(255,255,255,0.06)"
                ctx.lineWidth = 0.5
                ctx.beginPath()
                ctx.moveTo(plotMinX, p.y)
                ctx.lineTo(plotMinX + w, p.y)
                ctx.stroke()
            }

            for (let i = 0; i < activations.length; i++) {
                const act = activations[i]
                const p = position(act.div, act.deg)

                ctx.beginPath()
                ctx.arc(p.x, p.y, haloRadius, 0, Math.PI * 2)
                ctx.fillStyle = "rgba(255,255,255," + (0.18 * act.glow).toFixed(3) + ")"
                ctx.fill()

                ctx.beginPath()
                ctx.arc(p.x, p.y, actDotRadius * 1.6, 0, Math.PI * 2)
                ctx.fillStyle = "rgba(255,255,255," + (0.28 * act.glow).toFixed(3) + ")"
                ctx.fill()

                ctx.beginPath()
                ctx.arc(p.x, p.y, actDotRadius, 0, Math.PI * 2)
                ctx.fillStyle = "rgba(255,255,255,"
                    + Math.min(1.0, 0.55 + 0.45 * act.glow).toFixed(3) + ")"
                ctx.fill()
            }
            ctx.textBaseline = "alphabetic"
        }
    }
}