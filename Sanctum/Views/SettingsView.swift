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
        .frame(width: 480, height: 320)
    }
}

struct ModelSettingsTab: View {
    @Environment(AppState.self) var appState

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
                        } else {
                            Text("Not downloaded")
                                .foregroundColor(.secondary)
                                .font(.callout)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
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
