import SwiftUI

struct LibraryView: View {
    @Environment(AppState.self) private var appState

    @State private var searchText = ""
    @State private var selectedType: LibraryFilter = .all
    @State private var showInspector = false
    @State private var inspectedObject: WOMObject?

    enum LibraryFilter: String, CaseIterable {
        case all = "All"
        case messages = "Messages"
        case posts = "Posts"
        case media = "Media"
    }

    /// Date-grouped objects matching current search + filter.
    private var groupedObjects: [(date: Date, objects: [WOMObject])] {
        var objects = appState.womObjects

        // Type filter
        switch selectedType {
        case .all: break
        case .messages: objects = objects.filter { $0.type.contains("wom:Message") }
        case .posts: objects = objects.filter { $0.type.contains("wom:Post") }
        case .media: objects = objects.filter {
            $0.type.contains("external.youtube.video") ||
            $0.type.contains("external.podcast.episode") ||
            !$0.attachments.isEmpty
        }
        }

        // Search (case-insensitive, across content, names, channels, URIs)
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            objects = objects.filter { obj in
                (obj.content?.text?.lowercased().contains(query) ?? false) ||
                (obj.name?.lowercased().contains(query) ?? false) ||
                (obj.attributedTo?.name?.lowercased().contains(query) ?? false) ||
                (obj.data["channel"]?.lowercased().contains(query) ?? false) ||
                (obj.data["server"]?.lowercased().contains(query) ?? false) ||
                (obj.data["feedTitle"]?.lowercased().contains(query) ?? false) ||
                (obj.data["instance"]?.lowercased().contains(query) ?? false) ||
                obj.id.lowercased().contains(query)
            }
        }

        // Group by calendar day
        let cal = Calendar.current
        let grouped = Dictionary(grouping: objects) { obj -> Date in
            cal.startOfDay(for: obj.createdAt)
        }
        return grouped
            .map { (date: $0.key, objects: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter chips
                filterBar
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.sm)

                if groupedObjects.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(groupedObjects, id: \.date) { group in
                            Section {
                                ForEach(group.objects) { object in
                                    LibraryRow(object: object)
                                        .onTapGesture {
                                            inspectedObject = object
                                            showInspector = true
                                        }
                                }
                            } header: {
                                Text(group.date, style: .date)
                                    .font(DesignSystem.Fonts.dateHeader)
                                    .foregroundStyle(DesignSystem.Colors.pencil)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(DesignSystem.Colors.page)
            .searchable(text: $searchText, prompt: "Search objects...")
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { exportAll() } label: {
                            Label("Export All", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showInspector) {
                if let obj = inspectedObject {
                    ObjectInspectorSheet(object: obj)
                }
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(LibraryFilter.allCases, id: \.self) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedType = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(DesignSystem.Fonts.chipLabel)
                            .foregroundStyle(selectedType == filter ? .white : DesignSystem.Colors.ink)
                            .padding(.horizontal, DesignSystem.Spacing.md)
                            .padding(.vertical, DesignSystem.Spacing.sm)
                            .background(selectedType == filter ? DesignSystem.Colors.signal : DesignSystem.Colors.border)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.chip))
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Your library is empty", systemImage: "archivebox")
        } description: {
            Text("Objects from Stream are automatically saved here.\nOr import a WOM Bundle to get started.")
        }
    }

    // MARK: - Export (stub — full WOM Bundle export in future task)

    private func exportAll() {
        // Stub: for now, encode all objects to JSON and share
        // Full WOM Bundle export per spec §21 to be implemented in a follow-up
        guard let data = try? JSONEncoder().encode(appState.womObjects),
              let json = String(data: data, encoding: .utf8) else { return }
        let activityVC = UIActivityViewController(
            activityItems: [json],
            applicationActivities: nil
        )
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = windowScene.windows.first?.rootViewController {
            root.present(activityVC, animated: true)
        }
    }
}

// MARK: - Library Row

struct LibraryRow: View {
    let object: WOMObject

    private var network: String { object.data["network"] ?? "unknown" }
    private var sourceColor: Color { DesignSystem.Colors.forSource(network) }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Circle()
                .fill(sourceColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text(networkDisplayName)
                        .font(DesignSystem.Fonts.provenanceLabel)
                        .foregroundStyle(sourceColor)
                    if let channel = object.data["channel"] {
                        Text(channel)
                            .font(DesignSystem.Fonts.provenanceDetail)
                            .foregroundStyle(DesignSystem.Colors.pencil)
                    }
                }
                if let text = object.content?.text {
                    Text(text.stripHTML)
                        .font(DesignSystem.Fonts.caption())
                        .foregroundStyle(DesignSystem.Colors.ink)
                        .lineLimit(1)
                } else if let name = object.name {
                    Text(name)
                        .font(DesignSystem.Fonts.caption())
                        .foregroundStyle(DesignSystem.Colors.ink)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(object.createdAt, style: .time)
                .font(DesignSystem.Fonts.timestamp)
                .foregroundStyle(DesignSystem.Colors.pencil)
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
    }

    private var networkDisplayName: String {
        switch network.lowercased() {
        case "irc": return "IRC"
        case "mastodon": return "Mastodon"
        case "rss": return "RSS"
        case "github": return "GitHub"
        case "youtube": return "YouTube"
        case "podcast": return "Podcast"
        default: return network.capitalized
        }
    }
}
