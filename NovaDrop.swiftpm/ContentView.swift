import SwiftUI
import SpriteKit

/// Holds the one and only `GameScene` for the app's lifetime.
///
/// A `@State` initialiser closure is re-evaluated on every view init, which
/// quietly built (and threw away) a fresh SpriteKit scene on each SwiftUI
/// update. `@StateObject` guarantees exactly one.
final class SceneHolder: ObservableObject {
    let scene: GameScene = {
        let scene = GameScene()
        scene.scaleMode = .resizeFill
        scene.anchorPoint = CGPoint(x: 0, y: 0)
        return scene
    }()
}

struct ContentView: View {

    enum Screen {
        case home
        case playing
    }

    enum GameOverPhase {
        case offerSecondChance
        case results
    }

    @StateObject private var sceneHolder = SceneHolder()
    @StateObject private var scoreManager = ScoreManager.shared
    @StateObject private var progress = ProgressManager.shared
    @StateObject private var settings = GameSettings.shared
    @StateObject private var rewarded = RewardedAdManager.shared

    @State private var screen: Screen = .home
    @State private var mode: GameMode = .endless

    @State private var score = 0
    @State private var nextTier: CelestialTier = .dust
    @State private var nextPolarity: Polarity = .neutral
    @State private var comboLevel = 0
    @State private var comboToken = 0
    @State private var danger: Double = 0
    @State private var scoreBump = false

    @State private var showGameOver = false
    @State private var gameOverPhase: GameOverPhase = .results
    @State private var showPause = false
    @State private var showTutorial = false
    @State private var showSettings = false
    @State private var showStore = false
    @State private var isWatchingAd = false

    @State private var lastRun: RunStats?
    @State private var runFinalised = false
    @State private var isNewBest = false
    @State private var freshMissions: [Mission] = []

    private var scene: GameScene { sceneHolder.scene }

    private var isPlaying: Bool {
        screen == .playing && !showGameOver && !showPause && !showTutorial && !isWatchingAd
    }

    private var comboColor: Color {
        switch comboLevel {
        case ...3: return .cyan
        case 4...5: return .yellow
        default:   return .orange
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Measures the real safe-area insets and hands them to the scene.
            // The SpriteView ignores the safe area so the starfield reaches the
            // screen edges, which means the scene's bottom edge sits *below*
            // the banner — the floor has to be lifted by the same amount or the
            // ad covers the floor and the bodies resting on it.
            GeometryReader { geo in
                Color.clear
                    .onAppear { pushSafeArea(geo.safeAreaInsets) }
                    .onChange(of: geo.safeAreaInsets) { insets in pushSafeArea(insets) }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            SpriteView(scene: scene, isPaused: !isPlaying)
                .ignoresSafeArea()
                .allowsHitTesting(isPlaying)

            comboGlow
            dangerGlow

            if screen == .playing {
                playingChrome
            }

            if screen == .home {
                HomeView(
                    onPlayEndless: { start(mode: .endless) },
                    onPlayDaily: { start(mode: DailyChallenge.today().mode) },
                    onOpenStore: { showStore = true },
                    onOpenSettings: { showSettings = true },
                    onHowToPlay: { showTutorial = true }
                )
                .transition(.opacity)
            }

            if showTutorial {
                TutorialView {
                    settings.hasSeenTutorial = true
                    withAnimation { showTutorial = false }
                }
                .zIndex(10)
            }

            if showPause {
                PauseView(
                    onResume: { withAnimation { showPause = false } },
                    onRestart: {
                        withAnimation { showPause = false }
                        restartCurrentMode()
                    },
                    onQuit: { returnHome() },
                    onSettings: { showSettings = true }
                )
                .zIndex(11)
            }

            if showGameOver, let run = lastRun {
                gameOverLayer(run: run)
                    .zIndex(12)
            }

            if showSettings {
                SettingsView { showSettings = false }
                    .zIndex(20)
            }

            if showStore {
                StoreView { showStore = false }
                    .zIndex(20)
            }

            if isWatchingAd {
                Color.black.opacity(0.55).ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.4)
                    .zIndex(30)
            }
        }
        .onAppear(perform: wireScene)
    }

    // MARK: - Chrome while playing

