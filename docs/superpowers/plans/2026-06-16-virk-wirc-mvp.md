# Virk/WIRC MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Virk/WIRC iOS SwiftUI MVP — an IRC client that translates IRC events into WOM objects before rendering, with Chat (functional), Feed (placeholder), Settings, and Debug tabs.

**Architecture:** @Observable AppState owns InMemoryWOMStore and IRCClient instances. IRCClient uses NWConnection for TCP/TLS. IRCParser converts raw lines to IRCEvent. IRCToWOMAdapter converts IRCEvent to [WOMObject]. WOMToIRCAdapter converts WOM intents to IRC PRIVMSG commands. UI renders WOMObject, never raw IRC.

**Tech Stack:** Swift 5.9+, SwiftUI, iOS 17, NWConnection (Network framework), zero external dependencies, Codable persistence, UserDefaults for server configs.

## Global Constraints

- Target: iOS 17.0+
- No external SPM dependencies
- NWConnection for all socket I/O (no NSStream, no CocoaAsyncSocket, no SwiftNIO)
- @Observable macro (iOS 17) for state management
- Codable for all persistence (no NSCoding)
- Views render WOMObject; never IRCMessage or raw IRC directly
- IRC logic stays in Infrastructure/IRC; WOM stays in Core/WOM
- Xcode project: standard .xcodeproj named `Virk.xcodeproj`

---

### Task 1: Project scaffolding and directory structure

**Files:**
- Create: full directory tree under `Virk/VirkApp/`
- Create: `Virk/VirkApp/App/VirkApp.swift` (minimal @main stub)
- Create: `.gitignore`

**Interfaces:**
- Consumes: nothing
- Produces: directory structure all later tasks write into; VirkApp.swift entry point with empty WindowGroup

- [ ] **Step 1: Create directory tree**

```bash
mkdir -p Virk/VirkApp/App
mkdir -p Virk/VirkApp/Core/WOM
mkdir -p Virk/VirkApp/Core/Social
mkdir -p Virk/VirkApp/Infrastructure/IRC
mkdir -p Virk/VirkApp/Infrastructure/Persistence
mkdir -p Virk/VirkApp/Features/Feed
mkdir -p Virk/VirkApp/Features/Chat
mkdir -p Virk/VirkApp/Features/Settings
mkdir -p Virk/VirkApp/Features/Debug
```

- [ ] **Step 2: Create .gitignore**

Write `Virk/.gitignore`:
```
*.swp
*.xcuserdata
*.xcworkspace/xcuserdata
DerivedData/
build/
*.pbxuser
!default.pbxuser
*.mode1v3
!default.mode1v3
*.mode2v3
!default.mode2v3
*.perspectivev3
!default.perspectivev3
xcuserdata/
*.xccheckout
*.moved-aside
*.xcuserstate
*.DS_Store
```

- [ ] **Step 3: Create minimal VirkApp.swift stub**

Write `Virk/VirkApp/App/VirkApp.swift`:
```swift
import SwiftUI

@main
struct VirkApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Virk")
        }
    }
}
```

- [ ] **Step 4: Create Xcode project**

Open Xcode, File → New → Project → iOS → App. Name: "Virk". Interface: SwiftUI. Language: Swift. Minimum Deployment: iOS 17.0. Save inside the `Virk/` directory (so the .xcodeproj lives at `Virk/Virk.xcodeproj`). Delete the default `ContentView.swift` and `Assets.xcassets` if not needed. Add all created directories as groups (drag folders from Finder into Xcode project navigator, selecting "Create groups").

- [ ] **Step 5: Verify it builds**

In Xcode: Product → Build (⌘B). Expected: Build Succeeded.

---

### Task 2: WOM Core models

**Files:**
- Create: `Virk/VirkApp/Core/WOM/WOMObject.swift`
- Create: `Virk/VirkApp/Core/WOM/WOMContent.swift`
- Create: `Virk/VirkApp/Core/WOM/WOMReference.swift`
- Create: `Virk/VirkApp/Core/WOM/WOMRelation.swift`
- Create: `Virk/VirkApp/Core/WOM/WOMProvenance.swift`
- Create: `Virk/VirkApp/Core/WOM/WOMIDGenerator.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `WOMObject`, `WOMContent`, `WOMReference`, `WOMRelation`, `WOMProvenance` (all Codable, Equatable structs), `WOMIDGenerator.generate(type:) -> String`

- [ ] **Step 1: Write WOMContent.swift**

```swift
import Foundation

struct WOMContent: Codable, Equatable {
    var format: String      // "text/plain"
    var text: String?
}
```

- [ ] **Step 2: Write WOMReference.swift**

```swift
import Foundation

struct WOMReference: Codable, Equatable {
    var id: String
    var type: [String]?
    var name: String?
}
```

- [ ] **Step 3: Write WOMProvenance.swift**

```swift
import Foundation

struct WOMProvenance: Codable, Equatable {
    var origin: String          // "remotePeer", "localUser"
    var actor: WOMReference?
    var source: WOMReference?
    var createdAt: Date?
    var confidence: Double?
    var reviewStatus: String?   // "none", "verified", "rejected"
}
```

- [ ] **Step 4: Write WOMRelation.swift**

```swift
import Foundation

struct WOMRelation: Codable, Identifiable, Equatable {
    var id: String?
    var type: String            // "wom:references", "wom:trusts"
    var subject: String?
    var object: String
    var createdAt: Date?
    var confidence: Double?
    var provenance: WOMProvenance?
}
```

- [ ] **Step 5: Write WOMObject.swift**

```swift
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
```

- [ ] **Step 6: Write WOMIDGenerator.swift**

```swift
import Foundation

enum WOMIDGenerator {
    static func generate(type: String) -> String {
        let uuid = UUID().uuidString.lowercased()
        return "urn:wom:\(type):\(uuid)"
    }
}
```

- [ ] **Step 7: Build to verify compilation**

In Xcode: ⌘B. Expected: Build Succeeded.

---

### Task 3: WOMStore protocol and InMemoryWOMStore

**Files:**
- Create: `Virk/VirkApp/Infrastructure/Persistence/WOMStore.swift`
- Create: `Virk/VirkApp/Infrastructure/Persistence/InMemoryWOMStore.swift`

**Interfaces:**
- Consumes: `WOMObject` (Task 2)
- Produces: `protocol WOMStore` with `save`, `saveMany`, `get(id:)`, `list(type:)`, `delete(id:)`; `class InMemoryWOMStore: WOMStore`

- [ ] **Step 1: Write WOMStore protocol**

```swift
import Foundation

