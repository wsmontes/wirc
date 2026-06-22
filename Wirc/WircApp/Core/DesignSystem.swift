import os.log
import SwiftUI

/// Central design token system for Wirc.
/// Warm archival palette + New York serif display + SF Mono data.
enum DesignSystem {

    // MARK: - Color Tokens

    enum Colors {
        /// Warm paper background
        static let page = Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(hex: "1C1917")
                : UIColor(hex: "F6F3ED")
        })
        /// Cards, bubbles, elevated surfaces
        static let surface = Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(hex: "292524")
                : UIColor.white
        })
        /// Primary text -- near-black with warmth
        static let ink = Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(hex: "F6F3ED")
                : UIColor(hex: "1C1917")
        })
        /// Secondary text, captions, metadata
        static let pencil = Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(hex: "B8B0A8")
                : UIColor(hex: "615E5A")
        })
        /// Hairline rules, dividers
        static let border = Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(hex: "44403C")
                : UIColor(hex: "E7E5E2")
        })

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
        /// Display serif for headlines -- New York (fixed size, does not scale)
        static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .serif)
        }

        /// Headline sans -- SF Pro (scales with Dynamic Type)
        static func headline(_ size: CGFloat = 17) -> Font {
            .system(size: size, weight: .semibold, design: .default)
        }

        /// Body sans for messages and descriptions -- SF Pro (scales with Dynamic Type)
        static func body(_ size: CGFloat = 15) -> Font {
            .system(size: size, weight: .regular, design: .default)
        }

        /// For code/debug text (fixed size acceptable) -- SF Mono
        static func mono(_ size: CGFloat = 12) -> Font {
            .system(size: size, weight: .regular, design: .monospaced)
        }

        /// Data for UI metadata (fixed size acceptable)
        static func data(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .default)
        }

        // Pre-built sizes from spec -- text style-relative for Dynamic Type

        static let headlineLarge = display(20)

        // Text style-relative fonts (scale with Dynamic Type)
        static let senderName: Font = .system(.subheadline, weight: .bold)
        static let messageBody: Font = .body
        static let cardBody: Font = .body
        static let caption: Font = .caption
        static let chipLabel: Font = .system(.subheadline, design: .default)
        static let provenanceLabel: Font = .caption
        static let provenanceDetail: Font = .caption2
        static let timestamp: Font = .caption2
        static let footer: Font = .caption2
        static let systemEvent: Font = .caption2
        static let dateHeader: Font = .subheadline
        static let badge: Font = .caption2
    }
}

// MARK: - Color Hex Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6, let int = UInt64(hex, radix: 16) else {
            os_log(.error, "DesignSystem: invalid hex color '%{public}@', falling back to black", hex)
            self = .black
            return
        }
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

extension UIColor {
    convenience init(hex: String) {
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
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: 1.0
        )
    }
}
