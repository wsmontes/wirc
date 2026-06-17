import Foundation

enum WOMToIRCAdapter {
    /// Convert a WOM message intent into an IRC PRIVMSG command.
    /// Returns nil if the object is not a sendable message.
    static func convertToIRC(_ object: WOMObject) -> String? {
        guard object.type.contains("wom:Message") else { return nil }
        guard let content = object.content, let text = content.text, !text.isEmpty else { return nil }

        let channel = object.data["channel"] ?? ""
        let recipient = object.data["recipient"] ?? ""

        let target: String
        if !channel.isEmpty {
            target = channel
        } else if !recipient.isEmpty {
            target = recipient
        } else {
            return nil
        }

        return "PRIVMSG \(target) :\(text)"
    }
}
