import SwiftUI

/// Central observable state for the app.
@Observable
@MainActor
class AppState {
    var documents: [SanctumDocument] = []
    var messages: [ChatMessage] = []
    var isProcessing: Bool = false
    var modelDownloadProgress: Double = 0
    var selectedModel: ModelTier = .fast
    var isModelReady: Bool = false
    var onboardingComplete: Bool = false

    var activeDocument: SanctumDocument? {
        didSet {
            guard let doc = activeDocument else { return }
            messages = []
            Task {
                await DocumentService.shared.loadDocument(
                    url: URL(fileURLWithPath: doc.path))
            }
        }
    }

    init() {
        onboardingComplete = UserDefaults.standard.bool(forKey: "onboardingComplete")
        selectedModel = ModelTier(rawValue: UserDefaults.standard.string(
            forKey: "selectedModel") ?? "fast") ?? .fast
        isModelReady = ModelManager.shared.isModelDownloaded(selectedModel)
    }
}

struct SanctumDocument: Identifiable, Hashable {
    let id: UUID
    let name: String
    let path: String
    let fileSize: Int64
    let dateAdded: Date
    var pageCount: Int?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SanctumDocument, rhs: SanctumDocument) -> Bool {
        lhs.id == rhs.id
    }
}

struct ChatMessage: Identifiable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date

    enum MessageRole { case user, assistant }
}

enum ModelTier: String, CaseIterable {
    case fast = "fast"
    case balanced = "balanced"
    case thorough = "thorough"

    var displayName: String {
        switch self {
        case .fast: return "Fast"
        case .balanced: return "Balanced"
        case .thorough: return "Thorough"
        }
    }

    var description: String {
        switch self {
        case .fast: return "Quick answers on most documents. Works on all Macs."
        case .balanced: return "Recommended. Better reasoning on complex documents. Requires 16GB RAM."
        case .thorough: return "Best accuracy for dense legal or technical content. Requires 32GB RAM."
        }
    }

    var ramRequirementGB: Int {
        switch self {
        case .fast: return 8
        case .balanced: return 16
        case .thorough: return 32
        }
    }

    var downloadSizeGB: Double {
        switch self {
        case .fast: return 4.7
        case .balanced: return 8.4
        case .thorough: return 19.0
        }
    }

    var modelFilename: String {
        switch self {
        case .fast: return "llama-3.1-8b-instruct-q4_k_m.gguf"
        case .balanced: return "qwen2.5-14b-instruct-q4_k_m.gguf"
        case .thorough: return "qwen2.5-32b-instruct-q4_k_m.gguf"
        }
    }

    var downloadURL: String {
        // Host on own CDN or Hugging Face
        let base = "https://your-cdn.com/models"
        return "\(base)/\(modelFilename)"
    }
}