protocol WOMStore: AnyObject {
    func save(_ object: WOMObject) async throws
    func saveMany(_ objects: [WOMObject]) async throws
    func get(id: String) async throws -> WOMObject?
    func list(type: String?) async throws -> [WOMObject]
    func delete(id: String) async throws
    func all() async throws -> [WOMObject]
}
```

- [ ] **Step 2: Write InMemoryWOMStore**

```swift
import Foundation

final class InMemoryWOMStore: WOMStore {
    private var storage: [String: WOMObject] = [:]

    func save(_ object: WOMObject) async throws {
        storage[object.id] = object
    }

    func saveMany(_ objects: [WOMObject]) async throws {
        for obj in objects {
            storage[obj.id] = obj
        }
    }

    func get(id: String) async throws -> WOMObject? {
        return storage[id]
    }

    func list(type: String?) async throws -> [WOMObject] {
        let all = Array(storage.values)
        guard let type = type else { return all }
        return all.filter { $0.type.contains(type) }
    }

    func delete(id: String) async throws {
        storage.removeValue(forKey: id)
    }

    func all() async throws -> [WOMObject] {
        return Array(storage.values)
    }
}
```

- [ ] **Step 3: Build to verify**

⌘B. Expected: Build Succeeded.

---

### Task 4: IRC models — config, message, event

**Files:**
- Create: `Virk/VirkApp/Infrastructure/IRC/IRCConnectionConfig.swift`
- Create: `Virk/VirkApp/Infrastructure/IRC/IRCMessage.swift`
- Create: `Virk/VirkApp/Infrastructure/IRC/IRCEvent.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `IRCConnectionConfig` (Codable, Identifiable), `IRCMessage` (Codable, Equatable), `IRCEvent` enum

- [ ] **Step 1: Write IRCConnectionConfig.swift**

```swift
import Foundation

struct IRCConnectionConfig: Codable, Identifiable, Equatable {
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

    init(
        id: UUID = UUID(),
        name: String = "",
        host: String = "",
        port: Int = 6667,
        useTLS: Bool = false,
        nickname: String = "",
        username: String? = nil,
        realName: String? = nil,
        password: String? = nil,
        autoJoinChannels: [String] = []
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.nickname = nickname
        self.username = username
        self.realName = realName
        self.password = password
        self.autoJoinChannels = autoJoinChannels
    }
}
```

- [ ] **Step 2: Write IRCMessage.swift**

```swift
import Foundation

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

- [ ] **Step 3: Write IRCEvent.swift**

```swift
import Foundation

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

- [ ] **Step 4: Build to verify**

⌘B. Expected: Build Succeeded.

---

### Task 5: IRCParser — raw IRC line parser

**Files:**
- Create: `Virk/VirkApp/Infrastructure/IRC/IRCParser.swift`

**Interfaces:**
- Consumes: `IRCEvent`, `IRCMessage` (Task 4)
- Produces: `enum IRCParser` with `static func parse(rawLine: String, server: String) -> IRCEvent`

- [ ] **Step 1: Write IRCParser.swift**

```swift
import Foundation

enum IRCParser {
    /// Parse a raw IRC line into an IRCEvent.
    /// Format: `[:prefix] COMMAND [params] [:trailing]`
    static func parse(rawLine: String, server: String) -> IRCEvent {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

        // PING is special — no prefix
        if line.hasPrefix("PING") {
            return .rawLine(line)
        }

        var prefix: String?
        if line.hasPrefix(":") {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            prefix = String(parts[0].dropFirst())
            if parts.count > 1 {
                line = String(parts[1])
            } else {
                line = ""
            }
        }

        let command: String
        var paramsPart: String
        if let spaceIdx = line.firstIndex(of: " ") {
            command = String(line[..<spaceIdx]).uppercased()
            paramsPart = String(line[line.index(after: spaceIdx)...])
        } else {
            command = line.uppercased()
            paramsPart = ""
        }

        // Extract trailing parameter (after " :")
        var params: [String] = []
        var trailing: String?
        if let trailingRange = paramsPart.range(of: " :") {
            let beforeTrailing = String(paramsPart[..<trailingRange.lowerBound])
            params = beforeTrailing.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            let trailingStart = paramsPart.index(trailingRange.lowerBound, offsetBy: 2)
            trailing = String(paramsPart[trailingStart...])
        } else {
            params = paramsPart.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        }

        // Extract nick and hostmask from prefix (nick!user@host)
        var senderNick: String?
        var senderHostmask: String?
        if let pfx = prefix {
            if let exclamationIdx = pfx.firstIndex(of: "!") {
                senderNick = String(pfx[..<exclamationIdx])
                senderHostmask = String(pfx[pfx.index(after: exclamationIdx)...])
            } else {
                senderNick = pfx
            }
        }

        switch command {
        case "PRIVMSG":
            let target = params.first ?? ""
            let isChannel = target.hasPrefix("#") || target.hasPrefix("&")
            let msg = IRCMessage(
                server: server,
                channel: isChannel ? target : nil,
                senderNick: senderNick ?? "unknown",
                senderHostmask: senderHostmask,
                text: trailing ?? "",
                receivedAt: Date(),
                raw: rawLine
            )
            return .message(msg)

        case "NOTICE":
            let msg = IRCMessage(
                server: server,
                channel: nil,
                senderNick: senderNick ?? "server",
                senderHostmask: senderHostmask,
                text: trailing ?? "",
                receivedAt: Date(),
                raw: rawLine
            )
            return .notice(msg)

        case "JOIN":
            let channel = trailing ?? params.first ?? ""
            return .join(channel: channel, nick: senderNick ?? "unknown")

        case "PART":
            let channel = params.first ?? ""
            return .part(channel: channel, nick: senderNick ?? "unknown", reason: trailing)

        case "TOPIC":
            let channel = params.first ?? ""
            return .topic(channel: channel, topic: trailing ?? "")

        case "353": // NAMREPLY
            if let namesStr = trailing {
                let names = namesStr.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                // params are: ourNick = "@" channel :names; channel is params[2] or params[1] depending
                let channel = params.count >= 2 ? params[params.count - 1] : ""
                return .names(channel: channel, names: names)
            }
            return .rawLine(rawLine)

        case "366": // ENDOFNAMES
            return .rawLine(rawLine)

        case "PONG":
            return .rawLine(rawLine)

        case "ERROR":
            return .error(trailing ?? rawLine)

        default:
            // Numeric replies and unhandled commands go to rawLine for debug
            return .rawLine(rawLine)
        }
    }
}
```

- [ ] **Step 2: Build to verify**

⌘B. Expected: Build Succeeded.

---

### Task 6: IRCClient — NWConnection-based TCP client

**Files:**
- Create: `Virk/VirkApp/Infrastructure/IRC/IRCClient.swift`

