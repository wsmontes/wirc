import SwiftUI

struct ChatView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            ConversationListView()
                .navigationTitle("Chat")
        }
    }
}
