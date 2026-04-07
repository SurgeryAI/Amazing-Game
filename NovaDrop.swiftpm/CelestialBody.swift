import SwiftUI
import SpriteKit

enum CelestialTier: Int, CaseIterable {
    case dust = 0
    case meteor
    case moon
    case planet
    case gasGiant
    case star
    case blackHole

    var radius: CGFloat {
        switch self {
        case .dust: return 15
        case .meteor: return 25
        case .moon: return 38
        case .planet: return 55
        case .gasGiant: return 75
        case .star: return 100
        case .blackHole: return 130
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
        }
    }

    var color: Color {
        switch self {
        case .dust: return Color(uiColor: .systemGray2)
        case .meteor: return Color(uiColor: .systemBrown)
        case .moon: return Color(uiColor: .lightGray)
        case .planet: return Color(uiColor: .systemTeal)
        case .gasGiant: return Color(uiColor: .systemPurple)
        case .star: return Color(uiColor: .systemYellow)
        case .blackHole: return Color(uiColor: .black)
        }
    }
    
    var glowColor: UIColor {
        switch self {
        case .dust: return .lightGray
        case .meteor: return .orange
        case .moon: return .white
        case .planet: return .cyan
        case .gasGiant: return .magenta
        case .star: return .yellow
        case .blackHole: return .purple
        }
    }

    var scoreValue: Int {
        return Int(pow(2.0, Double(self.rawValue))) * 10
    }

    var nextTier: CelestialTier? {
        return CelestialTier(rawValue: self.rawValue + 1)
    }
}
