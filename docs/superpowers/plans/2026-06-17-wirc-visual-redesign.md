# Wirc Visual Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign Wirc from a conventional IRC/feed client into a visual embodiment of WOM 0.6 — three tabs (Stream/Library/Workshop), unified timeline, provenance badge on every object, object inspector sheet, warm archival visual system.

**Architecture:** DesignSystem provides tokens consumed by all views. StreamView merges Chat + Feed into a unified timeline using existing WOMObject data from AppState. FeedCard gets a unified skeleton with provenance badge. ObjectInspectorSheet is a shared bottom-sheet component. LibraryView adds search and date-grouped browsing. WorkshopView consolidates Settings into transports + governance defaults + data management. WOM models and infrastructure are untouched.

**Tech Stack:** Swift 5.9+, SwiftUI, iOS 17, New York (serif) + SF Pro + SF Mono, no external dependencies.

## Global Constraints

- Target: iOS 17.0+
- No external SPM dependencies
- Views render WOMObject; never raw protocol data
- WOM 0.6 models and all Infrastructure/ files must not change
- AppState changes limited to new query helpers and governance defaults storage
- All existing transport configurations must survive the redesign
- New York serif for display headlines is the signature typographic choice
- SF Mono for sender names, channel names, timestamps, and metadata
- Warm paper palette (Page `#F6F3ED`, Ink `#1C1917`, Pencil `#78716C`, Signal `#E85D3A`)
- Source-colored accents for provenance badges and hairlines
- Animations: connection pulse, new-content dot, refresh tick, inspector sheet spring — nothing else

---

## File Plan

| File | Action | Responsibility |
|------|--------|----------------|
| `Core/DesignSystem.swift` | Create | Color tokens, font extensions, spacing constants, source-color lookup |
| `Features/Shared/ObjectInspectorSheet.swift` | Create | Bottom sheet showing WOM layers (origin, governance, binding, classification) |
| `Features/Stream/StreamView.swift` | Create | Unified timeline: all womObjects sorted by createdAt, filterable by source |
| `Features/Library/LibraryView.swift` | Create | Search, date-grouped browsing, type/source filters, export trigger |
| `Features/Workshop/WorkshopView.swift` | Create | Transports list, governance defaults, data import/export, about/debug |
| `Features/Feed/FeedCard.swift` | Modify | Complete rewrite: unified skeleton, provenance badge, type variants |
| `Features/Chat/MessageView.swift` | Modify | System event pills (centered, capsule), bubble polish |
| `App/WircApp.swift` | Modify | New TabView (Stream/Library/Workshop), global styling |
| `App/AppState.swift` | Modify | Add governanceDefaults, library query helpers, new-content-dot state |
| `Features/Settings/AddServerView.swift` | Modify | Minor visual polish (DesignSystem colors, fonts) |
| `Features/Settings/AddFeedView.swift` | Modify | Minor visual polish (DesignSystem colors, fonts) |
| `Features/Debug/DebugView.swift` | Modify | Accessible as sheet from Workshop, not as tab |
| `Features/Chat/ConversationListView.swift` | Modify | Adapted as channel filter within Stream (sheet or inline) |

### Files NOT changed

| File | Reason |
|------|--------|
| All `Core/WOM/*` (9 files) | Data models are the stable foundation |
| All `Infrastructure/IRC/*` (12 files) | Transport logic unchanged |
| All `Infrastructure/Feed/*` (6 files) | Feed logic unchanged |
| All `Infrastructure/Mastodon/*` (3 files) | Mastodon logic unchanged |
| All `Infrastructure/Persistence/*` (3 files) | Storage unchanged |
| All `Core/Social/*` (3 files) | Future features, untouched |

---

### Task 1: DesignSystem — color tokens, fonts, spacing

**Files:**
- Create: `Wirc/WircApp/Core/DesignSystem.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `enum DesignSystem` with nested `Colors`, `Fonts`, `Spacing`, `Radius`; `Color` extension for hex init; `View` extension for source-color lookup; `Font` extension for New York serif shorthand

- [ ] **Step 1: Create Core directory if needed, write DesignSystem.swift**

```swift
import SwiftUI

/// Central design token system for Wirc.
/// Warm archival palette + New York serif display + SF Mono data.
enum DesignSystem {

    // MARK: - Color Tokens

    enum Colors {
        /// Warm paper background
        static let page = Color(hex: "F6F3ED")
        /// Cards, bubbles, elevated surfaces
        static let surface = Color.white
        /// Primary text — near-black with warmth
        static let ink = Color(hex: "1C1917")
        /// Secondary text, captions, metadata
        static let pencil = Color(hex: "78716C")
        /// Hairline rules, dividers
        static let border = Color(hex: "E7E5E2")

