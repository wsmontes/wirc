import SwiftUI

struct FeedCard: View {
    let post: WOMObject

    private var authorName: String {
        post.attributedTo?.name ?? "unknown"
    }

    private var authorHandle: String {
        post.data["boostedBy"] ?? ""
    }

    private var text: String {
        post.content?.text ?? ""
    }

    private var isBoost: Bool {
        post.type.contains("wom:Boost")
    }

    private var networkIcon: String {
        let net = post.data["network"] ?? ""
        switch net {
        case "mastodon": return "m.circle.fill"
        case "irc": return "number"
        default: return "globe"
        }
    }

    private var networkColor: Color {
        let net = post.data["network"] ?? ""
        switch net {
        case "mastodon": return .purple
        case "irc": return .blue
        default: return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 8) {
                // Avatar placeholder
                Circle()
                    .fill(networkColor.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: networkIcon)
                            .font(.caption)
                            .foregroundStyle(networkColor)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(authorName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Image(systemName: networkIcon)
                            .font(.caption2)
                            .foregroundStyle(networkColor)
                    }

                    if !authorHandle.isEmpty {
                        Text("boosted by @\(authorHandle)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if let instance = post.data["instance"] {
                        Text("@\(post.attributedTo?.id.components(separatedBy: "/@").last ?? "") · \(instance.replacingOccurrences(of: "https://", with: ""))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(post.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Boost indicator
            if isBoost, let boostedBy = post.data["boostedByDisplayName"] {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.2.squarepath")
                        .font(.caption2)
                    Text("\(boostedBy) boosted")
                        .font(.caption2)
                    Spacer()
                }
                .foregroundStyle(.green)
            }

            // Content
            Text(text)
                .font(.body)
                .lineLimit(12)

            // Media previews
            if !post.attachments.isEmpty {
                ForEach(post.attachments) { att in
                    let url = att.id; if att.type?.contains("image") == true {
                        AsyncImage(url: URL(string: url)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxHeight: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            default:
                                EmptyView()
                            }
                        }
                    }
                }
            }

            // Footer
            HStack(spacing: 24) {
                // Replies
                if let count = post.data["repliesCount"], let n = Int(count), n > 0 {
                    Label("\(n)", systemImage: "bubble.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Boosts
                if let count = post.data["reblogsCount"], let n = Int(count), n > 0 {
                    Label("\(n)", systemImage: "arrow.2.squarepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Favorites
                if let count = post.data["favouritesCount"], let n = Int(count), n > 0 {
                    Label("\(n)", systemImage: "star")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Source
                Text(post.data["via"] ?? "")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
