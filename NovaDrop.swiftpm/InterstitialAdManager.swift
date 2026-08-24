import Foundation
import GoogleMobileAds

/// Forced interstitials, on a much gentler leash than before.
///
/// The old rule was a flat 2-in-3 chance on *every* game over, including the
/// player's very first run and including the run where they just beat their
/// record. That is the most expensive moment in the whole session to
/// interrupt. The cadence here earns roughly the same over a session while
/// removing the placements that cost retention:
///
///  * never during the first few runs of a session — let them get hooked first
///  * never within a couple of minutes of the last full-screen ad
///  * never straight after a personal best
///  * never straight after the player voluntarily watched a rewarded ad
final class InterstitialAdManager: NSObject, GADFullScreenContentDelegate, ObservableObject {

    static let shared = InterstitialAdManager()

    // MARK: - Cadence tuning

    /// Runs completed in this session before an interstitial may appear.
    private let warmupRuns = 3
    /// Minimum seconds between any two full-screen ads.
    private let minSecondsBetweenAds: TimeInterval = 150
    /// Chance of showing once every other condition is satisfied.
    private let showProbability = 0.6

    private var interstitial: GADInterstitialAd?
    private var isLoading = false
    private var runsThisSession = 0
    private var lastFullScreenAdAt: Date?
    private var lastLoadFailure: Date?

    private override init() {
        super.init()
        loadAd()
    }

    // MARK: - Loading

    func loadAd() {
        guard interstitial == nil, !isLoading else { return }
        if let failed = lastLoadFailure, Date().timeIntervalSince(failed) < 20 { return }

        isLoading = true
        GADInterstitialAd.load(withAdUnitID: AdUnits.interstitial, request: GADRequest()) { [weak self] ad, error in
            guard let self = self else { return }
            self.isLoading = false
            if let error = error {
                self.lastLoadFailure = Date()
                self.interstitial = nil
                print("Failed to load interstitial ad: \(error.localizedDescription)")
                return
            }
            self.lastLoadFailure = nil
            self.interstitial = ad
            self.interstitial?.fullScreenContentDelegate = self
        }
    }

    // MARK: - Bookkeeping

    /// Called at the end of every run, whether or not an ad is shown.
    func noteRunFinished() {
        runsThisSession += 1
    }

    /// Called when a *rewarded* ad plays, so the two placements do not stack.
    func noteFullScreenAdShown() {
        lastFullScreenAdAt = Date()
    }

    // MARK: - Presenting

    /// Shows an interstitial if — and only if — the cadence rules allow it.
    /// - Parameter isPersonalBest: suppresses the ad on a record-setting run.
    func showAdIfAppropriate(isPersonalBest: Bool) {
        guard !isPersonalBest else { return }
        guard runsThisSession > warmupRuns else { return }

        if let last = lastFullScreenAdAt,
           Date().timeIntervalSince(last) < minSecondsBetweenAds { return }

        guard Double.random(in: 0..<1) < showProbability else { return }

        guard let ad = interstitial, let root = AdPresenter.rootViewController else {
            loadAd()
            return
        }

        // Consume before presenting: an ad object is single-use, and the old
        // code could hand the same object to `present` twice.
        interstitial = nil
        lastFullScreenAdAt = Date()
        ad.present(fromRootViewController: root)
    }

    // MARK: - GADFullScreenContentDelegate

    func ad(_ ad: GADFullScreenPresentingAd,
            didFailToPresentFullScreenContentWithError error: Error) {
        print("Interstitial failed to present: \(error.localizedDescription)")
        loadAd()
    }

    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        loadAd()
    }
}
