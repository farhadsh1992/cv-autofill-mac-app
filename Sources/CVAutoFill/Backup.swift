import Foundation

// Reads/writes the same JSON shape as the browser extension's Options →
// Info → Backup (Export/Import backup) — cv-autofill-backup.json. The two
// apps' internal models differ in one remaining place (there's no Addresses
// feature here at all) — import pulls in whatever maps cleanly and reports
// the rest as skipped rather than silently dropping or mangling it.
//
// Built with plain [String: Any] dictionaries + JSONSerialization instead
// of matching Codable structs, since the two schemas aren't identical and
// forcing a shared Codable type would mean either app tolerating fields it
// doesn't understand — plain dictionaries handle that for free.
enum Backup {
    struct ImportResult {
        var imported: [String] = []
        var skipped: [String] = []
    }

    // The extension keeps one global model per provider (its per-task
    // pickers choose a provider only, then follow that provider's single
    // model setting) — this app now has an independent model per task, so
    // there's no single "this provider's model" left. For extension-backup
    // compatibility we still export a best-guess: whichever of the three
    // tasks currently uses this provider, first match wins, falling back to
    // the catalog's first model if none of them do.
    @MainActor
    private static func modelForExport(_ provider: Provider, state: AppState) -> String {
        for choice in [state.settings.other, state.settings.tailorCv, state.settings.coverLetter] where choice.provider == provider {
            return choice.model
        }
        return ModelCatalog.models(for: provider).first ?? ""
    }

    @MainActor
    static func exportDictionary(state: AppState) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["exportedAt"] = ISO8601DateFormatter().string(from: Date())

        dict["providers"] = [
            "openai": ["apiKey": state.openaiApiKey, "model": modelForExport(.openai, state: state)],
            "anthropic": ["apiKey": state.anthropicApiKey, "model": modelForExport(.anthropic, state: state)],
            "kimi": ["apiKey": state.kimiApiKey, "model": modelForExport(.kimi, state: state)],
            "gemini": ["apiKey": state.geminiApiKey, "model": modelForExport(.gemini, state: state)],
            // No apiKey — CLI-based providers authenticate via their own
            // local login, not a key.
            "claudeCode": ["model": modelForExport(.claudeCode, state: state)],
            "openaiCode": ["model": modelForExport(.openaiCode, state: state)],
        ]
        // Matches the extension's "activeProvider" — the general-purpose
        // provider, i.e. this app's "Other" task (Ask AI + CV parsing).
        dict["activeProvider"] = state.settings.other.provider.rawValue
        // Extension-compatible shape: provider only, no model (see note on
        // modelForExport above for why the model can't travel per-provider
        // anymore). autofill/saveJob are extension-only concepts with no
        // equivalent task here, so they're not exported.
        dict["taskProviders"] = [
            "tailorCv": state.settings.tailorCv.provider.rawValue,
            "coverLetter": state.settings.coverLetter.provider.rawValue,
        ]
        // Full-fidelity provider+model per task, for round-tripping between
        // two installs of this app without losing the model half.
        dict["macTaskSettings"] = [
            "other": ["provider": state.settings.other.provider.rawValue, "model": state.settings.other.model],
            "tailorCv": ["provider": state.settings.tailorCv.provider.rawValue, "model": state.settings.tailorCv.model],
            "coverLetter": ["provider": state.settings.coverLetter.provider.rawValue, "model": state.settings.coverLetter.model],
        ]

        if let cv = state.cvData,
           let cvData = try? JSONEncoder().encode(cv),
           let cvObj = try? JSONSerialization.jsonObject(with: cvData) {
            dict["cvData"] = cvObj
        }

        if !state.cvStyle.isEmpty {
            var style: [String: Any] = [:]
            if let hex = state.cvStyle.accentColorHex { style["accentColorHex"] = hex }
            if let data = state.cvStyle.photoData, let mime = state.cvStyle.photoMimeType {
                style["photoBase64"] = data.base64EncodedString()
                style["photoMime"] = mime
            }
            dict["cvStyle"] = style
        }

        dict["coverLetterText"] = state.coverLetterText

        dict["aboutMeNotes"] = state.aboutMeNotes.map { n -> [String: Any] in
            [
                "id": n.id.uuidString,
                "label": n.label,
                "content": n.content,
                "addedAt": ISO8601DateFormatter().string(from: n.addedAt),
            ]
        }

