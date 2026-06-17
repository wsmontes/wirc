# Wirc Visual Redesign — Design Spec

**Status:** approved | **Date:** 2026-06-17 | **Version:** 1.0

## Overview

Redesign Wirc from a conventional IRC/feed client into a visual embodiment of the WOM 0.6
semantic object model. The app's purpose is to be a window into your information across all
protocols — with provenance, governance, and identity visible, not hidden in debug tools.

### Core thesis

> *"A informação é sua. O processo é seu. O histórico é seu. O aplicativo não é a prisão do dado."*
> — WOM 0.6, §26

The redesign makes three promises visible in every pixel:
1. **Everything has an origin.** The provenance badge is a first-class citizen on every object.
2. **Everything has permissions.** Governance is inspectable, not buried.
3. **Everything is yours.** Export, archive, and portability are primary features, not afterthoughts.

---

## 1. Navigation Architecture

Three tabs reorganized around the user's relationship to information (not protocol):

| Tab | SF Symbol | Purpose |
|-----|-----------|---------|
| **Stream** | `waveform` | Unified chronologic timeline of all incoming objects — IRC, Mastodon, RSS, YouTube, Podcast, GitHub. Filter by source type via provenance badge toggle. |
| **Library** | `archivebox` | Search, browse, and export your collection. Grouped by date. Filter by type and source. Export to WOM Bundle. |
| **Workshop** | `hammer` | Manage transports (IRC servers, RSS feeds, Mastodon accounts), governance defaults, import/export, and debug access. |

### What moves where

| Current | New |
|---------|-----|
| Chat tab | Stream — channel messages appear in timeline, filterable by channel |
| Feed tab | Stream — feed posts appear in timeline, filterable by source |
| Settings tab | Workshop |
| Debug tab | Workshop → bottom link "Debug" opens as sheet |
| Feed management | Workshop → Transports → Feeds |

---

## 2. Visual System

### Color — "Archive"

Grounded in the idea of information that lasts — warm, archival, not cold or flashy.

| Token | Hex | Role |
|-------|-----|------|
| Page | `#F6F3ED` | Background — warm paper |
| Surface | `#FFFFFF` | Cards, bubbles, elevated content |
| Ink | `#1C1917` | Primary text — near-black with warmth |
| Pencil | `#78716C` | Secondary text, captions, metadata |
| Border | `#E7E5E2` | Hairline rules, dividers, separators |
| Signal | `#E85D3A` | Primary accent — actions, IRC source badge, selected states |
| Mastodon | `#6366F1` | Source badge color — Mastodon |
| RSS | `#D97706` | Source badge color — RSS |
| GitHub | `#059669` | Source badge color — GitHub |
| Podcast | `#7C3AED` | Source badge color — Podcast |
| YouTube | `#DC2626` | Source badge color — YouTube |

### Typography

| Role | Font | Size | Weight | Usage |
|------|------|------|--------|-------|
| Display | New York | 16–20pt | Semibold | Headlines, article titles. The aesthetic risk — serif on a chat/feed app. Signals that content has weight. |
| Body | SF Pro | 15pt | Regular | Message text, descriptions, UI labels. Comfortable for sustained reading. |
| Data | SF Mono | 11–13pt | Regular/Bold | Sender names, channel names, timestamps, URIs, provenance metadata. Terminal heritage nod. |
| Caption | SF Pro | 12pt | Medium | Footer text, source names, filter chips. |

### Spacing scale

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4pt | Icon-to-label gaps, badge padding |
| sm | 8pt | Element internal padding, chip gaps |
| md | 12pt | Card internal padding, list row gaps |
| lg | 16pt | Card external padding, section margins |
| xl | 24pt | Section spacing, header bottom margin |

### Border radius

| Context | Radius |
|---------|--------|
| Cards | 12pt |
| Bubbles | 14pt (sent), 14pt (received) |
| Buttons / chips | 8pt |
| Inspector sheet | 16pt top |
| Source badges | 6pt (pill) |

---

## 3. The Signature Element — Provenance Badge

Every object in Stream carries a provenance badge at its top:

```
● IRC · Libera.Chat · 2m ago
```

Components:
- **Source dot** (6pt circle, source-colored)
- **Network name** (SF Mono 11pt Bold, Ink)
- **Server/instance** (SF Mono 11pt Regular, Pencil)
- **Relative timestamp** (SF Mono 11pt Regular, Pencil)

