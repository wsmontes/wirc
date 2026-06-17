import Foundation

struct WOMObject: Codable, Identifiable, Equatable {
    let wom: String             // "0.1"
    let id: String
    var type: [String]          // ["wom:Message"]
    var schema: String?
    var context: [String]?
    var name: String?
    var summary: String?
    var createdAt: Date
    var updatedAt: Date?
    var attributedTo: WOMReference?
    var content: WOMContent?
    var relationships: [WOMRelation]
    var attachments: [WOMReference]
    var provenance: WOMProvenance?
    var revision: [String: String]?
    var proof: [String: String]?
    var data: [String: String]

    init(
        id: String,
        type: [String],
        createdAt: Date = Date(),
        attributedTo: WOMReference? = nil,
        content: WOMContent? = nil,
        data: [String: String] = [:],
        provenance: WOMProvenance? = nil
    ) {
        self.wom = "0.1"
        self.id = id
        self.type = type
        self.createdAt = createdAt
        self.attributedTo = attributedTo
        self.content = content
        self.data = data
        self.provenance = provenance
        self.relationships = []
        self.attachments = []
        self.schema = nil
        self.context = nil
        self.name = nil
        self.summary = nil
        self.updatedAt = nil
        self.revision = nil
        self.proof = nil
    }
}
