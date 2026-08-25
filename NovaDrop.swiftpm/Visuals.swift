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

    // MARK: - Celestial Sphere Shading & Textures

    private static var celestialTextureCache: [String: SKTexture] = [:]

    static func celestialTexture(tier: CelestialTier, radius: CGFloat, theme: OrbTheme) -> SKTexture? {
        let key = "\(tier.rawValue)_\(Int(radius.rounded()))_\(theme.rawValue)"
        if let cached = celestialTextureCache[key] { return cached }

        let scale = UIScreen.main.scale
        let diameter = max(4.0, radius * 2)
        let size = CGSize(width: diameter, height: diameter)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false

        let baseColor = theme.fillUIColor(for: tier)
        let glowColor = theme.glowUIColor(for: tier)

        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            let bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            let centre = CGPoint(x: radius, y: radius)

            cg.saveGState()
            cg.addEllipse(in: bounds)
            cg.clip()

            switch tier {
            case .dust, .meteor:
                drawAsteroid(cg: cg, radius: radius, centre: centre, baseColor: baseColor, glowColor: glowColor, isDust: tier == .dust)
            case .moon:
                drawMoon(cg: cg, radius: radius, centre: centre, baseColor: baseColor, glowColor: glowColor)
            case .planet:
                drawPlanet(cg: cg, radius: radius, centre: centre, baseColor: baseColor, glowColor: glowColor)
            case .gasGiant:
                drawGasGiant(cg: cg, radius: radius, centre: centre, baseColor: baseColor, glowColor: glowColor)
            case .star:
                drawStar(cg: cg, radius: radius, centre: centre, baseColor: baseColor, glowColor: glowColor)
            case .blackHole:
                drawBlackHole(cg: cg, radius: radius, centre: centre, baseColor: baseColor, glowColor: glowColor)
            case .antimatter:
                drawAntimatter(cg: cg, radius: radius, centre: centre, baseColor: baseColor, glowColor: glowColor)
            }

            // Draw 3D spherical lighting overlay (specular and limb shadow)
            draw3DShadingOverlay(cg: cg, radius: radius, centre: centre, tier: tier, glowColor: glowColor)

            cg.restoreGState()
        }

        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        celestialTextureCache[key] = texture
        return texture
    }

    // MARK: - Procedural Sphere Renderers

    private static func drawAsteroid(cg: CGContext, radius: CGFloat, centre: CGPoint, baseColor: UIColor, glowColor: UIColor, isDust: Bool) {
        let lightPos = CGPoint(x: radius * 0.65, y: radius * 0.60)
        let darkColor = baseColor.darkened(by: 0.55)
        let brightColor = baseColor.lightened(by: 0.35)

        let colors = [brightColor.cgColor, baseColor.cgColor, darkColor.cgColor] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.45, 1.0]) {
            cg.drawRadialGradient(grad, startCenter: lightPos, startRadius: 0, endCenter: centre, endRadius: radius, options: [])
        }

        // Craters
        let count = isDust ? 3 : 6
        let craterCoords: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
            (0.35, 0.40, 0.22), (0.70, 0.30, 0.16), (0.55, 0.70, 0.20),
            (0.25, 0.75, 0.14), (0.80, 0.65, 0.18), (0.45, 0.22, 0.12)
        ]

        for i in 0..<min(count, craterCoords.count) {
            let (rx, ry, rr) = craterCoords[i]
            let cPos = CGPoint(x: radius * 2 * rx, y: radius * 2 * ry)
            let cRad = radius * rr
            let cRect = CGRect(x: cPos.x - cRad, y: cPos.y - cRad, width: cRad * 2, height: cRad * 2)

            cg.setFillColor(darkColor.darkened(by: 0.4).cgColor)
            cg.fillEllipse(in: cRect)

            // Inner shadow
            cg.setStrokeColor(UIColor.black.withAlphaComponent(0.5).cgColor)
            cg.setLineWidth(max(1.0, cRad * 0.25))
            cg.strokeEllipse(in: cRect)

            // Crater rim highlight
            cg.setStrokeColor(brightColor.withAlphaComponent(0.6).cgColor)
            cg.setLineWidth(max(1.0, cRad * 0.18))
            cg.strokeEllipse(in: CGRect(x: cRect.minX + cRad * 0.2, y: cRect.minY + cRad * 0.2, width: cRect.width * 0.85, height: cRect.height * 0.85))
        }
    }

    private static func drawMoon(cg: CGContext, radius: CGFloat, centre: CGPoint, baseColor: UIColor, glowColor: UIColor) {
        let lightPos = CGPoint(x: radius * 0.65, y: radius * 0.55)
        let highlight = baseColor.lightened(by: 0.45)
        let shadow = baseColor.darkened(by: 0.65)

        let colors = [highlight.cgColor, baseColor.cgColor, shadow.cgColor] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.5, 1.0]) {
            cg.drawRadialGradient(grad, startCenter: lightPos, startRadius: 0, endCenter: centre, endRadius: radius, options: [])
        }

        // Lunar Maria (dark basalt plains)
        cg.setFillColor(shadow.withAlphaComponent(0.55).cgColor)
        cg.fillEllipse(in: CGRect(x: radius * 0.35, y: radius * 0.70, width: radius * 0.75, height: radius * 0.55))
        cg.fillEllipse(in: CGRect(x: radius * 0.95, y: radius * 0.40, width: radius * 0.65, height: radius * 0.70))

        // Lunar Craters with ray systems
        let craters: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
            (0.6, 0.45, 0.24), (1.3, 0.7, 0.18), (0.75, 1.25, 0.22),
            (1.2, 1.35, 0.16), (0.4, 1.1, 0.14)
        ]
        for c in craters {
            let rect = CGRect(x: c.x * radius - c.r * radius, y: c.y * radius - c.r * radius, width: c.r * radius * 2, height: c.r * radius * 2)
            cg.setFillColor(shadow.darkened(by: 0.5).cgColor)
            cg.fillEllipse(in: rect)
            cg.setStrokeColor(highlight.withAlphaComponent(0.7).cgColor)
            cg.setLineWidth(max(1.0, radius * 0.04))
            cg.strokeEllipse(in: rect)
        }
    }

    private static func drawPlanet(cg: CGContext, radius: CGFloat, centre: CGPoint, baseColor: UIColor, glowColor: UIColor) {
        // Deep vibrant ocean base
        let oceanDeep = UIColor(red: 0.05, green: 0.22, blue: 0.55, alpha: 1.0)
        let oceanBright = UIColor(red: 0.10, green: 0.58, blue: 0.82, alpha: 1.0)
        let oceanShadow = UIColor(red: 0.02, green: 0.08, blue: 0.25, alpha: 1.0)

        let lightPos = CGPoint(x: radius * 0.65, y: radius * 0.55)
        let oColors = [oceanBright.cgColor, oceanDeep.cgColor, oceanShadow.cgColor] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: oColors, locations: [0.0, 0.55, 1.0]) {
            cg.drawRadialGradient(grad, startCenter: lightPos, startRadius: 0, endCenter: centre, endRadius: radius, options: [])
        }

        // Continents / landmasses (Emerald green & turquoise)
        let landColor = UIColor(red: 0.15, green: 0.72, blue: 0.45, alpha: 0.92)
        let coastColor = UIColor(red: 0.28, green: 0.88, blue: 0.68, alpha: 0.65)

        cg.setFillColor(landColor.cgColor)
        let continents: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, rot: CGFloat)] = [
            (0.55, 0.65, 0.75, 0.55, 0.3),
            (1.15, 1.05, 0.85, 0.65, -0.4),
            (0.85, 1.35, 0.65, 0.45, 0.2),
            (1.35, 0.55, 0.55, 0.40, 0.5)
        ]

        for c in continents {
            cg.saveGState()
            cg.translateBy(x: c.x * radius, y: c.y * radius)
            cg.rotate(by: c.rot)
            let rect = CGRect(x: -c.w * radius / 2, y: -c.h * radius / 2, width: c.w * radius, height: c.h * radius)
            cg.fillEllipse(in: rect)
            cg.setStrokeColor(coastColor.cgColor)
            cg.setLineWidth(max(1.5, radius * 0.06))
            cg.strokeEllipse(in: rect)
            cg.restoreGState()
        }

        // Swirling atmospheric white clouds
        cg.setFillColor(UIColor.white.withAlphaComponent(0.38).cgColor)
        cg.fillEllipse(in: CGRect(x: radius * 0.3, y: radius * 0.35, width: radius * 1.3, height: radius * 0.28))
        cg.fillEllipse(in: CGRect(x: radius * 0.4, y: radius * 0.85, width: radius * 1.2, height: radius * 0.24))
        cg.fillEllipse(in: CGRect(x: radius * 0.2, y: radius * 1.35, width: radius * 1.4, height: radius * 0.32))

        // Vibrant cyan atmospheric limb glow
        let limbColors = [UIColor.clear.cgColor, UIColor.cyan.withAlphaComponent(0.45).cgColor] as CFArray
        if let limbGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: limbColors, locations: [0.75, 1.0]) {
            cg.drawRadialGradient(limbGrad, startCenter: centre, startRadius: radius * 0.75, endCenter: centre, endRadius: radius, options: [])
        }
    }

    private static func drawGasGiant(cg: CGContext, radius: CGFloat, centre: CGPoint, baseColor: UIColor, glowColor: UIColor) {
        // Multi-layered Jovian atmospheric bands (amber, cream, golden ochre)
        let bandColors: [UIColor] = [
            UIColor(red: 0.95, green: 0.78, blue: 0.35, alpha: 1.0),
            UIColor(red: 0.85, green: 0.55, blue: 0.22, alpha: 1.0),
            UIColor(red: 0.98, green: 0.90, blue: 0.70, alpha: 1.0),
            UIColor(red: 0.78, green: 0.42, blue: 0.18, alpha: 1.0),
            UIColor(red: 0.92, green: 0.70, blue: 0.30, alpha: 1.0),
            UIColor(red: 0.65, green: 0.30, blue: 0.12, alpha: 1.0)
        ]

        let numBands = 12
        let bandHeight = (radius * 2) / CGFloat(numBands)

        for i in 0..<numBands {
            let y = CGFloat(i) * bandHeight
            let col = bandColors[i % bandColors.count]
            cg.setFillColor(col.cgColor)
            cg.fill(CGRect(x: 0, y: y, width: radius * 2, height: bandHeight + 1))
        }

        // Great Red / Amber Storm Oval
        let stormRect = CGRect(x: radius * 1.05, y: radius * 1.15, width: radius * 0.55, height: radius * 0.35)
        cg.setFillColor(UIColor(red: 0.85, green: 0.28, blue: 0.12, alpha: 0.92).cgColor)
        cg.fillEllipse(in: stormRect)
        cg.setStrokeColor(UIColor(red: 0.98, green: 0.85, blue: 0.40, alpha: 0.75).cgColor)
        cg.setLineWidth(max(1.0, radius * 0.04))
        cg.strokeEllipse(in: stormRect)
    }

    private static func drawStar(cg: CGContext, radius: CGFloat, centre: CGPoint, baseColor: UIColor, glowColor: UIColor) {
        let whiteHot = UIColor(white: 1.0, alpha: 1.0)
        let solarYellow = UIColor(red: 1.0, green: 0.88, blue: 0.20, alpha: 1.0)
        let solarOrange = UIColor(red: 1.0, green: 0.45, blue: 0.05, alpha: 1.0)
        let solarRed = UIColor(red: 0.90, green: 0.15, blue: 0.02, alpha: 1.0)

        let colors = [whiteHot.cgColor, solarYellow.cgColor, solarOrange.cgColor, solarRed.cgColor] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.35, 0.75, 1.0]) {
            cg.drawRadialGradient(grad, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: radius, options: [])
        }

        // Fiery solar plasma granulation / sunspots
        cg.setFillColor(solarRed.withAlphaComponent(0.45).cgColor)
        for _ in 0..<12 {
            let rx = CGFloat.random(in: 0.3...1.7) * radius
            let ry = CGFloat.random(in: 0.3...1.7) * radius
            let rr = CGFloat.random(in: 0.12...0.25) * radius
            cg.fillEllipse(in: CGRect(x: rx - rr, y: ry - rr, width: rr * 2, height: rr * 2))
        }
    }

    private static func drawBlackHole(cg: CGContext, radius: CGFloat, centre: CGPoint, baseColor: UIColor, glowColor: UIColor) {
        // Deep obsidian singularity
        cg.setFillColor(UIColor.black.cgColor)
        cg.fillEllipse(in: CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2))

        // Relativistic photon ring and accretion vortex
        let ringColors = [
            UIColor.clear.cgColor,
            UIColor.purple.withAlphaComponent(0.7).cgColor,
            UIColor.cyan.withAlphaComponent(0.95).cgColor,
            UIColor.white.cgColor
        ] as CFArray
        if let ringGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: ringColors, locations: [0.72, 0.85, 0.94, 1.0]) {
            cg.drawRadialGradient(ringGrad, startCenter: centre, startRadius: radius * 0.7, endCenter: centre, endRadius: radius, options: [])
        }
    }

    private static func drawAntimatter(cg: CGContext, radius: CGFloat, centre: CGPoint, baseColor: UIColor, glowColor: UIColor) {
        cg.setFillColor(UIColor(white: 0.08, alpha: 1.0).cgColor)
        cg.fillEllipse(in: CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2))

        // Crackling quantum energy fissures
        cg.setStrokeColor(UIColor.red.withAlphaComponent(0.85).cgColor)
        cg.setLineWidth(max(1.5, radius * 0.1))
        cg.move(to: CGPoint(x: radius * 0.4, y: radius * 0.3))
        cg.addLine(to: CGPoint(x: radius * 0.9, y: radius * 0.8))
        cg.addLine(to: CGPoint(x: radius * 1.5, y: radius * 0.6))
        cg.addLine(to: CGPoint(x: radius * 1.3, y: radius * 1.4))
        cg.strokePath()

        let auraColors = [UIColor.clear.cgColor, UIColor.red.withAlphaComponent(0.65).cgColor] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: auraColors, locations: [0.65, 1.0]) {
            cg.drawRadialGradient(grad, startCenter: centre, startRadius: radius * 0.65, endCenter: centre, endRadius: radius, options: [])
        }
    }

    private static func draw3DShadingOverlay(cg: CGContext, radius: CGFloat, centre: CGPoint, tier: CelestialTier, glowColor: UIColor) {
        if tier == .star || tier == .blackHole { return }

        // Spherical terminator / ambient occlusion shadow
        let shadowColors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.65).cgColor] as CFArray
        if let sGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: shadowColors, locations: [0.4, 1.0]) {
            cg.drawRadialGradient(sGrad, startCenter: CGPoint(x: radius * 0.65, y: radius * 0.55), startRadius: radius * 0.2, endCenter: centre, endRadius: radius, options: [])
        }

        // Specular highlight at 10 o'clock
        let specCentre = CGPoint(x: radius * 0.65, y: radius * 0.55)
        let specColors = [UIColor.white.withAlphaComponent(0.48).cgColor, UIColor.clear.cgColor] as CFArray
        if let specGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: specColors, locations: [0.0, 1.0]) {
            cg.drawRadialGradient(specGrad, startCenter: specCentre, startRadius: 0, endCenter: specCentre, endRadius: radius * 0.45, options: [])
        }

        // Atmospheric rim light
        let rimColors = [UIColor.clear.cgColor, glowColor.withAlphaComponent(0.55).cgColor] as CFArray
        if let rimGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: rimColors, locations: [0.85, 1.0]) {
            cg.drawRadialGradient(rimGrad, startCenter: centre, startRadius: radius * 0.85, endCenter: centre, endRadius: radius, options: [])
        }
    }
}

// MARK: - Color utilities

extension UIColor {
    func lightened(by amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: min(1.0, r + amount), green: min(1.0, g + amount), blue: min(1.0, b + amount), alpha: a)
    }

    func darkened(by amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: max(0.0, r - amount), green: max(0.0, g - amount), blue: max(0.0, b - amount), alpha: a)
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
