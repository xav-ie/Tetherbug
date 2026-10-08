import CoreBluetooth
import CoreWLAN
import Foundation
import Network

/// Background agent: keeps the Bluetooth LE link to the phone, decides when to ask for the hotspot,
/// and serves its state over a local socket to the app and the CLI.
final class Agent: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var central: CBCentralManager!
    private var phone: CBPeripheral?
    private var command: CBCharacteristic?
    private var server: SocketServer!
    private let wifi = NWPathMonitor(requiredInterfaceType: .wifi)
    private var offlineSince: Date?
    private var wanted: Bool? // the hotspot state we last asked for
    private var backoff: TimeInterval = 2
    private var nextRetry = Date.distantPast
    private var state = AgentState() {
        didSet { if state != oldValue { server.broadcast(state) } }
    }

    func run() {
        server = SocketServer(path: Socket.path) { [weak self] line in self?.handle(line) }
        central = CBCentralManager(delegate: self, queue: .main)
        wifi.pathUpdateHandler = { [weak self] path in DispatchQueue.main.async { self?.wifiChanged(path) } }
        wifi.start(queue: .main)
        // Re-evaluate retries even when nothing else changes.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        log("agent started; socket at \(Socket.path)")
        RunLoop.main.run()
    }

    // MARK: Socket requests

    private func handle(_ line: String) -> AgentState? {
        switch line {
        case "enable": request(true, reason: "manual")
        case "disable": request(false, reason: "manual")
        default: break
        }
        return state
    }

    // MARK: Wi-Fi trigger

    private func wifiChanged(_ path: NWPath) {
        let poweredOn = CWWiFiClient.shared().interface()?.powerOn() ?? false
        let offline = poweredOn && path.status != .satisfied
        state.wifiOffline = offline
        if offline {
            if offlineSince == nil {
                offlineSince = Date()
                backoff = 2
                // Give macOS's own auto-join (which bursts on wake) a head start.
                nextRetry = Date().addingTimeInterval(5)
            }
        } else {
            offlineSince = nil
            // Back on a regular network: the phone's hotspot is no longer needed.
            if path.status == .satisfied, !path.isExpensive, Settings.disableWhenBack, wanted == true {
                request(false, reason: "back on Wi-Fi")
            }
        }
        tick()
    }

    private func tick() {
        guard Settings.onNoWifi, offlineSince != nil, Date() >= nextRetry else { return }
        let hotspot = state.status?.hotspot
        guard hotspot != .on, hotspot != .starting else { return }
        request(true, reason: "no Wi-Fi")
        nextRetry = Date().addingTimeInterval(backoff)
        backoff = min(backoff * 2, 30)
    }

    func request(_ on: Bool, reason: String) {
        wanted = on
        state.lastRequest = "\(on ? "enable" : "disable") (\(reason)) at \(ISO8601DateFormatter().string(from: Date()))"
        guard let phone, let command else {
            log("\(on ? "enable" : "disable") requested (\(reason)) but the phone isn't connected")
            return
        }
        log("\(on ? "enable" : "disable") (\(reason))")
        phone.writeValue(Data([on ? Gatt.enable : Gatt.disable]), for: command, type: .withResponse)
    }

    // MARK: Bluetooth

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state.bluetooth = ["unknown", "resetting", "unsupported", "unauthorized", "off", "on"][min(central.state.rawValue, 5)]
        guard central.state == .poweredOn else {
            state.connected = false
            return
        }
        // A bonded phone may already be connected at the system level; otherwise scan for it.
        if let known = central.retrieveConnectedPeripherals(withServices: [Gatt.service]).first {
            connect(known)
        } else {
            central.scanForPeripherals(withServices: [Gatt.service])
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        central.stopScan()
        connect(peripheral)
    }

    private func connect(_ peripheral: CBPeripheral) {
        phone = peripheral
        peripheral.delegate = self
        state.phone = peripheral.name
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("connected to \(peripheral.name ?? "phone")")
        state.connected = true
        peripheral.discoverServices([Gatt.service])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log("disconnected: \(error?.localizedDescription ?? "no error")")
        state.connected = false
        command = nil
        // A pending connect has no timeout: the link comes back as soon as the phone is in range.
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("connect failed: \(error?.localizedDescription ?? "unknown")")
        central.connect(peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Gatt.service }) else { return }
        peripheral.discoverCharacteristics([Gatt.status, Gatt.command], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case Gatt.status:
                peripheral.readValue(for: characteristic)
                peripheral.setNotifyValue(true, for: characteristic)
            case Gatt.command:
                command = characteristic
            default: break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { return log("status read failed: \(error.localizedDescription)") }
        guard characteristic.uuid == Gatt.status, let value = characteristic.value, let status = PhoneStatus(value) else { return }
        state.status = status
        tick()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { log("command failed: \(error.localizedDescription)") }
    }
}

func log(_ message: String) {
    FileHandle.standardError.write("\(ISO8601DateFormatter().string(from: Date())) \(message)\n".data(using: .utf8)!)
}
