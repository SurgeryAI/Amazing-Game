import CoreHaptics
import UIKit

/// Centralised haptics.
///
/// The previous implementation rebuilt a `CHHapticEngine` player on every merge
/// and never handled the engine being reset or stopped by the system — after
/// backgrounding the app, haptics would silently stop for the rest of the
/// session. This owns one engine, restarts it on reset/stop, honours the user's
/// setting, and falls back to `UIImpactFeedbackGenerator` on hardware without
/// Core Haptics support.
final class HapticManager {

    static let shared = HapticManager()

    private var engine: CHHapticEngine?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)

    private init() {
        prepareEngine()
    }

    private func prepareEngine() {
        guard supportsHaptics else { return }
        do {
            let e = try CHHapticEngine()
            // Let the system reclaim the engine when idle; we restart on demand.
            e.isAutoShutdownEnabled = true
            e.playsHapticsOnly = true
            e.resetHandler = { [weak self] in
                try? self?.engine?.start()
            }
            e.stoppedHandler = { _ in
                // Intentionally empty: `play` restarts lazily.
            }
            try e.start()
            engine = e
        } catch {
            engine = nil
        }
    }

    private var enabled: Bool { GameSettings.shared.hapticsEnabled }

    // MARK: - Public API

    /// A single tap of the given strength.
    func impact(intensity: Float, sharpness: Float) {
        guard enabled else { return }
        guard supportsHaptics, let engine = engine else {
            fallbackImpact(intensity: intensity)
            return
        }
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: clamp(intensity)),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: clamp(sharpness))
        ], relativeTime: 0)
        play(events: [event], on: engine)
    }

    /// Merge feedback: heavier and duller as bodies grow.
    func merge(tier: Int) {
        let t = Float(max(0, min(7, tier))) / 7.0
        impact(intensity: 0.35 + t * 0.65, sharpness: 0.65 - t * 0.35)
    }

    /// A rumble for the Big Crunch — a continuous swell into a sharp hit.
    func bigCrunch() {
        guard enabled else { return }
        guard supportsHaptics, let engine = engine else {
            fallbackImpact(intensity: 1.0)
            return
        }
        let swell = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.75),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
            ],
            relativeTime: 0,
            duration: 0.9
        )
        let hit = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
        ], relativeTime: 0.95)
        play(events: [swell, hit], on: engine)
    }

    /// Two quick warning taps when the cosmos is close to overflowing.
    func warning() {
        guard enabled else { return }
        guard supportsHaptics, let engine = engine else {
            fallbackImpact(intensity: 0.6)
            return
        }
        let a = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
        ], relativeTime: 0)
        let b = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
        ], relativeTime: 0.13)
        play(events: [a, b], on: engine)
    }

    /// Light tick for UI affordances.
    func tick() {
        guard enabled else { return }
        impact(intensity: 0.35, sharpness: 0.6)
    }

    // MARK: - Internals

    private func play(events: [CHHapticEvent], on engine: CHHapticEngine) {
        do {
            // `start()` is a no-op when already running and revives the engine
            // after an auto-shutdown, which is why it is called every time.
            try engine.start()
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Silently degrade — haptics are never load-bearing.
        }
    }

    private func fallbackImpact(intensity: Float) {
        let generator: UIImpactFeedbackGenerator
        if intensity > 0.75 { generator = heavyImpact }
        else if intensity > 0.45 { generator = mediumImpact }
        else { generator = lightImpact }
        generator.prepare()
        generator.impactOccurred()
    }

    private func clamp(_ v: Float) -> Float { max(0, min(1, v)) }
}
