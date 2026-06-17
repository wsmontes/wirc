import Foundation

struct SuggestedServer: Codable, Identifiable {
    var id: String { "\(host):\(port)" }
    let name: String
    let host: String
    let port: Int
    let useTLS: Bool
    let description: String
}

enum SuggestedServersLoader {
    static let servers: [SuggestedServer] = {
        guard let url = Bundle.main.url(forResource: "SuggestedServers", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let servers = try? JSONDecoder().decode([SuggestedServer].self, from: data) else {
            return []
        }
        return servers
    }()
}