**Interfaces:**
- Consumes: `IRCConnectionConfig` (Task 4), `IRCEvent`, `IRCParser` (Task 5)
- Produces: `final class IRCClient` with `init(config:)`, `func connect()`, `func disconnect()`, `func join(channel:)`, `func sendMessage(_:to:)`, `var onEvent: ((IRCEvent) -> Void)?`

- [ ] **Step 1: Write IRCClient.swift**

```swift
import Foundation
import Network

final class IRCClient {
    let config: IRCConnectionConfig
    var onEvent: ((IRCEvent) -> Void)?

    private var connection: NWConnection?
    private var state: ClientState = .disconnected
    private let queue = DispatchQueue(label: "irc.client")

    private var readBuffer: String = ""

    enum ClientState {
        case disconnected
        case connecting
        case registering
        case online
    }

    init(config: IRCConnectionConfig) {
        self.config = config
    }

    // MARK: - Connection

    func connect() {
        guard case .disconnected = state else { return }
        state = .connecting

        let host = NWEndpoint.Host(config.host)
        let port = NWEndpoint.Port(integerLiteral: UInt16(config.port))
        let params: NWParameters = config.useTLS ? .tls : .tcp
        params.allowLocalEndpointReuse = true

        connection = NWConnection(host: host, port: port, using: params)
        connection?.stateUpdateHandler = { [weak self] newState in
            self?.handleConnectionState(newState)
        }
        connection?.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        state = .disconnected
        onEvent?(.disconnected)
    }

    // MARK: - IRC Commands

    func join(channel: String) {
        sendRaw("JOIN \(channel)")
    }

    func sendMessage(_ text: String, to target: String) {
        sendRaw("PRIVMSG \(target) :\(text)")
    }

    // MARK: - Private

    private func sendRaw(_ command: String) {
        let line = command + "\r\n"
        guard let data = line.data(using: .utf8) else { return }
        connection?.send(content: data, completion: .contentProcessed({ _ in }))
    }

    private func handleConnectionState(_ nwState: NWConnection.State) {
        switch nwState {
        case .ready:
            state = .registering
            onEvent?(.connected)
            register()

        case .failed(let error):
            state = .disconnected
            onEvent?(.error("Connection failed: \(error.localizedDescription)"))
            onEvent?(.disconnected)

        case .cancelled:
            state = .disconnected

        default:
            break
        }
    }

    private func register() {
        if let pass = config.password, !pass.isEmpty {
            sendRaw("PASS \(pass)")
        }
        let nickname = config.nickname
        let username = config.username ?? nickname
        let realName = config.realName ?? nickname
        sendRaw("NICK \(nickname)")
        sendRaw("USER \(username) 0 * :\(realName)")
    }

    private func startReading() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            guard let self = self else { return }
            if let error = error {
                self.onEvent?(.error("Read error: \(error.localizedDescription)"))
                return
            }
            if let data = data, let text = String(data: data, encoding: .utf8) {
                self.readBuffer.append(text)
                self.processBuffer()
            }
            // Continue reading
            if self.state != .disconnected {
                self.startReading()
            }
        }
    }

    private func processBuffer() {
        while let crlfRange = readBuffer.range(of: "\r\n") {
            let line = String(readBuffer[..<crlfRange.lowerBound])
            readBuffer = String(readBuffer[crlfRange.upperBound...])

            // Handle PING
            if line.hasPrefix("PING") {
                let token = line.replacingOccurrences(of: "PING :", with: "").replacingOccurrences(of: "PING ", with: "")
                sendRaw("PONG :\(token)")
                onEvent?(.rawLine(line))
                continue
            }

            // Detect registration completion (numeric 001 or end of MOTD 376/422)
            if line.contains(" 001 ") || line.contains(" 376 ") || line.contains(" 422 ") {
                if case .registering = state {
                    state = .online
                    for channel in config.autoJoinChannels {
                        join(channel: channel)
                    }
                }
            }

            let event = IRCParser.parse(rawLine: line, server: config.host)
            onEvent?(event)
        }
    }

    // Called after registration to begin the read loop
    private func beginReadLoop() {
        // The read loop is started via a callback after registration
        // We detect registration in processBuffer when 001/376/422 arrives
        // and transition to .online; reading starts immediately in startReading
    }

    // MARK: - Internal: called after state transitions to registering
    private func didConnect() {
        startReading()
    }
}

// Extend IRCClient to trigger read loop on connect
extension IRCClient {
    func connectAndRead() {
        let oldHandler = connection?.stateUpdateHandler
        connection?.stateUpdateHandler = { [weak self] newState in
            oldHandler?(newState)
            if case .ready = newState {
                self?.didConnect()
            }
        }
        connect()
    }

    // Override connect to use connectAndRead internally
    // Actually, let's simplify: just start reading after register
}
```

Wait — the above has a bug: `startReading()` is never called after `register()`. Let me fix this. After `register()` sends NICK/USER, we need to start the read loop. The server responds, and we parse responses.

Let me rewrite this file correctly.

- [ ] **Step 1 (revised): Write IRCClient.swift correctly**