### Interaction

Tapping the provenance badge opens the **Object Inspector** as a bottom sheet with WOM layers:

1. **Origin** — actor, source, confidence, review status
2. **Governance** — purpose, ads policy, agent use, sharing, retention
3. **Transport Binding** — protocol, server, channel/feed URL
4. **Classification** — semantic type, sensitivity, topics

Footer actions: Share · Export as JSON · Copy Object ID

---

## 4. Stream View — Cards & Messages

### Unified Stream Card skeleton

```
┌────────────────────────────────────────┐
│  ● IRC · Libera.Chat · 2m ago          │  ← provenance badge (tappable)
│  ───────────────────────────────────── │  ← hairline (1px, source-colored)
│                                        │
│  [HEADLINE — New York, if present]     │
│                                        │
│  Body text in SF Pro, up to 12 lines   │
│                                        │
│  ── #dev · sent by jhacker            │  ← footer (SF Mono 11pt, Pencil)
└────────────────────────────────────────┘
```

### Type-specific variations

**IRC message:**
- No headline
- Sender name in SF Mono Bold 13pt (Signal-colored for IRC)
- Body: message text in SF Pro 15pt
- Footer: channel name

**Mastodon post:**
- No headline (unless post has a content warning, which becomes headline)
- Author display name in SF Pro Semibold + @handle in SF Mono Pencil
- Body: post text (HTML stripped) in SF Pro 15pt
- Media: inline images, max 200pt height, rounded 8pt
- Footer: favourites/reblogs/replies counts + instance name

**Mastodon boost:**
- Indented 16pt from left
- "X boosted" label in SF Mono 11pt, Mastodon-colored
- Original author's card renders as a Mastodon post

**Article / blog post (RSS):**
- Headline in New York Semibold 17pt, Ink
- Author/site in SF Mono 11pt Pencil
- Body: first paragraph or description in SF Pro 15pt, line limit 8
- Footer: feed title

**YouTube video:**
- Thumbnail left (120×68pt, rounded 8pt, 16:9)
- Headline right (SF Pro Semibold 15pt, line limit 3)
- Channel name + duration badge
- "YouTube" tag in YouTube-red pill

**Podcast episode:**
- Cover art left (64×64pt, rounded 8pt)
- Episode title (SF Pro Semibold 15pt)
- Show name (SF Pro 13pt Pencil)
- Duration badge + "Podcast" pill in Podcast-violet

**GitHub release:**
- Tag icon + release name (SF Pro Semibold 15pt)
- Repo name (SF Mono 12pt Pencil)
- Release notes preview (SF Pro 14pt, line limit 5)

### System events

Between messages, rendered as centered pills:
```
        → jhacker joined #dev
        ← maria left (goodbye!)
        ~ oldnick → newnick
        * Mode +b user!*@*
```
- SF Mono 11pt, Pencil color
- Centered, max width 80% of card
- Background: Border color at 50% opacity, pill shape (capsule)

---

## 5. Library View

### Layout

- Search bar pinned to top
- Horizontal filter chips below search: All, Messages, Posts, Media
- Collapsible source filter row: colored dots (IRC, Mastodon, RSS, GitHub, Podcast, YouTube)
- Content grouped by date with date headers in SF Mono 12pt Pencil:
  ```
  Jun 17
    ● IRC · #dev — 12 messages
    ● Mastodon · social — 3 posts, 1 boost
    ● RSS · Daring Fireball — 2 articles
  Jun 16
    ● GitHub · vapor/vapor — 1 release
  ```

### Interactions

- Search: full-text across content, source names, channels, URIs, WOM classification
- Date headers: tapping selects all objects in that date for export
- Row tap: opens full object in detail view (same inspector sheet as Stream, content-first)
- Export button (top right): exports selected or all as WOM Bundle `.zip`

### Empty state

```
Your library is empty.
Objects from Stream are automatically saved here.
Or import a WOM Bundle to get started.

[Import WOM Bundle...]
```

---

## 6. Workshop View

### Sections

1. **Transports** — IRC servers, Mastodon accounts, Feed subscriptions. Each expandable inline to show details (server/host, channels, connection status dot).
2. **Governance Defaults** — Ads use, Agent use, Default sharing, Retention. Each tappable to cycle or open a picker. Apply to new objects at creation time.
3. **Data** — Export Library (share sheet with WOM Bundle `.zip`), Import WOM Bundle (file picker).
4. **About** — WOM version, app version, Debug link (11pt Pencil, opens debug view as sheet).

