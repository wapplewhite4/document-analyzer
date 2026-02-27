import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @State private var inputText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Document header bar
            if let doc = appState.activeDocument {
                DocumentHeaderView(document: doc)
                Divider()
            }

            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(appState.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        if appState.isProcessing {
                            ThinkingIndicator()
                                .id("thinking")
                        }
                    }
                    .padding()
                }
                .onChange(of: appState.messages.count) {
                    withAnimation {
                        proxy.scrollTo(appState.messages.last?.id ?? "thinking",
                                       anchor: .bottom)
                    }
                }
            }

            Divider()

            // Input bar
            HStack(spacing: 12) {
                TextField("Ask anything about this document...", text: $inputText, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .onSubmit { sendMessage() }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(inputText.isEmpty ? .secondary : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || appState.isProcessing)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    func sendMessage() {
        guard !inputText.isEmpty else { return }
        let question = inputText
        inputText = ""

        Task {
            await DocumentService.shared.ask(question: question)
        }
    }
}

struct DocumentHeaderView: View {
    let document: SanctumDocument

    var body: some View {
        HStack {
            Image(systemName: "doc.text.fill")
                .foregroundColor(.accentColor)
            Text(document.name)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.accentColor)
                    .frame(width: 28)
            } else {
                Spacer()
            }

            Text(message.content)
                .textSelection(.enabled)
                .padding(10)
                .background(
                    message.role == .user
                    ? Color.accentColor.opacity(0.15)
                    : Color(NSColor.controlBackgroundColor)
                )
                .cornerRadius(10)

            if message.role == .user {
                Image(systemName: "person.circle.fill")
                    .foregroundColor(.secondary)
                    .frame(width: 28)
            } else {
                Spacer()
            }
        }
    }
}

struct ThinkingIndicator: View {
    @State private var dots = ""
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack {
            Text("Analyzing\(dots)")
                .foregroundColor(.secondary)
                .font(.callout)
        }
        .onReceive(timer) { _ in
            dots = dots.count < 3 ? dots + "." : ""
        }
    }
}