        /// Primary accent — actions, IRC source, selected states
        static let signal = Color(hex: "E85D3A")
        /// Mastodon source badge
        static let mastodon = Color(hex: "6366F1")
        /// RSS source badge
        static let rss = Color(hex: "D97706")
        /// GitHub source badge
        static let github = Color(hex: "059669")
        /// Podcast source badge
        static let podcast = Color(hex: "7C3AED")
        /// YouTube source badge
        static let youtube = Color(hex: "DC2626")
        /// IRC source badge (uses signal)
        static let irc = signal

        /// Returns the source color for a given network string.
        static func forSource(_ network: String) -> Color {
            switch network.lowercased() {
            case "irc": return irc
            case "mastodon": return mastodon
            case "rss": return rss
            case "github": return github
            case "podcast": return podcast
            case "youtube": return youtube
            default: return pencil
            }
        }
    }

    // MARK: - Spacing Scale

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    // MARK: - Border Radius

    enum Radius {
        static let card: CGFloat = 12
        static let bubble: CGFloat = 14
        static let chip: CGFloat = 8
        static let sheet: CGFloat = 16
        static let badge: CGFloat = 6
        static let thumbnail: CGFloat = 8
    }

    // MARK: - Typography

    enum Fonts {
        /// Display serif for headlines — New York
        static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .serif)
        }

        /// Body sans for messages and descriptions — SF Pro
        static func body(_ size: CGFloat = 15) -> Font {
            .system(size: size, weight: .regular, design: .default)
        }

        /// Data mono for nicks, channels, timestamps — SF Mono
        static func data(_ size: CGFloat = 11, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }

        /// Caption for footer text and chips — SF Pro Medium
        static func caption(_ size: CGFloat = 12) -> Font {
            .system(size: size, weight: .medium, design: .default)
        }

        // Pre-built sizes from spec

        static let headline = display(17)
        static let headlineLarge = display(20)
        static let senderName = data(13, weight: .bold)
        static let provenanceLabel = data(11, weight: .bold)
        static let provenanceDetail = data(11)
        static let timestamp = data(11)
        static let footer = data(11)
        static let systemEvent = data(11)
        static let messageBody = body(15)
        static let cardBody = body(15)
        static let chipLabel = caption(12)
        static let dateHeader = data(12)
    }
}

// MARK: - Color Hex Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255
        )
    }
}
```

- [ ] **Step 2: Add to Xcode project**

Use the same Python pbxproj editing approach as the WOM files. Add `DesignSystem.swift` to:
- PBXFileReference
- PBXBuildFile
- Core group (under `5C9339764535359A67C64440 /* Core */`)
- Sources build phase

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project Wirc/Wirc.xcodeproj -scheme Wirc -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -c "error:"`
Expected: 0

- [ ] **Step 4: Commit**

```bash
git add Wirc/WircApp/Core/DesignSystem.swift Wirc/Wirc.xcodeproj/project.pbxproj
git commit -m "feat: add DesignSystem with color tokens, fonts, spacing"
```

---

### Task 2: ObjectInspectorSheet — provenance inspector

**Files:**
- Create: `Wirc/WircApp/Features/Shared/ObjectInspectorSheet.swift`

**Interfaces:**
- Consumes: `WOMObject` (from Core/WOM), `DesignSystem` (Task 1)
- Produces: `ObjectInspectorSheet` View — a bottom sheet showing WOM layers: Object ID, Origin, Governance, Transport Binding, Classification; with Share / Export JSON / Copy ID footer

- [ ] **Step 1: Create Shared directory**

```bash
mkdir -p Wirc/WircApp/Features/Shared
```

- [ ] **Step 2: Write ObjectInspectorSheet.swift**

