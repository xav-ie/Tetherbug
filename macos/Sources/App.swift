import AppKit
import CoreBluetooth
import ServiceManagement
import SwiftUI

/// A filled shape from flattened path data (design/icon.py): space-separated `Mx,y`, `Lx,y` and `Z`
/// tokens in a unit square, drawn even-odd and fitted to the rect at the given aspect ratio.
struct PathShape: Shape {
    let data: String
    var aspect: Double = 1

    static let buddy = PathShape(data: buddyPathData, aspect: buddyAspect)
    static let github = PathShape(data: githubPathData)

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let side = min(rect.width, rect.height * aspect)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        for token in data.split(separator: " ") {
            let command = token.first!
            if command == "Z" { path.closeSubpath(); continue }
            let xy = token.dropFirst().split(separator: ",").compactMap { Double($0) }
            let point = CGPoint(x: origin.x + xy[0] * side, y: origin.y + xy[1] * side)
            command == "M" ? path.move(to: point) : path.addLine(to: point)
        }
        return path
    }
}

/// Streams the agent's state; nil while the agent isn't running.
final class AgentModel: ObservableObject {
    @Published var state: AgentState?
    @Published var onNoWifi = Settings.onNoWifi { didSet { Settings.onNoWifi = onNoWifi } }
    @Published var disableWhenBack = Settings.disableWhenBack { didSet { Settings.disableWhenBack = disableWhenBack } }
    @Published var loginItem = SMAppService.agent(plistName: "ie.xav.tetherlink.agent.plist").status

    private let agent = SMAppService.agent(plistName: "ie.xav.tetherlink.agent.plist")

    init() {
        Thread.detachNewThread { [weak self] in
            while self != nil {
                // `watch` streams until the agent goes away; then retry, so the window follows restarts.
                let connected = SocketClient.request("watch") { state in
                    DispatchQueue.main.async { self?.state = state }
                    return true
                }
                if !connected { DispatchQueue.main.async { self?.state = nil } }
                Thread.sleep(forTimeInterval: 1)
            }
        }
    }

    /// The hotspot password, fetched on demand from the agent (it isn't in the status stream).
    @Published var password: String?

    func fetchPassword() {
        DispatchQueue.global().async {
            SocketClient.request("password") { state in
                DispatchQueue.main.async { self.password = state.password }
                return false
            }
        }
    }

    func send(_ command: String) {
        DispatchQueue.global().async { SocketClient.request(command) { _ in false } }
    }

    func setLoginItem(_ on: Bool) {
        do {
            if on { try agent.register() } else { try agent.unregister() }
        } catch {
            log("login item: \(error.localizedDescription)")
        }
        loginItem = agent.status
        // macOS asks the user to allow new background items in System Settings first.
        if loginItem == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }
}

enum Links {
    static let repo = URL(string: "https://github.com/xav-ie/TetherLink")!
    static let setup = URL(string: "https://github.com/xav-ie/TetherLink/blob/main/docs/macos.md")!
    static let pairing = URL(string: "https://github.com/xav-ie/TetherLink/blob/main/docs/macos.md#2-pair-the-phone-with-your-mac")!
    static let bluetoothSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")!
    static let sketchybar = URL(string: "https://github.com/xav-ie/TetherLink/blob/main/docs/sketchybar.md")!
    static let releases = URL(string: "https://github.com/xav-ie/TetherLink/releases")!
}

struct ContentView: View {
    @ObservedObject var model: AgentModel
    @Environment(\.colorScheme) private var scheme
    @StateObject private var keyboard = KeyboardFocus()

