// Renders the app icon (1024x1024 PNG) using the same geometry math the
// app uses at runtime. Run from the repo root:
//
//   swift Tools/GenerateAppIcon.swift Exochronometer/Assets.xcassets/AppIcon.appiconset/icon-1024.png
//
// The geometry math here mirrors ExochronometerCore.GeometryMath. If the
// app's default shape list changes, update both — there's no shared
// module because this is a free-standing script.

import Foundation
import AppKit
import CoreGraphics

// MARK: - Geometry math (mirror of ExochronometerCore.GeometryMath)

func gcd(_ a: Int, _ b: Int) -> Int {
    var a = abs(a), b = abs(b)
    while b != 0 { (a, b) = (b, a % b) }
    return a
}

struct Edge {
    let from: Int
    let to: Int
}

struct Shape {
    let divisions: Int
    let skip: Int
    let path: [Edge]
}

func generateShapePath(divisions: Int, skip: Int) -> [Edge] {
    var path: [Edge] = []
    var visited: Set<Int> = []
    for start in 0..<divisions {
        if visited.contains(start) { continue }
        var current = start
        while !visited.contains(current) {
            visited.insert(current)
            let next = (current + skip) % divisions
            path.append(Edge(from: current, to: next))
            current = next
        }
    }
    return path
}

func buildShapeList(minDiv: Int = 3, maxDiv: Int = 8) -> [Shape] {
    var out: [Shape] = []
    for div in minDiv...maxDiv {
        for skip in 1..<div {
            if Double(skip) >= Double(div) / 2 { continue }
            if gcd(div, skip) != 1 { continue }
            out.append(Shape(
                divisions: div,
                skip: skip,
                path: generateShapePath(divisions: div, skip: skip)
            ))
        }
    }
    return out
}

// MARK: - Render

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon-1024.png"

let size: CGFloat = 1024
let pad: CGFloat = 96
let radius = (size - 2 * pad) / 2
let center = CGPoint(x: size / 2, y: size / 2)

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write(Data("Failed to create CGContext\n".utf8))
    exit(1)
}

// Background
ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// Outer circle
ctx.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 0.9)
ctx.setLineWidth(10)
ctx.strokeEllipse(in: CGRect(
    x: center.x - radius,
    y: center.y - radius,
    width: 2 * radius,
    height: 2 * radius
))

// All inscribed shapes — at 0° every shape has a node at the top,
// so all lines converge there.
ctx.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 0.75)
ctx.setLineWidth(6)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

let shapes = buildShapeList()
for shape in shapes {
    var points: [CGPoint] = []
    points.reserveCapacity(shape.divisions)
    for i in 0..<shape.divisions {
        let deg = Double(i) * 360.0 / Double(shape.divisions)
        let rad = deg * .pi / 180
        // CoreGraphics is y-up. 0° = top = +y.
        points.append(CGPoint(
            x: center.x + radius * CGFloat(sin(rad)),
            y: center.y + radius * CGFloat(cos(rad))
        ))
    }
    ctx.beginPath()
    for edge in shape.path {
        ctx.move(to: points[edge.from])
        ctx.addLine(to: points[edge.to])
    }
    ctx.strokePath()
}

// Indicator dot at 0° (top of circle)
let dotRadius: CGFloat = 44
let dotCenter = CGPoint(x: center.x, y: center.y + radius)
ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
ctx.fillEllipse(in: CGRect(
    x: dotCenter.x - dotRadius,
    y: dotCenter.y - dotRadius,
    width: 2 * dotRadius,
    height: 2 * dotRadius
))

// Save PNG
guard let cgImage = ctx.makeImage() else {
    FileHandle.standardError.write(Data("Failed to make CGImage\n".utf8))
    exit(1)
}
let rep = NSBitmapImageRep(cgImage: cgImage)
guard let pngData = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("Failed to encode PNG\n".utf8))
    exit(1)
}

let url = URL(fileURLWithPath: outPath)
do {
    try pngData.write(to: url)
    print("Wrote \(url.path) — \(shapes.count) shapes, \(Int(size))x\(Int(size))")
} catch {
    FileHandle.standardError.write(Data("Failed to write: \(error)\n".utf8))
    exit(1)
}
