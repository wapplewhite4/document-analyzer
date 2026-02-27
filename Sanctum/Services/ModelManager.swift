import Foundation

/// Manages model download, storage, and availability.
///
/// Models are stored in ~/Library/Application Support/Sanctum/models/
/// (or inside the app container for sandboxed App Store builds).
@MainActor
class ModelManager {
    static let shared = ModelManager()

    private var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Sanctum/models")
        try? FileManager.default.createDirectory(at: dir,
            withIntermediateDirectories: true)
        return dir
    }

    func modelPath(for tier: ModelTier) -> String {
        modelsDirectory.appendingPathComponent(tier.modelFilename).path
    }

    func isModelDownloaded(_ tier: ModelTier) -> Bool {
        FileManager.default.fileExists(atPath: modelPath(for: tier))
    }

    /// Download a model with progress reporting.
    ///
    /// Uses URLSession.download() which writes directly to disk via the
    /// system's optimized download path — orders of magnitude faster than
    /// reading byte-by-byte through an async iterator.
    func downloadModel(_ tier: ModelTier, progress: @escaping @Sendable (Double, Int64) -> Void) async throws {
        guard let url = URL(string: tier.downloadURL) else {
            throw URLError(.badURL)
        }

        let destination = modelsDirectory.appendingPathComponent(tier.modelFilename)

        // Use a download task with progress observation
        let (tempURL, _) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(URL, URLResponse), Error>) in
            let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let tempURL, let response {
                    continuation.resume(returning: (tempURL, response))
                } else {
                    continuation.resume(throwing: URLError(.unknown))
                }
            }

            // Observe progress on a background timer
            let observation = task.progress.observe(\.fractionCompleted) { taskProgress, _ in
                let bytes = task.countOfBytesReceived
                progress(taskProgress.fractionCompleted, bytes)
            }

            // Store observation so it isn't deallocated
            objc_setAssociatedObject(task, "progressObservation", observation, .OBJC_ASSOCIATION_RETAIN)

            task.resume()
        }

        // Move downloaded file to final destination
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: tempURL, to: destination)

        progress(1.0, Int64(try fm.attributesOfItem(atPath: destination.path)[.size] as? UInt64 ?? 0))
    }
}
