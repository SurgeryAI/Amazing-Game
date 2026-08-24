import SwiftUI

// MARK: - Pause

struct PauseView: View {
    let onResume: () -> Void
    let onRestart: () -> Void
    let onQuit: () -> Void
    let onSettings: () -> Void

    var body: some View {
        ModalCard(maxHeightFraction: 0.55) {
            VStack(spacing: 14) {
                Text("PAUSED")
                    .font(.system(size: 30, weight: .black))
                    .foregroundColor(.white)
                Text("The cosmos will wait.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.bottom, 4)

                CosmicButton(title: "RESUME", systemImage: "play.fill", action: onResume)
                CosmicButton(title: "RESTART", systemImage: "arrow.clockwise",
                             isProminent: false, action: onRestart)
                CosmicButton(title: "SETTINGS", systemImage: "gearshape.fill",
                             isProminent: false, action: onSettings)
                CosmicButton(title: "QUIT TO MENU", isProminent: false, action: onQuit)
            }
            .padding(24)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    let onClose: () -> Void
    @ObservedObject private var settings = GameSettings.shared

    var body: some View {
        ModalCard(maxHeightFraction: 0.75) {
            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("SETTINGS")
                            .font(.system(size: 28, weight: .black))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)

                        toggleRow(
                            title: "Sound",
                            detail: "Merge chimes, combo blips, and warnings.",
                            symbol: "speaker.wave.2.fill",
                            isOn: $settings.soundEnabled
                        )

                        toggleRow(
                            title: "Haptics",
                            detail: "Vibration on merges and impacts.",
                            symbol: "waveform",
                            isOn: $settings.hapticsEnabled
                        )

                        toggleRow(
                            title: "Tilt Gravity",
                            detail: "Steer falling bodies by tilting the device. Off by default — it makes the game hard to play lying down. Calibrates to how you are holding the phone when a run starts.",
                            symbol: "gyroscope",
                            isOn: $settings.tiltEnabled
                        )

                        toggleRow(
                            title: "Reduce Flashing",
                            detail: "Removes full-screen flashes, screen shake, and heavy bloom.",
                            symbol: "eye.fill",
                            isOn: $settings.reducedFlash
                        )
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 24)
                    .padding(.bottom, 12)
                }

                CosmicButton(title: "DONE", action: onClose)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 22)
            }
        }
    }

    private func toggleRow(title: String, detail: String, symbol: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundColor(.cyan)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.cyan)
        }
    }
}

// MARK: - Store

struct StoreView: View {
    let onClose: () -> Void

    @ObservedObject private var progress = ProgressManager.shared
    @ObservedObject private var rewarded = RewardedAdManager.shared
    @State private var isWatchingAd = false
    @State private var message: String?

