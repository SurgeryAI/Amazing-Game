import CoreGraphics

/// Layout constants shared between the SwiftUI chrome and the SpriteKit scene.
///
/// Two separate coordinate spaces meet here, which is where the overlap bugs
/// come from. The `SpriteView` deliberately ignores the safe area so the
/// starfield reaches the physical screen edges — but the banner and the HUD
/// are laid out *inside* the safe area. So the scene's bottom edge is below
/// the banner by the height of the home indicator, and its top edge is above
/// the HUD by the height of the notch. Neither the floor nor the danger line
/// can be a fixed distance from the scene edge; both have to add the inset.
/// `GameScene.setSafeAreaInsets(top:bottom:)` is where that happens.
enum Layout {
    /// Height of a standard AdMob banner (GADAdSizeBanner is 320x50).
    static let bannerHeight: CGFloat = 50

    /// Gap between the top of the banner and the physics floor.
    ///
    /// Bodies rest *on* the floor, and their glow renders outside their
    /// radius, so this needs to clear the widest glow (22pt on a Black Hole)
    /// rather than just touching the banner.
    static let floorPadding: CGFloat = 14

    /// Minimum distance from the top of the scene down to the danger line,
    /// used on devices with little or no top inset.
    static let dropLineInset: CGFloat = 160

    /// Space reserved below the top inset for the HUD panel, so the danger
    /// line never slides underneath the score readout — which it did once a
    /// combo counter appeared and made the panel taller.
    static let hudClearance: CGFloat = 118
}