        dict["resources"] = state.resources.map { r -> [String: Any] in
            var o: [String: Any] = [
                "id": r.id.uuidString,
                "label": r.label,
                "content": r.content,
                "addedAt": ISO8601DateFormatter().string(from: r.addedAt),
            ]
            if let url = r.url { o["url"] = url }
            return o
        }

        dict["savedJobs"] = state.jobs.map { j -> [String: Any] in
            [
                "id": j.id.uuidString,
                "title": j.title,
                "company": j.company,
                "location": j.location,
                "requirements": j.requirements,
                "link": j.link,
                "results": j.results,
                "addedAt": ISO8601DateFormatter().string(from: j.addedAt),
            ]
        }

        dict["theme"] = state.settings.appearanceMode.rawValue
        dict["accentColor"] = state.settings.accentColorHex

        var promptOverrides: [String: Any] = [:]
        if let v = state.promptOverrides.cvSchema { promptOverrides["cvSchema"] = v }
        if let v = state.promptOverrides.coverLetterWrite { promptOverrides["coverLetterWrite"] = v }
        if let v = state.promptOverrides.cvTailor { promptOverrides["cvTailor"] = v }
        if let v = state.promptOverrides.ask { promptOverrides["ask"] = v }
        dict["promptOverrides"] = promptOverrides

