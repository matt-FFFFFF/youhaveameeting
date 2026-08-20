import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Draws the app icon and writes a complete `.iconset`.
///
/// Run via `make icons`, not during a build: the result is committed, so a
/// plain `make` needs no drawing step. It compiles against
/// `Sources/YouHaveAMeetingCore/Branding/BellGlyph.swift` so the icon and the
/// menu-bar glyph are the same mark by construction.
///
/// Icon Composer would be the native way to author a Liquid Glass icon on
/// macOS 26, but it ships with full Xcode and this project deliberately builds
/// with Command Line Tools alone. The glass treatment is therefore painted
/// here and baked into the `.icns`: it keeps the layered look, but it cannot
/// follow the system's tinted and clear icon modes the way a real `.icon`
/// bundle would.
@main
enum GenerateAppIcon {
    /// Every size an `.icns` wants, as (pixel size, iconset filename).
    static let variants: [(Int, String)] = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png")
    ]

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write(
                Data("usage: GenerateAppIcon <path/to/AppIcon.iconset>\n".utf8)
            )
            exit(2)
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        for (size, name) in variants {
            let image = render(pixels: size)
            try write(image, to: directory.appendingPathComponent(name))
        }
        print("wrote \(variants.count) images to \(directory.path)")
    }

    // MARK: - Palette

    /// Graphite for the body, near-white for the bell, and one saturated
    /// accent that only ever appears on the clapper.
    private enum Ink {
        static let bodyTop = rgb(0x4A, 0x4F, 0x58)
        static let bodyBottom = rgb(0x1E, 0x21, 0x26)
        static let bellTop = rgb(0xFF, 0xFF, 0xFF)
        static let bellBottom = rgb(0xC6, 0xCC, 0xD6)
        static let sparkTop = rgb(0xFF, 0xD4, 0x6B)
        static let sparkBottom = rgb(0xF2, 0x9E, 0x0C)

        static func rgb(_ red: Int, _ green: Int, _ blue: Int, _ alpha: CGFloat = 1) -> CGColor {
            CGColor(
                red: CGFloat(red) / 255,
                green: CGFloat(green) / 255,
                blue: CGFloat(blue) / 255,
                alpha: alpha
            )
        }

        static func white(_ alpha: CGFloat) -> CGColor {
            CGColor(red: 1, green: 1, blue: 1, alpha: alpha)
        }

        static func black(_ alpha: CGFloat) -> CGColor {
            CGColor(red: 0, green: 0, blue: 0, alpha: alpha)
        }
    }

    // MARK: - Drawing

    /// The icon is laid out once on a 1024 canvas and scaled to each size, so
    /// every variant is the same drawing rather than a separate design.
    private static let canvas: CGFloat = 1024
    /// macOS draws large icons at 824 inside 1024, leaving room for the
    /// shadow. Matching it is what makes the icon sit level with system ones.
    private static let body = CGRect(x: 100, y: 100, width: 824, height: 824)

    private static func render(pixels: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let scale = CGFloat(pixels) / canvas
        context.scaleBy(x: scale, y: scale)
        context.setShouldAntialias(true)

        let shape = squircle(in: body)
        castShadow(of: shape, in: context)
        fillBody(shape, in: context)
        glaze(shape, in: context)
        rim(shape, in: context)
        drawBell(in: context)

        return context.makeImage()!
    }

    /// The rounded-square outline, as a superellipse rather than a rounded
    /// rectangle: circular corners visibly disagree with the continuous curve
    /// macOS uses, and the difference shows most at the sizes people see.
    private static func squircle(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let exponent: CGFloat = 5
        let halfWidth = rect.width / 2
        let halfHeight = rect.height / 2
        let steps = 720

        for step in 0...steps {
            let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
            let cosine = cos(angle)
            let sine = sin(angle)
            let x = pow(abs(cosine), 2 / exponent) * halfWidth * (cosine < 0 ? -1 : 1)
            let y = pow(abs(sine), 2 / exponent) * halfHeight * (sine < 0 ? -1 : 1)
            let point = CGPoint(x: rect.midX + x, y: rect.midY + y)
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }

    private static func castShadow(of shape: CGPath, in context: CGContext) {
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -14),
            blur: 30,
            color: Ink.black(0.32)
        )
        context.setFillColor(Ink.bodyBottom)
        context.addPath(shape)
        context.fillPath()
        context.restoreGState()
    }

    private static func fillBody(_ shape: CGPath, in context: CGContext) {
        context.saveGState()
        context.addPath(shape)
        context.clip()
        linearGradient(
            from: CGPoint(x: 0, y: body.maxY),
            to: CGPoint(x: 0, y: body.minY),
            stops: [(0, Ink.bodyTop), (1, Ink.bodyBottom)],
            in: context
        )
        context.restoreGState()
    }

    /// The glass: a broad sheen from the upper left, a bright lip along the
    /// top edge, and a darkening at the foot. Three cheap gradients rather
    /// than a real blur, which at these sizes look the same.
    private static func glaze(_ shape: CGPath, in context: CGContext) {
        context.saveGState()
        context.addPath(shape)
        context.clip()

        radialGradient(
            centre: CGPoint(x: 330, y: 800),
            radius: 620,
            stops: [(0, Ink.white(0.20)), (1, Ink.white(0))],
            in: context
        )
        linearGradient(
            from: CGPoint(x: 0, y: body.maxY),
            to: CGPoint(x: 0, y: body.maxY - 260),
            stops: [(0, Ink.white(0.26)), (1, Ink.white(0))],
            in: context
        )
        linearGradient(
            from: CGPoint(x: 0, y: body.minY),
            to: CGPoint(x: 0, y: body.minY + 300),
            stops: [(0, Ink.black(0.24)), (1, Ink.black(0))],
            in: context
        )
        context.restoreGState()
    }

    /// A lit edge, brightest at the top, so the body reads as a solid piece of
    /// glass rather than a flat colour swatch.
    private static func rim(_ shape: CGPath, in context: CGContext) {
        context.saveGState()
        context.addPath(shape)
        context.setLineWidth(5)
        context.replacePathWithStrokedPath()
        context.clip()
        linearGradient(
            from: CGPoint(x: 0, y: body.maxY),
            to: CGPoint(x: 0, y: body.minY),
            stops: [(0, Ink.white(0.55)), (0.55, Ink.white(0.10)), (1, Ink.white(0.16))],
            in: context
        )
        context.restoreGState()
    }

    private static func drawBell(in context: CGContext) {
        let frame = CGRect(x: 512 - 250, y: 540 - 250, width: 500, height: 500)
        let paths = BellGlyph.paths(in: frame)

        // Lift the bell off the base. Without the shadow it looks printed on
        // the glass instead of resting above it.
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -16),
            blur: 34,
            color: Ink.black(0.45)
        )
        context.setFillColor(Ink.bellTop)
        context.addPath(paths.body)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(paths.body)
        context.clip()
        linearGradient(
            from: CGPoint(x: 0, y: frame.maxY),
            to: CGPoint(x: 0, y: frame.minY),
            stops: [(0, Ink.bellTop), (1, Ink.bellBottom)],
            in: context
        )
        context.restoreGState()

        // The clapper is the only colour in the icon, so it also carries the
        // glow: one warm point in an otherwise grey mark.
        context.saveGState()
        context.setShadow(
            offset: .zero,
            blur: 26,
            color: Ink.sparkBottom
        )
        context.setFillColor(Ink.sparkTop)
        context.addPath(paths.clapper)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(paths.clapper)
        context.clip()
        let clapper = paths.clapper.boundingBox
        linearGradient(
            from: CGPoint(x: 0, y: clapper.maxY),
            to: CGPoint(x: 0, y: clapper.minY),
            stops: [(0, Ink.sparkTop), (1, Ink.sparkBottom)],
            in: context
        )
        context.restoreGState()
    }

    // MARK: - Gradient helpers

    private static func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
        CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            colors: stops.map(\.1) as CFArray,
            locations: stops.map(\.0)
        )!
    }

    private static func linearGradient(
        from start: CGPoint,
        to end: CGPoint,
        stops: [(CGFloat, CGColor)],
        in context: CGContext
    ) {
        context.drawLinearGradient(
            gradient(stops),
            start: start,
            end: end,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    private static func radialGradient(
        centre: CGPoint,
        radius: CGFloat,
        stops: [(CGFloat, CGColor)],
        in context: CGContext
    ) {
        context.drawRadialGradient(
            gradient(stops),
            startCenter: centre,
            startRadius: 0,
            endCenter: centre,
            endRadius: radius,
            options: []
        )
    }

    // MARK: - Output

    private static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