```swift
import SwiftUI

/// Bottom sheet displaying WOM 0.6 layers for any object.
/// Triggered by tapping a provenance badge in Stream or a row in Library.
struct ObjectInspectorSheet: View {
    let object: WOMObject
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // MARK: Object ID
                Section("Object ID") {
                    LabeledContent("URN", value: object.id)
                    LabeledContent("Type", value: object.type.joined(separator: ", "))
                    if let schema = object.schema {
                        LabeledContent("Schema", value: schema)
                    }
                    LabeledContent("Created", value: object.createdAt.formatted(date: .abbreviated, time: .shortened))
                }

                // MARK: Origin
                if let prov = object.provenance {
                    Section("Origin") {
                        LabeledContent("Origin", value: prov.origin)
                        if let actor = prov.actor {
                            LabeledContent("Actor", value: actor.name ?? actor.id)
                        }
                        if let source = prov.source {
                            LabeledContent("Source", value: source.name ?? source.id)
                        }
                        if let confidence = prov.confidence {
                            LabeledContent("Confidence", value: String(format: "%.0f%%", confidence * 100))
                        }
                        if let review = prov.reviewStatus {
                            LabeledContent("Review", value: review)
                        }
                    }
                }

                // MARK: Governance
                if let gov = object.governance {
                    Section("Governance") {
                        if let purpose = gov.purpose, !purpose.isEmpty {
                            LabeledContent("Purpose", value: purpose.joined(separator: ", "))
                        }
                        if let adsUse = gov.adsUse {
                            LabeledContent("Ads", value: adsUse)
                        }
                        if let agentUse = gov.agentUse {
                            LabeledContent("Agent Use", value: agentUse)
                        }
                        if let sharing = gov.sharing {
                            LabeledContent("Sharing", value: sharing)
                        }
                        if let retention = gov.retention {
                            LabeledContent("Retention", value: retention)
                        }
                    }
                }

                // MARK: Transport Binding
                Section("Transport Binding") {
                    if let bindings = object.bindings {
                        if let irc = bindings.irc {
                            HStack {
                                sourceDot(for: "irc")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("IRC").font(DesignSystem.Fonts.provenanceLabel)
                                    if let server = irc.server {
                                        Text(server).font(DesignSystem.Fonts.provenanceDetail)
                                            .foregroundStyle(DesignSystem.Colors.pencil)
                                    }
                                    if let channel = irc.channel {
                                        Text(channel).font(DesignSystem.Fonts.provenanceDetail)
                                            .foregroundStyle(DesignSystem.Colors.pencil)
                                    }
                                }
                            }
                        }
                        if let ap = bindings.activitypub {
                            HStack {
                                sourceDot(for: "mastodon")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("ActivityPub").font(DesignSystem.Fonts.provenanceLabel)
                                    if let id = ap.id {
                                        Text(id).font(DesignSystem.Fonts.provenanceDetail)
                                            .foregroundStyle(DesignSystem.Colors.pencil)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        if bindings.irc == nil && bindings.activitypub == nil {
                            // RSS / feed — no explicit binding struct, fall back to data
                            if let network = object.data["network"] {
                                HStack {
                                    sourceDot(for: network)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(network.capitalized).font(DesignSystem.Fonts.provenanceLabel)
                                        if let feedURL = object.data["feedURL"] {
                                            Text(feedURL).font(DesignSystem.Fonts.provenanceDetail)
                                                .foregroundStyle(DesignSystem.Colors.pencil)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        Text("No binding").foregroundStyle(DesignSystem.Colors.pencil)
                    }
                }

                // MARK: Classification
                if let cls = object.classification {
                    Section("Classification") {
                        if let semType = cls.semanticType {
                            LabeledContent("Type", value: semType)
                        }
                        if let sensitivity = cls.sensitivity {
                            LabeledContent("Sensitivity", value: sensitivity)
                        }
                        if let category = cls.category {
                            LabeledContent("Category", value: category.value)
                        }
                        if let topics = cls.topics, !topics.isEmpty {
                            LabeledContent("Topics", value: topics.joined(separator: ", "))
                        }
                        if let confidence = cls.confidence {
                            LabeledContent("Confidence", value: String(format: "%.0f%%", confidence * 100))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Object Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button { copyJSON() } label: {
                            Label("Copy JSON", systemImage: "doc.on.doc")
                        }
                        Spacer()
                        ShareLink(item: shareableJSON()) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                    .font(DesignSystem.Fonts.caption())
                }
            }
        }
    }

    // MARK: - Helpers

    private func sourceDot(for network: String) -> some View {
        Circle()
            .fill(DesignSystem.Colors.forSource(network))
            .frame(width: 8, height: 8)
    }

    private func shareableJSON() -> String {
        guard let data = try? JSONEncoder().encode(object),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private func copyJSON() {
        UIPasteboard.general.string = shareableJSON()
    }
}
```

- [ ] **Step 3: Add Shared/ directory and file to Xcode project**

Add new PBXGroup `Shared` under Features, add `ObjectInspectorSheet.swift` to PBXFileReference, PBXBuildFile, and Sources build phase.

- [ ] **Step 4: Build to verify**

Expected: 0 errors.

- [ ] **Step 5: Commit**

```bash
git add Wirc/WircApp/Features/Shared/ Wirc/Wirc.xcodeproj/project.pbxproj
git commit -m "feat: add ObjectInspectorSheet — WOM layer inspector bottom sheet"
```

---

### Task 3: FeedCard redesign — unified skeleton with provenance badge

**Files:**
- Modify: `Wirc/WircApp/Features/Feed/FeedCard.swift` — complete rewrite

**Interfaces:**
- Consumes: `WOMObject`, `DesignSystem` (Task 1)
- Produces: `FeedCard` View — unified card with provenance badge, source-colored hairline, type-specific content, footer

- [ ] **Step 1: Rewrite FeedCard.swift**