### Transport detail (IRC example, expanded)

```
● IRC · libera.chat          ● online
   Port: 6667 · TLS: No
   Nick: wirc_user
   Channels: #dev, #general, #random

   [Disconnect]  [Edit]  [Remove]
```

---

## 7. Object Inspector (Bottom Sheet)

Triggered by tapping any provenance badge. Sections reflect WOM 0.6 layers:

1. **Object ID** — URN, type, schema, createdAt
2. **Origin** — provenance.origin, actor name/ID, source name/ID, confidence, review status
3. **Governance** — purpose[], adsUse, agentUse, sharing, retention, consent status
4. **Transport Binding** — protocol-specific binding (IRC server/channel, ActivityPub URI, RSS feed URL)
5. **Classification** — semanticType, sensitivity, category, topics, confidence

Footer: Share · Export JSON · Copy Object ID

---

## 8. Empty States & Micro-Interactions

### First launch (no transports)

- Abstract WOM layer diagram (4 dots connected by lines, rendered as SF Symbols or simple shapes)
- Tagline: "Your information, your memory, your tools."
- Description: "Wirc brings your IRC, RSS, and Mastodon into one space that you own and control."
- CTA: "Set up your Workshop →" (Signal background, white text)

### Connection pulse

When an IRC server transitions to `online`, its status dot does a single scale pulse (0.8× → 1.2× → 1.0× over 300ms).

### New content dot

When Stream receives new objects while the user is in another tab, a small Signal dot appears on the Stream tab icon. Not a count — just presence.

### Feed refresh

When a feed finishes refreshing, the Workshop feed count ticks up with a scale bounce (spring animation, 200ms).

### Animation philosophy

Animations are deliberate and sparse. No scroll-triggered reveals, no hover effects (this is iOS), no ambient motion. The only animations are: connection pulse, new-content dot, refresh count tick, and the inspector sheet spring.

---

## 9. Implementation Notes

### Files to create

| File | Purpose |
|------|---------|
| `DesignSystem.swift` | Color tokens, font extensions, spacing constants |

### Files to modify

| File | Changes |
|------|---------|
| `WircApp.swift` | New tab bar (Stream/Library/Workshop), styling |
| `FeedCard.swift` | Complete rewrite — unified skeleton, type variants, provenance badge |
| `FeedView.swift` | Becomes StreamView — unified timeline |
| `MessageView.swift` | Message bubble redesign, system event pills |
| `ConversationListView.swift` | Moves into Stream as channel filter |
| `SettingsView.swift` | Becomes WorkshopView |
| `AddServerView.swift` | Minimal updates for new visual system |
| `AddFeedView.swift` | Minimal updates for new visual system |
| `WOMObjectInspectorView.swift` | Elevated to first-class inspector sheet |
| `DebugView.swift` | Accessible from Workshop as sheet |

### Files to keep (no changes)

| File | Reason |
|------|--------|
| All `Core/WOM/*` | Data models don't change |
| All `Infrastructure/*` | Transport logic doesn't change |
| `AppState.swift` | State management doesn't change (new view names may need minor plumbing) |
| `SocialSignal.swift`, `TrustRelation.swift`, `RemoteIdentity.swift` | Future features, untouched |

### What does NOT change

- WOM 0.6 data models and types
- All infrastructure (IRC client, feed fetcher, Mastodon client, persistence)
- AppState (except for potential new query methods for Library)
- All adapters (IRC→WOM, Feed→WOM, Mastodon→WOM, WOM→IRC)
- No new external dependencies

---

## 10. Success Criteria

1. Stream shows IRC messages, Mastodon posts, and RSS items in a single unified timeline
2. Every object carries a visible provenance badge; tapping it opens the inspector
3. Library supports search across all objects and date-grouped browsing
4. Workshop manages all transports and governance defaults
5. Export produces a valid WOM Bundle
6. The app feels like a warm workshop, not a generic chat client
7. The New York serif for headlines is the memorable visual signature
8. System events render as subtle centered pills, not full rows
9. No regression in IRC connectivity, feed fetching, or Mastodon timeline
10. All existing transport configurations survive the redesign
