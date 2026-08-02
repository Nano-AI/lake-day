import SwiftUI
import UIKit

// MARK: - Palette constants (DESIGN.md hex tokens — defined in code, no asset catalog)

/// The 6 "Pastel Nature" palette colors (SchemeColor) — the ONLY pale tones used.
enum Palette {
    static let cream:  UInt = 0xF2EDDC   // Virgin Lace
    static let turq:   UInt = 0xD3EBE9   // Pastel Turquoise
    static let paper:  UInt = 0xBAD0DE   // Paper Blue
    static let tasman: UInt = 0xCADECD   // Tasman green
    static let green:  UInt = 0xDDE6CF   // Light Neutral Green
    static let gray:   UInt = 0xEEEEEE   // neutral gray
}

/// Deep tones DERIVED from the palette hues (blue/green/teal family) — the only
/// tokens dark enough for text, icons, and dark-mode surfaces. Pastels never carry text.
enum Ink {
    static let deep:      UInt = 0x26424A   // primary text / lakeInk (9.1:1 on cream)
    static let teal:      UInt = 0x3A7082   // accent / nav tint / links (4.7:1 on cream)
    static let slate:     UInt = 0x566E73   // secondary text (4.6:1 on cream)
    static let sage:      UInt = 0x5FA07B   // positive / "best day" highlight (was honey)
    static let bgDark:    UInt = 0x152A2E   // dark-mode background
    static let cardDark:  UInt = 0x1C333A   // dark-mode card
    static let textDark:  UInt = 0xE9F1EE   // dark-mode primary text
    static let subDark:   UInt = 0xA6C0C4   // dark-mode secondary text
    static let trackDark: UInt = 0x2C4C55   // dark-mode gauge track
    static let lineDark:  UInt = 0x25424A   // dark-mode hairline
}

/// Safety semantics — kept functional & distinct on purpose. Outside the pale
/// scheme by design; shape symbols back up color (color-blind floor, see SafetyPill).
enum Safety {
    static let open:    UInt = 0x3F7D61   // sage green
    static let caution: UInt = 0xA9742E   // dusty amber
    static let closed:  UInt = 0xB15140   // soft terracotta
    static let unknown: UInt = 0x74858A   // slate — never fake green
}

extension Color {

    /// 0xRRGGBB literal → Color.
    init(hex: UInt) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    // Brand tokens — "Pastel Nature" (SchemeColor): cream + soft turquoise /
    // paper-blue / green. The scheme is all-pale, so the load-bearing colors
    // (`lakeInk` text, `coldWater` accent, `sunDeck` highlight) are DERIVED as
    // deep members of the same hue family — pale grounds can't carry text.
    // RULE: pastels are fills only; anything that is text or an icon uses a
    // dark token. That is the structural cure for washed-out labels.
    static let lakeInk    = Color(hex: Ink.deep)      // deep slate-teal — text, dark base (derived)
    static let coldWater  = Color(hex: Ink.teal)      // deep teal — nav tint, links, score (derived, legible)
    static let shallows   = Color(hex: Palette.turq)  // pastel turquoise — fills, chips, card tint
    static let sunDeck    = Color(hex: Ink.sage)      // green highlight — sun / score / best-day (derived)
    static let mist       = Color(hex: Palette.cream) // cream (Virgin Lace) — light background

    // Safety states — conventional on purpose (safety semantics beat style).
    // Kept dark enough to read as small text (they double as hazard icons and
    // the smoky-air label); shape symbols carry the color-blind floor (SafetyPill).
    static let safetyOpen    = Color(hex: Safety.open)
    static let safetyCaution = Color(hex: Safety.caution)
    static let safetyClosed  = Color(hex: Safety.closed)
    static let safetyUnknown = Color(hex: Safety.unknown)

    // Adaptive surfaces. Light mode uses the palette pastels; dark mode uses the
    // deep tones derived from the same hues.
    static let appBackground = dynamic(light: Palette.cream,  dark: Ink.bgDark)     // cream / deep slate
    static let cardSurface   = dynamic(light: Palette.gray,   dark: Ink.cardDark)   // gray lifts off cream
    static let primaryText   = dynamic(light: Ink.deep,       dark: Ink.textDark)
    static let secondaryText = dynamic(light: Ink.slate,      dark: Ink.subDark)
    static let gaugeTrack    = dynamic(light: Palette.paper,  dark: Ink.trackDark)  // paper-blue track, sage arc pops
    static let hairline      = dynamic(light: Palette.tasman, dark: Ink.lineDark)

    /// Light/dark pair via a UIKit dynamic provider (no asset catalog available).
    static func dynamic(light: UInt, dark: UInt) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - Safety → color / symbol (view-layer mapping; keeps the model UI-free)

extension SafetyLevel {
    var tint: Color {
        switch self {
        case .open:    return .safetyOpen
        case .caution: return .safetyCaution
        case .closed:  return .safetyClosed
        case .unknown: return .safetyUnknown
        }
    }

    /// A shape cue in addition to color (color-blind floor).
    var symbolName: String {
        switch self {
        case .open:    return "checkmark.circle.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .closed:  return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

// MARK: - Typography (native SF; no bundled fonts)

extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Verdict headline — SF Pro Rounded Bold, 28pt.
    static let verdictHeadline = rounded(28, .bold)
    /// Lake card / detail name — 20pt rounded semibold.
    static let lakeName = rounded(20, .semibold)
    /// Section headers within detail.
    static let sectionTitle = rounded(17, .semibold)

    /// Reading numerals — 34pt rounded bold, monospaced digits so figures
    /// don't jitter as data updates (dive-watch feel).
    static let readingNumeral = rounded(34, .bold).monospacedDigit()
    /// Smaller reading numerals (card mini-gauge, day strip).
    static let readingNumeralSmall = rounded(15, .semibold).monospacedDigit()
    /// Medium reading numerals (component values, ETA).
    static let readingNumeralMedium = rounded(20, .bold).monospacedDigit()
}
