import SwiftUI

struct FeedCard: View {
    let object: WOMObject

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(object.attributedTo?.name ?? "unknown")
                    .font(.headline)
                Spacer()
                Text(object.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(object.content?.text ?? "")
                .font(.body)
            if let source = object.data["server"] {
                Text("via \(source)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
