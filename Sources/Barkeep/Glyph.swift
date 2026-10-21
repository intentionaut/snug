import AppKit

/// The menu bar icon: a solid short boxed beard and bowtie (design/icon-options, round 2 option 4),
/// the same in every state. Drawn as a template image so macOS tints it for light and dark bars.
enum Glyph {
    private static let viewBox = CGRect(x: 240, y: 350, width: 544, height: 500)

    static func image(collapsed: Bool) -> NSImage {
        let height: CGFloat = 16
        let size = NSSize(width: height * viewBox.width / viewBox.height, height: height)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let scale = rect.height / viewBox.height
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -viewBox.minX, y: -viewBox.minY)
            ctx.addPath(boxedBeard)
            ctx.fillPath()
            addBow(to: ctx, centreY: 730, size: 110)
            ctx.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = collapsed ? "Show hidden items" : "Hide items"
        return image
    }

    private static let boxedBeard: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 300, y: 400))
        p.addQuadCurve(to: CGPoint(x: 420, y: 490), control: CGPoint(x: 330, y: 480))
        p.addLine(to: CGPoint(x: 604, y: 490))
        p.addQuadCurve(to: CGPoint(x: 724, y: 400), control: CGPoint(x: 694, y: 480))
        p.addLine(to: CGPoint(x: 724, y: 520))
        p.addQuadCurve(to: CGPoint(x: 512, y: 610), control: CGPoint(x: 720, y: 600))
        p.addQuadCurve(to: CGPoint(x: 300, y: 520), control: CGPoint(x: 304, y: 600))
        p.closeSubpath()
        return p
    }()

    /// Two wings meeting at the centre, plus a rounded knot.
    private static func addBow(to ctx: CGContext, centreY y: CGFloat, size s: CGFloat) {
        let x: CGFloat = 512
        for side: CGFloat in [-1, 1] {
            ctx.move(to: CGPoint(x: x, y: y))
            ctx.addLine(to: CGPoint(x: x + side * 1.6 * s, y: y - 0.9 * s))
            ctx.addQuadCurve(to: CGPoint(x: x + side * 1.6 * s, y: y + 0.9 * s), control: CGPoint(x: x + side * 1.8 * s, y: y))
            ctx.closePath()
        }
        // Fill the wings before adding the knot, or the overlap cancels out and leaves a hole.
        ctx.fillPath()
        ctx.addPath(CGPath(roundedRect: CGRect(x: x - 0.35 * s, y: y - 0.45 * s, width: 0.7 * s, height: 0.9 * s),
                           cornerWidth: 0.15 * s, cornerHeight: 0.15 * s, transform: nil))
    }
}
