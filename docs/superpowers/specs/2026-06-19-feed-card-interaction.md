# Feed Card Interaction — Design Spec

**Status:** approved | **Date:** 2026-06-19 | **Version:** 1.0

## Overview

Make feed cards interactive: tap to expand inline with full content, action buttons
(Open, Share, Bookmark, Copy Link), and collapsible WOM metadata. Each source type
(RSS, Mastodon, YouTube, Podcast, GitHub) has a distinct visual identity.

## 1. Two states per card

### Collapsed (normal feed view)
- Provenance badge + source-colored hairline
- Headline (New York serif, if present)
- Author/source line
- Body preview (3 lines max for articles, 2 for other types)
- Footer with source name
- Media thumbnail (YouTube 120×68, Podcast 64×64)

### Expanded (tap to reveal)
- Same header as collapsed
- Full content (no line limit)
- Full-size media (YouTube 16:9 full width, Mastodon images full width)
- Action buttons row: Open, Share, Bookmark, Copy Link
- Collapsible WOM section: Origin, Governance, Transport Binding

## 2. Action buttons

| Action | SF Symbol | Implementation |
|--------|-----------|----------------|
| Open | `safari` | `UIApplication.shared.open(url)` |
| Share | `square.and.arrow.up` | `UIActivityViewController` with URL |
| Bookmark | `bookmark` | Creates WOM signal (stub: copy link feedback) |
| Copy Link | `doc.on.doc` | `UIPasteboard.general.string = url` |

## 3. Files

Modify: `Features/Feed/FeedCard.swift` — add `@State private var isExpanded = false`, expand/collapse animation, action buttons, WOM section.

## 4. Success Criteria

1. Tap card → expands inline with spring animation
2. Tap again or tap another card → collapses
3. Action buttons visible in expanded state
4. Open launches browser
5. Share opens iOS share sheet
6. Each source type retains distinct visual identity
