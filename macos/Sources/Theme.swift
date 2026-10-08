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
                // Inset bevel: a light top-left edge fading out, like the site's inset highlight.
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.14), .clear],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                )
                // One soft drop shadow down-right; the site's own shadow tone vanishes on #12081a.
                .compositingGroup()
                .shadow(color: Color.black.opacity(0.45), radius: 10, x: 4, y: 6)
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

/// Label on the left, a switch in the site's style pinned to the trailing edge: green track when on,
/// bubble track when off, yellow knob. Drawn by hand so it doesn't go grey when the window loses focus.
struct TrailingSwitchStyle: ToggleStyle {
    let palette: Palette
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? palette.alt : palette.surfaceBottom)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
                    .frame(width: 42, height: 24)
                Circle()
                    .fill(palette.foreground)
                    .shadow(color: .black.opacity(0.35), radius: 2, x: 1, y: 1)
                    .frame(width: 18, height: 18)
                    .padding(3)
            }
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Capsule())
            .onTapGesture { withAnimation(.snappy(duration: 0.18)) { configuration.isOn.toggle() } }
            .accessibilityAddTraits(.isButton)
        }
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
