import SwiftUI

/// Shown on first launch only. Simple, fast, builds trust.
struct OnboardingView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "lock.doc.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
                .padding(.bottom, 24)

            Text("Sanctum")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Your documents stay on your Mac.\nNo cloud. No accounts. No exceptions.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.top, 8)
                .padding(.bottom, 48)

            VStack(alignment: .leading, spacing: 20) {
                OnboardingPoint(
                    icon: "cpu",
                    title: "Runs entirely on your Mac",
                    detail: "AI inference happens locally using Apple Silicon."
                )
                OnboardingPoint(
                    icon: "wifi.slash",
                    title: "No internet required",
                    detail: "After setup, Sanctum works completely offline."
                )
                OnboardingPoint(
                    icon: "eye.slash",
                    title: "Nothing is ever uploaded",
                    detail: "Your documents never leave your device."
                )
            }
            .padding(.horizontal, 60)

            Spacer()

            Button("Get Started") {
                UserDefaults.standard.set(true, forKey: "onboardingComplete")
                appState.onboardingComplete = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct OnboardingPoint: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).foregroundColor(.secondary).font(.callout)
            }
        }
    }
}
