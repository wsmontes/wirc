import SwiftUI

/// Central design token system for Wirc.
/// Warm archival palette + New York serif display + SF Mono data.
enum DesignSystem {

    // MARK: - Color Tokens

    enum Colors {
        /// Warm paper background
        static let page = Color(hex: "F6F3ED")
        /// Cards, bubbles, elevated surfaces
        static let surface = Color.white
        /// Primary text -- near-black with warmth
        static let ink = Color(hex: "1C1917")
        /// Secondary text, captions, metadata
        static let pencil = Color(hex: "78716C")
        /// Hairline rules, dividers
        static let border = Color(hex: "E7E5E2")

        /// Primary accent -- actions, IRC source, selected states
        static let signal = Color(hex: "E85D3A")
        /// Mastodon source badge
        static let mastodon = Color(hex: "6366F1")
        /// RSS source badge
        static let rss = Color(hex: "D97706")
        /// GitHub source badge
        static let github = Color(hex: "059669")
        /// Podcast source badge
        static let podcast = Color(hex: "7C3AED")
        /// YouTube source badge
        static let youtube = Color(hex: "DC2626")
        /// IRC source badge (uses signal)
        static let irc = signal

        /// Returns the source color for a given network string.
        static func forSource(_ network: String) -> Color {
            switch network.lowercased() {
            case "irc": return irc
            case "mastodon": return mastodon
            case "rss": return rss
            case "github": return github
            case "podcast": return podcast
            case "youtube": return youtube
            default: return pencil
            }
        }
    }

    // MARK: - Spacing Scale

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    // MARK: - Border Radius

    enum Radius {
        static let card: CGFloat = 12
        static let bubble: CGFloat = 14
        static let chip: CGFloat = 8
        static let sheet: CGFloat = 16
        static let badge: CGFloat = 6
        static let thumbnail: CGFloat = 8
    }

    // MARK: - Typography

    enum Fonts {
        /// Display serif for headlines -- New York
        static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .serif)
        }

        /// Body sans for messages and descriptions -- SF Pro
        static func body(_ size: CGFloat = 15) -> Font {
            .system(size: size, weight: .regular, design: .default)
        }

        /// Data mono for nicks, channels, timestamps -- SF Mono
        static func data(_ size: CGFloat = 11, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }

        /// Caption for footer text and chips -- SF Pro Medium
        static func caption(_ size: CGFloat = 12) -> Font {
            .system(size: size, weight: .medium, design: .default)
        }

        // Pre-built sizes from spec

        static let headline = display(17)
        static let headlineLarge = display(20)
        static let senderName = data(13, weight: .bold)
        static let provenanceLabel = data(11, weight: .bold)
        static let provenanceDetail = data(11)
        static let timestamp = data(11)
        static let footer = data(11)
        static let systemEvent = data(11)
        static let messageBody = body(15)
        static let cardBody = body(15)
        static let chipLabel = caption(12)
        static let dateHeader = data(12)
    }
}

// MARK: - Color Hex Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255
        )
    }
}
