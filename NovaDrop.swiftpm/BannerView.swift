import SwiftUI
import GoogleMobileAds

/// Bottom banner.
///
/// Two fixes over the previous version: the ad unit IDs now live in `AdUnits`
/// (so the stale `#warning` about a placeholder ID — which had in fact already
/// been replaced — no longer fires on every release build), and the root view
/// controller is resolved from the genuinely active scene rather than
/// `connectedScenes.first`.
struct BannerView: UIViewRepresentable {

    func makeUIView(context: Context) -> GADBannerView {
        let banner = GADBannerView(adSize: GADAdSizeBanner)
        banner.adUnitID = AdUnits.banner
        banner.rootViewController = AdPresenter.rootViewController
        banner.load(GADRequest())
        return banner
    }

    func updateUIView(_ uiView: GADBannerView, context: Context) {
        // The root view controller is nil on the very first layout pass in
        // some launch sequences; recover it once the window exists.
        if uiView.rootViewController == nil {
            uiView.rootViewController = AdPresenter.rootViewController
        }
    }
}
