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
                                .font(DesignSystem.Fonts.provenanceDetail)
                                .foregroundStyle(DesignSystem.Colors.pencil)
                            Text(event.server)
                                .font(DesignSystem.Fonts.provenanceDetail)
                                .foregroundStyle(DesignSystem.Colors.signal)
                            Text(event.parsedAs)
                                .font(DesignSystem.Fonts.provenanceDetail)
                                .foregroundStyle(DesignSystem.Colors.signal)
                        }
                        Text(event.raw)
                            .font(DesignSystem.Fonts.mono(12))
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