    var body: some View {
        let palette = Palette.current(scheme)
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TetherLink").font(.custom("Palatino", size: 34).weight(.semibold))
                    Text("Instant Hotspot for your Mac").opacity(0.75)
                }
                Spacer()
                PathShape.buddy.fill(palette.foreground, style: FillStyle(eoFill: true)).frame(width: 96, height: 60)
                    .accessibilityHidden(true)
                WindowControls(palette: palette)
            }
            // The header (and the band above it) is the window's drag handle.
            .padding(.top, 22)
            .background(WindowDragArea().padding(.horizontal, -18))

            Card(palette: palette, label: "Status") { status(palette) }

            Card(palette: palette, title: "Settings") {
                Toggle("Ask for the hotspot when Wi-Fi drops", isOn: $model.onNoWifi)
                Toggle("Turn it off when back on regular Wi-Fi", isOn: $model.disableWhenBack)
                Toggle("Run in the background", isOn: Binding(
                    get: { model.loginItem == .enabled },
                    set: { model.setLoginItem($0) }
                ))
                Text("Starts at login and keeps working when this window is closed.").font(.caption).opacity(0.7)
                if model.loginItem == .requiresApproval {
                    Text("Allow TetherLink under System Settings → General → Login Items.").font(.caption).opacity(0.7)
                }
            }

            Card(palette: palette, title: "Using SketchyBar?") {
                Text("Show your phone's hotspot state and battery in the bar, and turn the hotspot on with a click.")
                    .opacity(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                SiteLink("Add TetherLink to SketchyBar →", url: Links.sketchybar, palette: palette)
            }

            HStack(spacing: 16) {
                SiteLink(title: "Setup guide", url: Links.setup, palette: palette) { Image(systemName: "book.closed") }
                SiteLink(title: "Phone app", url: Links.releases, palette: palette) { Image(systemName: "smartphone") }
                SiteLink(title: "GitHub", url: Links.repo, palette: palette) {
                    PathShape.github.fill(style: FillStyle(eoFill: true)).frame(width: 13, height: 13)
                }
                Spacer()
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                    .opacity(0.6)
            }
            .font(.callout)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Links")
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 26)
        .frame(width: 500)
        .foregroundStyle(palette.foreground)
        .tint(palette.alt)
        .toggleStyle(TrailingSwitchStyle(palette: palette))
        .background(WindowSurface(palette: palette))
        .clipShape(RoundedRectangle(cornerRadius: WindowSurface.radius, style: .continuous))
        .keyboardNavigation(keyboard)
    }

    @ViewBuilder private func status(_ palette: Palette) -> some View {
        let state = model.state
        let phone = state?.connected == true ? state?.status : nil
        if let state {
            if state.connected {
                Label("\(state.phone ?? "Phone") is connected", systemImage: "iphone.radiowaves.left.and.right").font(.headline)
            } else if state.bluetooth != "on" {
                Label("Bluetooth is \(state.bluetooth)", systemImage: "exclamationmark.triangle").font(.headline)
                if state.bluetooth == "unauthorized" {
                    Text("Allow TetherLink under Privacy & Security → Bluetooth.").font(.caption).opacity(0.7)
                    SiteLink("Open Bluetooth settings →", url: Links.bluetoothSettings, palette: palette)
                }
            } else {
                Label("Looking for your phone…", systemImage: "antenna.radiowaves.left.and.right").font(.headline)
            }
        } else {
            Label("The background agent isn't running", systemImage: "moon.zzz").font(.headline)
        }

        // Unknown (knob centred, disabled) until the phone reports a state it can change; starting
        // is in-between too. Failed counts as off so it can be retried.
        HotspotSwitch(
            isOn: phone.flatMap { $0.hotspot == .on ? true : ($0.hotspot == .off || $0.hotspot == .failed) ? false : nil },
            enabled: phone?.controllable == true && phone?.hotspot != .starting,
            palette: palette
        ) { model.send($0 ? "enable" : "disable") }

        if let phone {
            if phone.hotspot == .failed {
                Text("The phone couldn't switch its hotspot. Try again, or check TetherLink on the phone.").font(.caption).opacity(0.7)
            }
            if !phone.controllable {
                Text("Shizuku isn't ready on your phone, so it can't switch the hotspot. Open TetherLink there.")
                    .font(.caption).opacity(0.7)
            }
            if !phone.ssid.isEmpty {
                HStack {
                    Text("Network")
                    Spacer()
                    Text(phone.ssid).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Network")
                .accessibilityValue(phone.ssid)
                .accessibilityAddTraits(.isStaticText)
            }
            PasswordRow(model: model, palette: palette)
            // The phone's own cellular signal to its carrier, which limits the hotspot's speed.
            Text("Cell signal \(phone.signal)/4").font(.caption).opacity(0.7)
        } else if state == nil {
            Text("Turn on “Run in the background” below to start it.").font(.caption).opacity(0.7)
        } else if state?.connected != true, state?.bluetooth == "on" {
            Text("Make sure TetherLink is running on your phone and it's paired with this Mac.").font(.caption).opacity(0.7)
            SiteLink("How to pair", url: Links.pairing, palette: palette).font(.caption)
        }
    }
}

