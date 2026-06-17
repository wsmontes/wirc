import SwiftUI

struct FeedCard: View {
    let post: WOMObject

    private var network: String { post.data["network"] ?? "" }
    private var sourceType: String { post.data["sourceType"] ?? "" }

    private var isYouTubeVideo: Bool {
        post.type.contains("external.youtube.video")
    }

    private var isPodcastEpisode: Bool {
        post.type.contains("external.podcast.episode")
    }

    private var isGitHubRelease: Bool {
        post.type.contains("external.github.release")
    }

    private var isRSS: Bool {
        network == "rss"
    }

    var body: some View {
        if isYouTubeVideo {
            youTubeCard
        } else if isPodcastEpisode {
            podcastCard
        } else if isGitHubRelease {
            gitHubCard
        } else {
            standardCard
        }
    }

    // MARK: - YouTube Video Card

    private var youTubeCard: some View {
        HStack(alignment: .top, spacing: 12) {
            // Thumbnail
            if let thumbURL = post.data["enclosureURL"],
               let url = URL(string: thumbURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fit)
                            .frame(width: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    default:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                            .frame(width: 120, height: 68)
                            .overlay(Image(systemName: "play.rectangle").foregroundStyle(.secondary))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(post.name ?? post.content?.text ?? "")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(3)

                Text(post.attributedTo?.name ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    if let dur = post.data["duration"], !dur.isEmpty {
                        Label(dur, systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Label("YouTube", systemImage: "play.rectangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Text(post.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Podcast Episode Card

    private var podcastCard: some View {
        HStack(alignment: .top, spacing: 12) {
            // Cover art
            if let artURL = post.data["enclosureURL"],
               let url = URL(string: artURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    default:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                            .frame(width: 64, height: 64)
                            .overlay(Image(systemName: "waveform").foregroundStyle(.secondary))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(post.name ?? "")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                Text(post.attributedTo?.name ?? post.data["feedTitle"] ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    if let dur = post.data["duration"], !dur.isEmpty {
                        Label(dur, systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Label("Podcast", systemImage: "waveform")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                    Text(post.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - GitHub Release Card

    private var gitHubCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "tag.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text(post.name ?? "")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(post.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(post.data["feedTitle"] ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let desc = post.content?.text, !desc.isEmpty {
                Text(desc.stripHTML.prefix(200) + (desc.stripHTML.count > 200 ? "..." : ""))
                    .font(.body)
                    .lineLimit(5)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Standard Card (Blog, Mastodon, IRC)

    private var standardCard: some View {
        // Reuse existing card layout, with RSS-awareness
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 8) {
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
                        Text(post.attributedTo?.name ?? post.data["feedTitle"] ?? "unknown")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        if isRSS {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    if let feedTitle = post.data["feedTitle"], !feedTitle.isEmpty,
                       post.attributedTo?.name != feedTitle {
                        Text("via \(feedTitle)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if let instance = post.data["instance"] {
                        Text("@\(post.attributedTo?.id.components(separatedBy: "/@").last ?? "") · \(instance)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(post.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Title (RSS posts have a name/headline)
            if let name = post.name, !name.isEmpty,
               name != post.content?.text {
                Text(name)
                    .font(.headline)
                    .fontWeight(.medium)
            }

            // Content
            if let text = post.content?.text, !text.isEmpty {
                Text(text.stripHTML)
                    .font(.body)
                    .lineLimit(12)
            }

            // Media previews (Mastodon images)
            if !post.attachments.isEmpty {
                ForEach(post.attachments) { att in
                    let url = att.id
                    if att.type?.contains("image") == true || att.type?.contains("media:image") == true {
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
                if let count = post.data["repliesCount"], let n = Int(count), n > 0 {
                    Label("\(n)", systemImage: "bubble.right")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let count = post.data["reblogsCount"], let n = Int(count), n > 0 {
                    Label("\(n)", systemImage: "arrow.2.squarepath")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let count = post.data["favouritesCount"], let n = Int(count), n > 0 {
                    Label("\(n)", systemImage: "star")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Spacer()

                // Network badge
                HStack(spacing: 2) {
                    Image(systemName: networkIcon)
                        .font(.caption2)
                    Text(post.data["via"] ?? network.capitalized)
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private var networkIcon: String {
        switch network {
        case "mastodon": return "m.circle.fill"
        case "irc": return "number"
        case "rss": return "dot.radiowaves.left.and.right"
        default: return "globe"
        }
    }

    private var networkColor: Color {
        switch network {
        case "mastodon": return .purple
        case "irc": return .blue
        case "rss": return .orange
        default: return .gray
        }
    }
}

// MARK: - HTML stripping helper

private extension String {
    var stripHTML: String {
        guard let data = data(using: .utf8) else { return self }
        if let plain = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html],
            documentAttributes: nil
        ).string {
            return plain
        }
        // Fallback: basic regex strip
        return replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
