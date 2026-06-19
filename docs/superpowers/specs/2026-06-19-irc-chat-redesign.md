# IRC Chat Redesign — Design Spec

**Status:** approved | **Date:** 2026-06-19 | **Version:** 1.0

## Overview

Redesign the Messages tab from a multi-bar layout (server bar + channel tabs + timeline + input)
into a chat-first layout: full-screen timeline with a minimal header, and a bottom sheet for
server/channel/user management. Auto-scan + one-tap join eliminates onboarding friction.

## Goals

1. **Maximize chat space** — only 3 fixed UI elements: header (44pt), input bar (48pt), drag handle (20pt). Everything else is timeline.
2. **Eliminate horizontal scroll** — channels are a vertical list in the sheet, not tabs.
3. **Visible user list** — expandable per channel with colored prefixes.
4. **Zero-config onboarding** — auto-scan on connect, one-tap join popular channels.
5. **Single sheet** — servers, channels, users, scan, and join all in one bottom sheet.

## 1. Layout

```
┌──────────────────────────────────────┐
│  ● libera.chat · #python · 47        │  ← header (44pt, tappable → sheet)
│  ─────────────────────────────────── │
│                                      │
│  12:34  jhacker  this is the new    │  ← timeline (fills remaining space)
│         parser, it handles CTCP...   │
│  12:35  carla    +1 looks good       │
│                                      │
│  ─────────────────────────────────── │
│  │ [#python] mensagem...       [⏎] │  ← input bar (48pt, fixed bottom)
│  ──── ────────────────────────────── │  ← drag handle (20pt)
└──────────────────────────────────────┘
```

### Fixed UI height budget

| Element | Height |
|---------|--------|
| Header bar | 44pt |
| Divider | 1pt |
| Input bar | 48pt |
| Drag handle | 20pt |
| **Total fixed** | **113pt** |
| Timeline | remaining space |

## 2. Header Bar

Single line, 44pt. Three tappable zones:

```
┌──────────────────────────────────────┐
│  [All ▾]  libera.chat · #python · 47 │
└──────────────────────────────────────┘
```

- **Channel selector (left, 80pt):** Shows active channel or "All". Tap → dropdown with All + joined channels. Selecting a channel loads it immediately.
- **Info (center):** `server · channel · N users`. Tap → opens the bottom sheet.
- **Connection dot (left of server name):** Green = online, orange = connecting, grey = disconnected.

## 3. Bottom Sheet

Triggered by: tapping header info, tapping drag handle, or swipe up from handle.

```
┌──────────────────────────────────────┐
│  ═══ Servers & Channels ════════════ │
│                                      │
│  SERVERS                             │
│  ● libera.chat                online │
│    #dev              42 users     ▸  │
│    #python           47 users     ▸  │
│    #random           18 users     ▸  │
│  ○ dal.net                 offline   │
│    [+ Join channel...]              │
│  [+ Add Server...]                  │
│                                      │
│  QUICK JOIN                          │
│  🔍 Type channel name...             │
│                                      │
│  POPULAR                             │
│  #brasil        42    libera.chat    │
│  #linux         89    libera.chat    │
│  #python        47    libera.chat    │
└──────────────────────────────────────┘
```

### Behaviors

- **Tap server** → expand/collapse its channel list
- **Tap channel** → close sheet, load that channel in chat
- **Tap ▸ on channel** → expand inline user list with colored prefixes
- **User list:** `@` green (op), `%` blue (half-op), `+` orange (voice), ` ` normal. Tap nick → `/msg`. Long press → Message / WhoIs / Kick / Ban / Ignore menu.
- **QUICK JOIN:** text field. Type `#channel`, tap Join. Joins on the first online server.
- **POPULAR:** channels from orchestrator scan. Tap → auto-join + close sheet.
- **Pull down** to dismiss sheet.

## 4. Auto-Scan on Connect

When `IRCManager` transitions to `.online` for the first time on a server:

1. `orchestrator.startScan()` is called automatically
2. The sheet shows "Scanning for channels..." with a ProgressView
3. When scan completes, the POPULAR section populates
4. User sees popular channels immediately

## 5. Input Bar

```
┌──────────────────────────────────────┐
│  [#python] │ type message...  │ [⏎]  │
└──────────────────────────────────────┘
```

- **Channel prefix (tappable):** Shows `[#channel]` or `[All N]`. Tap opens quick channel switcher (same dropdown as header).
- **Send button:** Signal-colored when text is non-empty.
- **All mode:** prefix shows `[All 3]`. Tap opens broadcast target picker.
- **Future:** nick autocomplete (type `@jh` → suggest `@jhacker`).

## 6. Timeline

Same `deckMessageRow` as current implementation:
- All mode: channel label above nick
- Mentions: highlighted with Signal background
- `/me` actions: italic rendering
- System events: centered pills

## 7. Files

### New files

| File | Purpose |
|------|---------|
| `Features/Messages/IRCChatView.swift` | New Messages tab root: full-screen chat + bottom sheet |

### Modified files

| File | Changes |
|------|---------|
| `Features/Messages/IRCMessageDeckView.swift` | **Deleted.** Replaced by IRCChatView. |
| `Features/Messages/IRCServerManagerSheet.swift` | **Deleted.** Functionality merged into the bottom sheet. |
| `App/IRCManager.swift` | Add `autoScanOnConnect` flag, call orchestrator.startScan on first .online |
| `App/WircApp.swift` | Update Messages tab to use IRCChatView |

### Preserved

| File | Reason |
|------|--------|
| `App/IRCChannelManager.swift` | Data layer unchanged |
| `App/IRCAutomation.swift` | Automation unchanged |
| `Infrastructure/IRC/IRCCommandParser.swift` | Commands unchanged |
| `Infrastructure/IRC/IRCCommandExecutor.swift` | Executor unchanged |

## 8. Success Criteria

1. Chat occupies full screen minus 113pt of fixed chrome
2. Bottom sheet opens with drag handle or header tap or swipe
3. Sheet shows: servers (expandable) → channels → users → quick join → popular
4. Tapping a channel in the sheet loads it in the chat and closes the sheet
5. Header shows active channel with server info and user count
6. Channel dropdown in header switches channels without opening sheet
7. Auto-scan runs on first connect, populates POPULAR section
8. One-tap join from POPULAR
9. User list shows colored prefixes (@/%/+)
10. Input bar shows active channel prefix, tappable for quick switch
