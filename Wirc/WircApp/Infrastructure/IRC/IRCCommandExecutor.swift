import Foundation

/// Executes parsed IRC commands against AppState + IRCClient.
/// Handles UI-side effects (DM views, nick changes) and delegates IRC protocol to clients.
@MainActor
enum IRCCommandExecutor {

    /// Execute a parsed command in the context of a specific server.
    /// Returns a feedback string for display in the chat (nil = no feedback needed).
    static func execute(
        _ command: IRCCommand,
        serverId: UUID,
        appState: AppState
    ) -> String? {
        guard let client = appState.client(for: serverId),
              let config = appState.serverConfig(for: serverId) else {
            return "⚠️ Not connected to server"
        }

        switch command {
        case .message(let text):
            // Handled by caller directly — this path shouldn't be reached
            return nil

        case .join(let channel):
            let ch = channel.hasPrefix("#") ? channel : "#\(channel)"
            client.join(channel: ch)
            return nil

        case .part(let channel, let reason):
            let ch = channel ?? (appState.channelManager.activeChannel?.name ?? "")
            if !ch.isEmpty {
                client.part(channel: ch.hasPrefix("#") ? ch : "#\(ch)", reason: reason)
            }
            return nil

        case .msg(let nick, let text):
            client.sendMessage(text, to: nick)
            // Also save to local store as WOM object
            appState.saveSentDM(text: text, to: nick, server: config.host, serverId: serverId)
            return nil

        case .query(let nick):
            // Open DM view for this nick
            return "dm:\(nick)"

        case .nick(let newNick):
            client.sendRaw("NICK \(newNick)")
            // Update local config
            if let idx = appState.servers.firstIndex(where: { $0.id == serverId }) {
                var updated = appState.servers[idx]
                updated.nickname = newNick
                appState.servers[idx] = updated
            }
            return "→ Nickname changed to \(newNick)"

        case .quit(let reason):
            let msg = reason ?? "Wirc"
            client.sendRaw("QUIT :\(msg)")
            client.disconnect()
            return nil

        case .me(let action):
            let ircMsg = "\u{01}ACTION \(action)\u{01}"
            client.sendMessage(ircMsg, to: "")  // Send to active channel
            return nil

        case .topic(let newTopic):
            if let topic = newTopic {
                client.setTopic(channel: "", topic: topic)  // active channel
            } else {
                client.sendRaw("TOPIC")  // query topic
            }
            return nil

        case .whois(let nick):
            client.sendRaw("WHOIS \(nick)")
            return "Looking up \(nick)..."

        case .who(let mask):
            if let m = mask { client.sendRaw("WHO \(m)") }
            else { client.sendRaw("WHO") }
            return nil

        case .names(let channel):
            if let ch = channel { client.sendRaw("NAMES \(ch)") }
            else { client.sendRaw("NAMES") }
            return nil

        case .list(let filter):
            if let f = filter { client.sendRaw("LIST \(f)") }
            else { client.listChannels() }
            return nil

        case .kick(let nick, let reason):
            // Find active channel
            let channel = appState.channelManager.activeChannel?.name ?? ""
            if !channel.isEmpty {
                if let r = reason {
                    client.sendRaw("KICK \(channel) \(nick) :\(r)")
                } else {
                    client.sendRaw("KICK \(channel) \(nick)")
                }
            }
            return nil

        case .mode(let args):
            client.sendRaw("MODE \(args)")
            return nil

        case .invite(let nick, let channel):
            client.sendRaw("INVITE \(nick) \(channel)")
            return "Invited \(nick) to \(channel)"

        case .away(let message):
            if let msg = message {
                client.sendRaw("AWAY :\(msg)")
                return "→ Away: \(msg)"
            } else {
                client.sendRaw("AWAY")
                return "→ Back"
            }

        case .notice(let nick, let text):
            client.sendRaw("NOTICE \(nick) :\(text)")
            return nil

        case .ctcp(let nick, let command, let args):
            let payload = args.map { "\(command) \($0)" } ?? command
            client.sendRaw("PRIVMSG \(nick) :\u{01}\(payload)\u{01}")
            return nil

        case .ping(let nick):
            if let n = nick {
                client.sendRaw("PRIVMSG \(n) :\u{01}PING \(Int(Date().timeIntervalSince1970 * 1000))\u{01}")
            }
            return nil

        case .motd:
            client.sendRaw("MOTD")
            return nil

        case .raw(let line):
            client.sendRaw(line)
            return nil

        case .reconnect:
            client.disconnect()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                appState.connect(to: serverId)
            }
            return "Reconnecting..."

        case .disconnect:
            client.disconnect()
            return "Disconnected"
        }
    }
}