    private var playingChrome: some View {
        VStack(spacing: 0) {
            hud
                .padding(.horizontal)
                .padding(.top, 6)

            Spacer()

            BannerView()
                .frame(height: Layout.bannerHeight)
        }
    }

    private var hud: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.isDaily ? "DAILY" : "SCORE")
                    .font(.caption.weight(.heavy))
                    .foregroundColor(.gray)
                Text("\(score)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .scaleEffect(scoreBump ? 1.16 : 1.0, anchor: .leading)
                if comboLevel > 1 {
                    Text("\(comboLevel)x CHAIN")
                        .font(.caption2.weight(.black))
                        .foregroundColor(comboColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            Spacer(minLength: 4)

            VStack(spacing: 3) {
                Text("NEXT")
                    .font(.caption.weight(.heavy))
                    .foregroundColor(.gray)
                NextOrbView(tier: nextTier, polarity: nextPolarity, diameter: 38)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text("BEST")
                    .font(.caption.weight(.heavy))
                    .foregroundColor(.gray)
                Text("\(mode.isDaily ? scoreManager.dailyChallengeBest : scoreManager.bestScore)")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)

                Button {
                    HapticManager.shared.tick()
                    AudioManager.shared.play(.tap, volume: 0.5)
                    withAnimation { showPause = true }
                } label: {
                    Image(systemName: "pause.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.75))
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var comboGlow: some View {
        Group {
            if comboLevel > 1 && !settings.reducedFlash {
                Rectangle()
                    .stroke(comboColor, lineWidth: 90)
                    .blur(radius: 45)
                    .opacity(min(Double(comboLevel) / 6.0, 1.0) * 0.55)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
    }

    private var dangerGlow: some View {
        Group {
            if danger > 0.05 && screen == .playing {
                Rectangle()
                    .stroke(Color.red, lineWidth: 110)
                    .blur(radius: 55)
                    .opacity(danger * 0.7)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.25), value: danger)
            }
        }
    }

    // MARK: - Game over

    @ViewBuilder
    private func gameOverLayer(run: RunStats) -> some View {
        switch gameOverPhase {
        case .offerSecondChance:
            SecondChanceView(
                score: run.finalScore,
                onWatch: { takeSecondChance() },
                onDecline: {
                    finaliseRun()
                    withAnimation { gameOverPhase = .results }
                }
            )
        case .results:
            GameOverView(
                run: run,
                mode: mode,
                isNewBest: isNewBest,
                completedMissions: freshMissions,
                scoreManager: scoreManager,
                progress: progress,
                onRetry: {
                    showInterstitialThen { restartCurrentMode() }
                },
                onHome: {
                    showInterstitialThen { returnHome() }
                }
            )
        }
    }

    // MARK: - Wiring

    private func pushSafeArea(_ insets: EdgeInsets) {
        scene.setSafeAreaInsets(top: insets.top, bottom: insets.bottom)
    }

    private func wireScene() {
        guard scene.onGameOver == nil else { return }   // wire exactly once

        scene.onScoreChanged = { newScore in
            score = newScore
            withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { scoreBump = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { scoreBump = false }
            }
        }

        scene.onNextTierChanged = { tier, polarity in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                nextTier = tier
                nextPolarity = polarity
            }
        }

        scene.onComboChanged = { combo in
            guard combo > 1 else {
                withAnimation { comboLevel = 0 }
                return
            }
            withAnimation(.easeOut(duration: 0.12)) { comboLevel = combo }
            comboToken += 1
            let token = comboToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
                if token == comboToken {
                    withAnimation(.easeOut(duration: 0.4)) { comboLevel = 0 }
                }
            }
        }

        scene.onDangerChanged = { value in
            danger = value
        }

        scene.onGameOver = { stats in
            handleGameOver(stats)
        }
    }

    // MARK: - Flow

    private func start(mode newMode: GameMode) {
        mode = newMode
        scene.configure(mode: newMode)
        resetRunState()
        scene.resetGame()
        withAnimation(.easeOut(duration: 0.25)) {
            screen = .playing
        }
        if !settings.hasSeenTutorial {
            showTutorial = true
        }
        AudioManager.shared.play(.tap, volume: 0.6)
    }

    private func restartCurrentMode() {
        resetRunState()
        scene.resetGame()
        screen = .playing
    }

    private func returnHome() {
        resetRunState()
        withAnimation(.easeOut(duration: 0.25)) {
            screen = .home
        }
    }

    private func resetRunState() {
        showGameOver = false
        showPause = false
        gameOverPhase = .results
        lastRun = nil
        runFinalised = false
        isNewBest = false
        freshMissions = []
        comboLevel = 0
        danger = 0
        score = 0
    }

    private func handleGameOver(_ stats: RunStats) {
        lastRun = stats
        runFinalised = false

        // A Second Chance is only offered when it is genuinely available: not
        // in a Daily Challenge, not twice in a run, not on a zero score, and
        // only when an ad is actually loaded — a button that fails to deliver
        // is worse than no button.
        let canOffer = scene.canOfferSecondChance
            && stats.finalScore > 0
            && rewarded.isReady

        if canOffer {
            gameOverPhase = .offerSecondChance
        } else {
            finaliseRun()
            gameOverPhase = .results
        }
        withAnimation { showGameOver = true }
    }

    /// Banks the run exactly once: leaderboards, missions, shards.
    private func finaliseRun() {
        guard let stats = lastRun, !runFinalised else { return }
        runFinalised = true

        let dailyCompleted = stats.isDaily && stats.finalScore > 0
        isNewBest = scoreManager.submit(score: stats.finalScore,
                                        mode: mode,
                                        assisted: stats.wasAssisted)
        freshMissions = progress.applyRun(stats, dailyCompleted: dailyCompleted)
        InterstitialAdManager.shared.noteRunFinished()

        if !freshMissions.isEmpty {
            AudioManager.shared.play(.unlock, volume: 0.8)
        }
    }

    private func takeSecondChance() {
        isWatchingAd = true
        InterstitialAdManager.shared.noteFullScreenAdShown()
        rewarded.show { earned in
            isWatchingAd = false
            if earned {
                // The run resumes with its score intact — but it is now flagged
                // as assisted, so it will bank to the Marathon board.
                withAnimation { showGameOver = false }
                gameOverPhase = .results
                runFinalised = false
                scene.grantSecondChance()
            } else {
                finaliseRun()
                withAnimation { gameOverPhase = .results }
            }
        }
    }

    private func showInterstitialThen(_ action: @escaping () -> Void) {
        // Read the flag *before* running the action, which resets run state.
        let wasPersonalBest = isNewBest
        InterstitialAdManager.shared.showAdIfAppropriate(isPersonalBest: wasPersonalBest)
        action()
    }
}

// MARK: - Small shared pieces

struct NextOrbView: View {
    let tier: CelestialTier
    let polarity: Polarity
    var diameter: CGFloat = 40

    var body: some View {
        ZStack {
            Circle()
                .fill(tier.gradient)
                .overlay(
                    Circle().stroke(polarity == .neutral
                                    ? Color(uiColor: tier.glowColor).opacity(0.6)
                                    : polarity.color.opacity(0.95),
                                    lineWidth: 2)
                )
                .frame(width: diameter, height: diameter)
                .shadow(color: polarity == .neutral
                        ? Color(uiColor: tier.glowColor).opacity(0.85)
                        : polarity.color.opacity(0.85),
                        radius: 9)
            if polarity != .neutral {
                Text(polarity.symbol)
                    .font(.system(size: diameter * 0.6, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))
            }
        }
    }
}

struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

/// The app's one button style, so every screen matches.
struct CosmicButton: View {
    let title: String
    var systemImage: String? = nil
    var colors: [Color] = [.cyan, .purple]
    var isProminent: Bool = true
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.shared.tick()
            AudioManager.shared.play(.tap, volume: 0.6)
            action()
        } label: {
            HStack(spacing: 8) {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.headline)
            .foregroundColor(isProminent ? .black : .white)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                Group {
                    if isProminent {
                        LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                    } else {
                        Color.white.opacity(0.10)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

/// A dimmed, blurred card used by every modal in the game.
struct ModalCard<Content: View>: View {
    var maxHeightFraction: CGFloat = 0.8
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
            VStack(spacing: 0) {
                content()
            }
            .frame(maxHeight: UIScreen.main.bounds.height * maxHeightFraction)
            .background(BlurView(style: .systemMaterialDark))
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay(
                RoundedRectangle(cornerRadius: 26)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .purple.opacity(0.45), radius: 22)
            .padding(20)
        }
    }
}
