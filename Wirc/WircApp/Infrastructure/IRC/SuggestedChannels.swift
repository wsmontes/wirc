import Foundation

struct SuggestedChannel: Codable, Identifiable {
    var id: String { name }
    let name: String
    let description: String
}

enum SuggestedChannelsLoader {
    static let channels: [SuggestedChannel] = {
        guard let url = Bundle.main.url(forResource: "SuggestedChannels", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let channels = try? JSONDecoder().decode([SuggestedChannel].self, from: data) else {
            return []
        }
        return channels
    }()
}
