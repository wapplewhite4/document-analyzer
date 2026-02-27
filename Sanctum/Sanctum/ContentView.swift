import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if !appState.onboardingComplete {
                OnboardingView()
            } else if !appState.isModelReady {
                ModelDownloadView()
            } else {
                MainAppView()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

struct MainAppView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            LibraryView()
                .frame(minWidth: 220)
        } detail: {
            if appState.activeDocument != nil {
                ChatView()
            } else {
                DropZoneView()
            }
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Text("Sanctum")
                    .font(.headline)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: openFilePicker) {
                    Label("Open Document", systemImage: "plus")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDocumentRequested)) { _ in
            openFilePicker()
        }
    }

    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .plainText]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { await DocumentService.shared.loadDocument(url: url) }
        }
    }
}
