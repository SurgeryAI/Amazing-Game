import SwiftUI
import SpriteKit

enum Polarity: Int {
    case neutral = 0
    case positive = 1
    case negative = 2

    var symbol: String {
        switch self {
        case .neutral:  return ""
        case .positive: return "+"
        case .negative: return "−"
        }
    }

    var uiColor: UIColor {
        switch self {
        case .neutral:  return .clear
        case .positive: return UIColor(red: 0.30, green: 0.85, blue: 1.00, alpha: 1)
        case .negative: return UIColor(red: 1.00, green: 0.62, blue: 0.20, alpha: 1)
        }
    }

    var color: Color { Color(uiColor: uiColor) }
}

enum CelestialTier: Int, CaseIterable {
    case dust = 0
    case meteor
    case moon
    case planet
    case gasGiant
    case star
    case blackHole
    case antimatter

    var displayName: String {
        switch self {
        case .dust:       return "Dust"
        case .meteor:     return "Meteor"
        case .moon:       return "Moon"
        case .planet:     return "Planet"
        case .gasGiant:   return "Gas Giant"
        case .star:       return "Star"
        case .blackHole:  return "Black Hole"
        case .antimatter: return "Antimatter"
        }
    }

    var radius: CGFloat {
        switch self {
        case .dust: return 15
        case .meteor: return 22
        case .moon: return 30
        case .planet: return 42
        case .gasGiant: return 58
        case .star: return 80
        case .blackHole: return 110
        case .antimatter: return 20
        }
    }

    var mass: CGFloat {
        switch self {
        case .dust: return 1.0
        case .meteor: return 2.0
        case .moon: return 4.0
        case .planet: return 8.0
        case .gasGiant: return 16.0
        case .star: return 32.0
        case .blackHole: return 64.0
        case .antimatter: return 5.0
        }
    }

    // MARK: - Appearance
    //
    // Colours are resolved through the player's active cosmetic theme. Themes
    // change nothing but colour — radius, mass, score and behaviour above are
    // deliberately outside their reach.

    var color: Color {
        ProgressManager.shared.activeTheme.fillColor(for: self)
    }

    var uiColor: UIColor {
        ProgressManager.shared.activeTheme.fillUIColor(for: self)
    }

    var glowColor: UIColor {
        ProgressManager.shared.activeTheme.glowUIColor(for: self)
    }

    var gradient: RadialGradient {
        RadialGradient(
            gradient: Gradient(colors: [Color.white.opacity(0.55), color.opacity(0.85), color]),
            center: UnitPoint(x: 0.35, y: 0.30),
            startRadius: radius * 0.05,
            endRadius: radius
        )
    }

    var scoreValue: Int {
        if self == .antimatter { return 0 }
        return Int(pow(2.0, Double(self.rawValue))) * 10
    }

    var standardGlowWidth: CGFloat {
        switch self {
        case .dust:      return 5
        case .meteor:    return 6
        case .moon:      return 8
        case .planet:    return 10
        case .gasGiant:  return 12
        case .star:      return 14
        case .blackHole: return 22
        case .antimatter: return 10
        }
    }

    var nextTier: CelestialTier? {
        if self == .blackHole || self == .antimatter { return nil }
        return CelestialTier(rawValue: self.rawValue + 1)
    }

    /// Tiers that can appear as a fresh drop. Black holes and antimatter are
    /// earned, never dealt (antimatter has its own rare roll).
    static var droppableTiers: [CelestialTier] {
        [.dust, .meteor, .moon, .planet, .gasGiant]
    }
}
