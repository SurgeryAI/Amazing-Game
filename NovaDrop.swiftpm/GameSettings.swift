import Foundation
import Combine

/// User-facing toggles, persisted to UserDefaults.
///
/// Tilt control in particular *must* be optional: the accelerometer-driven
/// gravity makes the game unplayable when the device is not held upright
/// (lying in bed, propped on a desk), which is a large share of casual play.
final class GameSettings: ObservableObject {
    static let shared = GameSettings()

    private enum Key {
        static let sound = "SettingSoundEnabled"
        static let haptics = "SettingHapticsEnabled"
        static let tilt = "SettingTiltEnabled"
        static let reducedFlash = "SettingReducedFlash"
        static let seenTutorial = "HasSeenTutorial"
    }

    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: Key.sound) }
    }
    @Published var hapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: Key.haptics) }
    }
    @Published var tiltEnabled: Bool {
        didSet { UserDefaults.standard.set(tiltEnabled, forKey: Key.tilt) }
    }
    /// Accessibility: suppresses full-screen flashes and heavy bloom.
    @Published var reducedFlash: Bool {
        didSet { UserDefaults.standard.set(reducedFlash, forKey: Key.reducedFlash) }
    }

    private init() {
        let d = UserDefaults.standard
        // Register defaults so first launch gets sound/haptics ON and tilt OFF.
        d.register(defaults: [
            Key.sound: true,
            Key.haptics: true,
            Key.tilt: false,
            Key.reducedFlash: false
        ])
        soundEnabled = d.bool(forKey: Key.sound)
        hapticsEnabled = d.bool(forKey: Key.haptics)
        tiltEnabled = d.bool(forKey: Key.tilt)
        reducedFlash = d.bool(forKey: Key.reducedFlash)
    }

    var hasSeenTutorial: Bool {
        get { UserDefaults.standard.bool(forKey: Key.seenTutorial) }
        set { UserDefaults.standard.set(newValue, forKey: Key.seenTutorial) }
    }
}
