import Foundation

final class MastodonClient: @unchecked Sendable {
    let config: MastodonServerConfig

    private let session: URLSession
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init(config: MastodonServerConfig) {
        self.config = config
        let cfg = URLSessionConfiguration.default
        cfg.httpAdditionalHeaders = [
            "Authorization": "Bearer \(config.accessToken)",
            "User-Agent": "Wirc/1.0",
            "Accept": "application/json"
        ]
        self.session = URLSession(configuration: cfg)
    }

    // MARK: - Timelines

    /// Fetch home timeline
    func homeTimeline(maxId: String? = nil, limit: Int = 40) async throws -> MastodonTimeline {
        var url = buildURL("/api/v1/timelines/home")
        url.append(queryItems: [URLQueryItem(name: "limit", value: "\(limit)")])
        if let maxId { url.append(queryItems: [URLQueryItem(name: "max_id", value: maxId)]) }
        return try await get(url)
    }

    /// Fetch public timeline for instance
    func publicTimeline(local: Bool = true, maxId: String? = nil, limit: Int = 40) async throws -> MastodonTimeline {
        var url = buildURL("/api/v1/timelines/public")
        url.append(queryItems: [
            URLQueryItem(name: "local", value: local ? "true" : "false"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ])
        if let maxId { url.append(queryItems: [URLQueryItem(name: "max_id", value: maxId)]) }
        return try await get(url)
    }

    // MARK: - Status Actions

    /// Post a new status
    func postStatus(_ text: String, visibility: String = "public", inReplyToId: String? = nil) async throws -> MastodonStatus {
        var url = buildURL("/api/v1/statuses")
        var params: [String: String] = ["status": text, "visibility": visibility]
        if let replyId = inReplyToId { params["in_reply_to_id"] = replyId }
        return try await post(url, params: params)
    }

    /// Favorite a status
    func favourite(statusId: String) async throws -> MastodonStatus {
        let url = buildURL("/api/v1/statuses/\(statusId)/favourite")
        return try await post(url, params: [:])
    }

    /// Unfavorite a status
    func unfavourite(statusId: String) async throws -> MastodonStatus {
        let url = buildURL("/api/v1/statuses/\(statusId)/unfavourite")
        return try await post(url, params: [:])
    }

    /// Boost a status
    func boost(statusId: String) async throws -> MastodonStatus {
        let url = buildURL("/api/v1/statuses/\(statusId)/reblog")
        return try await post(url, params: [:])
    }

    /// Unboost a status
    func unboost(statusId: String) async throws -> MastodonStatus {
        let url = buildURL("/api/v1/statuses/\(statusId)/unreblog")
        return try await post(url, params: [:])
    }

    /// Fetch account info
    func verifyCredentials() async throws -> MastodonAccount {
        let url = buildURL("/api/v1/accounts/verify_credentials")
        return try await get(url)
    }

    // MARK: - HTTP Helpers

    private func buildURL(_ path: String) -> URL {
        URL(string: config.instanceURL + path)!
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw MastodonError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable>(_ url: URL, params: [String: String]) async throws -> T {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var comps = URLComponents()
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = comps.query?.data(using: .utf8)
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw MastodonError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try decoder.decode(T.self, from: data)
    }
}

enum MastodonError: LocalizedError {
    case http(Int, String)
    case parse(String)
    var errorDescription: String? {
        switch self {
        case .http(let code, let body): return "HTTP \(code): \(body.prefix(200))"
        case .parse(let msg): return "Parse: \(msg)"
        }
    }
}
