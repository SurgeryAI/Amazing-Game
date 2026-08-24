import AVFoundation
import Foundation

/// Procedurally synthesised sound.
///
/// Every sound in the game is generated as PCM at launch rather than loaded
/// from disk. That keeps the app binary tiny, needs no changes to the
/// auto-generated Package.swift (which cannot declare resources), and lets the
/// merge chime be *derived* from the tier — big bodies sound deep and heavy,
/// small ones sound bright and delicate, and combo blips climb a scale.
///
/// Every entry point is defensive: if the audio session or engine fails to come
/// up for any reason, `isAvailable` stays false and all playback is a silent
/// no-op. Audio must never be able to take the game down.
final class AudioManager {

    static let shared = AudioManager()

    // MARK: - Sound identifiers

    enum Sfx {
        case merge(tier: Int)
        case combo(level: Int)
        case drop
        case land
        case antimatter
        case bigCrunch
        case danger
        case gameOver
        case tap
        case reward
        case unlock

        var key: String {
            switch self {
            case .merge(let t):   return "merge\(max(0, min(7, t)))"
            case .combo(let l):   return "combo\(max(1, min(8, l)))"
            case .drop:           return "drop"
            case .land:           return "land"
            case .antimatter:     return "antimatter"
            case .bigCrunch:      return "bigcrunch"
            case .danger:         return "danger"
            case .gameOver:       return "gameover"
            case .tap:            return "tap"
            case .reward:         return "reward"
            case .unlock:         return "unlock"
            }
        }
    }

    // MARK: - Engine

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayerIndex = 0
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var isAvailable = false

    private let sampleRate: Double = 44_100
    private let voiceCount = 8
    private var format: AVAudioFormat?

