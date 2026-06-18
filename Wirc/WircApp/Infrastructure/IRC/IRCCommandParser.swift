import Foundation

/// Parsed IRC slash command or plain message.
enum IRCCommand: Equatable {
    case message(String)                          // plain PRIVMSG
    case join(String)                             // /join #channel
    case part(String, String?)                    // /part [#channel] [reason]
    case msg(String, String)                      // /msg nick message
    case query(String)                            // /query nick
    case nick(String)                              // /nick newNick
    case quit(String?)                             // /quit [reason]
    case me(String)                                // /me action text
    case topic(String?)                            // /topic [new topic]
    case whois(String)                             // /whois nick
    case who(String?)                              // /who [mask]
    case names(String?)                            // /names [channel]
    case list(String?)                             // /list [filter]
    case kick(String, String?)                     // /kick nick [reason]
    case mode(String)                              // /mode [target] [+flags]
    case invite(String, String)                    // /invite nick #channel
    case away(String?)                             // /away [message]
    case notice(String, String)                    // /notice nick message
    case ctcp(String, String, String?)             // /ctcp nick command [args]
    case ping(String?)                             // /ping [nick]
    case motd                                      // /motd
    case raw(String)                               // /raw irc line (admin)
    case reconnect                                 // /reconnect
    case disconnect                                // /disconnect
    case alias(String, String?)                    // /alias name [expansion]
    case unalias(String)                           // /unalias name
}

/// Parses slash commands from user input.
/// Lines starting with / are commands; everything else is a plain message.
enum IRCCommandParser {

    static func parse(_ input: String) -> IRCCommand {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else {
            return .message(input)
        }

        let withoutSlash = String(trimmed.dropFirst())
        guard let firstSpace = withoutSlash.firstIndex(of: " ") else {
            // Single-word command: /quit, /motd, /list, /disconnect, /reconnect
            let cmd = withoutSlash.lowercased()
            return parseSimple(cmd)
        }

        let command = String(withoutSlash[..<firstSpace]).lowercased()
        let args = String(withoutSlash[withoutSlash.index(after: firstSpace)...]).trimmingCharacters(in: .whitespaces)

        return parseCommand(command, args: args)
    }

    private static func parseSimple(_ cmd: String) -> IRCCommand {
        switch cmd {
        case "quit": return .quit(nil)
        case "motd": return .motd
        case "list": return .list(nil)
        case "names": return .names(nil)
        case "who": return .who(nil)
        case "disconnect": return .disconnect
        case "reconnect": return .reconnect
        default: return .message("/\(cmd)")  // unknown command → send as text
        }
    }

    private static func parseCommand(_ cmd: String, args: String) -> IRCCommand {
        switch cmd {
        case "join", "j":
            return .join(args)

        case "part", "leave":
            let parts = splitFirst(args)
            return .part(parts.first ?? args, parts.rest)

        case "msg", "m":
            let parts = splitFirst(args)
            guard let nick = parts.first, let msg = parts.rest else {
                return .message("/msg \(args)")  // incomplete
            }
            return .msg(nick, msg)

        case "query", "q":
            return .query(args)

        case "nick", "n":
            return .nick(args)

        case "quit", "exit":
            return .quit(args.isEmpty ? nil : args)

        case "me", "action":
            return .me(args)

        case "topic", "t":
            return .topic(args.isEmpty ? nil : args)

        case "whois", "wi":
            return .whois(args)

        case "who":
            return .who(args.isEmpty ? nil : args)

        case "names":
            return .names(args.isEmpty ? nil : args)

        case "list":
            return .list(args.isEmpty ? nil : args)

        case "kick", "k":
            let parts = splitFirst(args)
            return .kick(parts.first ?? args, parts.rest)

        case "mode":
            return .mode(args)

        case "invite":
            let parts = splitFirst(args)
            guard let nick = parts.first, let channel = parts.rest else {
                return .message("/invite \(args)")
            }
            return .invite(nick, channel)

        case "away":
            return .away(args.isEmpty ? nil : args)

        case "notice":
            let parts = splitFirst(args)
            guard let nick = parts.first, let msg = parts.rest else {
                return .message("/notice \(args)")
            }
            return .notice(nick, msg)

        case "ctcp":
            let parts = splitArgs(args, count: 3)
            guard parts.count >= 2 else { return .message("/ctcp \(args)") }
            return .ctcp(parts[0], parts[1], parts.count > 2 ? parts[2] : nil)

        case "ping":
            return .ping(args.isEmpty ? nil : args)

        case "raw":
            return .raw(args)

        case "disconnect":
            return .disconnect

        case "reconnect":
            return .reconnect

        case "alias":
            let parts = splitFirst(args)
            return .alias(parts.first ?? args, parts.rest)

        case "unalias":
            return .unalias(args)

        case "motd":
            return .motd

        default:
            return .message("/\(cmd) \(args)")  // unknown → send as text
        }
    }

    /// Split into (first word, rest of string).
    private static func splitFirst(_ s: String) -> (first: String?, rest: String?) {
        guard let space = s.firstIndex(of: " ") else {
            return (s.isEmpty ? nil : s, nil)
        }
        let first = String(s[..<space])
        let rest = String(s[s.index(after: space)...]).trimmingCharacters(in: .whitespaces)
        return (first, rest.isEmpty ? nil : rest)
    }

    /// Split into N parts (whitespace-separated), preserving remaining text in last element.
    private static func splitArgs(_ s: String, count: Int) -> [String] {
        var parts: [String] = []
        var remaining = s
        for _ in 0..<(count - 1) {
            let sp = splitFirst(remaining)
            if let f = sp.first {
                parts.append(f)
                remaining = sp.rest ?? ""
            } else {
                break
            }
        }
        if !remaining.isEmpty { parts.append(remaining) }
        return parts
    }
}
