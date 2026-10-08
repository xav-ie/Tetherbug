import AppKit
import SwiftUI

/// xav.ie's palette and surfaces (xav-ie.github.io src/styles/global.css), for light and dark mode.
struct Palette {
    let background, foreground, alt: Color
    let surfaceTop, surfaceBottom, shadow, highlight: Color
    /// A brighter purple for "on" switch tracks.
    let onTrack: Color
    /// The off switch trough: a little brighter than the card so it reads against it.
    let offTrack: Color

    static func current(_ scheme: ColorScheme) -> Palette {
        // --background / --foreground / --alt, with the color-mix() derived tones precomputed.
        scheme == .dark
            ? Palette(background: rgb(0x12081A), foreground: rgb(0xFFF17B), alt: rgb(0x51D136),
                      surfaceTop: rgb(0x210F2E), surfaceBottom: rgb(0x110718),
                      shadow: rgb(0x100717), highlight: rgb(0x413948), onTrack: rgb(0x4A2A63), offTrack: rgb(0x24132F))
            : Palette(background: rgb(0xBEBDB6), foreground: rgb(0x281336), alt: rgb(0x257015),
                      surfaceTop: rgb(0xC3C2BC), surfaceBottom: rgb(0xB3B2AB),
                      shadow: rgb(0xA7A6A0), highlight: rgb(0xCBCAC5), onTrack: rgb(0x9E8AAF), offTrack: rgb(0xA9A8A1))
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

/// App-level keyboard navigation. macOS only lets Tab reach text fields unless the user enables
/// Keyboard navigation, so the window drives focus itself: controls register their on-screen frame
/// and action, Tab/Shift-Tab walk them in reading order, Space/Return activate, Escape clears.
final class KeyboardFocus: ObservableObject {
    struct Entry {
        var frame: CGRect
        var action: () -> Void
    }

    @Published var current: UUID?
    var entries: [UUID: Entry] = [:]

    private var ordered: [UUID] {
        entries.sorted { a, b in
            abs(a.value.frame.midY - b.value.frame.midY) < 6 ? a.value.frame.minX < b.value.frame.minX : a.value.frame.midY < b.value.frame.midY
        }.map(\.key)
    }

    func move(by step: Int) {
        let order = ordered
        guard !order.isEmpty else { return }
        if let current, let i = order.firstIndex(of: current) {
            self.current = order[(i + step + order.count) % order.count]
        } else {
            current = step > 0 ? order.first : order.last
        }
    }

    func activate() -> Bool {
        guard let current, let entry = entries[current] else { return false }
        entry.action()
        return true
    }
}

extension View {
    /// Joins the window's keyboard navigation; draws the site's `:focus-visible` ring (a 2pt
    /// foreground outline 2pt outside the control) while focused.
    func keyboardFocusable(_ palette: Palette, radius: CGFloat = 8, action: @escaping () -> Void) -> some View {
        modifier(KeyboardFocusable(palette: palette, radius: radius, action: action))
    }

    /// The window side: owns key handling for everything marked `keyboardFocusable`.
    func keyboardNavigation(_ focus: KeyboardFocus) -> some View {
        modifier(KeyboardNavigation(focus: focus))
    }
}

private struct KeyboardFocusable: ViewModifier {
    let palette: Palette
    let radius: CGFloat
    let action: () -> Void
    @EnvironmentObject private var focus: KeyboardFocus
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { geometry in
                let frame = geometry.frame(in: .named(KeyboardNavigation.space))
                Color.clear
                    .onAppear { focus.entries[id] = .init(frame: frame, action: action) }
                    .onChange(of: frame) { _, frame in focus.entries[id] = .init(frame: frame, action: action) }
            })
            .onDisappear {
                focus.entries[id] = nil
                if focus.current == id { focus.current = nil }
            }
            .overlay(
                RoundedRectangle(cornerRadius: radius + 4, style: .continuous)
                    .stroke(palette.foreground, lineWidth: 2)
                    .padding(-4)
                    .opacity(focus.current == id ? 1 : 0)
                    .allowsHitTesting(false)
            )
    }
}

private struct KeyboardNavigation: ViewModifier {
    static let space = "keyboard-navigation"
    @ObservedObject var focus: KeyboardFocus
    @FocusState private var windowFocused: Bool

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: Self.space)
            .environmentObject(focus)
            .focusable()
            .focusEffectDisabled()
            .focused($windowFocused)
            .onAppear { windowFocused = true }
            .onKeyPress(keys: [.tab], phases: .down) { press in
                focus.move(by: press.modifiers.contains(.shift) ? -1 : 1)
                return .handled
            }
            .onKeyPress(keys: [.space, .return]) { _ in focus.activate() ? .handled : .ignored }
            .onKeyPress(.escape) {
                focus.current = nil
                return .handled
            }
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

    var body: some View {
        HStack {
            configuration.label
            Spacer()
            Button(action: toggle) {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    // Sunken trough; a brighter purple when on.
                    Capsule()
                        .fill((configuration.isOn ? palette.onTrack : palette.offTrack)
                            .shadow(.inner(color: .black.opacity(0.45), radius: 4, x: 3, y: 3))
                            .shadow(.inner(color: palette.highlight, radius: 1.5, x: -1, y: -1)))
                        .frame(width: 46, height: 26)
                    // Raised purple knob with a pronounced light top-left rim and dark bottom-right edge.
                    Circle()
                        .fill(LinearGradient(colors: [palette.surfaceTop, palette.surfaceBottom],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(Circle().strokeBorder(
                            LinearGradient(colors: [Color.white.opacity(0.6), .clear, Color.black.opacity(0.6)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1.6))
                        .shadow(color: .black.opacity(0.6), radius: 2.5, x: 1.5, y: 2)
                        .frame(width: 20, height: 20)
                        .padding(3)
                }
            }
            .buttonStyle(.plain)
            .keyboardFocusable(palette, radius: 13, action: toggle)
            .opacity(enabled ? 1 : 0.4)
        }
        // VoiceOver sees a native switch with the row's label and on/off value.
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }

    private func toggle() {
        guard enabled else { return }
        withAnimation(.snappy(duration: 0.18)) { configuration.isOn.toggle() }
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
        .keyboardFocusable(palette, radius: 4) { NSWorkspace.shared.open(url) }
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

/// Makes the view it backs a handle for moving the window (the window itself isn't draggable by its
/// background, so only the header moves it).
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
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
        .keyboardFocusable(palette, radius: 13, action: action)
        .help(help)
        .accessibilityLabel(help)
    }
}
