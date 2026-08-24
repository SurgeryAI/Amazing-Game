import SwiftUI
import UIKit

/// Orb palettes.
///
/// Deliberately cosmetic-only: a theme changes fill and glow colours and
/// nothing else — no radius, mass, score, or spawn behaviour. That is what
/// makes them safe to sell and safe to hand out for watching an ad. A player
/// who has every theme has exactly the same game as a player who has none.
enum OrbTheme: String, CaseIterable, Codable, Identifiable {
    case classic
    case aurora
    case ember
    case mono
    case candy
    case voidfall

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic:  return "Classic"
        case .aurora:   return "Aurora"
        case .ember:    return "Ember"
        case .mono:     return "Monochrome"
        case .candy:    return "Sugar Nebula"
        case .voidfall: return "Deep Void"
        }
    }

    var blurb: String {
        switch self {
        case .classic:  return "The cosmos as it was first observed."
        case .aurora:   return "Polar light, folded into matter."
        case .ember:    return "A universe still cooling from the forge."
        case .mono:     return "Everything reduced to light and shadow."
        case .candy:    return "Physics, but sweeter."
        case .voidfall: return "What is left when the stars go out."
        }
    }

    /// Cost in Star Shards. Classic is always owned.
    var cost: Int {
        switch self {
        case .classic:  return 0
        case .aurora:   return 6
        case .mono:     return 10
        case .ember:    return 15
        case .candy:    return 22
        case .voidfall: return 30
        }
    }

    // MARK: - Palettes
    //
    // Index order matches CelestialTier.rawValue:
    // 0 dust, 1 meteor, 2 moon, 3 planet, 4 gasGiant, 5 star, 6 blackHole, 7 antimatter

    private var fills: [UIColor] {
        switch self {
        case .classic:
            return [rgb(174, 174, 178), rgb(162, 132, 94), rgb(200, 200, 205),
                    rgb(64, 200, 224), rgb(175, 82, 222), rgb(255, 214, 10),
                    rgb(8, 8, 12), rgb(255, 69, 58)]
        case .aurora:
            return [rgb(190, 226, 214), rgb(96, 178, 156), rgb(214, 245, 232),
                    rgb(56, 214, 178), rgb(86, 150, 232), rgb(150, 255, 208),
                    rgb(6, 16, 20), rgb(255, 92, 168)]
        case .ember:
            return [rgb(224, 196, 160), rgb(176, 96, 48), rgb(246, 214, 176),
                    rgb(232, 128, 48), rgb(196, 52, 52), rgb(255, 196, 74),
                    rgb(18, 6, 4), rgb(120, 232, 255)]
        case .mono:
            return [rgb(120, 120, 124), rgb(160, 160, 166), rgb(200, 200, 206),
                    rgb(228, 228, 234), rgb(248, 248, 252), rgb(255, 255, 255),
                    rgb(4, 4, 6), rgb(88, 224, 255)]
        case .candy:
            return [rgb(255, 224, 236), rgb(255, 176, 196), rgb(196, 226, 255),
                    rgb(150, 208, 255), rgb(196, 168, 255), rgb(255, 236, 150),
                    rgb(38, 22, 48), rgb(255, 108, 132)]
        case .voidfall:
            return [rgb(72, 84, 116), rgb(58, 68, 104), rgb(96, 112, 156),
                    rgb(70, 128, 196), rgb(104, 88, 208), rgb(150, 176, 255),
                    rgb(2, 2, 6), rgb(255, 78, 120)]
        }
    }

    private var glows: [UIColor] {
        switch self {
        case .classic:
            return [.lightGray, .orange, .white, .cyan, .magenta, .yellow, .purple, .red]
        case .aurora:
            return [rgb(200, 255, 236), rgb(120, 232, 190), rgb(236, 255, 248),
                    rgb(64, 255, 208), rgb(120, 190, 255), rgb(190, 255, 226),
                    rgb(96, 255, 210), rgb(255, 120, 190)]
        case .ember:
            return [rgb(255, 226, 190), rgb(255, 150, 70), rgb(255, 238, 210),
                    rgb(255, 168, 60), rgb(255, 96, 72), rgb(255, 226, 130),
                    rgb(255, 120, 40), rgb(150, 246, 255)]
        case .mono:
            return [rgb(190, 190, 196), .white, .white, .white, .white, .white,
                    rgb(150, 150, 160), rgb(120, 236, 255)]
        case .candy:
            return [rgb(255, 236, 244), rgb(255, 196, 214), rgb(214, 238, 255),
                    rgb(176, 224, 255), rgb(214, 190, 255), rgb(255, 246, 186),
                    rgb(196, 130, 255), rgb(255, 140, 164)]
        case .voidfall:
            return [rgb(130, 150, 200), rgb(110, 130, 190), rgb(150, 172, 220),
                    rgb(110, 176, 255), rgb(150, 130, 255), rgb(190, 214, 255),
                    rgb(120, 96, 255), rgb(255, 110, 150)]
        }
    }

    func fillUIColor(for tier: CelestialTier) -> UIColor {
        let list = fills
        let i = max(0, min(list.count - 1, tier.rawValue))
        return list[i]
    }

    func fillColor(for tier: CelestialTier) -> Color {
        Color(uiColor: fillUIColor(for: tier))
    }

    func glowUIColor(for tier: CelestialTier) -> UIColor {
        let list = glows
        let i = max(0, min(list.count - 1, tier.rawValue))
        return list[i]
    }

    /// Five swatches used for the store preview row.
    var previewColors: [Color] {
        [CelestialTier.dust, .moon, .planet, .gasGiant, .star].map { fillColor(for: $0) }
    }

    private func rgb(_ r: Double, _ g: Double, _ b: Double) -> UIColor {
        UIColor(red: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: 1.0)
    }
}
