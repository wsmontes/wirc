import SwiftUI
import UIKit

struct MessageView: View {
    @Environment(AppState.self) private var appState
    let serverId: UUID
    let serverHost: String
    let conversation: AppState.Conversation

    @State private var messageText = ""
    @State private var showUserList = false

    private var channel: String { conversation.name }
    private var userKey: String { "\(serverHost)|\(channel.lowercased())" }
    private var users: [AppState.ChannelUser] { appState.channelUsers[userKey] ?? [] }
    private var topic: AppState.ChannelTopic? { appState.channelTopics[userKey] }

    private var messages: [WOMObject] {
        appState.messagesFor(server: serverHost, channel: channel)
    }

    private var timeline: [TimelineItem] {
        var items: [TimelineItem] = []

        for msg in messages {
            items.append(.message(msg))
        }

        let sysEvents = appState.womObjects.filter { obj in
            guard obj.type.contains("wom:SystemEvent") else { return false }
            guard obj.data["server"] == serverHost else { return false }
            let c = obj.data["channel"] ?? ""
            return c == channel || c.isEmpty
        }.sorted { $0.createdAt < $1.createdAt }

        for evt in sysEvents {
            let eventType = evt.data["eventType"] ?? evt.data["event"] ?? "unknown"
            if eventType == "names" || eventType == "endOfNames" { continue }
            items.append(.system(evt))
        }

        items.sort { lhs, rhs in
            lhs.timestamp < rhs.timestamp
        }
        return items
    }

