import AppKit
import SwiftUI

/// xav.ie's palette and surfaces (xav-ie.github.io src/styles/global.css), for light and dark mode.
struct Palette {
    let background, foreground, alt: Color
    let surfaceTop, surfaceBottom, shadow, highlight: Color
    /// The foreground mixed 55% into the background, for "on" switch tracks.
    let mutedForeground: Color

    static func current(_ scheme: ColorScheme) -> Palette {
        // --background / --foreground / --alt, with the color-mix() derived tones precomputed.
        scheme == .dark
            ? Palette(background: rgb(0x12081A), foreground: rgb(0xFFF17B), alt: rgb(0x51D136),
                      surfaceTop: rgb(0x210F2E), surfaceBottom: rgb(0x110718),
                      shadow: rgb(0x100717), highlight: rgb(0x413948), mutedForeground: rgb(0x7D7146))
            : Palette(background: rgb(0xBEBDB6), foreground: rgb(0x281336), alt: rgb(0x257015),
                      surfaceTop: rgb(0xC3C2BC), surfaceBottom: rgb(0xB3B2AB),
                      shadow: rgb(0xA7A6A0), highlight: rgb(0xCBCAC5), mutedForeground: rgb(0x7A707C))
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

/// Keyboard focus like the site's `:focus-visible`: a 2pt foreground outline 2pt outside the control.
/// Makes the control reachable with Tab (and Space/Return to activate) even without Full Keyboard Access.
struct FocusRing: ViewModifier {
    let palette: Palette
    var radius: CGFloat = 8
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable(interactions: .activate)
            .focusEffectDisabled()
            .focused($focused)
            .overlay(
                RoundedRectangle(cornerRadius: radius + 4, style: .continuous)
                    .stroke(palette.foreground, lineWidth: 2)
                    .padding(-4)
                    .opacity(focused ? 1 : 0)
            )
    }
}

/// The site's theme-toggle look as an on/off switch: a sunken trough with a raised knob that is dim
/// on the left when off and lit in the foreground colour on the right when on. Label on the left.
struct TrailingSwitchStyle: ToggleStyle {
    let palette: Palette

    func makeBody(configuration: Configuration) -> some View { SwitchRow(configuration: configuration, palette: palette) }
}

private struct SwitchRow: View {
    let configuration: ToggleStyleConfiguration
    let palette: Palette
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    var body: some View {
        HStack {
            configuration.label
            Spacer()
            Button {
                withAnimation(.snappy(duration: 0.18)) { configuration.isOn.toggle() }
            } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    // Sunken trough; muted yellow when on.
                    Capsule()
                        .fill((configuration.isOn ? palette.mutedForeground : palette.surfaceBottom)
                            .shadow(.inner(color: .black.opacity(0.45), radius: 4, x: 3, y: 3))
                            .shadow(.inner(color: palette.highlight, radius: 1.5, x: -1, y: -1)))
                        .frame(width: 46, height: 26)
                    // Raised purple knob with a light top-left rim and a dark bottom-right edge.
                    Circle()
                        .fill(LinearGradient(colors: [palette.surfaceTop, palette.surfaceBottom],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(Circle().strokeBorder(
                            LinearGradient(colors: [Color.white.opacity(hovering ? 0.45 : 0.3), .clear, Color.black.opacity(0.4)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1.2))
                        .shadow(color: .black.opacity(0.55), radius: 2.5, x: 1.5, y: 2)
                        .frame(width: 20, height: 20)
                        .padding(3)
                }
            }
            .buttonStyle(.plain)
            .modifier(FocusRing(palette: palette, radius: 13))
            .onHover { hovering = $0 }
            .opacity(enabled ? 1 : 0.4)
        }
        // VoiceOver sees a native switch with the row's label and on/off value.
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// A link in the site's style: accent colour, underlined on hover, pointing-hand cursor, focus ring.
struct SiteLink<Icon: View>: View {
    let title: String
    let url: URL
    let palette: Palette
    @ViewBuilder var icon: Icon
    @State private var hovering = false

    var body: some View {
        Link(destination: url) {
            Label { Text(title).underline(hovering) } icon: { icon }
        }
        .foregroundStyle(palette.alt)
        .onHover { inside in
            hovering = inside
            inside ? NSCursor.pointingHand.push() : NSCursor.pop()
        }
        .modifier(FocusRing(palette: palette, radius: 4))
    }
}

extension SiteLink where Icon == EmptyView {
    init(_ title: String, url: URL, palette: Palette) {
        self.init(title: title, url: url, palette: palette) { EmptyView() }
    }
}

/// Plain text buttons in the accent colour, underlined on hover (Show, Copy).
struct TextButtonStyle: ButtonStyle {
    let palette: Palette

    func makeBody(configuration: Configuration) -> some View { TextButtonLabel(configuration: configuration, palette: palette) }
}

private struct TextButtonLabel: View {
    let configuration: ButtonStyleConfiguration
    let palette: Palette
    @State private var hovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(palette.alt)
            .underline(hovering)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .onHover { hovering = $0 }
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
        WindowControl(symbol: symbol, help: help, palette: palette, action: action)
    }
}

private struct WindowControl: View {
    let symbol: String
    let help: String
    let palette: Palette
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.foreground)
        .opacity(hovering ? 1 : 0.7)
        .bubble(palette, radius: 13)
        .onHover { hovering = $0 }
        .modifier(FocusRing(palette: palette, radius: 13))
        .help(help)
        .accessibilityLabel(help)
    }
}
