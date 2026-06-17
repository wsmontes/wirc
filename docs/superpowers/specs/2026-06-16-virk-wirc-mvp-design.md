# Virk/WIRC — MVP Design Spec

**Date:** 2026-06-16
**Status:** Approved
**Target:** iOS 17+, SwiftUI, Xcode project

## Overview

Virk (aka WIRC, Fala Virk) is a local-first, open-source, multi-protocol social client. The MVP implements an IRC client whose events are translated into WOM (Wawa Object Model) objects before reaching the UI. The architecture treats IRC as the first transport adapter, not the whole product.

### Core Thesis

Current social networks aren't true social networks; they're centralized media platforms using human relationships as raw material. Virk returns curation to human relationships, using open protocols as transport and WOM as the common semantic model.

### MVP Goal

Prove four things:
1. App connects to an IRC server
2. App sends and receives IRC messages
3. Incoming IRC events are converted to WOM objects
4. UI renders WOM objects, not raw IRC events

**MVP focus is the Chat tab** — IRC channels and DMs as `wom:Message`. The Feed tab exists as a placeholder for future protocols (Mastodon, Bluesky) that natively produce `wom:Post`. IRC is a messaging protocol, not a posting protocol.

## Architecture

### Runtime Data Flow

```
IRC Server ──TCP/TLS──▶ IRCClient ──IRCEvent──▶ IRCToWOMAdapter ──[WOMObject]──▶ WOMStore ──▶ UI
                                                                                    ▲
UI ──WOM intent──▶ WOMToIRCAdapter ──IRC command──▶ IRCClient ──▶ IRC Server      │
                                                                                    │
                                          (sent message saved locally) ────────────┘
```

### Central State: AppState

Single `@Observable` class injected via SwiftUI environment:
- Owns `WOMStore` instance (InMemoryWOMStore first, JSONFileStore later)
- Manages `IRCClient` instances per server (dictionary keyed by server ID)
- Exposes `var feedObjects: [WOMObject]` — all objects sorted by createdAt descending
- Exposes `func messagesForChannel(server:channel:) -> [WOMObject]`
- Handles send flow: WOM intent → adapter → IRC command → save local WOM object

### Layer Isolation

| Layer | Folder | Responsibility | Does NOT know |
|-------|--------|---------------|---------------|
| WOM Core | `Core/WOM/` | Pure Codable models, no external dependencies | IRC, UI, any framework |
| Social Core | `Core/Social/` | Future Signal, TrustRelation, RemoteIdentity types | Feed algorithm (MVP) |
| IRC Infra | `Infrastructure/IRC/` | TCP/TLS, IRC protocol parsing, IRC events | WOM |
| Adapters | `Infrastructure/IRC/` | Translate IRC ↔ WOM | Network I/O |
| Persistence | `Infrastructure/Persistence/` | WOMStore protocol + implementations | IRC, UI |
| Features | `Features/` | SwiftUI views + AppState | Protocol logic |
| App | `App/` | @main entry, TabView bootstrap | As little as possible |

## UI Design

### Navigation

Simple tab bar with three tabs:
1. **Chat** (bubble icon) — primary functional tab. Conversation list (channels + DMs), push to message view
2. **Feed** (house icon) — placeholder. Will render `wom:Post` cards when posting protocols are added. MVP shows empty state.
3. **Settings** (gear icon) — server management, with a discreet debug entry point

### View Tree

```
TabView
├── ChatView (tab 1 — primary)
│   ├── ConversationListView (channels + DMs grouped by server)
│   └── Push → MessageView
│       ├── ScrollView of message bubbles
│       └── TextField + send button
├── FeedView (tab 2 — placeholder)
│   └── Empty state: "Posts from people you follow will appear here."
│       Future: ScrollView of FeedCard rendering wom:Post objects
└── SettingsView (tab 3)
    ├── List of configured servers
    ├── AddServerView (sheet)
    └── DebugView (discreet link at bottom)
        ├── RawEventLogView — raw IRC lines
        └── WOMObjectInspectorView — JSON of generated WOM object
```

### Design Principles
- **Non-technical feel**: A child should be able to use it. No IRC jargon in primary UI.
- **Chronological only**: No algorithmic curation in MVP. Pure time-ordered feed.
- **Cards**: Each WOMObject renders as a card showing content, author, origin network, time.
- **IRC as source**: Feed content comes from IRC channel messages (wom:Post + wom:Message).

