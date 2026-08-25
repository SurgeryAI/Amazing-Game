import SpriteKit
import CoreMotion
import QuartzCore

/// What a single upcoming drop will be. Precomputing this as a value type is
/// what lets Daily Challenge runs be identical for every player: the whole
/// sequence is a pure function of the day's seed and the drop index, so it can
/// never diverge based on how well someone happens to be playing.
struct DropSpec {
    var tier: CelestialTier = .dust
    var polarity: Polarity = .neutral
    var unstable: Bool = false
}

final class GameScene: SKScene, SKPhysicsContactDelegate {

    enum PhysicsCategory {
        static let none: UInt32 = 0
        static let body: UInt32 = 0b1
        static let wall: UInt32 = 0b10
    }

    // Tuning lives in `Balance` so a difficulty pass is one file to open.

    // MARK: - Callbacks

    var onScoreChanged: ((Int) -> Void)?
    var onGameOver: ((RunStats) -> Void)?
    var onNextTierChanged: ((CelestialTier, Polarity) -> Void)?
    var onComboChanged: ((Int) -> Void)?
    /// 0 = safe, 1 = about to lose. Drives the UI danger vignette.
    var onDangerChanged: ((Double) -> Void)?

    // MARK: - Mode / randomness

    private(set) var mode: GameMode = .endless
    private(set) var modifier: DailyModifier = .standard
    private var usesSeed = false
    private var seed: UInt64 = 0

    // MARK: - State

    private var score = 0 {
        didSet { onScoreChanged?(score) }
    }
    private(set) var runStats = RunStats()
    private(set) var wasAssisted = false
    private(set) var secondChanceUsed = false

    private var isGameOver = false
    private var activeBody: SKShapeNode?
    private var activeTouch: UITouch?

    private var currentSpec = DropSpec()
    private var lookaheadSpec = DropSpec()
    private var specIndex = 0

    private var mergingIds = Set<String>()

    private let playLayer = SKNode()
    private let bgLayer = SKNode()
    private let dropGuide = SKShapeNode()
    private let landingMarker = SKShapeNode(ellipseOf: CGSize(width: 34, height: 10))
    private var dangerLine = SKShapeNode()
    private var boundary = SKNode()

    private var comboCount = 0
    private var lastMergeTime: TimeInterval = 0

    private var spawnBlockedRetries = 0
    private var gameOverTimer: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0
    private var lastWarningBeep: TimeInterval = 0
    private var lastLandSound: TimeInterval = 0
    private var reportedDanger: Double = -1

    /// False until `didMove(to:)` has built the world. Guards against a
    /// `resetGame()` arriving from the UI before SpriteKit has presented the
    /// scene, which would spawn the first orb into an unbuilt world.
    private var hasAppeared = false

    /// Safe-area insets, pushed in from the SwiftUI layer — the only layer that
    /// knows them. The scene's own edges are the *physical* screen edges, so
    /// without these the floor is drawn behind the banner and the danger line
    /// hides under the HUD.
    private var safeAreaTop: CGFloat = 0
    private var safeAreaBottom: CGFloat = 0

    private var topY: CGFloat = 0

    /// Height of the floor above the scene's bottom edge: the home indicator,
    /// then the banner, then a gap wide enough for a resting body's glow.
    private var floorY: CGFloat {
        safeAreaBottom + Layout.bannerHeight + Layout.floorPadding
    }

    /// Depth of the danger line below the scene's top edge. Clears the HUD on
    /// notched devices without stealing play area on ones with a small inset.
    private var dropLineYOffset: CGFloat {
        max(Layout.dropLineInset, safeAreaTop + Layout.hudClearance)
    }

    /// Called by the UI whenever the safe area is known or changes.
    func setSafeAreaInsets(top: CGFloat, bottom: CGFloat) {
        let newTop = max(0, top)
        let newBottom = max(0, bottom)
        guard abs(newTop - safeAreaTop) > 0.5 || abs(newBottom - safeAreaBottom) > 0.5 else { return }
        safeAreaTop = newTop
        safeAreaBottom = newBottom

        guard hasAppeared else { return }   // didMove will build with these values
        rebuildBoundary()
        layoutGuides()
        liftBodiesOffFloor()
    }

    /// After the floor moves up, any body left below it would be embedded in
    /// the new wall and shoved out hard by the solver. Seat them on it instead.
    private func liftBodiesOffFloor() {
        for child in playLayer.children {
            guard let node = child as? SKShapeNode,
                  let tierRaw = node.userData?["tier"] as? Int,
                  let tier = CelestialTier(rawValue: tierRaw) else { continue }
            let restingY = floorY + tier.radius
            if node.position.y < restingY {
                node.position.y = restingY
                node.physicsBody?.velocity = .zero
            }
        }
    }

    // MARK: - Motion

    private let motionManager = CMMotionManager()
    /// Captured when a run starts, so "level" means "however the player is
    /// actually holding the phone" instead of "perfectly upright". Playing
    /// lying down used to pin every body against one wall.
    private var tiltBaseline: Double = 0
    private var hasTiltBaseline = false

    // MARK: - Setup

    func configure(mode: GameMode) {
        self.mode = mode
        switch mode {
        case .endless:
            modifier = .standard
            usesSeed = false
            seed = 0
        case .daily(let key):
            modifier = DailyChallenge.modifier(forDateKey: key)
            usesSeed = true
            seed = mode.seed ?? stableHash(key)
        }
    }

    override func didMove(to view: SKView) {
        backgroundColor = .black
        physicsWorld.gravity = CGVector(dx: 0, dy: modifier.gravityY)
        physicsWorld.contactDelegate = self

        addChild(bgLayer)
        addChild(playLayer)
        playLayer.zPosition = 10

        buildEnvironment()
        startMotionUpdates()
        hasAppeared = true
        primeQueue()
        spawnActiveBody()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard oldSize != size, size.width > 0, size.height > 0, boundary.parent != nil else { return }
        rebuildBoundary()
        layoutGuides()
    }

    private func buildEnvironment() {
        buildCosmicBackground(in: bgLayer, size: size)
        buildTwinklingStars(in: bgLayer, size: size)
        scheduleShootingStars(in: bgLayer, size: size)

        rebuildBoundary()

        dangerLine.strokeColor = UIColor(white: 1.0, alpha: 0.30)
        dangerLine.lineWidth = 2
        dangerLine.zPosition = 5
        addChild(dangerLine)

        dropGuide.strokeColor = UIColor.white.withAlphaComponent(0.22)
        dropGuide.lineWidth = 2
        dropGuide.zPosition = 4
        addChild(dropGuide)

        landingMarker.strokeColor = UIColor.white.withAlphaComponent(0.30)
        landingMarker.fillColor = .clear
        landingMarker.lineWidth = 2
        landingMarker.zPosition = 4
        addChild(landingMarker)

        layoutGuides()
    }

