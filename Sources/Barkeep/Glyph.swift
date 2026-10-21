import AppKit

/// The beard-and-bowtie menu bar icon (design/icon-options, option A), drawn as a template image
/// so macOS tints it for light and dark menu bars. Filled means items are hidden; outline means showing.
/// Coordinates are the app icon's 1024-unit space, cropped to the glyph.
enum Glyph {
    private static let viewBox = CGRect(x: 240, y: 300, width: 544, height: 580)

    static func image(filled: Bool) -> NSImage {
        let height: CGFloat = 16
        let size = NSSize(width: height * viewBox.width / viewBox.height, height: height)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let scale = rect.height / viewBox.height
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -viewBox.minX, y: -viewBox.minY)
            ctx.setLineJoin(.round)

            if filled {
                ctx.addPath(beard); ctx.fillPath()
                // Cut a gap around the moustache so it separates from the beard.
                ctx.setBlendMode(.clear)
                ctx.setLineWidth(40)
                ctx.addPath(moustache); ctx.strokePath()
                ctx.setBlendMode(.normal)
                ctx.addPath(moustache); ctx.fillPath()
                ctx.addPath(bow); ctx.fillPath()
                ctx.addPath(knot); ctx.fillPath()
            } else {
                ctx.setLineWidth(30)
                for path in [beard, moustache, bow] { ctx.addPath(path) }
                ctx.strokePath()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = filled ? "Show hidden items" : "Hide items"
        return image
    }

    private static let beard: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 300, y: 360))
        p.addQuadCurve(to: CGPoint(x: 512, y: 640), control: CGPoint(x: 300, y: 600))
        p.addQuadCurve(to: CGPoint(x: 724, y: 360), control: CGPoint(x: 724, y: 600))
        p.addQuadCurve(to: CGPoint(x: 620, y: 510), control: CGPoint(x: 700, y: 500))
        p.addQuadCurve(to: CGPoint(x: 512, y: 492), control: CGPoint(x: 560, y: 485))
        p.addQuadCurve(to: CGPoint(x: 404, y: 510), control: CGPoint(x: 464, y: 485))
        p.addQuadCurve(to: CGPoint(x: 300, y: 360), control: CGPoint(x: 324, y: 500))
        p.closeSubpath()
        return p
    }()

    private static let moustache: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 380, y: 500))
        p.addQuadCurve(to: CGPoint(x: 512, y: 470), control: CGPoint(x: 450, y: 430))
        p.addQuadCurve(to: CGPoint(x: 644, y: 500), control: CGPoint(x: 574, y: 430))
        p.addQuadCurve(to: CGPoint(x: 512, y: 500), control: CGPoint(x: 590, y: 530))
        p.addQuadCurve(to: CGPoint(x: 380, y: 500), control: CGPoint(x: 434, y: 530))
        p.closeSubpath()
        return p
    }()

    private static let bow: CGPath = {
        let p = CGMutablePath()
        for side: CGFloat in [-1, 1] {
            p.move(to: CGPoint(x: 512, y: 770))
            p.addLine(to: CGPoint(x: 512 + side * 152, y: 684.5))
            p.addQuadCurve(to: CGPoint(x: 512 + side * 152, y: 855.5), control: CGPoint(x: 512 + side * 171, y: 770))
            p.closeSubpath()
        }
        return p
    }()

    private static let knot = CGPath(roundedRect: CGRect(x: 478.75, y: 727.25, width: 66.5, height: 85.5),
                                     cornerWidth: 14.25, cornerHeight: 14.25, transform: nil)
}
