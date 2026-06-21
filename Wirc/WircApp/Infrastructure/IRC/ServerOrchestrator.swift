import Foundation
import Network

@Observable
@MainActor
final class ServerOrchestrator: @unchecked Sendable {
    private(set) var globalChannels: [GlobalChannel] = []
    private(set) var isScanning = false
    private(set) var scanProgress: String = ""
    private var scannedCount = 0
    private var totalServers = 0

    struct GlobalChannel: Identifiable, Hashable {
        var id: String { "\(serverHost)|\(name)" }
        let name: String
        let users: Int
        let topic: String
        let serverHost: String
        let serverName: String
        let serverPort: Int
        let serverUseTLS: Bool
        let serverId: UUID
    }

    private let servers: [SuggestedServer]
    private let nicknameBase: String
    private var activeClients: [(server: SuggestedServer, client: IRCClient, configId: UUID)] = []
    private let maxConcurrent = 8
    private var pendingServers: [SuggestedServer] = []
    private let scanQueue = DispatchQueue(label: "orchestrator.scan")

    init(servers: [SuggestedServer], nickname: String = "virc_guest") {
        self.servers = servers
        self.nicknameBase = nickname
    }

    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        scannedCount = 0
        totalServers = servers.count
        globalChannels = []
        pendingServers = Array(servers.shuffled()) // randomize to spread load
        activeClients = []

        // Start initial batch
        for _ in 0..<min(maxConcurrent, pendingServers.count) {
            connectNext()
        }
    }

    func stopScan() {
        isScanning = false
        pendingServers = []
        for (_, client, _) in activeClients {
            client.disconnect()
        }
        activeClients = []
        updateProgress()
    }

    // MARK: - Private

    private func connectNext() {
        guard !pendingServers.isEmpty else {
            if activeClients.isEmpty {
                isScanning = false
                updateProgress()
            }
            return
        }

        let server = pendingServers.removeFirst()
        let configId = UUID()

        let config = IRCConnectionConfig(
            id: configId,
            name: server.name,
            host: server.host,
            port: server.port,
            useTLS: server.useTLS,
            nickname: "\(nicknameBase)_\(Int.random(in: 1000...9999))",
            autoJoinChannels: []
        )

        let client = IRCClient(config: config)
        let entry = (server: server, client: client, configId: configId)
        activeClients.append(entry)

        var didReceiveList = false

        client.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .connected:
                // Connected — LIST will be triggered automatically
                // But we trigger it manually here
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    client.listChannels()
                }
            case .listItem(let channel, let users, let topic):
                didReceiveList = true
                let gc = GlobalChannel(
                    name: channel,
                    users: users,
                    topic: topic,
                    serverHost: server.host,
                    serverName: server.name,
                    serverPort: server.port,
                    serverUseTLS: server.useTLS,
                    serverId: configId
                )
                DispatchQueue.main.async { [weak self] in
                    self?.addChannel(gc)
                }
            case .listEnd:
                finishServer(configId)
            case .error(let msg):
                // If we got list items already, finish. Otherwise mark as failed.
                if didReceiveList {
                    finishServer(configId)
                } else {
                    // Give it a few more seconds then bail
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                        self?.finishServer(configId)
                    }
                }
            case .disconnected:
                finishServer(configId)
            default:
                break
            }
        }

        client.connect()

        // Timeout after 25s
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            guard let self else { return }
            if self.activeClients.contains(where: { $0.configId == configId }) {
                self.finishServer(configId)
            }
        }
    }

    private func addChannel(_ gc: GlobalChannel) {
        // Binary-search insertion maintaining sort by users descending
        var lo = 0, hi = globalChannels.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if globalChannels[mid].users >= gc.users {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        globalChannels.insert(gc, at: lo)
        // Keep max 5000 channels for memory
        if globalChannels.count > 5000 {
            globalChannels = Array(globalChannels.prefix(5000))
        }
        updateProgress()
    }

    private func finishServer(_ configId: UUID) {
        // Disconnect the client before removing
        if let entry = activeClients.first(where: { $0.configId == configId }) {
            entry.client.disconnect()
        }
        activeClients.removeAll { $0.configId == configId }
        scannedCount += 1
        updateProgress()

        // Connect next if pending
        if isScanning {
            connectNext()
        }
    }

    private func updateProgress() {
        let active = activeClients.count
        if isScanning {
            scanProgress = "\(scannedCount)/\(totalServers) servers · \(active) active · \(globalChannels.count) channels"
        } else {
            scanProgress = "\(globalChannels.count) channels from \(scannedCount)/\(totalServers) servers"
        }
    }
}
