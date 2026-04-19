import Foundation

class ScoreManager: ObservableObject {
    static let shared = ScoreManager()
    
    private let allTimeKey = "AllTimeTopScores"
    private let dailyScoresKey = "DailyTopScores"
    private let dailyDateKey = "DailyScoresDate"
    
    @Published var allTimeTop3: [Int] = []
    @Published var todayTop3: [Int] = []
    
    var bestScore: Int {
        allTimeTop3.first ?? 0
    }
    
    init() {
        loadScores()
    }
    
    /// Submit a finished game's score. Updates both all-time and daily leaderboards.
    func submitScore(_ score: Int) {
        guard score > 0 else { return }
        
        // --- All-time ---
        allTimeTop3.append(score)
        allTimeTop3.sort(by: >)
        if allTimeTop3.count > 3 { allTimeTop3 = Array(allTimeTop3.prefix(3)) }
        UserDefaults.standard.set(allTimeTop3, forKey: allTimeKey)
        
        // --- Today ---
        refreshDailyIfNeeded()
        todayTop3.append(score)
        todayTop3.sort(by: >)
        if todayTop3.count > 3 { todayTop3 = Array(todayTop3.prefix(3)) }
        UserDefaults.standard.set(todayTop3, forKey: dailyScoresKey)
    }
    
    // MARK: - Persistence helpers
    
    private func loadScores() {
        allTimeTop3 = (UserDefaults.standard.array(forKey: allTimeKey) as? [Int]) ?? []
        
        // Migrate the old single high-score if the new array is empty
        if allTimeTop3.isEmpty {
            let legacy = UserDefaults.standard.integer(forKey: "HighScore")
            if legacy > 0 {
                allTimeTop3 = [legacy]
                UserDefaults.standard.set(allTimeTop3, forKey: allTimeKey)
            }
        }
        
        refreshDailyIfNeeded()
    }
    
    /// Resets today's scores if the stored date is not today.
    private func refreshDailyIfNeeded() {
        let today = dateString(for: Date())
        let stored = UserDefaults.standard.string(forKey: dailyDateKey) ?? ""
        
        if stored == today {
            todayTop3 = (UserDefaults.standard.array(forKey: dailyScoresKey) as? [Int]) ?? []
        } else {
            // New day — clear daily scores
            todayTop3 = []
            UserDefaults.standard.set(todayTop3, forKey: dailyScoresKey)
            UserDefaults.standard.set(today, forKey: dailyDateKey)
        }
    }
    
    private func dateString(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }
}
