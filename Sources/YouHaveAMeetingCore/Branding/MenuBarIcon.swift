import AppKit

/// Renders the menu-bar glyphs from `BellGlyph`.
///
/// Template images, so macOS handles light, dark and the highlighted menu
/// state. Nothing here chooses a colour: state is carried by shape and fill
/// weight alone, which is the only thing that survives a menu bar the user may
/// have tinted, inverted, or put over any wallpaper.
enum MenuBarIcon {
    /// Standard status-item artwork size. The mark is fitted to it, so the
    /// glyph fills the square rather than floating in it.
    static let size = NSSize(width: 18, height: 18)

    static func image(for state: MenuBarIconState) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(state, in: rect, context: context)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = state.accessibilityDescription
        return image
    }

    private static func draw(_ state: MenuBarIconState, in rect: CGRect, context: CGContext) {
        // Fit to the wider box whenever the arcs are drawn, so a ringed state
        // is the same overall size as a plain one and the glyph never jumps.
        let hasRings = state == .alerting || state == .forced
        let paths = BellGlyph.paths(in: rect, withRings: hasRings)
        let stroke = BellGlyph.strokeWidth * paths.unit

        context.setFillColor(.black)
        context.setStrokeColor(.black)
        context.setLineWidth(stroke)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Fill says "now", the arcs say "will ring". Forced is the outline
        // bell with arcs - it will ring, guaranteed - which keeps it distinct
        // from alerting, where a filled bell says one is ringing already.
        switch state {
        case .idle, .quiet:
            outline(paths, in: context)
        case .forced:
            outline(paths, in: context)
            rings(paths, in: context)
        case .imminent:
            solid(paths, in: context)
        case .alerting:
            solid(paths, in: context)
            rings(paths, in: context)
        }

        if state == .quiet {
            slash(paths, stroke: stroke, in: context)
        }
    }

    private static func outline(_ paths: BellGlyph.Paths, in context: CGContext) {
        context.addPath(paths.body)
        context.addPath(paths.clapper)
        context.strokePath()
    }

    private static func solid(_ paths: BellGlyph.Paths, in context: CGContext) {
        context.addPath(paths.body)
        context.addPath(paths.clapper)
        context.fillPath()
    }

    private static func rings(_ paths: BellGlyph.Paths, in context: CGContext) {
        context.addPath(paths.rings)
        context.strokePath()
    }

    /// The mute diagonal, cut clear of the bell before being drawn.
    ///
    /// A template image has no background colour to knock out with, so the gap
    /// is punched in the alpha channel instead. Without it the slash merges
    /// into the bell's own strokes and reads as a smudge at 18pt.
    private static func slash(_ paths: BellGlyph.Paths, stroke: CGFloat, in context: CGContext) {
        context.saveGState()
        context.setBlendMode(.clear)
        context.setLineWidth(stroke * 1.9)
        context.addPath(paths.slash)
        context.strokePath()
        context.restoreGState()

        context.setLineWidth(stroke)
        context.addPath(paths.slash)
        context.strokePath()
    }
}
