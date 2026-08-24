import Foundation
import SwiftUI

/// What a mission asks of the player.
enum MissionKind: String, Codable, CaseIterable {
    case score          // reach N points in a single run
    case mergeTier      // create N bodies of a given tier
    case combo          // reach an Nx combo
    case merges         // perform N merges total today
    case antimatter     // trigger N antimatter detonations
    case bigCrunch      // annihilate N pairs of black holes
    case playDaily      // finish today's Daily Challenge
}

struct Mission: Codable, Identifiable, Equatable {
    var kind: MissionKind
    var param: Int          // tier index for `.mergeTier`; unused otherwise
    var target: Int
    var progress: Int
    var rewarded: Bool      // shards already credited

    var id: String { "\(kind.rawValue)-\(param)-\(target)" }
    var isComplete: Bool { progress >= target }
    var fraction: Double {
        guard target > 0 else { return 0 }
        return min(1.0, Double(progress) / Double(target))
    }

    var reward: Int {
        switch kind {
        case .playDaily:  return 5
        case .bigCrunch:  return 5
        case .combo:      return 4
        case .mergeTier:  return 4
        case .antimatter: return 3
        case .score:      return 3
        case .merges:     return 3
        }
    }

    var title: String {
        switch kind {
        case .score:
            return "Score \(target) in one run"
        case .mergeTier:
            let name = CelestialTier(rawValue: param)?.displayName ?? "body"
            return target == 1 ? "Create a \(name)" : "Create \(target) \(name)s"
        case .combo:
            return "Reach a \(target)x combo"
        case .merges:
            return "Merge \(target) bodies today"
        case .antimatter:
            return target == 1 ? "Detonate antimatter" : "Detonate antimatter \(target) times"
        case .bigCrunch:
            return target == 1 ? "Trigger a Big Crunch" : "Trigger \(target) Big Crunches"
        case .playDaily:
            return "Finish today's Daily Challenge"
        }
    }

    var symbolName: String {
        switch kind {
        case .score:      return "number"
        case .mergeTier:  return "circle.circle.fill"
        case .combo:      return "flame.fill"
        case .merges:     return "arrow.triangle.merge"
        case .antimatter: return "burst.fill"
        case .bigCrunch:  return "circle.hexagongrid.fill"
        case .playDaily:  return "calendar"
        }
    }
}

/// What one run produced. Accumulated in memory during play and applied to
/// persistent progress exactly once, at game over — so a 40-merge run does not
/// write to UserDefaults 40 times or churn SwiftUI 40 times.
struct RunStats {
    var merges: Int = 0
    var maxCombo: Int = 0
    var tierCounts: [Int: Int] = [:]
    var antimatterDetonations: Int = 0
    var bigCrunches: Int = 0
    var finalScore: Int = 0
    var wasAssisted: Bool = false
    var isDaily: Bool = false

    mutating func recordMerge(resultTier: Int?, combo: Int) {
        merges += 1
        maxCombo = max(maxCombo, combo)
        if let t = resultTier { tierCounts[t, default: 0] += 1 }
    }
}

// MARK: - Daily mission generation

enum MissionFactory {

    /// Three missions per day, derived from the date so they are the same for
    /// everyone and stable across relaunches. One is always the Daily
    /// Challenge itself, which is what ties missions to the return hook.
    static func missions(forDateKey key: String) -> [Mission] {
        var rng = SeededGenerator(seed: stableHash("gravitycascade.missions.\(key)"))

        var pool: [Mission] = [
            Mission(kind: .score, param: 0, target: pick([600, 900, 1200, 1800], &rng), progress: 0, rewarded: false),
            Mission(kind: .merges, param: 0, target: pick([25, 40, 60], &rng), progress: 0, rewarded: false),
            Mission(kind: .combo, param: 0, target: pick([3, 4, 5], &rng), progress: 0, rewarded: false),
            Mission(kind: .mergeTier, param: CelestialTier.planet.rawValue, target: pick([2, 3, 4], &rng), progress: 0, rewarded: false),
            Mission(kind: .mergeTier, param: CelestialTier.gasGiant.rawValue, target: pick([1, 2], &rng), progress: 0, rewarded: false),
            Mission(kind: .mergeTier, param: CelestialTier.star.rawValue, target: 1, progress: 0, rewarded: false),
            Mission(kind: .antimatter, param: 0, target: pick([1, 2], &rng), progress: 0, rewarded: false)
        ]

        var chosen: [Mission] = [
            Mission(kind: .playDaily, param: 0, target: 1, progress: 0, rewarded: false)
        ]

        // Two more, distinct by kind so the list never reads as repetitive.
        var usedKinds: Set<MissionKind> = [.playDaily]
        while chosen.count < 3 && !pool.isEmpty {
            let index = Int(rng.next() % UInt64(pool.count))
            let candidate = pool.remove(at: index)
            if usedKinds.contains(candidate.kind) { continue }
            usedKinds.insert(candidate.kind)
            chosen.append(candidate)
        }

        // Defensive: if the distinct-kind filter starved the list, top it up.
        while chosen.count < 3 {
            chosen.append(Mission(kind: .merges, param: 0, target: 30, progress: 0, rewarded: false))
        }

        return chosen
    }

    private static func pick(_ options: [Int], _ rng: inout SeededGenerator) -> Int {
        guard !options.isEmpty else { return 1 }
        return options[Int(rng.next() % UInt64(options.count))]
    }
}
