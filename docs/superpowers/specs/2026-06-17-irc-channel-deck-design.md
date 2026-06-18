# IRC Channel Deck — Design Spec

**Status:** approved | **Date:** 2026-06-17 | **Version:** 1.0

## Overview

Restructure the IRC experience from a sheet buried inside Stream into a first-class
**Messages** tab with a "Channel Deck" paradigm: horizontal channel tabs, a unified
"All" merged view, broadcast messaging, and server management all within the tab.
Built to handle hundreds of simultaneous channels via windowed data loading.

## Core Concept

```
[Server status bar]    ● libra ● oftc ● ircnet +3  [⚙]
[Channel tabs]         [All] [#dev] [#random] [#py] [#rust] ⊕
[Timeline]             Messages for active channel/All mode
[Input bar]            [#dev] ──── message ──── [⏎]
```

### Viewing modes

| Tab | Shows |
|-----|-------|
| **All** | Merged timeline from ALL joined channels, chronological. Each message has channel label. |
| **#channel** | Messages from that specific channel only. |

### Sending modes

| Mode | Behavior |
|------|----------|
| **Normal** (individual tab) | Sends to active channel only |
| **Broadcast** (All tab) | Opens target picker; sends same message to selected channels sequentially |

---

## 1. Navigation Architecture

```
TabView
├── Stream      (posts from feeds — RSS, Mastodon, YouTube, Podcast, GitHub)
├── Messages    (IRC Channel Deck — NEW)
├── Library     (archive, search, export — unchanged)
└── Workshop    (transports for feeds/Mastodon, governance, data — IRC section removed)
```

### What moves

| Current | New |
|---------|-----|
| ChannelFilterView (sheet in Stream) | **Deleted.** Replaced by Messages tab. |
| MessageCard (IRC card in Stream) | **Deleted.** IRC no longer appears in Stream. |
| ConversationListView | **Preserved as fallback.** Messages tab is new implementation. |
| MessageView | **Preserved.** Used inside Messages tab. |
| Workshop IRCTransportDetail | **Deleted.** Server management moves to Messages. |
| Stream connectionStatusBar | **Deleted.** Connection status moves to Messages server bar. |

### Stream tab changes

| Before | After |
|--------|-------|
| 4 filter chips (All/Messages/Posts/Media) | Dynamic source chips (RSS, Mastodon, YouTube, Podcast, GitHub...) |
| Shows IRC messages | Shows only posts |
| MessageCard + FeedCard | Only FeedCard |
| ChannelFilterView sheet | No sheet — Messages tab handles IRC |
| Connection status bar | Removed |

Dynamic filter chips are built from `Set(network)` of WOMObjects with type `wom:Post`. Order: RSS, Mastodon, YouTube, Podcast, GitHub (fixed), then alphabetical for any others.

---

## 2. Messages Tab — Channel Deck

### 2.1 Server Status Bar

Horizontal scroll of connected servers. Each server is a dot (color = status) + hostname abbreviation.

```
● libra ● oftc ● ircnet +3 more  [⚙]
```

- **Tap dot:** expands to show server detail inline (host, port, nick, channels)
- **[⚙]:** opens Server Manager sheet (full management)
- **+3 more:** when too many servers to fit, shows overflow count; tap shows all

### 2.2 Channel Tabs

Horizontal scroll of joined channels, ALWAYS starting with "All."

```
[All] [#dev] [#random] [#python] [#rust] [#linux] ... ⊕
```

- **Scroll performance:** with 300 channels, uses lazy horizontal stack. Only renders visible tabs (~10-15).
- **Active tab:** Signal-colored background, white text.
- **Inactive:** Border-colored background, Ink text.
- **⊕:** Opens Join Channel sheet (server picker + channel name input).

### 2.3 Timeline

LazyVStack of messages for the active context.

**All mode:** each message has a small channel label above the sender name.
```
┌─ #dev ──────────────────────────────┐
│ jhacker   this is the new parser    │
└─────────────────────────────────────┘
┌─ #random ───────────────────────────┐
│ carla     can someone review my PR? │
└─────────────────────────────────────┘
```

**Single channel mode:** no channel label needed. Same MessageBubble as today.

**Scroll up:** loads older messages from JSONFileStore (pagination, 50 at a time).

**Max visible:** 500 messages in the active window. Older ones are on disk.

### 2.4 Input Bar

```
[#dev] ──────── type your message ──────── [⏎]
```

- **Single channel mode:** shows `[#channel]` prefix. Enter sends.
- **All mode:** shows `[All N channels]`. Enter opens broadcast picker, or a setting toggles between "send to all joined" vs "pick targets."
- **Broadcast mode:** tapping the prefix opens target picker (list of joined channels with checkboxes).

---

## 3. Server Manager Sheet

Opened via [⚙] in server bar or ⊕ → Add Server.

```
┌──────────────────────────────────────┐
│  Servers & Channels            [Done]│
│  ─────────────────────────────────── │
│                                      │
│  ● libera.chat                online │
│    #dev          42 users      [✕]   │
│    #random       18 users      [✕]   │
│    [+ Join channel...]               │
│    [Disconnect] [Remove]             │
│  ─────────────────────────────────── │
│  ○ oftc.net                  offline │
│    #rust         8 users             │
│    [Connect]                         │
│  ─────────────────────────────────── │
│  [+ Add Server...]                   │
└──────────────────────────────────────┘
```

- **Add Server:** opens existing `AddServerView`
- **Join channel:** text field + server picker, calls `appState.joinChannel`
- **[✕] Part:** calls `appState.partChannel`
- **Connect/Disconnect:** calls `appState.connect` / `appState.disconnect`
- **Remove:** removes server config entirely