    private func rebuildBoundary() {
        boundary.removeFromParent()
        boundary = SKNode()
        // The floor sits exactly on top of the banner, using the banner's own
        // constant. These were previously two independent numbers (60 here, 50
        // in SwiftUI) that quietly disagreed by ten points.
        let rect = CGRect(x: 0, y: floorY,
                          width: size.width,
                          height: max(1, size.height - floorY))
        let body = SKPhysicsBody(edgeLoopFrom: rect)
        body.categoryBitMask = PhysicsCategory.wall
        body.contactTestBitMask = PhysicsCategory.body
        body.collisionBitMask = PhysicsCategory.body
        body.restitution = 0.2
        body.friction = 0.4
        boundary.physicsBody = body
        addChild(boundary)
    }

    private func layoutGuides() {
        topY = size.height - dropLineYOffset

        let linePath = CGMutablePath()
        linePath.move(to: CGPoint(x: 0, y: topY))
        linePath.addLine(to: CGPoint(x: size.width, y: topY))
        dangerLine.path = linePath.copy(dashingWithPhase: 0, lengths: [10, 10])

        let guidePath = CGMutablePath()
        guidePath.move(to: CGPoint(x: 0, y: topY - 4))
        guidePath.addLine(to: CGPoint(x: 0, y: floorY + 4))
        dropGuide.path = guidePath.copy(dashingWithPhase: 0, lengths: [5, 9])
        dropGuide.position = CGPoint(x: size.width / 2, y: 0)

        landingMarker.position = CGPoint(x: size.width / 2, y: floorY + 8)
    }

    private func startMotionUpdates() {
        guard motionManager.isAccelerometerAvailable, !motionManager.isAccelerometerActive else { return }
        motionManager.accelerometerUpdateInterval = 1.0 / 30.0
        motionManager.startAccelerometerUpdates()
    }

    // MARK: - Seeded randomness
    //
    // Every roll that affects gameplay goes through these. Decorative
    // randomness (stars, nebula drift, shake) deliberately uses the system
    // generator so it can never perturb a seeded run.

    private func roll(_ range: ClosedRange<Int>, using rng: inout SeededGenerator) -> Int {
        Int.random(in: range, using: &rng)
    }

    private func rng(forIndex index: Int) -> SeededGenerator {
        if usesSeed {
            return SeededGenerator(seed: seed &+ (UInt64(bitPattern: Int64(index)) &* 0x9E3779B97F4A7C15))
        }
        return SeededGenerator(seed: UInt64.random(in: 1...UInt64.max))
    }

    // MARK: - Drop queue

    /// `currentSpec` is what the next `spawnActiveBody` will hand the player;
    /// `lookaheadSpec` is the one after that.
    private func primeQueue() {
        currentSpec = makeDropSpec(index: 0)
        lookaheadSpec = makeDropSpec(index: 1)
        specIndex = 2
    }

    private func advanceQueue() -> DropSpec {
        let spawning = currentSpec
        currentSpec = lookaheadSpec
        lookaheadSpec = makeDropSpec(index: specIndex)
        specIndex += 1
        // The NEXT indicator shows what follows the orb now in hand, which is
        // `currentSpec` after the shift — not the lookahead.
        onNextTierChanged?(currentSpec.tier, currentSpec.polarity)
        return spawning
    }

    private func makeDropSpec(index: Int) -> DropSpec {
        var g = rng(forIndex: index)
        var spec = DropSpec()

        // Progression: in Daily mode it ramps on drop count so every player
        // sees the identical sequence; in Endless it ramps on score, which
        // rewards skill with bigger raw material.
        let progression = usesSeed ? index : score
        let planetGate = usesSeed ? Balance.dailyPlanetDrop : Balance.endlessPlanetScore
        let giantGate = usesSeed ? Balance.dailyGiantDrop : Balance.endlessGiantScore
        let antimatterGate = usesSeed ? Balance.dailyAntimatterDrop : Balance.endlessAntimatterScore

        var maxRaw = 2
        if progression >= giantGate { maxRaw = 4 }
        else if progression >= planetGate { maxRaw = 3 }
        maxRaw = min(CelestialTier.gasGiant.rawValue, maxRaw + modifier.startTierBonus)

        if progression > antimatterGate && roll(1...100, using: &g) <= Balance.antimatterChance {
            spec.tier = .antimatter
        } else {
            spec.tier = weightedTier(maxRaw: maxRaw, using: &g)
        }

        // Black holes and antimatter never carry a charge — they have their own
        // dominant behaviour and stacking magnetism on top reads as noise.
        if spec.tier != .blackHole && spec.tier != .antimatter,
           roll(1...100, using: &g) <= modifier.chargeChance {
            spec.polarity = roll(1...2, using: &g) == 1 ? .positive : .negative
        }

        spec.unstable = roll(1...100, using: &g) <= modifier.unstableChance

        return spec
    }

    /// Picks a drop tier from `Balance.dropWeights`, restricted to what has
    /// been unlocked. Consumes exactly one roll, so a seeded Daily run stays
    /// reproducible.
    private func weightedTier(maxRaw: Int, using g: inout SeededGenerator) -> CelestialTier {
        let weights = Balance.dropWeights
        let top = max(0, min(maxRaw, weights.count - 1))

        var total = 0
        for i in 0...top { total += weights[i] }
        guard total > 0 else { return .dust }

        var pick = roll(1...total, using: &g)
        for i in 0...top {
            pick -= weights[i]
            if pick <= 0 { return CelestialTier(rawValue: i) ?? .dust }
        }
        return .dust
    }

    // MARK: - Spawning

