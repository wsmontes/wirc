import Foundation

struct IRCConnectionConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var useTLS: Bool
    var nickname: String
    var username: String?
    var realName: String?
    var password: String?
    var autoJoinChannels: [String]

    init(
        id: UUID = UUID(),
        name: String = "",
        host: String = "",
        port: Int = 6667,
        useTLS: Bool = false,
        nickname: String = "",
        username: String? = nil,
        realName: String? = nil,
        password: String? = nil,
        autoJoinChannels: [String] = []
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.nickname = nickname
        self.username = username
        self.realName = realName
        self.password = password
        self.autoJoinChannels = autoJoinChannels
    }
}
