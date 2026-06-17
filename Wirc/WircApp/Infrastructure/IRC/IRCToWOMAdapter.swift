import Foundation

final class IRCToWOMAdapter {

    func convert(_ event: IRCEvent, config: IRCConnectionConfig) -> [WOMObject] {
        switch event {
        case .message(let ircMsg):
            return [convertMessage(ircMsg, config: config)]

        case .notice(let ircMsg):
            return [convertNotice(ircMsg, config: config)]

        case .join(let channel, let nick):
            return [convertJoin(channel: channel, nick: nick, config: config)]

        case .part(let channel, let nick, let reason):
            return [convertPart(channel: channel, nick: nick, reason: reason, config: config)]

        case .quit(let nick, let reason):
            return [convertQuit(nick: nick, reason: reason, config: config)]

        case .nickChange(let oldNick, let newNick):
            return [convertNickChange(oldNick: oldNick, newNick: newNick, config: config)]

        case .kick(let channel, let nick, let by, let reason):
            return [convertKick(channel: channel, nick: nick, by: by, reason: reason, config: config)]

        case .topic(let channel, let topic):
            return [convertTopicChange(channel: channel, topic: topic, config: config)]

        case .topicWho(let channel, let setBy, let setAt):
            return [convertTopicWho(channel: channel, setBy: setBy, setAt: setAt, config: config)]

        case .names(let channel, let names):
            return [convertNames(channel: channel, names: names, config: config)]

        case .endOfNames(let channel):
            return [convertEndOfNames(channel: channel, config: config)]

        case .channelMode(let channel, let mode):
            return [convertChannelMode(channel: channel, mode: mode, config: config)]

        case .motdLine: fallthrough
        case .motdEnd: fallthrough
        case .nickInUse:
            return []

        case .connected, .disconnected, .rawLine, .error, .ctcpQuery,
             .listStart, .listItem, .listEnd:
            return []
        }
    }

    // MARK: - Message

    private func convertMessage(_ ircMsg: IRCMessage, config: IRCConnectionConfig) -> WOMObject {
        let isChannel = ircMsg.channel != nil
        let objectId = WOMIDGenerator.generate(type: "message")

        var data: [String: String] = [
            "network": "irc",
            "server": config.host,
            "nick": ircMsg.senderNick
        ]
        if let channel = ircMsg.channel { data["channel"] = channel }
        data["visibility"] = isChannel ? "channel" : "direct"
        if let raw = ircMsg.raw { data["raw"] = raw }

        return WOMObject(
            id: objectId,
            type: ["wom:Message"],
            createdAt: ircMsg.receivedAt,
            attributedTo: WOMReference(
                id: "irc://\(config.host)/\(ircMsg.senderNick)",
                type: ["wom:RemoteIdentity"],
                name: ircMsg.senderNick
            ),
            content: WOMContent(format: "text/plain", text: ircMsg.text),
            data: data,
            provenance: WOMProvenance(
                origin: "remotePeer",
                source: WOMReference(
                    id: isChannel ? "irc://\(config.host)/\(ircMsg.channel ?? "")" : "irc://\(config.host)",
                    type: isChannel ? ["irc:Channel"] : ["irc:Server"]
                ),
                createdAt: ircMsg.receivedAt,
                confidence: 1.0,
                reviewStatus: "none"
            )
        )
    }

    // MARK: - System Events

    private func convertNotice(_ ircMsg: IRCMessage, config: IRCConnectionConfig) -> WOMObject {
        return systemEvent(type: "notice", config: config, extra: [
            "nick": ircMsg.senderNick,
            "text": ircMsg.text
        ])
    }

    private func convertJoin(channel: String, nick: String, config: IRCConnectionConfig) -> WOMObject {
        return systemEvent(type: "join", config: config, extra: [
            "channel": channel, "nick": nick
        ])
    }

    private func convertPart(channel: String, nick: String, reason: String?, config: IRCConnectionConfig) -> WOMObject {
        var extra: [String: String] = ["channel": channel, "nick": nick, "event": "part"]
        if let r = reason { extra["reason"] = r }
        return systemEvent(type: "part", config: config, extra: extra)
    }

    private func convertQuit(nick: String, reason: String?, config: IRCConnectionConfig) -> WOMObject {
        var extra: [String: String] = ["nick": nick, "event": "quit"]
        if let r = reason { extra["reason"] = r }
        return systemEvent(type: "quit", config: config, extra: extra)
    }

    private func convertNickChange(oldNick: String, newNick: String, config: IRCConnectionConfig) -> WOMObject {
        return systemEvent(type: "nick", config: config, extra: [
            "oldNick": oldNick, "newNick": newNick, "event": "nick"
        ])
    }

    private func convertKick(channel: String, nick: String, by: String, reason: String?, config: IRCConnectionConfig) -> WOMObject {
        var extra: [String: String] = ["channel": channel, "nick": nick, "by": by, "event": "kick"]
        if let r = reason { extra["reason"] = r }
        return systemEvent(type: "kick", config: config, extra: extra)
    }

    private func convertTopicChange(channel: String, topic: String, config: IRCConnectionConfig) -> WOMObject {
        return systemEvent(type: "topic", config: config, extra: [
            "channel": channel, "topic": topic, "event": "topic"
        ])
    }

    private func convertTopicWho(channel: String, setBy: String, setAt: Date, config: IRCConnectionConfig) -> WOMObject {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return systemEvent(type: "topicWho", config: config, extra: [
            "channel": channel, "setBy": setBy, "setAt": df.string(from: setAt), "event": "topicWho"
        ])
    }

    private func convertNames(channel: String, names: [String], config: IRCConnectionConfig) -> WOMObject {
        return systemEvent(type: "names", config: config, extra: [
            "channel": channel, "names": names.joined(separator: "\t"), "event": "names"
        ])
    }

    private func convertEndOfNames(channel: String, config: IRCConnectionConfig) -> WOMObject {
        return systemEvent(type: "endOfNames", config: config, extra: [
            "channel": channel, "event": "endOfNames"
        ])
    }

    private func convertChannelMode(channel: String, mode: String, config: IRCConnectionConfig) -> WOMObject {
        return systemEvent(type: "mode", config: config, extra: [
            "channel": channel, "mode": mode, "event": "mode"
        ])
    }

    // MARK: - Helpers

    private func systemEvent(type: String, config: IRCConnectionConfig, extra: [String: String]) -> WOMObject {
        var data: [String: String] = [
            "network": "irc",
            "server": config.host,
            "eventType": type
        ]
        for (k, v) in extra { data[k] = v }
        return WOMObject(
            id: WOMIDGenerator.generate(type: "event"),
            type: ["wom:TransportEnvelope", "wom:SystemEvent"],
            createdAt: Date(),
            data: data,
            provenance: WOMProvenance(origin: "remotePeer", confidence: 1.0)
        )
    }
}
