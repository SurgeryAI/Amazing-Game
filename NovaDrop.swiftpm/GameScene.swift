import SpriteKit
import CoreHaptics
import CoreMotion

class GameScene: SKScene, SKPhysicsContactDelegate {
    
    enum PhysicsCategory {
        static let none: UInt32 = 0
        static let body: UInt32 = 0b1
        static let wall: UInt32 = 0b10
    }
    
    var hapticEngine: CHHapticEngine?
    var motionManager = CMMotionManager()
    
    var onScoreChanged: ((Int) -> Void)?
    var onGameOver: (() -> Void)?
    var onNextTierChanged: ((CelestialTier) -> Void)?
    
    private var score = 0 {
        didSet { onScoreChanged?(score) }
    }
    
    private var isGameOver = false
    private var activeBody: SKShapeNode?
    var currentNextTier: CelestialTier = .dust
    private var mergingIds = Set<String>()
    private let playLayer = SKNode()

    // Combo chain multiplier state
    private var comboCount: Int = 0
    private var lastMergeTime: TimeInterval = 0
    private let comboWindow: TimeInterval = 1.5

    private var gameOverTimer: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0
    
    private let dropLineYOffset: CGFloat = 160
    private var topY: CGFloat = 0

    override func didMove(to view: SKView) {
        backgroundColor = .black
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
        physicsWorld.contactDelegate = self
        setupHaptics()
        
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 0.1
            motionManager.startAccelerometerUpdates()
        }
        
