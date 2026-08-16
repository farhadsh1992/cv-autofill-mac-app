import SwiftUI

// Split "install + log in" helper, shown as a sheet from Settings when a
// CLI-based provider's binary isn't found. Left is a real live terminal —
// runs whatever the user types through their own login shell, exactly like
// Terminal.app would (same trust boundary: their own local input, their own
// shell, their own privileges). Right is a short numbered guide with the
// exact commands and a link to the official docs.
struct CLISetupGuideView: View {
    enum Kind {
        case claudeCode
        case openaiCode

        var displayName: String {
            switch self {
            case .claudeCode: return "Claude Code"
            case .openaiCode: return "OpenAI Codex"
            }
        }

        var installSteps: [(label: String, command: String)] {
            switch self {
            case .claudeCode:
                return [
                    ("Official installer", "curl -fsSL https://claude.ai/install.sh | bash"),
                    ("npm alternative", "npm install -g @anthropic-ai/claude-code"),
                ]
            case .openaiCode:
                return [
                    ("npm (needs Node.js)", "npm install -g @openai/codex"),
                    ("Official installer", "curl -fsSL https://chatgpt.com/codex/install.sh | sh"),
                ]
            }
        }

        var loginCommand: String {
            switch self {
            case .claudeCode: return "claude auth login"
            case .openaiCode: return "codex login"
            }
        }

        var statusCommand: String {
            switch self {
            case .claudeCode: return "claude auth status"
            case .openaiCode: return "codex login status"
            }
        }

        var docsURL: URL {
            switch self {
            case .claudeCode: return URL(string: "https://code.claude.com/docs/en/overview")!
            case .openaiCode: return URL(string: "https://learn.chatgpt.com/docs/codex/cli")!
            }
        }

        var subscriptionNote: String {
            switch self {
            case .claudeCode:
                return "Needs a Claude Pro or Max subscription. (An Anthropic Console/API key works too, but then you'd be back to per-token billing — the whole point of using Claude Code here is avoiding that.)"
            case .openaiCode:
                return "Needs a ChatGPT Plus, Pro, or Team subscription. (An OpenAI API key works too, but same tradeoff — per-token billing instead of your existing subscription.)"
            }
        }

        var afterLoginSteps: [String] {
            switch self {
            case .claudeCode:
                return [
                    "Run the install command on the left (or paste your own).",
                    "Run \"claude auth login\" — it opens your browser to sign in with your Anthropic/Claude account.",
                    "Come back here and click \"Check again\" below.",
                ]
            case .openaiCode:
                return [
                    "Run the install command on the left.",
                    "Run \"codex login\" — it opens your browser to sign in with your ChatGPT account. No browser on this machine (e.g. over SSH)? Use \"codex login --device-auth\" instead.",
                    "Come back here and click \"Check again\" below.",
                ]
            }
        }
    }

    let kind: Kind
    @Environment(\.dismiss) private var dismiss
    @State private var terminalOutput = ""
    @State private var customCommand = ""
    @State private var running = false
    @State private var found: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Set up \(kind.displayName)").font(.title2)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            HStack(spacing: 0) {
                terminalPane
                Divider()
                guidePane
            }
        }
        .frame(width: 920, height: 580)
        .onAppear { refreshFound() }
    }

    private var terminalPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "terminal")
                Text("Terminal").font(.headline)
                Spacer()
                if running { ProgressView().controlSize(.small) }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(terminalOutput.isEmpty ? "Run a command below to get started." : terminalOutput)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(terminalOutput.isEmpty ? Color(white: 0.5) : Color(white: 0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .textSelection(.enabled)
                        .id("bottom")
                }
                .background(Color.black)
                .onChange(of: terminalOutput) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
            }

            HStack {
                TextField("Type a command and press Return", text: $customCommand)
                    .onSubmit { runCustom() }
                    .disabled(running)
                Button("Run") { runCustom() }
                    .disabled(running || customCommand.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var guidePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(kind.subscriptionNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("1. Install").font(.headline)
                ForEach(kind.installSteps, id: \.command) { step in
                    commandRow(label: step.label, command: step.command)
                }

                Text("2. Log in").font(.headline)
                commandRow(label: "Sign in with your account", command: kind.loginCommand)

                Text("3. Check").font(.headline)
                commandRow(label: "Confirm you're logged in", command: kind.statusCommand)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(kind.afterLoginSteps.enumerated()), id: \.offset) { i, step in
                        Text("\(i + 1). \(step)").font(.callout)
                    }
                }

                Link("Full documentation ↗", destination: kind.docsURL)
                    .font(.footnote)

                Spacer(minLength: 12)

                HStack {
                    Button("Check again") { refreshFound() }
                    if let found {
                        Text("Found: \(found)").font(.footnote).foregroundStyle(.green)
                    } else {
                        Text("Not found yet").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .frame(minWidth: 340, maxWidth: 400)
    }

    private func commandRow(label: String, command: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.footnote).foregroundStyle(.secondary)
            HStack {
                Text(command)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Run") { run(command) }.disabled(running)
            }
        }
    }

    private func runCustom() {
        let command = customCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        customCommand = ""
        run(command)
    }

    private func run(_ command: String) {
        guard !running else { return }
        running = true
        terminalOutput += "$ \(command)\n"
        Task {
            let status = await ShellCommandRunner.run(command: command) { chunk in
                terminalOutput += chunk
            }
            terminalOutput += "\n[exit \(status)]\n\n"
            running = false
            refreshFound()
        }
    }

    private func refreshFound() {
        switch kind {
        case .claudeCode:
            ClaudeCodeCLI.invalidateCache()
            found = ClaudeCodeCLI.resolvePath()
        case .openaiCode:
            CodexCLI.invalidateCache()
            found = CodexCLI.resolvePath()
        }
    }
}
