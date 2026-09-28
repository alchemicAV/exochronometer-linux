import Foundation

/// Thin wrapper over the X API v2 endpoints we use:
///   - POST /2/media/upload   (image attachment)
///   - POST /2/tweets         (tweet creation)
///
/// All calls go through `XAuthService.currentAccessToken()` which
/// transparently refreshes the OAuth 2.0 access token when stale.
@MainActor
final class XAPIClient {
    static let shared = XAPIClient()
    private init() {}

    private let mediaUploadEndpoint = URL(string: "https://api.x.com/2/media/upload")!
    private let tweetsEndpoint      = URL(string: "https://api.x.com/2/tweets")!

    struct PostResult {
        let tweetID: String
        let tweetURL: URL
    }

    /// Upload an image (if any) and create a tweet referencing it.
    /// Pass `replyToID` to post this tweet as a reply, threading it under
    /// an earlier tweet (used for the chord-detail follow-up post).
    func postTweet(text: String, imagePNG: Data?, replyToID: String? = nil) async throws -> PostResult {
        var mediaID: String? = nil
        if let imagePNG {
            mediaID = try await uploadImage(pngData: imagePNG)
        }
        return try await createTweet(text: text, mediaID: mediaID, replyToID: replyToID)
    }

    /// POST /2/media/upload — simple (non-chunked) upload for files under
    /// ~5MB, which is all we ever produce. The endpoint accepts OAuth 2.0
    /// Bearer tokens directly as long as the `media.write` scope was
    /// granted. Returns the media id we'll reference from the tweet.
    func uploadImage(pngData: Data) async throws -> String {
        let token = try await XAuthService.shared.currentAccessToken()
        let boundary = "----ExoBoundary-\(UUID().uuidString)"
        var req = URLRequest(url: mediaUploadEndpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }
        // media_category
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"media_category\"\r\n\r\n")
        append("tweet_image\r\n")
        // media field (the bytes)
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"media\"; filename=\"image.png\"\r\n")
        append("Content-Type: image/png\r\n\r\n")
        body.append(pngData)
        append("\r\n")
        append("--\(boundary)--\r\n")
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw XError.http("media/upload failed (\(snippet))")
        }
        // The v2 media endpoint returns either { "data": { "id": "..." } }
        // or { "id": "..." } depending on the rollout window. Handle both.
        struct V2Wrapped: Decodable { struct Inner: Decodable { let id: String }; let data: Inner }
        struct Flat: Decodable { let id: String }
        if let wrapped = try? JSONDecoder().decode(V2Wrapped.self, from: data) {
            return wrapped.data.id
        }
        if let flat = try? JSONDecoder().decode(Flat.self, from: data) {
            return flat.id
        }
        // Some older response shapes use `media_id_string`.
        struct V1: Decodable { let media_id_string: String }
        if let v1 = try? JSONDecoder().decode(V1.self, from: data) {
            return v1.media_id_string
        }
        let snippet = String(data: data, encoding: .utf8) ?? ""
        throw XError.unexpectedResponse("media/upload response shape unknown: \(snippet)")
    }

    /// POST /2/tweets — create a tweet, optionally attaching one media id
    /// and optionally threading it as a reply to `replyToID`.
    func createTweet(text: String, mediaID: String?, replyToID: String? = nil) async throws -> PostResult {
        let token = try await XAuthService.shared.currentAccessToken()
        var body: [String: Any] = ["text": text]
        if let mediaID {
            body["media"] = ["media_ids": [mediaID]]
        }
        if let replyToID {
            body["reply"] = ["in_reply_to_tweet_id": replyToID]
        }
        var req = URLRequest(url: tweetsEndpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw XError.http("/2/tweets failed (\(snippet))")
        }
        struct Resp: Decodable {
            struct Inner: Decodable { let id: String; let text: String }
            let data: Inner
        }
        let parsed = try JSONDecoder().decode(Resp.self, from: data)
        let username = XKeychain.get(.authedUsername) ?? "i"
        let url = URL(string: "https://x.com/\(username)/status/\(parsed.data.id)")
            ?? URL(string: "https://x.com")!
        return PostResult(tweetID: parsed.data.id, tweetURL: url)
    }
}
