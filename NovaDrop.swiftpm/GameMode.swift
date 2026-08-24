import Foundation
import CoreGraphics

// MARK: - Deterministic randomness

/// SplitMix64 — small, fast, and (critically) *reproducible*.
///
/// The Daily Challenge only works if every player on Earth gets the identical
/// drop sequence, so the scene has to be able to run on a seeded stream instead
/// of the system generator. Swift's built-in hashing is seeded per-process and
/// must never be used to derive the daily seed.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Avoid the degenerate all-zero state.
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// FNV-1a. Stable across launches and OS versions, unlike `String.hashValue`.
func stableHash(_ string: String) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100000001b3
    }
    return hash
}

// MARK: - Modes

enum GameMode: Equatable {
    case endless
    case daily(dateKey: String)

    var isDaily: Bool {
        if case .daily = self { return true }
        return false
    }

    var title: String {
        switch self {
        case .endless: return "ENDLESS"
        case .daily:   return "DAILY CHALLENGE"
        }
    }

    /// `nil` for Endless, which uses the system generator.
    var seed: UInt64? {
        switch self {
        case .endless: return nil
        case .daily(let key): return stableHash("gravitycascade.daily.\(key)")
        }
    }
}

// MARK: - Daily modifiers

/// One rule twist per day. This is the reason to open the app tomorrow even
/// after a good run today: the challenge is not merely a new seed, it is a
/// different game. Each modifier is a small parameter change to the existing
/// systems — nothing here introduces a new code path that can desync a run.
enum DailyModifier: Int, CaseIterable {
    case standard
    case magneticStorm
    case heavyGravity
    case calmVoid
    case denseCosmos
    case volatile

    var title: String {
        switch self {
        case .standard:      return "Open Space"
        case .magneticStorm: return "Magnetic Storm"
        case .heavyGravity:  return "Heavy Gravity"
        case .calmVoid:      return "The Calm Void"
        case .denseCosmos:   return "Dense Cosmos"
        case .volatile:      return "Volatile Matter"
        }
    }

    var blurb: String {
        switch self {
        case .standard:      return "No twists. Pure skill."
        case .magneticStorm: return "Every body carries a charge."
        case .heavyGravity:  return "Everything falls harder and faster."
        case .calmVoid:      return "No charges at all. Just merging."
        case .denseCosmos:   return "Bigger bodies from the very first drop."
        case .volatile:      return "Unstable orbs everywhere. Drop fast."
        }
    }

    var symbolName: String {
        switch self {
        case .standard:      return "circle.dashed"
        case .magneticStorm: return "bolt.fill"
        case .heavyGravity:  return "arrow.down.circle.fill"
        case .calmVoid:      return "moon.stars.fill"
        case .denseCosmos:   return "circle.grid.3x3.fill"
        case .volatile:      return "exclamationmark.triangle.fill"
        }
    }

    // MARK: Tuning knobs consumed by GameScene

    /// Downward gravity for this modifier.
    var gravityY: CGFloat { self == .heavyGravity ? -15.0 : -9.8 }

    /// Percent chance (0–100) that a spawned body carries a charge.
    var chargeChance: Int {
        switch self {
        case .magneticStorm: return 100
        case .calmVoid:      return 0
        default:             return 50
        }
    }

    /// Percent chance (0–100) that a spawned body is unstable.
    var unstableChance: Int { self == .volatile ? 32 : 15 }

    /// Added to the maximum tier that can be rolled for a fresh drop.
    var startTierBonus: Int { self == .denseCosmos ? 1 : 0 }
}

// MARK: - Daily challenge

struct DailyChallenge {
    let dateKey: String
    let modifier: DailyModifier

    var mode: GameMode { .daily(dateKey: dateKey) }

    /// Today's challenge, in the player's own time zone.
    static func today(now: Date = Date()) -> DailyChallenge {
        let key = DailyChallenge.dateKey(for: now)
        return DailyChallenge(dateKey: key, modifier: modifier(forDateKey: key))
    }

    static func dateKey(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    static func modifier(forDateKey key: String) -> DailyModifier {
        var rng = SeededGenerator(seed: stableHash("gravitycascade.modifier.\(key)"))
        let all = DailyModifier.allCases
        let index = Int(rng.next() % UInt64(all.count))
        return all[index]
    }

    /// Human-readable countdown to the next challenge.
    static func timeUntilNextChallenge(now: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: now),
              let midnight = cal.dateInterval(of: .day, for: tomorrow)?.start else {
            return "—"
        }
        let seconds = Int(midnight.timeIntervalSince(now))
        guard seconds > 0 else { return "now" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