### Receive Flow (detailed)
1. IRCClient reads raw line from socket
2. IRCParser produces IRCEvent.message(IRCMessage)
3. IRCToWOMAdapter.convert(event, config) → [WOMObject]
4. AppState saves to WOMStore → UI updates reactively
5. FeedView shows new card; ChatView shows new message if viewing that channel

### Send Flow (detailed)
1. User types in MessageView, taps send
2. View calls appState.sendMessage(text:channel:server:)
3. AppState creates WOMObject with type ["wom:Message"] and content
4. WOMToIRCAdapter.convert(womObject) → "PRIVMSG #channel :text"
5. IRCClient sends the command
6. AppState saves WOMObject locally → UI reflects sent message

## Folder Structure

```
Virk/
├── VirkApp/
│   ├── App/
│   │   ├── VirkApp.swift              // @main + TabView
│   │   └── AppState.swift             // @Observable central state
│   ├── Core/
│   │   ├── WOM/
│   │   │   ├── WOMObject.swift
│   │   │   ├── WOMContent.swift
│   │   │   ├── WOMReference.swift
│   │   │   ├── WOMRelation.swift
│   │   │   ├── WOMProvenance.swift
│   │   │   └── WOMIDGenerator.swift
│   │   └── Social/
│   │       ├── SocialSignal.swift
│   │       ├── TrustRelation.swift
│   │       └── RemoteIdentity.swift
│   ├── Infrastructure/
│   │   ├── IRC/
│   │   │   ├── IRCClient.swift
│   │   │   ├── IRCConnectionConfig.swift
│   │   │   ├── IRCMessage.swift
│   │   │   ├── IRCParser.swift
│   │   │   ├── IRCEvent.swift
│   │   │   ├── IRCToWOMAdapter.swift
│   │   │   └── WOMToIRCAdapter.swift
│   │   └── Persistence/
│   │       ├── WOMStore.swift          // protocol
│   │       ├── InMemoryWOMStore.swift
│   │       └── JSONFileStore.swift
│   └── Features/
│       ├── Feed/
│       │   ├── FeedView.swift
│       │   └── FeedCard.swift
│       ├── Chat/
│       │   ├── ChatView.swift
│       │   ├── ConversationListView.swift
│       │   └── MessageView.swift
│       ├── Settings/
│       │   ├── SettingsView.swift
│       │   └── AddServerView.swift
│       └── Debug/
│           ├── DebugView.swift
│           ├── RawEventLogView.swift
│           └── WOMObjectInspectorView.swift
```

## WOM Core (Minimum)

### WOMObject
```swift
struct WOMObject: Codable, Identifiable, Equatable {
    let wom: String           // "0.1"
    let id: String            // "urn:wom:object:..."
    var type: [String]        // ["wom:Message", "wom:Post"]
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
    var data: [String: String]   // Simple key-value for MVP
}
```

### Supporting Types
- **WOMContent**: `{ format: String, text: String? }`
- **WOMReference**: `{ id: String, type: [String]?, name: String? }`
- **WOMRelation**: `{ id: String?, type: String, subject: String?, object: String, createdAt: Date?, confidence: Double?, provenance: WOMProvenance? }`
- **WOMProvenance**: `{ origin: String, actor: WOMReference?, source: WOMReference?, createdAt: Date?, confidence: Double?, reviewStatus: String? }`

### WOM Types for MVP
- `wom:Message` — a chat message (channel or DM)
- `wom:Post` — a public post (channel message also gets this type)
- `wom:RemoteIdentity` — an external person/account
- `wom:TransportEnvelope` — wrapper for raw transport events

### Future WOM Types (defined but not functional in MVP)
- `wom:Signal`, `wom:Reaction`, `wom:Recommendation`, `wom:Profile`, `wom:TrustRelation`, `wom:AttentionPolicy`, `wom:FeedItem`, `wom:ExternalObject`

## IRC Client

### IRCConnectionConfig
```swift
struct IRCConnectionConfig: Codable, Identifiable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var useTLS: Bool
    var nickname: String
    var username: String?
    var realName: String?
    var password: String?
    var autoJoinChannels: [String]
}
```

