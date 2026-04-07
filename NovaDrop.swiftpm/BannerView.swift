import SwiftUI
import GoogleMobileAds

struct BannerView: UIViewRepresentable {
    func makeUIView(context: Context) -> GADBannerView {
        let banner = GADBannerView(adSize: GADAdSizeBanner)
        
        #if DEBUG
        // Google Official Test Ad Unit ID for Banners guarantees no false-click bans
        banner.adUnitID = "ca-app-pub-3940256099942544/2934735716"
        #else
        // REPLACEME: Your actual Production Banner Ad Unit ID
        banner.adUnitID = "ca-app-pub-3940256099942544/2934735716"
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
