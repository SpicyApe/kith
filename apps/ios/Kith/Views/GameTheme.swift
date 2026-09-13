// GameTheme.swift — the games-hub design tokens (docs/08-visual-design.md). One `Theme`
// enum, colours built dynamic light/dark, plus the Stars region palette and the
// game→colour lookups the hub, host chrome and results screens all share.
//
// This file is deliberately separate from `Views/Shared/Theme.swift` (the older
// onboarding/Lineup colours and button styles); nothing here renames or removes those.

import Foundation
import GridGames
import SwiftUI
import UIKit

enum Theme {
    // MARK: Hex helper

    /// `"#RRGGBB"` (leading `#` optional) → `Color`. Traps on a malformed literal — every
    /// call site here passes a compile-time constant from the tokens table.
    static func hex(_ string: String) -> Color {
        var value = string
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else {
            assertionFailure("Theme.hex: malformed literal \(string)")
            return Color.black
        }
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }

    /// Builds a dynamic `Color` from a light/dark pair of hex literals.
    private static func dynamic(light: String, dark: String) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(Theme.hex(dark)) : UIColor(Theme.hex(light))
        })
    }

    // MARK: Tokens

    static let ink = dynamic(light: "#1C1C1E", dark: "#F2F2F7")
    static let paper = dynamic(light: "#FFFFFF", dark: "#1C1C1E")
    static let paperMuted = dynamic(light: "#EFEFF3", dark: "#2C2C2E")
    static let danger = dynamic(light: "#D9342B", dark: "#FF6B5E")
    static let dangerWash = dynamic(light: "#FFE3E0", dark: "#4A2622")
    static let lineup = dynamic(light: "#3B6FE0", dark: "#6C93F2")
    static let stars = dynamic(light: "#6E56CF", dark: "#9B86F0")
    static let duo = dynamic(light: "#F5A524", dark: "#F7B955")
    static let duoAlt = dynamic(light: "#4C5BD4", dark: "#7C8AF0")
    static let trail = dynamic(light: "#1F9E89", dark: "#3FC3AC")
    static let quint = dynamic(light: "#C8377B", dark: "#E85D9B")

    // MARK: Geometry

    static let cardRadius: CGFloat = 14
    static let pillRadius: CGFloat = 10
    static let boardRadius: CGFloat = 10

    // MARK: Stars region palette

    /// Ten opaque region fills, distinct hue and lightness, with a dark-mode twin each.
    private static let regionFills: [Color] = [
        dynamic(light: "#C9B8F0", dark: "#4E3F7A"), // 0 lavender
        dynamic(light: "#FFC9A3", dark: "#7A4A2A"), // 1 peach
        dynamic(light: "#A9CFFF", dark: "#2C4A78"), // 2 sky
        dynamic(light: "#B5E8B0", dark: "#2E5E33"), // 3 mint
        dynamic(light: "#F3EC8E", dark: "#6B6320"), // 4 lemon
        dynamic(light: "#F5B3C8", dark: "#7A3A52"), // 5 rose
        dynamic(light: "#D9CBA8", dark: "#5A5040"), // 6 sand
        dynamic(light: "#9EDCE0", dark: "#23575C"), // 7 aqua
        dynamic(light: "#FF9C8A", dark: "#7A3A30"), // 8 coral
        dynamic(light: "#CFD4DC", dark: "#4A5060"), // 9 slate
    ]

    /// The region fill for region `index`, wrapping every 10.
    static func region(_ index: Int) -> Color {
        regionFills[((index % regionFills.count) + regionFills.count) % regionFills.count]
    }

    // MARK: Game colours

    static func color(for kind: GameKind) -> Color {
        switch kind {
        case .stars: return stars
        case .duo: return duo
        case .trail: return trail
        case .quint: return quint
        }
    }

    static func color(for game: HubGame) -> Color {
        switch game {
        case .lineup: return lineup
        case .grid(let kind): return color(for: kind)
        }
    }
}
