import Foundation

/// Persists FeedSubscriptions as a single JSON array file.
/// Thread-safe via a serial queue.
final class FeedSubscriptionStore {
    private var subscriptions: [FeedSubscription] = []
    private let fileURL: URL
    private let queue = DispatchQueue(label: "wirc.subscriptionstore")

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("wirc/subscriptions.json")
        load()
    }

    func add(_ subscription: FeedSubscription) {
        queue.sync {
            subscriptions.append(subscription)
            persist()
        }
    }

    func addMany(_ newSubscriptions: [FeedSubscription]) {
        queue.sync {
            subscriptions.append(contentsOf: newSubscriptions)
            persist()
        }
    }

    func remove(id: UUID) {
        queue.sync {
            subscriptions.removeAll { $0.id == id }
            persist()
        }
    }

    func update(_ subscription: FeedSubscription) {
        queue.sync {
            if let idx = subscriptions.firstIndex(where: { $0.id == subscription.id }) {
                subscriptions[idx] = subscription
                persist()
            }
        }
    }

    func get(id: UUID) -> FeedSubscription? {
        queue.sync {
            subscriptions.first { $0.id == id }
        }
    }

    /// Thread-safe accessor for all subscriptions.
    func getAll() -> [FeedSubscription] {
        queue.sync { subscriptions }
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(subscriptions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([FeedSubscription].self, from: data) else { return }
        subscriptions = saved
    }
}