```swift
import Foundation
import Network

final class IRCClient {
    let config: IRCConnectionConfig
    var onEvent: ((IRCEvent) -> Void)?

    private var connection: NWConnection?
    private var state: ClientState = .disconnected
    private let queue = DispatchQueue(label: "irc.client.\(UUID().uuidString.prefix(8))")
    private var readBuffer: String = ""

    enum ClientState {
        case disconnected
        case connecting
        case registering
        case online
    }

    // MARK: - Init

    init(config: IRCConnectionConfig) {
        self.config = config
    }

    // MARK: - Public API

    func connect() {
        guard case .disconnected = state else { return }
        state = .connecting

        let host = NWEndpoint.Host(config.host)
        let port = NWEndpoint.Port(integerLiteral: UInt16(config.port))
        let params: NWParameters = config.useTLS ? .tls : .tcp
        params.allowLocalEndpointReuse = true

        connection = NWConnection(host: host, port: port, using: params)
        connection?.stateUpdateHandler = { [weak self] nwState in
            DispatchQueue.main.async { self?.handleState(nwState) }
        }
        connection?.start(queue: queue)
    }

    func disconnect() {
        sendRaw("QUIT :Virk")
        connection?.cancel()
        connection = nil
        state = .disconnected
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(.disconnected)
        }
    }

    func join(channel: String) {
        sendRaw("JOIN \(channel)")
    }

    func sendMessage(_ text: String, to target: String) {
        sendRaw("PRIVMSG \(target) :\(text)")
    }

    // MARK: - Private: Networking

    private func sendRaw(_ command: String) {
        let line = command + "\r\n"
        guard let data = line.data(using: .utf8), let conn = connection else { return }
        conn.send(content: data, completion: .contentProcessed({ _ in }))
    }

    private func handleState(_ nwState: NWConnection.State) {
        switch nwState {
        case .ready:
            state = .registering
            onEvent?(.connected)
            register()
            startReading()

        case .failed(let error):
            state = .disconnected
            onEvent?(.error("Connection failed: \(error.localizedDescription)"))
            onEvent?(.disconnected)

        case .cancelled:
            state = .disconnected

        default:
            break
        }
    }

    // MARK: - Private: IRC Registration

    private func register() {
        if let pass = config.password, !pass.isEmpty {
            sendRaw("PASS \(pass)")
        }
        let nickname = config.nickname
        let username = config.username ?? nickname
        let realName = config.realName ?? nickname
        sendRaw("NICK \(nickname)")
        sendRaw("USER \(username) 0 * :\(realName)")
    }

    // MARK: - Private: Reading

    private func startReading() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.onEvent?(.error("Read error: \(error.localizedDescription)"))
                }
                return
            }

            if let data = data, let text = String(data: data, encoding: .utf8) {
                self.readBuffer.append(text)
                self.processBuffer()
            }

            if self.state != .disconnected {
                self.startReading()
            }
        }
    }

    private func processBuffer() {
        while let crlfRange = readBuffer.range(of: "\r\n") {
            let line = String(readBuffer[..<crlfRange.lowerBound])
            readBuffer = String(readBuffer[crlfRange.upperBound...])

            guard !line.isEmpty else { continue }

            // Handle PING
            if line.hasPrefix("PING") {
                let token = line
                    .replacingOccurrences(of: "PING :", with: "")
                    .replacingOccurrences(of: "PING ", with: "")
                sendRaw("PONG :\(token)")
                DispatchQueue.main.async { [weak self] in
                    self?.onEvent?(.rawLine(line))
                }
                continue
            }

            // Detect registration completion
            if line.contains(" 001 ") {
                if case .registering = state {
                    state = .online
                    for channel in config.autoJoinChannels {
                        join(channel: channel)
                    }
                }
            }

            let event = IRCParser.parse(rawLine: line, server: config.host)
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?(event)
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify**

⌘B. Expected: Build Succeeded.

---

### Task 7: IRCToWOMAdapter

**Files:**
- Create: `Virk/VirkApp/Infrastructure/IRC/IRCToWOMAdapter.swift`

**Interfaces:**
- Consumes: `IRCEvent`, `IRCMessage` (Task 4), `WOMObject`, `WOMContent`, `WOMReference`, `WOMProvenance`, `WOMIDGenerator` (Task 2), `IRCConnectionConfig` (Task 4)
- Produces: `final class IRCToWOMAdapter` with `func convert(_ event: IRCEvent, config: IRCConnectionConfig) -> [WOMObject]`

- [ ] **Step 1: Write IRCToWOMAdapter.swift**

```swift
import Foundation

final class IRCToWOMAdapter {

    func convert(_ event: IRCEvent, config: IRCConnectionConfig) -> [WOMObject] {
        switch event {
        case .message(let ircMsg):
            return [convertMessage(ircMsg, config: config)]

        case .notice(let ircMsg):
            return [convertNotice(ircMsg, config: config)]

        case .join(let channel, let nick):
            return [convertJoin(channel: channel, nick: nick, config: config)]

        case .part(let channel, let nick, let reason):
            return [convertPart(channel: channel, nick: nick, reason: reason, config: config)]

        case .topic(let channel, let topic):
            return [convertTopic(channel: channel, topic: topic, config: config)]

        case .names(let channel, let names):
            return [convertNames(channel: channel, names: names, config: config)]

        case .connected, .disconnected, .rawLine, .error:
            return []

        case .names:
            return []
        }
    }

    // MARK: - Message conversion

    private func convertMessage(_ ircMsg: IRCMessage, config: IRCConnectionConfig) -> WOMObject {
        let isChannel = ircMsg.channel != nil
        var types: [String] = ["wom:Message"]

        let objectId = WOMIDGenerator.generate(type: "message")

        var data: [String: String] = [
            "network": "irc",
            "server": config.host,
            "nick": ircMsg.senderNick
        ]

        if isChannel {
            data["channel"] = ircMsg.channel ?? ""
            data["visibility"] = "channel"
        } else {
            data["visibility"] = "direct"
        }

        if let raw = ircMsg.raw {
            data["raw"] = raw
        }

        let attributedToId = "irc://\(config.host)/\(ircMsg.senderNick)"

        return WOMObject(
            id: objectId,
            type: types,
            createdAt: ircMsg.receivedAt,
            attributedTo: WOMReference(
                id: attributedToId,
                type: ["wom:RemoteIdentity"],
                name: ircMsg.senderNick
            ),
            content: WOMContent(
                format: "text/plain",
                text: ircMsg.text
            ),
            data: data,
            provenance: WOMProvenance(
                origin: "remotePeer",
                source: WOMReference(
                    id: isChannel
                        ? "irc://\(config.host)/\(ircMsg.channel?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")"
                        : "irc://\(config.host)",
                    type: isChannel ? ["irc:Channel"] : ["irc:Server"]
                ),
                createdAt: ircMsg.receivedAt,
                confidence: 1.0,
                reviewStatus: "none"
            )
        )
    }

    // MARK: - Notice, Join, Part, Topic, Names

    private func convertNotice(_ ircMsg: IRCMessage, config: IRCConnectionConfig) -> WOMObject {
        return WOMObject(
            id: WOMIDGenerator.generate(type: "transport-envelope"),
            type: ["wom:TransportEnvelope"],
            createdAt: ircMsg.receivedAt,
            content: WOMContent(format: "text/plain", text: ircMsg.text),
            data: [
                "network": "irc",
                "server": config.host,
                "event": "notice",
                "nick": ircMsg.senderNick,
                "raw": ircMsg.raw ?? ""
            ]
        )
    }

    private func convertJoin(channel: String, nick: String, config: IRCConnectionConfig) -> WOMObject {
        return WOMObject(
            id: WOMIDGenerator.generate(type: "transport-envelope"),
            type: ["wom:TransportEnvelope"],
            createdAt: Date(),
            data: [
                "network": "irc",
                "server": config.host,
                "event": "join",
                "channel": channel,
                "nick": nick
            ]
        )
    }

    private func convertPart(channel: String, nick: String, reason: String?, config: IRCConnectionConfig) -> WOMObject {
        var data: [String: String] = [
            "network": "irc",
            "server": config.host,
            "event": "part",
            "channel": channel,
            "nick": nick
        ]
        if let reason = reason { data["reason"] = reason }
        return WOMObject(
            id: WOMIDGenerator.generate(type: "transport-envelope"),
            type: ["wom:TransportEnvelope"],
            createdAt: Date(),
            data: data
        )
    }

    private func convertTopic(channel: String, topic: String, config: IRCConnectionConfig) -> WOMObject {
        return WOMObject(
            id: WOMIDGenerator.generate(type: "transport-envelope"),
            type: ["wom:TransportEnvelope"],
            createdAt: Date(),
            data: [
                "network": "irc",
                "server": config.host,
                "event": "topic",
                "channel": channel,
                "topic": topic
            ]
        )
    }

    private func convertNames(channel: String, names: [String], config: IRCConnectionConfig) -> WOMObject {
        return WOMObject(
            id: WOMIDGenerator.generate(type: "transport-envelope"),
            type: ["wom:TransportEnvelope"],
            createdAt: Date(),
            data: [
                "network": "irc",
                "server": config.host,
                "channel": channel,
                "names": names.joined(separator: ",")
            ]
        )
    }
}
```

- [ ] **Step 2: Build to verify**

⌘B. Expected: Build Succeeded.

---

### Task 8: WOMToIRCAdapter

**Files:**
- Create: `Virk/VirkApp/Infrastructure/IRC/WOMToIRCAdapter.swift`

**Interfaces:**
- Consumes: `WOMObject`, `WOMContent` (Task 2)
- Produces: `enum WOMToIRCAdapter` with `static func convertToIRC(_ object: WOMObject) -> String?`

- [ ] **Step 1: Write WOMToIRCAdapter.swift**

```swift
import Foundation