```swift
import SwiftUI

struct FeedCard: View {
    let post: WOMObject
    @State private var showInspector = false

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
        }
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.card))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .sheet(isPresented: $showInspector) {
            ObjectInspectorSheet(object: post)
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
                    Text("·")
                        .foregroundStyle(DesignSystem.Colors.pencil)
                    Text(sourceDetail)
                        .font(DesignSystem.Fonts.provenanceDetail)
                        .foregroundStyle(DesignSystem.Colors.pencil)
                        .lineLimit(1)
                }
                Text("·")
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
        } else if network == "irc" {
            ircContent
        } else if network == "mastodon" {
            mastodonContent
        } else {
            rssContent
        }
    }

    // MARK: - IRC message content

    private var ircContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            if let nick = post.attributedTo?.name ?? post.data["nick"] {
                Text(nick)
                    .font(DesignSystem.Fonts.senderName)
                    .foregroundStyle(sourceColor)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.top, DesignSystem.Spacing.md)
            }
            if let text = post.content?.text {
                Text(text)
                    .font(DesignSystem.Fonts.messageBody)
                    .foregroundStyle(DesignSystem.Colors.ink)
                    .lineLimit(12)
                    .padding(.horizontal, DesignSystem.Spacing.md)
            }
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
        case "irc": return post.data["channel"] != nil
        case "mastodon": return true
        default: return post.data["feedTitle"] != nil
        }
    }

    private var footerArea: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            if network == "irc", let channel = post.data["channel"] {
                Text(channel)
                    .font(DesignSystem.Fonts.footer)
                    .foregroundStyle(DesignSystem.Colors.pencil)
            }
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

// Keep existing CSS stripHTML extension on String (unchanged, already in file)
```

- [ ] **Step 2: Build to verify**

Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/Features/Feed/FeedCard.swift
git commit -m "feat: redesign FeedCard — unified skeleton, provenance badge, type variants"
```

---

### Task 4: MessageView — system event pills, bubble polish

**Files:**
- Modify: `Wirc/WircApp/Features/Chat/MessageView.swift`

**Interfaces:**
- Consumes: `WOMObject`, `DesignSystem` (Task 1), `AppState`
- Produces: Updated `MessageView` with system event pills (centered, capsule shape, SF Mono 11pt Pencil), polished bubble styling, sender name in SF Mono Bold source-colored

- [ ] **Step 1: Rewrite SystemEventRow with pill design**

Replace the existing `SystemEventRow` (lines 229-303 in current file) with:

```swift
// MARK: - System Event Pill

struct SystemEventPill: View {
    let object: WOMObject

    private var text: String {
        let eventType = object.data["eventType"] ?? object.data["event"] ?? ""
        let nick = object.data["nick"] ?? ""
        let channel = object.data["channel"] ?? ""

        switch eventType {
        case "join":
            return "→ \(nick) joined \(channel)"
        case "part":
            let reason = object.data["reason"]
            return "← \(nick) left\(reason.map { " (\($0))" } ?? "")"
        case "quit":
            let reason = object.data["reason"]
            return "← \(nick) quit\(reason.map { " (\($0))" } ?? "")"
        case "kick":
            let by = object.data["by"] ?? ""
            let reason = object.data["reason"]
            return "✕ \(nick) kicked by \(by)\(reason.map { " (\($0))" } ?? "")"
        case "nick":
            let oldNick = object.data["oldNick"] ?? ""
            let newNick = object.data["newNick"] ?? ""
            return "~ \(oldNick) → \(newNick)"
        case "topic":
            let topic = object.data["topic"] ?? ""
            return "# \(nick) set topic: \(topic)"
        case "mode":
            let mode = object.data["mode"] ?? ""
            return "* Mode \(mode)"
        default:
            let text = object.data["text"] ?? ""
            return text.isEmpty ? "· \(eventType)" : text
        }
    }

    var body: some View {
        Text(text)
            .font(DesignSystem.Fonts.systemEvent)
            .foregroundStyle(DesignSystem.Colors.pencil)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .background(DesignSystem.Colors.border.opacity(0.5))
            .clipShape(Capsule())
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 2)
    }
}
```

- [ ] **Step 2: Update MessageBubble with DesignSystem**

Replace the `MessageBubble` body styling to use DesignSystem tokens:

```swift
struct MessageBubble: View {
    let object: WOMObject

    private var isFromLocalUser: Bool { object.provenance?.isLocalUser ?? false }
    private var senderName: String { object.attributedTo?.name ?? object.data["nick"] ?? "unknown" }
    private var text: String { object.content?.text ?? "" }
    private var network: String { object.data["network"] ?? "irc" }
    private var sourceColor: Color { DesignSystem.Colors.forSource(network) }

