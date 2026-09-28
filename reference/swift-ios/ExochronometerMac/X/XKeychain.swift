import Foundation
import Security

/// Thin Keychain wrapper for X (Twitter) credentials. Each item is
/// stored as a generic password under the `service` identifier so we
/// can audit and clear them in one shot.
///
/// Reads are backed by an in-memory cache so the keychain is touched at
/// most once per key per process launch. Under ad-hoc signing (no paid
/// developer program yet) every rebuild is a "new app" to the keychain
/// ACL, so each read otherwise prompts for the login password and the OS
/// won't persist trust across rebuilds. Caching collapses the per-post
/// prompts down to one per key on first access; the cache dies with the
/// process, so it resets on the next rebuild — exactly the intended
/// behaviour. Writes are write-through, keeping the cache and keychain
/// in lockstep.
enum XKeychain {
    private static let service = "com.alchemicav.exochronometer.x"

    private static var cache: [Key: String] = [:]
    private static let cacheLock = NSLock()

    enum Key: String, CaseIterable {
        case clientID         = "clientID"
        case clientSecret     = "clientSecret"
        case accessToken      = "accessToken"
        case refreshToken     = "refreshToken"
        case accessTokenExpiry = "accessTokenExpiry"   // ISO-8601 of expiry
        case authedUsername   = "authedUsername"
        case authedUserID     = "authedUserID"
    }

    static func set(_ value: String?, for key: Key) {
        guard let value, !value.isEmpty else {
            delete(key)
            return
        }
        let data = Data(value.utf8)
        let q: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  key.rawValue
        ]
        // Update the existing item in place rather than delete-then-add.
        // Recreating the item reset its ACL on every write, so a token
        // refresh (~every 2h) produced a brand-new item the keychain didn't
        // recognise — defeating "Always Allow" and re-prompting each refresh,
        // which was fatal for an unattended overnight run. SecItemUpdate
        // preserves the item and the trust granted to it. Fall back to add
        // only when the item doesn't exist yet.
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(q as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }

        cacheLock.lock()
        cache[key] = value
        cacheLock.unlock()
    }

    static func get(_ key: Key) -> String? {
        cacheLock.lock()
        if let cached = cache[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        guard let str = rawGet(key) else { return nil }

        cacheLock.lock()
        cache[key] = str
        cacheLock.unlock()
        return str
    }

    /// Reads straight from the keychain, bypassing the in-memory cache.
    /// Used where we must confirm what actually landed on disk (see
    /// `rotateRefreshToken`). Within a single process this runs right
    /// after our own write, so it does not trigger a fresh prompt.
    private static func rawGet(_ key: Key) -> String? {
        let q: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  key.rawValue,
            kSecMatchLimit as String:   kSecMatchLimitOne,
            kSecReturnData as String:   true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    static func delete(_ key: Key) {
        let q: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  key.rawValue
        ]
        SecItemDelete(q as CFDictionary)

        cacheLock.lock()
        cache[key] = nil
        cacheLock.unlock()
    }

    /// Atomically rotate the refresh token: write the new value, then
    /// immediately verify it before considering the swap complete. X
    /// rotates refresh tokens on every refresh and the old token is
    /// invalidated server-side, so losing the new one locks us out.
    /// Verification reads past the cache so we confirm the keychain
    /// itself persisted the new value, not just our in-memory copy.
    static func rotateRefreshToken(_ newValue: String) -> Bool {
        set(newValue, for: .refreshToken)
        return rawGet(.refreshToken) == newValue
    }

    /// Warm the cache for every key in one go. Call this once at launch
    /// (e.g. right after the user opens the app) so all keychain prompts
    /// happen up front in a single cluster, rather than trickling in at
    /// the first post while the run is meant to be unattended.
    static func preload() {
        for key in Key.allCases { _ = get(key) }
    }

    static func clearAll() {
        for key in Key.allCases { delete(key) }
    }
}
