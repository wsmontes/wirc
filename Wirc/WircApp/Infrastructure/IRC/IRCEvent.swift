import Foundation

enum IRCEvent {
    case connected
    case disconnected(reason: String?)
    case rawLine(String)
    case message(IRCMessage)
    case notice(IRCMessage)
    case join(channel: String, nick: String)
    case part(channel: String, nick: String, reason: String?)
    case quit(nick: String, reason: String?)
    case nickChange(oldNick: String, newNick: String)
    case kick(channel: String, nick: String, by: String, reason: String?)
    case topic(channel: String, topic: String)
    case topicWho(channel: String, setBy: String, setAt: Date)
    case names(channel: String, names: [String])
    case endOfNames(channel: String)
    case motdLine(String)
    case motdEnd
    case nickInUse(String)
    case channelMode(channel: String, mode: String)
    case error(String)
    case ctcpQuery(nick: String, command: String, argument: String?)
    case listStart
    case listItem(channel: String, users: Int, topic: String)
    case listEnd
}
