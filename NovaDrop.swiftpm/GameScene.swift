import SpriteKit
import CoreHaptics

class GameScene: SKScene, SKPhysicsContactDelegate {
    
    enum PhysicsCategory {
        static let none: UInt32 = 0
        static let body: UInt32 = 0b1
        static let wall: UInt32 = 0b10
    }
    
    var hapticEngine: CHHapticEngine?
    
    var onScoreChanged: ((Int) -> Void)?
    var onGameOver: (() -> Void)?
    var onNextTierChanged: ((CelestialTier) -> Void)?
    
    private var score = 0 {
        didSet { onScoreChanged?(score) }
    }
    
    private var isGameOver = false
    private var activeBody: SKShapeNode?
    var currentNextTier: CelestialTier = .dust
    
    private var gameOverTimer: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0
    
    private let dropLineYOffset: CGFloat = 100
    private var topY: CGFloat = 0

    override func didMove(to view: SKView) {
        backgroundColor = .black
        physicsWorld.gravity = CGVector(dx: 0, dy: -6.0)
        physicsWorld.contactDelegate = self
        setupHaptics()
        buildEnvironment()
        spawnActiveBody()
    }
    
    func buildEnvironment() {
        let boundary = SKNode()
        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        boundary.physicsBody = SKPhysicsBody(edgeLoopFrom: rect)
        boundary.physicsBody?.categoryBitMask = PhysicsCategory.wall
        boundary.physicsBody?.contactTestBitMask = PhysicsCategory.none
        boundary.physicsBody?.collisionBitMask = PhysicsCategory.body
        boundary.physicsBody?.restitution = 0.2
        addChild(boundary)
        
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
        let maxTier = min(2, CelestialTier.allCases.count - 1)
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
        addChild(node)
        activeBody = node
    }
    
    func createBodyNode(tier: CelestialTier) -> SKShapeNode {
        let node = SKShapeNode(circleOfRadius: tier.radius)
        node.fillColor = UIColor(tier.color)
        node.strokeColor = tier.glowColor
        node.lineWidth = 3
        node.glowWidth = 4
        
        if tier == .blackHole {
            node.fillColor = .black
            node.glowWidth = 15
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
        node.physicsBody?.restitution = 0.05
        node.physicsBody?.friction = 0.8
        node.physicsBody?.angularDamping = 0.8
        node.physicsBody?.linearDamping = 0.6
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
        
        if tierAValue == tierBValue, let tier = CelestialTier(rawValue: tierAValue) {
            handleMerge(nodeA: a, nodeB: b, tier: tier, contactPoint: contact.contactPoint)
        }
    }
    
    func handleMerge(nodeA: SKShapeNode, nodeB: SKShapeNode, tier: CelestialTier, contactPoint: CGPoint) {
        nodeA.removeFromParent()
        nodeB.removeFromParent()
        
        let scoreGain = tier.scoreValue
        score += scoreGain
        
        createExplosion(at: contactPoint, color: tier.glowColor)
        playHaptic(for: tier)
        
        guard let nextTier = tier.nextTier else {
            playHaptic(for: .blackHole)
            return
        }
        
        let newNode = createBodyNode(tier: nextTier)
        newNode.position = contactPoint
        newNode.setScale(0.1)
        addChild(newNode)
        
        setupBodyPhysics(node: newNode, tier: nextTier)
        
        let scaleAction = SKAction.scale(to: 1.0, duration: 0.2)
        scaleAction.timingMode = .easeOut
        newNode.run(scaleAction)
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
        children.forEach { node in
            if node.name?.starts(with: "tier_") == true {
                node.removeFromParent()
            }
        }
        spawnActiveBody()
    }

    override func update(_ currentTime: TimeInterval) {
        guard !isGameOver else { return }
        
        if lastUpdateTime == 0 { lastUpdateTime = currentTime }
        let dt = currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        
        var isOverflowing = false
        
        for child in children {
            if child.name?.starts(with: "tier_") == true {
                if child == activeBody { continue }
                
                let tier = CelestialTier(rawValue: child.userData?["tier"] as? Int ?? 0) ?? .dust
                let topEdge = child.position.y + tier.radius
                
                if topEdge > topY + 10 {
                    isOverflowing = true
                    break
                }
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
}
