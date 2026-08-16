import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var settings: AppSettings
    @Published var cvData: CVData?
    @Published var coverLetterText: String
    @Published var aboutMeNotes: [AboutMeNote]
    @Published var resources: [ResourceItem]
    @Published var jobs: [JobItem]
    @Published var openaiApiKey: String
    @Published var anthropicApiKey: String
    @Published var kimiApiKey: String
    @Published var geminiApiKey: String
    @Published var usage: UsageLog
    @Published var cvStyle: DocxStyle
    @Published var lastAutoImportMessage: String?
    @Published var promptOverrides: PromptOverrides
    // Shared by both CLI-based providers (only one runs at a time) — the
    // panel's title just reflects whichever one is currently active.
    @Published var cliTerminalText: String = ""
    @Published var cliTerminalVisible = false
    @Published var cliTerminalProviderName: String = ""

    init() {
        settings = Storage.loadJSON(AppSettings.self, from: "settings.json") ?? AppSettings()
        cvData = Storage.loadJSON(CVData.self, from: "cv.json")
        coverLetterText = Storage.loadText(from: "cover-letter.txt") ?? ""
        aboutMeNotes = Storage.loadJSON([AboutMeNote].self, from: "about-me-notes.json") ?? []
        resources = Storage.loadJSON([ResourceItem].self, from: "resources.json") ?? []
        jobs = Storage.loadJSON([JobItem].self, from: "jobs.json") ?? []
        openaiApiKey = Keychain.get(forKey: "openaiApiKey") ?? ""
        anthropicApiKey = Keychain.get(forKey: "anthropicApiKey") ?? ""
        kimiApiKey = Keychain.get(forKey: "kimiApiKey") ?? ""
        geminiApiKey = Keychain.get(forKey: "geminiApiKey") ?? ""
        usage = Storage.loadJSON(UsageLog.self, from: "usage.json") ?? UsageLog()
        cvStyle = AppState.loadCVStyle()
        promptOverrides = Storage.loadJSON(PromptOverrides.self, from: "prompts.json") ?? PromptOverrides()
        migrateLegacyAboutMeText()
        autoImportJobsFromDownloads()
    }

    // One-time: the old design stored About Me as a single free-text file
    // (about-me.txt). If there's no notes.json yet but that legacy file
    // exists with real content, wrap it as one labeled note instead of
    // silently losing it, then remove the old file.
    private func migrateLegacyAboutMeText() {
        guard aboutMeNotes.isEmpty else { return }
        guard let legacyText = Storage.loadText(from: "about-me.txt")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !legacyText.isEmpty else { return }
        var note = AboutMeNote()
        note.label = "About me"
        note.content = legacyText
        aboutMeNotes = [note]
        Storage.saveJSON(aboutMeNotes, to: "about-me-notes.json")
        Storage.deleteFile("about-me.txt")
    }

    // Checked once per launch: if the browser extension has left an
    // "applied jobs.json" in Downloads (from Save this job / Export), pull
    // in whatever rows aren't already here by id. Safe to run every launch —
    // re-importing the same file is a no-op since nothing new matches.
    private func autoImportJobsFromDownloads() {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        let url = downloads.appendingPathComponent("applied jobs.json")
        guard let data = try? Data(contentsOf: url), let imported = JobsImport.parse(data) else { return }
        let existingIds = Set(jobs.map(\.id))
        let newOnes = imported.filter { !existingIds.contains($0.id) }
        guard !newOnes.isEmpty else { return }
        jobs.append(contentsOf: newOnes)
        saveJobs()
        lastAutoImportMessage = "Automatically added \(newOnes.count) job(s) found in Downloads/applied jobs.json."
    }

    func saveSettings() {
        Storage.saveJSON(settings, to: "settings.json")
        Keychain.set(openaiApiKey, forKey: "openaiApiKey")
        Keychain.set(anthropicApiKey, forKey: "anthropicApiKey")
        Keychain.set(kimiApiKey, forKey: "kimiApiKey")
        Keychain.set(geminiApiKey, forKey: "geminiApiKey")
    }

    func saveCV() {
        if let cv = cvData { Storage.saveJSON(cv, to: "cv.json") }
    }

    func clearCV() {
        cvData = nil
        Storage.deleteFile("cv.json")
    }

    // Photo (extracted from an uploaded .docx) as a separate binary file;
    // color + which extension the photo is in a small metadata JSON.
    private static func loadCVStyle() -> DocxStyle {
        guard let meta = Storage.loadJSON(CVStyleMeta.self, from: "cv-style.json") else { return DocxStyle() }
        var style = DocxStyle()
        style.accentColorHex = meta.accentColorHex
        style.photoMimeType = meta.photoMimeType
        if let ext = meta.photoExt {
            style.photoData = Storage.loadData(from: "cv-style-photo.\(ext)")
        }
        return style
    }

    func saveCVStyle() {
        guard !cvStyle.isEmpty else {
            clearCVStyle()
            return
        }
        var meta = CVStyleMeta(photoExt: nil, photoMimeType: cvStyle.photoMimeType, accentColorHex: cvStyle.accentColorHex)
        if let data = cvStyle.photoData, let mime = cvStyle.photoMimeType {
            let ext = DocxStyleExtractor.fileExtension(forMimeType: mime)
            meta.photoExt = ext
            Storage.saveData(data, to: "cv-style-photo.\(ext)")
        }
        Storage.saveJSON(meta, to: "cv-style.json")
    }

    func clearCVStyle() {
        cvStyle = DocxStyle()
        Storage.deleteFile("cv-style.json")
        for ext in ["png", "jpg", "jpeg", "gif", "bmp"] { Storage.deleteFile("cv-style-photo.\(ext)") }
    }

    func saveCoverLetter() { Storage.saveText(coverLetterText, to: "cover-letter.txt") }
    func saveAboutMeNotes() { Storage.saveJSON(aboutMeNotes, to: "about-me-notes.json") }
    func saveResources() { Storage.saveJSON(resources, to: "resources.json") }
    func saveJobs() { Storage.saveJSON(jobs, to: "jobs.json") }
    func savePromptOverrides() { Storage.saveJSON(promptOverrides, to: "prompts.json") }

    func contextBlock() -> String {
        ContextBuilder.build(aboutMeNotes: aboutMeNotes, resources: resources)
    }

    /// Builds a client for a specific provider/model, wired to record token
    /// usage automatically. Both providers can be configured and used side
    /// by side — this is how callers pick which one for a given request.
    func aiClient(provider: Provider, model: String) -> AIClient {
        if provider.isCLIBased {
            cliTerminalText = ""
            cliTerminalProviderName = provider.displayName
        }
        return AIClient(
            provider: provider, model: model,
            onUsage: { [weak self] input, output in
                Task { @MainActor in
                    self?.recordUsage(provider: provider, model: model, input: input, output: output)
                }
            },
            onTerminalLine: { [weak self] chunk in
                self?.appendCLITerminalText(chunk)
            }
        )
    }

    // ClaudeCodeCLI/CodexCLI already dispatch onLine to the main thread, so
    // this can run directly rather than hopping through another Task.
    func appendCLITerminalText(_ chunk: String) {
        cliTerminalText += chunk
        let maxLength = 50_000
        if cliTerminalText.count > maxLength {
            cliTerminalText = String(cliTerminalText.suffix(maxLength))
        }
    }

    /// Convenience for call sites that don't offer a per-action picker
    /// (CV parsing, cover letter PDF text extraction, Ask AI) — uses the
    /// "Other" task's provider+model from Settings → AI.
    var defaultAIClient: AIClient {
        aiClient(provider: settings.other.provider, model: settings.other.model)
    }

    var tailorCvAIClient: AIClient {
        aiClient(provider: settings.tailorCv.provider, model: settings.tailorCv.model)
    }

    var coverLetterAIClient: AIClient {
        aiClient(provider: settings.coverLetter.provider, model: settings.coverLetter.model)
    }

    func recordUsage(provider: Provider, model: String, input: Int, output: Int) {
        var dict = usage.dict(for: provider)
        var stats = dict[model] ?? UsageStats()
        stats.inputTokens += input
        stats.outputTokens += output
        stats.requestCount += 1
        dict[model] = stats
        usage.setDict(dict, for: provider)
        Storage.saveJSON(usage, to: "usage.json")
    }

    func usageEntries(for provider: Provider) -> [UsageEntry] {
        usage.dict(for: provider)
            .map { model, stats in
                UsageEntry(model: model, stats: stats, estimatedCost: Pricing.estimateCost(
                    provider: provider, model: model, inputTokens: stats.inputTokens, outputTokens: stats.outputTokens
                ))
            }
            .sorted { $0.model < $1.model }
    }
}
