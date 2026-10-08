import AppKit
import SwiftUI

/// Renders the app icon's iconset (build.sh turns it into AppIcon.icns with iconutil), so no raster
/// assets live in the repo: the buddy on macOS's rounded-square tile in xav.ie's purple and yellow.
func renderIconset(to dir: String) -> Never {
    let purple = CGColor(red: 0x28 / 255, green: 0x13 / 255, blue: 0x36 / 255, alpha: 1)
    let yellow = CGColor(red: 0xFF / 255, green: 0xF1 / 255, blue: 0x7B / 255, alpha: 1)
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
        let px = points * scale
        let size = CGFloat(px)
        let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // macOS icon grid: the tile is 824/1024 of the canvas with a ~185/1024 corner radius.
        let tile = CGRect(x: size * 100 / 1024, y: size * 100 / 1024, width: size * 824 / 1024, height: size * 824 / 1024)
        ctx.addPath(CGPath(roundedRect: tile, cornerWidth: size * 185 / 1024, cornerHeight: size * 185 / 1024, transform: nil))
        ctx.setFillColor(purple)
        ctx.fillPath()
        // Glyph centred on the tile, 76% of its width. SwiftUI paths are y-down; flip for CoreGraphics.
        let glyph = tile.insetBy(dx: tile.width * 0.12, dy: tile.height * 0.12)
        var flip = CGAffineTransform(translationX: 0, y: size).scaledBy(x: 1, y: -1)
        if let path = PathShape.buddy.path(in: glyph).cgPath.copy(using: &flip) {
            ctx.addPath(path)
            ctx.setFillColor(yellow)
            ctx.fillPath(using: .evenOdd)
        }
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let url = URL(fileURLWithPath: dir).appendingPathComponent(name) as CFURL
        let out = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(out, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(out)
    }
    exit(0)
}
