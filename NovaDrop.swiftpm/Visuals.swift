import SpriteKit
import UIKit

/// Cached, programmatically generated textures so particles actually render
/// (an SKEmitterNode with no texture draws nothing) and so glows look soft.
enum FX {
    /// Small soft dot used for sparks, stars and trails.
    static let spark: SKTexture = makeRadialTexture(diameter: 32)
    /// Large soft blob used for drifting nebula clouds.
    static let blob: SKTexture = makeRadialTexture(diameter: 256)

    static func makeRadialTexture(diameter: CGFloat) -> SKTexture {
        let size = CGSize(width: diameter, height: diameter)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [UIColor.white.withAlphaComponent(1).cgColor,
                          UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors,
                                        locations: [0, 1]) else { return }
            let c = CGPoint(x: diameter / 2, y: diameter / 2)
            cg.drawRadialGradient(grad, startCenter: c, startRadius: 0,
                                  endCenter: c, endRadius: diameter / 2, options: [])
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    // MARK: - Orb shading

    /// Rim light + specular highlight, baked into one cached texture per radius.
    ///
    /// These used to be two extra `SKShapeNode`s on every single body. Shape
    /// nodes are the most expensive thing SpriteKit draws (no batching, and a
    /// glow forces an offscreen pass), and a full board carried five of them
    /// per orb. Collapsing the two decorative layers into one cached sprite
    /// roughly halves the draw calls on a busy board without changing how a
    /// single orb looks.
    private static var shadingCache: [Int: SKTexture] = [:]

    static func orbShading(radius: CGFloat) -> SKTexture? {
        let key = Int(radius.rounded())
        if let cached = shadingCache[key] { return cached }

        let scale = UIScreen.main.scale
        let diameter = max(2.0, radius * 2)
        let size = CGSize(width: diameter, height: diameter)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false

        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            let centre = CGPoint(x: radius, y: radius)

            // Rim: a soft ring of light just inside the edge.
            cg.saveGState()
            let rimColors = [UIColor.white.withAlphaComponent(0.0).cgColor,
                             UIColor.white.withAlphaComponent(0.32).cgColor,
                             UIColor.white.withAlphaComponent(0.0).cgColor] as CFArray
            if let rimGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: rimColors,
                                        locations: [0.55, 0.88, 1.0]) {
                cg.addEllipse(in: CGRect(x: 0, y: 0, width: diameter, height: diameter))
                cg.clip()
                cg.drawRadialGradient(rimGrad, startCenter: centre, startRadius: 0,
                                      endCenter: centre, endRadius: radius, options: [])
            }
            cg.restoreGState()

            // Specular: a bright spot up and to the left, at roughly 10 o'clock.
            cg.saveGState()
            let specCentre = CGPoint(x: radius * 0.72, y: radius * 0.70)
            let specRadius = radius * 0.55
            let specColors = [UIColor.white.withAlphaComponent(0.52).cgColor,
                              UIColor.white.withAlphaComponent(0.0).cgColor] as CFArray
            if let specGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: specColors,
                                         locations: [0, 1]) {
                cg.addEllipse(in: CGRect(x: 0, y: 0, width: diameter, height: diameter))
                cg.clip()
                cg.drawRadialGradient(specGrad, startCenter: specCentre, startRadius: 0,
                                      endCenter: specCentre, endRadius: specRadius, options: [])
            }
            cg.restoreGState()
        }

        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        shadingCache[key] = texture
        return texture
    }
}

/// An expanding, fading ring — the satisfying impact pulse of a merge.
func spawnShockwave(in scene: SKScene, at point: CGPoint, color: UIColor, radius: CGFloat) {
    // The ring is drawn at `radius` and scales to 1.0 from a small start, so
    // its final size matches the radius the caller asked for. It previously
    // over-scaled to 1.7x, which made an antimatter blast *look* like it had a
    // 200pt reach when it actually cleared 120pt — a misleading tell.
    let ring = SKShapeNode(circleOfRadius: max(radius, 12))
    ring.position = point
    ring.strokeColor = color
    ring.fillColor = .clear
    ring.lineWidth = 4
    ring.glowWidth = 6
    ring.alpha = 0.9
    ring.zPosition = 50
    ring.blendMode = .add
    ring.setScale(0.15)
    scene.addChild(ring)
    ring.run(.sequence([
        .group([.scale(to: 1.0, duration: 0.38),
                .fadeOut(withDuration: 0.38)]),
        .removeFromParent()
    ]))
}

/// A brief full-screen flash. Used sparingly, and suppressed entirely when the
/// player has asked for reduced flashing.
func spawnFlash(in scene: SKScene, color: UIColor, intensity: CGFloat = 0.35) {
    guard !GameSettings.shared.reducedFlash else { return }
    let flash = SKSpriteNode(color: color, size: CGSize(width: scene.size.width * 1.2,
                                                        height: scene.size.height * 1.2))
    flash.position = CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)
    flash.blendMode = .add
    flash.alpha = 0
    flash.zPosition = 90
    scene.addChild(flash)
    flash.run(.sequence([
        .fadeAlpha(to: intensity, duration: 0.05),
        .fadeOut(withDuration: 0.35),
        .removeFromParent()
    ]))
}

