# Zero-Friction Onboarding — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate all setup friction. App opens with content immediately — 3 default IRC servers auto-connect, auto-scan channels, auto-join top 5, unread badges on channels and tab icon.

**Architecture:** IRCManager embeds default servers and auto-connects in init(). After .online, orchestrator scans automatically and auto-joins top 5 channels. IRCChannelManager tracks unread counts per channel. IRCChatView shows badges in sheet. TabView shows total badge.

**Tech Stack:** SwiftUI, iOS 17, @Observable, UserDefaults for nickname persistence.

## Global Constraints

- Target: iOS 17.0+
- No external SPM dependencies
- Default servers: libera.chat, OFTC, dal.net (port 6667, plaintext)
- Random nickname suffix persisted in UserDefaults
- 200 RSS feeds already loaded via DefaultFeedsLoader
- Auto-join heuristic: top 5 channels per server by user count
- Unread badges in-memory only (reset on app restart)

---

### Task 1: Default servers + auto-connect + auto-scan + auto-join

**Files:**
- Modify: `App/IRCManager.swift`

**Interfaces:**
- Consumes: ServerOrchestrator, IRCAutomation
- Produces: Static `defaultServers` array, auto-connect in init(), orchestrator scan trigger on .connected, auto-join top 5 after scan

- [ ] **Step 1: Add defaultServers constant**

```swift
// In IRCManager:
static let defaultServers: [(name: String, host: String, port: Int)] = [
    ("libera.chat", "irc.libera.chat", 6667),
    ("OFTC",        "irc.oftc.net",     6667),
    ("dal.net",     "irc.dal.net",      6667),
]

private static let nicknameKey = "wirc.defaultNickSuffix"
private static var randomNickname: String {
    let key = nicknameKey
    if let saved = UserDefaults.standard.string(forKey: key), !saved.isEmpty { return "wirc_\(saved)" }
    let suffix = String(UUID().uuidString.prefix(4)).lowercased()
    UserDefaults.standard.set(suffix, forKey: key)
    return "wirc_\(suffix)"
}
```

- [ ] **Step 2: Auto-insert default servers and connect in init()**

```swift
// At end of IRCManager.init():
for (name, host, port) in Self.defaultServers {
    if !servers.contains(where: { $0.host == host && $0.port == port }) {
        let config = IRCConnectionConfig(name: name, host: host, port: port, nickname: Self.randomNickname)
        servers.append(config)
    }
}
// Auto-connect after a short delay (let UI render first)
DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
    for server in self?.servers ?? [] {
        self?.connect(to: server.id)
    }
}
```

- [ ] **Step 3: Trigger orchestrator scan on .connected**

```swift
// In handleEvent, case .connected: after auto-join channels, add:
if orchestrator.globalChannels.isEmpty && !orchestrator.isScanning {
    orchestrator.startScan()
}
```

- [ ] **Step 4: Auto-join top 5 channels after scan**

Add a polling mechanism or callback. Since ServerOrchestrator doesn't have a completion callback, use a periodic check:

```swift
// In IRCManager, after calling orchestrator.startScan():
private func scheduleAutoJoinCheck(serverId: UUID) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
        guard let self, !self.orchestrator.isScanning else {
            self?.scheduleAutoJoinCheck(serverId: serverId) // retry in 2s
            return
        }
        let channels = self.orchestrator.globalChannels
            .filter { self.servers.contains(where: { s in s.host == $0.serverHost }) }
            .sorted { $0.users > $1.users }
            .prefix(5)
        for ch in channels {
            guard let sid = self.servers.first(where: { $0.host == ch.serverHost })?.id else { continue }
            self.joinChannel(ch.name, serverId: sid)
        }
    }
}
```

- [ ] **Step 5: Build and verify**

```bash
xcodebuild -project Wirc/Wirc.xcodeproj -scheme Wirc -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```
Expected: 0 errors. On first launch, 3 servers appear and auto-connect.

- [ ] **Step 6: Commit**

```bash
git commit -m "feat: default IRC servers + auto-connect + auto-scan + auto-join top 5"
```

---

### Task 2: Unread badges per channel

**Files:**
- Modify: `App/IRCChannelManager.swift`
- Modify: `Features/Messages/IRCChatView.swift`

**Interfaces:**
- Consumes: IRCChannelManager, IRCChatView
- Produces: `unreadCounts: [String: Int]`, `totalUnread: Int`, badge display in sheet

- [ ] **Step 1: Add unread tracking to IRCChannelManager**

```swift
// In IRCChannelManager, add:
var unreadCounts: [String: Int] = [:]  // channelKey → count
var totalUnread: Int { unreadCounts.values.reduce(0, +) }

func incrementUnread(for channelKey: String) {
    guard activeChannel?.id != channelKey else { return } // don't count active channel
    unreadCounts[channelKey, default: 0] += 1
}

func markRead(_ channelKey: String) {
    unreadCounts[channelKey] = 0
}
```

- [ ] **Step 2: Wire unread increment in AppState**

```swift
// In AppState, in the onWOMObjects callback, after appending:
for obj in objects {
    if obj.type.contains("wom:Message"), let server = obj.data["server"], let channel = obj.data["channel"] {
        irc.channelManager.incrementUnread(for: "\(server)|\(channel.lowercased())")
    }
}
```

- [ ] **Step 3: Show unread badges in IRCChatView sheet**

In the channel row in `serverSection`:
```swift
let channelKey = "\(server.host)|\(conv.name.lowercased())"
let unread = manager.unreadCounts[channelKey] ?? 0
if unread > 0 {
    Circle()
        .fill(DesignSystem.Colors.signal)
        .frame(width: 8, height: 8)
    Text("\(unread)")
        .font(DesignSystem.Fonts.data(9))
        .foregroundStyle(DesignSystem.Colors.signal)
}
```

- [ ] **Step 4: Mark read when selecting channel**

In `setActiveChannel`:
```swift
if let ch = channel {
    markRead("\(ch.serverHost)|\(ch.name.lowercased())")
}
```

- [ ] **Step 5: Tab badge in WircApp**

```swift
IRCChatView()
    .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right") }
    .badge(appState.irc.channelManager.totalUnread)
```

- [ ] **Step 6: Build and verify**

Expected: 0 errors. Unread badges appear on channels in sheet and on tab icon.

- [ ] **Step 7: Commit**

```bash
git commit -m "feat: unread badges per channel and tab icon"
```
