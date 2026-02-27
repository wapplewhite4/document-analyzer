import Foundation

/// Service that bridges the Swift UI layer to the Rust core via C FFI.
///
/// Import the generated header via bridging header:
///   #import "sanctum_core.h"
@MainActor
class DocumentService {
    static let shared = DocumentService()
    private weak var appState: AppState?

    func configure(appState: AppState) {
        self.appState = appState
    }

    func loadDocument(url: URL) async {
        guard let appState else { return }

        appState.isProcessing = true
        appState.messages = []

        let modelPath = ModelManager.shared.modelPath(for: appState.selectedModel)

        await Task.detached(priority: .userInitiated) {
            let result = sanctum_load_document(
                url.path.cString(using: .utf8),
                modelPath.cString(using: .utf8)
            )

            await MainActor.run {
                if result == 0 {
                    let fileSize: Int64 = {
                        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
                        return Int64(values?.fileSize ?? 0)
                    }()

                    let doc = SanctumDocument(
                        id: UUID(),
                        name: url.lastPathComponent,
                        path: url.path,
                        fileSize: fileSize,
                        dateAdded: Date()
                    )

                    // Only set activeDocument directly (not via published setter)
                    // to avoid re-triggering loadDocument from the didSet observer
                    if !appState.documents.contains(where: { $0.path == url.path }) {
                        appState.documents.insert(doc, at: 0)
                    }

                    // Update activeDocument without triggering the didSet reload
                    // by checking if it's already the same path
                    if appState.activeDocument?.path != url.path {
                        // Temporarily disable the didSet by setting directly
                        appState.activeDocument = doc
                    }

                    appState.messages.append(ChatMessage(
                        id: UUID(),
                        role: .assistant,
                        content: "Document loaded. What would you like to know?",
                        timestamp: Date()
                    ))
                } else {
                    appState.messages.append(ChatMessage(
                        id: UUID(),
                        role: .assistant,
                        content: "Failed to load document. Make sure it's a readable PDF or text file.",
                        timestamp: Date()
                    ))
                }
                appState.isProcessing = false
            }
        }.value
    }

    func ask(question: String) async {
        guard let appState else { return }

        // Add user message immediately
        appState.messages.append(ChatMessage(
            id: UUID(),
            role: .user,
            content: question,
            timestamp: Date()
        ))

        // Add empty assistant message that we'll stream into
        let assistantMessageId = UUID()
        appState.messages.append(ChatMessage(
            id: assistantMessageId,
            role: .assistant,
            content: "",
            timestamp: Date()
        ))

        appState.isProcessing = true

        await Task.detached(priority: .userInitiated) {
            // Streaming token callback — updates the last message on main thread
            let callback: @convention(c) (UnsafePointer<CChar>?) -> Void = { tokenPtr in
                guard let tokenPtr else { return }
                let token = String(cString: tokenPtr)
                Task { @MainActor in
                    if let idx = appState.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                        appState.messages[idx].content += token
                    }
                }
            }

            let resultPtr = sanctum_ask(
                question.cString(using: .utf8),
                callback
            )

            await MainActor.run {
                appState.isProcessing = false

                if let resultPtr {
                    let jsonStr = String(cString: resultPtr)
                    if let data = jsonStr.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = json["error"] as? String {
                        if let idx = appState.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                            appState.messages[idx].content = "Error: \(error)"
                        }
                    }
                    sanctum_free_string(resultPtr)
                }
            }
        }.value
    }
}
