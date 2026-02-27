import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .foregroundColor(isTargeted ? .accentColor : .secondary.opacity(0.4))
                .padding(40)

            VStack(spacing: 16) {
                Image(systemName: "lock.doc")
                    .font(.system(size: 56))
                    .foregroundColor(.secondary)

                Text("Drop a document to get started")
                    .font(.title2)
                    .fontWeight(.medium)

                Text("PDF, Word, or text files -- Everything stays on your Mac")
                    .foregroundColor(.secondary)
                    .font(.callout)
            }
        }
        .onDrop(of: [.pdf, .plainText, .fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                Task { await DocumentService.shared.loadDocument(url: url) }
            }
        }
        return true
    }
}
