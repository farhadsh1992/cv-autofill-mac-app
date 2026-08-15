import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var status = ""
    @State private var isError = false
    @State private var backupStatus = ""
    @State private var backupIsError = false

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $state.settings.appearanceMode) {
                    Text("System").tag(AppearanceMode.system)
                    Text("Light").tag(AppearanceMode.light)
                    Text("Dark").tag(AppearanceMode.dark)
                }
                .pickerStyle(.segmented)

                ColorPicker(
                    "Button color",
                    selection: Binding(
                        get: { Color(hex: state.settings.accentColorHex) },
                        set: { state.settings.accentColorHex = $0.toHex() }
                    ),
                    supportsOpacity: false
                )

                Picker("Button style", selection: $state.settings.buttonStyle) {
                    Text("Normal").tag(ButtonStyleChoice.normal)
                    Text("Glass").tag(ButtonStyleChoice.glass)
                }
                .pickerStyle(.segmented)
                Text(glassNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Appearance").font(.headline)
            }

            Section {
                Text("Neither OpenAI nor Anthropic offer a public account-login flow for third-party apps — the ChatGPT/Claude.ai subscription login is separate from their developer APIs. An API key, billed per call, is the supported way to connect. Both providers can be set up at once — pick which one to use per generation.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Picker("Default provider", selection: $state.settings.defaultProvider) {
                    Text("OpenAI").tag(Provider.openai)
                    Text("Anthropic (Claude)").tag(Provider.anthropic)
                }
                .pickerStyle(.segmented)
                Text("Pre-fills the picker in Generate — you can still switch providers per action there.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("AI providers").font(.headline)
            }

            Section {
                SecureField("sk-...", text: $state.openaiApiKey)
                Picker("Model", selection: $state.settings.openaiModel) {
                    ForEach(ModelCatalog.openai, id: \.self) { m in
                        Text(ModelCatalog.displayName(m)).tag(m)
                    }
                }
                Link("Get an API key at platform.openai.com/api-keys", destination: URL(string: "https://platform.openai.com/api-keys")!)
                    .font(.footnote)
                UsageSummary(provider: .openai)
            } header: {
                Text("OpenAI").font(.headline)
            }

            Section {
                SecureField("sk-ant-...", text: $state.anthropicApiKey)
                Picker("Model", selection: $state.settings.anthropicModel) {
                    ForEach(ModelCatalog.anthropic, id: \.self) { m in
                        Text(ModelCatalog.displayName(m)).tag(m)
                    }
                }
                Link("Get an API key at console.anthropic.com/settings/keys", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    .font(.footnote)
                UsageSummary(provider: .anthropic)
            } header: {
                Text("Anthropic (Claude)").font(.headline)
            }

            Section {
                HStack {
                    Button("Save") {
                        if state.openaiApiKey.contains("://") {
                            status = "The OpenAI API key field has a URL in it, not a key — paste the actual sk-... key instead."
                            isError = true
                            return
                        }
                        if state.anthropicApiKey.contains("://") {
                            status = "The Anthropic API key field has a URL in it, not a key — paste the actual sk-ant-... key instead."
                            isError = true
                            return
                        }
                        state.saveSettings()
                        status = "Saved."
                        isError = false
                    }
                    if !status.isEmpty { Text(status).foregroundStyle(isError ? .red : .secondary) }
                }
                Text("Your API keys are stored in the macOS Keychain, not in a plain file.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Reads and writes the same JSON format as the browser extension's Options → Info → Backup — export from one, import into the other, to move your CV, resources, applied jobs, and API keys across. Not automatic: run this whenever you want the two back in sync. A few things don't carry over either way — addresses and Kimi/Gemini keys aren't supported in this app yet, and About Me notes get merged into this app's single text field.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Export backup") { exportBackup() }
                    Button("Import backup") { importBackup() }
                }
                if !backupStatus.isEmpty {
                    Text(backupStatus).foregroundStyle(backupIsError ? .red : .secondary).font(.footnote)
                }
                Text("This file contains your API keys in plain text — keep it private, never commit it to a Git repo or share it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Backup").font(.headline)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }

    private func exportBackup() {
        let dict = Backup.exportDictionary(state: state)
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) else {
            backupStatus = "Couldn't build the backup file."
            backupIsError = true
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "cv-autofill-backup.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
            backupStatus = "Exported."
            backupIsError = false
        } catch {
            backupStatus = error.localizedDescription
            backupIsError = true
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                backupStatus = "That file doesn't look like a backup from this app or the extension."
                backupIsError = true
                return
            }
            let result = Backup.apply(dict, to: state)
            var summary = result.imported.isEmpty ? "Nothing recognizable to import." : "Imported: \(result.imported.joined(separator: ", "))."
            if !result.skipped.isEmpty {
                summary += " Skipped: \(result.skipped.joined(separator: ", "))."
            }
            backupStatus = summary
            backupIsError = result.imported.isEmpty
        } catch {
            backupStatus = "Import failed: \(error.localizedDescription)"
            backupIsError = true
        }
    }

    private var glassNote: String {
        if #available(macOS 26.0, *) {
            return "Glass uses macOS's Liquid Glass button material. (The window's title bar already gets that look automatically from macOS 26 itself — that part isn't controlled by this app.)"
        } else {
            return "Glass needs macOS 26 (Tahoe) or later — this Mac will use the normal style regardless."
        }
    }
}

private struct UsageSummary: View {
    @EnvironmentObject var state: AppState
    let provider: Provider

    var body: some View {
        let entries = state.usageEntries(for: provider)
        VStack(alignment: .leading, spacing: 3) {
            Text("Usage so far (this app)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            if entries.isEmpty {
                Text("No requests yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    Text(
                        "\(entry.model): \(entry.stats.inputTokens + entry.stats.outputTokens) tokens" +
                        " · ~$\(String(format: "%.3f", entry.estimatedCost)) estimated" +
                        " (\(entry.stats.requestCount) request\(entry.stats.requestCount == 1 ? "" : "s"))"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Text("Estimated from a fixed price table, not fetched live — check your provider's dashboard for exact billing.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
