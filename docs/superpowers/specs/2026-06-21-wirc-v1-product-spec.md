# Wirc v1.0 — Product Specification

> **Status:** Draft for review
> **Date:** 2026-06-21
> **Author:** Wagner Montes + Claude

---

## 1. Product Identity

### One-liner
**Wirc brings all your content together — RSS, YouTube, Podcasts, Mastodon, and IRC — in one place.**

### Elevator pitch
You follow people and sources you trust. Their content flows into a single, fast, private timeline. No algorithm. No ads. No platform. Just the stuff you asked for, from the places you chose, in an app that stays out of your way.

### Who it's for
People who consume content from multiple sources and value control over their information diet. Early adopters, developers, journalists, researchers — anyone who currently juggles 3-5 different apps for RSS, social media, podcasts, and chat.

### What it replaces
- NetNewsWire / Reeder / Feedly (RSS)
- Ivory / Mona / Mastodon app (Mastodon)
- YouTube subscriptions tab (YouTube via RSS)
- Apple Podcasts / Overcast (podcasts via RSS)
- LimeChat / Textual (IRC)

### What it doesn't do
- Algorithmic recommendations
- Ads or tracking
- Social networking (follow/unfollow other Wirc users — that's v2)
- Content creation (posting to Mastodon exists but is minimal)

---

## 2. Current State Assessment

### What's built (66 Swift files, ~9,400 lines)
| Feature | Status | Notes |
|---|---|---|
| RSS/Atom feed ingestion | ✅ Production | 200+ default feeds, conditional GET, OPML import |
| YouTube via RSS | ✅ Production | Thumbnails, channel discovery |
| Podcast via RSS | ✅ Production | Artwork, duration, episode info |
| GitHub releases via Atom | ✅ Production | Release notes, tag info |
| Mastodon home timeline | ✅ Production | REST API, Keychain tokens, pagination |
| IRC multi-server client | ✅ Production | 11 default servers, auto-join, broadcast |
| Unified WOM data model | ✅ Production | JSON file store, lazy indexes |
| Stream view (feed) | ✅ Production | Round-robin diversity, pull-to-refresh, filter bar |
| Messages view (IRC) | ✅ Production | Unified single implementation, server pills, channel tabs |
| Library view (archive) | ✅ Production | Search, date grouping, type filters |
| Settings | ✅ Production | Server/feed/account management |
| Dark Mode | ✅ Production | All DesignSystem colors support light/dark |
| Dynamic Type | ✅ Production | Text style-relative fonts |
| VoiceOver | ✅ Production | Labels, hints, text alternatives |
| Status bar (progress) | ✅ Production | Real-time feed refresh progress + summary |
| Performance | ✅ Production | O(1) indexed queries, debounced triggers, async I/O |

### What's missing for v1.0
| Feature | Priority | Effort |
|---|---|---|
| Onboarding flow | Critical | 4 hours |
| Bookmarks ("Save for later") | High | 2 hours |
| Share Extension (receive URLs) | High | 3 hours |
| Widget ("Latest 3 cards") | Medium | 2 hours |
| Feed curation (remove defaults easily) | Medium | 1 hour |
| Mastodon OAuth (no manual token) | Medium | 3 hours |
| Search: filter by date/source/type | Medium | 2 hours |
| Tests (FeedParser, Store, IRC) | Medium | 4 hours |
| App Store assets | Medium | 2 hours |

---

## 3. Target User Experience

### First launch (new user)
```
1. App opens → Welcome screen
   "Wirc brings all your content together."
   [Get Started] button

2. Tap Get Started → Brief explanation
   "We've prepared 200+ trusted sources across tech,
    news, podcasts, and video. You can customize
    everything later in Settings."
   [Continue]

3. App loads feeds → Status bar shows progress
   "Fetching 45/218 sources · 12 posts found"
   
4. Cards appear → Mixed RSS, YouTube, Podcast, GitHub
   User scrolls, taps a card → article opens in Safari
   
5. Bottom tab bar: Stream | Messages | Library | Settings
```

### Daily use (returning user)
```
1. Open app → Existing content loads instantly from disk
2. Pull to refresh → Bar shows "45/218 sources · 3 new posts"
3. Scroll feed → Mixed content from all sources
4. Tap card → Read article
5. Long-press card → Share / Copy Link / Save for later
6. Filter by source → Tap "YouTube" chip → only video cards
7. Switch to Messages → Chat on connected IRC servers
8. Switch to Library → Search archived content
```

### Key interactions
| Action | Gesture | Result |
|---|---|---|
| Open article | Tap card | Opens URL in Safari |
| Actions menu | Long-press card | Share, Copy Link, Save for Later |
| Filter feed | Tap source chip | Shows only that source |
| Refresh | Pull down | Fetches all feeds, shows progress |
| Read later | Long-press → Save | Adds to Saved list in Library |
| Share TO Wirc | Share sheet in any app | Detects feed, offers to add |

---

## 4. Architecture Decisions

### What to KEEP
- **Single @Observable AppState.** It works. No need for Redux/TCA.
- **WOM data model.** The unified object format is our differentiator.
- **JSONFileStore.** Simple, local, fast. No database needed at this scale.
- **Lazy indexed queries.** O(1) lookups, rebuilt on mutation. Proven pattern.
- **DesignSystem tokens.** Colors, fonts, spacing all centralized.

### What to CHANGE
- **Remove Workshop tab.** Move governance to Settings → Advanced. Move debug to Developer menu (hidden).
- **IRC servers: opt-in, not opt-out.** Default to NO auto-connect. Show a "Connect to IRC" prompt in Messages tab.
- **Settings as primary config surface.** Merge Workshop functionality into Settings.

### What to ADD
- **Share Extension target.** New Xcode target, minimal UI. Receives URL, detects feed, offers to add.
- **Widget Extension target.** New Xcode target. Shows 3 most recent cards.
- **Bookmark system.** WOM objects with `type: ["wom:Signal"]` and `signalType: "bookmarked"`.

---

## 5. Feature Specifications

### 5.1 Onboarding Flow
**File:** New `OnboardingView.swift` in `Features/Onboarding/`

Screen 1: Welcome
- App icon + "Wirc" title
- "All your content, one place." subtitle
- [Get Started] button

Screen 2: What to expect
- Three icons: RSS feed, Chat bubbles, Archive box
- "We've added 200+ trusted sources to get you started."
- "Customize everything in Settings."
- [Continue] button

Screen 3: (skip if Mastodon account already configured)
- "Connect your Mastodon account?"
- [Connect] / [Skip] buttons

Onboarding is shown ONCE. Controlled by `@AppStorage("wirc.onboarding.completed")`.

### 5.2 Bookmarks
**Files:** Modify `FeedCard.swift`, `LibraryView.swift`

- Long-press menu adds "Save for Later" action
- Creates WOMObject with `type: ["wom:Signal"]`, `data["signalType"] = "bookmarked"`
- Library gains a "Saved" filter option
- Swipe to remove bookmark (deletes the signal object)

### 5.3 Share Extension
**New target:** `WircShareExtension`

Minimal UI:
- Receives URL from host app (Safari, Mail, etc.)
- Calls `FeedFetcher.discoverFeed(from:)` to find RSS/Atom
- Shows feed title + "Add to Wirc" button
- On confirm: creates `FeedSubscription`, saves to shared store, shows checkmark
- Auto-dismisses after 2 seconds

### 5.4 Widget
**New target:** `WircWidget`

- iOS 17+ WidgetKit
- "Latest" widget: small (1 card), medium (3 cards)
- Shows: source icon, title, relative timestamp
- Tapping opens Wirc to Stream tab
- Refreshes every 15 minutes (iOS widget budget)

### 5.5 Feed Curation
**Files:** Modify `SettingsView.swift`, `FeedManager.swift`

- Settings → Feeds shows all subscriptions with swipe-to-delete
- "Reset to defaults" button restores DefaultFeeds.json
- "Add from OPML" file picker
- Default feeds no longer re-add on relaunch if user deleted them

### 5.6 Mastodon OAuth
**Files:** Modify `MastodonClient.swift`, `SettingsView.swift`

- Replace manual token entry with OAuth flow
- User enters instance URL → app opens Safari for OAuth authorize
- Callback URL returns token → stored in Keychain
- Remove manual token text field from UI

### 5.7 Search Enhancements
**Files:** Modify `LibraryView.swift`

- Add date range picker (last 24h, 7d, 30d, all)
- Add source type filter chips (same as Stream filter)
- Add sort options: newest, oldest, by source
- Search now includes `data["author"]` field

---

## 6. Tab Bar Redesign

### Current (5 tabs)
```
Stream | Messages | Library | Workshop | Settings
```

### Proposed (4 tabs)
```
Stream | Messages | Library | Settings
```

- **Stream:** Feed cards, filter bar, pull-to-refresh
- **Messages:** Unified IRC view (server pills, channel tabs, chat)
- **Library:** Archive with search, filters, Saved, export
- **Settings:** Server management, feed management, Mastodon accounts, governance, about, debug (hidden behind long-press on version number)

Workshop content moves:
- Governance → Settings → Advanced
- Debug tools → hidden, accessible via long-press on version number in About
- Feed/Mastodon management → already in Settings

---

## 7. What We're NOT Building (v1.0)

These are explicitly deferred:
- Nostr / Bluesky / Hacker News integration
- BLE mesh / proximity features
- Lightning / cryptocurrency payments
- Geolocation / spatial features
- Trust graph / social following
- P2P sync between devices
- Email newsletters
- iPad / macOS versions
- Notifications (push)
- iCloud sync

---

## 8. Success Criteria

### v1.0 is ready when:
- [ ] New user opens app → sees onboarding → understands what Wirc does
- [ ] Default feeds load in < 30 seconds
- [ ] User can save articles for later, find them in Library
- [ ] Share sheet works: send URL from Safari → appears in Wirc
- [ ] Widget shows recent content on home screen
- [ ] All 4 tabs have clear purpose and consistent design
- [ ] Dark Mode and Dynamic Type work everywhere
- [ ] Zero crashes in basic usage flows
- [ ] Test coverage on core data pipeline (FeedParser, JSONFileStore, IRCChannelManager)
- [ ] App Store listing has: name, icon, description, screenshots, privacy policy

---

## 9. Roadmap

### Week 1: Foundation (June 23-27)
- [ ] Onboarding flow (3 screens)
- [ ] Bookmarks (save + library integration)
- [ ] Tab bar: remove Workshop, consolidate Settings

### Week 2: Growth (June 30 - July 4)
- [ ] Share Extension
- [ ] Feed curation (delete, reset, OPML)
- [ ] Mastodon OAuth

### Week 3: Polish (July 7-11)
- [ ] Search enhancements
- [ ] Widget
- [ ] App Store assets

### Week 4: Quality (July 14-18)
- [ ] Tests (FeedParser, JSONFileStore, IRCChannelManager)
- [ ] Final dark mode audit
- [ ] Performance profiling
- [ ] Submit to App Store

---

## 10. Open Questions

1. **Name:** "Wirc" — keep it? The name suggests "wire" + "IRC" but doesn't communicate the multi-protocol nature. Consider: "Wirc" as a brand, with subtitle "RSS + IRC + Social" in the App Store.

2. **Icon:** Current icon is the default Xcode placeholder. Need a real icon. Suggestion: interlocking circles (RSS) + chat bubble + archive box, in warm orange/amber tones.

3. **Monetization:** Free for v1.0. If the app gains traction, add Wirc Premium: iCloud sync, push notifications, custom themes. $2.99/month or $19.99/year.

4. **Privacy:** No analytics for v1.0. The app is fully local. The privacy policy can honestly say: "We collect nothing. Your data stays on your device."

5. **TestFlight:** Before App Store, run a TestFlight beta with 10-20 users. Collect feedback on onboarding clarity and crash reports.
