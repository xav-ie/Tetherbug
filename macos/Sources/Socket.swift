import Foundation

/// Line-based Unix socket: a client sends one request (`status`, `enable`, `disable`, `watch`) and
/// gets the agent's state back as one JSON line; `watch` keeps streaming a line per change.
final class SocketServer {
    private let listener: Int32
    private var source: DispatchSourceRead?
    private var clients: [Int32: DispatchSourceRead] = [:]
    private var watchers: Set<Int32> = []
    private let handle: (String) -> AgentState?

    init(path: String, handle: @escaping (String) -> AgentState?) {
        self.handle = handle
        unlink(path)
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un.make(path)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(listener, 8) == 0 else { fatalError("can't listen on \(path): \(String(cString: strerror(errno)))") }
        chmod(path, 0o600)
        source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: .main)
        source?.setEventHandler { [weak self] in self?.accept() }
        source?.resume()
    }

    private func accept() {
        let fd = Darwin.accept(listener, nil, nil)
        guard fd >= 0 else { return }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let reader = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        reader.setEventHandler { [weak self] in self?.read(fd) }
        reader.setCancelHandler { close(fd) }
        clients[fd] = reader
        reader.resume()
    }

    private func read(_ fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 256)
        let n = Darwin.read(fd, &buffer, buffer.count)
        guard n > 0 else { return drop(fd) }
        let request = String(decoding: buffer[..<n], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if request == "watch" { watchers.insert(fd) }
        if let state = handle(request) { send(state, to: fd) }
        if request != "watch" { drop(fd) }
    }

    func broadcast(_ state: AgentState) {
        for fd in watchers { send(state, to: fd) }
    }

    private func send(_ state: AgentState, to fd: Int32) {
        guard var data = try? JSONEncoder().encode(state) else { return }
        data.append(0x0A)
        let ok = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) } == data.count
        if !ok { drop(fd) }
    }

    private func drop(_ fd: Int32) {
        watchers.remove(fd)
        clients.removeValue(forKey: fd)?.cancel()
    }
}

/// Client side: send one request, then call `onState` for every JSON line the agent sends back.
enum SocketClient {
    @discardableResult
    static func request(_ line: String, onState: (AgentState) -> Bool) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_un.make(Socket.path)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { return false }
        _ = "\(line)\n".withCString { Darwin.write(fd, $0, strlen($0)) }
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = Darwin.read(fd, &buffer, buffer.count)
            guard n > 0 else { return true }
            pending.append(contentsOf: buffer[..<n])
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex..<newline]
                pending.removeSubrange(pending.startIndex...newline)
                if let state = try? JSONDecoder().decode(AgentState.self, from: line), !onState(state) { return true }
            }
        }
    }
}

private extension sockaddr_un {
    static func make(_ path: String) -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            let bytes = Array(path.utf8.prefix(raw.count - 1))
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return addr
    }
}
