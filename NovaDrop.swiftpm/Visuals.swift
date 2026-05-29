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
}

/// An expanding, fading ring — the satisfying impact pulse of a merge.
func spawnShockwave(in scene: SKScene, at point: CGPoint, color: UIColor, radius: CGFloat) {
    let ring = SKShapeNode(circleOfRadius: max(radius, 12))
    ring.position = point
    ring.strokeColor = color
    ring.fillColor = .clear
    ring.lineWidth = 4
    ring.glowWidth = 6
    ring.alpha = 0.9
    ring.zPosition = 50
    ring.blendMode = .add
    ring.setScale(0.2)
    scene.addChild(ring)
    ring.run(.sequence([
        .group([.scale(to: 1.7, duration: 0.4),
                .fadeOut(withDuration: 0.4)]),
        .removeFromParent()
    ]))
}

/// Slowly drifting, additive nebula clouds behind everything.
func buildCosmicBackground(in scene: SKScene) {
    let size = scene.size
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
        scene.addChild(blob)

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
func buildTwinklingStars(in scene: SKScene, count: Int = 70) {
    let size = scene.size
    for _ in 0..<count {
        let r = CGFloat.random(in: 0.8...2.6)
        let star = SKSpriteNode(texture: FX.spark)
        star.size = CGSize(width: r * 4, height: r * 4)
        star.blendMode = .add
        star.alpha = CGFloat.random(in: 0.2...0.8)
        star.position = CGPoint(x: .random(in: 0...size.width),
                                y: .random(in: 0...size.height))
        star.zPosition = -10
        scene.addChild(star)

        let dur = Double.random(in: 1.5...3.5)
        star.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.15, duration: dur),
            .fadeAlpha(to: 0.85, duration: dur)
        ])))
    }
}

/// Occasional shooting stars streaking across the sky.
func scheduleShootingStars(in scene: SKScene) {
    let spawn = SKAction.run { [weak scene] in
        guard let scene = scene else { return }
        spawnShootingStar(in: scene)
    }
    let wait = SKAction.wait(forDuration: 5.0, withRange: 6.0)
    scene.run(.repeatForever(.sequence([wait, spawn])), withKey: "shootingStars")
}

private func spawnShootingStar(in scene: SKScene) {
    let head = SKSpriteNode(texture: FX.spark)
    head.size = CGSize(width: 8, height: 8)
    head.blendMode = .add
    head.zPosition = -8
    head.position = CGPoint(x: .random(in: scene.size.width * 0.3...scene.size.width),
                            y: scene.size.height + 20)
    scene.addChild(head)

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

    let dx = CGFloat.random(in: -scene.size.width * 0.35 ... -scene.size.width * 0.12)
    let move = SKAction.moveBy(x: dx, y: -scene.size.height - 60,
                               duration: Double.random(in: 0.9...1.5))
    move.timingMode = .easeIn
    head.run(.sequence([move, .removeFromParent()]))
}
