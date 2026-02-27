import SwiftUI

struct LibraryView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var appState = appState
        List(appState.documents, selection: $appState.activeDocument) { doc in
            DocumentRow(document: doc)
                .tag(doc)
        }
        .listStyle(.sidebar)
        .navigationTitle("Documents")
        .safeAreaInset(edge: .bottom) {
            ModelStatusBar()
                .padding(8)
        }
    }
}

struct DocumentRow: View {
    let document: SanctumDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(document.name)
                .lineLimit(2)
                .font(.callout)
                .fontWeight(.medium)

            HStack {
                Text(document.dateAdded, style: .date)
                Text("·")
                Text(formatFileSize(document.fileSize))
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    func formatFileSize(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb < 1 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", mb)
    }
}

struct ModelStatusBar: View {
    @Environment(AppState.self) var appState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
            Text("\(appState.selectedModel.displayName) model active")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
