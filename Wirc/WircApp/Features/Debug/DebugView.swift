import SwiftUI

struct DebugView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            NavigationLink("Raw Event Log (\(appState.rawEvents.count))") {
                RawEventLogView()
            }
            NavigationLink("WOM Objects (\(appState.womObjects.count))") {
                WOMObjectInspectorView()
            }
        }
        .navigationTitle("Debug")
    }
}
