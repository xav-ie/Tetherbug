import AppKit
import ServiceManagement
import SwiftUI

/// The mascot, drawn from the outline design/icon.py generates: space-separated `Mx,y`, `Lx,y` and `Z` tokens.
struct Buddy: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let side = min(rect.width, rect.height * buddyAspect)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        for token in buddyPathData.split(separator: " ") {
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
    static let sketchybar = URL(string: "https://github.com/xav-ie/TetherLink/blob/main/docs/sketchybar.md")!
    static let releases = URL(string: "https://github.com/xav-ie/TetherLink/releases")!
}

struct ContentView: View {
    @ObservedObject var model: AgentModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette.current(scheme)
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TetherLink").font(.custom("Palatino", size: 34).weight(.semibold))
                    Text("Instant Hotspot for your Mac").opacity(0.75)
                }
                Spacer()
                Buddy().fill(palette.foreground, style: FillStyle(eoFill: true)).frame(width: 96, height: 60)
            }

            Card(palette: palette) { status(palette) }

            HStack(spacing: 12) {
                Button("Turn hotspot on") { model.send("enable") }
                    .buttonStyle(BubbleButtonStyle(palette: palette, primary: true))
                    .keyboardShortcut(.defaultAction)
                Button("Turn hotspot off") { model.send("disable") }
                    .buttonStyle(BubbleButtonStyle(palette: palette))
            }
            .disabled(!(model.state?.connected ?? false))

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
                Link("Add TetherLink to SketchyBar →", destination: Links.sketchybar).foregroundStyle(palette.alt)
            }

            HStack(spacing: 16) {
                Group {
                    Link("Setup guide", destination: Links.setup)
                    Link("Get the phone app", destination: Links.releases)
                    Link("GitHub", destination: Links.repo)
                }
                .foregroundStyle(palette.alt)
                Spacer()
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                    .opacity(0.6)
            }
            .font(.callout)
        }
        .padding(.horizontal, 28)
        .padding(.top, 44)
        .padding(.bottom, 26)
        .frame(width: 500)
        .foregroundStyle(palette.foreground)
        .tint(palette.alt)
        .toggleStyle(.switch)
        .background(palette.background.overlay(Image(nsImage: noise).resizable(resizingMode: .tile)).ignoresSafeArea())
        .overlay(alignment: .topTrailing) { WindowControls(palette: palette).padding(14) }
    }

    @ViewBuilder private func status(_ palette: Palette) -> some View {
        if let state = model.state {
            if state.connected, let phone = state.status {
                Label("\(state.phone ?? "Phone") is connected", systemImage: "iphone.radiowaves.left.and.right")
                    .font(.headline)
                Text("Hotspot \(phone.hotspot.rawValue)\(phone.ssid.isEmpty ? "" : " · \(phone.ssid)")")
                Text("Battery \(phone.battery)% · Signal \(phone.signal)/4").opacity(0.7)
            } else if state.bluetooth != "on" {
                Label("Bluetooth is \(state.bluetooth)", systemImage: "exclamationmark.triangle")
            } else {
                Label("Looking for your phone…", systemImage: "antenna.radiowaves.left.and.right")
                Text("Make sure TetherLink is running on your phone and it's paired with this Mac.")
                    .font(.caption).opacity(0.7)
                Link("How to pair", destination: Links.pairing).font(.caption).foregroundStyle(palette.alt)
            }
        } else {
            Label("The background agent isn't running", systemImage: "moon.zzz")
            Text("Turn on “Run in the background” below to start it.").font(.caption).opacity(0.7)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let model = AgentModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Content fills the whole window; the themed view draws its own close/minimise controls.
        window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "TetherLink"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        NSApp.mainMenu = mainMenu()
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.setContentSize(window.contentView!.fittingSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
