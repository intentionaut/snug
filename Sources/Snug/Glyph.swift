import AppKit

/// The menu bar icon: a mousehole with a blanket drawn up (design/snug-options-2, F), the same in
/// every state. Drawn on a 16-unit grid, so at 16 pt each unit is one point. Template image, so
/// macOS tints it for light and dark menu bars.
enum Glyph {
    static func image(collapsed: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.addPath(arch)
            ctx.addPath(blanket)
            ctx.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = collapsed ? "Show hidden items" : "Hide items"
        return image
    }

    /// The hole's frame: outer arch radius 6, inner 3.8, both centred on (8, 8), legs to the floor.
    private static let arch: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 2, y: 15))
        p.addLine(to: CGPoint(x: 2, y: 8))
        // y grows downward here, so sweeping from π by +π passes over the top.
        p.addRelativeArc(center: CGPoint(x: 8, y: 8), radius: 6, startAngle: .pi, delta: .pi)
        p.addLine(to: CGPoint(x: 14, y: 15))
        p.addLine(to: CGPoint(x: 11.8, y: 15))
        p.addLine(to: CGPoint(x: 11.8, y: 8))
        p.addRelativeArc(center: CGPoint(x: 8, y: 8), radius: 3.8, startAngle: 0, delta: -.pi)
        p.addLine(to: CGPoint(x: 4.2, y: 15))
        p.closeSubpath()
        return p
    }()

    /// The blanket filling the bottom of the hole, its top edge one wave.
    private static let blanket: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 4.2, y: 15))
        p.addLine(to: CGPoint(x: 4.2, y: 11.2))
        p.addQuadCurve(to: CGPoint(x: 8, y: 11), control: CGPoint(x: 6.1, y: 9.4))
        p.addQuadCurve(to: CGPoint(x: 11.8, y: 10.8), control: CGPoint(x: 9.9, y: 12.6))
        p.addLine(to: CGPoint(x: 11.8, y: 15))
        p.closeSubpath()
        return p
    }()
}