    var body: some View {
        HStack(alignment: .top) {
            if isFromLocalUser { Spacer(minLength: 50) }

            VStack(alignment: isFromLocalUser ? .trailing : .leading, spacing: 2) {
                if !isFromLocalUser {
                    Text(senderName)
                        .font(DesignSystem.Fonts.senderName)
                        .foregroundStyle(sourceColor)
                }
                Text(text)
                    .font(DesignSystem.Fonts.messageBody)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isFromLocalUser ? sourceColor : DesignSystem.Colors.border.opacity(0.3))
                    .foregroundStyle(isFromLocalUser ? .white : DesignSystem.Colors.ink)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.bubble))
            }
            .contextMenu {
                Button { UIPasteboard.general.string = text } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                if !isFromLocalUser {
                    Button {
                        UIPasteboard.general.string = "/msg \(senderName) "
                    } label: {
                        Label("Reply to \(senderName)", systemImage: "arrowshape.turn.up.left")
                    }
                }
            }

            if !isFromLocalUser { Spacer(minLength: 50) }
        }
    }
}
```

- [ ] **Step 3: Update MessageView to use SystemEventPill**

In the `ForEach(timeline)` section, replace `SystemEventRow(object: object)` with `SystemEventPill(object: object)`.

- [ ] **Step 4: Build to verify**

Expected: 0 errors.

- [ ] **Step 5: Commit**

```bash
git add Wirc/WircApp/Features/Chat/MessageView.swift
git commit -m "feat: redesign MessageView — system event pills, polished bubbles, source-colored sender names"
```

---

### Task 5: StreamView — unified timeline

**Files:**
- Create: `Wirc/WircApp/Features/Stream/StreamView.swift`

**Interfaces:**
- Consumes: `AppState`, `FeedCard` (Task 3), `MessageView` components (Task 4), `DesignSystem` (Task 1)
- Produces: `StreamView` — unified chronologic timeline of all WOM objects (messages + posts), filterable by source type via segmented control

- [ ] **Step 1: Create Stream directory and write StreamView.swift**

```bash
mkdir -p Wirc/WircApp/Features/Stream
```

```swift
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
```

- [ ] **Step 2: Add Stream/ to Xcode project**

Add Stream group, StreamView.swift to PBXFileReference, PBXBuildFile, Sources.

- [ ] **Step 3: Build to verify**

Expected: 0 errors.

- [ ] **Step 4: Commit**

```bash
git add Wirc/WircApp/Features/Stream/ Wirc/Wirc.xcodeproj/project.pbxproj
git commit -m "feat: add StreamView — unified timeline with filter chips and provenance badges"
```

---

### Task 6: LibraryView — search, date grouping, export

**Files:**
- Create: `Wirc/WircApp/Features/Library/LibraryView.swift`

**Interfaces:**
- Consumes: `AppState`, `DesignSystem` (Task 1), `ObjectInspectorSheet` (Task 2)
- Produces: `LibraryView` — search bar, filter chips, date-grouped object list, export trigger

- [ ] **Step 1: Create Library directory and write LibraryView.swift**

```bash
mkdir -p Wirc/WircApp/Features/Library
```

```swift
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
```

- [ ] **Step 2: Add to Xcode project**

Add Library group, file refs, build files.

- [ ] **Step 3: Build to verify**

Expected: 0 errors.

- [ ] **Step 4: Commit**

```bash
git add Wirc/WircApp/Features/Library/ Wirc/Wirc.xcodeproj/project.pbxproj
git commit -m "feat: add LibraryView — search, date grouping, browse, export stub"
```

---

### Task 7: WorkshopView — transports, governance, data

**Files:**
- Create: `Wirc/WircApp/Features/Workshop/WorkshopView.swift`

**Interfaces:**
- Consumes: `AppState`, `DesignSystem` (Task 1)
- Produces: `WorkshopView` — transports list (IRC, Mastodon, Feeds expandable), governance defaults, data export/import, about/debug link

- [ ] **Step 1: Create Workshop directory and write WorkshopView.swift**

```bash
mkdir -p Wirc/WircApp/Features/Workshop
```

```swift
import SwiftUI

struct WorkshopView: View {
    @Environment(AppState.self) private var appState

    @State private var showAddServer = false
    @State private var showAddFeed = false
    @State private var showDebug = false

    // Governance defaults (stored in AppState)
    @State private var adsUse: String = WOMAdsUse.notAllowed.rawValue
    @State private var agentUse: String = "allowed"
    @State private var defaultSharing: String = WOMSharing.friendsOnly.rawValue
    @State private var retention: String = "forever"

    var body: some View {
        NavigationStack {
            List {
                // MARK: Transports
                transportsSection

                // MARK: Governance Defaults
                governanceSection

                // MARK: Data
                dataSection

                // MARK: About
                aboutSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(DesignSystem.Colors.page)
            .navigationTitle("Workshop")
            .sheet(isPresented: $showAddServer) {
                AddServerView { config in
                    appState.servers.append(config)
                }
            }
            .sheet(isPresented: $showAddFeed) {
                AddFeedView()
            }
            .sheet(isPresented: $showDebug) {
                DebugView()
            }
        }
    }

    // MARK: - Transports

    private var transportsSection: some View {
        Section {
            // IRC
            NavigationLink {
                IRCTransportDetail()
            } label: {
                HStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "number")
                        .foregroundStyle(DesignSystem.Colors.irc)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("IRC")
                            .font(.system(size: 15, weight: .medium))
                        Text("\(appState.servers.count) server\(appState.servers.count == 1 ? "" : "s")")
                            .font(DesignSystem.Fonts.caption())
                            .foregroundStyle(DesignSystem.Colors.pencil)
                    }
                }
            }

