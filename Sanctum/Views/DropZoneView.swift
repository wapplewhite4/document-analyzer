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
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, url.isFileURL else { return false }
            DocumentService.shared.addDocument(url: url)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }
}
