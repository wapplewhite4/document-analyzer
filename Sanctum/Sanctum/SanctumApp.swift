import SwiftUI

@main
struct SanctumApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
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
                .environmentObject(appState)
        }
    }
}

extension Notification.Name {
    static let openDocumentRequested = Notification.Name("openDocumentRequested")
}
