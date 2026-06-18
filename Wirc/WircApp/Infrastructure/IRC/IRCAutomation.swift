import Foundation
import os.log

/// IRC automations: auto-identify, auto-join, flood protection, reconnect, aliases, keywords.
@Observable
@MainActor
final class IRCAutomation {

    // MARK: - State

    /// Server → channels that were joined before disconnect (for reconnect restoration)
    private var joinedChannels: [UUID: Set<String>] = [:]

    /// Per-server reconnect attempt counter (for exponential backoff)
    private var reconnectAttempts: [UUID: Int] = [:]

    /// Per-server flood control: timestamps of recent messages
    private var messageTimestamps: [UUID: [Date]] = [:]

    /// Custom command aliases: name → expansion
    var aliases: [String: String] = [:]

    /// Notification keywords (matched case-insensitively in messages)
    var notifyKeywords: [String] = []

    /// Max messages per second before flood protection kicks in
    var floodLimitPerSecond = 4

    /// Whether auto-reconnect is enabled (default true)
    var autoReconnect = true

    /// NickServ password per server host
    var nickservPasswords: [String: String] = [:]

    // MARK: - Auto-identification

    /// Send NickServ IDENTIFY after connecting, if password is configured.
    func autoIdentify(serverHost: String, client: IRCClient) {
        guard let pass = nickservPasswords[serverHost], !pass.isEmpty else { return }
        client.sendMessage("IDENTIFY \(pass)", to: "NickServ")
        os_log(.info, "IRCAutomation: sent NickServ IDENTIFY for %{public}@", serverHost)
    }

    // MARK: - Auto-join & Channel Restoration

    /// Record currently joined channels for a server (called after NAMES reply).
    func recordJoinedChannels(serverId: UUID, channels: [String]) {
        joinedChannels[serverId] = Set(channels)
    }

    /// Rejoin all previously-joined channels after reconnect.
    func restoreChannels(serverId: UUID, client: IRCClient, config: IRCConnectionConfig) {
        // First, join autoJoinChannels from config
        for ch in config.autoJoinChannels {
            client.join(channel: ch)
        }
        // Then, restore channels from before the disconnect
        if let previous = joinedChannels[serverId] {
            for ch in previous {
                client.join(channel: ch)
            }
        }
        reconnectAttempts[serverId] = 0
    }

    /// Called when a disconnect happens — don't clear channels so we can restore.
    func onDisconnect(serverId: UUID) {
        // Keep joinedChannels intact for restoration
        reconnectAttempts[serverId] = (reconnectAttempts[serverId] ?? 0) + 1
    }

    /// Called on manual disconnect — clear state.
    func onManualDisconnect(serverId: UUID) {
        joinedChannels.removeValue(forKey: serverId)
        reconnectAttempts.removeValue(forKey: serverId)
    }

    /// Get reconnect delay with exponential backoff (3s, 6s, 12s, 24s... max 60s).
    func reconnectDelay(for serverId: UUID) -> TimeInterval {
        let attempts = reconnectAttempts[serverId] ?? 1
        let delay = min(3.0 * pow(2.0, Double(attempts - 1)), 60.0)
        return delay
    }

    // MARK: - Flood Protection

    /// Check if sending a message would exceed rate limits.
    /// Returns true if the message is allowed.
    func checkFlood(serverId: UUID) -> Bool {
        let now = Date()
        var stamps = messageTimestamps[serverId] ?? []
        // Remove timestamps older than 1 second
        stamps = stamps.filter { now.timeIntervalSince($0) < 1.0 }
        defer { messageTimestamps[serverId] = stamps }

        if stamps.count >= floodLimitPerSecond {
            os_log(.info, "IRCAutomation: flood protection triggered for server %{public}@", serverId.uuidString)
            return false
        }
        stamps.append(now)
        return true
    }

    // MARK: - Keyword Notifications

    /// Check if a message text contains any notification keywords or the user's nick.
    /// Returns the matching keyword, or nil.
    func checkKeywords(_ text: String, nick: String) -> String? {
        let lower = text.lowercased()
        // Always check for nick mention
        if lower.contains(nick.lowercased()) {
            return nick
        }
        // Check custom keywords
        for kw in notifyKeywords {
            if lower.contains(kw.lowercased()) {
                return kw
            }
        }
        return nil
    }

    // MARK: - Aliases

    /// Expand a slash command through aliases. Returns the expanded command or nil if no alias matches.
    func expandAlias(_ input: String) -> String? {
        guard input.hasPrefix("/") else { return nil }
        let trimmed = String(input.dropFirst())
        let cmd = trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? trimmed
        guard let expansion = aliases[cmd.lowercased()] else { return nil }

        // Replace $1, $2... with arguments
        let args = trimmed.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
        var result = expansion
        let argParts = args.split(separator: " ").map(String.init)
        for (i, arg) in argParts.enumerated() {
            result = result.replacingOccurrences(of: "$\(i+1)", with: arg)
        }
        result = result.replacingOccurrences(of: "$*", with: args)
        // If the alias expansion is itself a command (starts with /), return it directly
        // Otherwise prepend / to make it a message
        if result.hasPrefix("/") {
            return result
        }
        return "/msg \(result)"
    }

    /// Set an alias: /alias name /expansion with $1 $2...
    func setAlias(_ input: String) -> String? {
        let parts = input.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return "Usage: /alias name /command $1 $2" }
        let name = String(parts[0]).lowercased()
        let expansion = parts.count >= 2 ? String(parts[1]) : ""
        aliases[name] = expansion
        return "Alias /\(name) → \(expansion)"
    }
}
