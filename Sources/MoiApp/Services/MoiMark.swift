import AppKit

/// Moi's face: a dark tile with two bright eyes, like something peeking out of the notch.
///
/// Drawn in code rather than shipped as artwork so the app icon (via
/// `Scripts/make-icon.sh`), the dock image, and the in-app `MoiFace` stay one character.
/// Pure AppKit/CoreGraphics with no bundle lookups, so the icon script can compile it alone.
enum MoiMark {
    static let eyeColor = CGColor(srgbRed: 0.20, green: 0.78, blue: 1.0, alpha: 1)

    /// Full app-icon artwork, following Apple's macOS icon grid (an 824/1024 tile with a soft shadow).
    static func drawIcon(in rect: CGRect, context: CGContext) {
        let side = min(rect.width, rect.height)
        let tileSide = side * 824 / 1024
        let tile = CGRect(x: rect.midX - tileSide / 2, y: rect.midY - tileSide / 2 + side * 0.008, width: tileSide, height: tileSide)
        let radius = tileSide * 0.2237
        let shape = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -side * 0.012), blur: side * 0.03, color: CGColor(gray: 0, alpha: 0.4))
        context.addPath(shape)
        context.setFillColor(CGColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 1))
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(shape)
        context.clip()
        let colors = [CGColor(srgbRed: 0.17, green: 0.18, blue: 0.21, alpha: 1), CGColor(srgbRed: 0.04, green: 0.04, blue: 0.05, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: tile.midX, y: tile.maxY), end: CGPoint(x: tile.midX, y: tile.minY), options: [])
        }
        context.restoreGState()

        context.addPath(shape)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.10))
        context.setLineWidth(max(1, side * 0.004))
        context.strokePath()

        drawEyes(in: tile, context: context)
    }

    /// Oval eyes plus a small smile — tall bars alone read as a pause button.
    static func drawEyes(in tile: CGRect, context: CGContext) {
        let width = tile.width * 0.135
        let height = tile.width * 0.2
        let spread = tile.width * 0.155
        let eyeCenterY = tile.midY + tile.width * 0.075
        context.saveGState()
        context.setShadow(offset: .zero, blur: tile.width * 0.07, color: eyeColor.copy(alpha: 0.75))
        context.setFillColor(eyeColor)
        for direction in [-1.0, 1.0] {
            context.fillEllipse(in: CGRect(x: tile.midX + direction * spread - width / 2, y: eyeCenterY - height / 2, width: width, height: height))
        }
        let smileWidth = tile.width * 0.16
        let smileY = tile.midY - tile.width * 0.13
        context.setStrokeColor(eyeColor)
        context.setLineWidth(tile.width * 0.045)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: tile.midX - smileWidth / 2, y: smileY))
        context.addQuadCurve(to: CGPoint(x: tile.midX + smileWidth / 2, y: smileY), control: CGPoint(x: tile.midX, y: smileY - tile.width * 0.09))
        context.strokePath()
        context.restoreGState()
    }

    static func image(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            drawIcon(in: rect, context: context)
            return true
        }
    }
}
