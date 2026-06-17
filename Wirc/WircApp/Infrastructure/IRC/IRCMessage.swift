import Foundation

struct IRCMessage: Codable, Equatable {
    var server: String
    var channel: String?
    var senderNick: String
    var senderHostmask: String?
    var text: String
    var receivedAt: Date
    var raw: String?
}
