import SwiftUI
import AppTrackingTransparency
import AdSupport
import GoogleMobileAds

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    ATTrackingManager.requestTrackingAuthorization { status in
                        GADMobileAds.sharedInstance().start(completionHandler: nil)
                    }
                }
        }
    }
}
