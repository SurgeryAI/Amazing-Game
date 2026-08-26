import Foundation
import UIKit

/// Every AdMob unit ID in one place.
///
/// DEBUG builds always use Google's public test units — running live ads
/// against your own build is the fastest way to get an AdMob account
/// suspended for invalid traffic.
enum AdUnits {
    #if DEBUG
    static let banner       = "ca-app-pub-3940256099942544/2934735716"
    static let interstitial = "ca-app-pub-3940256099942544/4411468910"
    static let rewarded     = "ca-app-pub-3940256099942544/1712485313"
    #else
    static let banner       = "ca-app-pub-6432429930581606/6568763063"
    static let interstitial = "ca-app-pub-6432429930581606/4971979475"

    static let rewarded     = "ca-app-pub-6432429930581606/3782519218"
    #endif
}

enum AdPresenter {
    /// The view controller ads should be presented from.
    ///
    /// The previous implementation used `connectedScenes.first`, which on
    /// iPad (or whenever the system keeps a background scene around) can hand
    /// back a scene that is not on screen — the ad then silently fails to
    /// present. This walks to the genuinely active, key window.
    static var rootViewController: UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let scene = active else { return nil }

        let window = scene.windows.first { $0.isKeyWindow } ?? scene.windows.first
        guard var vc = window?.rootViewController else { return nil }

        // Present from the topmost controller so we never try to present on a
        // controller that is already presenting something.
        while let presented = vc.presentedViewController {
            vc = presented
        }
        return vc
    }
}
