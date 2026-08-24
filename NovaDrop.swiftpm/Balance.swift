import CoreGraphics
import Foundation

/// Every gameplay number in one place.
///
/// These live here rather than scattered through `GameScene` so a tuning pass
/// is a single file to open between playtests. Nothing in here is referenced
/// by the save format or the leaderboards, so changing a value is safe — it
/// changes how the game feels, never what a stored score means.
enum Balance {

    // MARK: - Charge decay (the difficulty ramp)
    //
    // Charges bleed off so a board can never lock permanently — but *how long*
    // they last is what the Endless ramp escalates. Early on a jam unsticks in
    // a few drops and the player gets to learn the mechanic forgivingly. Deep
    // into a run the same jam persists for the better part of a minute, so
    // sloppy charge management compounds instead of resolving itself.
    //
    // The one invariant that must never be broken: a charge ALWAYS expires,
    // and the symbol ALWAYS blinks before it does. A permanent charge
    // recreates the unwinnable-board bug this system exists to fix.

    /// Charge lifetime at the start of a run, in seconds.
    static let chargeLifetimeBase: TimeInterval = 12
    /// Charge lifetime once the ramp is fully wound up.
    static let chargeLifetimeMax: TimeInterval = 26
    /// Score at which the ramp reaches `chargeLifetimeMax`.
    static let chargeRampScore: Double = 4000
    /// Seconds of blinking warning before a charge fades.
    static let chargeWarningLead: TimeInterval = 3.0

    /// Lifetime for a charge stamped at the given score.
    ///
    /// Eased so most of the tightening happens in the first half of the ramp —
    /// the player should feel the game hardening while they are still building,
    /// not discover it only after a record run.
    static func chargeLifetime(atScore score: Int) -> TimeInterval {
        let t = min(1.0, max(0.0, Double(score) / chargeRampScore))
        let eased = 1 - pow(1 - t, 2)
        return chargeLifetimeBase + (chargeLifetimeMax - chargeLifetimeBase) * eased
    }

    // MARK: - Danger

    /// Seconds between the cosmos overflowing and the run ending.
    static let overflowGrace: TimeInterval = 2.0

    /// How far above the danger line a body's top edge must sit to register.
    static let overflowMargin: CGFloat = 8

    /// How long a body must stay above the line before it counts against you.
    ///
    /// This replaced a velocity threshold, which was subtly catastrophic: on a
    /// full board magnetism, the spawn overlap and the contact solver keep
    /// everything near the top permanently jostling, so no body ever read as
    /// "settled" and the run could not end at all. Position over time cannot be
    /// gamed that way. The slowest tier falling from the spawn point clears the
    /// line in about 0.3s, so half a second cleanly separates "falling through"
    /// from "resting on a full stack".
    static let overflowDwell: TimeInterval = 0.5

    /// How fast the countdown unwinds when the board is no longer overflowing,
    /// as a multiple of real time. Decaying rather than snapping to zero means
    /// one lucky frame cannot wipe out an accumulated countdown.
    static let overflowRecoveryRate: Double = 2.0
    /// How far below the danger line the UI vignette starts to rise.
    static let dangerProximityWindow: CGFloat = 140

    // MARK: - Scoring

    /// Seconds within which a second merge continues a chain.
    static let comboWindow: TimeInterval = 1.5
    /// Flat bonus for a Big Crunch, before the combo multiplier.
    static let bigCrunchBonus = 250
    /// Bonus per body swallowed by a Big Crunch.
    static let bigCrunchPerBody = 40

    // MARK: - Board size

    /// Multiplier on every body radius.
    ///
    /// The single cleanest difficulty knob: capacity falls with the square of
    /// this, so 1.15 leaves the board holding about a quarter fewer bodies
    /// without moving the danger line or changing the layout. Raise it to
    /// tighten the game, lower it to open it up.
    static let bodyScale: CGFloat = 1.15

    // MARK: - Drops

    /// Delay between dropping a body and the next one appearing.
    static let respawnDelay: TimeInterval = 0.25

    /// How long to wait before retrying a spawn whose drop point is occupied.
    static let spawnRetryDelay: TimeInterval = 0.15

    /// Fraction of a radius used when testing whether the drop point is clear.
    /// Below 1 so bodies must genuinely intrude on the spawn zone to block it.
    static let spawnBlockRadiusScale: CGFloat = 0.85
    /// How long an unstable orb waits before it starts shaking.
    static let unstableFuse: TimeInterval = 3.0

    // MARK: - Physics safety
    //
    // Without these a body could leave the world entirely. Dropping into an
    // already-occupied point spawns a body *inside* the stack; the solver
    // resolves that overlap with an enormous impulse, and an uncapped,
    // undamped body moving faster than its own diameter per frame passes
    // straight through the boundary. Bodies leaked out of play, the board
    // visibly emptied, and the run became unloseable.

    /// Hard ceiling on body speed, in points per second.
    static let maxBodySpeed: CGFloat = 1400
    /// Light damping so repeated magnetic forces cannot pump in energy forever.
    static let linearDamping: CGFloat = 0.08
    /// Bounce pads add energy; keep it modest.
    static let bouncePadRestitution: CGFloat = 1.2

    // MARK: - Forces

    static let blackHolePullRadius: CGFloat = 220
    static let blackHolePullStrength: CGFloat = 180
    /// Reach and pull of a charge. Deliberately short: at longer range the
    /// magnets drag same-tier opposites together on their own and the board
    /// solves itself without the player aiming anything.
    static let magnetRadius: CGFloat = 100
    static let magnetStrength: CGFloat = 140
    /// Like charges shove apart harder than opposites pull together.
    static let magnetRepelMultiplier: CGFloat = 1.5

    // MARK: - Blasts

    static let antimatterReach: CGFloat = 120
    /// Bodies an antimatter blast must clear before it leaves a bounce pad.
    static let bouncePadThreshold = 4
    static let bouncePadLifetime: TimeInterval = 12
    static let bigCrunchReach: CGFloat = 260
    /// Bodies removed from the top of the stack by a Second Chance.
    static let secondChancePurgeCount = 6

    // MARK: - Progression
    //
    // Endless ramps on score, which rewards skill with bigger raw material.
    // Daily ramps on drop index instead, so the sequence is identical for
    // every player regardless of how well any of them is doing.

    static let endlessPlanetScore = 200
    static let endlessGiantScore = 500
    static let endlessAntimatterScore = 300

    static let dailyPlanetDrop = 22
    static let dailyGiantDrop = 48
    static let dailyAntimatterDrop = 40

    /// Percent chance a fresh drop is antimatter, once unlocked.
    static let antimatterChance = 3
}