/// Slowly drifting, additive nebula clouds behind everything.
func buildCosmicBackground(in parent: SKNode, size: CGSize) {
    let nebulaColors: [UIColor] = [.systemPurple, .systemBlue, .systemIndigo, .systemTeal]
    for i in 0..<4 {
        let blob = SKSpriteNode(texture: FX.blob)
        blob.color = nebulaColors[i % nebulaColors.count]
        blob.colorBlendFactor = 1.0
        blob.blendMode = .add
        blob.alpha = 0.10
        blob.zPosition = -20
        let dim = size.width * CGFloat.random(in: 0.9...1.3)
        blob.size = CGSize(width: dim, height: dim)
        blob.position = CGPoint(x: .random(in: 0...size.width),
                                y: .random(in: size.height * 0.15...size.height))
        parent.addChild(blob)

        let dx = CGFloat.random(in: -50...50)
        let dy = CGFloat.random(in: -50...50)
        let dur = Double.random(in: 14...22)
        blob.run(.repeatForever(.sequence([
            .move(by: CGVector(dx: dx, dy: dy), duration: dur),
            .move(by: CGVector(dx: -dx, dy: -dy), duration: dur)
        ])))
    }
}

/// Soft, twinkling parallax stars.
func buildTwinklingStars(in parent: SKNode, size: CGSize, count: Int = 70) {
    for _ in 0..<count {
        let r = CGFloat.random(in: 0.8...2.6)
        let star = SKSpriteNode(texture: FX.spark)
        star.size = CGSize(width: r * 4, height: r * 4)
        star.blendMode = .add
        star.alpha = CGFloat.random(in: 0.2...0.8)
        star.position = CGPoint(x: .random(in: 0...size.width),
                                y: .random(in: 0...size.height))
        star.zPosition = -10
        parent.addChild(star)

        let dur = Double.random(in: 1.5...3.5)
        star.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.15, duration: dur),
            .fadeAlpha(to: 0.85, duration: dur)
        ])))
    }
}

/// Occasional shooting stars streaking across the sky.
func scheduleShootingStars(in parent: SKNode, size: CGSize) {
    let spawn = SKAction.run { [weak parent] in
        guard let parent = parent else { return }
        spawnShootingStar(in: parent, size: size)
    }
    let wait = SKAction.wait(forDuration: 5.0, withRange: 6.0)
    parent.run(.repeatForever(.sequence([wait, spawn])), withKey: "shootingStars")
}

private func spawnShootingStar(in parent: SKNode, size: CGSize) {
    let head = SKSpriteNode(texture: FX.spark)
    head.size = CGSize(width: 8, height: 8)
    head.blendMode = .add
    head.zPosition = -8
    head.position = CGPoint(x: .random(in: size.width * 0.3...size.width),
                            y: size.height + 20)
    parent.addChild(head)

    let trail = SKEmitterNode()
    trail.particleTexture = FX.spark
    trail.particleBirthRate = 140
    trail.particleLifetime = 0.5
    trail.particleColor = .white
    trail.particleColorBlendFactor = 1
    trail.particleAlpha = 0.7
    trail.particleAlphaSpeed = -1.6
    trail.particleScale = 0.18
    trail.particleScaleSpeed = -0.25
    trail.particleSpeed = 0
    trail.particleBlendMode = .add
    head.addChild(trail)

    let dx = CGFloat.random(in: -size.width * 0.35 ... -size.width * 0.12)
    let move = SKAction.moveBy(x: dx, y: -size.height - 60,
                               duration: Double.random(in: 0.9...1.5))
    move.timingMode = .easeIn
    head.run(.sequence([move, .removeFromParent()]))
}

/// A short positional jolt. Applied to the decorative background layer only —
/// never to nodes that own physics bodies, because moving a physics body's
/// parent teleports the body and makes the solver explode.
func shake(_ node: SKNode, amplitude: CGFloat = 9, duration: TimeInterval = 0.28) {
    guard !GameSettings.shared.reducedFlash else { return }
    node.removeAction(forKey: "shake")
    let home = node.position
    var steps: [SKAction] = []
    let stepCount = 8
    for i in 0..<stepCount {
        let decay = 1.0 - CGFloat(i) / CGFloat(stepCount)
        let dx = CGFloat.random(in: -amplitude...amplitude) * decay
        let dy = CGFloat.random(in: -amplitude...amplitude) * decay
        steps.append(.move(to: CGPoint(x: home.x + dx, y: home.y + dy),
                           duration: duration / Double(stepCount)))
    }
    steps.append(.move(to: home, duration: duration / Double(stepCount)))
    node.run(.sequence(steps), withKey: "shake")
}
