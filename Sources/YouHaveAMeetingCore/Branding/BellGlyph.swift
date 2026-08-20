import CoreGraphics
import Foundation

/// The bell mark, as geometry.
///
/// Both the menu-bar glyph and the app icon are drawn from this one source, so
/// the two can never drift apart. It depends on CoreGraphics alone, which lets
/// `Scripts/GenerateAppIcon.swift` compile it directly without the rest of the
/// library.
///
/// Everything is expressed on a 24x24 design grid with the origin at the
/// bottom left, then fitted to whatever rectangle the caller asks for.
enum BellGlyph {
    /// Stroke weight for the outline treatments, in grid units.
    static let strokeWidth: CGFloat = 1.15

    /// What the bell occupies on the grid, stroke included. Used to fit the
    /// mark to a rectangle without leaving accidental margins.
    static let bounds = CGRect(x: 5.02, y: 2.52, width: 13.96, height: 18.96)

    /// The same, once the ring arcs are drawn. Wider, so fitting to this box
    /// is what makes the bell itself shrink to make room for the arcs.
    static let ringedBounds = CGRect(x: 3.02, y: 2.52, width: 17.96, height: 18.96)

    struct Paths {
        /// The bell body, closed, ready to fill or stroke.
        let body: CGPath
        /// The clapper below the rim - the one element that carries colour.
        let clapper: CGPath
        /// Two arcs flanking the bell, for the ringing state.
        let rings: CGPath
        /// The mute diagonal, corner to corner.
        let slash: CGPath
        /// Grid units per point, so callers can scale stroke widths to match.
        let unit: CGFloat
    }

    /// Fit the mark into `rect`, centred, preserving its proportions.
    ///
    /// `withRings` selects which bounding box is fitted, not whether the arcs
    /// are drawn: the caller decides that. Passing it consistently is what
    /// keeps the ringing state the same overall size as the quiet one.
    static func paths(in rect: CGRect, withRings: Bool = false) -> Paths {
        let box = withRings ? ringedBounds : bounds
        let unit = min(rect.width / box.width, rect.height / box.height)
        var transform = CGAffineTransform(
            translationX: rect.midX - box.midX * unit,
            y: rect.midY - box.midY * unit
        ).scaledBy(x: unit, y: unit)

        func fit(_ path: CGPath) -> CGPath {
            path.copy(using: &transform) ?? path
        }

        return Paths(
            body: fit(bodyPath()),
            clapper: fit(circle(centreX: 12, centreY: 4.6, radius: 1.5)),
            rings: fit(ringsPath()),
            slash: fit(slashPath()),
            unit: unit
        )
    }

    // MARK: - Grid geometry

    /// Rim flare, walls, dome, and the crown nub at the top.
    ///
    /// One closed silhouette rather than a body plus a separate crown circle:
    /// drawn as two shapes the crown reads as a dot floating above the bell,
    /// both when filled and at menu-bar size.
    private static func bodyPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 5.6, y: 6.8))
        path.addLine(to: CGPoint(x: 18.4, y: 6.8))
        path.addCurve(
            to: CGPoint(x: 16.8, y: 12.0),
            control1: CGPoint(x: 17.2, y: 6.8),
            control2: CGPoint(x: 16.8, y: 8.0)
        )
        path.addCurve(
            to: CGPoint(x: 12.85, y: 19.7),
            control1: CGPoint(x: 16.8, y: 16.6),
            control2: CGPoint(x: 15.0, y: 19.4)
        )
        path.addCurve(
            to: CGPoint(x: 11.15, y: 19.7),
            control1: CGPoint(x: 12.7, y: 21.3),
            control2: CGPoint(x: 11.3, y: 21.3)
        )
        path.addCurve(
            to: CGPoint(x: 7.2, y: 12.0),
            control1: CGPoint(x: 9.0, y: 19.4),
            control2: CGPoint(x: 7.2, y: 16.6)
        )
        path.addCurve(
            to: CGPoint(x: 5.6, y: 6.8),
            control1: CGPoint(x: 7.2, y: 8.0),
            control2: CGPoint(x: 6.8, y: 6.8)
        )
        path.closeSubpath()
        return path
    }

    /// Sound, as two arcs struck from the centre of the bell.
    private static func ringsPath() -> CGPath {
        let path = CGMutablePath()
        let centre = CGPoint(x: 12, y: 12.0)
        let radius: CGFloat = 8.4
        for (start, end) in [(15.0, 58.0), (122.0, 165.0)] {
            let from = start * .pi / 180
            // Start each arc with an explicit move. CGPath draws a line from
            // the current point to the arc's start, which would otherwise
            // stitch the two arcs together straight through the bell.
            path.move(to: CGPoint(
                x: centre.x + radius * cos(from),
                y: centre.y + radius * sin(from)
            ))
            path.addArc(
                center: centre,
                radius: radius,
                startAngle: from,
                endAngle: end * .pi / 180,
                clockwise: false
            )
        }
        return path
    }

    /// The mute diagonal. Drawn low-left to high-right, matching the system
    /// idiom so it is read as "muted" and not as an error mark.
    ///
    /// It stops inside the bell's own footprint rather than running corner to
    /// corner: a longer line collides with the rim flare and the clapper, and
    /// at 18pt the three together read as damage rather than as a slash.
    private static func slashPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 5.6, y: 4.6))
        path.addLine(to: CGPoint(x: 18.4, y: 18.8))
        return path
    }

    private static func circle(centreX: CGFloat, centreY: CGFloat, radius: CGFloat) -> CGPath {
        CGPath(
            ellipseIn: CGRect(
                x: centreX - radius,
                y: centreY - radius,
                width: radius * 2,
                height: radius * 2
            ),
            transform: nil
        )
    }
}
