import SwiftUI

struct FeedCard: View {
    let post: WOMObject
    @State private var isExpanded = false
    @State private var showInspector = false

    private var cardURL: URL? {
        let link = post.data["canonicalUrl"] ?? post.data["url"] ?? post.data["link"] ?? ""
        return URL(string: link)
    }

    // MARK: - Derived properties

    private var network: String { post.data["network"] ?? "" }

    private var sourceColor: Color {
        DesignSystem.Colors.forSource(network)
    }

    private var isYouTubeVideo: Bool {
        post.type.contains("external.youtube.video")
    }
    private var isPodcastEpisode: Bool {
        post.type.contains("external.podcast.episode")
    }
    private var isGitHubRelease: Bool {
        post.type.contains("external.github.release")
    }
    private var isBoost: Bool {
        post.type.contains("wom:Boost")
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            provenanceBadge
            hairline
            contentArea
            if hasFooter { footerArea }
            if isExpanded { expandedActions }
        }
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: DesignSystem.Radius.card).stroke(DesignSystem.Colors.border, lineWidth: 0.5))
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isExpanded.toggle() }
        }
        .sheet(isPresented: $showInspector) {
            ObjectInspectorSheet(object: post)
        }
    }

    // MARK: - Expanded Actions

    private var expandedActions: some View {
        VStack(spacing: 0) {
            Divider().padding(.vertical, DesignSystem.Spacing.sm)
            HStack(spacing: DesignSystem.Spacing.lg) {
                if let url = cardURL {
                    Button { UIApplication.shared.open(url) } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "safari").font(.title3)
                            Text("Open").font(.system(size: 10))
                        }
                    }
                    Button {
                        let avc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let root = scene.windows.first?.rootViewController {
                            root.present(avc, animated: true)
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "square.and.arrow.up").font(.title3)
                            Text("Share").font(.system(size: 10))
                        }
                    }
                    Button { UIPasteboard.general.string = url.absoluteString } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "doc.on.doc").font(.title3)
                            Text("Copy").font(.system(size: 10))
                        }
                    }
                }
                Button { showInspector = true } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "info.circle").font(.title3)
                        Text("Inspect").font(.system(size: 10))
                    }
                }
            }
            .foregroundStyle(DesignSystem.Colors.pencil)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.bottom, DesignSystem.Spacing.sm)
        }
    }

    // MARK: - Provenance Badge

    private var provenanceBadge: some View {
        Button {
            showInspector = true
        } label: {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Circle()
                    .fill(sourceColor)
                    .frame(width: 6, height: 6)
                Text(networkDisplayName)
                    .font(DesignSystem.Fonts.provenanceLabel)
                    .foregroundStyle(DesignSystem.Colors.ink)
                if !sourceDetail.isEmpty {
                    Text("\u{00B7}")
                        .foregroundStyle(DesignSystem.Colors.pencil)
                    Text(sourceDetail)
                        .font(DesignSystem.Fonts.provenanceDetail)
                        .foregroundStyle(DesignSystem.Colors.pencil)
                        .lineLimit(1)
                }
                Text("\u{00B7}")
                    .foregroundStyle(DesignSystem.Colors.pencil)
                Text(post.createdAt, style: .relative)
                    .font(DesignSystem.Fonts.timestamp)
                    .foregroundStyle(DesignSystem.Colors.pencil)
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
        }
        .buttonStyle(.plain)
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

    private var sourceDetail: String {
        if let channel = post.data["channel"], !channel.isEmpty {
            return channel
        }
        if let instance = post.data["instance"] {
            return instance
        }
        if let feedTitle = post.data["feedTitle"] {
            return feedTitle
        }
        if let server = post.data["server"] {
            return server
        }
        return ""
    }

    // MARK: - Hairline

    private var hairline: some View {
        Rectangle()
            .fill(sourceColor)
            .frame(height: 1)
            .padding(.horizontal, DesignSystem.Spacing.md)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if isYouTubeVideo {
            youTubeContent
        } else if isPodcastEpisode {
            podcastContent
        } else if isGitHubRelease {
            gitHubContent
        } else if isBoost {
            boostContent
        } else if network == "mastodon" {
            mastodonContent
        } else {
            rssContent
        }
    }

    // MARK: - Mastodon post content

    private var mastodonContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            if let name = post.attributedTo?.displayName ?? post.attributedTo?.name {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text(name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.ink)
                    if let handle = post.data["nick"] ?? post.attributedTo?.name {
                        Text("@\(handle)")
                            .font(DesignSystem.Fonts.provenanceDetail)
                            .foregroundStyle(DesignSystem.Colors.pencil)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.top, DesignSystem.Spacing.md)
            }
            if let spoiler = post.data["spoiler"], !spoiler.isEmpty {
                Text(spoiler)
                    .font(DesignSystem.Fonts.headline)
                    .foregroundStyle(DesignSystem.Colors.ink)
                    .padding(.horizontal, DesignSystem.Spacing.md)
            }
            if let text = post.content?.text, !text.isEmpty {
                Text(text.stripHTML)
                    .font(DesignSystem.Fonts.messageBody)
                    .foregroundStyle(DesignSystem.Colors.ink)
                    .lineLimit(12)
                    .padding(.horizontal, DesignSystem.Spacing.md)
            }
            // Media attachments
            if !post.attachments.isEmpty {
                mediaAttachments
            }
        }
    }

    private var mediaAttachments: some View {
        ForEach(post.attachments) { att in
            if att.type?.contains("image") == true || att.type?.contains("media:image") == true,
               let url = URL(string: att.id) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.thumbnail))
                    default:
                        EmptyView()
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
            }
        }
    }

    // MARK: - Boost content

    private var boostContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            if let booster = post.data["boostedByDisplayName"], !booster.isEmpty {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "arrow.2.squarepath")
                        .font(.caption2)
                    Text("\(booster) boosted")
                        .font(DesignSystem.Fonts.provenanceDetail)
                }
                .foregroundStyle(DesignSystem.Colors.mastodon)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.top, DesignSystem.Spacing.sm)
            }
            // Original content rendered same as mastodon post
            if let text = post.content?.text, !text.isEmpty {
                Text(text.stripHTML)
                    .font(DesignSystem.Fonts.messageBody)
                    .foregroundStyle(DesignSystem.Colors.ink)
                    .lineLimit(12)
                    .padding(.horizontal, DesignSystem.Spacing.md)
            }
        }
    }

    // MARK: - RSS article content

    private var rssContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            if let name = post.name, !name.isEmpty {
                Text(name)
                    .font(DesignSystem.Fonts.headline)
                    .foregroundStyle(DesignSystem.Colors.ink)
                    .lineLimit(3)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.top, DesignSystem.Spacing.md)
            }
            if let author = post.attributedTo?.name {
                Text(author)
                    .font(DesignSystem.Fonts.provenanceDetail)
                    .foregroundStyle(DesignSystem.Colors.pencil)
                    .padding(.horizontal, DesignSystem.Spacing.md)
            }
            if let text = post.content?.text, !text.isEmpty {
                Text(text.stripHTML)
                    .font(DesignSystem.Fonts.cardBody)
                    .foregroundStyle(DesignSystem.Colors.ink)
                    .lineLimit(8)
                    .padding(.horizontal, DesignSystem.Spacing.md)
            }
        }
    }

    // MARK: - YouTube video content

    private var youTubeContent: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            if let thumbURL = post.data["enclosureURL"],
               let url = URL(string: thumbURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                            .aspectRatio(16/9, contentMode: .fit)
                            .frame(width: 120)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.thumbnail))
                    default:
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.thumbnail)
                            .fill(DesignSystem.Colors.border)
                            .frame(width: 120, height: 68)
                            .overlay(Image(systemName: "play.rectangle").foregroundStyle(DesignSystem.Colors.pencil))
                    }
                }
            }
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(post.name ?? post.content?.text ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.ink)
                    .lineLimit(3)
                Text(post.attributedTo?.name ?? "")
                    .font(DesignSystem.Fonts.caption())
                    .foregroundStyle(DesignSystem.Colors.pencil)
                HStack(spacing: DesignSystem.Spacing.sm) {
                    if let dur = post.data["duration"], !dur.isEmpty {
                        Label(dur, systemImage: "clock")
                            .font(.caption2).foregroundStyle(DesignSystem.Colors.pencil)
                    }
                    pill("YouTube", color: DesignSystem.Colors.youtube)
                    Text(post.createdAt, style: .relative)
                        .font(.caption2).foregroundStyle(DesignSystem.Colors.pencil)
                }
            }
            Spacer()
        }
        .padding(DesignSystem.Spacing.md)
    }

    // MARK: - Podcast episode content

    private var podcastContent: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            if let artURL = post.data["enclosureURL"],
               let url = URL(string: artURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.thumbnail))
                    default:
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.thumbnail)
                            .fill(DesignSystem.Colors.border)
                            .frame(width: 64, height: 64)
                            .overlay(Image(systemName: "waveform").foregroundStyle(DesignSystem.Colors.pencil))
                    }
                }
            }
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(post.name ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.ink)
                    .lineLimit(2)
                Text(post.attributedTo?.name ?? post.data["feedTitle"] ?? "")
                    .font(DesignSystem.Fonts.caption())
                    .foregroundStyle(DesignSystem.Colors.pencil)
                HStack(spacing: DesignSystem.Spacing.sm) {
                    if let dur = post.data["duration"], !dur.isEmpty {
                        Label(dur, systemImage: "clock")
                            .font(.caption2).foregroundStyle(DesignSystem.Colors.pencil)
                    }
                    pill("Podcast", color: DesignSystem.Colors.podcast)
                    Text(post.createdAt, style: .relative)
                        .font(.caption2).foregroundStyle(DesignSystem.Colors.pencil)
                }
            }
            Spacer()
        }
        .padding(DesignSystem.Spacing.md)
    }

    // MARK: - GitHub release content

    private var gitHubContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: "tag.fill")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.github)
                Text(post.name ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.ink)
                Spacer()
                Text(post.createdAt, style: .relative)
                    .font(.caption2).foregroundStyle(DesignSystem.Colors.pencil)
            }
            Text(post.data["feedTitle"] ?? "")
                .font(DesignSystem.Fonts.data(12))
                .foregroundStyle(DesignSystem.Colors.pencil)
            if let desc = post.content?.text, !desc.isEmpty {
                Text(desc.stripHTML.prefix(200) + (desc.stripHTML.count > 200 ? "..." : ""))
                    .font(.system(size: 14))
                    .foregroundStyle(DesignSystem.Colors.ink)
                    .lineLimit(5)
            }
        }
        .padding(DesignSystem.Spacing.md)
    }

    // MARK: - Footer

    private var hasFooter: Bool {
        switch network.lowercased() {
        case "mastodon": return true
        default: return post.data["feedTitle"] != nil
        }
    }

    private var footerArea: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            if network == "mastodon" {
                if let replies = post.data["repliesCount"], let n = Int(replies), n > 0 {
                    Label("\(n)", systemImage: "bubble.right")
                        .font(.caption2).foregroundStyle(DesignSystem.Colors.pencil)
                }
                if let reblogs = post.data["reblogsCount"], let n = Int(reblogs), n > 0 {
                    Label("\(n)", systemImage: "arrow.2.squarepath")
                        .font(.caption2).foregroundStyle(DesignSystem.Colors.pencil)
                }
                if let favs = post.data["favouritesCount"], let n = Int(favs), n > 0 {
                    Label("\(n)", systemImage: "star")
                        .font(.caption2).foregroundStyle(DesignSystem.Colors.pencil)
                }
            }
            Spacer()
            if let feedTitle = post.data["feedTitle"] {
                Text(feedTitle)
                    .font(DesignSystem.Fonts.footer)
                    .foregroundStyle(DesignSystem.Colors.pencil)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
    }

    // MARK: - Helpers

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.badge))
    }
}

// MARK: - HTML stripping helper

extension String {
    /// Fast HTML tag stripper — uses regex only, never NSAttributedString
    /// (which blocks the main thread when called during scroll rendering).
    var stripHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
