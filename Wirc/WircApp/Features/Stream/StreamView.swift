import SwiftUI

struct StreamView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedFilter: StreamFilter = .all
    @State private var showingChannelPicker = false

    enum StreamFilter: String, CaseIterable {
        case all = "All"
        case messages = "Messages"
        case posts = "Posts"
        case media = "Media"
    }

    /// All objects in reverse chronological order.
    private var timeline: [WOMObject] {
        let objects = appState.womObjects
        let filtered: [WOMObject]
        switch selectedFilter {
        case .all:
            filtered = objects
        case .messages:
            filtered = objects.filter { $0.type.contains("wom:Message") }
        case .posts:
            filtered = objects.filter { $0.type.contains("wom:Post") }
        case .media:
            filtered = objects.filter { obj in
                obj.type.contains("external.youtube.video") ||
                obj.type.contains("external.podcast.episode") ||
                !obj.attachments.isEmpty
            }
        }
        return filtered.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter chips
                filterBar
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.sm)

                // Timeline
                if timeline.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(timeline) { object in
                                if object.type.contains("wom:SystemEvent") {
                                    SystemEventPill(object: object)
                                        .padding(.vertical, 2)
                                } else if object.type.contains("wom:Message") && !object.type.contains("wom:SystemEvent") {
                                    MessageCard(object: object)
                                } else {
                                    FeedCard(post: object)
                                }
                            }
                        }
                        .padding(.vertical, DesignSystem.Spacing.lg)
                    }
                }
            }
            .background(DesignSystem.Colors.page)
            .navigationTitle("Stream")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingChannelPicker = true } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                    }
                }
            }
            .sheet(isPresented: $showingChannelPicker) {
                ChannelFilterView()
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(StreamFilter.allCases, id: \.self) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedFilter = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(DesignSystem.Fonts.chipLabel)
                            .foregroundStyle(selectedFilter == filter ? .white : DesignSystem.Colors.ink)
                            .padding(.horizontal, DesignSystem.Spacing.md)
                            .padding(.vertical, DesignSystem.Spacing.sm)
                            .background(selectedFilter == filter ? DesignSystem.Colors.signal : DesignSystem.Colors.border)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.chip))
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "No objects yet",
            systemImage: "waveform",
            description: Text("Connect an IRC server, add a feed, or link a Mastodon account in Workshop to start your stream.")
        )
    }
}

// MARK: - Message Card (IRC message in Stream context)

struct MessageCard: View {
    let object: WOMObject
    @State private var showInspector = false

    private var network: String { object.data["network"] ?? "irc" }
    private var sourceColor: Color { DesignSystem.Colors.forSource(network) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Provenance badge
            Button {
                showInspector = true
            } label: {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Circle().fill(sourceColor).frame(width: 6, height: 6)
                    Text("IRC")
                        .font(DesignSystem.Fonts.provenanceLabel)
                        .foregroundStyle(DesignSystem.Colors.ink)
                    if let server = object.data["server"] {
                        Text("· \(server)")
                            .font(DesignSystem.Fonts.provenanceDetail)
                            .foregroundStyle(DesignSystem.Colors.pencil)
                    }
                    Text("·")
                        .foregroundStyle(DesignSystem.Colors.pencil)
                    Text(object.createdAt, style: .relative)
                        .font(DesignSystem.Fonts.timestamp)
                        .foregroundStyle(DesignSystem.Colors.pencil)
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
            }
            .buttonStyle(.plain)

            // Hairline
            Rectangle()
                .fill(sourceColor)
                .frame(height: 1)
                .padding(.horizontal, DesignSystem.Spacing.md)

            // Content
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    if let nick = object.attributedTo?.name ?? object.data["nick"] {
                        Text(nick)
                            .font(DesignSystem.Fonts.senderName)
                            .foregroundStyle(sourceColor)
                    }
                    if let text = object.content?.text {
                        Text(text)
                            .font(DesignSystem.Fonts.messageBody)
                            .foregroundStyle(DesignSystem.Colors.ink)
                            .lineLimit(12)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.md)
                Spacer(minLength: 40)
            }

            // Footer
            if let channel = object.data["channel"] {
                HStack {
                    Text(channel)
                        .font(DesignSystem.Fonts.footer)
                        .foregroundStyle(DesignSystem.Colors.pencil)
                    Spacer()
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.bottom, DesignSystem.Spacing.sm)
            }
        }
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.card))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .sheet(isPresented: $showInspector) {
            ObjectInspectorSheet(object: object)
        }
    }
}

// MARK: - Channel Filter (placeholder — full ConversationListView adapted for Stream)

struct ChannelFilterView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(appState.servers) { server in
                    Section(server.name.isEmpty ? server.host : server.name) {
                        let conversations = appState.conversations(forServer: server.host)
                        ForEach(conversations) { conv in
                            HStack {
                                Text(conv.name)
                                    .font(DesignSystem.Fonts.data(13))
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption2)
                                    .foregroundStyle(DesignSystem.Colors.pencil)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Channels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
