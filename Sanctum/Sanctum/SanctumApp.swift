import SwiftUI

@main
struct SanctumApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .onAppear {
                    DocumentService.shared.configure(appState: appState)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Document...") {
                    NotificationCenter.default.post(
                        name: .openDocumentRequested, object: nil)
                }
                .keyboardShortcut("o")
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}

extension Notification.Name {
    static let openDocumentRequested = Notification.Name("openDocumentRequested")
}