        return dict
    }

    @MainActor
    static func apply(_ dict: [String: Any], to state: AppState) -> ImportResult {
        var result = ImportResult()

        var providerModelGuess: [Provider: String] = [:]
        if let providers = dict["providers"] as? [String: Any] {
            if let openai = providers["openai"] as? [String: Any] {
                if let key = openai["apiKey"] as? String, !key.isEmpty { state.openaiApiKey = key }
                if let model = openai["model"] as? String, !model.isEmpty { providerModelGuess[.openai] = model }
                result.imported.append("OpenAI key")
            }
            if let anthropic = providers["anthropic"] as? [String: Any] {
                if let key = anthropic["apiKey"] as? String, !key.isEmpty { state.anthropicApiKey = key }
                if let model = anthropic["model"] as? String, !model.isEmpty { providerModelGuess[.anthropic] = model }
                result.imported.append("Anthropic key")
            }
            if let kimi = providers["kimi"] as? [String: Any] {
                if let key = kimi["apiKey"] as? String, !key.isEmpty { state.kimiApiKey = key }
                if let model = kimi["model"] as? String, !model.isEmpty { providerModelGuess[.kimi] = model }
                result.imported.append("Kimi key")
            }
            if let gemini = providers["gemini"] as? [String: Any] {
                if let key = gemini["apiKey"] as? String, !key.isEmpty { state.geminiApiKey = key }
                if let model = gemini["model"] as? String, !model.isEmpty { providerModelGuess[.gemini] = model }
                result.imported.append("Gemini key")
            }
            if let claudeCode = providers["claudeCode"] as? [String: Any],
               let model = claudeCode["model"] as? String, !model.isEmpty {
                providerModelGuess[.claudeCode] = model
            }
            if let openaiCode = providers["openaiCode"] as? [String: Any],
               let model = openaiCode["model"] as? String, !model.isEmpty {
                providerModelGuess[.openaiCode] = model
            }
        }

        // Prefer this app's own full-fidelity block (provider + model per
        // task) when present; otherwise fall back to the extension's
        // provider-only taskProviders + activeProvider, pairing each
        // provider with the best-guess model gathered above.
        if let macTaskSettings = dict["macTaskSettings"] as? [String: Any] {
            func choice(_ key: String) -> TaskProviderChoice? {
                guard let o = macTaskSettings[key] as? [String: Any],
                      let providerRaw = o["provider"] as? String,
                      let p = Provider(rawValue: providerRaw) else { return nil }
                let model = (o["model"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? ModelCatalog.models(for: p).first ?? ""
                return TaskProviderChoice(provider: p, model: model)
            }
            if let c = choice("other") { state.settings.other = c }
            if let c = choice("tailorCv") { state.settings.tailorCv = c }
            if let c = choice("coverLetter") { state.settings.coverLetter = c }
            result.imported.append("AI task settings")
        } else {
            if let activeProvider = dict["activeProvider"] as? String, let p = Provider(rawValue: activeProvider) {
                let model = providerModelGuess[p] ?? ModelCatalog.models(for: p).first ?? ""
                state.settings.other = TaskProviderChoice(provider: p, model: model)
                result.imported.append("AI task settings")
            }
            if let taskProviders = dict["taskProviders"] as? [String: Any] {
                if let raw = taskProviders["tailorCv"] as? String, let p = Provider(rawValue: raw) {
                    let model = providerModelGuess[p] ?? ModelCatalog.models(for: p).first ?? ""
                    state.settings.tailorCv = TaskProviderChoice(provider: p, model: model)
                }
                if let raw = taskProviders["coverLetter"] as? String, let p = Provider(rawValue: raw) {
                    let model = providerModelGuess[p] ?? ModelCatalog.models(for: p).first ?? ""
                    state.settings.coverLetter = TaskProviderChoice(provider: p, model: model)
                }
            }
        }

        if let cvObj = dict["cvData"],
           let cvData = try? JSONSerialization.data(withJSONObject: cvObj),
           let cv = try? JSONDecoder().decode(CVData.self, from: cvData) {
            state.cvData = cv
            result.imported.append("CV")
        }

        if let styleObj = dict["cvStyle"] as? [String: Any] {
            var style = DocxStyle()
            style.accentColorHex = styleObj["accentColorHex"] as? String
            if let b64 = styleObj["photoBase64"] as? String, let data = Data(base64Encoded: b64) {
                style.photoData = data
                style.photoMimeType = styleObj["photoMime"] as? String
            }
            if !style.isEmpty {
                state.cvStyle = style
                result.imported.append("CV style")
            }
        }

        if let coverLetter = dict["coverLetterText"] as? String, !coverLetter.isEmpty {
            state.coverLetterText = coverLetter
            result.imported.append("Cover letter")
        }

        if let notes = dict["aboutMeNotes"] as? [[String: Any]] {
            state.aboutMeNotes = notes.map { o in
                var note = AboutMeNote()
                note.id = (o["id"] as? String).flatMap { UUID(uuidString: $0) } ?? UUID()
                note.label = o["label"] as? String ?? "Note"
                note.content = o["content"] as? String ?? ""
                note.addedAt = JobsImport.parseFlexibleDate(o["addedAt"]) ?? Date()
                return note
            }
            result.imported.append("About me notes")
        }

        if let addresses = dict["addresses"] as? [[String: Any]], !addresses.isEmpty {
            result.skipped.append("Addresses (not supported in this app)")
        }

        if let resourcesArr = dict["resources"] as? [[String: Any]] {
            state.resources = resourcesArr.map { o in
                ResourceItem(
                    id: (o["id"] as? String).flatMap { UUID(uuidString: $0) } ?? UUID(),
                    label: o["label"] as? String ?? "Note",
                    url: o["url"] as? String,
                    content: o["content"] as? String ?? "",
                    addedAt: JobsImport.parseFlexibleDate(o["addedAt"]) ?? Date()
                )
            }
            result.imported.append("Resources")
        }

        if let jobsData = try? JSONSerialization.data(withJSONObject: dict["savedJobs"] ?? []),
           let jobsArr = JobsImport.parse(jobsData) {
            state.jobs = jobsArr
            result.imported.append("Applied jobs")
        }

        if let themeRaw = dict["theme"] as? String, let mode = AppearanceMode(rawValue: themeRaw) {
            state.settings.appearanceMode = mode
        }
        if let accent = dict["accentColor"] as? String, !accent.isEmpty {
            state.settings.accentColorHex = accent
        }

        if let prompts = dict["promptOverrides"] as? [String: Any] {
            if let v = prompts["cvSchema"] as? String, !v.isEmpty { state.promptOverrides.cvSchema = v }
            if let v = prompts["coverLetterWrite"] as? String, !v.isEmpty { state.promptOverrides.coverLetterWrite = v }
            if let v = prompts["cvTailor"] as? String, !v.isEmpty { state.promptOverrides.cvTailor = v }
            if let v = prompts["ask"] as? String, !v.isEmpty { state.promptOverrides.ask = v }
            result.imported.append("Prompt overrides")
        }

        state.saveSettings()
        state.saveCV()
        state.saveCVStyle()
        state.saveCoverLetter()
        state.saveAboutMeNotes()
        state.saveResources()
        state.saveJobs()
        state.savePromptOverrides()

        return result
    }
}
