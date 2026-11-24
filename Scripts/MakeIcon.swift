// Run from the project root:
// swiftc Sources/ClawdCompanion/MascotArt.swift Scripts/MakeIcon.swift -o /tmp/ClawdMakeIcon
// /tmp/ClawdMakeIcon
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@main
struct MakeIcon {
    enum IconError: Error {
        case bitmap, png
    }

    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    static func bitmap(_ width: Int, _ height: Int) throws -> CGContext {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw IconError.bitmap }
        return ctx
    }

    static func png(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data,
                                                         UTType.png.identifier as CFString,
                                                         1, nil) else { throw IconError.png }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw IconError.png }
        return data as Data
    }

    static func tile() throws -> CGImage {
        let ctx = try bitmap(1024, 1024)
        ctx.translateBy(x: 0, y: 1024)
        ctx.scaleBy(x: 1, y: -1)

        let tile = Path(roundedRect: CGRect(x: 87, y: 77, width: 850, height: 850),
                        cornerRadius: 194, style: .continuous).cgPath
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 19,
                      color: CGColor(gray: 0, alpha: 0.35))
        ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
        ctx.addPath(tile)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.addPath(tile)
        ctx.clip()
        let colors = [
            CGColor(srgbRed: 0.272, green: 0.218, blue: 0.226, alpha: 1),
            CGColor(srgbRed: 0.165, green: 0.150, blue: 0.174, alpha: 1),
            CGColor(srgbRed: 0.079, green: 0.084, blue: 0.111, alpha: 1)
        ]
        let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray,
                                  locations: [0, 0.55, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 190, y: 77),
                               end: CGPoint(x: 850, y: 927),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.setStrokeColor(CGColor(srgbRed: 0.97, green: 0.83, blue: 0.77, alpha: 0.22))
        ctx.setLineWidth(5)
        ctx.addPath(tile)
        ctx.strokePath()

        ctx.saveGState()
        ctx.translateBy(x: 102, y: 145)
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 9,
                      color: CGColor(gray: 0.02, alpha: 0.42))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        MascotPixels.draw(in: ctx, size: CGSize(width: 820, height: 703),
                          pose: .happy, facingLeft: false, frame: 0)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
        guard let image = ctx.makeImage() else { throw IconError.bitmap }
        return image
    }

    static func menuIcon(scale: Int) throws -> CGImage {
        let ctx = try bitmap(20 * scale, 18 * scale)
        ctx.translateBy(x: 0, y: CGFloat(18 * scale))
        ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        ctx.setShouldAntialias(false)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
            ctx.fill(CGRect(x: x, y: y, width: w, height: h))
        }
        fill(4, 2, 12, 10)
        fill(3, 3, 14, 8)
        fill(1, 5, 2, 5)
        fill(0, 5, 1, 2)
        fill(17, 5, 2, 5)
        fill(19, 5, 1, 2)
        fill(4, 11, 2, 5)
        fill(7, 11, 2, 3)
        fill(11, 11, 2, 3)
        fill(14, 11, 2, 5)
        for x in [6, 12] { ctx.clear(CGRect(x: x, y: 5, width: 2, height: 3)) }
        guard let image = ctx.makeImage() else { throw IconError.bitmap }
        return image
    }

    static func main() throws {
        let fm = FileManager.default
        let resources = URL(fileURLWithPath: fm.currentDirectoryPath)
            .appendingPathComponent("Resources", isDirectory: true)
        let original = try tile()

        // Each ICNS chunk stores a four-byte type and its total size in network order.
        func chunk(_ type: String, _ payload: Data) -> Data {
            var result = Data(type.utf8)
            var length = UInt32(8 + payload.count).bigEndian
            withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
            result.append(payload)
            return result
        }

        let representations = [
            ("icp4", 16), ("ic11", 32), ("icp5", 32), ("ic12", 64),
            ("ic07", 128), ("ic13", 256), ("ic08", 256), ("ic14", 512),
            ("ic09", 512), ("ic10", 1024)
        ]
        var chunks = Data()
        for (type, pixels) in representations {
            let ctx = try bitmap(pixels, pixels)
            ctx.interpolationQuality = .high
            ctx.draw(original, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
            guard let image = ctx.makeImage() else { throw IconError.bitmap }
            chunks.append(chunk(type, try png(image)))
        }
        try chunk("icns", chunks).write(to: resources.appendingPathComponent("Clawd.icns"), options: .atomic)
        for scale in [1, 2] {
            let name = scale == 1 ? "MenuPet.png" : "MenuPet@2x.png"
            try png(menuIcon(scale: scale)).write(to: resources.appendingPathComponent(name), options: .atomic)
        }
    }
}
