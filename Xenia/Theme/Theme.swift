//
//  Theme.swift
//  Xenia
//
//  The "Instrument" design language: true neutral greys, high contrast in both
//  appearances, one amber accent, monospaced figures, a strict spacing grid,
//  and hairline rules instead of shadows or fills for structure.
//

import SwiftUI

// MARK: - Color

extension Color {
    init(hex: UInt) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// A color that resolves differently in light and dark appearance.
    static func adaptive(light: UInt, dark: UInt) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark))
                : UIColor(Color(hex: light))
        })
    }
}

enum Palette {
    /// App canvas.
    static let ground = Color.adaptive(light: 0xF3F3F1, dark: 0x0D0D0D)
    /// Raised panels and rows.
    static let panel = Color.adaptive(light: 0xFFFFFF, dark: 0x1A1A1A)
    /// Recessed wells: text fields, steppers, the readout body.
    static let well = Color.adaptive(light: 0xEBEBE8, dark: 0x070707)

    /// Primary text and figures. Contrast on `ground`: ~15:1 light, ~16:1 dark.
    static let ink = Color.adaptive(light: 0x161615, dark: 0xF1F1EF)
    /// Supporting text. Contrast on `ground`: ~5.3:1 light, ~7:1 dark.
    static let inkDim = Color.adaptive(light: 0x656562, dark: 0xA2A29E)
    /// Faint text: placeholders, disabled. Use only for non-essential content.
    static let inkFaint = Color.adaptive(light: 0x97978F, dark: 0x6C6C68)

    /// Hairline rules and dividers.
    static let rule = Color.adaptive(light: 0xD9D9D4, dark: 0x2B2B2B)
    /// A heavier rule for emphasis (readout frame, section splits).
    static let ruleStrong = Color.adaptive(light: 0x161615, dark: 0xF1F1EF)

    /// The single accent. Used as a fill under `onAccent`, or as a 3px marker.
    static let accent = Color.adaptive(light: 0xE8A317, dark: 0xF0AE28)
    /// Text/icons sitting on an `accent` fill.
    static let onAccent = Color(hex: 0x1A1400)
    /// Amber as readable text on `ground`/`panel` (the fill amber is too light).
    static let accentText = Color.adaptive(light: 0x9A6A05, dark: 0xF0AE28)

    /// Negative adjustments. Kept muted so amber stays the only loud color.
    static let negative = Color.adaptive(light: 0xBC5240, dark: 0xE6A493)
    /// Solid red behind white — the swipe-to-delete action.
    static let destructive = Color.adaptive(light: 0xD22F2F, dark: 0xE5484D)
}

// MARK: - Spacing grid

/// One scale, used everywhere. No ad-hoc paddings.
enum Grid {
    static let x1: CGFloat = 4
    static let x2: CGFloat = 8
    static let x3: CGFloat = 12
    static let x4: CGFloat = 16
    static let x5: CGFloat = 20
    static let x6: CGFloat = 24
    static let x8: CGFloat = 32
    static let x12: CGFloat = 48

    /// Height of the custom `InstrumentTabBar` content that sits above the home
    /// indicator. `InstrumentScreen` / `InstrumentList` add this to their scroll
    /// bottom padding because the parent `.safeAreaInset` on the `TabView` does
    /// not propagate through their nested `NavigationStack`.
    static let tabBar: CGFloat = 54
}

enum Corner {
    static let panel: CGFloat = 14
    static let control: CGFloat = 10
    static let chip: CGFloat = 8
}

// MARK: - Type

extension Font {
    /// Big instrument readout (the tip percent, headline amounts).
    static let readout = Font.system(size: 46, weight: .semibold, design: .monospaced)
    static let readoutMid = Font.system(size: 24, weight: .semibold, design: .monospaced)
    /// Any figure in a table or row: aligned, tabular, monospaced.
    static let figure = Font.system(.body, design: .monospaced).weight(.medium)
    static let figureSmall = Font.system(.footnote, design: .monospaced)
    /// Prose that isn't a figure or a label: hints, descriptions, footnotes.
    static let noteText = Font.system(.footnote)
    /// Screen titles (SF Pro, not mono).
    static let screenTitle = Font.system(size: 30, weight: .bold)
    static let cardTitle = Font.system(.headline)
    static let bodyText = Font.system(.subheadline)
}

extension View {
    /// Ledger-style section label: small, uppercase, tracked, dim.
    func sectionLabelStyle() -> some View {
        self
            .font(.system(.caption2, weight: .semibold))
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(Palette.inkDim)
    }
}

// MARK: - Environment: appearance-locked accent

extension View {
    /// Apply Xenia's global tint and background. Put on the root.
    func instrumentChrome() -> some View {
        self.tint(Palette.accentText)
    }
}
