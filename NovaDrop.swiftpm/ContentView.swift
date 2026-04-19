import SwiftUI
import SpriteKit

struct ContentView: View {
    @State private var score: Int = 0
    @State private var showGameOver: Bool = false
    @State private var showTutorial: Bool = !UserDefaults.standard.bool(forKey: "HasSeenTutorial")
    @StateObject private var scoreManager = ScoreManager.shared
    @State private var nextTier: CelestialTier = .dust
    
    @State private var gameScene: GameScene = {
        let scene = GameScene()
        scene.scaleMode = .resizeFill
        return scene
    }()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            SpriteView(scene: gameScene)
                .allowsHitTesting(!showTutorial && !showGameOver)
            
            VStack {
                HStack {
                    VStack(alignment: .leading) {
                        Text("SCORE")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("\(score)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    VStack {
                        Text("NEXT")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Circle()
                            .fill(nextTier.gradient)
                            .frame(width: 40, height: 40)
                            .shadow(color: Color(uiColor: nextTier.glowColor).opacity(0.9), radius: 10)
                            .animation(.spring(), value: nextTier)
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
                withAnimation {
                    self.showGameOver = true
                }
            }
            gameScene.onNextTierChanged = { tier in
                self.nextTier = tier
            }
            self.nextTier = gameScene.currentNextTier
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
