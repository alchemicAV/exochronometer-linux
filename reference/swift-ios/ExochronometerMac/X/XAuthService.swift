import AppKit
import CryptoKit
import Foundation

/// OAuth 2.0 Authorization Code + PKCE flow against x.com. The flow:
///   1. Generate a code verifier (random) and challenge (SHA256 of verifier).
///   2. Open the X authorize URL in the user's browser.
///   3. User approves → X redirects to `exochronometer://oauth/callback?code=…`.
///   4. macOS launches/focuses the app and `handleRedirect` is called.
///   5. We POST the auth code + verifier to /2/oauth2/token, get the access
///      and refresh tokens, persist them in Keychain.
///
/// Refresh tokens rotate single-use, valid 6 months. Access tokens last
/// 2 hours. The token store rotates atomically — see XKeychain.
@MainActor
final class XAuthService: ObservableObject {
    static let shared = XAuthService()

    static let authorizeEndpoint = URL(string: "https://x.com/i/oauth2/authorize")!
    static let tokenEndpoint     = URL(string: "https://api.x.com/2/oauth2/token")!
    static let redirectURI       = "exochronometer://oauth/callback"
    static let scopes            = ["tweet.read", "tweet.write", "users.read",
                                    "media.write", "offline.access"]

    @Published private(set) var authState: AuthState = .signedOut

    enum AuthState: Equatable {
        case signedOut
        case authorizing
        case signedIn(username: String)
        case error(String)
    }

    /// PKCE verifier kept in memory while a sign-in is in flight. Cleared
    /// after token exchange (or on cancel). The matching state is also
    /// kept here so we can validate the redirect.
    private var pendingVerifier: String?
    private var pendingState: String?

    /// In-flight token refresh, if any. Concurrent posts (multiple triggers
    /// in one tick, or a post + its chord reply) would otherwise each kick
    /// off their own refresh and race on X's single-use refresh token,
    /// corrupting the stored token + stranding the expiry. We coalesce them
    /// onto one refresh — see `refreshAccessTokenCoalesced`.
    private var refreshTask: Task<Void, Error>?

    private init() {
        // Restore "signed in" state if we have credentials persisted.
        if XKeychain.get(.refreshToken) != nil,
           let username = XKeychain.get(.authedUsername) {
            authState = .signedIn(username: username)
        }
    }

    /// Kick off the sign-in flow. Opens the user's browser to X's
    /// authorize URL.
    func beginSignIn() {
        guard let clientID = XKeychain.get(.clientID), !clientID.isEmpty else {
            authState = .error("Client ID not set — paste it in Configure X first.")
            return
        }
        let verifier = Self.generateCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomURLSafe(32)
        pendingVerifier = verifier
        pendingState = state

        var comps = URLComponents(url: Self.authorizeEndpoint, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "client_id",             value: clientID),
            URLQueryItem(name: "redirect_uri",          value: Self.redirectURI),
            URLQueryItem(name: "scope",                 value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "state",                 value: state),
            URLQueryItem(name: "code_challenge",        value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let url = comps.url else {
            authState = .error("Failed to build authorize URL.")
            return
        }
        authState = .authorizing
        NSWorkspace.shared.open(url)
    }

    /// Called when the browser hands us the redirect URL. Extracts the
    /// auth code (or error), validates state, and exchanges for tokens.
    func handleRedirect(_ url: URL) {
        guard url.scheme == "exochronometer" else { return }
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let items = comps.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }

        if let error = value("error") {
            authState = .error("X rejected the sign-in: \(error)")
            pendingVerifier = nil
            pendingState = nil
            return
        }

        guard let code = value("code") else {
            authState = .error("No auth code in redirect.")
            return
        }
        guard let state = value("state"), state == pendingState else {
            authState = .error("OAuth state mismatch — possible session leak.")
            return
        }
        guard let verifier = pendingVerifier else {
            authState = .error("Verifier missing — sign-in not initiated by this session.")
            return
        }

        Task { await exchangeCodeForTokens(code: code, verifier: verifier) }
    }

    /// Exchange the authorization code for an access + refresh token pair.
    private func exchangeCodeForTokens(code: String, verifier: String) async {
        guard let clientID = XKeychain.get(.clientID), !clientID.isEmpty else {
            authState = .error("Client ID missing during token exchange.")
            return
        }
        let body: [String: String] = [
            "code": code,
            "grant_type": "authorization_code",
            "client_id": clientID,
            "redirect_uri": Self.redirectURI,
            "code_verifier": verifier
        ]
        do {
            let response = try await postFormToToken(body: body)
            try await persist(tokenResponse: response)
            try await fetchAndStoreAuthedUser()
            if let username = XKeychain.get(.authedUsername) {
                authState = .signedIn(username: username)
            }
            pendingVerifier = nil
            pendingState = nil
        } catch {
            authState = .error("Token exchange failed: \(error.localizedDescription)")
        }
    }

    /// Use the stored refresh token to get a fresh access token. X rotates
    /// the refresh token on every refresh, so we MUST persist the new
    /// refresh token atomically (see XKeychain.rotateRefreshToken).
    func refreshAccessToken() async throws {
        guard let clientID = XKeychain.get(.clientID), !clientID.isEmpty,
              let refresh = XKeychain.get(.refreshToken) else {
            throw XError.notAuthenticated
        }
        let body: [String: String] = [
            "refresh_token": refresh,
            "grant_type": "refresh_token",
            "client_id": clientID
        ]
        let response = try await postFormToToken(body: body)
        try await persist(tokenResponse: response)
    }

