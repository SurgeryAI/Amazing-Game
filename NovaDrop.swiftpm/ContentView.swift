import SwiftUI
import SpriteKit

struct ContentView: View {
    @State private var score: Int = 0
    @State private var showGameOver: Bool = false
    @State private var showTutorial: Bool = !UserDefaults.standard.bool(forKey: "HasSeenTutorial")
    @StateObject private var scoreManager = ScoreManager.shared
    @State private var nextTier: CelestialTier = .dust
    @State private var nextPolarity: Polarity = .neutral
    @State private var scoreBump: Bool = false
    @State private var comboLevel: Int = 0
    @State private var comboResetToken: Int = 0
    
    @State private var gameScene: GameScene = {
        let scene = GameScene()
        scene.scaleMode = .resizeFill
        return scene
    }()
    
    private var polarityColor: Color {
        switch nextPolarity {
        case .positive: return .cyan
        case .negative: return .orange
        case .neutral:  return .clear
        }
    }

    private var glowColorForNext: Color {
        nextPolarity == .neutral ? Color(uiColor: nextTier.glowColor) : polarityColor
    }

    private var comboColor: Color {
        switch comboLevel {
        case ...3: return .cyan
        case 4...5: return .yellow
        default:   return .orange
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            SpriteView(scene: gameScene)
                .allowsHitTesting(!showTutorial && !showGameOver)

            // Combo heat: an escalating edge glow during merge chains.
            if comboLevel > 1 {
                Rectangle()
                    .stroke(comboColor, lineWidth: 90)
                    .blur(radius: 45)
                    .opacity(min(Double(comboLevel) / 6.0, 1.0) * 0.65)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            VStack {
                HStack {
                    VStack(alignment: .leading) {
                        Text("SCORE")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("\(score)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .scaleEffect(scoreBump ? 1.18 : 1.0, anchor: .leading)
                            .onChange(of: score) { _ in
                                withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) {
                                    scoreBump = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                                        scoreBump = false
                                    }
                                }
                            }
                    }
                    Spacer()
                    VStack {
                        Text("NEXT")
                            .font(.headline)
                            .foregroundColor(.gray)
                        ZStack {
                            Circle()
                                .fill(nextTier.gradient)
                                .overlay(
                                    Circle().stroke(polarityColor.opacity(nextPolarity == .neutral ? 0 : 0.9), lineWidth: 2)
                                )
                                .frame(width: 40, height: 40)
                                .shadow(color: glowColorForNext.opacity(0.9), radius: 10)
                            if nextPolarity != .neutral {
                                Text(nextPolarity == .positive ? "+" : "−")
                                    .font(.system(size: 24, weight: .black, design: .rounded))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                        .animation(.spring(), value: nextTier)
                        .animation(.spring(), value: nextPolarity)
                    }
                    .frame(width: 80)
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("BEST")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("\(scoreManager.bestScore)")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color.black.opacity(0.6))
                        .background(BlurView(style: .systemThinMaterialDark).clipShape(RoundedRectangle(cornerRadius: 15)))
                )
                .padding()
                
                Spacer()
                
                BannerView()
                    .frame(height: 50)
            }
            
            if showGameOver {
                GameOverView(score: score, scoreManager: scoreManager) {
                    showGameOver = false
                    comboLevel = 0
                    gameScene.resetGame()
                    
                    // Show interstitial ad after a short delay to let the UI fade away
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        InterstitialAdManager.shared.showAd()
                    }
                }
            } else if showTutorial {
                TutorialView {
                    withAnimation {
                        UserDefaults.standard.set(true, forKey: "HasSeenTutorial")
                        showTutorial = false
                    }
                }
            }
        }
        .onAppear {
            _ = InterstitialAdManager.shared // Preload the interstitial ad
            
            gameScene.onScoreChanged = { newScore in
                self.score = newScore
            }
            gameScene.onGameOver = {
                scoreManager.submitScore(self.score)
                withAnimation { self.comboLevel = 0 }
                withAnimation {
                    self.showGameOver = true
                }
            }
            gameScene.onNextTierChanged = { tier, polarity in
                self.nextTier = tier
                self.nextPolarity = polarity
            }
            gameScene.onComboChanged = { combo in
                guard combo > 1 else { return }
                withAnimation(.easeOut(duration: 0.12)) { self.comboLevel = combo }
                self.comboResetToken += 1
                let token = self.comboResetToken
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
                    if token == self.comboResetToken {
                        withAnimation(.easeOut(duration: 0.4)) { self.comboLevel = 0 }
                    }
                }
            }
            self.nextTier = gameScene.currentNextTier
            self.nextPolarity = gameScene.currentNextPolarity
        }
    }
}

