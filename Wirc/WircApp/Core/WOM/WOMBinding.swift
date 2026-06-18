import Foundation

// MARK: - WOM 0.6 Transport Bindings (§16)

/// Transport-agnostic bindings per WOM 0.6 §16.
/// Records where/how the object exists in other protocols without
/// contaminating the Core.
struct WOMBindings: Codable, Equatable {
    var irc: WOMIRCBinding?
    var atproto: WOMATProtoBinding?
    var email: WOMEmailBinding?
    var nostr: WOMNostrBinding?
    var activitypub: WOMActivityPubBinding?
    var didcomm: WOMDIDCommBinding?
    var mcp: WOMMCPBinding?
    var ninjs: WOMNinjsBinding?
    var newsmlg2: WOMNewsMLG2Binding?
    var bibreame: WOMBIBFRAMEBinding?
}

struct WOMIRCBinding: Codable, Equatable {
    var server: String?
    var channel: String?
    var nick: String?
}

struct WOMATProtoBinding: Codable, Equatable {
    var uri: String?
    var cid: String?
}

struct WOMEmailBinding: Codable, Equatable {
    var messageId: String?
    var from: String?
}

struct WOMNostrBinding: Codable, Equatable {
    var eventId: String?
    var pubkey: String?
    var relay: String?
}

struct WOMActivityPubBinding: Codable, Equatable {
    var id: String?
    var actor: String?
    var inbox: String?
}

struct WOMDIDCommBinding: Codable, Equatable {
    var messageId: String?
    var threadId: String?
}

struct WOMMCPBinding: Codable, Equatable {
    var server: String?
    var resource: String?
}

struct WOMNinjsBinding: Codable, Equatable {
    var version: String?    // "3.x"
    var exportable: Bool?
}

struct WOMNewsMLG2Binding: Codable, Equatable {
    var exportable: Bool?
}

struct WOMBIBFRAMEBinding: Codable, Equatable {
    var workId: String?
    var instanceId: String?
    var itemId: String?
}
