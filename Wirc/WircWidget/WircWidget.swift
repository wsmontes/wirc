import WidgetKit
import SwiftUI

// MARK: - Sendable bridge for WidgetKit completion callback

private final class TimelineCompletion: @unchecked Sendable {
    let handler: (Timeline<SimpleEntry>) -> Void
    init(handler: @escaping (Timeline<SimpleEntry>) -> Void) {
        self.handler = handler
    }
}

// MARK: - Timeline Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(cards: [
            CardData(title: "Example Article", source: "RSS", time: "2m ago"),
            CardData(title: "Latest Episode", source: "Podcast", time: "1h ago"),
            CardData(title: "New Release", source: "GitHub", time: "3h ago")
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let sendableCompletion = TimelineCompletion(handler: completion)
        Task {
            let store = JSONFileStore()
            let objects = (try? await store.all()) ?? []
            let cards = objects
                .filter { $0.type.contains("wom:Post") }
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(3)
                .map { CardData(title: $0.name ?? "", source: $0.data["network"] ?? "", time: $0.createdAt.formatted(.relative(presentation: .named))) }
            let entry = SimpleEntry(cards: Array(cards))
            let nextUpdate = Date().addingTimeInterval(15 * 60)
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            sendableCompletion.handler(timeline)
        }
    }
}

// MARK: - Data Types

struct SimpleEntry: TimelineEntry {
    let date: Date = .now
    let cards: [CardData]
}

struct CardData: Identifiable {
    let id = UUID()
    let title: String
    let source: String
    let time: String
}

// MARK: - Widget View

struct WircWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        if entry.cards.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No feed items yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(entry.cards) { card in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(sourceColor(card.source))
                            .frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(card.title)
                                .font(.caption)
                                .lineLimit(1)
                            Text(card.time)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func sourceColor(_ s: String) -> Color {
        switch s.lowercased() {
        case "rss": return .orange
        case "mastodon": return .purple
        case "youtube": return .red
        case "podcast": return .indigo
        case "github": return .green
        default: return .gray
        }
    }
}

// MARK: - Widget Configuration

struct WircWidget: Widget {
    let kind = "WircWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            WircWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Latest Posts")
        .description("Shows your most recent feed items.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
