import Foundation
import Network

final class IRCClient: @unchecked Sendable {
    let config: IRCConnectionConfig
    var onEvent: ((IRCEvent) -> Void)?

    private var connection: NWConnection?
    private var state: ClientState = .disconnected
    private let queue = DispatchQueue(label: "irc.client.\(UUID().uuidString.prefix(8))")
    private var readBuffer: String = ""
    private var nickRetryCount = 0
    private var shouldReconnect = false

    enum ClientState {
        case disconnected
        case connecting
        case registering
        case online
    }

    init(config: IRCConnectionConfig) {
        self.config = config
    }

    // MARK: - Public API

    func connect() {
        guard case .disconnected = state else { return }
        nickRetryCount = 0
        shouldReconnect = true
        connectSocket()
    }

    func disconnect() {
        shouldReconnect = false
        sendRaw("QUIT :Wirc")
        connection?.cancel()
        connection = nil
        state = .disconnected
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(.disconnected(reason: nil))
        }
    }

    func join(channel: String) {
        let ch = channel.hasPrefix("#") || channel.hasPrefix("&") ? channel : "#\(channel)"
        sendRaw("JOIN \(ch)")
    }

    func part(channel: String, reason: String? = nil) {
        if let reason {
            sendRaw("PART \(channel) :\(reason)")
        } else {
            sendRaw("PART \(channel)")
        }
    }

    func sendMessage(_ text: String, to target: String) {
        // Split long messages
        let maxLen = 400
        var remaining = text
        while !remaining.isEmpty {
            let chunk = String(remaining.prefix(maxLen))
            sendRaw("PRIVMSG \(target) :\(chunk)")
            if remaining.count > maxLen {
                remaining = String(remaining.dropFirst(maxLen))
            } else {
                remaining = ""
            }
        }
    }

    func sendCTCPReply(nick: String, command: String, response: String) {
        sendRaw("NOTICE \(nick) :\u{01}\(command) \(response)\u{01}")
    }

    func setTopic(channel: String, topic: String) {
        sendRaw("TOPIC \(channel) :\(topic)")
    }

    func whois(nick: String) {
        sendRaw("WHOIS \(nick)")
    }

    func kick(channel: String, nick: String, reason: String? = nil) {
        if let reason {
            sendRaw("KICK \(channel) \(nick) :\(reason)")
        } else {
            sendRaw("KICK \(channel) \(nick)")
        }
    }

    // MARK: - Private: Connection

    private func connectSocket() {
        state = .connecting

        let host = NWEndpoint.Host(config.host)
        let port = NWEndpoint.Port(integerLiteral: UInt16(config.port))
        let params: NWParameters = config.useTLS ? .tls : .tcp
        params.allowLocalEndpointReuse = true

        connection = NWConnection(host: host, port: port, using: params)
        connection?.stateUpdateHandler = { [weak self] nwState in
            DispatchQueue.main.async { self?.handleState(nwState) }
        }
        connection?.start(queue: queue)
    }

    private func handleState(_ nwState: NWConnection.State) {
        switch nwState {
        case .ready:
            state = .registering
            onEvent?(.connected)
            register()
            startReading()

        case .failed(let error):
            state = .disconnected
            onEvent?(.error("Connection failed: \(error.localizedDescription)"))
            onEvent?(.disconnected(reason: error.localizedDescription))
            tryReconnect()

        case .cancelled:
            state = .disconnected

        default:
            break
        }
    }

    private func tryReconnect() {
        guard shouldReconnect else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.shouldReconnect, case .disconnected = self.state else { return }
            self.connectSocket()
        }
    }

    // MARK: - Private: Registration

    private func register() {
        if let pass = config.password, !pass.isEmpty {
            sendRaw("PASS \(pass)")
        }
        let nickname = nickRetryCount > 0 ? "\(config.nickname)\(nickRetryCount)" : config.nickname
        let username = config.username ?? nickname
        let realName = config.realName ?? nickname
        sendRaw("NICK \(nickname)")
        sendRaw("USER \(username) 0 * :\(realName)")
    }

    // MARK: - Private: Reading

    private func startReading() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            guard let self = self else { return }

            if let error = error {
                if self.shouldReconnect {
                    DispatchQueue.main.async {
                        self.onEvent?(.error("Read error: \(error.localizedDescription)"))
                        self.onEvent?(.disconnected(reason: error.localizedDescription))
                    }
                    self.state = .disconnected
                    self.tryReconnect()
                }
                return
            }

            if let data = data, let text = String(data: data, encoding: .utf8) {
                self.readBuffer.append(text)
                self.processBuffer()
            }

            if self.state != .disconnected {
                self.startReading()
            }
        }
    }

    private func processBuffer() {
        while let crlfRange = readBuffer.range(of: "\r\n") {
            let line = String(readBuffer[..<crlfRange.lowerBound])
            readBuffer = String(readBuffer[crlfRange.upperBound...])
            guard !line.isEmpty else { continue }

            // Handle PING
            if line.hasPrefix("PING") {
                let token = line
                    .replacingOccurrences(of: "PING :", with: "")
                    .replacingOccurrences(of: "PING ", with: "")
                sendRaw("PONG :\(token)")
                DispatchQueue.main.async { [weak self] in
                    self?.onEvent?(.rawLine(line))
                }
                continue
            }

            // Detect registration
            if line.contains(" 001 ") {
                if case .registering = state {
                    state = .online
                    nickRetryCount = 0
                    for channel in config.autoJoinChannels {
                        join(channel: channel)
                    }
                }
            }

            // Handle nick in use -> retry
            if line.contains(" 433 ") {
                nickRetryCount += 1
                if nickRetryCount <= 5 {
                    let tryNick = "\(config.nickname)\(nickRetryCount)"
                    sendRaw("NICK \(tryNick)")
                }
            }

            // Process the line
            var event = IRCParser.parse(rawLine: line, server: config.host)

            // Route CTCP responses
            if case .ctcpQuery(let nick, let command, let arg) = event {
                handleCTCP(nick: nick, command: command, argument: arg)
                // Also pass through as raw for debug
                event = .rawLine(line)
            }

            DispatchQueue.main.async { [weak self] in
                self?.onEvent?(event)
            }
        }
    }

    private func handleCTCP(nick: String, command: String, argument: String?) {
        switch command.uppercased() {
        case "VERSION":
            sendCTCPReply(nick: nick, command: "VERSION", response: "Wirc IRC Client (iOS)")
        case "PING":
            let ts = argument.map { " \($0)" } ?? ""
            sendCTCPReply(nick: nick, command: "PING", response: "\(UInt64(Date().timeIntervalSince1970 * 1000))\(ts)")
        case "TIME":
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm:ss"
            sendCTCPReply(nick: nick, command: "TIME", response: df.string(from: Date()))
        case "SOURCE":
            sendCTCPReply(nick: nick, command: "SOURCE", response: "https://github.com/wirc")
        case "CLIENTINFO":
            sendCTCPReply(nick: nick, command: "CLIENTINFO", response: "PING VERSION TIME SOURCE CLIENTINFO")
        default:
            break // Ignore unknown CTCP
        }
    }

    private func sendRaw(_ command: String) {
        let line = command + "\r\n"
        guard let data = line.data(using: .utf8), let conn = connection else { return }
        conn.send(content: data, completion: .contentProcessed({ _ in }))
    }
}
