import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var settings: AppSettings
    @Published var cvData: CVData?
    @Published var coverLetterText: String
    @Published var aboutMeText: String
    @Published var resources: [ResourceItem]
    @Published var openaiApiKey: String
    @Published var anthropicApiKey: String
    @Published var usage: UsageLog

    init() {
        settings = Storage.loadJSON(AppSettings.self, from: "settings.json") ?? AppSettings()
        cvData = Storage.loadJSON(CVData.self, from: "cv.json")
        coverLetterText = Storage.loadText(from: "cover-letter.txt") ?? ""
        aboutMeText = Storage.loadText(from: "about-me.txt") ?? ""
        resources = Storage.loadJSON([ResourceItem].self, from: "resources.json") ?? []
        openaiApiKey = Keychain.get(forKey: "openaiApiKey") ?? ""
        anthropicApiKey = Keychain.get(forKey: "anthropicApiKey") ?? ""
        usage = Storage.loadJSON(UsageLog.self, from: "usage.json") ?? UsageLog()
    }

    func saveSettings() {
        Storage.saveJSON(settings, to: "settings.json")
        Keychain.set(openaiApiKey, forKey: "openaiApiKey")
        Keychain.set(anthropicApiKey, forKey: "anthropicApiKey")
    }

    func saveCV() {
        if let cv = cvData { Storage.saveJSON(cv, to: "cv.json") }
    }

    func clearCV() {
        cvData = nil
        Storage.deleteFile("cv.json")
    }

    func saveCoverLetter() { Storage.saveText(coverLetterText, to: "cover-letter.txt") }
    func saveAboutMe() { Storage.saveText(aboutMeText, to: "about-me.txt") }
    func saveResources() { Storage.saveJSON(resources, to: "resources.json") }

    func contextBlock() -> String {
        ContextBuilder.build(aboutMe: aboutMeText, resources: resources)
    }

    func modelFor(_ provider: Provider) -> String {
        provider == .openai ? settings.openaiModel : settings.anthropicModel
    }

    /// Builds a client for a specific provider/model, wired to record token
    /// usage automatically. Both providers can be configured and used side
    /// by side — this is how callers pick which one for a given request.
    func aiClient(provider: Provider, model: String) -> AIClient {
        AIClient(provider: provider, model: model) { [weak self] input, output in
            Task { @MainActor in
                self?.recordUsage(provider: provider, model: model, input: input, output: output)
            }
        }
    }

    /// Convenience for call sites that don't offer a per-action picker
    /// (CV parsing, cover letter PDF text extraction) — uses whichever
    /// provider is set as the default in Settings.
    var defaultAIClient: AIClient {
        aiClient(provider: settings.defaultProvider, model: modelFor(settings.defaultProvider))
    }

    func recordUsage(provider: Provider, model: String, input: Int, output: Int) {
        var stats: UsageStats
        switch provider {
        case .openai:
            stats = usage.openai[model] ?? UsageStats()
            stats.inputTokens += input
            stats.outputTokens += output
            stats.requestCount += 1
            usage.openai[model] = stats
        case .anthropic:
            stats = usage.anthropic[model] ?? UsageStats()
            stats.inputTokens += input
            stats.outputTokens += output
            stats.requestCount += 1
            usage.anthropic[model] = stats
        }
        Storage.saveJSON(usage, to: "usage.json")
    }

    func usageEntries(for provider: Provider) -> [UsageEntry] {
        let dict = provider == .openai ? usage.openai : usage.anthropic
        return dict
            .map { model, stats in
                UsageEntry(model: model, stats: stats, estimatedCost: Pricing.estimateCost(
                    provider: provider, model: model, inputTokens: stats.inputTokens, outputTokens: stats.outputTokens
                ))
            }
            .sorted { $0.model < $1.model }
    }
}