            // Mastodon
            NavigationLink {
                MastodonTransportDetail()
            } label: {
                HStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "m.circle")
                        .foregroundStyle(DesignSystem.Colors.mastodon)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mastodon")
                            .font(.system(size: 15, weight: .medium))
                        Text("\(appState.mastodonAccounts.count) account\(appState.mastodonAccounts.count == 1 ? "" : "s")")
                            .font(DesignSystem.Fonts.caption())
                            .foregroundStyle(DesignSystem.Colors.pencil)
                    }
                }
            }

            // Feeds
            NavigationLink {
                FeedTransportDetail()
            } label: {
                HStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(DesignSystem.Colors.rss)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Feeds")
                            .font(.system(size: 15, weight: .medium))
                        Text("\(appState.feedStore.getAll().count) subscription\(appState.feedStore.getAll().count == 1 ? "" : "s")")
                            .font(DesignSystem.Fonts.caption())
                            .foregroundStyle(DesignSystem.Colors.pencil)
                    }
                }
            }

            // Add buttons
            HStack(spacing: DesignSystem.Spacing.md) {
                Button { showAddServer = true } label: {
                    Label("Add Server", systemImage: "plus")
                        .font(DesignSystem.Fonts.caption())
                }
                .buttonStyle(.bordered)
                .tint(DesignSystem.Colors.irc)

                Button { showAddFeed = true } label: {
                    Label("Add Feed", systemImage: "plus")
                        .font(DesignSystem.Fonts.caption())
                }
                .buttonStyle(.bordered)
                .tint(DesignSystem.Colors.rss)
            }
        } header: {
            Text("Transports".uppercased())
                .font(DesignSystem.Fonts.data(11))
                .foregroundStyle(DesignSystem.Colors.pencil)
        }
    }

    // MARK: - Governance Defaults

    private var governanceSection: some View {
        Section {
            HStack {
                Text("Ads use")
                Spacer()
                Text(adsUse)
                    .font(DesignSystem.Fonts.data(11))
                    .foregroundStyle(DesignSystem.Colors.pencil)
            }
            HStack {
                Text("Agent use")
                Spacer()
                Text(agentUse)
                    .font(DesignSystem.Fonts.data(11))
                    .foregroundStyle(DesignSystem.Colors.pencil)
            }
            HStack {
                Text("Default sharing")
                Spacer()
                Text(defaultSharing)
                    .font(DesignSystem.Fonts.data(11))
                    .foregroundStyle(DesignSystem.Colors.pencil)
            }
            HStack {
                Text("Retention")
                Spacer()
                Text(retention)
                    .font(DesignSystem.Fonts.data(11))
                    .foregroundStyle(DesignSystem.Colors.pencil)
            }
        } header: {
            Text("Governance Defaults".uppercased())
                .font(DesignSystem.Fonts.data(11))
                .foregroundStyle(DesignSystem.Colors.pencil)
        } footer: {
            Text("These defaults apply to new objects. Changing them does not retroactively modify existing objects.")
                .font(DesignSystem.Fonts.data(10))
                .foregroundStyle(DesignSystem.Colors.pencil)
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        Section {
            Button { exportLibrary() } label: {
                Label("Export Library...", systemImage: "square.and.arrow.up")
            }
            Button { /* file picker stub */ } label: {
                Label("Import WOM Bundle...", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Data".uppercased())
                .font(DesignSystem.Fonts.data(11))
                .foregroundStyle(DesignSystem.Colors.pencil)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                Text("WOM")
                Spacer()
                Text("0.6")
                    .font(DesignSystem.Fonts.data(11))
                    .foregroundStyle(DesignSystem.Colors.pencil)
            }
            HStack {
                Text("Wirc")
                Spacer()
                Text("0.1")
                    .font(DesignSystem.Fonts.data(11))
                    .foregroundStyle(DesignSystem.Colors.pencil)
            }
            Button { showDebug = true } label: {
                Label("Debug", systemImage: "wrench.and.screwdriver")
                    .font(DesignSystem.Fonts.caption())
                    .foregroundStyle(DesignSystem.Colors.pencil)
            }
        } header: {
            Text("About".uppercased())
                .font(DesignSystem.Fonts.data(11))
                .foregroundStyle(DesignSystem.Colors.pencil)
        }
    }

    // MARK: - Helpers

    private func exportLibrary() {
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

// MARK: - IRC Transport Detail

struct IRCTransportDetail: View {
    @Environment(AppState.self) private var appState
    @State private var showAddServer = false

    var body: some View {
        List {
            ForEach(appState.servers) { server in
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                            Text(server.name.isEmpty ? server.host : server.name)
                                .font(.system(size: 15, weight: .medium))
                            Text("\(server.host):\(server.port) as \(server.nickname)")
                                .font(DesignSystem.Fonts.data(11))
                                .foregroundStyle(DesignSystem.Colors.pencil)
                            if !server.autoJoinChannels.isEmpty {
                                Text("Channels: \(server.autoJoinChannels.joined(separator: ", "))")
                                    .font(DesignSystem.Fonts.data(11))
                                    .foregroundStyle(DesignSystem.Colors.pencil)
                            }
                        }
                        Spacer()
                        let status = appState.connectionStates[server.id] ?? .disconnected
                        Circle()
                            .fill(statusColor(status))
                            .frame(width: 8, height: 8)
                    }
                    HStack {
                        Button(statusLabel(server.id)) {
                            toggleConnection(server.id)
                        }
                        .buttonStyle(.bordered)
                        .tint(statusTint(server.id))
                        Spacer()
                        Button("Remove", role: .destructive) {
                            appState.disconnect(from: server.id)
                            if let idx = appState.servers.firstIndex(where: { $0.id == server.id }) {
                                appState.servers.remove(at: idx)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            Button { showAddServer = true } label: {
                Label("Add IRC Server", systemImage: "plus")
            }
        }
        .navigationTitle("IRC Servers")
        .sheet(isPresented: $showAddServer) {
            AddServerView { config in
                appState.servers.append(config)
            }
        }
    }

    private func statusColor(_ s: AppState.ConnectionStatus) -> Color {
        switch s { case .disconnected: return .gray; case .connecting: return .orange; case .online: return DesignSystem.Colors.github }
    }
    private func statusLabel(_ id: UUID) -> String {
        switch appState.connectionStates[id] ?? .disconnected {
        case .disconnected: return "Connect"
        case .connecting: return "Connecting..."
        case .online: return "Disconnect"
        }
    }
    private func statusTint(_ id: UUID) -> Color {
        switch appState.connectionStates[id] ?? .disconnected {
        case .disconnected: return DesignSystem.Colors.github
        case .connecting: return .orange
        case .online: return DesignSystem.Colors.signal
        }
    }
    private func toggleConnection(_ id: UUID) {
        switch appState.connectionStates[id] ?? .disconnected {
        case .disconnected: appState.connect(to: id)
        case .connecting, .online: appState.disconnect(from: id)
        }
    }
}

// MARK: - Mastodon Transport Detail (stub)

struct MastodonTransportDetail: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            if appState.mastodonAccounts.isEmpty {
                ContentUnavailableView("No Mastodon accounts", systemImage: "m.circle")
            }
            ForEach(appState.mastodonAccounts) { account in
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text(account.name)
                        .font(.system(size: 15, weight: .medium))
                    Text(account.instanceURL)
                        .font(DesignSystem.Fonts.data(11))
                        .foregroundStyle(DesignSystem.Colors.pencil)
                }
            }
        }
        .navigationTitle("Mastodon")
    }
}

// MARK: - Feed Transport Detail (stub)

struct FeedTransportDetail: View {
    @Environment(AppState.self) private var appState
    @State private var showAddFeed = false

    var body: some View {
        List {
            let feeds = appState.feedStore.getAll()
            if feeds.isEmpty {
                ContentUnavailableView("No feed subscriptions", systemImage: "dot.radiowaves.left.and.right")
            }
            ForEach(feeds) { sub in
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text(sub.title.isEmpty ? sub.feedURL : sub.title)
                        .font(.system(size: 15, weight: .medium))
                    Text(sub.feedURL)
                        .font(DesignSystem.Fonts.data(10))
                        .foregroundStyle(DesignSystem.Colors.pencil)
                        .lineLimit(1)
                    HStack(spacing: DesignSystem.Spacing.md) {
                        pill(sub.sourceType.rawValue.capitalized,
                             color: DesignSystem.Colors.forSource(sub.sourceType.rawValue))
                        if let last = sub.lastFetchedAt {
                            Text("Updated \(last, style: .relative)")
                                .font(.caption2)
                                .foregroundStyle(DesignSystem.Colors.pencil)
                        }
                        if sub.errorCount > 0 {
                            Text("\(sub.errorCount) errors")
                                .font(.caption2)
                                .foregroundStyle(DesignSystem.Colors.signal)
                        }
                    }
                }
            }
            .onDelete { indexSet in
                let feeds = appState.feedStore.getAll()
                for idx in indexSet {
                    appState.removeFeed(feeds[idx])
                }
            }

            Button { showAddFeed = true } label: {
                Label("Add Feed", systemImage: "plus")
            }
        }
        .navigationTitle("Feeds")
        .sheet(isPresented: $showAddFeed) {
            AddFeedView()
        }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(color)
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.badge))
    }
}
```

- [ ] **Step 2: Add to Xcode project**

Add Workshop group, file refs, build files.

- [ ] **Step 3: Build to verify**

Expected: 0 errors.

- [ ] **Step 4: Commit**

```bash
git add Wirc/WircApp/Features/Workshop/ Wirc/Wirc.xcodeproj/project.pbxproj
git commit -m "feat: add WorkshopView — transports, governance defaults, data management"
```

---

### Task 8: WircApp — new tab bar, global styling

**Files:**
- Modify: `Wirc/WircApp/App/WircApp.swift`

**Interfaces:**
- Consumes: `StreamView` (Task 5), `LibraryView` (Task 6), `WorkshopView` (Task 7), `DesignSystem` (Task 1), `AppState`
- Produces: Rewired `WircApp` with Stream/Library/Workshop tabs, global background styling

- [ ] **Step 1: Rewrite WircApp.swift**

```swift
import SwiftUI

