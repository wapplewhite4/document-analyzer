import Foundation

/// Global token callback for C FFI bridging.
/// sanctum_ask's callback is a bare C function pointer (no user_data param),
/// so we must use a global to shuttle tokens back to Swift.
nonisolated(unsafe) private var gTokenCallback: ((String) -> Void)?

private let cTokenCallback: @convention(c) (UnsafePointer<CChar>?) -> Void = { tokenPtr in
    guard let tokenPtr else { return }
    let token = String(cString: tokenPtr)
    gTokenCallback?(token)
}

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

    /// Add a document to the library and make it active.
    /// Setting activeDocument triggers its didSet which calls loadDocument.
    func addDocument(url: URL) {
        guard let appState else { return }

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

        if !appState.documents.contains(where: { $0.path == url.path }) {
            appState.documents.insert(doc, at: 0)
        }

        appState.activeDocument = doc
    }

    /// Load a document via FFI. Called by activeDocument.didSet.
    func loadDocument(url: URL) async {
        guard let appState else { return }

        let modelPath = ModelManager.shared.modelPath(for: appState.selectedModel)
        guard FileManager.default.fileExists(atPath: modelPath) else {
            appState.isModelReady = false
            appState.messages.append(ChatMessage(
                id: UUID(),
                role: .assistant,
                content: "Model file not found. Please download a model first.",
                timestamp: Date()
            ))
            return
        }

        // In a sandboxed app, gain access to the file's security scope.
        // NSOpenPanel grants this automatically, but drag-and-drop or
        // reconstructed URLs may need it explicitly.
        let hasScope = url.startAccessingSecurityScopedResource()

        let docPath = url.path

        guard FileManager.default.isReadableFile(atPath: docPath) else {
            if hasScope { url.stopAccessingSecurityScopedResource() }
            appState.messages.append(ChatMessage(
                id: UUID(),
                role: .assistant,
                content: "Cannot read the file. Try opening it from the file picker instead of drag-and-drop.",
                timestamp: Date()
            ))
            return
        }

        appState.isProcessing = true

        // For scanned PDFs, use Vision OCR on the Swift side, then pass
        // the extracted text to Rust via sanctum_load_document_from_text.
        let isPDF = docPath.lowercased().hasSuffix(".pdf")
        let needsOCR = isPDF && OCRService.pdfNeedsOCR(url: url)

        let result: Int32
        if needsOCR {
            appState.messages.append(ChatMessage(
                id: UUID(),
                role: .assistant,
                content: "Scanned PDF detected — running OCR...",
                timestamp: Date()
            ))

            do {
                let ocrText = try await OCRService.ocrPDF(url: url)

                if hasScope { url.stopAccessingSecurityScopedResource() }

                result = await Task.detached(priority: .userInitiated) {
                    return sanctum_load_document_from_text(
                        ocrText.cString(using: .utf8),
                        modelPath.cString(using: .utf8)
                    )
                }.value
            } catch {
                if hasScope { url.stopAccessingSecurityScopedResource() }

                appState.messages.append(ChatMessage(
                    id: UUID(),
                    role: .assistant,
                    content: "OCR failed: \(error.localizedDescription)",
                    timestamp: Date()
                ))
                appState.isProcessing = false
                return
            }
        } else {
            result = await Task.detached(priority: .userInitiated) {
                return sanctum_load_document(
                    docPath.cString(using: .utf8),
                    modelPath.cString(using: .utf8)
                )
            }.value

            if hasScope { url.stopAccessingSecurityScopedResource() }
        }

        if result == 0 {
            // Only show the greeting when this is a fresh document load,
            // not when switching back to a document with existing chat.
            let hasOCRMessage = appState.messages.contains(where: { $0.content.contains("running OCR") })
            if appState.messages.isEmpty || hasOCRMessage {
                let greeting = needsOCR
                    ? "Document scanned and loaded via OCR. What would you like to know?"
                    : "Document loaded. What would you like to know?"
                appState.messages.append(ChatMessage(
                    id: UUID(),
                    role: .assistant,
                    content: greeting,
                    timestamp: Date()
                ))
            }
        } else {
            appState.messages.append(ChatMessage(
                id: UUID(),
                role: .assistant,
                content: "Failed to load document. The model may need more RAM than available, or the file format is unsupported.",
                timestamp: Date()
            ))
        }
        appState.isProcessing = false
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

        // Set up global streaming callback before calling FFI
        gTokenCallback = { [weak appState] token in
            Task { @MainActor in
                guard let appState,
                      let idx = appState.messages.firstIndex(where: { $0.id == assistantMessageId })
                else { return }
                appState.messages[idx].content += token
            }
        }

        let resultPtr = await Task.detached(priority: .userInitiated) {
            return sanctum_ask(
                question.cString(using: .utf8),
                cTokenCallback
            )
        }.value

        gTokenCallback = nil
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
}
