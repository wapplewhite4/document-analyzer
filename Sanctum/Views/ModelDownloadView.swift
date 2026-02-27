import SwiftUI

/// Critical UX moment — handle the large model download gracefully.
struct ModelDownloadView: View {
    @Environment(AppState.self) var appState
    @State private var selectedTier: ModelTier = .fast
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var downloadError: String?
    @State private var bytesDownloaded: Int64 = 0

    var body: some View {
        VStack(spacing: 32) {
            Text("Choose Your Model")
                .font(.title)
                .fontWeight(.bold)

            Text("Sanctum needs to download an AI model to analyze documents.\nThis is a one-time download that stays on your Mac.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            // Model tier selection
            VStack(spacing: 12) {
                ForEach(ModelTier.allCases, id: \.self) { tier in
                    ModelTierRow(
                        tier: tier,
                        isSelected: selectedTier == tier,
                        isRecommended: tier == .balanced,
                        ramAvailable: SystemInfo.totalRAMGB
                    ) {
                        selectedTier = tier
                    }
                }
            }
            .padding(.horizontal, 40)

            if isDownloading {
                VStack(spacing: 8) {
                    ProgressView(value: downloadProgress)
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 40)

                    HStack {
                        Text(formatBytes(bytesDownloaded))
                        Text("of")
                        Text(String(format: "%.1f GB", selectedTier.downloadSizeGB))
                        Spacer()
                        Text(String(format: "%.0f%%", downloadProgress * 100))
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 40)
                }
            }

            if let error = downloadError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.callout)
            }

            Button(isDownloading ? "Downloading..." : "Download \(selectedTier.displayName) Model") {
                startDownload()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isDownloading || !isRAMSufficient)

            if !isRAMSufficient {
                Text("Your Mac has \(SystemInfo.totalRAMGB)GB RAM. \(selectedTier.displayName) requires \(selectedTier.ramRequirementGB)GB.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .frame(maxWidth: 560)
        .padding(48)
    }

    var isRAMSufficient: Bool {
        SystemInfo.totalRAMGB >= selectedTier.ramRequirementGB
    }

    func startDownload() {
        isDownloading = true
        downloadError = nil

        Task {
            do {
                try await ModelManager.shared.downloadModel(selectedTier) { progress, bytes in
                    Task { @MainActor in
                        self.downloadProgress = progress
                        self.bytesDownloaded = bytes
                    }
                }

                appState.selectedModel = selectedTier
                appState.isModelReady = true
                UserDefaults.standard.set(selectedTier.rawValue, forKey: "selectedModel")
            } catch {
                isDownloading = false
                downloadError = "Download failed: \(error.localizedDescription). Check your connection and try again."
            }
        }
    }

    func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 0.1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_000_000
        return String(format: "%.0f MB", mb)
    }
}

struct ModelTierRow: View {
    let tier: ModelTier
    let isSelected: Bool
    let isRecommended: Bool
    let ramAvailable: Int
    let onSelect: () -> Void

    var isDisabled: Bool { ramAvailable < tier.ramRequirementGB }

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(tier.displayName).fontWeight(.semibold)
                        if isRecommended {
                            Text("Recommended")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundColor(.accentColor)
                                .cornerRadius(4)
                        }
                    }
                    Text(tier.description)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f GB", tier.downloadSizeGB))
                        .fontWeight(.medium)
                    Text("download")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.1)
                          : Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
    }
}

/// Helper to detect installed RAM.
struct SystemInfo {
    static var totalRAMGB: Int {
        Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
    }
}
