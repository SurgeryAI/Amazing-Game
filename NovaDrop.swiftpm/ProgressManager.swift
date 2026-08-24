import Foundation
import Combine
import SwiftUI

/// Everything the player keeps between runs: shards, themes, streak, missions.
///
/// This is the layer that makes a *losing* run still worth something. In the
/// original build a bad run produced nothing at all, which is the single
/// biggest reason players stop opening a score-chase game.
final class ProgressManager: ObservableObject {

    static let shared = ProgressManager()

    private enum Key {
        static let shards = "ProgShards"
        static let owned = "ProgOwnedThemes"
        static let active = "ProgActiveTheme"
        static let missions = "ProgMissions"
        static let missionsDate = "ProgMissionsDate"
        static let streak = "ProgStreak"
        static let bestStreak = "ProgBestStreak"
        static let lastDailyKey = "ProgLastDailyKey"
        static let recoverableStreak = "ProgRecoverableStreak"
        static let recoverableOn = "ProgRecoverableOn"
        static let adShardDate = "ProgAdShardDate"
        static let adShardCount = "ProgAdShardCount"
        static let runsPlayed = "ProgRunsPlayed"
        static let lifetimeMerges = "ProgLifetimeMerges"
    }

    /// Rewarded-ad shard grants allowed per day.
    static let maxAdShardClaimsPerDay = 3
    static let shardsPerAdClaim = 3

    @Published private(set) var shards: Int = 0
    @Published private(set) var ownedThemes: Set<String> = [OrbTheme.classic.rawValue]
    @Published var activeTheme: OrbTheme = .classic {
        didSet { UserDefaults.standard.set(activeTheme.rawValue, forKey: Key.active) }
    }
    @Published private(set) var missions: [Mission] = []
    @Published private(set) var streak: Int = 0
    @Published private(set) var bestStreak: Int = 0
    @Published private(set) var adShardClaimsToday: Int = 0

    private(set) var runsPlayed: Int = 0
    private(set) var lifetimeMerges: Int = 0

    private var missionsDateKey: String = ""
    private var lastDailyKey: String = ""
    private var recoverableStreak: Int = 0
    private var recoverableOnKey: String = ""

    private init() {
        load()
        refreshForToday()
    }

    // MARK: - Loading / saving

    private func load() {
        let d = UserDefaults.standard
        shards = d.integer(forKey: Key.shards)
        if let owned = d.array(forKey: Key.owned) as? [String], !owned.isEmpty {
            ownedThemes = Set(owned)
        }
        ownedThemes.insert(OrbTheme.classic.rawValue)
        activeTheme = OrbTheme(rawValue: d.string(forKey: Key.active) ?? "") ?? .classic
        // Guard against an active theme the player no longer owns (e.g. data
        // restored from another install).
        if !ownedThemes.contains(activeTheme.rawValue) { activeTheme = .classic }

        missionsDateKey = d.string(forKey: Key.missionsDate) ?? ""
        if let data = d.data(forKey: Key.missions),
           let decoded = try? JSONDecoder().decode([Mission].self, from: data) {
            missions = decoded
        }

        streak = d.integer(forKey: Key.streak)
        bestStreak = d.integer(forKey: Key.bestStreak)
        lastDailyKey = d.string(forKey: Key.lastDailyKey) ?? ""
        recoverableStreak = d.integer(forKey: Key.recoverableStreak)
        recoverableOnKey = d.string(forKey: Key.recoverableOn) ?? ""
        runsPlayed = d.integer(forKey: Key.runsPlayed)
        lifetimeMerges = d.integer(forKey: Key.lifetimeMerges)

        let adDate = d.string(forKey: Key.adShardDate) ?? ""
        adShardClaimsToday = (adDate == DailyChallenge.dateKey(for: Date()))
            ? d.integer(forKey: Key.adShardCount) : 0
    }

    private func saveMissions() {
        let d = UserDefaults.standard
        d.set(missionsDateKey, forKey: Key.missionsDate)
        if let data = try? JSONEncoder().encode(missions) {
            d.set(data, forKey: Key.missions)
        }
    }

    private func saveShards() {
        UserDefaults.standard.set(shards, forKey: Key.shards)
    }

    private func saveOwned() {
        UserDefaults.standard.set(Array(ownedThemes), forKey: Key.owned)
    }

    private func saveStreak() {
        let d = UserDefaults.standard
        d.set(streak, forKey: Key.streak)
        d.set(bestStreak, forKey: Key.bestStreak)
        d.set(lastDailyKey, forKey: Key.lastDailyKey)
        d.set(recoverableStreak, forKey: Key.recoverableStreak)
        d.set(recoverableOnKey, forKey: Key.recoverableOn)
    }

    // MARK: - Daily rollover

