import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case appearance = "Appearance"
    case ai = "AI"
    case askAI = "Ask AI"
    case backup = "Backup"

    var id: String { rawValue }
}

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var tab: SettingsTab = .appearance
    @State private var status = ""
    @State private var isError = false
    @State private var backupStatus = ""
    @State private var backupIsError = false
    @State private var showClaudeCodeSetup = false
    @State private var showCodexSetup = false

    @State private var presetLabel = ""
    @State private var presetPrompt = ""
    @State private var editingPresetId: UUID?
    @State private var presetStatus = ""
    @State private var presetIsError = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(SettingsTab.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            Form {
                switch tab {
                case .appearance: appearanceSection
                case .ai: aiSection
                case .askAI: askAISection
                case .backup: backupSection
                }
            }
            .formStyle(.grouped)
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showClaudeCodeSetup) {
            CLISetupGuideView(kind: .claudeCode)
        }
        .sheet(isPresented: $showCodexSetup) {
            CLISetupGuideView(kind: .openaiCode)
        }
    }

    @ViewBuilder
    private var appearanceSection: some View {
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
            Text("Also used for the selected item's background in the sidebar.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ColorPicker(
                "Selected menu text color",
                selection: Binding(
                    get: { Color(hex: state.settings.menuTextColorHex) },
                    set: { state.settings.menuTextColorHex = $0.toHex() }
                ),
                supportsOpacity: false
            )
            Text("The sidebar item's text color while it's selected — set this separately if your button color makes the default white text hard to read.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Picker("Button style", selection: $state.settings.buttonStyle) {
                Text("Normal").tag(ButtonStyleChoice.normal)
                Text("Glass").tag(ButtonStyleChoice.glass)
            }
            .pickerStyle(.segmented)
            Text(glassNote)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Picker("Window style", selection: $state.settings.windowStyle) {
                Text("Normal").tag(ButtonStyleChoice.normal)
                Text("Glass").tag(ButtonStyleChoice.glass)
            }
            .pickerStyle(.segmented)
            Text(windowGlassNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Appearance").font(.headline)
        }
    }

    @ViewBuilder
    private var aiSection: some View {
        Section {
            Text("Each action below picks its own provider and model, independently — the same provider can be used with different models for different tasks. The sections further down are credentials only: an API key, or CLI setup, for each provider you want available here.")
                .font(.callout)
                .foregroundStyle(.secondary)

            taskPicker(title: "Rebuild / tailor CV", choice: $state.settings.tailorCv)
            taskPicker(title: "Rebuild / write cover letter", choice: $state.settings.coverLetter)
            taskPicker(title: "CV parsing", choice: $state.settings.other)
            Text("Ask AI has its own provider/model picker at the top of the Ask AI page — see the Ask AI tab above for its saved tasks.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("AI providers").font(.headline)
        }

        Section {
            SecureField("sk-...", text: $state.openaiApiKey)
            Link("Get an API key at platform.openai.com/api-keys", destination: URL(string: "https://platform.openai.com/api-keys")!)
                .font(.footnote)
            UsageSummary(provider: .openai)
        } header: {
            Text("OpenAI").font(.headline)
        }

        Section {
            SecureField("sk-ant-...", text: $state.anthropicApiKey)
            Link("Get an API key at console.anthropic.com/settings/keys", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                .font(.footnote)
            UsageSummary(provider: .anthropic)
        } header: {
            Text("Anthropic (Claude)").font(.headline)
        }

        Section {
            SecureField("sk-...", text: $state.kimiApiKey)
            Link("Get an API key at platform.moonshot.ai/console/api-keys", destination: URL(string: "https://platform.moonshot.ai/console/api-keys")!)
                .font(.footnote)
            Text("If your account is on Moonshot's mainland-China platform instead, its keys are issued for api.moonshot.cn and won't work here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            UsageSummary(provider: .kimi)
        } header: {
            Text("Kimi (Moonshot)").font(.headline)
        }

        Section {
            SecureField("AIza...", text: $state.geminiApiKey)
            Link("Get an API key at aistudio.google.com/apikey", destination: URL(string: "https://aistudio.google.com/apikey")!)
                .font(.footnote)
            UsageSummary(provider: .gemini)
        } header: {
            Text("Gemini (Google)").font(.headline)
        }

        Section {
            SecureField("sk-...", text: $state.deepseekApiKey)
            Link("Get an API key at platform.deepseek.com/api_keys", destination: URL(string: "https://platform.deepseek.com/api_keys")!)
                .font(.footnote)
            Text("Open-weight model, but this API is still billed per token like the others here — only DeepSeek's own consumer chat app (chat.deepseek.com) is free. Doesn't support PDF uploads — switch to OpenAI, Anthropic, or Gemini first for those.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            UsageSummary(provider: .deepseek)
        } header: {
            Text("DeepSeek").font(.headline)
        }

        Section {
            if let path = ClaudeCodeCLI.resolvePath() {
                Text("Found: \(path)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("The claude command wasn't found.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                    Button("Set up...") { showClaudeCodeSetup = true }
                }
            }
            Text("Runs through the claude CLI already logged into your Mac's Terminal — your Pro/Max subscription, not an API key or per-token billing. File/bash/web tool access is switched off for these calls, same as every other provider here — it's a plain text-in, text-out completion.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            UsageSummary(provider: .claudeCode)
        } header: {
            Text("Claude Code (Terminal)").font(.headline)
        }

        Section {
            if let path = CodexCLI.resolvePath() {
                Text("Found: \(path)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("The codex command wasn't found.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                    Button("Set up...") { showCodexSetup = true }
                }
            }
            Text("Runs through OpenAI's codex CLI, logged in with your ChatGPT Plus/Pro/Team account — not an API key or per-token billing. Sandbox mode is set to read-only with approvals disabled, same intent as Claude Code above: a plain text-in, text-out completion, no file/bash/web access.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            UsageSummary(provider: .openaiCode)
        } header: {
            Text("OpenAI Codex (Terminal)").font(.headline)
        }

        Section {
            HStack {
                Button("Save") {
                    let checks: [(String, String)] = [
                        (state.openaiApiKey, "OpenAI"), (state.anthropicApiKey, "Anthropic"),
                        (state.kimiApiKey, "Kimi"), (state.geminiApiKey, "Gemini"),
                        (state.deepseekApiKey, "DeepSeek"),
                    ]
                    for (key, name) in checks where key.contains("://") {
                        status = "The \(name) API key field has a URL in it, not a key — paste the actual key instead."
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
    }

    @ViewBuilder
    private var askAISection: some View {
        Section {
            Text("Reusable instructions for the Ask AI chat — write one once, give it a label, then pull it back up with the # button in the chat window instead of retyping it. Once selected, a task's instructions apply to every message in that chat until you clear it or pick a different one. Ask AI's own provider/model picker lives at the top of the Ask AI page, not here.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(editingPresetId == nil ? "Add a task" : "Editing \"\(presetLabel.isEmpty ? "Task" : presetLabel)\"")
                .font(.subheadline.weight(.medium))
            TextField("Label — e.g. Interview prep", text: $presetLabel)
            TextEditor(text: $presetPrompt)
                .frame(minHeight: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            HStack {
                Button(editingPresetId == nil ? "Add task" : "Save changes") { savePreset() }
                if editingPresetId != nil {
                    Button("Cancel", role: .cancel) {
                        cancelEditingPreset()
                        presetStatus = ""
                    }
                }
                if !presetStatus.isEmpty { Text(presetStatus).foregroundStyle(presetIsError ? .red : .secondary) }
            }
        } header: {
            Text("Ask AI — Saved tasks").font(.headline)
        }

        Section {
            if state.askPresets.isEmpty {
                Text("No saved tasks yet.").foregroundStyle(.secondary)
            } else {
                ForEach(state.askPresets) { preset in
                    presetRow(preset)
                }
            }
        }
    }

    private func presetRow(_ preset: AskPreset) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text(preset.prompt)
                    .font(.callout)
                    .textSelection(.enabled)
                HStack {
                    Button("Edit") { startEditingPreset(preset) }
                    Button("Remove", role: .destructive) { removePreset(preset) }
                }
            }
            .padding(.top, 4)
        } label: {
            Text(preset.label.isEmpty ? "Task" : preset.label).bold()
        }
    }

    private func startEditingPreset(_ preset: AskPreset) {
        editingPresetId = preset.id
        presetLabel = preset.label
        presetPrompt = preset.prompt
        presetStatus = ""
    }

    private func cancelEditingPreset() {
        editingPresetId = nil
        presetLabel = ""
        presetPrompt = ""
    }

    private func savePreset() {
        let label = presetLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = presetPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else {
            presetStatus = "Give it a label first."
            presetIsError = true
            return
        }
        guard !prompt.isEmpty else {
            presetStatus = "Write the instructions first."
            presetIsError = true
            return
        }
        let wasEditing = editingPresetId != nil
        if let editingPresetId, let index = state.askPresets.firstIndex(where: { $0.id == editingPresetId }) {
            state.askPresets[index].label = label
            state.askPresets[index].prompt = prompt
        } else {
            var preset = AskPreset()
            preset.label = label
            preset.prompt = prompt
            state.askPresets.append(preset)
        }
        state.saveAskPresets()
        cancelEditingPreset()
        presetStatus = wasEditing ? "Task updated." : "Task added."
        presetIsError = false
    }

    private func removePreset(_ preset: AskPreset) {
        state.askPresets.removeAll { $0.id == preset.id }
        state.saveAskPresets()
        if editingPresetId == preset.id {
            cancelEditingPreset()
            presetStatus = ""
        }
    }

    @ViewBuilder
    private func taskPicker(title: String, choice: Binding<TaskProviderChoice>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.medium))
            HStack {
                Picker("Provider", selection: choice.provider) {
                    ForEach(Provider.allCases, id: \.self) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 160)
                .onChange(of: choice.wrappedValue.provider) { newProvider in
                    choice.wrappedValue.model = ModelCatalog.models(for: newProvider).first ?? ""
                }

                Picker("Model", selection: choice.model) {
                    ForEach(ModelCatalog.models(for: choice.wrappedValue.provider), id: \.self) { m in
                        Text(ModelCatalog.displayName(m)).tag(m)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 220)

                TextField("or type a custom model ID", text: choice.model)
                    .labelsHidden()
                    .frame(minWidth: 140, maxWidth: 220)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var backupSection: some View {
        Section {
            Text("Reads and writes the same JSON format as the browser extension's Options → Info → Backup — export from one, import into the other, to move your CV, About Me notes, resources, applied jobs, and API keys (all four providers) across. Not automatic: run this whenever you want the two back in sync. One thing doesn't carry over either way — Addresses aren't supported in this app yet.")
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

    private var windowGlassNote: String {
        if #available(macOS 26.0, *) {
            return "Glass adds a Liquid Glass background behind the sidebar and the main content panel. Whole-window glass isn't offered — it broke this app's layout when tried."
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
