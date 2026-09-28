import AppKit
import AVFoundation
import ExochronometerCore
import ScreenCaptureKit
import SwiftUI

/// Records the app's own window — the live canvas, the moving synth knobs, the
/// cursor — plus its audio, to a heavily-compressed H.264/MP4 suitable for
/// posting. ScreenCaptureKit gives video and (system) audio on one clock, so
/// A/V stays in sync without cross-clock math.
///
/// Compression is the whole point: the canvas is thin light line-art on black,
/// which an inter-frame codec eats for breakfast. We lean on a low average
/// bitrate, B-frames, CABAC, and a long GOP. Output is H.264 in MP4 (not HEVC)
/// because X reliably ingests H.264 and re-encodes regardless — HEVC would only
/// risk rejection for no post-upload gain.
final class CanvasRecorder: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var statusMessage: String?
    @Published private(set) var lastURL: URL?

    /// Compression presets. "Small" is the default; "Tiny" for the smallest
    /// postable file; "High" when fidelity matters more than bytes.
    enum Quality: String, CaseIterable, Identifiable {
        case tiny, small, high
        var id: String { rawValue }

        var label: String {
            switch self {
            case .tiny:  return "Tiny (~3 MB/30s)"
            case .small: return "Small (~6 MB/30s)"
            case .high:  return "High (~22 MB/30s)"
            }
        }
        /// Longest output edge in pixels — content is downscaled to fit.
        var maxDimension: CGFloat {
            switch self {
            case .tiny:  return 720
            case .small: return 1080
            case .high:  return 1440
            }
        }
        var fps: Int { self == .high ? 30 : 30 }
        var videoBitrate: Int {
            switch self {
            case .tiny:  return 800_000
            case .small: return 1_800_000
            case .high:  return 6_000_000
            }
        }
        var audioBitrate: Int { self == .tiny ? 64_000 : 96_000 }
    }

    var quality: Quality = .small

    /// The synth engine. While recording we force audio on (so the clip has
    /// sound), then restore its prior on/off state when recording ends.
    weak var audio: HarmonicAudio?
    private var managedAudio = false
    private var audioWasRunning = false

    // Writer + stream state. After `start()` returns, the writer/inputs are
    // only touched on `sampleQueue`, which also serves both stream outputs —
    // so `sessionStarted` and the appends never race.
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var running = false
    private let sampleQueue = DispatchQueue(label: "com.alchemicav.exo.recorder.samples")
    private var timer: Timer?
    private var startedAt: Date?

    // MARK: - Control

    func toggle(window: NSWindow?) {
        if isRecording { stop() } else { Task { await start(window: window) } }
    }

    @MainActor
    func start(window: NSWindow?) async {
        guard !running else { return }
        guard let window else {
            statusMessage = "No window to record."
            return
        }
        statusMessage = nil

        do {
            let scWindow = try await resolveWindow(windowNumber: window.windowNumber)
            let (pxW, pxH) = outputSize(for: window)

            let url = makeOutputURL()
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            writer.shouldOptimizeForNetworkUse = true   // moov atom up front

            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings(width: pxW, height: pxH))
            videoInput.expectsMediaDataInRealTime = true
            guard writer.canAdd(videoInput) else { throw RecorderError.cannotConfigure }
            writer.add(videoInput)

            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings())
            audioInput.expectsMediaDataInRealTime = true
            if writer.canAdd(audioInput) { writer.add(audioInput) }

            let config = SCStreamConfiguration()
            config.width = pxW
            config.height = pxH
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(quality.fps))
            config.queueDepth = 6
            config.showsCursor = true                   // show the knob adjustments
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = false   // keep OUR synth audio
            config.sampleRate = 44_100
            config.channelCount = 2

            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)

            self.writer = writer
            self.videoInput = videoInput
            self.audioInput = audioInput
            self.stream = stream
            self.sessionStarted = false
            self.lastURL = url

            // Force the synth on so the clip has sound; remember prior state.
            if let a = audio {
                managedAudio = true
                audioWasRunning = a.isRunning
                if !a.isRunning { a.start() }
            }

            try await stream.startCapture()
            self.running = true
            self.isRecording = true
            self.startedAt = Date()
            self.startTimer()
        } catch {
            restoreAudio()
            teardownState()
            statusMessage = recorderMessage(for: error)
        }
    }

    /// Put audio back the way it was before recording forced it on.
    @MainActor
    private func restoreAudio() {
        guard managedAudio else { return }
        managedAudio = false
        if let a = audio, !audioWasRunning { a.stop() }
    }

    func stop() {
        guard running else { return }
        running = false
        let stream = self.stream
        Task { @MainActor in
            self.isRecording = false
            self.stopTimer()
            try? await stream?.stopCapture()
            self.restoreAudio()
            self.finishWriting()
        }
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard running, sampleBuffer.isValid, CMSampleBufferGetNumSamples(sampleBuffer) > 0 else { return }
        switch type {
        case .screen: handleVideo(sampleBuffer)
        case .audio:  handleAudio(sampleBuffer)
        default: break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        running = false
        Task { @MainActor in
            self.isRecording = false
            self.stopTimer()
            self.restoreAudio()
            self.statusMessage = self.recorderMessage(for: error)
            self.finishWriting()
        }
    }

    private func handleVideo(_ sampleBuffer: CMSampleBuffer) {
        // Only commit frames the compositor marked complete; idle/blank frames
        // carry a non-complete status and would just bloat the file.
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let statusRaw = attachments.first?[.status] as? Int,
            SCFrameStatus(rawValue: statusRaw) == .complete
        else { return }

        guard let writer, let videoInput else { return }

        if !sessionStarted {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: pts)
            sessionStarted = true
        }
        if videoInput.isReadyForMoreMediaData {
            videoInput.append(sampleBuffer)
        }
    }

    private func handleAudio(_ sampleBuffer: CMSampleBuffer) {
        guard sessionStarted, let audioInput, audioInput.isReadyForMoreMediaData else { return }
        audioInput.append(sampleBuffer)
    }

    // MARK: - Finalize

    /// Must run after `stream.stopCapture()` so no more samples arrive. We hop
    /// onto `sampleQueue` to serialize with any in-flight append.
    @MainActor
    private func finishWriting() {
        guard let writer = self.writer else { teardownState(); return }
        let video = videoInput
        let audio = audioInput
        let started = sessionStarted
        sampleQueue.async {
            guard started, writer.status == .writing else {
                writer.cancelWriting()
                Task { @MainActor in
                    self.statusMessage = "Nothing recorded."
                    self.teardownState()
                }
                return
            }
            video?.markAsFinished()
            audio?.markAsFinished()
            writer.finishWriting {
                Task { @MainActor in
                    if writer.status == .completed, let url = writer.outputURL as URL? {
                        self.lastURL = url
                        self.statusMessage = "Saved \(url.lastPathComponent)"
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } else {
                        self.statusMessage = writer.error?.localizedDescription ?? "Recording failed."
                    }
                    self.teardownState()
                }
            }
        }
    }

    @MainActor
    private func teardownState() {
        stream = nil
        writer = nil
        videoInput = nil
        audioInput = nil
        sessionStarted = false
        running = false
        elapsed = 0
        startedAt = nil
    }

    // MARK: - Settings

    private func videoSettings(width: Int, height: Int) -> [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: quality.videoBitrate,
                AVVideoMaxKeyFrameIntervalKey: quality.fps * 4,     // ~4s GOP
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAllowFrameReorderingKey: true,               // B-frames
                AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
                AVVideoExpectedSourceFrameRateKey: quality.fps,
            ],
        ]
    }

    private func audioSettings() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: quality.audioBitrate,
        ]
    }

    // MARK: - Window / sizing

    private func resolveWindow(windowNumber: Int) async throws -> SCWindow {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let wantedID = CGWindowID(windowNumber)
        if let match = content.windows.first(where: { $0.windowID == wantedID }) {
            return match
        }
        // Fallback: the largest on-screen window owned by this process.
        let pid = ProcessInfo.processInfo.processIdentifier
        let mine = content.windows
            .filter { $0.owningApplication?.processID == pid && $0.isOnScreen }
            .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
        guard let mine else { throw RecorderError.windowNotFound }
        return mine
    }

    /// Output pixel size: the window at backing scale, downscaled so the
    /// longest edge fits the quality cap, rounded to even (H.264 needs even).
    @MainActor
    private func outputSize(for window: NSWindow) -> (Int, Int) {
        let scale = window.backingScaleFactor
        let size = window.frame.size
        var pxW = size.width * scale
        var pxH = size.height * scale
        let longest = max(pxW, pxH)
        let cap = quality.maxDimension
        if longest > cap {
            let f = cap / longest
            pxW *= f
            pxH *= f
        }
        func even(_ v: CGFloat) -> Int { let n = Int(v.rounded()); return n - (n % 2) }
        return (max(2, even(pxW)), max(2, even(pxH)))
    }

    @MainActor
    private func makeOutputURL() -> URL {
        let dir = SnapshotEngine.defaultDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        return dir.appendingPathComponent("exo-recording-\(fmt.string(from: Date())).mp4")
    }

    // MARK: - Timer

    @MainActor
    private func startTimer() {
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let started = self.startedAt else { return }
            self.elapsed = Date().timeIntervalSince(started)
        }
    }

    @MainActor
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Errors

    private enum RecorderError: Error { case cannotConfigure, windowNotFound }

    private func recorderMessage(for error: Error) -> String {
        let ns = error as NSError
        // TCC denial surfaces from ScreenCaptureKit's domain.
        if ns.domain == SCStreamErrorDomain {
            return "Allow Screen Recording for Exochronometer in System Settings ▸ Privacy & Security, then try again."
        }
        return ns.localizedDescription
    }
}