    /// Returns a currently-valid access token, refreshing if needed.
    func currentAccessToken() async throws -> String {
        if let expiryStr = XKeychain.get(.accessTokenExpiry),
           let expiry = ISO8601DateFormatter().date(from: expiryStr),
           Date() < expiry.addingTimeInterval(-60),
           let token = XKeychain.get(.accessToken) {
            return token
        }
        // Stale or missing → refresh, coalescing concurrent callers.
        try await refreshAccessTokenCoalesced()
        guard let token = XKeychain.get(.accessToken) else {
            throw XError.notAuthenticated
        }
        return token
    }

    /// Single-flight wrapper around `refreshAccessToken`. If a refresh is
    /// already running, await it instead of starting a second one. The
    /// `@MainActor` isolation makes the check-and-set of `refreshTask`
    /// atomic (no `await` between them), so two callers can't both start a
    /// refresh and race on the single-use refresh token.
    private func refreshAccessTokenCoalesced() async throws {
        if let existing = refreshTask {
            try await existing.value
            return
        }
        let task = Task { try await self.refreshAccessToken() }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    func signOut() {
        XKeychain.delete(.accessToken)
        XKeychain.delete(.refreshToken)
        XKeychain.delete(.accessTokenExpiry)
        XKeychain.delete(.authedUsername)
        XKeychain.delete(.authedUserID)
        authState = .signedOut
    }

    // MARK: HTTP helpers

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int?
        let token_type: String
        let scope: String?
    }

    private func postFormToToken(body: [String: String]) async throws -> TokenResponse {
        var req = URLRequest(url: Self.tokenEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // Confidential clients: HTTP Basic auth with clientID:clientSecret.
        if let clientID = XKeychain.get(.clientID),
           let secret = XKeychain.get(.clientSecret),
           !clientID.isEmpty, !secret.isEmpty {
            let raw = "\(clientID):\(secret)"
            let b64 = Data(raw.utf8).base64EncodedString()
            req.setValue("Basic \(b64)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = encodeForm(body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw XError.http("Token endpoint failed: \(snippet)")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func persist(tokenResponse r: TokenResponse) async throws {
        XKeychain.set(r.access_token, for: .accessToken)
        // Write the expiry immediately after the access token, BEFORE
        // rotating the refresh token. If rotation throws, the access token
        // and its expiry are still consistent, so `currentAccessToken()`
        // won't keep seeing a stale expiry and refresh on every post — the
        // loop that stranded the expiry and re-prompted the keychain.
        let expiry = Date().addingTimeInterval(TimeInterval(r.expires_in ?? 7200))
        XKeychain.set(ISO8601DateFormatter().string(from: expiry), for: .accessTokenExpiry)
        if let newRefresh = r.refresh_token {
            guard XKeychain.rotateRefreshToken(newRefresh) else {
                throw XError.keychain("Failed to rotate refresh token.")
            }
        }
    }

    private func fetchAndStoreAuthedUser() async throws {
        guard let token = XKeychain.get(.accessToken) else { return }
        var req = URLRequest(url: URL(string: "https://api.x.com/2/users/me")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        struct UserResponse: Decodable {
            struct User: Decodable { let id: String; let username: String }
            let data: User
        }
        let user = try JSONDecoder().decode(UserResponse.self, from: data).data
        XKeychain.set(user.id, for: .authedUserID)
        XKeychain.set(user.username, for: .authedUsername)
    }

    // MARK: PKCE helpers

    private static func generateCodeVerifier() -> String {
        // 64 bytes → 86 base64url chars, comfortably inside the 43-128 limit.
        randomURLSafe(64)
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString()
    }

    private static func randomURLSafe(_ byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private func encodeForm(_ body: [String: String]) -> Data {
        let pairs = body
            .map { (k, v) -> String in
                let ek = k.addingPercentEncoding(withAllowedCharacters: .urlFormPart) ?? k
                let ev = v.addingPercentEncoding(withAllowedCharacters: .urlFormPart) ?? v
                return "\(ek)=\(ev)"
            }
            .joined(separator: "&")
        return Data(pairs.utf8)
    }
}

enum XError: LocalizedError {
    case notAuthenticated
    case http(String)
    case keychain(String)
    case unexpectedResponse(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:       return "Not signed in to X."
        case .http(let m):            return "HTTP error: \(m)"
        case .keychain(let m):        return "Keychain error: \(m)"
        case .unexpectedResponse(let m): return "Unexpected response: \(m)"
        }
    }
}

private extension Data {
    /// Base64URL (RFC 7636): standard base64 with +→-, /→_, no padding.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension CharacterSet {
    /// `application/x-www-form-urlencoded` allows alphanumerics + `-._~`.
    /// Everything else (including space which becomes `+` or `%20`) must
    /// be percent-encoded.
    static let urlFormPart: CharacterSet = {
        var s = CharacterSet.alphanumerics
        s.insert(charactersIn: "-._~")
        return s
    }()
}
