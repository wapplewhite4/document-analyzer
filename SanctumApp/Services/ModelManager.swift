import Foundation

/// Manages model download, storage, and availability.
///
/// Models are stored in ~/Library/Application Support/Sanctum/models/
/// (or inside the app container for sandboxed App Store builds).
class ModelManager: ObservableObject {
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
    /// - Parameters:
    ///   - tier: The model tier to download.
    ///   - progress: Callback with (fraction 0-1, bytesDownloaded).
    func downloadModel(_ tier: ModelTier, progress: @escaping (Double, Int64) -> Void) async throws {
        guard let url = URL(string: tier.downloadURL) else {
            throw URLError(.badURL)
        }

        let destination = modelsDirectory.appendingPathComponent(tier.modelFilename)

        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)
        let totalBytes = response.expectedContentLength

        var downloadedBytes: Int64 = 0
        var buffer = Data()

        let outputStream = OutputStream(url: destination, append: false)!
        outputStream.open()
        defer { outputStream.close() }

        for try await byte in asyncBytes {
            buffer.append(byte)
            downloadedBytes += 1

            if buffer.count >= 1024 * 1024 { // Flush every 1MB
                buffer.withUnsafeBytes { ptr in
                    _ = outputStream.write(
                        ptr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        maxLength: buffer.count)
                }
                buffer.removeAll(keepingCapacity: true)

                if totalBytes > 0 {
                    progress(Double(downloadedBytes) / Double(totalBytes), downloadedBytes)
                }
            }
        }

        // Flush remaining bytes
        if !buffer.isEmpty {
            buffer.withUnsafeBytes { ptr in
                _ = outputStream.write(
                    ptr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    maxLength: buffer.count)
            }
        }

        progress(1.0, downloadedBytes)
    }
}
