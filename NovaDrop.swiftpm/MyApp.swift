import SwiftUI
import AppTrackingTransparency
import AdSupport
import GoogleMobileAds

@main
struct MyApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .onAppear { AppBootstrap.shared.startIfNeeded() }
                .onChange(of: scenePhase) { phase in
                    guard phase == .active else { return }
                    // The app can be left open across midnight; re-derive the
                    // day-scoped state (missions, streak, daily boards) every
                    // time it comes forward.
                    ProgressManager.shared.refreshForToday()
                    ScoreManager.shared.refreshForToday()
                    AudioManager.shared.restartIfNeeded()
                }
        }
    }
}

/// One-time startup work.
///
/// Previously the ATT prompt and `GADMobileAds.start` were fired on *every*
/// `didBecomeActive` notification — so every return from the background
/// re-requested tracking authorisation and re-initialised the ads SDK. Both
/// are once-per-launch operations.
final class AppBootstrap {
    static let shared = AppBootstrap()
    private var hasStarted = false

    private init() {}

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true

        // Warm the managers so their first use is not the thing that pays for
        // engine construction and buffer synthesis.
        _ = GameSettings.shared
        _ = AudioManager.shared
        _ = HapticManager.shared
        _ = ProgressManager.shared
        _ = ScoreManager.shared

        // Apple requires the app to be foreground-active before the ATT prompt
        // will display; a short delay after first appearance is the reliable
        // window for it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            ATTrackingManager.requestTrackingAuthorization { _ in
                DispatchQueue.main.async {
                    GADMobileAds.sharedInstance().start(completionHandler: nil)
                    InterstitialAdManager.shared.loadAd()
                    RewardedAdManager.shared.load()
                }
            }
        }
    }
}