### IRCClient
Responsibilities: open TCP/TLS connection, authenticate NICK/USER, send IRC commands, join channels, send messages, receive raw lines, emit IRCEvent stream.

Uses `NWConnection` (Network framework) for socket I/O.

Does NOT know about WOM.

### IRCEvent
```swift
enum IRCEvent {
    case connected
    case disconnected
    case rawLine(String)
    case message(IRCMessage)
    case notice(IRCMessage)
    case join(channel: String, nick: String)
    case part(channel: String, nick: String, reason: String?)
    case topic(channel: String, topic: String)
    case names(channel: String, names: [String])
    case error(String)
}
```

### IRCMessage
```swift
struct IRCMessage: Codable, Equatable {
    var server: String
    var channel: String?
    var senderNick: String
    var senderHostmask: String?
    var text: String
    var receivedAt: Date
    var raw: String?
}
```

## Adapters

### IRCToWOMAdapter
Pure function where possible: IRCEvent in → [WOMObject] out.

Channel message → type ["wom:Message"], attributedTo with irc:// URI, data with network/server/channel/nick, provenance with origin "remotePeer".

Private message → type ["wom:Message"], data.visibility "direct".

IRC does NOT produce `wom:Post` — posts come from posting-oriented protocols (Mastodon, Bluesky, etc.) added in the future.

Join/part → wom:TransportEnvelope (debug only, not in main feed).

### WOMToIRCAdapter
WOM intent → IRC command string. MVP supports only PRIVMSG.

Input: WOMObject with type ["wom:Message"], content.text, data.channel.
Output: `PRIVMSG #channel :text`

Also handles saving the sent message as a local WOMObject.

## Persistence

### WOMStore Protocol
```swift
protocol WOMStore {
    func save(_ object: WOMObject) async throws
    func saveMany(_ objects: [WOMObject]) async throws
    func get(id: String) async throws -> WOMObject?
    func list(type: String?) async throws -> [WOMObject]
    func delete(id: String) async throws
}
```

### Implementations (in order)
1. **InMemoryWOMStore** — Dictionary-backed, for prototyping and tests
2. **JSONFileStore** — Simple file-based persistence, Codable to disk

SwiftData/SQLite deferred until after flow validation.

## MVP Scope Boundaries

### Included
- iOS SwiftUI app (iOS 17+)
- Standard .xcodeproj
- WOM Core models (Codable structs)
- InMemoryWOMStore
- IRCClient with NWConnection
- IRCParser for PRIVMSG, NOTICE, JOIN, PART, PING/PONG
- IRCToWOMAdapter and WOMToIRCAdapter
- Feed tab (chronological cards from IRC channel messages)
- Chat tab (conversation list + message view)
- Settings tab (server config + debug entry)
- Debug views (raw IRC log, WOM JSON inspector)
- Local persistence of WOM objects

### Explicitly Excluded
- Mastodon, Bluesky, Nostr, ActivityPub
- DID signatures, Verifiable Credentials
- Complex social feed with trust algorithms
- Media uploads
- Push notifications
- Own server
- Cross-device sync
- Automatic cross-network bridging
- SwiftData or SQLite (deferred)
- Functional Signal/TrustRelation (types only)

## Implementation Phases

1. **WOM Core** — Models, ID generator, in-memory store
2. **IRC Core** — Config, client, parser, connection
3. **Adapters** — IRC→WOM, WOM→IRC, store integration
4. **UI** — Chat (functional), Feed (placeholder), Settings, Debug views + AppState wiring
5. **Social prep** — Define Signal, TrustRelation, RemoteIdentity types (no behavior)

## Success Criteria

The skeleton is correct when you can:
1. Open the app
2. Configure an IRC server
3. Connect
4. Join a channel
5. Receive messages
6. See messages rendered in the Chat message view as bubbles
7. Inspect the WOM object generated for each message
8. Send a message
9. See the sent message also as a WOM object
10. Close and reopen the app with local history preserved

## Key Design Rules

- **Never mix protocol with domain**: Views render WOMObject, never IRCMessage directly
- **No own server**: MVP uses existing IRC servers only
- **No cross-posting**: Receive → Convert → Store → Render only. No automatic republishing
- **Preserve raw events**: WOMObject.data preserves the raw reference for debugging
- **Design for export**: Store data in a way compatible with future WOM Bundle export