---

## 4. Data Architecture — IRCChannelManager

```swift
@Observable
final class IRCChannelManager {
    /// Lightweight channel references — safe to have hundreds
    var channels: [ChannelHandle] = []

    /// Currently selected channel tab (nil = All mode)
    var activeChannel: ChannelHandle?

    /// Whether we're in All (merged) mode
    var isAllMode: Bool { activeChannel == nil }

    /// Visible message window — max 500 items
    var visibleMessages: [WOMObject] = []

    /// Broadcast targets (for All mode sending)
    var broadcastTargets: Set<ChannelHandle> = []

    // MARK: Data loading

    /// Load recent messages for a channel (or all if nil) from store
    func loadMessages(for channel: ChannelHandle?, limit: Int = 200)

    /// Paginate older messages from disk
    func loadOlderMessages() async -> [WOMObject]

    // MARK: Sending

    func sendMessage(_ text: String, to: ChannelHandle)
    func broadcastMessage(_ text: String, to: Set<ChannelHandle>)

    // MARK: Channel lifecycle

    func addChannel(_ handle: ChannelHandle)
    func removeChannel(_ handle: ChannelHandle)
    func refreshChannelList()
}

struct ChannelHandle: Identifiable, Hashable {
    let serverId: UUID
    let serverHost: String
    let name: String          // "#dev"
    var userCount: Int
    var lastPreview: String?  // last message preview
    var id: String { "\(serverId)|\(name)" }
}
```

### Window strategy for 300+ channels

| Tier | Count | Memory | Behavior |
|------|-------|--------|----------|
| Active tab | 1 channel or All | 200-500 messages | Full message objects in memory |
| Visible tabs | ~10-15 (scroll viewport) | 50 messages each | Preloaded for fast tab switch |
| Background | All others | 1 preview msg each | Just `ChannelHandle.lastPreview` |

Total with 300 channels: ~10 active × 50 + 290 × 1 preview = ~790 message references. Well within limits.

### Old message loading

When user scrolls up past the in-memory window, `loadOlderMessages()` queries `JSONFileStore` for messages from that channel before the oldest known timestamp, 50 at a time. Disk I/O happens on background queue; results are appended to `visibleMessages` on main actor.

---

## 5. Broadcast Behavior

1. User is in All mode
2. Taps input prefix `[All N channels]` → opens broadcast picker
3. Picker shows all joined channels with checkboxes
4. "Select All" / "Deselect All" shortcuts
5. User types message, taps send
6. Message is sent sequentially to each selected channel via `PRIVMSG`
7. Each send result is shown: `✓ #dev  ✓ #random  ✕ #rust (offline)`

Failures don't block remaining sends — each is independent.

---

## 6. Files

### New files

| File | Purpose |
|------|---------|
| `Infrastructure/IRC/IRCChannelManager.swift` | @Observable windowed message manager |
| `Features/Messages/IRCMessageDeckView.swift` | Full Messages tab: server bar + channel tabs + timeline + input + broadcast picker |
| `Features/Messages/IRCServerManagerSheet.swift` | Server & channel management sheet |

### Modified files

| File | Changes |
|------|---------|
| `App/AppState.swift` | Add `let channelManager = IRCChannelManager()` |
| `App/WircApp.swift` | Add Messages tab (4th tab) |
| `Features/Stream/StreamView.swift` | Remove IRC: delete MessageCard, ChannelFilterView, connectionStatusBar; dynamic source filters |
| `Features/Feed/FeedCard.swift` | Remove `ircContent` variant (IRC no longer in Stream) |
| `Features/Workshop/WorkshopView.swift` | Remove `IRCTransportDetail` and IRC section from transports |
| `Core/DesignSystem.swift` | Add source colors for dynamic filter chips if needed |

### Preserved (no changes)

| File | Reason |
|------|--------|
| `Features/Chat/ConversationListView.swift` | Fallback until Messages tab is stable |
| `Features/Chat/MessageView.swift` | Used inside Messages tab |
| `Features/Chat/ChatView.swift` | Preserved as-is |
| `Features/Chat/MessageView.swift` (SystemEventPill) | Moves to Messages |

### No files deleted

All existing Chat/* files kept as fallback.

---

## 7. Implementation Sequence

1. **IRCChannelManager** — data layer, windowed loading, broadcast
2. **IRCServerManagerSheet** — reusable sheet for server/channel management
3. **IRCMessageDeckView** — Messages tab UI (server bar + tabs + timeline + input)
4. **StreamView cleanup** — remove IRC, dynamic source filters
5. **WorkshopView cleanup** — remove IRC section
6. **FeedCard cleanup** — remove ircContent
7. **WircApp wiring** — add Messages tab
8. **Polish** — scroll performance, pagination, broadcast UX

---

## 8. Success Criteria

1. Messages tab shows server status bar with all configured IRC servers
2. Channel tabs scroll horizontally and support 300+ channels without lag
3. All mode merges messages from all channels chronologically with source labels
4. Single channel mode shows only that channel's messages
5. Sending works in both normal and broadcast modes
6. Broadcast to N channels sends N independent PRIVMSG, reports results per channel
7. Scroll up loads older messages from disk (pagination)
8. Server Manager sheet: add/remove servers, join/part channels, connect/disconnect
9. Stream tab only shows feed posts (no IRC), with dynamic source filter chips
10. Workshop no longer has IRC section
11. Existing ConversationListView/MessageView still work as fallback
12. No regression in IRC connectivity or message delivery
