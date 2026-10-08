import AppKit
import SwiftUI

/// xav.ie's palette and surfaces (xav-ie.github.io src/styles/global.css), for light and dark mode.
struct Palette {
    let background, foreground, alt: Color
    let surfaceTop, surfaceBottom, shadow, highlight: Color

    static func current(_ scheme: ColorScheme) -> Palette {
        // --background / --foreground / --alt, with the color-mix() derived tones precomputed.
        scheme == .dark
            ? Palette(background: rgb(0x12081A), foreground: rgb(0xFFF17B), alt: rgb(0x51D136),
                      surfaceTop: rgb(0x210F2E), surfaceBottom: rgb(0x110718),
                      shadow: rgb(0x100717), highlight: rgb(0x413948))
            : Palette(background: rgb(0xBEBDB6), foreground: rgb(0x281336), alt: rgb(0x257015),
                      surfaceTop: rgb(0xC3C2BC), surfaceBottom: rgb(0xB3B2AB),
                      shadow: rgb(0xA7A6A0), highlight: rgb(0xCBCAC5))
    }

    private static func rgb(_ hex: Int) -> Color {
        Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// The site's faint fractal-noise overlay: white specks at ~2% opacity, generated once.
let noise: NSImage = {
    let size = 240
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    var rng = SystemRandomNumberGenerator()
    for y in 0..<size {
        for x in 0..<size {
            let a = CGFloat(UInt8.random(in: 0...255, using: &rng)) / 255 * 0.05
            rep.setColor(NSColor(white: 1, alpha: a), atX: x, y: y)
        }
    }
    let image = NSImage(size: NSSize(width: size, height: size))
    image.addRepresentation(rep)
    return image
}()

extension View {
    /// The site's "bubble" surface: noise over a 155° gradient, soft corner shadow, inset rim.
    func bubble(_ palette: Palette, radius: CGFloat = 18) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [palette.surfaceTop, palette.surfaceBottom],
                                     startPoint: UnitPoint(x: 0.21, y: 0.05), endPoint: UnitPoint(x: 0.79, y: 0.95)))
                .overlay(Image(nsImage: noise).resizable(resizingMode: .tile).clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous)))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
                .shadow(color: palette.shadow, radius: 7, x: 6, y: 6)
                .shadow(color: palette.highlight.opacity(0.6), radius: 2, x: -2, y: -2)
        )
    }
}

/// A full-width card with a serif heading, like the site's project cards.
struct Card<Content: View>: View {
    let palette: Palette
    var title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.custom("Palatino", size: 17).weight(.semibold)) }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .bubble(palette)
    }
}

/// Bubble buttons in the site's colours; `primary` swaps to the foreground fill.
struct BubbleButtonStyle: ButtonStyle {
    let palette: Palette
    var primary = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16).padding(.vertical, 9)
            .foregroundStyle(primary ? palette.background : palette.foreground)
            .background {
                if primary {
                    Capsule().fill(palette.foreground)
                } else {
                    Color.clear.bubble(palette, radius: 20)
                }
            }
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Replaces the hidden traffic lights: round bubble buttons for minimise and close.
struct WindowControls: View {
    let palette: Palette

    var body: some View {
        HStack(spacing: 10) {
            control("minus", "Minimize") { NSApp.keyWindow?.miniaturize(nil) }
            control("xmark", "Close") { NSApp.keyWindow?.performClose(nil) }
        }
    }

    private func control(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.foreground)
        .bubble(palette, radius: 13)
        .help(help)
    }
}
