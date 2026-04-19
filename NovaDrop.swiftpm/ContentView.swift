import SwiftUI
import SpriteKit

struct ContentView: View {
    @State private var score: Int = 0
    @State private var showGameOver: Bool = false
    @State private var showTutorial: Bool = !UserDefaults.standard.bool(forKey: "HasSeenTutorial")
    @State private var highScore: Int = UserDefaults.standard.integer(forKey: "HighScore")
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
                        Text("\(highScore)")
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
                GameOverView(score: score, highScore: highScore) {
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
                if newScore > self.highScore {
                    self.highScore = newScore
                    UserDefaults.standard.set(newScore, forKey: "HighScore")
                }
            }
            gameScene.onGameOver = {
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
    let highScore: Int
    let onRetry: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text("COSMOS FULL")
                    .font(.system(size: 40, weight: .black))
                    .foregroundColor(.white)
                
                HStack(spacing: 40) {
                    VStack {
                        Text("Score")
                            .foregroundColor(.gray)
                        Text("\(score)")
                            .font(.title)
                            .bold()
                            .foregroundColor(.white)
                    }
                    VStack {
                        Text("Best")
                            .foregroundColor(.gray)
                        Text("\(highScore)")
                            .font(.title)
                            .bold()
                            .foregroundColor(.white)
                    }
                }
                .padding()
                
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
                .padding(.horizontal, 40)
            }
            .padding(30)
            .background(BlurView(style: .systemMaterialDark))
            .clipShape(RoundedRectangle(cornerRadius: 25))
            .shadow(color: .purple.opacity(0.5), radius: 20, x: 0, y: 0)
            .padding(20)
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
