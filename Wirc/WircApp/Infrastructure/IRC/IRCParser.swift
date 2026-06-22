import Foundation

enum IRCParser {
    /// Parse a raw IRC line into an IRCEvent.
    /// Format: `[@tags] [:prefix] COMMAND [params] [:trailing]`
    static func parse(rawLine: String, server: String) -> IRCEvent {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return .rawLine(rawLine) }

        // PING is special — no prefix
        if line.hasPrefix("PING") {
            return .rawLine(line)
        }

        // IRCv3 tags (@key=value;...)
        var tags: [String: String] = [:]
        if line.hasPrefix("@") {
            if let spaceIdx = line.firstIndex(of: " ") {
                let tagString = String(line[line.index(after: line.startIndex)..<spaceIdx])
                for tag in tagString.split(separator: ";") {
                    let parts = tag.split(separator: "=", maxSplits: 1)
                    let key = String(parts[0])
                    let value = parts.count > 1 ? String(parts[1]) : ""
                    tags[key] = value
                }
                line = String(line[line.index(after: spaceIdx)...])
            }
        }

        var prefix: String?
        if line.hasPrefix(":") {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            prefix = String(parts[0].dropFirst())
            if parts.count > 1 {
                line = String(parts[1])
            } else {
                line = ""
            }
        }

        let command: String
        var paramsPart: String
        if let spaceIdx = line.firstIndex(of: " ") {
            command = String(line[..<spaceIdx]).uppercased()
            paramsPart = String(line[line.index(after: spaceIdx)...])
        } else {
            command = line.uppercased()
            paramsPart = ""
        }

        // Extract trailing parameter (after " :")
        var params: [String] = []
        var trailing: String?
        if let trailingRange = paramsPart.range(of: " :") {
            let beforeTrailing = String(paramsPart[..<trailingRange.lowerBound])
            params = beforeTrailing.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            let trailingStart = paramsPart.index(trailingRange.lowerBound, offsetBy: 2)
            if trailingStart < paramsPart.endIndex {
                trailing = String(paramsPart[trailingStart...])
            } else {
                trailing = ""
            }
        } else {
            params = paramsPart.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        }

        let senderNick = extractNick(from: prefix)
        let senderHostmask = extractHostmask(from: prefix)

        switch command {
        case "PRIVMSG":
            let target = params.first ?? ""
            let isChannel = target.hasPrefix("#") || target.hasPrefix("&") || target.hasPrefix("+") || target.hasPrefix("!")

            // CTCP check
            if let text = trailing, text.hasPrefix("\u{01}"), text.hasSuffix("\u{01}") {
                let inner = String(text.dropFirst().dropLast())
                let ctcpParts = inner.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                let ctcpCmd = String(ctcpParts[0])
                let ctcpArg: String? = ctcpParts.count > 1 ? String(ctcpParts[1]) : nil
                return .ctcpQuery(nick: senderNick ?? "unknown", command: ctcpCmd, argument: ctcpArg)
            }

            let msg = IRCMessage(
                server: server,
                channel: isChannel ? target : nil,
                senderNick: senderNick ?? "unknown",
                senderHostmask: senderHostmask,
                text: trailing ?? "",
                receivedAt: Date(),
                raw: rawLine,
                tags: tags
            )
            return .message(msg)

        case "NOTICE":
            let msg = IRCMessage(
                server: server,
                channel: nil,
                senderNick: senderNick ?? "server",
                senderHostmask: senderHostmask,
                text: trailing ?? "",
                receivedAt: Date(),
                raw: rawLine,
                tags: tags
            )
            return .notice(msg)

        case "JOIN":
            let channel = trailing ?? params.first ?? ""
            return .join(channel: channel, nick: senderNick ?? "unknown")

        case "PART":
            let channel = params.first ?? ""
            return .part(channel: channel, nick: senderNick ?? "unknown", reason: trailing)

        case "QUIT":
            return .quit(nick: senderNick ?? "unknown", reason: trailing)

        case "NICK":
            return .nickChange(oldNick: senderNick ?? "unknown", newNick: trailing ?? params.first ?? "unknown")

        case "KICK":
            let channel = params.first ?? ""
            let kickedNick = params.count >= 2 ? params[1] : (trailing ?? "unknown")
            return .kick(channel: channel, nick: kickedNick, by: senderNick ?? "unknown", reason: trailing)

        case "TOPIC":
            let channel = params.first ?? ""
            return .topic(channel: channel, topic: trailing ?? "")

        case "MODE":
            if let channel = params.first, channel.hasPrefix("#") {
                let modeStr = params.dropFirst().joined(separator: " ") + (trailing.map { " \($0)" } ?? "")
                return .channelMode(channel: channel, mode: modeStr)
            }
            return .rawLine(rawLine)

        case "353": // RPL_NAMREPLY
            // params: myNick = #channel :names
            let channel = params.count >= 2 ? params[params.count - 1] : (params.count >= 1 ? params[0] : "")
            if let namesStr = trailing {
                let names = namesStr.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                return .names(channel: channel, names: names)
            }
            return .rawLine(rawLine)

        case "366": // RPL_ENDOFNAMES
            let channel = params.count >= 1 ? params[params.count - 1] : ""
            return .endOfNames(channel: channel)

        case "332": // RPL_TOPIC
            let channel = params.count >= 2 ? params[1] : ""
            return .topic(channel: channel, topic: trailing ?? "")

        case "333": // RPL_TOPICWHOTIME
            // params: myNick #channel setBy setAt
            if params.count >= 3 {
                let channel = params[1]
                let setBy = params[2]
                let ts = Int(params.count >= 4 ? params[3] : "0") ?? 0
                let setAt = Date(timeIntervalSince1970: TimeInterval(ts))
                return .topicWho(channel: channel, setBy: setBy, setAt: setAt)
            }
            return .rawLine(rawLine)

        case "375": // RPL_MOTDSTART
            return .motdLine(trailing ?? "")
        case "372": // RPL_MOTD
            return .motdLine(trailing ?? "")
        case "376", "422": // RPL_ENDOFMOTD
            return .motdEnd

        case "321": // RPL_LISTSTART
            return .listStart
        case "322": // RPL_LIST
            let channel = params.count >= 2 ? params[1] : (params.first ?? "")
            let users = Int(params.count >= 3 ? params[2] : "0") ?? 0
            return .listItem(channel: channel, users: users, topic: trailing ?? "")
        case "323": // RPL_LISTEND
            return .listEnd
        case "433": // ERR_NICKNAMEINUSE
            let badNick = params.count >= 1 ? params[0] : (trailing ?? "unknown")
            return .nickInUse(badNick)

        case "ERROR":
            return .error(trailing ?? rawLine)

        case "PONG", "001", "002", "003", "004", "005", "251", "252", "253", "254",
             "255", "265", "266", "250", "375", "396":
            return .rawLine(rawLine)

        default:
            return .rawLine(rawLine)
        }
    }

    // MARK: - Helpers

    private static func extractNick(from prefix: String?) -> String? {
        guard let pfx = prefix else { return nil }
        if let exclamationIdx = pfx.firstIndex(of: "!") {
            return String(pfx[..<exclamationIdx])
        }
        // Could be servername
        if pfx.contains(".") { return nil }
        return pfx
    }

    private static func extractHostmask(from prefix: String?) -> String? {
        guard let pfx = prefix else { return nil }
        if let exclamationIdx = pfx.firstIndex(of: "!") {
            return String(pfx[pfx.index(after: exclamationIdx)...])
        }
        return nil
    }
}
