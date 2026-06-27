import XCTest
@testable import Wirc

@MainActor
final class IRCChannelManagerTests: XCTestCase {
    var manager: IRCChannelManager!
    var store: JSONFileStore!

    override func setUp() async throws {
        store = JSONFileStore()
        manager = IRCChannelManager(store: store)
    }

    func testAllModeWhenActiveChannelNil() {
        XCTAssertTrue(manager.isAllMode)
        manager.setActiveChannel(nil)
        XCTAssertTrue(manager.isAllMode)
    }

    func testLoadMessagesFiltersByChannel() {
        let msg1 = makeMsg(server: "irc.example.com", channel: "#general", text: "hello")
        let msg2 = makeMsg(server: "irc.example.com", channel: "#random", text: "world")
        manager.allObjects = [msg1, msg2]

        let ch = ChannelHandle(serverId: UUID(), serverHost: "irc.example.com", name: "#general", userCount: 0)
        manager.setActiveChannel(ch)

        XCTAssertEqual(manager.visibleMessages.count, 1)
        XCTAssertEqual(manager.visibleMessages[0].content?.text, "hello")
    }

    func testLoadMessagesInAllMode() {
        let msg1 = makeMsg(server: "irc.example.com", channel: "#general", text: "hi")
        let msg2 = makeMsg(server: "irc.example.com", channel: "#random", text: "hey")
        manager.allObjects = [msg1, msg2]

        let ch1 = ChannelHandle(serverId: UUID(), serverHost: "irc.example.com", name: "#general", userCount: 0)
        let ch2 = ChannelHandle(serverId: UUID(), serverHost: "irc.example.com", name: "#random", userCount: 0)
        manager.channels = [ch1, ch2]
        manager.setActiveChannel(nil)

        XCTAssertEqual(manager.visibleMessages.count, 2)
    }

    private func makeMsg(server: String, channel: String, text: String) -> WOMObject {
        WOMObject(id: UUID().uuidString, type: ["wom:Message"], createdAt: Date(),
                  content: WOMContent(format: "text/plain", text: text),
                  data: ["server": server, "channel": channel],
                  provenance: .remotePeer(source: nil, actor: nil, createdAt: Date()))
    }
}
