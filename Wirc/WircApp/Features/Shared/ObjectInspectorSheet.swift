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