    /// Call on launch and whenever the app returns to the foreground: the app
    /// can easily be left open across midnight.
    func refreshForToday(now: Date = Date()) {
        let today = DailyChallenge.dateKey(for: now)

        if missionsDateKey != today {
            missionsDateKey = today
            missions = MissionFactory.missions(forDateKey: today)
            saveMissions()
        }

        let d = UserDefaults.standard
        let adDate = d.string(forKey: Key.adShardDate) ?? ""
        if adDate != today {
            adShardClaimsToday = 0
            d.set(today, forKey: Key.adShardDate)
            d.set(0, forKey: Key.adShardCount)
        }

        // A streak that is more than one full day stale is already broken;
        // reflect that in the UI immediately rather than at next completion.
        if !lastDailyKey.isEmpty, streak > 0 {
            if let missed = daysBetween(lastDailyKey, today), missed > 1 {
                if recoverableOnKey != today {
                    recoverableStreak = streak
                    recoverableOnKey = today
                }
                streak = 0
                saveStreak()
            }
        }
    }

    // MARK: - Missions

    var completedMissionCount: Int { missions.filter { $0.isComplete }.count }
    var allMissionsComplete: Bool { !missions.isEmpty && completedMissionCount == missions.count }

    /// Applies one finished run to persistent progress.
    /// Returns the missions that completed *because of this run*, so the game
    /// over screen can celebrate them.
    @discardableResult
    func applyRun(_ stats: RunStats, dailyCompleted: Bool, now: Date = Date()) -> [Mission] {
        refreshForToday(now: now)

        runsPlayed += 1
        lifetimeMerges += stats.merges
        let d = UserDefaults.standard
        d.set(runsPlayed, forKey: Key.runsPlayed)
        d.set(lifetimeMerges, forKey: Key.lifetimeMerges)

        var newlyCompleted: [Mission] = []
        var earned = 0

        for index in missions.indices {
            let before = missions[index].isComplete
            var m = missions[index]

            switch m.kind {
            case .score:
                m.progress = max(m.progress, stats.finalScore)
            case .combo:
                m.progress = max(m.progress, stats.maxCombo)
            case .merges:
                m.progress += stats.merges
            case .mergeTier:
                m.progress += stats.tierCounts[m.param] ?? 0
            case .antimatter:
                m.progress += stats.antimatterDetonations
            case .bigCrunch:
                m.progress += stats.bigCrunches
            case .playDaily:
                if dailyCompleted { m.progress = max(m.progress, 1) }
            }

            if m.isComplete && !m.rewarded {
                m.rewarded = true
                earned += m.reward
                if !before { newlyCompleted.append(m) }
            }
            missions[index] = m
        }

        if earned > 0 {
            shards += earned
            saveShards()
        }
        saveMissions()

        if dailyCompleted {
            registerDailyCompletion(now: now)
        }

        return newlyCompleted
    }

    // MARK: - Streak

    private func registerDailyCompletion(now: Date) {
        let today = DailyChallenge.dateKey(for: now)
        guard lastDailyKey != today else { return }   // already counted today

        if let gap = daysBetween(lastDailyKey, today), gap == 1 {
            streak += 1
        } else {
            if streak > 1 { recoverableStreak = streak; recoverableOnKey = today }
            streak = 1
        }
        lastDailyKey = today
        bestStreak = max(bestStreak, streak)
        saveStreak()
    }

    /// True when the player broke a streak worth restoring, today.
    var canRecoverStreak: Bool {
        recoverableStreak > 1 && recoverableOnKey == DailyChallenge.dateKey(for: Date())
    }

    var recoverableStreakValue: Int { recoverableStreak }

    /// Restores a streak broken today. Purely a convenience — it grants no
    /// score, no shards, and no gameplay advantage.
    func recoverStreak() {
        guard canRecoverStreak else { return }
        streak = max(streak, recoverableStreak)
        bestStreak = max(bestStreak, streak)
        recoverableStreak = 0
        recoverableOnKey = ""
        saveStreak()
    }

    var hasPlayedTodaysDaily: Bool {
        lastDailyKey == DailyChallenge.dateKey(for: Date())
    }

    // MARK: - Economy

    func canAfford(_ theme: OrbTheme) -> Bool { shards >= theme.cost }
    func owns(_ theme: OrbTheme) -> Bool { ownedThemes.contains(theme.rawValue) }

    @discardableResult
    func purchase(_ theme: OrbTheme) -> Bool {
        guard !owns(theme), shards >= theme.cost else { return false }
        shards -= theme.cost
        ownedThemes.insert(theme.rawValue)
        saveShards()
        saveOwned()
        return true
    }

    var canClaimAdShards: Bool {
        adShardClaimsToday < ProgressManager.maxAdShardClaimsPerDay
    }

    /// Credits the reward for a completed rewarded-ad view.
    func grantAdShards() {
        guard canClaimAdShards else { return }
        adShardClaimsToday += 1
        shards += ProgressManager.shardsPerAdClaim
        let d = UserDefaults.standard
        d.set(DailyChallenge.dateKey(for: Date()), forKey: Key.adShardDate)
        d.set(adShardClaimsToday, forKey: Key.adShardCount)
        saveShards()
    }

    // MARK: - Helpers

    /// Whole days from `from` to `to`, or nil if either key is unparseable.
    private func daysBetween(_ from: String, _ to: String) -> Int? {
        guard !from.isEmpty, !to.isEmpty else { return nil }
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        guard let a = fmt.date(from: from), let b = fmt.date(from: to) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        return cal.dateComponents([.day], from: a, to: b).day
    }
}
