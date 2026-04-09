import SwiftUI
import GoogleMobileAds

struct BannerView: UIViewRepresentable {
    func makeUIView(context: Context) -> GADBannerView {
        let banner = GADBannerView(adSize: GADAdSizeBanner)
        
        #if DEBUG
        // Google Official Test Ad Unit ID for Banners guarantees no false-click bans
        banner.adUnitID = "ca-app-pub-3940256099942544/2934735716"
        #else
        // Replace with your actual Production Banner Ad Unit ID before shipping.
        // The compiler warning below will remind you if this placeholder is still present.
        #warning("Replace YOUR_PRODUCTION_AD_UNIT_ID with your real AdMob banner unit ID before release.")
        banner.adUnitID = "YOUR_PRODUCTION_AD_UNIT_ID"
        #endif
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            banner.rootViewController = rootVC
        }
        
        banner.load(GADRequest())
        return banner
    }
    
    func updateUIView(_ uiView: GADBannerView, context: Context) {}
}
