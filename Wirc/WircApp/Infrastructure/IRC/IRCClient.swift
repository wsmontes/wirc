import Foundation
import Network

// MARK: - Console Entry

struct ConsoleEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let direction: Direction
    let text: String
    let tag: Int
    enum Direction { case sent, received }
}

// MARK: - IRC Client

final class IRCClient: @unchecked Sendable {
    let config: IRCConnectionConfig
    var onEvent: ((IRCEvent) -> Void)?
    var onConsole: ((ConsoleEntry) -> Void)?

    private var connection: NWConnection?
    private var state: ClientState = .disconnected
    private let queue = DispatchQueue(label: "irc.\(UUID().uuidString.prefix(6))")
    private var readBuffer = ""
    private var nickRetry = 0
    private var shouldReconnect = false
    private var writeTag = 0

    enum ClientState { case disconnected, connecting, registering, online }

    init(config: IRCConnectionConfig) { self.config = config }

    // MARK: - Public API

    func connect() {
        guard case .disconnected = state else { return }
        nickRetry = 0; shouldReconnect = true
        state = .connecting
        let host = NWEndpoint.Host(config.host)
        let port = NWEndpoint.Port(integerLiteral: UInt16(config.port))
        let params: NWParameters = config.useTLS ? .tls : .tcp
        params.allowLocalEndpointReuse = true
        connection = NWConnection(host: host, port: port, using: params)
        connection?.stateUpdateHandler = { [weak self] s in
            DispatchQueue.main.async { self?.handleNWState(s) }
        }
        connection?.start(queue: queue)
    }

    func disconnect() {
        shouldReconnect = false
        write("QUIT :Wirc", tag: 0)
        connection?.cancel()
        connection = nil; state = .disconnected
        emit(.disconnected(reason: nil))
    }

    func join(channel: String) {
        let ch = channel.hasPrefix("#") || channel.hasPrefix("&") ? channel : "#\(channel)"
        write("JOIN \(ch)", tag: 0)
    }

    func part(channel: String, reason: String? = nil) {
        if let r = reason { write("PART \(channel) :\(r)", tag: 0) }
        else { write("PART \(channel)", tag: 0) }
    }

    func sendMessage(_ text: String, to target: String) {
        write("PRIVMSG \(target) :\(text)", tag: 0)
    }

    func listChannels() {
        write("LIST", tag: 1)
    }

    func setTopic(channel: String, topic: String) {
        write("TOPIC \(channel) :\(topic)", tag: 0)
    }

    // MARK: - Private: Network State

    private func handleNWState(_ s: NWConnection.State) {
        switch s {
        case .ready:
            state = .registering; emit(.connected); register(); readLoop()
        case .failed(let e):
            state = .disconnected
            emit(.error("Connection failed: \(e.localizedDescription)"))
            emit(.disconnected(reason: e.localizedDescription))
            scheduleReconnect()
        case .cancelled: state = .disconnected
        default: break
        }
    }

    private func scheduleReconnect() {
        guard shouldReconnect else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.shouldReconnect, case .disconnected = self.state else { return }
            self.connect()
        }
    }

    // MARK: - Private: Registration

    private func register() {
        if let pass = config.password, !pass.isEmpty { write("PASS \(pass)", tag: 101) }
        let nick = nickRetry > 0 ? "\(config.nickname)\(nickRetry)" : config.nickname
        let user = config.username ?? nick
        let real = config.realName ?? nick
        write("NICK \(nick)", tag: 102)
        write("USER \(user) 0 * :\(real)", tag: 103)
    }

    // MARK: - Private: Write

    private func write(_ cmd: String, tag: Int) {
        writeTag += 1
        let line = cmd + "\r\n"
        guard let data = line.data(using: .utf8), let conn = connection else { return }
        conn.send(content: data, completion: .contentProcessed({ _ in }))
        let entry = ConsoleEntry(timestamp: Date(), direction: .sent, text: cmd, tag: tag)
        DispatchQueue.main.async { [weak self] in self?.onConsole?(entry) }
    }

    // MARK: - Private: Read Loop

    private func readLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, err in
            guard let self else { return }
            if let err {
                if self.shouldReconnect {
                    self.emit(.error("Read: \(err.localizedDescription)"))
                    self.emit(.disconnected(reason: err.localizedDescription))
                    self.state = .disconnected; self.scheduleReconnect()
                }
                return
            }
            if let data, let text = String(data: data, encoding: .utf8) {
                self.readBuffer.append(text); self.processLines()
            }
            if self.state != .disconnected { self.readLoop() }
        }
    }

    private func processLines() {
        while let r = readBuffer.range(of: "\r\n") {
            let line = String(readBuffer[..<r.lowerBound])
            readBuffer = String(readBuffer[r.upperBound...])
            guard !line.isEmpty else { continue }
            let entry = ConsoleEntry(timestamp: Date(), direction: .received, text: line, tag: 0)
            DispatchQueue.main.async { [weak self] in self?.onConsole?(entry) }

            if line.hasPrefix("PING") {
                let tok = line.replacingOccurrences(of: "PING :", with: "").replacingOccurrences(of: "PING ", with: "")
                write("PONG :\(tok)", tag: 0); emit(.rawLine(line)); continue
            }
            if line.contains(" 001 ") {
                if case .registering = state { state = .online; nickRetry = 0
                    for ch in config.autoJoinChannels { join(channel: ch) }
                }
            }
            if line.contains(" 433 ") { nickRetry += 1; if nickRetry <= 5 { write("NICK \(config.nickname)\(nickRetry)", tag: 0) } }
            var evt = IRCParser.parse(rawLine: line, server: config.host)
            if case .ctcpQuery(let n, let c, let a) = evt { handleCTCP(nick: n, cmd: c, arg: a); evt = .rawLine(line) }
            emit(evt)
        }
    }

    private func handleCTCP(nick: String, cmd: String, arg: String?) {
        switch cmd.uppercased() {
        case "VERSION": write("NOTICE \(nick) :\u{01}VERSION Wirc IRC Client (iOS)\u{01}", tag: 0)
        case "PING": write("NOTICE \(nick) :\u{01}PING \(arg ?? "")\u{01}", tag: 0)
        case "TIME": let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; write("NOTICE \(nick) :\u{01}TIME \(f.string(from: Date()))\u{01}", tag: 0)
        case "CLIENTINFO": write("NOTICE \(nick) :\u{01}CLIENTINFO PING VERSION TIME SOURCE CLIENTINFO\u{01}", tag: 0)
        case "SOURCE": write("NOTICE \(nick) :\u{01}SOURCE https://github.com/wirc\u{01}", tag: 0)
        default: break
        }
    }

    private func emit(_ e: IRCEvent) { DispatchQueue.main.async { [weak self] in self?.onEvent?(e) } }
}
