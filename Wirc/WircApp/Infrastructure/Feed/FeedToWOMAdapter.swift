import Foundation

/// Converts parsed FeedItems into WOMObjects.
/// Type mapping is driven by the subscription's sourceType.
/// Mirrors IRCToWOMAdapter in pattern.
final class FeedToWOMAdapter: @unchecked Sendable {

    /// Convert feed items to WOM objects, skipping items already in the store (dedup by canonicalUrl).
    func convert(
        items: [FeedItem],
        subscription: FeedSubscription,
        store: WOMStore
    ) async -> [WOMObject] {
        let existingURLs = await existingCanonicalURLs(in: store)
        return items.compactMap { item in
            guard !existingURLs.contains(item.link) else { return nil }
            return convertItem(item, subscription: subscription)
        }
    }

    /// Convert a single FeedItem with no dedup check (for direct use).
    func convertSingle(item: FeedItem, subscription: FeedSubscription) -> WOMObject {
        convertItem(item, subscription: subscription)
    }

    // MARK: - Private

    private func existingCanonicalURLs(in store: WOMStore) async -> Set<String> {
        guard let all = try? await store.all() else { return [] }
        return Set(all.compactMap { $0.data["canonicalUrl"] })
    }

    private func convertItem(_ item: FeedItem, subscription: FeedSubscription) -> WOMObject {
        let types = womTypes(for: subscription.sourceType)
        let objectID = WOMIDGenerator.generate(type: "post")

        var data: [String: String] = [
            "network": subscription.sourceType.rawValue,
            "canonicalUrl": item.link,
            "feedTitle": subscription.title,
            "feedURL": subscription.feedURL,
            "sourceType": subscription.sourceType.rawValue
        ]

        if let author = item.author { data["author"] = author }
        if let category = item.category { data["category"] = category }
        if let duration = item.duration { data["duration"] = duration }
        if let encURL = item.enclosureURL { data["enclosureURL"] = encURL }
        if let encType = item.enclosureType { data["enclosureType"] = encType }

        var attachments: [WOMReference] = []
        if let encURL = item.enclosureURL {
            var attType: [String] = ["wom:Media"]
            if let mime = item.enclosureType {
                if mime.hasPrefix("image/") { attType.append("media:image") }
                else if mime.hasPrefix("audio/") { attType.append("media:audio") }
                else if mime.hasPrefix("video/") { attType.append("media:video") }
            }
            attachments.append(WOMReference(
                id: encURL,
                type: attType,
                name: "enclosure"
            ))
        }

        return WOMObject(
            id: objectID,
            type: types,
            createdAt: item.publishedAt ?? Date(),
            attributedTo: WOMReference(
                id: subscription.feedURL,
                type: ["wom:RemoteIdentity"],
                name: item.author ?? subscription.title
            ),
            content: WOMContent(
                format: item.description?.contains("<") == true ? "text/html" : "text/plain",
                text: item.description ?? ""
            ),
            data: data,
            provenance: WOMProvenance(
                origin: "remotePeer",
                source: WOMReference(
                    id: subscription.feedURL,
                    type: provenanceTypes(for: subscription.sourceType)
                ),
                createdAt: Date(),
                confidence: 1.0,
                reviewStatus: "none"
            ),
            attachments: attachments
        )
    }

    private func womTypes(for sourceType: FeedSourceType) -> [String] {
        var types = ["wom:Post"]
        switch sourceType {
        case .youtube:
            types.append("external.youtube.video")
        case .podcast:
            types.append("external.podcast.episode")
        case .github:
            types.append("external.github.release")
        case .rss, .atom:
            break // just wom:Post
        }
        return types
    }

    private func provenanceTypes(for sourceType: FeedSourceType) -> [String] {
        switch sourceType {
        case .youtube:
            return ["youtube:Channel"]
        case .podcast:
            return ["podcast:Feed"]
        case .github:
            return ["github:Repo"]
        case .rss, .atom:
            return ["rss:Feed"]
        }
    }
}
