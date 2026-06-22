import Foundation

/// Streaming client for Mastodon timeline updates via WebSocket.
/// Currently a stub -- REST polling is used until this is implemented.
final class MastodonStreamer {
    private var task: URLSessionWebSocketTask?

    func connect(instanceURL: String, token: String) {
        // TODO: Implement WebSocket connection to /api/v1/streaming
    }

    func disconnect() {
        task?.cancel()
        task = nil
    }
}