    private init() {
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            return
        }
        format = fmt
        buildBuffers(format: fmt)
        configureSession()
        startEngine(format: fmt)
        observeInterruptions()
    }

    // MARK: - Session / engine lifecycle

    private func configureSession() {
        // `.ambient` is the right category for a casual game: it respects the
        // hardware mute switch and, critically, does not stop the player's
        // own music. Nothing kills a commute session faster than a game that
        // silences a podcast.
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            // Non-fatal: the engine may still work with the default session.
        }
    }

    private func startEngine(format: AVAudioFormat) {
        // Touch the main mixer before attaching so the engine instantiates it.
        _ = engine.mainMixerNode
        for _ in 0..<voiceCount {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            players.append(node)
        }
        do {
            engine.prepare()
            try engine.start()
            isAvailable = true
        } catch {
            isAvailable = false
        }
    }

    private func observeInterruptions() {
        // A phone call, Siri, or a backgrounded app can stop the engine. Bring
        // it back rather than leaving the rest of the session silent.
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .ended { self.restartIfNeeded() }
        }
    }

    /// Safe to call often; does nothing when the engine is already healthy.
    func restartIfNeeded() {
        guard isAvailable, !engine.isRunning else { return }
        try? AVAudioSession.sharedInstance().setActive(true, options: [])
        try? engine.start()
    }

    // MARK: - Playback

    func play(_ sfx: Sfx, volume: Float = 1.0) {
        guard isAvailable, GameSettings.shared.soundEnabled else { return }
        guard let buffer = buffers[sfx.key] else { return }
        if !engine.isRunning { restartIfNeeded() }
        guard engine.isRunning, !players.isEmpty else { return }

        let node = players[nextPlayerIndex]
        nextPlayerIndex = (nextPlayerIndex + 1) % players.count

        node.stop()
        node.volume = max(0, min(1, volume))
        node.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionHandler: nil)
        node.play()
    }

    // MARK: - Synthesis

    private func buildBuffers(format: AVAudioFormat) {
        // Merge chimes: pitch descends as bodies grow, so a Black Hole lands
        // like a gong and Dust like a wind-chime. Frequencies are a minor
        // pentatonic walked downward, which keeps any two merges consonant no
        // matter what order they fire in during a cascade.
        let mergeFreqs: [Double] = [880.0, 740.0, 587.33, 493.88, 392.0, 293.66, 196.0, 155.56]
        for tier in 0..<8 {
            let f = mergeFreqs[tier]
            let bigness = Double(tier) / 7.0                  // 0 = dust, 1 = black hole
            let duration = 0.45 + bigness * 0.85
            let decay = 9.0 - bigness * 6.5                   // big bodies ring longer
            let modIndex = 2.4 + bigness * 3.0                // and are richer / more metallic
            let subGain = bigness * 0.55                      // sub-octave weight
            buffers["merge\(tier)"] = render(format: format, duration: duration) { t in
                let e = AudioManager.envelope(t: t, duration: duration, attack: 0.004, decay: decay)
                guard e > 0 else { return 0 }
                let mod = sin(2 * Double.pi * f * 2.01 * t) * modIndex * e
                var s = sin(2 * Double.pi * f * t + mod)
                s += 0.28 * sin(2 * Double.pi * f * 3.0 * t) * e
                if subGain > 0.01 {
                    s += subGain * sin(2 * Double.pi * f * 0.5 * t)
                }
                return Float(s * e * 0.34)
            }
        }

        // Combo blips climb a major scale — the audible "ladder" that makes a
        // chain feel like it is building toward something.
        let comboSemitones: [Double] = [0, 2, 4, 7, 9, 12, 14, 16]
        for level in 1...8 {
            let semi = comboSemitones[level - 1]
            let f = 523.25 * pow(2.0, semi / 12.0)
            let duration = 0.22
            buffers["combo\(level)"] = render(format: format, duration: duration) { t in
                let e = AudioManager.envelope(t: t, duration: duration, attack: 0.003, decay: 18.0)
                guard e > 0 else { return 0 }
                let s = sin(2 * Double.pi * f * t) + 0.4 * sin(2 * Double.pi * f * 2 * t)
                return Float(s * e * 0.22)
            }
        }

        // Drop: a short airy "whoosh down" so releasing an orb has weight.
        buffers["drop"] = render(format: format, duration: 0.18) { t in
            let e = AudioManager.envelope(t: t, duration: 0.18, attack: 0.006, decay: 22.0)
            guard e > 0 else { return 0 }
            let f = 340.0 - 180.0 * (t / 0.18)
            let s = sin(2 * Double.pi * f * t) * 0.6 + AudioManager.noise(t) * 0.25
            return Float(s * e * 0.20)
        }

        // Land: a very short filtered click.
        buffers["land"] = render(format: format, duration: 0.09) { t in
            let e = AudioManager.envelope(t: t, duration: 0.09, attack: 0.001, decay: 46.0)
            guard e > 0 else { return 0 }
            let s = sin(2 * Double.pi * 150.0 * t) * 0.7 + AudioManager.noise(t) * 0.4
            return Float(s * e * 0.18)
        }

        // Antimatter: a bright noise burst that collapses downward.
        buffers["antimatter"] = render(format: format, duration: 0.55) { t in
            let e = AudioManager.envelope(t: t, duration: 0.55, attack: 0.002, decay: 7.5)
            guard e > 0 else { return 0 }
            let sweep = 900.0 * exp(-4.0 * t)
            let s = AudioManager.noise(t) * 0.7 + sin(2 * Double.pi * sweep * t) * 0.6
            return Float(s * e * 0.30)
        }

        // Big Crunch: the climax. A deep rising rumble that snaps into a boom.
        buffers["bigcrunch"] = render(format: format, duration: 2.0) { t in
            let riseDur = 1.1
            if t < riseDur {
                let p = t / riseDur
                let e = p * p * 0.7
                let f = 40.0 + 200.0 * p * p
                let s = sin(2 * Double.pi * f * t) + AudioManager.noise(t) * 0.3 * p
                return Float(s * e * 0.30)
            } else {
                let bt = t - riseDur
                let e = AudioManager.envelope(t: bt, duration: 0.9, attack: 0.002, decay: 4.0)
                guard e > 0 else { return 0 }
                let s = sin(2 * Double.pi * 55.0 * bt)
                    + 0.5 * sin(2 * Double.pi * 82.5 * bt)
                    + AudioManager.noise(bt) * 0.35
                return Float(s * e * 0.34)
            }
        }

        // Danger: a low two-pulse warning, deliberately unpleasant.
        buffers["danger"] = render(format: format, duration: 0.5) { t in
            let pulse = (t < 0.22) ? t : (t < 0.28 ? -1 : t - 0.28)
            guard pulse >= 0 else { return 0 }
            let e = AudioManager.envelope(t: pulse, duration: 0.22, attack: 0.01, decay: 11.0)
            guard e > 0 else { return 0 }
            let s = sin(2 * Double.pi * 116.0 * t) + 0.5 * sin(2 * Double.pi * 174.0 * t)
            return Float(s * e * 0.22)
        }

        // Game over: a descending minor third, the universal "you lost" cadence.
        buffers["gameover"] = render(format: format, duration: 1.3) { t in
            let f: Double = t < 0.32 ? 329.63 : (t < 0.62 ? 261.63 : 196.0)
            let seg: Double = t < 0.32 ? t : (t < 0.62 ? t - 0.32 : t - 0.62)
            let dur: Double = t < 0.62 ? 0.30 : 0.68
            let e = AudioManager.envelope(t: seg, duration: dur, attack: 0.008, decay: 5.0)
            guard e > 0 else { return 0 }
            let s = sin(2 * Double.pi * f * t) + 0.3 * sin(2 * Double.pi * f * 2 * t)
            return Float(s * e * 0.26)
        }

        // UI tap.
        buffers["tap"] = render(format: format, duration: 0.07) { t in
            let e = AudioManager.envelope(t: t, duration: 0.07, attack: 0.001, decay: 55.0)
            guard e > 0 else { return 0 }
            return Float(sin(2 * Double.pi * 720.0 * t) * e * 0.16)
        }

        // Reward / unlock sparkles: fast ascending arpeggios.
        buffers["reward"] = render(format: format, duration: 0.6) { t in
            let steps: [Double] = [523.25, 659.25, 783.99, 1046.5]
            let idx = min(3, Int(t / 0.11))
            let seg = t - Double(idx) * 0.11
            let e = AudioManager.envelope(t: seg, duration: 0.34, attack: 0.002, decay: 12.0)
            guard e > 0 else { return 0 }
            return Float(sin(2 * Double.pi * steps[idx] * t) * e * 0.20)
        }

        buffers["unlock"] = render(format: format, duration: 0.85) { t in
            let steps: [Double] = [392.0, 523.25, 659.25, 783.99, 1046.5]
            let idx = min(4, Int(t / 0.10))
            let seg = t - Double(idx) * 0.10
            let e = AudioManager.envelope(t: seg, duration: 0.45, attack: 0.002, decay: 9.0)
            guard e > 0 else { return 0 }
            let f = steps[idx]
            let s = sin(2 * Double.pi * f * t) + 0.35 * sin(2 * Double.pi * f * 2 * t)
            return Float(s * e * 0.20)
        }
    }

    /// Renders a mono buffer by sampling `generator` at each frame.
    private func render(format: AVAudioFormat,
                        duration: Double,
                        generator: (Double) -> Float) -> AVAudioPCMBuffer? {
        let frameCount = Int(duration * sampleRate)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(frameCount)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        // A short release ramp on the tail prevents the click you would
        // otherwise hear when a buffer is cut off mid-cycle.
        let releaseFrames = min(frameCount, Int(0.008 * sampleRate))
        let releaseStart = frameCount - releaseFrames

        for i in 0..<frameCount {
            var v = generator(Double(i) / sampleRate)
            if releaseFrames > 0 && i >= releaseStart {
                v *= Float(frameCount - i) / Float(releaseFrames)
            }
            channel[i] = max(-1.0, min(1.0, v))
        }
        return buffer
    }

    /// Percussive envelope: linear attack into exponential decay.
    private static func envelope(t: Double, duration: Double,
                                 attack: Double, decay: Double) -> Double {
        if t < 0 || t > duration { return 0 }
        if t < attack { return attack > 0 ? t / attack : 1 }
        return exp(-(t - attack) * decay)
    }

    /// Deterministic value noise. A plain LCG keeps this reproducible and
    /// avoids pulling in a random source during buffer construction.
    private static func noise(_ t: Double) -> Double {
        var x = UInt64(abs(t) * 44_100.0) &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        x ^= x >> 33
        x = x &* 0xff51afd7ed558ccd
        x ^= x >> 33
        return Double(x % 20_000) / 10_000.0 - 1.0
    }
}
