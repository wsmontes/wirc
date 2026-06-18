import Foundation
import os.log

/// Converts parsed FeedItems into WOMObjects.
/// Type mapping is driven by the subscription's sourceType.
/// Mirrors IRCToWOMAdapter in pattern.
final class FeedToWOMAdapter: @unchecked Sendable {

    /// Convert feed items to WOM objects, saving each one atomically via the store's
    /// dedup-aware `saveIfNew`. Returns only the objects that were newly saved
    /// (skipping duplicates). This avoids the TOCTOU race between dedup check and save.
    func convert(
        items: [FeedItem],
        subscription: FeedSubscription,
        store: WOMStore
    ) async -> [WOMObject] {
        var savedObjects: [WOMObject] = []
        for item in items {
            let object = convertItem(item, subscription: subscription)
            let canonicalURL = object.data["canonicalUrl"] ?? item.link
            do {
                let isNew = try await store.saveIfNew(object, byCanonicalURL: canonicalURL)
                if isNew {
                    savedObjects.append(object)
                }
            } catch {
                os_log(.error, "FeedToWOMAdapter: saveIfNew failed for %{public}@: %{public}@",
                       canonicalURL, error.localizedDescription)
            }
        }
        return savedObjects
    }

    /// Convert a single FeedItem with no dedup check (for direct use).
    func convertSingle(item: FeedItem, subscription: FeedSubscription) -> WOMObject {
        convertItem(item, subscription: subscription)
    }

    // MARK: - Private

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

        // Determine content format
        let contentFormat: String = item.description?.contains("<") == true ? "text/html" : "text/plain"

        // Attachments from enclosures
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

        // Source reference for provenance
        let sourceRef = WOMReference(
            id: subscription.feedURL,
            type: provenanceTypes(for: subscription.sourceType)
        )

        // Attribution
        let attributionRef = WOMReference(
            id: subscription.feedURL,
            type: ["wom:RemoteIdentity"],
            name: item.author ?? subscription.title,
            displayName: item.author,
            url: subscription.feedURL
        )

        // Classification based on source type
        let classification = WOMClassification(
            semanticType: semanticType(for: subscription.sourceType),
            dataSubject: "remote_peer",
            origin: WOMOrigin.remotePeer.rawValue,
            sensitivity: WOMDataSensitivity.public.rawValue,
            category: WOMCategory(scheme: "wom.feed.sourceType", value: subscription.sourceType.rawValue),
            topics: item.category.map { [$0] },
            confidence: 1.0
        )

        return WOMObject(
            id: objectID,
            type: types,
            createdAt: item.publishedAt ?? Date(),
            schema: WOMSchema.post,
            name: item.title,
            attributedTo: attributionRef,
            content: WOMContent(
                format: contentFormat,
                text: item.description ?? ""
            ),
            data: data,
            provenance: .remotePeer(
                source: sourceRef,
                actor: attributionRef,
                createdAt: Date()
            ),
            governance: defaultGovernance(for: subscription.sourceType),
            classification: classification,
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

    private func semanticType(for sourceType: FeedSourceType) -> String {
        switch sourceType {
        case .youtube: return "social.video"
        case .podcast: return "social.podcast"
        case .github: return "development.release"
        case .rss, .atom: return "social.post"
        }
    }

    private func defaultGovernance(for sourceType: FeedSourceType) -> WOMGovernance {
        let sharing: String
        switch sourceType {
        case .youtube, .podcast, .github:
            sharing = WOMSharing.public.rawValue
        case .rss, .atom:
            sharing = WOMSharing.public.rawValue
        }
        return WOMGovernance(
            purpose: ["curation"],
            adsUse: WOMAdsUse.notAllowed.rawValue,
            agentUse: "allowed",
            sharing: sharing,
            retention: "forever"
        )
    }
}