    enum TimelineItem: Identifiable {
        case message(WOMObject)
        case system(WOMObject)
        var id: String {
            switch self {
            case .message(let o): return o.id
            case .system(let o): return o.id
            }
        }
        var timestamp: Date {
            switch self {
            case .message(let o): return o.createdAt
            case .system(let o): return o.createdAt
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Topic bar
            if let topic, !topic.text.isEmpty {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 4) {
                        Text("Topic:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(topic.text)
                            .font(.caption)
                            .lineLimit(3)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    Divider()
                }
                .background(Color(.systemGray6))
            }

            // Chat area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(timeline) { item in
                            switch item {
                            case .message(let object):
                                MessageBubble(object: object)
                            case .system(let object):
                                SystemEventPill(object: object)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = timeline.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onAppear {
                    if let last = timeline.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            // Input bar
            HStack(spacing: 8) {
                TextField("Message \(channel)", text: $messageText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit { send() }

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .navigationTitle(channel)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    // User count badge
                    if !users.isEmpty {
                        Button { showUserList = true } label: {
                            Text("\(users.count)")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(.systemGray5))
                                .clipShape(Capsule())
                        }
                    }

                    Menu {
                        Button { showUserList = true } label: {
                            Label("User List (\(users.count))", systemImage: "person.2")
                        }
                        if let topic, !topic.text.isEmpty {
                            Button {
                                UIPasteboard.general.string = topic.text
                            } label: {
                                Label("Copy Topic", systemImage: "doc.on.doc")
                            }
                        }
                        Divider()
                        Button(role: .destructive) {
                            appState.partChannel(channel, serverId: serverId)
                        } label: {
                            Label("Leave Channel", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showUserList) {
            UserListView(users: users, channel: channel)
        }
    }

    private func send() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messageText = ""
        appState.sendMessage(text, channel: channel, serverId: serverId)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let object: WOMObject

    private var isFromLocalUser: Bool { object.provenance?.isLocalUser ?? false }
    private var senderName: String { object.attributedTo?.name ?? object.data["nick"] ?? "unknown" }
    private var text: String { object.content?.text ?? "" }
    private var network: String { object.data["network"] ?? "irc" }
    private var sourceColor: Color { DesignSystem.Colors.forSource(network) }

    var body: some View {
        HStack(alignment: .top) {
            if isFromLocalUser { Spacer(minLength: 50) }

            VStack(alignment: isFromLocalUser ? .trailing : .leading, spacing: 2) {
                if !isFromLocalUser {
                    Text(senderName)
                        .font(DesignSystem.Fonts.senderName)
                        .foregroundStyle(sourceColor)
                }
                Text(text)
                    .font(DesignSystem.Fonts.messageBody)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isFromLocalUser ? sourceColor : DesignSystem.Colors.border.opacity(0.3))
                    .foregroundStyle(isFromLocalUser ? .white : DesignSystem.Colors.ink)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.bubble))
            }
            .contextMenu {
                Button { UIPasteboard.general.string = text } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                if !isFromLocalUser {
                    Button {
                        UIPasteboard.general.string = "/msg \(senderName) "
                    } label: {
                        Label("Reply to \(senderName)", systemImage: "arrowshape.turn.up.left")
                    }
                }
            }

            if !isFromLocalUser { Spacer(minLength: 50) }
        }
    }
}

// MARK: - System Event Pill

struct SystemEventPill: View {
    let object: WOMObject

    private var text: String {
        let eventType = object.data["eventType"] ?? object.data["event"] ?? ""
        let nick = object.data["nick"] ?? ""
        let channel = object.data["channel"] ?? ""

        switch eventType {
        case "join":
            return "→ \(nick) joined \(channel)"
        case "part":
            let reason = object.data["reason"]
            return "← \(nick) left\(reason.map { " (\($0))" } ?? "")"
        case "quit":
            let reason = object.data["reason"]
            return "← \(nick) quit\(reason.map { " (\($0))" } ?? "")"
        case "kick":
            let by = object.data["by"] ?? ""
            let reason = object.data["reason"]
            return "✕ \(nick) kicked by \(by)\(reason.map { " (\($0))" } ?? "")"
        case "nick":
            let oldNick = object.data["oldNick"] ?? ""
            let newNick = object.data["newNick"] ?? ""
            return "~ \(oldNick) → \(newNick)"
        case "topic":
            let topic = object.data["topic"] ?? ""
            return "# \(nick) set topic: \(topic)"
        case "mode":
            let mode = object.data["mode"] ?? ""
            return "* Mode \(mode)"
        default:
            let text = object.data["text"] ?? ""
            return text.isEmpty ? "· \(eventType)" : text
        }
    }

    var body: some View {
        Text(text)
            .font(DesignSystem.Fonts.systemEvent)
            .foregroundStyle(DesignSystem.Colors.pencil)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .background(DesignSystem.Colors.border.opacity(0.5))
            .clipShape(Capsule())
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 2)
    }
}

// MARK: - User List View

struct UserListView: View {
    let users: [AppState.ChannelUser]
    let channel: String
    @Environment(\.dismiss) private var dismiss

    private var sortedUsers: [AppState.ChannelUser] {
        users.sorted { u1, u2 in
            let rank: [Character: Int] = ["~": 0, "&": 1, "@": 2, "%": 3, "+": 4]
            let r1 = (u1.prefix.first.flatMap { rank[$0] }) ?? 99
            let r2 = (u2.prefix.first.flatMap { rank[$0] }) ?? 99
            if r1 != r2 { return r1 < r2 }
            return u1.nick.lowercased() < u2.nick.lowercased()
        }
    }

    var body: some View {
        NavigationStack {
            List(sortedUsers) { user in
                HStack(spacing: 8) {
                    if !user.prefix.isEmpty {
                        Text(user.prefix)
                            .font(.caption)
                            .foregroundStyle(prefixColor(user.prefix))
                            .frame(width: 14)
                    } else {
                        Spacer().frame(width: 14)
                    }
                    Text(user.nick)
                        .font(.body)
                }
            }
            .navigationTitle("\(channel) — \(users.count) users")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func prefixColor(_ p: String) -> Color {
        switch p {
        case "~": return .purple   // founder
        case "&": return .red      // admin
        case "@": return .green    // op
        case "%": return .blue     // half-op
        case "+": return .orange   // voice
        default: return .secondary
        }
    }
}