        buildEnvironment()
        spawnActiveBody()
    }
    
    func buildEnvironment() {
        let boundary = SKNode()
        let bannerHeight: CGFloat = 60
        let rect = CGRect(x: 0, y: bannerHeight, width: size.width, height: size.height - bannerHeight)
        boundary.physicsBody = SKPhysicsBody(edgeLoopFrom: rect)
        boundary.physicsBody?.categoryBitMask = PhysicsCategory.wall
        boundary.physicsBody?.contactTestBitMask = PhysicsCategory.none
        boundary.physicsBody?.collisionBitMask = PhysicsCategory.body
        boundary.physicsBody?.restitution = 0.2
        addChild(boundary)
        addChild(playLayer)
        
        topY = size.height - dropLineYOffset
        
        let dashedLine = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: topY))
        path.addLine(to: CGPoint(x: size.width, y: topY))
        dashedLine.path = path
        dashedLine.strokeColor = .init(white: 1.0, alpha: 0.3)
        let dashed = dashedLine.path?.copy(dashingWithPhase: 0, lengths: [10, 10])
        dashedLine.path = dashed
        addChild(dashedLine)
        
        for _ in 0..<50 {
            let star = SKShapeNode(circleOfRadius: CGFloat.random(in: 1...3))
            star.fillColor = .white
            star.alpha = CGFloat.random(in: 0.2...0.8)
            star.position = CGPoint(x: CGFloat.random(in: 0...size.width), y: CGFloat.random(in: 0...size.height))
            star.zPosition = -10
            addChild(star)
        }
    }
    
    func randomStartTier() -> CelestialTier {
        if score > 100 && Int.random(in: 1...100) <= 8 {
            return .antimatter
        }
        var maxRaw = 2  // up to Moon by default
        if score >= 500 { maxRaw = 4 }   // Gas Giant unlocked
        else if score >= 200 { maxRaw = 3 } // Planet unlocked
        let maxTier = min(maxRaw, 5) // Exclude black hole and antimatter from normal random
        return CelestialTier(rawValue: Int.random(in: 0...maxTier)) ?? .dust
    }
    
    func spawnActiveBody() {
        guard !isGameOver else { return }
        
        let tier = currentNextTier
        currentNextTier = randomStartTier()
        onNextTierChanged?(currentNextTier)
        
        let node = createBodyNode(tier: tier)
        node.position = CGPoint(x: size.width / 2, y: topY)
        
        node.physicsBody = nil
        node.alpha = 0.5
        playLayer.addChild(node)
        activeBody = node
    }
    
    func createBodyNode(tier: CelestialTier) -> SKShapeNode {
        let node = SKShapeNode(circleOfRadius: tier.radius)
        node.fillColor = UIColor(tier.color)
        node.strokeColor = tier.glowColor
        node.lineWidth = 2

        let glowWidths: [CelestialTier: CGFloat] = [
            .dust: 5, .meteor: 6, .moon: 8, .planet: 10,
            .gasGiant: 12, .star: 14, .blackHole: 22, .antimatter: 10
        ]
        node.glowWidth = glowWidths[tier] ?? 8

        if tier == .blackHole {
            node.fillColor = .black
        }
        
        if tier == .antimatter {
            node.fillColor = UIColor(white: 0.1, alpha: 1.0)
            let pulseIn = SKAction.scale(to: 0.8, duration: 0.5)
            let pulseOut = SKAction.scale(to: 1.2, duration: 0.5)
            node.run(SKAction.repeatForever(SKAction.sequence([pulseIn, pulseOut])))
        }

        // Inner rim lighting — a slightly smaller ring painted with the glow
        // colour to simulate light wrapping around the edge of the sphere.
        let rimRadiusScale: CGFloat = 0.88      // ring sits just inside the orb edge
        let rimAlpha: CGFloat = 0.45
        let rimLineWidthScale: CGFloat = 0.18   // thick enough to fill toward the edge
        let rimNode = SKShapeNode(circleOfRadius: tier.radius * rimRadiusScale)
        rimNode.fillColor = .clear
        rimNode.strokeColor = tier.glowColor.withAlphaComponent(rimAlpha)
        rimNode.lineWidth = tier.radius * rimLineWidthScale
        rimNode.zPosition = 1
        node.addChild(rimNode)

        // Specular highlight — a bright spot offset to the top-left, simulating
        // a light source at roughly 10 o'clock, giving each orb a 3D sphere look.
        let highlightRadiusScale: CGFloat = 0.30
        let highlightAlpha: CGFloat = 0.45
        let highlightOffsetX: CGFloat = -0.26   // fraction of radius, left of centre
        let highlightOffsetY: CGFloat = 0.27    // fraction of radius, above centre
        if tier != .blackHole && tier != .antimatter {
            let highlight = SKShapeNode(circleOfRadius: tier.radius * highlightRadiusScale)
            highlight.fillColor = UIColor(white: 1.0, alpha: highlightAlpha)
            highlight.strokeColor = .clear
            highlight.position = CGPoint(x: tier.radius * highlightOffsetX,
                                         y: tier.radius * highlightOffsetY)
            highlight.zPosition = 2
            node.addChild(highlight)
        }

        // Gas Giant — decorative planetary ring in the orbital plane
        if tier == .gasGiant {
            let ring = SKShapeNode(ellipseOf: CGSize(
                width: tier.radius * 2.6, height: tier.radius * 0.52))
            ring.fillColor = .clear
            ring.strokeColor = UIColor.purple.withAlphaComponent(0.60)
            ring.lineWidth = 4
            ring.glowWidth = 4
            ring.zPosition = -1
            node.addChild(ring)
        }

        // Star — glow pulses to simulate radiant energy
        if tier == .star {
            let minStarGlow: CGFloat = 14
            let maxStarGlow: CGFloat = 32
            let pulseDuration: Double = 0.8
            let glowRange = maxStarGlow - minStarGlow
            let glowUp = SKAction.customAction(withDuration: pulseDuration) { n, elapsed in
                (n as? SKShapeNode)?.glowWidth = minStarGlow + (elapsed / pulseDuration) * glowRange
            }
            let glowDown = SKAction.customAction(withDuration: pulseDuration) { n, elapsed in
                (n as? SKShapeNode)?.glowWidth = maxStarGlow - (elapsed / pulseDuration) * glowRange
            }
            node.run(SKAction.repeatForever(SKAction.sequence([glowUp, glowDown])))
        }

        // Black Hole — rotating accretion disk ellipse
        if tier == .blackHole {
            let disk = SKShapeNode(ellipseOf: CGSize(
                width: tier.radius * 2.8, height: tier.radius * 0.55))
            disk.fillColor = .clear
            disk.strokeColor = UIColor.purple.withAlphaComponent(0.90)
            disk.lineWidth = 6
            disk.glowWidth = 10
            disk.zPosition = -1
            disk.run(SKAction.repeatForever(
                SKAction.rotate(byAngle: .pi * 2, duration: 5.0)))
            node.addChild(disk)
        }

        node.name = "tier_\(tier.rawValue)"
        let userData = NSMutableDictionary()
        userData["tier"] = tier.rawValue
        userData["mergeId"] = UUID().uuidString
        node.userData = userData
        
        return node
    }
    
    func setupBodyPhysics(node: SKShapeNode, tier: CelestialTier) {
        node.physicsBody = SKPhysicsBody(circleOfRadius: tier.radius)
        node.physicsBody?.mass = tier.mass
        node.physicsBody?.restitution = 0.1
        node.physicsBody?.friction = 0.2
        node.physicsBody?.angularDamping = 0.2
        node.physicsBody?.linearDamping = 0.0
        node.physicsBody?.categoryBitMask = PhysicsCategory.body
        node.physicsBody?.contactTestBitMask = PhysicsCategory.body
        node.physicsBody?.collisionBitMask = PhysicsCategory.body | PhysicsCategory.wall
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, !isGameOver else { return }
        let loc = touch.location(in: self)
        updateActiveBodyPosition(x: loc.x)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, !isGameOver else { return }
        let loc = touch.location(in: self)
        updateActiveBodyPosition(x: loc.x)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isGameOver else { return }
        dropActiveBody()
    }
    
    func updateActiveBodyPosition(x: CGFloat) {
        guard let active = activeBody else { return }
        let tier = CelestialTier(rawValue: active.userData?["tier"] as? Int ?? 0) ?? .dust
        let r = tier.radius
        let clampedX = max(r, min(size.width - r, x))
        active.position.x = clampedX
    }
    
    func dropActiveBody() {
        guard let active = activeBody else { return }
        active.alpha = 1.0
        let tier = CelestialTier(rawValue: active.userData?["tier"] as? Int ?? 0) ?? .dust
        setupBodyPhysics(node: active, tier: tier)
        
        activeBody = nil
        
        run(SKAction.sequence([
            SKAction.wait(forDuration: 1.0),
            SKAction.run { [weak self] in self?.spawnActiveBody() }
        ]))
    }
    
    func didBegin(_ contact: SKPhysicsContact) {
        let nodeA = contact.bodyA.node as? SKShapeNode
        let nodeB = contact.bodyB.node as? SKShapeNode
        

        
        guard let a = nodeA, let b = nodeB else { return }
        guard a.parent != nil && b.parent != nil else { return }
        
        let tierAValue = a.userData?["tier"] as? Int ?? -1
        let tierBValue = b.userData?["tier"] as? Int ?? -2
        
        let idA = a.userData?["mergeId"] as? String ?? ""
        let idB = b.userData?["mergeId"] as? String ?? ""
        
        guard !mergingIds.contains(idA), !mergingIds.contains(idB) else { return }
        
        if tierAValue == CelestialTier.antimatter.rawValue || tierBValue == CelestialTier.antimatter.rawValue {
            mergingIds.insert(idA)
            mergingIds.insert(idB)
            handleAntiMatterDestruction(nodeA: a, nodeB: b, contactPoint: contact.contactPoint)
            return
        }
        
        if tierAValue == tierBValue, let tier = CelestialTier(rawValue: tierAValue) {
            mergingIds.insert(idA)
            mergingIds.insert(idB)
            handleMerge(nodeA: a, nodeB: b, tier: tier, contactPoint: contact.contactPoint)
        }
    }
    
    func handleAntiMatterDestruction(nodeA: SKShapeNode, nodeB: SKShapeNode, contactPoint: CGPoint) {
        nodeA.removeFromParent()
        nodeB.removeFromParent()
        createExplosion(at: contactPoint, color: .red)

        if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
            ], relativeTime: 0)
            do {
                let pattern = try CHHapticPattern(events: [event], parameters: [])
                let player = try hapticEngine?.makePlayer(with: pattern)
                try player?.start(atTime: 0)
            } catch { }
        }
    }
    
    func handleMerge(nodeA: SKShapeNode, nodeB: SKShapeNode, tier: CelestialTier, contactPoint: CGPoint) {
        let idA = nodeA.userData?["mergeId"] as? String ?? ""
        let idB = nodeB.userData?["mergeId"] as? String ?? ""

        nodeA.removeFromParent()
        nodeB.removeFromParent()

        // Combo chain multiplier
        let now = CACurrentMediaTime()
        if now - lastMergeTime <= comboWindow {
            comboCount += 1
        } else {
            comboCount = 1
        }
        lastMergeTime = now

        let multiplier = comboCount
        let scoreGain = tier.scoreValue * multiplier
        score += scoreGain

        if multiplier > 1 {
            showComboLabel(multiplier: multiplier, at: contactPoint)
        }

        createExplosion(at: contactPoint, color: tier.glowColor)
        playHaptic(for: tier)

        guard let nextTier = tier.nextTier else {
            return
        }

        let newNode = createBodyNode(tier: nextTier)
        newNode.position = contactPoint
        playLayer.addChild(newNode)

        setupBodyPhysics(node: newNode, tier: nextTier)
    }

    func showComboLabel(multiplier: Int, at position: CGPoint) {
        let label = SKLabelNode(text: "\(multiplier)x COMBO!")
        label.fontName = "AvenirNext-Heavy"
        label.fontSize = 22 + CGFloat(min(multiplier, 8)) * 3
        label.fontColor = .systemYellow
        label.position = position
        label.zPosition = 100
        label.alpha = 0
        addChild(label)

        let appear = SKAction.fadeIn(withDuration: 0.1)
        let scale = SKAction.sequence([
            SKAction.scale(to: 1.3, duration: 0.15),
            SKAction.scale(to: 1.0, duration: 0.1)
        ])
        let rise = SKAction.moveBy(x: 0, y: 50, duration: 0.8)
        let fadeOut = SKAction.fadeOut(withDuration: 0.4)
        let wait = SKAction.wait(forDuration: 0.5)
        let remove = SKAction.removeFromParent()

        label.run(SKAction.group([scale, SKAction.sequence([appear, wait, fadeOut, remove])]))
        label.run(rise)
    }
    
    func createExplosion(at position: CGPoint, color: UIColor) {
        let emitter = SKEmitterNode()
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1.0
        emitter.particleBirthRate = 500
        emitter.numParticlesToEmit = 50
        emitter.particleLifetime = 0.5
        emitter.particlePositionRange = CGVector(dx: 15, dy: 15)
        emitter.particleSpeed = 200
        emitter.particleSpeedRange = 100
        emitter.particleAlpha = 1.0
        emitter.particleAlphaSpeed = -2.0
        emitter.particleScale = 0.5
        emitter.particleScaleSpeed = -1.0
        emitter.emissionAngleRange = .pi * 2
        emitter.position = position
        
        addChild(emitter)
        
        let wait = SKAction.wait(forDuration: 1.0)
        let remove = SKAction.removeFromParent()
        emitter.run(SKAction.sequence([wait, remove]))
    }
    
    func setupHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
        } catch {
            print("Haptics Error: \(error.localizedDescription)")
        }
    }
    
    func playHaptic(for tier: CelestialTier) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        var intensity: Float = 0.3
        var sharpness: Float = 0.3
        
        switch tier {
        case .dust, .meteor:
            intensity = 0.4; sharpness = 0.4
        case .moon, .planet:
            intensity = 0.6; sharpness = 0.5
        case .gasGiant, .star:
            intensity = 0.8; sharpness = 0.6
        case .blackHole:
            intensity = 1.0; sharpness = 1.0
        }
        
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0
        )
        
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try hapticEngine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch {
            print("Failed to play haptic: \(error.localizedDescription)")
        }
    }
    
    func triggerGameOver() {
        guard !isGameOver else { return }
        isGameOver = true
        onGameOver?()
        activeBody?.removeFromParent()
        activeBody = nil
    }
    
    func resetGame() {
        isGameOver = false
        score = 0
        gameOverTimer = 0.0
        lastUpdateTime = 0.0
        comboCount = 0
        lastMergeTime = 0
        currentNextTier = randomStartTier()
        mergingIds.removeAll()
        playLayer.removeAllChildren()
        spawnActiveBody()
    }

    override func update(_ currentTime: TimeInterval) {
        guard !isGameOver else { return }
        
        if lastUpdateTime == 0 { lastUpdateTime = currentTime }
        let dt = currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        
        if let data = motionManager.accelerometerData {
            let tiltThreshold: Double = 0.05
            var dx = data.acceleration.x * 20.0
            if abs(data.acceleration.x) < tiltThreshold { dx = 0 }
            physicsWorld.gravity = CGVector(dx: CGFloat(dx), dy: -9.8)
        }

        // Black Hole Gravity Well: attract nearby bodies toward each black hole
        let allNodes = playLayer.children.compactMap { $0 as? SKShapeNode }
            .filter { $0 != activeBody }
        let blackHoles = allNodes.filter {
            ($0.userData?["tier"] as? Int) == CelestialTier.blackHole.rawValue
        }
        if !blackHoles.isEmpty {
            let pullRadiusSq: CGFloat = 220 * 220
            let pullStrength: CGFloat = 180
            for bh in blackHoles {
                for body in allNodes where body !== bh {
                    guard let pb = body.physicsBody else { continue }
                    let diff = CGVector(dx: bh.position.x - body.position.x,
                                       dy: bh.position.y - body.position.y)
                    let distSq = diff.dx * diff.dx + diff.dy * diff.dy
                    guard distSq > 1 && distSq < pullRadiusSq else { continue }
                    let dist = sqrt(distSq)
                    let scale = pullStrength * (1 - dist / 220)
                    let force = CGVector(dx: diff.dx / dist * scale,
                                        dy: diff.dy / dist * scale)
                    pb.applyForce(force)
                }
            }
        }

        var isOverflowing = false
        
        for child in playLayer.children {
            if child == activeBody { continue }
            
            let tier = CelestialTier(rawValue: child.userData?["tier"] as? Int ?? 0) ?? .dust
            let topEdge = child.position.y + tier.radius
            
            if topEdge > topY + 10 {
                isOverflowing = true
                break
            }
        }
        
        if isOverflowing {
            gameOverTimer += dt
            if gameOverTimer > 2.0 {
                triggerGameOver()
            }
        } else {
            gameOverTimer = 0.0
        }
    }
    
    deinit {
        motionManager.stopAccelerometerUpdates()
    }
}
