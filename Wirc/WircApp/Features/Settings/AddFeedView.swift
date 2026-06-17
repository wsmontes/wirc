import SwiftUI
import UniformTypeIdentifiers

struct AddFeedView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var sourceType: FeedSourceType = .rss
    @State private var isDiscovering = false
    @State private var discoveredURLs: [String] = []
    @State private var selectedDiscoveredURL: String?
    @State private var errorMessage: String?
    @State private var showOPMLPicker = false

    var body: some View {
        NavigationStack {
            Form {
                // URL input
                Section("Feed URL or Website") {
                    TextField("https://example.com or https://youtube.com/@channel",
                              text: $urlText)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    Button {
                        discover()
                    } label: {
                        HStack {
                            if isDiscovering {
                                ProgressView()
                            }
                            Text("Auto-discover Feed")
                        }
                    }
                    .disabled(urlText.isEmpty || isDiscovering)

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                // Discovered feeds
                if !discoveredURLs.isEmpty {
                    Section("Discovered Feeds") {
                        ForEach(discoveredURLs, id: \.self) { url in
                            HStack {
                                Text(url)
                                    .font(.caption)
                                    .lineLimit(2)
                                Spacer()
                                if selectedDiscoveredURL == url {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedDiscoveredURL = url
                                urlText = url
                            }
                        }
                    }
                }

                // Manual source type
                Section("Feed Type") {
                    Picker("Type", selection: $sourceType) {
                        ForEach(FeedSourceType.allCases, id: \.self) { t in
                            Text(typeLabel(t)).tag(t)
                        }
                    }
                }

                // OPML import
                Section {
                    Button {
                        showOPMLPicker = true
                    } label: {
                        Label("Import OPML File", systemImage: "doc.text")
                    }
                } header: {
                    Text("Bulk Import")
                } footer: {
                    Text("Import subscriptions from another RSS reader via OPML file.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(DesignSystem.Colors.page)
            .navigationTitle("Add Feed")
            .navigationBarTitleDisplayMode(.inline)
            .tint(DesignSystem.Colors.signal)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Subscribe") { subscribe() }
                        .disabled(urlText.isEmpty)
                }
            }
            .fileImporter(
                isPresented: $showOPMLPicker,
                allowedContentTypes: [.xml, UTType(filenameExtension: "opml") ?? .xml],
                allowsMultipleSelection: false
            ) { result in
                handleOPMLImport(result)
            }
        }
    }

    private func discover() {
        isDiscovering = true
        errorMessage = nil
        discoveredURLs = []
        Task {
            do {
                let urls = try await appState.discoverFeedURL(from: urlText)
                await MainActor.run {
                    discoveredURLs = urls
                    if let first = urls.first {
                        selectedDiscoveredURL = first
                        urlText = first
                        // Auto-detect type
                        if first.contains("youtube.com") { sourceType = .youtube }
                        else if first.contains("github.com") { sourceType = .github }
                    }
                    if urls.isEmpty {
                        errorMessage = "No feed found. Try pasting the feed URL directly."
                    }
                    isDiscovering = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isDiscovering = false
                }
            }
        }
    }

    private func subscribe() {
        let finalURL = selectedDiscoveredURL ?? urlText
        guard !finalURL.isEmpty else { return }
        Task {
            do {
                try await appState.addFeed(url: finalURL, sourceType: sourceType)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func handleOPMLImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let fileURL = urls.first else { return }
            Task {
                do {
                    let data = try Data(contentsOf: fileURL)
                    _ = try await appState.importOPML(data: data)
                    await MainActor.run {
                        errorMessage = nil
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = "OPML import failed: \(error.localizedDescription)"
                    }
                }
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func typeLabel(_ type: FeedSourceType) -> String {
        switch type {
        case .rss: return "RSS / Blog"
        case .atom: return "Atom Feed"
        case .youtube: return "YouTube Channel"
        case .github: return "GitHub Releases"
        case .podcast: return "Podcast"
        }
    }
}