enum WOMToIRCAdapter {
    /// Convert a WOM message intent into an IRC PRIVMSG command.
    /// Returns nil if the object is not a sendable message.
    static func convertToIRC(_ object: WOMObject) -> String? {
        guard object.type.contains("wom:Message") else { return nil }
        guard let content = object.content, let text = content.text, !text.isEmpty else { return nil }

        let channel = object.data["channel"] ?? ""
        let recipient = object.data["recipient"] ?? ""

        let target: String
        if !channel.isEmpty {
            target = channel
        } else if !recipient.isEmpty {
            target = recipient
        } else {
            return nil
        }

        return "PRIVMSG \(target) :\(text)"
    }
}
```

- [ ] **Step 2: Build to verify**

⌘B. Expected: Build Succeeded.

---

### Task 9: AppState — central @Observable state

**Files:**
- Create: `Virk/VirkApp/App/AppState.swift`

**Interfaces:**
- Consumes: `WOMObject`, `WOMIDGenerator` (Task 2), `WOMStore`, `InMemoryWOMStore` (Task 3), `IRCConnectionConfig`, `IRCEvent` (Task 4), `IRCClient` (Task 6), `IRCToWOMAdapter` (Task 7), `WOMToIRCAdapter` (Task 8)
- Produces: `@Observable final class AppState` with `servers`, `store`, `clients`, `connect(to:)`, `disconnect(from:)`, `join(channel:serverId:)`, `sendMessage(_:channel:serverId:)`, `messagesFor(server:channel:)`, `feedObjects`, `rawEvents`, `womObjects`

- [ ] **Step 1: Write AppState.swift**

```swift
import SwiftUI
import Observation

@Observable
final class AppState {
    // MARK: - Server configs (persisted in UserDefaults)
    var servers: [IRCConnectionConfig] = [] {
        didSet { saveServers() }
    }

    // MARK: - WOM Store
    let store: WOMStore = InMemoryWOMStore()

    // MARK: - IRC Clients (keyed by server id)
    private var clients: [UUID: IRCClient] = [:]

    // MARK: - Connection status
    var connectionStates: [UUID: ConnectionStatus] = [:]

    // MARK: - Debug logs
    var rawEvents: [DebugRawEvent] = []
    var womObjects: [WOMObject] = []

    // MARK: - Adapters
    private let ircToWOM = IRCToWOMAdapter()

    enum ConnectionStatus {
        case disconnected
        case connecting
        case online
    }

    struct DebugRawEvent: Identifiable {
        let id = UUID()
        let timestamp: Date
        let server: String
        let raw: String
        let parsedAs: String
    }

    // MARK: - Init

    init() {
        loadServers()
    }

    // MARK: - Server persistence

    private let serversKey = "virk.servers"

    private func saveServers() {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        UserDefaults.standard.set(data, forKey: serversKey)
    }

    private func loadServers() {
        guard let data = UserDefaults.standard.data(forKey: serversKey),
              let saved = try? JSONDecoder().decode([IRCConnectionConfig].self, from: data) else {
            return
        }
        servers = saved
    }

    // MARK: - Connection management

    func connect(to configId: UUID) {
        guard let config = servers.first(where: { $0.id == configId }) else { return }
        connectionStates[configId] = .connecting

        let client = IRCClient(config: config)
        clients[configId] = client

        client.onEvent = { [weak self] event in
            self?.handleEvent(event, serverId: configId)
        }

        client.connect()
    }

    func disconnect(from configId: UUID) {
        clients[configId]?.disconnect()
        clients[configId] = nil
        connectionStates[configId] = .disconnected
    }

    // MARK: - Channel / Message

    func join(channel: String, serverId: UUID) {
        clients[serverId]?.join(channel: channel)
    }

    func sendMessage(_ text: String, channel: String, serverId: UUID) {
        guard let config = servers.first(where: { $0.id == serverId }) else { return }

        // Build WOM intent
        let objectId = WOMIDGenerator.generate(type: "message")
        let womObj = WOMObject(
            id: objectId,
            type: ["wom:Message"],
            createdAt: Date(),
            attributedTo: WOMReference(
                id: "local:user",
                type: ["wom:Person"],
                name: config.nickname
            ),
            content: WOMContent(format: "text/plain", text: text),
            data: [
                "network": "irc",
                "server": config.host,
                "channel": channel
            ],
            provenance: WOMProvenance(
                origin: "localUser",
                createdAt: Date(),
                confidence: 1.0,
                reviewStatus: "none"
            )
        )

        // Convert to IRC and send
        if let command = WOMToIRCAdapter.convertToIRC(womObj) {
            clients[serverId]?.sendMessage(text, to: channel)
        }

        // Save locally
        Task {
            try? await store.save(womObj)
            await MainActor.run {
                womObjects.append(womObj)
            }
        }
    }

    // MARK: - Event handling

    private func handleEvent(_ event: IRCEvent, serverId: UUID) {
        guard let config = servers.first(where: { $0.id == serverId }) else { return }

        switch event {
        case .connected:
            connectionStates[serverId] = .online

        case .disconnected:
            connectionStates[serverId] = .disconnected

        case .rawLine(let line):
            rawEvents.append(DebugRawEvent(
                timestamp: Date(),
                server: config.host,
                raw: line,
                parsedAs: "raw"
            ))

        case .error(let msg):
            rawEvents.append(DebugRawEvent(
                timestamp: Date(),
                server: config.host,
                raw: msg,
                parsedAs: "error"
            ))

        default:
            break
        }

        // Convert to WOM
        let objects = ircToWOM.convert(event, config: config)

        // Save to store
        Task {
            try? await store.saveMany(objects)
            await MainActor.run {
                womObjects.append(contentsOf: objects)
            }
        }
    }

