import SwiftUI

struct FeedView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            Group {
                if appState.feedObjects.isEmpty {
                    ContentUnavailableView(
                        "No Posts Yet",
                        systemImage: "newspaper",
                        description: Text("Posts from people you follow will appear here.\nComing when Mastodon, Bluesky, and other posting protocols are added.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(appState.feedObjects) { object in
                                FeedCard(object: object)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Feed")
        }
    }
}
