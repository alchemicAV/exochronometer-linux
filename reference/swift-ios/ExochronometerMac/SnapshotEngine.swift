import AppKit
import Foundation
import SwiftUI
import ExochronometerCore

/// What caused a snapshot to fire. Used in filenames, captions, and the
/// future trigger UI. Phase 1: only `.manual` is in use; the rest of the
/// cases are placeholders so the rule engine can adopt them without
/// changing this enum.
public enum SnapshotTrigger: String, Codable, CaseIterable, Sendable {
    case manual
    case yearGeometryPeak, moonGeometryPeak
    case dayBoundary, halfDayBoundary
    case dissonanceHigh, dissonanceLow
    case dissonanceExtremeHigh, dissonanceExtremeLow
    case entropyHigh, entropyLow
    case entropyExtremeHigh, entropyExtremeLow
    case chordOnset
    case phaseClosed                    // any 2+ timeframes simultaneously closed
    case phaseClosedYear, phaseClosedMoon, phaseClosedQuarterMoon
    case phaseClosedDay, phaseClosedHour

    // Legacy cases — kept so persisted user rules from older versions
    // still decode. They no longer appear in `makeDefaultRules` or in
    // the settings UI, and are force-disabled on the first launch
    // after upgrading via the evaluator's one-time migration.
    case newMoon, fullMoon, firstQuarter, lastQuarter
    case yearBoundary

    /// Cases whose semantic was superseded by yearGeometryPeak /
    /// moonGeometryPeak. The init migration disables any saved rules
    /// of these kinds so they stop firing.
    public static let legacyReplacedByGeometryPeak: Set<SnapshotTrigger> = [
        .newMoon, .fullMoon, .firstQuarter, .lastQuarter, .yearBoundary
    ]

    public var displayName: String {
        switch self {
        case .manual:                  return "Manual"
        case .yearGeometryPeak:        return "Year Geometry Peak"
        case .moonGeometryPeak:        return "Moon Geometry Peak"
        case .newMoon:                 return "New Moon (legacy)"
        case .fullMoon:                return "Full Moon (legacy)"
        case .firstQuarter:            return "First Quarter (legacy)"
        case .lastQuarter:             return "Last Quarter (legacy)"
        case .yearBoundary:            return "Year Boundary (legacy)"
        case .dayBoundary:             return "Day Boundary"
        case .halfDayBoundary:         return "Half-Day Boundary"
        case .dissonanceHigh:          return "Dissonance Peak"
        case .dissonanceLow:           return "Dissonance Trough"
        case .dissonanceExtremeHigh:   return "Dissonance Extreme High"
        case .dissonanceExtremeLow:    return "Dissonance Extreme Low"
        case .entropyHigh:             return "Entropy Peak"
        case .entropyLow:              return "Entropy Trough"
        case .entropyExtremeHigh:      return "Entropy Extreme High"
        case .entropyExtremeLow:       return "Entropy Extreme Low"
        case .chordOnset:              return "Chord Onset"
        case .phaseClosed:             return "Phase Closure (multi)"
        case .phaseClosedYear:         return "Phase Closure · Year"
        case .phaseClosedMoon:         return "Phase Closure · Moon"
        case .phaseClosedQuarterMoon:  return "Phase Closure · Quarter Moon"
        case .phaseClosedDay:          return "Phase Closure · Day"
        case .phaseClosedHour:         return "Phase Closure · Hour"
        }
    }

    /// Short slug used inside saved filenames.
    public var slug: String { rawValue }

    /// Default cooldown in seconds. Periodic events get long defaults so
    /// they don't double-fire across a tick boundary; event-driven ones
    /// get shorter cooldowns since the underlying condition can re-arm.
    public var defaultCooldown: TimeInterval {
        switch self {
        case .manual:                  return 0
        case .yearGeometryPeak:        return 1800   // year peaks are sparse (~weeks apart)
        case .moonGeometryPeak:        return 1800   // moon peaks are sparse (~days apart)
        case .newMoon, .fullMoon, .firstQuarter, .lastQuarter:
                                       return 12 * 3600   // legacy
        case .yearBoundary:            return 24 * 3600   // legacy
        case .dayBoundary:             return 4 * 3600
        case .halfDayBoundary:         return 2 * 3600
        case .dissonanceHigh, .dissonanceLow,
             .entropyHigh, .entropyLow: return 3600
        case .dissonanceExtremeHigh, .dissonanceExtremeLow,
             .entropyExtremeHigh, .entropyExtremeLow:
                                       return 1800
        case .chordOnset:              return 600
        case .phaseClosed:             return 1800
        case .phaseClosedYear, .phaseClosedMoon, .phaseClosedQuarterMoon,
             .phaseClosedDay, .phaseClosedHour:
                                       return 1800
        }
    }
}

/// A single fired snapshot — image on disk + caption text + which rule
/// caused it. Future trigger engine returns these to a sink (e.g. an
/// X-poster) that decides whether to publish.
public struct SnapshotArtifact: Sendable {
    public let imageURL: URL
    public let textURL: URL
    public let trigger: SnapshotTrigger
    public let stats: SnapshotStats
    public let firedAt: Date
}

/// Captures the current canvas to a PNG and writes a side-by-side `.txt`
/// caption derived from `SnapshotStats`. The capture path is independent
/// of *what* triggered it, so manual and future automated firings share
/// one code path.
@MainActor
public final class SnapshotEngine {
    public static let shared = SnapshotEngine()

    /// Override-able output directory. Defaults to ~/Pictures/Exochronometer.
    public var outputDirectory: URL = SnapshotEngine.defaultDirectory

    public static var defaultDirectory: URL {
        let pictures = FileManager.default
            .urls(for: .picturesDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
        return pictures.appendingPathComponent("Exochronometer", isDirectory: true)
    }

    /// Render `content` to a PNG at 2x scale and emit a `.txt` sidecar with
    /// the formatted caption. The view must already be fully sized via
    /// `.frame(width:height:)` upstream — we don't impose a layout.
    public func capture<V: View>(
        content: V,
        renderSize: CGSize,
        trigger: SnapshotTrigger,
        stats: SnapshotStats
    ) throws -> SnapshotArtifact {
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2.0
        renderer.proposedSize = ProposedViewSize(renderSize)

        guard let image = renderer.nsImage else {
            throw SnapshotError.renderFailed
        }
        guard let pngData = pngData(from: image) else {
            throw SnapshotError.encodeFailed
        }

        let now = Date()
        let base = filenameBase(for: trigger, at: now)
        let imageURL = outputDirectory.appendingPathComponent(base + ".png")
        let textURL  = outputDirectory.appendingPathComponent(base + ".txt")

        try pngData.write(to: imageURL)
        try stats.formatCaption(trigger: trigger).write(to: textURL, atomically: true, encoding: .utf8)

        return SnapshotArtifact(
            imageURL: imageURL,
            textURL: textURL,
            trigger: trigger,
            stats: stats,
            firedAt: now
        )
    }

    private func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func filenameBase(for trigger: SnapshotTrigger, at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "exo_\(formatter.string(from: date))_\(trigger.slug)"
    }
}

public enum SnapshotError: Error {
    case renderFailed
    case encodeFailed
}
