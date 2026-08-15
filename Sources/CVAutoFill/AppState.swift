import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var settings: AppSettings
    @Published var cvData: CVData?
    @Published var coverLetterText: String
    @Published var aboutMeText: String
    @Published var resources: [ResourceItem]
    @Published var jobs: [JobItem]
    @Published var openaiApiKey: String
    @Published var anthropicApiKey: String
    @Published var usage: UsageLog
    @Published var cvStyle: DocxStyle
    @Published var lastAutoImportMessage: String?

    init() {
        settings = Storage.loadJSON(AppSettings.self, from: "settings.json") ?? AppSettings()
        cvData = Storage.loadJSON(CVData.self, from: "cv.json")
        coverLetterText = Storage.loadText(from: "cover-letter.txt") ?? ""
        aboutMeText = Storage.loadText(from: "about-me.txt") ?? ""
        resources = Storage.loadJSON([ResourceItem].self, from: "resources.json") ?? []
        jobs = Storage.loadJSON([JobItem].self, from: "jobs.json") ?? []
        openaiApiKey = Keychain.get(forKey: "openaiApiKey") ?? ""
        anthropicApiKey = Keychain.get(forKey: "anthropicApiKey") ?? ""
        usage = Storage.loadJSON(UsageLog.self, from: "usage.json") ?? UsageLog()
        cvStyle = AppState.loadCVStyle()
        autoImportJobsFromDownloads()
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
    func saveAboutMe() { Storage.saveText(aboutMeText, to: "about-me.txt") }
    func saveResources() { Storage.saveJSON(resources, to: "resources.json") }
    func saveJobs() { Storage.saveJSON(jobs, to: "jobs.json") }

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
