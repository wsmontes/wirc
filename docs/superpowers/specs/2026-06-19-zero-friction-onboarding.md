# Zero-Friction Onboarding — Design Spec

**Status:** approved | **Date:** 2026-06-19 | **Version:** 1.0

## Overview

Eliminate all setup friction. A kid opens the app and sees content immediately —
no configuration, no buttons to press, no decisions to make. The app does everything
automatically in the background.

## 1. First Launch — Automatic Timeline

```
App opens → Stream tab visible

t=0s:
  RSS: 200 preloaded feeds begin batched download (background)
  Mastodon: account refresh starts (background, 1s delay)
  IRC: auto-connect to 3 default servers (background)
  IRC: orchestrator.startScan() queued for after connect

t=3-5s:
  Stream: first RSS + Mastodon posts appear
  IRC: connected to all 3 servers, scanning channels

t=10-15s:
  Stream: 50-100 posts visible, dynamic source filters populated
  IRC: scan complete, auto-join top 5 channels per server
  Messages: live chat flowing, channel list populated

t=30s:
  App fully populated. No user action taken.
```

## 2. Default Servers

Three servers are embedded in the app. They auto-connect on launch. The user
never needs to add a server.

```swift
static let defaultServers: [(name: String, host: String, port: Int)] = [
    ("libera.chat", "irc.libera.chat", 6667),
    ("OFTC",        "irc.oftc.net",     6667),
    ("dal.net",     "irc.dal.net",      6667),
]
```

- Nickname: `wirc_XXXX` where XXXX is a random 4-char suffix (persisted across launches)
- Marked as `isDefault: true` — removable by user but restored on reinstall
- Saved to UserDefaults like user-configured servers

## 3. Auto-Connect on Launch

`IRCManager.init()` automatically calls `connect(to:)` for each default server.
No user action needed. TLS/SSL not used by default (port 6667 plaintext).
Connection is non-blocking — the UI renders immediately.

## 4. Auto-Scan + Auto-Join

After each server transitions to `.online`:
1. `orchestrator.startScan()` runs automatically
2. When scan completes, the top 5 channels by user count are auto-joined via `JOIN`
3. These channels appear in the Messages sheet and the channel dropdown
4. Messages start flowing into `IRCChannelManager.visibleMessages`

## 5. Unread Badges

### Per-channel unread count

`IRCChannelManager` tracks unread messages per channel:
- Increments when a WOMObject arrives for a channel that is NOT the active channel
- Resets to 0 when the user selects that channel
- Persisted in memory only (resets on app restart — acceptable)

### Tab badge

The Messages tab icon shows the total unread count across all channels:
```swift
TabView {
    IRCChatView()
        .tabItem { Label("Messages", ...) }
        .badge(totalUnreadCount)
}
```

### Sheet indicators

In the channel sheet, each channel row shows:
```
#python    47 users    ⬤ 3
```
Where `⬤ 3` = 3 unread messages. Color: `DesignSystem.Colors.signal`.

## 6. Stream — Content from Second 3

- 200 RSS feeds already loaded into `FeedSubscriptionStore` on first launch
- `refreshAllFeedsBatched` starts immediately in `AppState.init()`
- Mastodon accounts refresh with 1s delay
- Dynamic source filter chips appear as content arrives

## 7. What the User Never Does

| Action | Before | After |
|--------|--------|-------|
| Add server | Manual | 3 default servers auto-connected |
| Connect button | Tap required | Auto-connect on launch |
| Find channels | Know names or manual scan | Auto-scan + auto-join top 5 |
| Join channels | Type name + tap join | Already joined |
| Configure feeds | Add URLs | 200 preloaded |
| Know IRC/RSS concepts | Required | Zero knowledge needed |

## 8. Files

### Modified

| File | Changes |
|------|---------|
| `App/IRCManager.swift` | Add `defaultServers`, auto-connect in `init()`, auto-scan after `.online`, auto-join top 5 |
| `App/IRCChannelManager.swift` | Add `unreadCount` per channel, `totalUnread` computed property |
| `Features/Messages/IRCChatView.swift` | Show unread badge in sheet, badge on tab icon |
| `App/WircApp.swift` | `.badge()` on Messages tab |
| `App/AppState.swift` | `womObjects.append` triggers `channelManager.updatePreview` for unread tracking |

## 9. Success Criteria

1. App opens to Stream with content appearing within 3-5 seconds
2. Three default IRC servers auto-connect without user action
3. Channels are auto-scanned and top 5 per server are auto-joined
4. Messages tab shows channel list with unread badges
5. Tab icon shows total unread count
6. User can remove default servers (they return on reinstall)
7. Zero configuration needed for basic functionality
