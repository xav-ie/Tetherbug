import CoreBluetooth
import Foundation

/// The phone's GATT service (see README "BLE protocol").
enum Gatt {
    static let service = CBUUID(string: "1581bac4-33fe-43a8-b97f-5dd7a01f48c9")
    static let status = CBUUID(string: "90766fca-8a24-43ae-8501-3dcef06a8479")
    static let command = CBUUID(string: "e036426f-6317-487d-8777-e6f6d91f8a4d")
    static let enable: UInt8 = 0x01
    static let disable: UInt8 = 0x02
}

/// What the phone reports in its status characteristic.
struct PhoneStatus: Codable, Equatable {
    enum Hotspot: String, Codable { case off, starting, on, failed }

    var hotspot: Hotspot
    var battery: Int
    var signal: Int
    var ssid: String

    /// `version u8, hotspot u8, battery u8, signal u8, ssid utf-8...`
    init?(_ data: Data) {
        let b = [UInt8](data)
        guard b.count >= 4, b[0] == 1 else { return nil }
        hotspot = [.off, .starting, .on, .failed][Int(min(b[1], 3))]
        battery = Int(b[2])
        signal = Int(b[3])
        ssid = String(decoding: b[4...], as: UTF8.self)
    }
}

/// Everything the agent knows, sent to the app and CLI over the local socket.
struct AgentState: Codable, Equatable {
    var bluetooth = "unknown"
    var phone: String?
    var connected = false
    var status: PhoneStatus?
    var wifiOffline = false
    var lastRequest: String?
}

/// Settings shared by the app, agent and CLI. An explicit domain keeps it the same however the
/// binary is launched (inside the bundle or through a symlink).
enum Settings {
    static let defaults = UserDefaults(suiteName: "ie.xav.tetherlink.settings") ?? .standard

    /// Ask for the hotspot when the Mac's Wi-Fi has no connection.
    static var onNoWifi: Bool {
        get { defaults.object(forKey: "onNoWifi") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "onNoWifi") }
    }

    /// Ask for the hotspot whenever the Wi-Fi menu opens. Off by default: every glance at the
    /// menu would wake the phone's hotspot.
    static var onWifiMenuOpen: Bool {
        get { defaults.object(forKey: "onWifiMenuOpen") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "onWifiMenuOpen") }
    }

    /// Turn the phone's hotspot back off once the Mac is on a regular (non-metered) network.
    static var disableWhenBack: Bool {
        get { defaults.object(forKey: "disableWhenBack") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "disableWhenBack") }
    }
}

/// The agent's local socket, used by the app and the CLI.
enum Socket {
    static var path: String {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TetherLink")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("agent.sock").path
    }
}
