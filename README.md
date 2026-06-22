# Wirc

A native iOS app that brings together RSS feeds, YouTube channels, podcasts, Mastodon, and IRC chat into a single, curated timeline. No algorithm, no ads, no tracking — just the content you choose, presented chronologically.

## Features

- **Unified Timeline** — Mixed feed of RSS, YouTube, podcasts, Mastodon, and GitHub activity, chronologically sorted with source diversity guarantees
- **Full IRC Client** — Multi-server IRC with SASL, TLS, channel management, and conversation history
- **Mastodon Integration** — OAuth-based account management with full timeline and post history
- **Smart Curation** — 200+ curated sources, date range filters, sort options, and bookmarking
- **Share Extension** — Send any URL to Wirc from any app
- **Home Screen Widget** — See latest posts at a glance
- **Accessibility** — Dark Mode, Dynamic Type, and VoiceOver support throughout
- **Privacy First** — 100% local storage, no analytics, no tracking

## Requirements

- iOS 17.0+
- Xcode 15.0+ (for development)

## Building

```bash
cd Wirc
xcodegen generate   # Generate Xcode project from project.yml
open Wirc.xcodeproj  # Open in Xcode
```

Select the **Wirc** scheme and build for your target device or simulator.

## Project Structure

```
Wirc/
  WircApp/           # Main app target
    App/             # App entry point, state management
    Core/            # DesignSystem, theme, shared utilities
    Features/        # Feature modules (Feed, Chat, Settings, etc.)
    Models/          # Data models, persistence
    Networking/      # Feed parsing, IRC, Mastodon clients
  WircShareExtension/ # Share-to-Wirc extension
  WircWidget/        # iOS Home Screen widget
  WircTests/         # Unit tests
  AppStore/          # App Store metadata
```

## License

MIT
