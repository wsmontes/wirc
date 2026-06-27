import Foundation

final class MastodonToWOMAdapter: @unchecked Sendable {
    let instanceURL: String
    /// Target language for on-device translation. "off" means no translation.
    var preferredLanguage: String = "off"

    init(instanceURL: String) {
        self.instanceURL = instanceURL
    }

    func convert(status: MastodonStatus) -> WOMObject {
        if let reblog = status.reblog {
            return convertReblog(status: status, reblog: reblog)
        }
        return convertStatus(status)
    }

    /// Convert a status and translate its content if a target language is configured.
    func convertWithTranslation(status: MastodonStatus) async -> WOMObject {
        var obj = convert(status: status)
        if preferredLanguage != "off", let text = obj.content?.text, !text.isEmpty {
            let translated = await TranslationService.shared.translate(text, to: preferredLanguage)
            if translated != text {
                obj.data["translatedText"] = translated
            }
        }
        return obj
    }

    // MARK: - Conversion

    private func convertStatus(_ s: MastodonStatus) -> WOMObject {
        let plainText = stripHTML(s.content ?? "")

        var data: [String: String] = [
            "network": "mastodon",
            "instance": instanceURL,
            "statusId": s.id,
            "visibility": s.visibility ?? "public",
            "language": s.language ?? "",
            "favouritesCount": "\(s.favouritesCount ?? 0)",
            "reblogsCount": "\(s.reblogsCount ?? 0)",
            "repliesCount": "\(s.repliesCount ?? 0)",
            "url": s.url ?? "",
            "uri": s.uri ?? ""
        ]

        if let app = s.application?.name { data["via"] = app }
        if s.sensitive == true { data["sensitive"] = "true" }
        if let spoiler = s.spoilerText { data["spoiler"] = spoiler }

        var attachments: [WOMReference] = []
        if let media = s.mediaAttachments {
            for m in media {
                attachments.append(WOMReference(
                    id: m.url ?? m.previewUrl ?? m.id,
                    type: ["Media", m.type ?? "unknown"],
                    name: m.description
                ))
            }
        }

        let actorRef = WOMReference(
            id: "mastodon://\(instanceURL)/@\(s.account.acct)",
            type: ["wom:Person"],
            name: "@\(s.account.acct)",
            displayName: s.account.displayName.isEmpty ? nil : s.account.displayName
        )

        let authorRef = WOMReference(
            id: "mastodon://\(instanceURL)/@\(s.account.acct)",
            type: ["wom:RemoteIdentity", "wom:Person"],
            name: s.account.displayName.isEmpty ? s.account.acct : s.account.displayName,
            displayName: s.account.displayName.isEmpty ? nil : s.account.displayName
        )

        let visibility = s.visibility ?? "public"
        let sharing: String = visibility == "public"
            ? WOMSharing.public.rawValue
            : (visibility == "unlisted" ? WOMSharing.groupOnly.rawValue : WOMSharing.friendsOnly.rawValue)

        return WOMObject(
            id: "mastodon://\(instanceURL)/status/\(s.id)",
            type: ["wom:Post"],
            createdAt: s.parsedDate ?? Date(),
            schema: WOMSchema.post,
            attributedTo: authorRef,
            content: WOMContent(
                format: "text/html",
                text: plainText,
                language: s.language
            ),
            data: data,
            provenance: .remotePeer(
                source: WOMReference(id: instanceURL, type: ["mastodon:Instance"]),
                actor: actorRef,
                createdAt: s.parsedDate ?? Date()
            ),
            governance: WOMGovernance(
                purpose: ["messaging", "curation"],
                adsUse: WOMAdsUse.notAllowed.rawValue,
                agentUse: "allowed",
                sharing: sharing,
                retention: "forever"
            ),
            classification: WOMClassification(
                semanticType: "social.post",
                dataSubject: "remote_peer",
                origin: WOMOrigin.remotePeer.rawValue,
                sensitivity: visibility == "public"
                    ? WOMDataSensitivity.public.rawValue
                    : WOMDataSensitivity.personal.rawValue,
                category: WOMCategory(scheme: "wom.social.protocol", value: "mastodon")
            ),
            bindings: WOMBindings(activitypub: WOMActivityPubBinding(
                id: s.uri,
                actor: "mastodon://\(instanceURL)/@\(s.account.acct)"
            )),
            attachments: attachments
        )
    }

