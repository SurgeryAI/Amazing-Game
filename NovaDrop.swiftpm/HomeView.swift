import SwiftUI

struct HomeView: View {

    let onPlayEndless: () -> Void
    let onPlayDaily: () -> Void
    let onOpenStore: () -> Void
    let onOpenSettings: () -> Void
    let onHowToPlay: () -> Void

    @ObservedObject private var progress = ProgressManager.shared
    @ObservedObject private var scores = ScoreManager.shared

    private var challenge: DailyChallenge { DailyChallenge.today() }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.55), Color.black.opacity(0.88)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 14) {
                        dailyCard
                        endlessCard
                        missionsCard
                        footerButtons
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 26)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Text("GRAVITY")
                .font(.system(size: 38, weight: .black, design: .rounded))
                // `tracking` must come before `foregroundStyle`: on iOS 16
                // `foregroundStyle` returns `some View`, and `tracking` only
                // exists on `Text`.
                .tracking(6)
                .foregroundStyle(
                    LinearGradient(colors: [.cyan, .purple],
                                   startPoint: .leading, endPoint: .trailing)
                )
            Text("CASCADE")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .tracking(12)
                .offset(y: -8)

            HStack(spacing: 16) {
                statChip(icon: "flame.fill",
                         tint: progress.streak > 0 ? .orange : .gray,
                         text: "\(progress.streak) day streak")
                statChip(icon: "sparkles", tint: .yellow, text: "\(progress.shards)")
            }
            .padding(.top, 2)
        }
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private func statChip(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .foregroundColor(tint)
            Text(text)
                .font(.footnote.weight(.bold))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    // MARK: - Daily

    private var dailyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("DAILY CHALLENGE", systemImage: "calendar")
                    .font(.caption.weight(.heavy))
                    .foregroundColor(.cyan)
                Spacer()
                Text("resets in \(DailyChallenge.timeUntilNextChallenge())")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            HStack(spacing: 12) {
                Image(systemName: challenge.modifier.symbolName)
                    .font(.title2)
                    .foregroundColor(.cyan)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.modifier.title)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(challenge.modifier.blurb)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Everyone gets the exact same sequence today. No second chances — this board is pure.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)

            if scores.dailyChallengeBest > 0 {
                HStack {
                    Text("Today's best")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.gray)
                    Spacer()
                    Text("\(scores.dailyChallengeBest)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }

            CosmicButton(title: scores.dailyChallengeBest > 0 ? "PLAY AGAIN" : "PLAY TODAY'S RUN",
                         systemImage: "play.fill",
                         action: onPlayDaily)
        }
        .padding(16)
        .background(cardBackground(tint: .cyan))
    }

    // MARK: - Endless

    private var endlessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("ENDLESS", systemImage: "infinity")
                    .font(.caption.weight(.heavy))
                    .foregroundColor(.purple)
                Spacer()
            }

            HStack(spacing: 22) {
                bestColumn(title: "PURE BEST",
                           value: scores.bestScore,
                           tint: .yellow,
                           caption: "unassisted")
                if scores.marathonBest > 0 {
                    bestColumn(title: "MARATHON",
                               value: scores.marathonBest,
                               tint: .orange,
                               caption: "with second chances")
                }
            }

            CosmicButton(title: "PLAY ENDLESS",
                         systemImage: "play.fill",
                         colors: [.purple, .indigo],
                         action: onPlayEndless)
        }
        .padding(16)
        .background(cardBackground(tint: .purple))
    }

    private func bestColumn(title: String, value: Int, tint: Color, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2.weight(.heavy))
                .foregroundColor(tint)
            Text("\(value)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(caption)
                .font(.system(size: 9))
                .foregroundColor(.gray)
        }
    }

    // MARK: - Missions

    private var missionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("TODAY'S MISSIONS", systemImage: "checklist")
                    .font(.caption.weight(.heavy))
                    .foregroundColor(.yellow)
                Spacer()
                Text("\(progress.completedMissionCount)/\(progress.missions.count)")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.gray)
            }

            ForEach(progress.missions) { mission in
                MissionRow(mission: mission)
            }
        }
        .padding(16)
        .background(cardBackground(tint: .yellow))
    }

    // MARK: - Footer

    private var footerButtons: some View {
        HStack(spacing: 10) {
            iconButton("bag.fill", "Themes", onOpenStore)
            iconButton("questionmark.circle.fill", "How to play", onHowToPlay)
            iconButton("gearshape.fill", "Settings", onOpenSettings)
        }
    }

    private func iconButton(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.shared.tick()
            AudioManager.shared.play(.tap, volume: 0.5)
            action()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.title3)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(.white.opacity(0.8))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
        }
    }

    private func cardBackground(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            )
    }
}

struct MissionRow: View {
    let mission: Mission

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: mission.isComplete ? "checkmark.circle.fill" : mission.symbolName)
                .foregroundColor(mission.isComplete ? .green : .white.opacity(0.65))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(mission.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(mission.isComplete ? .white.opacity(0.55) : .white)
                    .strikethrough(mission.isComplete, color: .white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.10))
                        Capsule()
                            .fill(mission.isComplete
                                  ? LinearGradient(colors: [.green, .mint],
                                                   startPoint: .leading, endPoint: .trailing)
                                  : LinearGradient(colors: [.cyan, .purple],
                                                   startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * mission.fraction)
                    }
                }
                .frame(height: 4)
            }

            HStack(spacing: 2) {
                Text("+\(mission.reward)")
                    .font(.caption2.weight(.bold))
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
            }
            .foregroundColor(mission.isComplete ? .green : .yellow.opacity(0.8))
        }
    }
}
