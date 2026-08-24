import CoreGraphics

/// Layout constants shared between the SwiftUI chrome and the SpriteKit scene.
///
/// The banner height in particular used to be written twice — 50 in the
/// SwiftUI frame and 60 in the scene's physics floor — so the play area and
/// the ad quietly disagreed by ten points on every device.
enum Layout {
    /// Height of a standard AdMob banner (GADAdSizeBanner is 320x50).
    static let bannerHeight: CGFloat = 50
    /// Clearance between the banner and the physics floor.
    static let floorPadding: CGFloat = 10
    /// Distance from the top of the scene down to the danger line.
    static let dropLineInset: CGFloat = 160
}