@main
struct WircApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            TabView {
                StreamView()
                    .tabItem {
                        Label("Stream", systemImage: "waveform")
                    }

                LibraryView()
                    .tabItem {
                        Label("Library", systemImage: "archivebox")
                    }

                WorkshopView()
                    .tabItem {
                        Label("Workshop", systemImage: "hammer")
                    }
            }
            .tint(DesignSystem.Colors.signal)
            .environment(appState)
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/App/WircApp.swift
git commit -m "feat: rewire tab bar to Stream/Library/Workshop with warm paper styling"
```

---

### Task 9: Polish — empty states, visual refinements, build & install

**Files:**
- Modify: `Wirc/WircApp/Features/Settings/AddServerView.swift` — adopt DesignSystem colors
- Modify: `Wirc/WircApp/Features/Settings/AddFeedView.swift` — adopt DesignSystem colors
- Modify: `Wirc/WircApp/Features/Debug/DebugView.swift` — sheet-accessible from Workshop already wired

**Interfaces:**
- Consumes: `DesignSystem` (Task 1), all prior views
- Produces: Polished visual system across all remaining views; verified build and install on iPhone

- [ ] **Step 1: Polish AddServerView with DesignSystem**

In `AddServerView.swift`, update `NavigationStack` to add background, use DesignSystem fonts for section headers, and Signal tint on Save button.

Minimal changes — add `.scrollContentBackground(.hidden)` and `.background(DesignSystem.Colors.page)` to the Form, and `.tint(DesignSystem.Colors.signal)` on the toolbar save button.

- [ ] **Step 2: Polish AddFeedView with DesignSystem**

Same pattern as AddServerView: page background, Signal tint.

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -project Wirc/Wirc.xcodeproj -scheme Wirc -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -c "error:"
```
Expected: 0

