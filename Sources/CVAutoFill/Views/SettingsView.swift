import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var status = ""
    @State private var isError = false

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
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }

    private var glassNote: String {
        if #available(macOS 26.0, *) {
            return "Glass uses macOS's Liquid Glass button material."
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
