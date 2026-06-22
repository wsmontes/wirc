import Foundation

final class MastodonClient: @unchecked Sendable {
    let config: MastodonServerConfig

    private let session: URLSession
    private var rateLimitRemaining: Int = 300
    private var rateLimitReset: Date = .distantPast

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

    // MARK: - Rate Limiting

    private func updateRateLimits(from response: HTTPURLResponse) {
        if let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining") {
            rateLimitRemaining = Int(remaining) ?? rateLimitRemaining
        }
        if let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset") {
            if let epoch = Double(reset) {
                rateLimitReset = Date(timeIntervalSince1970: epoch)
            }
        }
    }

    private func checkRateLimit() async throws {
        if rateLimitRemaining <= 0 && Date() < rateLimitReset {
            let wait = rateLimitReset.timeIntervalSinceNow
            if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
        }
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
        try await checkRateLimit()
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse {
            updateRateLimits(from: http)
            if http.statusCode >= 400 {
                throw MastodonError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable>(_ url: URL, params: [String: String]) async throws -> T {
        try await checkRateLimit()
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var comps = URLComponents()
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = comps.query?.data(using: .utf8)
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse {
            updateRateLimits(from: http)
            if http.statusCode >= 400 {
                throw MastodonError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - OAuth

    /// Response from POST /api/v1/apps (dynamic client registration).
    struct ClientRegistration: Codable {
        let id: String
        let clientId: String
        let clientSecret: String
        let name: String
        let redirectUri: String

        enum CodingKeys: String, CodingKey {
            case id
            case clientId = "client_id"
            case clientSecret = "client_secret"
            case name
            case redirectUri = "redirect_uri"
        }
    }

    /// Response from POST /oauth/token (token exchange).
    struct TokenResponse: Codable {
        let accessToken: String
        let tokenType: String
        let scope: String
        let createdAt: Int?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case tokenType = "token_type"
            case scope
            case createdAt = "created_at"
        }
    }

    /// Dynamically register this app on the given Mastodon instance.
    /// Returns client credentials needed for the OAuth flow.
    static func registerApp(instance: String, redirectURI: String = "wirc://oauth/callback") async throws -> ClientRegistration {
        guard let base = URL(string: "https://\(instance)") else {
            throw MastodonError.invalidURL(instance)
        }
        let url = base.appendingPathComponent("/api/v1/apps")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var comps = URLComponents()
        comps.queryItems = [
            URLQueryItem(name: "client_name", value: "Wirc"),
            URLQueryItem(name: "redirect_uris", value: redirectURI),
            URLQueryItem(name: "scopes", value: "read write"),
            URLQueryItem(name: "website", value: "https://github.com/wagnermontes/wirc"),
        ]
        req.httpBody = comps.query?.data(using: .utf8)

        let session = URLSession(configuration: .default)
        let (data, response) = try await session.data(for: req)

        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw MastodonError.http(code, body)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ClientRegistration.self, from: data)
    }

    /// Build the OAuth authorization URL to present in the browser.
    static func oauthURL(instance: String, clientId: String) throws -> URL {
        guard let base = URL(string: "https://\(instance)") else {
            throw MastodonError.invalidURL(instance)
        }
        var components = URLComponents(
            url: base.appendingPathComponent("/oauth/authorize"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: "wirc://oauth/callback"),
            URLQueryItem(name: "scope", value: "read write"),
            URLQueryItem(name: "response_type", value: "code"),
        ]
        guard let url = components?.url else {
            throw MastodonError.invalidURL(instance)
        }
        return url
    }

    /// Exchange the authorization code for an access token.
    static func exchangeCode(code: String, instance: String, clientId: String, clientSecret: String) async throws -> String {
        guard let base = URL(string: "https://\(instance)") else {
            throw MastodonError.invalidURL(instance)
        }
        let url = base.appendingPathComponent("/oauth/token")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var comps = URLComponents()
        comps.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "redirect_uri", value: "wirc://oauth/callback"),
            URLQueryItem(name: "scope", value: "read write"),
        ]
        req.httpBody = comps.query?.data(using: .utf8)

        let session = URLSession(configuration: .default)
        let (data, response) = try await session.data(for: req)

        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw MastodonError.http(code, body)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let tokenResponse = try decoder.decode(TokenResponse.self, from: data)
        return tokenResponse.accessToken
    }
}

enum MastodonError: LocalizedError {
    case http(Int, String)
    case parse(String)
    case invalidURL(String)
    var errorDescription: String? {
        switch self {
        case .http(let code, let body): return "HTTP \(code): \(body.prefix(200))"
        case .parse(let msg): return "Parse: \(msg)"
        case .invalidURL(let str): return "Invalid Mastodon URL: \(str)"
        }
    }
}
