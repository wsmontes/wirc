import SwiftUI

struct WOMObjectInspectorView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List(appState.womObjects.reversed()) { object in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(object.type.joined(separator: ", "))
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(.blue)
                    Spacer()
                    Text(object.createdAt, style: .time)
                        .font(DesignSystem.Fonts.provenanceDetail)
                        .foregroundStyle(.secondary)
                }
                Text(object.content?.text ?? "(no text)")
                    .font(DesignSystem.Fonts.body())
                    .lineLimit(3)

                if let json = prettyJSON(object) {
                    Text(json)
                        .font(DesignSystem.Fonts.mono(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(10)
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("WOM Objects")
    }

    private func prettyJSON(_ object: WOMObject) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(object),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }
}
