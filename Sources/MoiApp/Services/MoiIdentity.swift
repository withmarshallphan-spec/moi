import AppKit
import Foundation

enum MoiIdentity {
    /// The app-icon character, drawn from `MoiMark` so the dock matches the bundle icon
    /// even when Moi runs unbundled from `.build`.
    static let logo: NSImage = MoiMark.image(size: 512)
}
