import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        TabView {
            ModelSettingsTab()
                .tabItem { Label("Models", systemImage: "cpu") }

            PrivacyTab()
                .tabItem { Label("Privacy", systemImage: "lock.shield") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 360)
    }
}

struct ModelSettingsTab: View {
    @Environment(AppState.self) var appState
    @State private var downloadingTier: ModelTier?
    @State private var downloadProgress: Double = 0
    @State private var downloadError: String?
    @State private var tierToDelete: ModelTier?

    var body: some View {
        Form {
            Section("Active Model") {
                ForEach(ModelTier.allCases, id: \.self) { tier in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(tier.displayName)
                            Text(tier.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if ModelManager.shared.isModelDownloaded(tier) {
                            if appState.selectedModel == tier {
                                Text("Active")
                                    .foregroundColor(.accentColor)
                                    .font(.callout)
                            } else {
                                Button("Use") {
                                    appState.selectedModel = tier
                                    UserDefaults.standard.set(tier.rawValue, forKey: "selectedModel")
                                }
                                .buttonStyle(.borderless)
                            }
                            Button(role: .destructive) {
                                tierToDelete = tier
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete \(tier.displayName) model (\(String(format: "%.1f", tier.downloadSizeGB)) GB)")
                        } else if downloadingTier == tier {
                            HStack(spacing: 8) {
                                ProgressView(value: downloadProgress)
                                    .frame(width: 80)
                                Text(String(format: "%.0f%%", downloadProgress * 100))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 36, alignment: .trailing)
                            }
                        } else {
                            Button("Download") {
                                downloadModel(tier)
                            }
                            .buttonStyle(.borderless)
                            .disabled(downloadingTier != nil)
                        }
                    }
                }
            }

            if let error = downloadError {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Delete Model?", isPresented: Binding(
            get: { tierToDelete != nil },
            set: { if !$0 { tierToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { tierToDelete = nil }
            Button("Delete", role: .destructive) {
                if let tier = tierToDelete {
                    ModelManager.shared.deleteModel(tier)
                    if appState.selectedModel == tier {
                        appState.isModelReady = false
                    }
                    tierToDelete = nil
                }
            }
        } message: {
            if let tier = tierToDelete {
                Text("This will delete the \(tier.displayName) model (\(String(format: "%.1f", tier.downloadSizeGB)) GB). You can re-download it later.")
            }
        }
    }

    func downloadModel(_ tier: ModelTier) {
        downloadingTier = tier
        downloadProgress = 0
        downloadError = nil

        Task {
            do {
                try await ModelManager.shared.downloadModel(tier) { progress, _ in
                    Task { @MainActor in
                        self.downloadProgress = progress
                    }
                }
                downloadingTier = nil
                appState.selectedModel = tier
                appState.isModelReady = true
                UserDefaults.standard.set(tier.rawValue, forKey: "selectedModel")
            } catch {
                downloadingTier = nil
                downloadError = "Download failed: \(error.localizedDescription)"
            }
        }
    }
}

struct PrivacyTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("No network connections", systemImage: "wifi.slash")
            Label("No telemetry or analytics", systemImage: "eye.slash")
            Label("No account or sign-in required", systemImage: "person.slash")
            Label("Documents never leave this Mac", systemImage: "lock.doc")

            Divider()

            Text("Sanctum makes no outbound network requests after model download. You can verify this with Little Snitch or any network monitor.")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .padding(24)
    }
}

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Sanctum").font(.title2).fontWeight(.bold)
            Text("Version 1.0").foregroundColor(.secondary)
            Text("Built for people who need AI help\nwith documents that can't leave their machine.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