    var body: some View {
        ZStack {
            ModalCard(maxHeightFraction: 0.85) {
                VStack(spacing: 0) {
                    header
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 12) {
                            if progress.canRecoverStreak { streakRescueCard }
                            earnShardsCard
                            ForEach(OrbTheme.allCases) { theme in
                                themeRow(theme)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                    }
                    CosmicButton(title: "DONE", action: onClose)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 22)
                        .padding(.top, 6)
                }
            }

            if isWatchingAd {
                Color.black.opacity(0.5).ignoresSafeArea()
                ProgressView().tint(.white).scaleEffect(1.3)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("THEMES")
                .font(.system(size: 28, weight: .black))
                .foregroundColor(.white)
            HStack(spacing: 5) {
                Image(systemName: "sparkles").foregroundColor(.yellow)
                Text("\(progress.shards) Star Shards")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white.opacity(0.9))
            }
            Text("Themes change colour only. They never change how anything plays.")
                .font(.caption2)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if let message = message {
                Text(message)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.green)
            }
        }
        .padding(.top, 24)
        .padding(.bottom, 14)
    }

    private var earnShardsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("EARN SHARDS", systemImage: "sparkles")
                    .font(.caption.weight(.heavy))
                    .foregroundColor(.yellow)
                Spacer()
                Text("\(progress.adShardClaimsToday)/\(ProgressManager.maxAdShardClaimsPerDay) today")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            Text("Complete missions to earn shards, or watch a short ad for \(ProgressManager.shardsPerAdClaim).")
                .font(.caption2)
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)

            if progress.canClaimAdShards {
                CosmicButton(title: "WATCH FOR \(ProgressManager.shardsPerAdClaim) SHARDS",
                             systemImage: "play.rectangle.fill",
                             colors: [.yellow, .orange]) {
                    watchAd { progress.grantAdShards(); flash("+\(ProgressManager.shardsPerAdClaim) shards") }
                }
            } else {
                Text("Back tomorrow for more.")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.yellow.opacity(0.08)))
    }

    private var streakRescueCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("STREAK AT RISK", systemImage: "flame.fill")
                .font(.caption.weight(.heavy))
                .foregroundColor(.orange)
            Text("Your \(progress.recoverableStreakValue)-day streak broke. Watch an ad to restore it — it changes no score and unlocks nothing.")
                .font(.caption2)
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
            CosmicButton(title: "RESTORE STREAK",
                         systemImage: "flame.fill",
                         colors: [.orange, .red]) {
                watchAd { progress.recoverStreak(); flash("Streak restored") }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.orange.opacity(0.10)))
    }

    private func themeRow(_ theme: OrbTheme) -> some View {
        let owned = progress.owns(theme)
        let active = progress.activeTheme == theme

        return HStack(spacing: 12) {
            HStack(spacing: -6) {
                ForEach(Array(theme.previewColors.enumerated()), id: \.offset) { _, color in
                    Circle()
                        .fill(color)
                        .frame(width: 20, height: 20)
                        .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
                }
            }
            .frame(width: 92, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(theme.displayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)
                Text(theme.blurb)
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            themeAction(theme: theme, owned: owned, active: active)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(active ? Color.cyan.opacity(0.12) : Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(active ? Color.cyan.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func themeAction(theme: OrbTheme, owned: Bool, active: Bool) -> some View {
        if active {
            Text("ACTIVE")
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(.cyan)
        } else if owned {
            Button {
                HapticManager.shared.tick()
                AudioManager.shared.play(.tap, volume: 0.6)
                progress.activeTheme = theme
            } label: {
                Text("EQUIP")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(.black)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.9)))
            }
        } else {
            Button {
                guard progress.canAfford(theme) else {
                    HapticManager.shared.impact(intensity: 0.4, sharpness: 0.8)
                    flash("Not enough shards yet")
                    return
                }
                if progress.purchase(theme) {
                    progress.activeTheme = theme
                    AudioManager.shared.play(.unlock, volume: 0.9)
                    HapticManager.shared.impact(intensity: 0.8, sharpness: 0.5)
                    flash("\(theme.displayName) unlocked")
                }
            } label: {
                HStack(spacing: 3) {
                    Text("\(theme.cost)")
                    Image(systemName: "sparkles").font(.system(size: 9))
                }
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(progress.canAfford(theme) ? .black : .white.opacity(0.5))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(
                    Capsule().fill(progress.canAfford(theme)
                                   ? Color.yellow.opacity(0.95)
                                   : Color.white.opacity(0.10))
                )
            }
        }
    }

    private func watchAd(_ onEarned: @escaping () -> Void) {
        guard rewarded.isReady else {
            flash("No ad available right now")
            return
        }
        isWatchingAd = true
        InterstitialAdManager.shared.noteFullScreenAdShown()
        rewarded.show { earned in
            isWatchingAd = false
            if earned {
                onEarned()
            } else {
                flash("Reward not earned")
            }
        }
    }

    private func flash(_ text: String) {
        message = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if message == text { message = nil }
        }
    }
}

// MARK: - Tutorial

struct TutorialView: View {
    let onDismiss: () -> Void

    var body: some View {
        ModalCard(maxHeightFraction: 0.85) {
            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("HOW TO PLAY")
                            .font(.system(size: 30, weight: .black))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 4)

                        rule(icon: "hand.point.up.left.fill", tint: .cyan,
                             title: "Aim and drop",
                             text: "Drag anywhere to slide your body left or right, then release to drop it.")

                        rule(icon: "sparkles", tint: .yellow,
                             title: "Merge to grow",
                             text: "Two identical bodies fuse into the next one up: Dust → Meteor → Moon → Planet → Gas Giant → Star → Black Hole. Chain merges quickly for a combo multiplier.")

                        rule(icon: "bolt.fill", tint: .orange,
                             title: "Charges attract and repel",
                             text: "A body marked + or − pulls on opposite charges and shoves away matching ones. Two like-charged bodies refuse to merge — but a charge fades after a few seconds, and the symbol blinks before it goes. Wait it out, or use the pull to line up a chain.")

                        rule(icon: "burst.fill", tint: .red,
                             title: "Antimatter clears the board",
                             text: "Rare red orbs annihilate everything they touch within a short radius. Drop one into a jam.")

                        rule(icon: "circle.hexagongrid.fill", tint: .purple,
                             title: "The Big Crunch",
                             text: "Two Black Holes colliding collapse the whole region around them for a huge score. It is the best thing that can happen in a run.")

                        rule(icon: "exclamationmark.triangle.fill", tint: .red,
                             title: "Don't overflow",
                             text: "If settled bodies stay above the dashed line, the cosmos collapses. The edges glow red as you get close.")
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 24)
                    .padding(.bottom, 12)
                }

                CosmicButton(title: "GOT IT — LET'S PLAY", action: onDismiss)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 22)
                    .padding(.top, 6)
            }
        }
    }

    private func rule(icon: String, tint: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(tint)
                .font(.title3)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)
                Text(text)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
