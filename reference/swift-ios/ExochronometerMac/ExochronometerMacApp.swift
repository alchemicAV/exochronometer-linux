import SwiftData
import SwiftUI
import ExochronometerCore

@main
struct ExochronometerMacApp: App {
    var body: some Scene {
        WindowGroup("Exochronometer") {
            ContentView()
                .preferredColorScheme(.dark)
                .frame(minWidth: 800, minHeight: 600)
                .onOpenURL { url in
                    // X OAuth 2.0 redirect lands here via the
                    // exochronometer:// scheme registered in Info.plist.
                    XAuthService.shared.handleRedirect(url)
                }
                .task {
                    // Warm the keychain cache once at launch so every
                    // login-password prompt clusters here, up front,
                    // instead of trickling in at the first post during
                    // an unattended run. Off the main actor so the
                    // modal prompts don't block UI setup.
                    await Task.detached(priority: .utility) {
                        XKeychain.preload()
                    }.value
                }
        }
        .modelContainer(for: JournalNote.self)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: true))
        .defaultSize(width: 1400, height: 900)
        .commands {
            CommandMenu("Calibration") {
                Button("Run 1-Year Dissonance Simulation (1 min sampling)") {
                    runCalibration(samplingSeconds: 60)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button("Run 1-Year Dissonance Simulation (5 min sampling, faster)") {
                    runCalibration(samplingSeconds: 300)
                }
            }
        }
    }

    /// Fired off the main thread so the UI doesn't freeze for the few
    /// seconds the simulation takes. Output goes to stderr/console.
    private func runCalibration(samplingSeconds: Double) {
        Task.detached(priority: .userInitiated) {
            print("[Calibration] starting…")
            let started = Date()
            let stats = DissonanceCalibrator.simulate(
                sampleIntervalSeconds: samplingSeconds
            )
            let elapsed = Date().timeIntervalSince(started)
            print("[Calibration] finished in \(String(format: "%.2f", elapsed))s")
            print(stats.description)
        }
    }
}
