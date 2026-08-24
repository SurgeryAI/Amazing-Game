import Foundation
import Combine

/// Leaderboards, split so an assisted run can never contaminate a real one.
///
/// **Pure** — Endless runs finished without a Second Chance. This is the
/// number that means "how well I played", and it is what `bestScore` reports
/// and what the HUD shows.
///
/// **Marathon** — Endless runs that used a Second Chance. Still worth
/// chasing, but tracked separately and always labelled, the same way
/// speedrunning keeps glitchless and any% apart.
///
/// **Daily** — today's Challenge, which runs on a fixed seed. Second Chance is
/// disabled entirely in Daily mode, so this board needs no split.
final class ScoreManager: ObservableObject {

    static let shared = ScoreManager()

    private enum Key {
        static let pureAllTime = "AllTimeTopScores"      // reused: existing players keep their scores
        static let pureDaily = "DailyTopScores"          // reused
        static let pureDailyDate = "DailyScoresDate"     // reused
        static let marathonAllTime = "MarathonTopScores"
        static let dailyChallengeBest = "DailyChallengeBest"
        static let dailyChallengeKey = "DailyChallengeBestKey"
        static let dailyChallengeAllTimeBest = "DailyChallengeAllTimeBest"
        static let legacyHighScore = "HighScore"
    }

    @Published private(set) var allTimeTop3: [Int] = []
    @Published private(set) var todayTop3: [Int] = []
    @Published private(set) var marathonTop3: [Int] = []
    @Published private(set) var dailyChallengeBest: Int = 0
    @Published private(set) var dailyChallengeAllTimeBest: Int = 0

    /// The headline number. Pure runs only — by design.
    var bestScore: Int { allTimeTop3.first ?? 0 }
    var marathonBest: Int { marathonTop3.first ?? 0 }

    private var dailyChallengeKey: String = ""

    private init() {
        load()
    }

    // MARK: - Submission

    /// Records a finished run.
    /// - Returns: `true` when this run set a new personal best on whichever
    ///   board it belongs to — used to suppress the interstitial on the one
    ///   screen where an ad would sting most.
    @discardableResult
    func submit(score: Int, mode: GameMode, assisted: Bool, now: Date = Date()) -> Bool {
        guard score > 0 else { return false }

        switch mode {
        case .daily(let dateKey):
            return submitDaily(score: score, dateKey: dateKey)
        case .endless:
            return assisted ? submitMarathon(score: score)
                            : submitPure(score: score, now: now)
        }
    }

    private func submitPure(score: Int, now: Date) -> Bool {
        let isBest = score > (allTimeTop3.first ?? 0)

        allTimeTop3 = Array((allTimeTop3 + [score]).sorted(by: >).prefix(3))
        UserDefaults.standard.set(allTimeTop3, forKey: Key.pureAllTime)

        rolloverDailyIfNeeded(now: now)
        todayTop3 = Array((todayTop3 + [score]).sorted(by: >).prefix(3))
        UserDefaults.standard.set(todayTop3, forKey: Key.pureDaily)

        return isBest
    }

    private func submitMarathon(score: Int) -> Bool {
        let isBest = score > (marathonTop3.first ?? 0)
        marathonTop3 = Array((marathonTop3 + [score]).sorted(by: >).prefix(3))
        UserDefaults.standard.set(marathonTop3, forKey: Key.marathonAllTime)
        return isBest
    }

    private func submitDaily(score: Int, dateKey: String) -> Bool {
        let d = UserDefaults.standard
        if dailyChallengeKey != dateKey {
            dailyChallengeKey = dateKey
            dailyChallengeBest = 0
            d.set(dateKey, forKey: Key.dailyChallengeKey)
        }
        let isBest = score > dailyChallengeBest
        if isBest {
            dailyChallengeBest = score
            d.set(score, forKey: Key.dailyChallengeBest)
        }
        if score > dailyChallengeAllTimeBest {
            dailyChallengeAllTimeBest = score
            d.set(score, forKey: Key.dailyChallengeAllTimeBest)
        }
        return isBest
    }

    // MARK: - Persistence

    private func load() {
        let d = UserDefaults.standard

        allTimeTop3 = (d.array(forKey: Key.pureAllTime) as? [Int]) ?? []
        marathonTop3 = (d.array(forKey: Key.marathonAllTime) as? [Int]) ?? []

        // Migrate the very old single high score.
        if allTimeTop3.isEmpty {
            let legacy = d.integer(forKey: Key.legacyHighScore)
            if legacy > 0 {
                allTimeTop3 = [legacy]
                d.set(allTimeTop3, forKey: Key.pureAllTime)
            }
        }

        let today = DailyChallenge.dateKey(for: Date())
        if d.string(forKey: Key.pureDailyDate) == today {
            todayTop3 = (d.array(forKey: Key.pureDaily) as? [Int]) ?? []
        } else {
            todayTop3 = []
            d.set(todayTop3, forKey: Key.pureDaily)
            d.set(today, forKey: Key.pureDailyDate)
        }

        dailyChallengeKey = d.string(forKey: Key.dailyChallengeKey) ?? ""
        dailyChallengeBest = (dailyChallengeKey == today) ? d.integer(forKey: Key.dailyChallengeBest) : 0
        dailyChallengeAllTimeBest = d.integer(forKey: Key.dailyChallengeAllTimeBest)
    }

    /// Clears the "today" board when the calendar day has turned over.
    ///
    /// The stored array is rewritten *immediately* rather than waiting for the
    /// next submission. Previously, in-memory state was cleared but the stale
    /// array stayed on disk under the new date, so a crash or a force-quit
    /// between the two would resurrect yesterday's scores as today's.
    private func rolloverDailyIfNeeded(now: Date) {
        let d = UserDefaults.standard
        let today = DailyChallenge.dateKey(for: now)
        guard d.string(forKey: Key.pureDailyDate) != today else { return }
        todayTop3 = []
        d.set(todayTop3, forKey: Key.pureDaily)
        d.set(today, forKey: Key.pureDailyDate)
    }

    /// Call when the app returns to the foreground — a session can straddle midnight.
    func refreshForToday(now: Date = Date()) {
        rolloverDailyIfNeeded(now: now)
        let today = DailyChallenge.dateKey(for: now)
        if dailyChallengeKey != today {
            dailyChallengeKey = today
            dailyChallengeBest = 0
            UserDefaults.standard.set(today, forKey: Key.dailyChallengeKey)
            UserDefaults.standard.set(0, forKey: Key.dailyChallengeBest)
        }
    }
}
