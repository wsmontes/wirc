import SwiftUI

struct RawEventLogView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(appState.rawEvents) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(event.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(event.server)
                                .font(.caption2)
                                .foregroundStyle(.blue)
                            Text(event.parsedAs)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        Text(event.raw)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                    Divider()
                }
            }
            .padding()
        }
        .navigationTitle("Raw Events")
    }
}
