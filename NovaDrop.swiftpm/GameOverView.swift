import SwiftUI

/// Offered once per Endless run, never in a Daily Challenge.
///
/// The copy is deliberately explicit about the cost: taking it moves the run
/// off the Pure board. A player should never discover after the fact that a
/// record "doesn't count" — that is the thing that makes a continue feel like
/// cheating rather than a choice.
struct SecondChanceView: View {
    let score: Int
    let onWatch: () -> Void
    let onDecline: () -> Void

    var body: some View {
        ModalCard(maxHeightFraction: 0.7) {
            VStack(spacing: 18) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(
                        LinearGradient(colors: [.cyan, .purple],
                                       startPoint: .top, endPoint: .bottom)
                    )

                Text("ONE MORE CHANCE?")
                    .font(.system(size: 26, weight: .black))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                VStack(spacing: 4) {
                    Text("\(score)")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.cyan, .purple],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                    Text("and still going")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Text("Watch a short ad to clear the six highest bodies and keep this run alive.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("A rescued run is scored on the **Marathon** board instead of your Pure best. Your unassisted record stays untouched.")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.10)))

                VStack(spacing: 10) {
                    CosmicButton(title: "WATCH & CONTINUE",
                                 systemImage: "play.rectangle.fill",
                                 action: onWatch)
                    CosmicButton(title: "END THE RUN",
                                 isProminent: false,
                                 action: onDecline)
                }
            }
            .padding(24)
        }
    }
}

struct GameOverView: View {

    let run: RunStats
    let mode: GameMode
    let isNewBest: Bool
    let completedMissions: [Mission]
    @ObservedObject var scoreManager: ScoreManager
    @ObservedObject var progress: ProgressManager
    let onRetry: () -> Void
    let onHome: () -> Void

    private let medals = ["🥇", "🥈", "🥉"]

    var body: some View {
        ModalCard(maxHeightFraction: 0.82) {
            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        titleBlock
                        scoreBlock
                        if run.wasAssisted { assistedBadge }
                        boards
                        if !completedMissions.isEmpty { missionsBlock }
                        runSummary
                    }
                    .padding(.top, 24)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 12)
                }

                VStack(spacing: 10) {
                    CosmicButton(title: "PLAY AGAIN", systemImage: "arrow.clockwise", action: onRetry)
                    CosmicButton(title: "HOME", isProminent: false, action: onHome)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Pieces

    private var titleBlock: some View {
        Text(mode.isDaily ? "CHALLENGE OVER" : "COSMOS FULL")
            .font(.system(size: 30, weight: .black))
            .foregroundColor(.white)
    }

    private var scoreBlock: some View {
        VStack(spacing: 6) {
            Text("\(run.finalScore)")
                .font(.system(size: 52, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [.cyan, .purple],
                                   startPoint: .leading, endPoint: .trailing)
                )
            if isNewBest && run.finalScore > 0 {
                Text(bestLabel)
                    .font(.subheadline.weight(.heavy))
                    .foregroundColor(.yellow)
            }
        }
    }

    private var bestLabel: String {
        if mode.isDaily { return "🎉 BEST RUN OF THE DAY!" }
        return run.wasAssisted ? "🏃 NEW MARATHON BEST!" : "🎉 NEW ALL-TIME BEST!"
    }

    private var assistedBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.counterclockwise")
            Text("Second Chance used — scored on Marathon")
        }
        .font(.caption2.weight(.semibold))
        .foregroundColor(.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.orange.opacity(0.14)))
    }

    @ViewBuilder
    private var boards: some View {
        if mode.isDaily {
            HStack(alignment: .top, spacing: 16) {
                column(title: "TODAY", icon: "sun.max.fill", tint: .orange,
                       scores: scoreManager.dailyChallengeBest > 0 ? [scoreManager.dailyChallengeBest] : [])
                divider
                column(title: "BEST DAILY", icon: "calendar", tint: .cyan,
                       scores: scoreManager.dailyChallengeAllTimeBest > 0
                               ? [scoreManager.dailyChallengeAllTimeBest] : [])
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
        } else {
            HStack(alignment: .top, spacing: 16) {
                column(title: "PURE", icon: "crown.fill", tint: .yellow,
                       scores: scoreManager.allTimeTop3)
                divider
                column(title: "TODAY", icon: "sun.max.fill", tint: .orange,
                       scores: scoreManager.todayTop3)
                divider
                column(title: "MARATHON", icon: "figure.run", tint: .mint,
                       scores: scoreManager.marathonTop3)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 1)
            .padding(.vertical, 4)
    }

    private func column(title: String, icon: String, tint: Color, scores: [Int]) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(tint)
                    .font(.system(size: 9))
                Text(title)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(.gray)
            }

            if scores.isEmpty {
                Text("—")
                    .font(.body)
                    .foregroundColor(.gray.opacity(0.5))
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(scores.prefix(3).enumerated()), id: \.offset) { index, value in
                    HStack(spacing: 3) {
                        Text(medals[min(index, medals.count - 1)])
                            .font(.system(size: 11))
                        Spacer(minLength: 0)
                        Text("\(value)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(index == 0 ? .white : .white.opacity(0.65))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var missionsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.green)
                Text("MISSION COMPLETE")
                    .font(.caption.weight(.heavy))
                    .foregroundColor(.green)
            }
            ForEach(completedMissions) { mission in
                HStack {
                    Text(mission.title)
                        .font(.footnote)
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    HStack(spacing: 2) {
                        Text("+\(mission.reward)")
                            .font(.caption.weight(.bold))
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.yellow)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.green.opacity(0.10)))
    }

    private var runSummary: some View {
        HStack(spacing: 0) {
            summaryItem(value: "\(run.merges)", label: "merges")
            summaryItem(value: run.maxCombo > 1 ? "\(run.maxCombo)x" : "—", label: "best chain")
            summaryItem(value: "\(progress.streak)", label: "day streak")
        }
        .padding(.vertical, 6)
    }

    private func summaryItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}