struct GameOverView: View {
    let score: Int
    @ObservedObject var scoreManager: ScoreManager
    let onRetry: () -> Void
    
    private let medals = ["🥇", "🥈", "🥉"]
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            
            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        Text("COSMOS FULL")
                            .font(.system(size: 36, weight: .black))
                            .foregroundColor(.white)
                        
                        // Current score
                        Text("\(score)")
                            .font(.system(size: 48, weight: .heavy, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(colors: [.cyan, .purple], startPoint: .leading, endPoint: .trailing)
                            )
                        
                        if score == scoreManager.allTimeTop3.first ?? 0, score > 0 {
                            Text("🎉 NEW ALL-TIME BEST!")
                                .font(.subheadline.weight(.heavy))
                                .foregroundColor(.yellow)
                        }
                        
                        // Leaderboard columns
                        HStack(alignment: .top, spacing: 16) {
                            // All-Time
                            leaderboardColumn(
                                title: "ALL-TIME",
                                icon: "crown.fill",
                                iconColor: .yellow,
                                scores: scoreManager.allTimeTop3
                            )
                            
                            // Divider
                            Rectangle()
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 1)
                                .padding(.vertical, 4)
                            
                            // Today
                            leaderboardColumn(
                                title: "TODAY",
                                icon: "sun.max.fill",
                                iconColor: .orange,
                                scores: scoreManager.todayTop3
                            )
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.06))
                        )
                    }
                    .padding(.top, 24)
                    .padding(.horizontal, 24)
                }
                
                Button(action: onRetry) {
                    Text("TRY AGAIN")
                        .font(.headline)
                        .foregroundColor(.black)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(colors: [.cyan, .purple], startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 24)
                .padding(.top, 12)
            }
            .frame(maxHeight: UIScreen.main.bounds.height * 0.70)
            .background(BlurView(style: .systemMaterialDark))
            .clipShape(RoundedRectangle(cornerRadius: 25))
            .shadow(color: .purple.opacity(0.5), radius: 20, x: 0, y: 0)
            .padding(20)
        }
    }
    
    @ViewBuilder
    private func leaderboardColumn(title: String, icon: String, iconColor: Color, scores: [Int]) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.caption)
                Text(title)
                    .font(.caption.weight(.heavy))
                    .foregroundColor(.gray)
            }
            
            if scores.isEmpty {
                Text("—")
                    .font(.title3)
                    .foregroundColor(.gray.opacity(0.5))
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(scores.enumerated()), id: \.offset) { index, s in
                    HStack {
                        Text(medals[index])
                            .font(.body)
                        Spacer()
                        Text("\(s)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(index == 0 ? .white : .white.opacity(0.7))
                    }
                    .padding(.horizontal, 6)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

struct TutorialView: View {
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            
            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 25) {
                        Text("HOW TO PLAY")
                            .font(.system(size: 32, weight: .black))
                            .foregroundColor(.white)
                        
                        VStack(alignment: .leading, spacing: 20) {
                            HStack(alignment: .top) {
                                Image(systemName: "hand.point.up.left.fill")
                                    .foregroundColor(.cyan)
                                    .font(.title)
                                    .frame(width: 36)
                                Text("1. Tap and drag left or right at the top of the screen to aim your celestial body, then release to drop it.")
                                    .foregroundColor(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            
                            HStack(alignment: .top) {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.yellow)
                                    .font(.title)
                                    .frame(width: 36)
                                Text("2. When two identical bodies touch (like two Moons), they merge into a bigger, heavier body and you gain points!")
                                    .foregroundColor(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            
                            HStack(alignment: .top) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.title)
                                    .frame(width: 36)
                                Text("3. Don't let your universe fill up! If objects pile up past the faint line at the top, the cosmos overflows and the game is over.")
                                    .foregroundColor(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding()
                    }
                    .padding(.top, 30)
                    .padding(.horizontal, 30)
                }
                
                Button(action: onDismiss) {
                    Text("GOT IT! LET'S PLAY")
                        .font(.headline)
                        .foregroundColor(.black)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(colors: [.cyan, .purple], startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
                .padding(.top, 10)
            }
            .frame(maxHeight: UIScreen.main.bounds.height * 0.75)
            .background(BlurView(style: .systemMaterialDark))
            .clipShape(RoundedRectangle(cornerRadius: 25))
            .shadow(color: .purple.opacity(0.3), radius: 20, x: 0, y: 0)
            .padding(20)
        }
    }
}
