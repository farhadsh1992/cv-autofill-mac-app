import SwiftUI

// Live-updating, terminal-styled panel showing a CLI-based provider's
// streamed output as it happens — docked to the right of the detail pane,
// toggled by a button in whichever view is currently using that provider.
// Shared by both CLI-based providers (Claude Code, OpenAI Codex); only one
// runs at a time, so one panel is enough — its title just follows
// state.cliTerminalProviderName.
struct CLITerminalPanel: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "terminal")
                Text(state.cliTerminalProviderName.isEmpty ? "Terminal" : state.cliTerminalProviderName)
                    .font(.headline)
                Spacer()
                Button {
                    state.cliTerminalVisible = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(10)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    Text(state.cliTerminalText.isEmpty ? "Waiting for a request..." : state.cliTerminalText)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(state.cliTerminalText.isEmpty ? Color(white: 0.5) : Color(white: 0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .textSelection(.enabled)
                        .id("bottom")
                }
                .background(Color.black)
                .onChange(of: state.cliTerminalText) { _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .frame(width: 340)
        .background(.regularMaterial)
    }
}

// Small toggle used in views that can invoke a CLI-based provider, shown
// only when that view's currently-selected provider is one of them.
struct CLITerminalToggle: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Button {
            state.cliTerminalVisible.toggle()
        } label: {
            Label(state.cliTerminalVisible ? "Hide terminal" : "Show terminal", systemImage: "terminal")
        }
    }
}