    // MARK: - Queries

    func messagesFor(server: String, channel: String) -> [WOMObject] {
        return womObjects.filter { obj in
            guard obj.type.contains("wom:Message") else { return false }
            return obj.data["server"] == server && obj.data["channel"] == channel
        }.sorted { $0.createdAt < $1.createdAt }
    }

    func conversations(forServer server: String) -> [Conversation] {
        var channelSet: Set<String> = []
        var dms: Set<String> = []

        for obj in womObjects where obj.type.contains("wom:Message") && obj.data["server"] == server {
            if let channel = obj.data["channel"], !channel.isEmpty {
                channelSet.insert(channel)
            } else if obj.data["visibility"] == "direct" {
                dms.insert(obj.data["nick"] ?? "unknown")
            }
        }

        var result: [Conversation] = channelSet.map { .channel($0) } + dms.map { .dm($0) }
        result.sort { $0.name < $1.name }
        return result
    }

    var feedObjects: [WOMObject] {
        return womObjects.filter { $0.type.contains("wom:Post") }
            .sorted { $0.createdAt > $1.createdAt }
    }

    enum Conversation: Identifiable {
        case channel(String)
        case dm(String)

        var id: String { name }
        var name: String {
            switch self {
            case .channel(let n): return n
            case .dm(let n): return n
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify**

⌘B. Expected: Build Succeeded.

---

### Task 10: Chat UI — ConversationListView and MessageView

**Files:**
- Create: `Virk/VirkApp/Features/Chat/ChatView.swift`
- Create: `Virk/VirkApp/Features/Chat/ConversationListView.swift`
- Create: `Virk/VirkApp/Features/Chat/MessageView.swift`

**Interfaces:**
- Consumes: `AppState` (Task 9), `WOMObject` (Task 2)
- Produces: `ChatView` (container with NavigationStack), `ConversationListView` (list of channels/DMs per server), `MessageView` (chat bubbles + input)

- [ ] **Step 1: Write ChatView.swift**

```swift
import SwiftUI

struct ChatView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        NavigationStack {
            ConversationListView()
                .navigationTitle("Chat")
        }
    }
}
```

- [ ] **Step 2: Write ConversationListView.swift**

```swift
import SwiftUI

struct ConversationListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        List {
            ForEach(appState.servers) { server in
                Section(server.name.isEmpty ? server.host : server.name) {
                    let status = appState.connectionStates[server.id] ?? .disconnected
                    HStack {
                        Circle()
                            .fill(statusColor(status))
                            .frame(width: 8, height: 8)
                        Text(server.host)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    let conversations = appState.conversations(forServer: server.host)
                    if conversations.isEmpty {
                        Text("No conversations yet")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(conversations) { conv in
                            NavigationLink(value: ChatDestination(serverId: server.id, serverHost: server.host, conversation: conv)) {
                                Label(conv.name.dropFirst(), systemImage: icon(for: conv))
                            }
                        }
                    }
                }
            }
        }
        .navigationDestination(for: ChatDestination.self) { dest in
            MessageView(serverId: dest.serverId, serverHost: dest.serverHost, conversation: dest.conversation)
        }
        .overlay {
            if appState.servers.isEmpty {
                ContentUnavailableView(
                    "No Servers",
                    systemImage: "server.rack",
                    description: Text("Add an IRC server in Settings to start chatting.")
                )
            }
        }
    }

    private func statusColor(_ status: AppState.ConnectionStatus) -> Color {
        switch status {
        case .disconnected: return .gray
        case .connecting: return .orange
        case .online: return .green
        }
    }

    private func icon(for conv: AppState.Conversation) -> String {
        switch conv {
        case .channel: return "number"
        case .dm: return "person"
        }
    }
}

struct ChatDestination: Hashable {
    let serverId: UUID
    let serverHost: String
    let conversation: AppState.Conversation
}
```

- [ ] **Step 3: Write MessageView.swift**

```swift
import SwiftUI

struct MessageView: View {
    @Environment(AppState.self) private var appState
    let serverId: UUID
    let serverHost: String
    let conversation: AppState.Conversation

    @State private var messageText: String = ""

    private var messages: [WOMObject] {
        let channel = conversation.name
        return appState.messagesFor(server: serverHost, channel: channel)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { object in
                            MessageBubble(object: object)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            // Input bar
            HStack(spacing: 8) {
                TextField("Message", text: $messageText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { send() }

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .navigationTitle(String(conversation.name.dropFirst()))
    }

    private func send() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messageText = ""
        appState.sendMessage(text, channel: conversation.name, serverId: serverId)
    }
}

struct MessageBubble: View {
    let object: WOMObject

    private var isFromLocalUser: Bool {
        object.provenance?.origin == "localUser"
    }

    private var senderName: String {
        object.attributedTo?.name ?? object.data["nick"] ?? "unknown"
    }

    private var text: String {
        object.content?.text ?? ""
    }

    var body: some View {
        HStack(alignment: .top) {
            if isFromLocalUser { Spacer(minLength: 60) }

            VStack(alignment: isFromLocalUser ? .trailing : .leading, spacing: 2) {
                if !isFromLocalUser {
                    Text(senderName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isFromLocalUser ? Color.blue : Color(.systemGray5))
                    .foregroundStyle(isFromLocalUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            if !isFromLocalUser { Spacer(minLength: 60) }
        }
    }
}
```

- [ ] **Step 4: Build to verify**

⌘B. Expected: Build Succeeded.

---

### Task 11: Feed UI — placeholder

**Files:**
- Create: `Virk/VirkApp/Features/Feed/FeedView.swift`
- Create: `Virk/VirkApp/Features/Feed/FeedCard.swift`

**Interfaces:**
- Consumes: `WOMObject` (Task 2)
- Produces: `FeedView` showing empty state with placeholder message

- [ ] **Step 1: Write FeedView.swift**

```swift
import SwiftUI

struct FeedView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            Group {
                if appState.feedObjects.isEmpty {
                    ContentUnavailableView(
                        "No Posts Yet",
                        systemImage: "newspaper",
                        description: Text("Posts from people you follow will appear here.\nComing when Mastodon, Bluesky, and other posting protocols are added.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(appState.feedObjects) { object in
                                FeedCard(object: object)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Feed")
        }
    }
}
```

- [ ] **Step 2: Write FeedCard.swift**

```swift
import SwiftUI

struct FeedCard: View {
    let object: WOMObject

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(object.attributedTo?.name ?? "unknown")
                    .font(.headline)
                Spacer()
                Text(object.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(object.content?.text ?? "")
                .font(.body)
            if let source = object.data["server"] {
                Text("via \(source)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
```

- [ ] **Step 3: Build to verify**

⌘B. Expected: Build Succeeded.

---

### Task 12: Settings UI — server list and add server

**Files:**
- Create: `Virk/VirkApp/Features/Settings/SettingsView.swift`
- Create: `Virk/VirkApp/Features/Settings/AddServerView.swift`

**Interfaces:**
- Consumes: `AppState` (Task 9), `IRCConnectionConfig` (Task 4)
- Produces: `SettingsView` (server list, connect/disconnect, add button), `AddServerView` (form for new server config)

- [ ] **Step 1: Write SettingsView.swift**

```swift
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAddServer = false

    var body: some View {
        @Bindable var appState = appState
        NavigationStack {
            List {
                ForEach(appState.servers) { server in
                    ServerRow(server: server)
                }
                .onDelete { indexSet in
                    for idx in indexSet {
                        let server = appState.servers[idx]
                        appState.disconnect(from: server.id)
                    }
                    appState.servers.remove(atOffsets: indexSet)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAddServer = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddServer) {
                AddServerView { config in
                    appState.servers.append(config)
                }
            }
            .overlay {
                if appState.servers.isEmpty {
                    ContentUnavailableView(
                        "No Servers",
                        systemImage: "server.rack",
                        description: Text("Tap + to add an IRC server.")
                    )
                }
            }
        }
    }
}

struct ServerRow: View {
    @Environment(AppState.self) private var appState
    let server: IRCConnectionConfig

    private var status: AppState.ConnectionStatus {
        appState.connectionStates[server.id] ?? .disconnected
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(server.name.isEmpty ? server.host : server.name)
                    .font(.headline)
                Text("\(server.host):\(server.port) as \(server.nickname)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            Button(action: toggleConnection) {
                Text(status == .online ? "Disconnect" : "Connect")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch status {
        case .disconnected: return .gray
        case .connecting: return .orange
        case .online: return .green
        }
    }

    private func toggleConnection() {
        switch status {
        case .disconnected:
            appState.connect(to: server.id)
        case .connecting, .online:
            appState.disconnect(from: server.id)
        }
    }
}
```

- [ ] **Step 2: Write AddServerView.swift**

```swift
import SwiftUI

struct AddServerView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (IRCConnectionConfig) -> Void

    @State private var name = ""
    @State private var host = ""
    @State private var port = 6667
    @State private var useTLS = false
    @State private var nickname = ""
    @State private var username = ""
    @State private var realName = ""
    @State private var password = ""
    @State private var autoJoinChannels = ""

    private var portBinding: Binding<Int> {
        Binding(
            get: { port },
            set: { port = max(1, min(65535, $0)) }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Display Name", text: $name)
                    TextField("Host (e.g. irc.libera.chat)", text: $host)
                    HStack {
                        Text("Port")
                        TextField("6667", value: portBinding, format: .number)
                            .keyboardType(.numberPad)
                    }
                    Toggle("Use TLS/SSL", isOn: $useTLS)
                    TextField("Password (optional)", text: $password)
                }

                Section("Identity") {
                    TextField("Nickname", text: $nickname)
                    TextField("Username (optional)", text: $username)
                    TextField("Real Name (optional)", text: $realName)
                }

                Section("Auto-join") {
                    TextField("Channels (comma-separated, e.g. #general,#dev)", text: $autoJoinChannels)
                }
            }
            .navigationTitle("Add Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(host.isEmpty || nickname.isEmpty)
                }
            }
        }
    }

    private func save() {
        let channels = autoJoinChannels
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let config = IRCConnectionConfig(
            name: name,
            host: host,
            port: port,
            useTLS: useTLS,
            nickname: nickname,
            username: username.isEmpty ? nil : username,
            realName: realName.isEmpty ? nil : realName,
            password: password.isEmpty ? nil : password,
            autoJoinChannels: channels
        )
        onSave(config)
        dismiss()
    }
}
```

- [ ] **Step 3: Build to verify**

⌘B. Expected: Build Succeeded.

---

### Task 13: Debug UI

**Files:**
- Create: `Virk/VirkApp/Features/Debug/DebugView.swift`
- Create: `Virk/VirkApp/Features/Debug/RawEventLogView.swift`
- Create: `Virk/VirkApp/Features/Debug/WOMObjectInspectorView.swift`

**Interfaces:**
- Consumes: `AppState` (Task 9), `WOMObject` (Task 2)
- Produces: `DebugView` (menu), `RawEventLogView` (scrollable log), `WOMObjectInspectorView` (JSON dump)

- [ ] **Step 1: Write DebugView.swift**

```swift
import SwiftUI

struct DebugView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            NavigationLink("Raw Event Log (\(appState.rawEvents.count))") {
                RawEventLogView()
            }
            NavigationLink("WOM Objects (\(appState.womObjects.count))") {
                WOMObjectInspectorView()
            }
        }
        .navigationTitle("Debug")
    }
}
```

- [ ] **Step 2: Write RawEventLogView.swift**

```swift
import SwiftUI

struct RawEventLogView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(appState.rawEvents) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(event.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(event.server)
                                .font(.caption2)
                                .foregroundStyle(.blue)
                            Text(event.parsedAs)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        Text(event.raw)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                    Divider()
                }
            }
            .padding()
        }
        .navigationTitle("Raw Events")
    }
}
```

- [ ] **Step 3: Write WOMObjectInspectorView.swift**

```swift
import SwiftUI

struct WOMObjectInspectorView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List(appState.womObjects.reversed()) { object in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(object.type.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Spacer()
                    Text(object.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(object.content?.text ?? "(no text)")
                    .font(.body)
                    .lineLimit(3)

                if let json = prettyJSON(object) {
                    Text(json)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(10)
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("WOM Objects")
    }

    private func prettyJSON(_ object: WOMObject) -> String? {
        guard let data = try? JSONEncoder().encode(object),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }
}
```

- [ ] **Step 4: Build to verify**

⌘B. Expected: Build Succeeded.

---

### Task 14: Social types — Signal, TrustRelation, RemoteIdentity

**Files:**
- Create: `Virk/VirkApp/Core/Social/SocialSignal.swift`
- Create: `Virk/VirkApp/Core/Social/TrustRelation.swift`
- Create: `Virk/VirkApp/Core/Social/RemoteIdentity.swift`

**Interfaces:**
- Consumes: `WOMObject`, `WOMReference`, `WOMProvenance` (Task 2)
- Produces: conceptual type definitions for future social layer (no runtime behavior in MVP)

- [ ] **Step 1: Write SocialSignal.swift**

```swift
import Foundation

/// Represents a social signal: like, recommend, block, mute, follow, etc.
/// Not functional in MVP — type definition for future social layer.
enum SocialSignalType: String, Codable {
    case liked
    case saved
    case recommended
    case followed
    case blocked
    case muted
    case confirmed
    case rejected
    case shared
    case watched
    case read
    case joined
}

struct SocialSignal: Codable, Identifiable {
    var id: String
    var signalType: SocialSignalType
    var strength: String?     // "low", "medium", "high"
    var topic: String?
    var visibility: String?   // "public", "friends", "private"
    var attributedTo: WOMReference
    var objectRef: String?    // ID of the object this signal references
    var createdAt: Date
    var provenance: WOMProvenance?
}
```

- [ ] **Step 2: Write TrustRelation.swift**

```swift
import Foundation

/// Represents a trust relationship from the local user to a remote identity.
/// Not functional in MVP — type definition for future social layer.
struct TrustRelation: Codable, Identifiable {
    var id: String
    var trustedIdentityId: String
    var topic: String?
    var weight: String?          // "low", "medium", "high"
    var allowedSignals: [SocialSignalType]?
    var maxDepth: Int?           // max hops for transitive trust
    var createdAt: Date
    var updatedAt: Date?
}
```

- [ ] **Step 3: Write RemoteIdentity.swift**

```swift
import Foundation

/// Represents a remote person/account known to the system.
/// Not functional in MVP — type definition for future social layer.
struct RemoteIdentity: Codable, Identifiable {
    var id: String              // irc://server/nick, did:key:..., @user@mastodon.server
    var displayName: String
    var protocolType: String    // "irc", "mastodon", "bluesky", "nostr"
    var avatarURL: String?
    var profileURL: String?
    var knownServers: [String]?
    var lastSeen: Date?
    var createdAt: Date
}
```

- [ ] **Step 4: Build to verify**

⌘B. Expected: Build Succeeded.

---

### Task 15: Wire up TabView and final VirkApp

**Files:**
- Modify: `Virk/VirkApp/App/VirkApp.swift` — replace stub with full TabView
- Modify: `Virk/VirkApp/App/AppState.swift` — add SettingsView debug link integration

**Interfaces:**
- Consumes: All previous tasks
- Produces: Complete, runnable app with 3-tab navigation

- [ ] **Step 1: Rewrite VirkApp.swift with full TabView**

```swift
import SwiftUI

@main
struct VirkApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            TabView {
                ChatView()
                    .tabItem {
                        Label("Chat", systemImage: "bubble.left.and.bubble.right")
                    }

                FeedView()
                    .tabItem {
                        Label("Feed", systemImage: "house")
                    }

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
            }
            .environment(appState)
        }
    }
}
```

- [ ] **Step 2: Add debug entry to SettingsView**

Modify `Virk/VirkApp/Features/Settings/SettingsView.swift`: at the bottom of the List, after the `ForEach(appState.servers)`, add a debug navigation link section:

```swift
// Add this Section after the ForEach in SettingsView body, before .navigationTitle:
Section {
    NavigationLink {
        DebugView()
    } label: {
        Label("Debug", systemImage: "wrench.and.screwdriver")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
```

- [ ] **Step 3: Build and run**

⌘R in Xcode. Expected: App launches in simulator with 3 tabs. Chat shows "No Servers" empty state. Settings allows adding a server. After connecting to an IRC server and joining a channel, messages flow into Chat → ConversationListView → MessageView. Debug shows raw events and WOM objects.

- [ ] **Step 4: Verify flow end-to-end**

Manual test:
1. Add server: `irc.libera.chat:6667`, nickname `virk_test`
2. Tap Connect → status turns green
3. Join channel `#virk` (via Settings → or type manually... note: join UI — for MVP, the auto-join channels in server config serve as the join mechanism. If joined successfully, messages from that channel appear under Chat.)
4. Send a message from another IRC client to `#virk`
5. Message appears in Chat → ConversationListView → tap channel → MessageView shows the message bubble
6. Go to Debug tab → WOM Objects → see the parsed WOM object with type `["wom:Message"]`, attributedTo, content, provenance
7. Go to Debug → Raw Events → see the raw IRC PRIVMSG line
8. Send a message from Virk → other client receives it
9. Message bubble shows on the right (blue, local user)

---

## Spec Coverage Self-Review

After writing the plan, verify coverage:

1. **WOM Core models** (WOMObject, WOMContent, WOMReference, WOMRelation, WOMProvenance, WOMIDGenerator) — Task 2 ✓
2. **WOMStore protocol + InMemoryWOMStore** — Task 3 ✓
3. **IRCConnectionConfig** — Task 4 ✓
4. **IRCMessage, IRCEvent** — Task 4 ✓
5. **IRCParser** (PRIVMSG, NOTICE, JOIN, PART, PING/PONG, TOPIC, NAMES) — Task 5 ✓
6. **IRCClient** (NWConnection, NICK/USER registration, PING/PONG, send/receive) — Task 6 ✓
7. **IRCToWOMAdapter** (channel message → wom:Message, DM → wom:Message, join/part → TransportEnvelope) — Task 7 ✓
8. **WOMToIRCAdapter** (WOM intent → PRIVMSG) — Task 8 ✓
9. **AppState** (@Observable, manages store+clients, exposes queries) — Task 9 ✓
10. **Chat UI** (ConversationListView, MessageView with bubbles) — Task 10 ✓
11. **Feed UI** (placeholder empty state) — Task 11 ✓
12. **Settings UI** (server list, add/delete, connect/disconnect) — Task 12 ✓
13. **Debug UI** (RawEventLogView, WOMObjectInspectorView) — Task 13 ✓
14. **Social types** (Signal, TrustRelation, RemoteIdentity) — Task 14 ✓
15. **TabView wiring** (Chat/Feed/Settings tabs) — Task 15 ✓
16. **Success criteria** (connect, join channel, receive, render WOM, send, inspect, persist across launches — for persistence, JSONFileStore is deferred but config save/load works via UserDefaults) — Partially covered; JSONFileStore deferred ✓

**Gap identified:** No `JSONFileStore` — intentionally deferred per spec (InMemoryWOMStore first). Config persistence uses UserDefaults.

**Placeholder scan:** No TBDs, no TODOs, no "implement later" patterns. All code is concrete.

**Type consistency:** `WOMObject.id` is `String` throughout. `IRCConnectionConfig.id` is `UUID` throughout. `AppState.connectionStates` uses `UUID` keys matching `IRCConnectionConfig.id`. `ChatDestination` uses `serverId: UUID`. All consistent.