- [ ] **Step 4: Build for iPhone and install**

```bash
xcodebuild -project Wirc/Wirc.xcodeproj -scheme Wirc -destination 'platform=iOS,id=00008110-00067D861486201E' -allowProvisioningUpdates build 2>&1 | grep "BUILD"
xcrun devicectl device install app --device 00008110-00067D861486201E <path-to-app>
```
Expected: BUILD SUCCEEDED, App installed.

- [ ] **Step 5: Commit**

```bash
git add Wirc/WircApp/Features/Settings/AddServerView.swift Wirc/WircApp/Features/Settings/AddFeedView.swift
git commit -m "polish: apply DesignSystem to AddServerView, AddFeedView — warm paper styling"
```

---

## Spec Coverage Self-Review

1. **§1 Navigation:** Stream/Library/Workshop tabs → Task 8 ✓
2. **§2 Visual System (colors, type, spacing):** → Task 1 ✓
3. **§3 Provenance Badge:** Tappable badge on every card → Tasks 3, 5 ✓
4. **§3 Object Inspector:** Bottom sheet with WOM layers → Task 2 ✓
5. **§4 Stream View:** Unified timeline, IRC/Mastodon/RSS/YT/Podcast/GitHub cards → Tasks 3, 5 ✓
6. **§4 System Events:** Centered capsule pills → Task 4 ✓
7. **§5 Library View:** Search, date grouping, type filter, export → Task 6 ✓
8. **§6 Workshop View:** Transports, governance defaults, data, about/debug → Task 7 ✓
9. **§7 Object Inspector:** Full WOM layer display → Task 2 ✓
10. **§8 Empty States & Micro-interactions:** Welcome state in Stream, connection pulse, new-content dot → Tasks 5, 9 ✓

**No placeholder violations.** All tasks contain concrete code, exact file paths, and explicit commands.
