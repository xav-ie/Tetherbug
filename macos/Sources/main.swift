import Foundation

let usage = """
    usage: tether-link [command]

      (none)     open the TetherLink window
      agent      run the background agent (started as a login item by the app)
      status     print the phone and hotspot state (--json for machine output)
      enable     ask the phone to turn its hotspot on
      disable    ask the phone to turn its hotspot off
      watch      print the state every time it changes (one JSON line each)
    """

func describe(_ s: AgentState) -> String {
    guard s.connected, let status = s.status else {
        return s.bluetooth == "on" ? "phone not connected" : "Bluetooth \(s.bluetooth)"
    }
    let ssid = status.ssid.isEmpty ? "" : " (\(status.ssid))"
    return "\(s.phone ?? "phone"): hotspot \(status.hotspot.rawValue)\(ssid), battery \(status.battery)%, signal \(status.signal)/4"
}

func cli(_ command: String, json: Bool) -> Never {
    let ok = SocketClient.request(command) { state in
        if json || command == "watch" {
            print(String(decoding: try! JSONEncoder().encode(state), as: UTF8.self))
            fflush(stdout)
        } else {
            print(describe(state))
        }
        return command == "watch"
    }
    if !ok {
        FileHandle.standardError.write("tether-link: the agent isn't running (open TetherLink to start it)\n".data(using: .utf8)!)
        exit(1)
    }
    exit(0)
}

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "agent":
    Agent().run()
case "status", "enable", "disable", "watch":
    cli(args.first!, json: args.contains("--json"))
case "-h", "--help", "help":
    print(usage)
case nil:
    print(usage) // the app window comes next
default:
    FileHandle.standardError.write("\(usage)\n".data(using: .utf8)!)
    exit(2)
}