    private func spawnActiveBody() {
        guard !isGameOver, activeBody == nil else { return }

        // Never spawn into an occupied drop point.
        //
        // This is what made rapid-fire tapping into a full board an exploit
        // rather than a loss: each new body appeared *inside* the stack, and
        // the solver resolved the overlap by firing everything apart hard
        // enough to leave the world. Waiting for room instead means a board
        // with nowhere left to drop simply stops feeding the player — and the
        // bodies sitting above the danger line run out the overflow clock.
        if isSpawnBlocked(tier: currentSpec.tier) {
            spawnBlockedRetries += 1

            // A drop point that stays buried means there is nowhere left to
            // play. That is the loss, not a stall to sit in forever.
            if spawnBlockedRetries >= Balance.spawnBlockRetryLimit {
                triggerGameOver()
                return
            }

            // Peg the danger vignette while the board is jammed, so the player
            // can see the run being lost rather than just wondering where the
            // next orb went.
            if reportedDanger < 1 {
                reportedDanger = 1
                onDangerChanged?(1)
            }

            run(.sequence([
                .wait(forDuration: Balance.spawnRetryDelay),
                .run { [weak self] in self?.spawnActiveBody() }
            ]), withKey: "respawn")
            return
        }
        spawnBlockedRetries = 0

        let spec = advanceQueue()
        let node = createBodyNode(tier: spec.tier, polarity: spec.polarity)
        node.position = CGPoint(x: size.width / 2, y: topY)
        node.physicsBody = nil
        node.alpha = 0.55
        playLayer.addChild(node)
        activeBody = node

        dropGuide.position.x = size.width / 2
        landingMarker.position.x = size.width / 2
        dropGuide.removeAllActions()
        landingMarker.removeAllActions()
        dropGuide.run(.fadeAlpha(to: 1.0, duration: 0.15))
        landingMarker.run(.fadeAlpha(to: 1.0, duration: 0.15))

        // A finger held through the respawn gap keeps its aim instead of the
        // new orb snapping back to the centre.
        if let held = activeTouch {
            updateActiveBodyPosition(x: held.location(in: self).x)
        }

        if spec.unstable {
            node.userData?["unstable"] = true
            node.strokeColor = .red
            node.glowWidth = spec.tier.standardGlowWidth + 5

            let pulse = SKAction.sequence([
                .scale(to: 0.93, duration: 0.2),
                .scale(to: 1.07, duration: 0.2)
            ])
            node.run(.repeatForever(pulse), withKey: "unstableWarning")

            let shakeStep = SKAction.sequence([
                .moveBy(x: -6, y: 0, duration: 0.05),
                .moveBy(x: 12, y: 0, duration: 0.10),
                .moveBy(x: -6, y: 0, duration: 0.05)
            ])
            node.run(.sequence([
                .wait(forDuration: Balance.unstableFuse),
                .repeat(shakeStep, count: 15),
                .run { [weak self] in self?.dropActiveBody() }
            ]), withKey: "unstableTimer")
        } else {
            let breatheIn = SKAction.scale(to: 1.05, duration: 0.7)
            breatheIn.timingMode = .easeInEaseOut
            let breatheOut = SKAction.scale(to: 0.97, duration: 0.7)
            breatheOut.timingMode = .easeInEaseOut
            node.run(.repeatForever(.sequence([breatheIn, breatheOut])), withKey: "idlePulse")
        }
    }

    /// Is there already a body sitting where the next one would appear?
    private func isSpawnBlocked(tier: CelestialTier) -> Bool {
        let point = CGPoint(x: size.width / 2, y: topY)
        let clearance = tier.radius * Balance.spawnBlockRadiusScale

        for child in playLayer.children {
            guard let node = child as? SKShapeNode, node !== activeBody,
                  let data = node.userData, node.physicsBody != nil else { continue }
            if data["isBounce"] as? Bool == true { continue }
            if data["dying"] as? Bool == true { continue }
            guard let tierRaw = data["tier"] as? Int,
                  let other = CelestialTier(rawValue: tierRaw) else { continue }

            let dx = node.position.x - point.x
            let dy = node.position.y - point.y
            let minimum = clearance + other.radius * Balance.spawnBlockRadiusScale
            if dx * dx + dy * dy < minimum * minimum { return true }
        }
        return false
    }