    private func convertReblog(status: MastodonStatus, reblog: MastodonReblog) -> WOMObject {
        let plainText = reblog.content.map { stripHTML($0) } ?? ""

        var data: [String: String] = [
            "network": "mastodon",
            "instance": instanceURL,
            "statusId": status.id,
            "visibility": "public",
            "isBoost": "true",
            "boostedBy": status.account.acct,
            "boostedByDisplayName": status.account.displayName,
            "originalId": reblog.id ?? "",
            "url": reblog.url ?? ""
        ]

        if let date = reblog.createdAt.flatMap({ MastodonToWOMAdapter.parseMastodonDate($0) }) {
            data["originalDate"] = MastodonToWOMAdapter.isoFormatter.string(from: date)
        }

        var attachments: [WOMReference] = []
        if let media = reblog.mediaAttachments {
            for m in media {
                attachments.append(WOMReference(
                    id: m.url ?? m.previewUrl ?? m.id,
                    type: ["Media"],
                    name: m.description
                ))
            }
        }

        let author = reblog.account

        let actorRef = WOMReference(
            id: "mastodon://\(instanceURL)/@\(status.account.acct)",
            type: ["wom:Person"],
            name: "@\(status.account.acct)",
            displayName: status.account.displayName.isEmpty ? nil : status.account.displayName
        )

        let authorRef = WOMReference(
            id: author.map { "mastodon://\(instanceURL)/@\($0.acct)" } ?? "unknown",
            type: ["wom:RemoteIdentity"],
            name: author.map { $0.displayName.isEmpty ? "@\($0.acct)" : $0.displayName },
            displayName: author?.displayName
        )

        return WOMObject(
            id: "mastodon://\(instanceURL)/status/\(status.id)",
            type: ["wom:Post", "wom:Boost"],
            createdAt: status.parsedDate ?? Date(),
            schema: WOMSchema.post,
            attributedTo: authorRef,
            content: WOMContent(
                format: "text/html",
                text: plainText,
                language: status.language
            ),
            data: data,
            provenance: .remotePeer(
                source: WOMReference(id: instanceURL, type: ["mastodon:Instance"]),
                actor: actorRef,
                createdAt: status.parsedDate ?? Date()
            ),
            governance: WOMGovernance(
                purpose: ["curation"],
                adsUse: WOMAdsUse.notAllowed.rawValue,
                agentUse: "allowed",
                sharing: WOMSharing.public.rawValue,
                retention: "forever"
            ),
            classification: WOMClassification(
                semanticType: "social.boost",
                dataSubject: "remote_peer",
                origin: WOMOrigin.remotePeer.rawValue,
                sensitivity: WOMDataSensitivity.public.rawValue,
                category: WOMCategory(scheme: "wom.social.protocol", value: "mastodon")
            ),
            bindings: WOMBindings(activitypub: WOMActivityPubBinding(
                id: reblog.url ?? status.uri,
                actor: author.map { "mastodon://\(instanceURL)/@\($0.acct)" }
            )),
            attachments: attachments
        )
    }

    // MARK: - Helpers

    private func stripHTML(_ html: String) -> String {
        guard let data = html.data(using: .utf8) else { return html }
        if let plain = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html],
            documentAttributes: nil
        ).string {
            return plain.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Fallback: strip tags manually
        return html.replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

}

extension MastodonToWOMAdapter {
    nonisolated(unsafe) static let dateFormatters: [DateFormatter] = {
        let fmts = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSZ",
        ]
        return fmts.map { fmt in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = fmt
            return f
        }
    }()

    nonisolated(unsafe) static let isoFormatter = ISO8601DateFormatter()

    static func parseMastodonDate(_ s: String) -> Date? {
        for fmt in dateFormatters {
            if let d = fmt.date(from: s) { return d }
        }
        return isoFormatter.date(from: s)
    }
}
