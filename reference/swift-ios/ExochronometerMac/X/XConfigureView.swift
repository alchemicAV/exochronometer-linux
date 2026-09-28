import SwiftUI

/// Sheet for setting X credentials, signing in via OAuth 2.0, and
/// firing a test post to verify the whole pipeline end-to-end before
/// auto-posting triggers go live.
struct XConfigureView: View {
    @ObservedObject var auth: XAuthService = .shared
    @Environment(\.dismiss) private var dismiss

    @State private var clientID: String = XKeychain.get(.clientID) ?? ""
    @State private var clientSecret: String = XKeychain.get(.clientSecret) ?? ""
    @State private var testResult: TestResult = .idle
    @State private var isTestingPost: Bool = false

    private enum TestResult: Equatable {
        case idle
        case posting
        case ok(URL)
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            credentialsBlock
            Divider()
            authBlock
            Divider()
            testBlock
            Spacer()
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 540)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Configure X")
                .font(.system(size: 15, weight: .medium))
            Text("OAuth 2.0 with PKCE · credentials stored in macOS Keychain.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var credentialsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CREDENTIALS")
                .font(.system(size: 9, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.secondary)
            HStack {
                Text("Client ID:")
                    .frame(width: 90, alignment: .trailing)
                TextField("from X Developer Portal", text: $clientID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
            }
            HStack {
                Text("Client Secret:")
                    .frame(width: 90, alignment: .trailing)
                SecureField("from X Developer Portal", text: $clientSecret)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
            }
            HStack {
                Spacer()
                Button("Save to Keychain") {
                    XKeychain.set(clientID.trimmingCharacters(in: .whitespacesAndNewlines), for: .clientID)
                    XKeychain.set(clientSecret.trimmingCharacters(in: .whitespacesAndNewlines), for: .clientSecret)
                }
                .controlSize(.small)
                .disabled(clientID.isEmpty || clientSecret.isEmpty)
            }
            Text("Redirect URI registered with X: exochronometer://oauth/callback")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var authBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AUTH STATE")
                .font(.system(size: 9, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.secondary)
            HStack {
                authStateIcon
                Text(authStateText)
                    .font(.system(size: 11))
                Spacer()
                switch auth.authState {
                case .signedIn:
                    Button("Sign out") { auth.signOut() }
                        .controlSize(.small)
                case .authorizing:
                    ProgressView()
                        .scaleEffect(0.5)
                default:
                    Button("Sign in with X") {
                        // Make sure latest credentials are saved before opening browser.
                        XKeychain.set(clientID, for: .clientID)
                        XKeychain.set(clientSecret, for: .clientSecret)
                        auth.beginSignIn()
                    }
                    .controlSize(.small)
                    .disabled(clientID.isEmpty || clientSecret.isEmpty)
                }
            }
            Text("Clicking Sign in opens your browser. After approving, X will redirect back to this app.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var testBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TEST POST")
                .font(.system(size: 9, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.secondary)
            Text("Posts a small \"Exochronometer test · <timestamp>\" message + a 256×256 PNG to verify the auth + media + tweet pipeline before triggers go live. Charged at ~$0.015.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button {
                    Task { await runTestPost() }
                } label: {
                    Label("Send Test Post", systemImage: "paperplane.fill")
                }
                .disabled(!canTest || isTestingPost)
                if isTestingPost { ProgressView().scaleEffect(0.5) }
                Spacer()
            }
            testResultView
        }
    }

    @ViewBuilder
    private var testResultView: some View {
        switch testResult {
        case .idle:
            EmptyView()
        case .posting:
            Text("posting…")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        case .ok(let url):
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Posted.")
                    .font(.system(size: 11))
                Link(url.absoluteString, destination: url)
                    .font(.system(size: 10, design: .monospaced))
            }
        case .failed(let msg):
            HStack(alignment: .top) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(msg)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var canTest: Bool {
        if case .signedIn = auth.authState { return true }
        return false
    }

    private var authStateIcon: some View {
        Group {
            switch auth.authState {
            case .signedOut:
                Image(systemName: "person.crop.circle.badge.xmark")
                    .foregroundStyle(.secondary)
            case .authorizing:
                Image(systemName: "person.crop.circle.badge.clock")
                    .foregroundStyle(.orange)
            case .signedIn:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private var authStateText: String {
        switch auth.authState {
        case .signedOut:                  return "Not signed in."
        case .authorizing:                return "Waiting for browser approval…"
        case .signedIn(let username):     return "Signed in as @\(username)"
        case .error(let msg):             return "Error: \(msg)"
        }
    }

    private func runTestPost() async {
        isTestingPost = true
        testResult = .posting
        do {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            let timestamp = formatter.string(from: Date())
            let text = "Exochronometer test · \(timestamp)"
            let image = Self.makeTestImagePNG(label: timestamp)
            let result = try await XAPIClient.shared.postTweet(text: text, imagePNG: image)
            testResult = .ok(result.tweetURL)
        } catch {
            testResult = .failed(error.localizedDescription)
        }
        isTestingPost = false
    }

    /// Quick 256×256 PNG with the given label rendered onto a black
    /// canvas — enough to round-trip through the media endpoint.
    private static func makeTestImagePNG(label: String) -> Data {
        let renderer = ImageRenderer(content:
            ZStack {
                Color.black
                VStack(spacing: 6) {
                    Text("EXOCHRONOMETER")
                        .font(.system(size: 14, design: .monospaced))
                        .tracking(3)
                        .foregroundStyle(.white)
                    Text(label)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: 256, height: 256)
        )
        renderer.scale = 1.0
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return Data()
        }
        return png
    }
}