    func createBodyNode(tier: CelestialTier, polarity: Polarity) -> SKShapeNode {
        let node = SKShapeNode(circleOfRadius: tier.radius)
        node.fillColor = .clear
        node.lineWidth = polarity == .neutral ? 1.5 : 3.0
        node.glowWidth = tier.standardGlowWidth
        node.strokeColor = polarity == .neutral ? tier.glowColor.withAlphaComponent(0.60) : polarity.uiColor

        let theme = ProgressManager.shared.activeTheme
        if let texture = FX.celestialTexture(tier: tier, radius: tier.radius, theme: theme) {
            let sprite = SKSpriteNode(texture: texture)
            sprite.size = CGSize(width: tier.radius * 2, height: tier.radius * 2)
            sprite.zPosition = 0
            sprite.name = "celestialTexture"
            node.addChild(sprite)
        }

        if tier == .antimatter {
            node.run(.repeatForever(.sequence([
                .scale(to: 0.84, duration: 0.5),
                .scale(to: 1.16, duration: 0.5)
            ])))
        }

        if tier == .gasGiant {
            let ring = SKShapeNode(ellipseOf: CGSize(width: tier.radius * 2.7,
                                                     height: tier.radius * 0.55))
            ring.fillColor = .clear
            ring.strokeColor = tier.glowColor.withAlphaComponent(0.75)
            ring.lineWidth = 4
            ring.glowWidth = 5
            ring.zPosition = -1
            node.addChild(ring)
        }

        if tier == .star {
            let minGlow: CGFloat = 16, maxGlow: CGFloat = 36, dur: Double = 0.8
            let range = maxGlow - minGlow
            let up = SKAction.customAction(withDuration: dur) { n, elapsed in
                (n as? SKShapeNode)?.glowWidth = minGlow + (elapsed / dur) * range
            }
            let down = SKAction.customAction(withDuration: dur) { n, elapsed in
                (n as? SKShapeNode)?.glowWidth = maxGlow - (elapsed / dur) * range
            }
            node.run(.repeatForever(.sequence([up, down])), withKey: "starPulse")
        }

        if tier == .blackHole {
            let disk = SKShapeNode(ellipseOf: CGSize(width: tier.radius * 2.9,
                                                     height: tier.radius * 0.58))
            disk.fillColor = .clear
            disk.strokeColor = tier.glowColor.withAlphaComponent(0.95)
            disk.lineWidth = 6
            disk.glowWidth = 12
            disk.zPosition = -1
            disk.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 4.5)))
            node.addChild(disk)
        }

        if polarity != .neutral {
            let symbol = SKLabelNode(text: polarity.symbol)
            symbol.name = "polaritySymbol"
            symbol.fontName = "AvenirNext-Bold"
            symbol.fontSize = max(16, tier.radius * 1.1)
            symbol.fontColor = UIColor(white: 1.0, alpha: 0.95)
            symbol.horizontalAlignmentMode = .center
            symbol.verticalAlignmentMode = .center
            symbol.zPosition = 5
            node.addChild(symbol)
        }

        node.name = "tier_\(tier.rawValue)"
        let data = NSMutableDictionary()
        data["tier"] = tier.rawValue
        data["mergeId"] = UUID().uuidString
        data["polarity"] = polarity.rawValue
        node.userData = data

        return node
    }

    private func setupBodyPhysics(node: SKShapeNode, tier: CelestialTier) {
        let body = SKPhysicsBody(circleOfRadius: tier.radius)
        body.mass = tier.mass
        body.restitution = 0.1
        body.friction = Balance.bodyFriction
        body.angularDamping = 0.2
        body.linearDamping = Balance.linearDamping
        // Continuous collision detection for the small tiers, which are the
        // ones that can cross their own diameter in a single frame and pass
        // straight through a wall. The heavy tiers never move fast enough to
        // need it and it is not cheap.
        body.usesPreciseCollisionDetection = tier.rawValue <= CelestialTier.moon.rawValue
        body.categoryBitMask = PhysicsCategory.body
        body.contactTestBitMask = PhysicsCategory.body | PhysicsCategory.wall
        body.collisionBitMask = PhysicsCategory.body | PhysicsCategory.wall
        node.physicsBody = body
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isGameOver, !isPaused else { return }
        // Track exactly one touch. Previously any second finger lifting would
        // release the orb, which made a stray palm touch drop it for you.
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        updateActiveBodyPosition(x: touch.location(in: self).x)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isGameOver, !isPaused else { return }
        guard let tracked = activeTouch, touches.contains(tracked) else { return }
        updateActiveBodyPosition(x: tracked.location(in: self).x)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let tracked = activeTouch, touches.contains(tracked) else { return }
        activeTouch = nil
        guard !isGameOver, !isPaused else { return }
        dropActiveBody()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let tracked = activeTouch, touches.contains(tracked) else { return }
        activeTouch = nil
    }

    private func updateActiveBodyPosition(x: CGFloat) {
        guard let active = activeBody else { return }
        let tier = CelestialTier(rawValue: active.userData?["tier"] as? Int ?? 0) ?? .dust
        let r = tier.radius
        let clampedX = max(r, min(size.width - r, x))
        active.position.x = clampedX
        dropGuide.position.x = clampedX
        landingMarker.position.x = clampedX
    }

    private func dropActiveBody() {
        guard let active = activeBody, !isGameOver else { return }
        activeBody = nil
        activeTouch = nil

        active.removeAction(forKey: "unstableTimer")
        active.removeAction(forKey: "unstableWarning")
        active.removeAction(forKey: "idlePulse")
        active.setScale(1.0)
        active.alpha = 1.0

        dropGuide.removeAllActions()
        landingMarker.removeAllActions()
        dropGuide.run(.fadeAlpha(to: 0.0, duration: 0.15))
        landingMarker.run(.fadeAlpha(to: 0.0, duration: 0.15))

        let tier = CelestialTier(rawValue: active.userData?["tier"] as? Int ?? 0) ?? .dust
        let polarityRaw = active.userData?["polarity"] as? Int ?? 0
        let polarity = Polarity(rawValue: polarityRaw) ?? .neutral

        // An unstable body has its stroke forced red and its glow widened;
        // restore both so the dropped body reads correctly.
        active.strokeColor = polarity == .neutral ? tier.glowColor : polarity.uiColor
        active.glowWidth = tier.standardGlowWidth
        active.userData?["unstable"] = false

        // The charge clock starts on release, not on spawn, so time spent
        // aiming never eats into it.
        if polarity != .neutral {
            stampCharge(on: active, at: CACurrentMediaTime())
        }

        setupBodyPhysics(node: active, tier: tier)
        AudioManager.shared.play(.drop, volume: 0.7)

        run(.sequence([
            .wait(forDuration: Balance.respawnDelay),
            .run { [weak self] in self?.spawnActiveBody() }
        ]), withKey: "respawn")
    }

    // MARK: - Contacts

    func didBegin(_ contact: SKPhysicsContact) {
        let catA = contact.bodyA.categoryBitMask
        let catB = contact.bodyB.categoryBitMask

        if catA == PhysicsCategory.wall || catB == PhysicsCategory.wall {
            let impacted = (catA == PhysicsCategory.body ? contact.bodyA.node
                                                         : contact.bodyB.node) as? SKShapeNode
            if let n = impacted,
               contact.collisionImpulse > 1.5,
               abs(contact.contactNormal.dy) > 0.6 {
                squashLand(n)
            }
            return
        }

        guard let a = contact.bodyA.node as? SKShapeNode,
              let b = contact.bodyB.node as? SKShapeNode,
              a !== b,
              a.parent != nil, b.parent != nil else { return }

        // Bodies mid-removal keep their nodes around for the implosion
        // animation; they must not be able to merge again on the way out.
        if a.userData?["dying"] as? Bool == true { return }
        if b.userData?["dying"] as? Bool == true { return }

        let tierA = a.userData?["tier"] as? Int ?? -1
        let tierB = b.userData?["tier"] as? Int ?? -2
        let idA = a.userData?["mergeId"] as? String ?? ""
        let idB = b.userData?["mergeId"] as? String ?? ""

        guard !mergingIds.contains(idA), !mergingIds.contains(idB) else { return }

        if tierA == CelestialTier.antimatter.rawValue || tierB == CelestialTier.antimatter.rawValue {
            mergingIds.insert(idA)
            mergingIds.insert(idB)
            handleAntimatter(nodeA: a, nodeB: b, at: contact.contactPoint)
            return
        }

        guard tierA == tierB, let tier = CelestialTier(rawValue: tierA) else { return }

        let polA = a.userData?["polarity"] as? Int ?? 0
        let polB = b.userData?["polarity"] as? Int ?? 0

        // Like charges repel and refuse to fuse. With charge decay in place
        // this is now a temporary obstacle rather than a dead end.
        let likeCharges = (polA != 0 && polA == polB)
        if likeCharges { return }

        mergingIds.insert(idA)
        mergingIds.insert(idB)

        var resulting: Polarity = .neutral
        if polA != 0 && polB == 0 { resulting = Polarity(rawValue: polA) ?? .neutral }
        else if polB != 0 && polA == 0 { resulting = Polarity(rawValue: polB) ?? .neutral }

        handleMerge(nodeA: a, nodeB: b, tier: tier,
                    at: contact.contactPoint, resultingPolarity: resulting)
    }

    private func squashLand(_ node: SKShapeNode) {
        guard node.action(forKey: "squash") == nil else { return }
        let down = SKAction.scaleX(to: 1.14, y: 0.86, duration: 0.06)
        down.timingMode = .easeOut
        let up = SKAction.scaleX(to: 1.0, y: 1.0, duration: 0.16)
        up.timingMode = .easeOut
        node.run(.sequence([down, up]), withKey: "squash")

        let now = CACurrentMediaTime()
        if now - lastLandSound > 0.06 {
            lastLandSound = now
            AudioManager.shared.play(.land, volume: 0.5)
        }
    }

    // MARK: - Merging

    private func handleMerge(nodeA: SKShapeNode, nodeB: SKShapeNode,
                             tier: CelestialTier, at point: CGPoint,
                             resultingPolarity: Polarity) {
        let idA = nodeA.userData?["mergeId"] as? String ?? ""
        let idB = nodeB.userData?["mergeId"] as? String ?? ""

        nodeA.removeFromParent()
        nodeB.removeFromParent()

        let now = CACurrentMediaTime()
        comboCount = (now - lastMergeTime <= Balance.comboWindow) ? comboCount + 1 : 1
        lastMergeTime = now

        let multiplier = comboCount
        score += tier.scoreValue * multiplier
        onComboChanged?(comboCount)

        runStats.recordMerge(resultTier: tier.nextTier?.rawValue, combo: comboCount)

        if multiplier > 1 {
            showComboLabel(multiplier: multiplier, at: point)
            AudioManager.shared.play(.combo(level: multiplier), volume: 0.8)
        }

        createExplosion(at: point, color: tier.glowColor)
        spawnShockwave(in: self, at: point, color: tier.glowColor, radius: tier.radius * 2.0)
        AudioManager.shared.play(.merge(tier: tier.rawValue),
                                 volume: 0.55 + Float(tier.rawValue) * 0.06)
        HapticManager.shared.merge(tier: tier.rawValue)

        // Weighty merges get a frame of hit-stop. Slowing the simulation for a
        // beat reads as impact far more convincingly than a bigger particle
        // burst, and unlike a screen shake it cannot desync physics.
        if tier.rawValue >= CelestialTier.planet.rawValue {
            hitStop(duration: 0.05 + Double(tier.rawValue) * 0.012)
            shake(bgLayer, amplitude: 4 + CGFloat(tier.rawValue) * 1.5)
        }

        mergingIds.remove(idA)
        mergingIds.remove(idB)

        guard let nextTier = tier.nextTier else {
            // Two black holes met. This is the top of the ladder and deserves
            // to feel like the end of a universe rather than a silent removal.
            bigCrunch(at: point, multiplier: multiplier)
            return
        }

        let newNode = createBodyNode(tier: nextTier, polarity: resultingPolarity)
        newNode.position = point
        if resultingPolarity != .neutral {
            stampCharge(on: newNode, at: now)
        }
        playLayer.addChild(newNode)
        setupBodyPhysics(node: newNode, tier: nextTier)

        newNode.setScale(0.25)
        newNode.run(.sequence([
            .scale(to: 1.12, duration: 0.12),
            .scale(to: 1.0, duration: 0.08)
        ]))
    }

    /// The Big Crunch: colliding black holes collapse everything nearby.
    ///
    /// This replaces what used to happen when two black holes touched — they
    /// simply vanished, with no feedback at all, at the single most impressive
    /// moment the game can produce.
    private func bigCrunch(at point: CGPoint, multiplier: Int) {
        runStats.bigCrunches += 1

        let reach = Balance.bigCrunchReach
        let reachSq = reach * reach
        var swallowed = 0

        for child in playLayer.children {
            guard let node = child as? SKShapeNode, node !== activeBody else { continue }
            if node.userData?["dying"] as? Bool == true { continue }
            let dx = node.position.x - point.x
            let dy = node.position.y - point.y
            guard dx * dx + dy * dy <= reachSq else { continue }
            let isProp = node.userData?["isBounce"] as? Bool == true
            implode(node, toward: point)
            // Props get swallowed for the spectacle but never pay out.
            if !isProp { swallowed += 1 }
        }

        score += Balance.bigCrunchBonus * multiplier + swallowed * Balance.bigCrunchPerBody

        spawnShockwave(in: self, at: point, color: .purple, radius: reach)
        spawnShockwave(in: self, at: point, color: .white, radius: reach * 0.55)
        createExplosion(at: point, color: .purple)
        spawnFlash(in: self, color: UIColor(white: 0.9, alpha: 1), intensity: 0.42)
        shake(bgLayer, amplitude: 22, duration: 0.5)
        hitStop(duration: 0.22, scale: 0.08)
        AudioManager.shared.play(.bigCrunch, volume: 1.0)
        HapticManager.shared.bigCrunch()

        let label = SKLabelNode(text: "BIG CRUNCH")
        label.fontName = "AvenirNext-Heavy"
        label.fontSize = 34
        label.fontColor = .white
        label.position = CGPoint(x: size.width / 2, y: size.height * 0.55)
        label.zPosition = 120
        label.alpha = 0
        label.setScale(0.6)
        addChild(label)
        label.run(.sequence([
            .group([.fadeIn(withDuration: 0.12), .scale(to: 1.0, duration: 0.2)]),
            .wait(forDuration: 0.9),
            .fadeOut(withDuration: 0.4),
            .removeFromParent()
        ]))
    }

    /// Removes a body with a collapse animation, detaching physics first so it
    /// cannot generate contacts on the way out.
    private func implode(_ node: SKShapeNode, toward point: CGPoint) {
        node.physicsBody = nil
        node.userData?["dying"] = true
        if let id = node.userData?["mergeId"] as? String { mergingIds.remove(id) }
        node.removeAllActions()
        node.run(.sequence([
            .group([
                .move(to: point, duration: 0.28),
                .scale(to: 0.05, duration: 0.28),
                .fadeOut(withDuration: 0.28)
            ]),
            .removeFromParent()
        ]))
    }

    private func handleAntimatter(nodeA: SKShapeNode, nodeB: SKShapeNode, at point: CGPoint) {
        let idA = nodeA.userData?["mergeId"] as? String ?? ""
        let idB = nodeB.userData?["mergeId"] as? String ?? ""

        let reach = Balance.antimatterReach
        let reachSq = reach * reach
        var cleared = 0

        for child in playLayer.children {
            guard let node = child as? SKShapeNode, node !== activeBody else { continue }
            if node.userData?["isBounce"] as? Bool == true { continue }
            if node.userData?["dying"] as? Bool == true { continue }
            let dx = node.position.x - point.x
            let dy = node.position.y - point.y
            guard dx * dx + dy * dy <= reachSq else { continue }
            if let id = node.userData?["mergeId"] as? String { mergingIds.remove(id) }
            node.physicsBody = nil
            node.userData?["dying"] = true
            node.removeAllActions()
            node.run(.sequence([.fadeOut(withDuration: 0.12), .removeFromParent()]))
            cleared += 1
        }

        // Defensive: the pair should have been inside the blast, but never
        // leave them behind if a contact point lands oddly.
        for node in [nodeA, nodeB]
        where node.parent != nil && (node.userData?["dying"] as? Bool != true) {
            node.physicsBody = nil
            node.userData?["dying"] = true
            node.run(.sequence([.fadeOut(withDuration: 0.12), .removeFromParent()]))
            cleared += 1
        }

        mergingIds.remove(idA)
        mergingIds.remove(idB)

        runStats.antimatterDetonations += 1

        createExplosion(at: point, color: .red)
        spawnShockwave(in: self, at: point, color: .red, radius: reach)
        shake(bgLayer, amplitude: 12)
        hitStop(duration: 0.08)
        AudioManager.shared.play(.antimatter, volume: 0.9)
        HapticManager.shared.impact(intensity: 1.0, sharpness: 1.0)

        if cleared >= Balance.bouncePadThreshold {
            spawnBouncePad(at: point)
        }
    }

    private func spawnBouncePad(at location: CGPoint) {
        let size = CGSize(width: 80, height: 15)
        let pad = SKShapeNode(rectOf: size, cornerRadius: 5)
        pad.fillColor = UIColor(white: 0.9, alpha: 1.0)
        pad.strokeColor = .green
        pad.glowWidth = 8
        pad.position = location
        pad.zRotation = CGFloat.random(in: -0.4...0.4)

        let data = NSMutableDictionary()
        data["isBounce"] = true
        pad.userData = data

        let body = SKPhysicsBody(rectangleOf: size)
        body.isDynamic = false
        body.restitution = Balance.bouncePadRestitution
        body.friction = 0.2
        body.categoryBitMask = PhysicsCategory.wall
        body.contactTestBitMask = PhysicsCategory.none
        body.collisionBitMask = PhysicsCategory.body
        pad.physicsBody = body

        playLayer.addChild(pad)
        pad.run(.sequence([
            .wait(forDuration: Balance.bouncePadLifetime),
            .fadeOut(withDuration: 1.0),
            .removeFromParent()
        ]))
    }

    // MARK: - Feedback helpers

    /// Briefly slows the simulation for impact. Restored on a scene action so
    /// `resetGame`'s `removeAllActions` can never leave the world in slow-mo.
    private func hitStop(duration: TimeInterval, scale: CGFloat = 0.18) {
        physicsWorld.speed = scale
        removeAction(forKey: "hitStop")
        run(.sequence([
            .wait(forDuration: duration),
            .run { [weak self] in self?.physicsWorld.speed = 1.0 }
        ]), withKey: "hitStop")
    }

    private func showComboLabel(multiplier: Int, at position: CGPoint) {
        let label = SKLabelNode(text: "\(multiplier)x COMBO!")
        label.fontName = "AvenirNext-Heavy"
        label.fontSize = 22 + CGFloat(min(multiplier, 8)) * 3
        label.fontColor = .systemYellow
        // Keep the label on screen: a combo near an edge used to render
        // half-off, and one near the top slid under the HUD.
        let margin: CGFloat = 90
        label.position = CGPoint(
            x: max(margin, min(size.width - margin, position.x)),
            y: min(position.y, topY - 30)
        )
        label.zPosition = 100
        label.alpha = 0
        addChild(label)

        label.run(.group([
            .sequence([
                .scale(to: 1.3, duration: 0.15),
                .scale(to: 1.0, duration: 0.10)
            ]),
            .sequence([
                .fadeIn(withDuration: 0.10),
                .wait(forDuration: 0.5),
                .fadeOut(withDuration: 0.4),
                .removeFromParent()
            ]),
            .moveBy(x: 0, y: 50, duration: 0.8)
        ]))
    }

    private func createExplosion(at position: CGPoint, color: UIColor) {
        let emitter = SKEmitterNode()
        emitter.particleTexture = FX.spark
        emitter.particleBlendMode = .add
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1.0
        emitter.particleBirthRate = 1200
        emitter.numParticlesToEmit = 60
        emitter.particleLifetime = 0.6
        emitter.particleLifetimeRange = 0.3
        emitter.particlePositionRange = CGVector(dx: 15, dy: 15)
        emitter.particleSpeed = 220
        emitter.particleSpeedRange = 120
        emitter.particleAlpha = 1.0
        emitter.particleAlphaSpeed = -1.8
        emitter.particleScale = 0.6
        emitter.particleScaleRange = 0.3
        emitter.particleScaleSpeed = -0.9
        emitter.emissionAngleRange = .pi * 2
        emitter.zPosition = 40
        emitter.position = position
        addChild(emitter)
        emitter.run(.sequence([.wait(forDuration: 1.0), .removeFromParent()]))
    }

    // MARK: - Charge decay

    /// Records when a charge started and how long it gets.
    ///
    /// The lifetime is fixed at stamp time from the score *then*, so a body
    /// dropped early in a run keeps its short, forgiving fuse even if the
    /// score climbs while it sits there. The ramp raises the cost of new
    /// mistakes rather than retroactively punishing old ones.
    private func stampCharge(on node: SKShapeNode, at time: TimeInterval) {
        node.userData?["chargeBorn"] = time
        node.userData?["chargeLife"] = Balance.chargeLifetime(atScore: score)
    }

    private func neutralize(_ node: SKShapeNode) {
        guard let data = node.userData,
              (data["polarity"] as? Int ?? 0) != Polarity.neutral.rawValue else { return }

        data["polarity"] = Polarity.neutral.rawValue
        let tier = CelestialTier(rawValue: data["tier"] as? Int ?? 0) ?? .dust
        node.strokeColor = tier.glowColor

        if let symbol = node.childNode(withName: "polaritySymbol") {
            symbol.removeAction(forKey: "fading")
            symbol.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
        }
        spawnShockwave(in: self, at: node.position,
                       color: UIColor(white: 1.0, alpha: 1.0), radius: tier.radius * 1.3)
    }

    // MARK: - Game loop

    override func update(_ currentTime: TimeInterval) {
        guard !isGameOver else { return }

        if lastUpdateTime == 0 { lastUpdateTime = currentTime }
        let dt = min(0.1, currentTime - lastUpdateTime)   // clamp after a stall
        lastUpdateTime = currentTime
        let now = CACurrentMediaTime()

        applyTiltGravity()

        // One pass to collect the live bodies. This used to be rebuilt two or
        // three separate times per frame with `compactMap` + `filter`.
        var bodies: [SKShapeNode] = []
        bodies.reserveCapacity(playLayer.children.count)
        var blackHoles: [SKShapeNode] = []
        var charged: [SKShapeNode] = []

        for child in playLayer.children {
            guard let node = child as? SKShapeNode, node !== activeBody else { continue }
            guard let data = node.userData else { continue }
            if data["isBounce"] as? Bool == true { continue }
            if data["dying"] as? Bool == true { continue }
            guard node.physicsBody != nil, let tierRaw = data["tier"] as? Int else { continue }
            if let tier = CelestialTier(rawValue: tierRaw) { keepInWorld(node, tier: tier) }
            bodies.append(node)
            if tierRaw == CelestialTier.blackHole.rawValue { blackHoles.append(node) }
            if (data["polarity"] as? Int ?? 0) != Polarity.neutral.rawValue { charged.append(node) }
        }

        applyBlackHoleGravity(bodies: bodies, blackHoles: blackHoles)
        applyMagnetism(charged: charged)
        decayCharges(charged: charged, now: now)
        evaluateDanger(bodies: bodies, dt: dt, now: now)
    }

    /// Caps speed and puts back anything that has left the play area.
    ///
    /// The cap is the real fix — a body moving faster than its own diameter
    /// per frame can cross a wall between two simulation steps no matter what
    /// the collision masks say. The reposition is a belt-and-braces net for
    /// anything that still slips out, because a body that silently leaves the
    /// world takes its area off the board and makes the game unloseable.
    private func keepInWorld(_ node: SKShapeNode, tier: CelestialTier) {
        guard let pb = node.physicsBody else { return }

        let v = pb.velocity
        let speed = sqrt(v.dx * v.dx + v.dy * v.dy)
        if speed > Balance.maxBodySpeed {
            let scale = Balance.maxBodySpeed / speed
            pb.velocity = CGVector(dx: v.dx * scale, dy: v.dy * scale)
        }

        let r = tier.radius
        let minX = r, maxX = size.width - r
        let minY = floorY + r, maxY = size.height - r
        let escaped = node.position.x < minX - 30 || node.position.x > maxX + 30
                   || node.position.y < minY - 40 || node.position.y > maxY + 200
        if escaped {
            node.position = CGPoint(x: min(maxX, max(minX, node.position.x)),
                                    y: min(maxY, max(minY, node.position.y)))
            pb.velocity = .zero
            pb.angularVelocity = 0
        }
    }

    private func applyTiltGravity() {
        guard GameSettings.shared.tiltEnabled else {
            physicsWorld.gravity = CGVector(dx: 0, dy: modifier.gravityY)
            return
        }
        guard let data = motionManager.accelerometerData else { return }

        // Calibrate to however the player is holding the device when the run
        // begins, so "neutral" is their posture, not perfect vertical.
        if !hasTiltBaseline {
            tiltBaseline = data.acceleration.x
            hasTiltBaseline = true
        }

        let relative = data.acceleration.x - tiltBaseline
        var dx = relative * 3.5
        if abs(relative) < 0.08 { dx = 0 }
        dx = max(-1.5, min(1.5, dx))
        physicsWorld.gravity = CGVector(dx: CGFloat(dx), dy: modifier.gravityY)
    }

    private func applyBlackHoleGravity(bodies: [SKShapeNode], blackHoles: [SKShapeNode]) {
        guard !blackHoles.isEmpty else { return }
        let pullRadius = Balance.blackHolePullRadius
        let pullRadiusSq = pullRadius * pullRadius
        let pullStrength = Balance.blackHolePullStrength

        for hole in blackHoles {
            for body in bodies where body !== hole {
                guard let pb = body.physicsBody else { continue }
                let dx = hole.position.x - body.position.x
                let dy = hole.position.y - body.position.y
                let distSq = dx * dx + dy * dy
                guard distSq > 1, distSq < pullRadiusSq else { continue }
                let dist = sqrt(distSq)
                let scale = pullStrength * (1 - dist / pullRadius)
                pb.applyForce(CGVector(dx: dx / dist * scale, dy: dy / dist * scale))
            }
        }
    }

    private func applyMagnetism(charged: [SKShapeNode]) {
        guard charged.count > 1 else { return }
        let radius = Balance.magnetRadius
        let radiusSq = radius * radius

        for i in 0..<(charged.count - 1) {
            let a = charged[i]
            guard let pbA = a.physicsBody,
                  let polA = a.userData?["polarity"] as? Int else { continue }

            for j in (i + 1)..<charged.count {
                let b = charged[j]
                guard let pbB = b.physicsBody,
                      let polB = b.userData?["polarity"] as? Int else { continue }

                let dx = b.position.x - a.position.x
                let dy = b.position.y - a.position.y
                let distSq = dx * dx + dy * dy
                guard distSq > 1, distSq < radiusSq else { continue }

                let dist = sqrt(distSq)
                let base = Balance.magnetStrength * (1 - dist / radius)
                let magnitude = (polA != polB) ? base : -base * Balance.magnetRepelMultiplier
                let fx = (dx / dist) * magnitude
                let fy = (dy / dist) * magnitude
                pbA.applyForce(CGVector(dx: fx, dy: fy))
                pbB.applyForce(CGVector(dx: -fx, dy: -fy))
            }
        }
    }

    private func decayCharges(charged: [SKShapeNode], now: TimeInterval) {
        for node in charged {
            guard let born = node.userData?["chargeBorn"] as? TimeInterval else { continue }
            let life = node.userData?["chargeLife"] as? TimeInterval ?? Balance.chargeLifetimeBase
            let age = now - born
            if age >= life {
                neutralize(node)
            } else if age >= life - Balance.chargeWarningLead,
                      node.childNode(withName: "polaritySymbol")?.action(forKey: "fading") == nil {
                // Telegraph the final seconds so the decay never feels like
                // something that just happened to the player.
                node.childNode(withName: "polaritySymbol")?.run(
                    .repeatForever(.sequence([
                        .fadeAlpha(to: 0.25, duration: 0.25),
                        .fadeAlpha(to: 0.9, duration: 0.25)
                    ])), withKey: "fading")
            }
        }
    }

    private func evaluateDanger(bodies: [SKShapeNode], dt: TimeInterval, now: TimeInterval) {
        var highestTop: CGFloat = 0
        var isOverflowing = false

        for node in bodies {
            guard let data = node.userData,
                  let tierRaw = data["tier"] as? Int,
                  let tier = CelestialTier(rawValue: tierRaw) else { continue }
            let topEdge = node.position.y + tier.radius
            highestTop = max(highestTop, topEdge)

            guard topEdge > topY + Balance.overflowMargin else {
                data["aboveSince"] = nil
                continue
            }

            // How long the body has hung above the line — not how fast it is
            // moving. A freshly dropped orb spawns at the line and falls
            // through it in about a third of a second, so it never reaches the
            // dwell threshold; a body resting on a full stack never leaves.
            if let since = data["aboveSince"] as? TimeInterval {
                if now - since >= Balance.overflowDwell { isOverflowing = true }
            } else {
                data["aboveSince"] = now
            }
        }

        if isOverflowing {
            gameOverTimer += dt
            if now - lastWarningBeep > 0.75 {
                lastWarningBeep = now
                AudioManager.shared.play(.danger, volume: 0.75)
                HapticManager.shared.warning()
            }
            if gameOverTimer >= Balance.overflowGrace {
                triggerGameOver()
                return
            }
        } else {
            // Unwind rather than reset. A hard reset meant a single frame in
            // which nothing qualified wiped out the whole countdown, so it
            // could never accumulate on a jittering board.
            gameOverTimer = max(0, gameOverTimer - dt * Balance.overflowRecoveryRate)
        }

        // Danger reported to the UI blends "stack is getting high" with "the
        // countdown is running", so the vignette rises smoothly and then
        // spikes rather than appearing out of nowhere.
        let proximityWindow = Balance.dangerProximityWindow
        let proximity = max(0, min(1, (highestTop - (topY - proximityWindow)) / proximityWindow))
        let countdown = min(1, gameOverTimer / Balance.overflowGrace)
        let danger = max(Double(proximity), countdown)

        if abs(danger - reportedDanger) > 0.04 || (danger == 0 && reportedDanger != 0) {
            reportedDanger = danger
            onDangerChanged?(danger)
        }

        let lineAlpha = 0.30 + danger * 0.6
        dangerLine.strokeColor = UIColor(red: 1.0,
                                         green: CGFloat(1.0 - danger * 0.85),
                                         blue: CGFloat(1.0 - danger * 0.85),
                                         alpha: CGFloat(lineAlpha))
        dangerLine.glowWidth = CGFloat(danger * 8)
    }

    // MARK: - Run lifecycle

    private func triggerGameOver() {
        guard !isGameOver else { return }
        isGameOver = true

        activeBody?.removeAllActions()
        activeBody?.removeFromParent()
        activeBody = nil
        activeTouch = nil
        removeAction(forKey: "respawn")
        physicsWorld.speed = 1.0

        dropGuide.alpha = 0
        landingMarker.alpha = 0

        AudioManager.shared.play(.gameOver, volume: 0.9)
        HapticManager.shared.impact(intensity: 0.9, sharpness: 0.3)

        runStats.finalScore = score
        runStats.wasAssisted = wasAssisted
        runStats.isDaily = mode.isDaily

        onDangerChanged?(0)
        reportedDanger = 0

        onGameOver?(runStats)
    }

    /// Whether a Second Chance may be offered.
    ///
    /// Never in a Daily Challenge — that board runs on a fixed seed and has to
    /// mean the same thing for everyone — and never twice in one run.
    var canOfferSecondChance: Bool {
        isGameOver && !mode.isDaily && !secondChanceUsed
    }

    /// Clears the highest bodies and resumes the run. Flags the run as
    /// assisted, which routes its score to the Marathon board.
    func grantSecondChance() {
        guard canOfferSecondChance else { return }

        secondChanceUsed = true
        spawnBlockedRetries = 0
        wasAssisted = true
        runStats.wasAssisted = true
        isGameOver = false
        gameOverTimer = 0
        lastUpdateTime = 0
        comboCount = 0
        lastMergeTime = 0

        let purgePoint = CGPoint(x: size.width / 2, y: topY)
        let candidates = playLayer.children
            .compactMap { $0 as? SKShapeNode }
            .filter { $0 !== activeBody
                && ($0.userData?["isBounce"] as? Bool != true)
                && ($0.userData?["dying"] as? Bool != true)
                && $0.physicsBody != nil }
            .sorted { $0.position.y > $1.position.y }

        for node in candidates.prefix(Balance.secondChancePurgeCount) {
            implode(node, toward: purgePoint)
        }

        spawnShockwave(in: self, at: purgePoint, color: .cyan, radius: 200)
        spawnFlash(in: self, color: UIColor(red: 0.4, green: 0.9, blue: 1.0, alpha: 1), intensity: 0.3)
        AudioManager.shared.play(.reward, volume: 0.9)
        HapticManager.shared.impact(intensity: 0.7, sharpness: 0.5)

        onDangerChanged?(0)
        reportedDanger = 0

        dropGuide.alpha = 1
        landingMarker.alpha = 1
        spawnActiveBody()
    }

    func resetGame() {
        // Before the scene has been presented there is no world to reset;
        // `didMove(to:)` performs the initial setup with whatever mode has
        // already been configured.
        guard hasAppeared else { return }

        isGameOver = false
        wasAssisted = false
        secondChanceUsed = false
        runStats = RunStats()
        score = 0
        gameOverTimer = 0
        spawnBlockedRetries = 0
        lastUpdateTime = 0
        lastWarningBeep = 0
        comboCount = 0
        lastMergeTime = 0
        mergingIds.removeAll()
        activeBody = nil
        activeTouch = nil
        hasTiltBaseline = false
        reportedDanger = -1

        removeAllActions()
        physicsWorld.speed = 1.0
        physicsWorld.gravity = CGVector(dx: 0, dy: modifier.gravityY)
        playLayer.removeAllChildren()

        // `removeAllActions` on the scene also cancels effects and labels that
        // were parented to the scene; clear their leftovers explicitly.
        for child in children where child is SKLabelNode || child is SKEmitterNode {
            child.removeFromParent()
        }

        // The shooting-star loop lives on the background layer and survives,
        // but re-arm it defensively in case the layer was reset.
        if bgLayer.action(forKey: "shootingStars") == nil {
            scheduleShootingStars(in: bgLayer, size: size)
        }

        dangerLine.strokeColor = UIColor(white: 1.0, alpha: 0.30)
        dangerLine.glowWidth = 0
        dropGuide.removeAllActions()
        landingMarker.removeAllActions()
        dropGuide.alpha = 1
        landingMarker.alpha = 1
        dropGuide.position.x = size.width / 2
        landingMarker.position.x = size.width / 2

        onDangerChanged?(0)
        reportedDanger = 0
        onComboChanged?(0)

        primeQueue()
        spawnActiveBody()
    }

    deinit {
        motionManager.stopAccelerometerUpdates()
    }
}
