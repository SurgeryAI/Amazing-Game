import SwiftUI
import GoogleMobileAds

class InterstitialAdManager: NSObject, GADFullScreenContentDelegate, ObservableObject {
    static let shared = InterstitialAdManager()
    
    private var interstitial: GADInterstitialAd?
    
    #if DEBUG
    // Test Ad Unit ID
    private let adUnitID = "ca-app-pub-3940256099942544/4411468910"
    #else
    private let adUnitID = "ca-app-pub-6432429930581606/4971979475"
    #endif
    
    override init() {
        super.init()
        loadAd()
    }
    
    func loadAd() {
        let request = GADRequest()
        GADInterstitialAd.load(withAdUnitID: adUnitID,
                               request: request,
                               completionHandler: { [weak self] ad, error in
            if let error = error {
                print("Failed to load interstitial ad with error: \(error.localizedDescription)")
                return
            }
            self?.interstitial = ad
            self?.interstitial?.fullScreenContentDelegate = self
        })
    }
    
    func showAd() {
        guard let interstitial = interstitial else {
            print("Ad wasn't ready")
            loadAd() // Try to load it for next time if it failed
            return
        }
        
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        let window = windowScene?.windows.first(where: { $0.isKeyWindow })
        let rootVC = window?.rootViewController
        
        if let rootVC = rootVC {
            interstitial.present(fromRootViewController: rootVC)
        }
    }
    
    // MARK: - GADFullScreenContentDelegate
    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("Ad did fail to present full screen content.")
        loadAd()
    }
    
    func adWillPresentFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        print("Ad will present full screen content.")
    }
    
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        print("Ad did dismiss full screen content.")
        loadAd()
    }
}
