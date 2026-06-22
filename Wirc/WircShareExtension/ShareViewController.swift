import UIKit
import UniformTypeIdentifiers

/// Share Extension view controller — accepts URLs via the system share sheet,
/// discovers RSS/Atom feeds from the URL, and adds them to the feed store.
class ShareViewController: UIViewController {

    // MARK: - UI

    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let messageLabel = UILabel()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        preferredContentSize = CGSize(width: 320, height: 280)
        setupUI()

        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first else {
            showMessage("No content received", autoDismiss: true)
            return
        }

        provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] url, error in
            guard let self, let url = url as? URL else {
                DispatchQueue.main.async { self?.showMessage("No URL received", autoDismiss: true) }
                return
            }
            DispatchQueue.main.async {
                self.discoverAndSave(url: url)
            }
        }
    }

    // MARK: - Feed Discovery

    private func discoverAndSave(url: URL) {
        messageLabel.text = "Checking \(url.host ?? "URL") for feeds..."
        activityIndicator.startAnimating()

        Task {
            let fetcher = FeedFetcher()
            do {
                let discovered = try await fetcher.discoverFeed(from: url)
                guard !discovered.isEmpty else {
                    showMessage("No feed found at this URL", autoDismiss: true)
                    return
                }

                let store = FeedSubscriptionStore()
                for feedURL in discovered {
                    let sub = FeedSubscription(feedURL: feedURL.absoluteString)
                    store.add(sub)
                }

                let count = discovered.count
                let label = count == 1 ? "1 feed added" : "\(count) feeds added"
                showMessage(label, autoDismiss: true)
            } catch {
                showMessage("Error: \(error.localizedDescription)", autoDismiss: true)
            }
        }
    }

    // MARK: - UI Helpers

    private func setupUI() {
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.font = UIFont.preferredFont(forTextStyle: .body)
        messageLabel.textColor = .label
        view.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -24),

            messageLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 16),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }

    private func showMessage(_ text: String, autoDismiss: Bool) {
        activityIndicator.stopAnimating()
        messageLabel.text = text

        if autoDismiss {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.complete()
            }
        }
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: [])
    }
}