/// The hotspot password, hidden until asked for; Copy puts it on the clipboard.
struct PasswordRow: View {
    @ObservedObject var model: AgentModel
    let palette: Palette
    @State private var shown = false
    /// Bumped on every copy; the label says "Copied!" until 5s after the latest one.
    @State private var copies = 0
    @State private var copied = false

    private func toggleShown() {
        if !shown { model.fetchPassword() }
        shown.toggle()
    }

    private func copy() {
        model.fetchPassword()
        // Copy once the agent has replied.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let password = model.password else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(password, forType: .string)
            copies += 1
            copied = true
            let copy = copies
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { if copies == copy { copied = false } }
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("Password")
            Spacer()
            Text(shown ? (model.password ?? "…") : "••••••••").font(.system(.body, design: .monospaced)).textSelection(.enabled)
                .accessibilityLabel(shown ? (model.password ?? "loading") : "hidden")
            Button(shown ? "Hide" : "Show", action: toggleShown)
                .buttonStyle(TextButtonStyle(palette: palette))
                .keyboardFocusable(palette, radius: 4, action: toggleShown)
            Button(copied ? "Copied!" : "Copy", action: copy)
                .buttonStyle(TextButtonStyle(palette: palette))
                .keyboardFocusable(palette, radius: 4, action: copy)
        }
    }
}

/// A borderless window that can still take keyboard focus and close from ⌘W / the close control.
final class AppWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func performClose(_ sender: Any?) { close() }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let model = AgentModel()
    private var bluetooth: CBCentralManager?

    /// macOS never shows the windowless agent the Bluetooth prompt, so ask from the window: the agent
    /// is the same app and shares the grant. Only an active app may prompt.
    func applicationDidBecomeActive(_ notification: Notification) {
        if bluetooth == nil, CBManager.authorization == .notDetermined { bluetooth = CBCentralManager(delegate: nil, queue: nil) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Content fills the whole window; the themed view draws its own close/minimise controls.
        // Borderless and transparent: the content draws the rounded, bevelled window body itself, and
        // the system shadow follows that shape.
        window = AppWindow(contentRect: .zero, styleMask: [.borderless, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "TetherLink"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        NSApp.mainMenu = mainMenu()
        let hosting = NSHostingView(rootView: ContentView(model: model))
        hosting.safeAreaRegions = []
        window.contentView = hosting
        window.setContentSize(window.contentView!.fittingSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // The shadow is computed from the window's alpha, so redo it once the rounded body is drawn.
        DispatchQueue.main.async { self.window.invalidateShadow() }
    }

    /// Keeps ⌘W, ⌘M and ⌘Q working without the standard window buttons.
    private func mainMenu() -> NSMenu {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu!.addItem(withTitle: "Quit TetherLink", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let windowItem = NSMenuItem()
        windowItem.submenu = NSMenu(title: "Window")
        windowItem.submenu!.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu!.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        menu.addItem(appItem)
        menu.addItem(windowItem)
        return menu
    }

    // Closing the window quits the app; the background agent keeps running on its own.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

func runApp() -> Never {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
    exit(0)
}
