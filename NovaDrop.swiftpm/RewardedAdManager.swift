import Foundation
import GoogleMobileAds

/// Opt-in, rewarded video.
///
/// Every placement built on this manager is something the player *asks* for.
/// Nothing here interrupts play, and nothing it grants can change a score on
/// the Pure leaderboard — Second Chance moves a run to the Marathon board
/// instead, and shard grants only buy cosmetics.
final class RewardedAdManager: NSObject, ObservableObject, GADFullScreenContentDelegate {

    static let shared = RewardedAdManager()

    @Published private(set) var isReady: Bool = false

    private var rewardedAd: GADRewardedAd?
    private var isLoading = false
    private var didEarnReward = false
    private var completion: ((Bool) -> Void)?
    private var lastLoadFailure: Date?

    private override init() {
        super.init()
        load()
    }

    // MARK: - Loading

    func load() {
        guard rewardedAd == nil, !isLoading else { return }

        // Back off after a failure so a device with no connectivity does not
        // spin on load requests.
        if let failed = lastLoadFailure, Date().timeIntervalSince(failed) < 20 { return }

        isLoading = true
        GADRewardedAd.load(withAdUnitID: AdUnits.rewarded, request: GADRequest()) { [weak self] ad, error in
            guard let self = self else { return }
            self.isLoading = false
            if let error = error {
                self.lastLoadFailure = Date()
                self.rewardedAd = nil
                self.isReady = false
                print("Rewarded ad failed to load: \(error.localizedDescription)")
                return
            }
            self.lastLoadFailure = nil
            self.rewardedAd = ad
            self.rewardedAd?.fullScreenContentDelegate = self
            self.isReady = true
        }
    }

    // MARK: - Presenting

    /// Presents a rewarded ad. `completion(true)` only if the reward was
    /// genuinely earned — never grant on dismissal alone.
    func show(completion: @escaping (Bool) -> Void) {
        guard let ad = rewardedAd, let root = AdPresenter.rootViewController else {
            // Nothing to show. Report failure so the caller can fall back
            // gracefully rather than leaving the player staring at a spinner.
            load()
            completion(false)
            return
        }

        self.completion = completion
        self.didEarnReward = false

        // Consume the ad immediately: an ad object must never be presented twice.
        rewardedAd = nil
        isReady = false

        ad.present(fromRootViewController: root) { [weak self] in
            self?.didEarnReward = true
        }
    }

    private func finish() {
        let earned = didEarnReward
        let handler = completion
        completion = nil
        didEarnReward = false
        DispatchQueue.main.async {
            handler?(earned)
        }
        load()
    }

    // MARK: - GADFullScreenContentDelegate

    func ad(_ ad: GADFullScreenPresentingAd,
            didFailToPresentFullScreenContentWithError error: Error) {
        print("Rewarded ad failed to present: \(error.localizedDescription)")
        finish()
    }

    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        finish()
    }
}
