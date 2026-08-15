import Foundation

// Reads/writes the same JSON shape as the browser extension's Options →
// Info → Backup (Export/Import backup) — cv-autofill-backup.json. The two
// apps' internal models differ in a few places (this app only supports
// OpenAI/Anthropic, not Kimi/Gemini; About Me is a single text field here,
// not labeled notes; there's no Addresses feature here at all) — import
// pulls in whatever maps cleanly and reports the rest as skipped rather
// than silently dropping or mangling it.
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

    @MainActor
    static func exportDictionary(state: AppState) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["exportedAt"] = ISO8601DateFormatter().string(from: Date())

        dict["providers"] = [
            "openai": ["apiKey": state.openaiApiKey, "model": state.settings.openaiModel],
            "anthropic": ["apiKey": state.anthropicApiKey, "model": state.settings.anthropicModel],
        ]
        dict["activeProvider"] = state.settings.defaultProvider.rawValue

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

        if !state.aboutMeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dict["aboutMeNotes"] = [[
                "id": UUID().uuidString,
                "label": "About me",
                "content": state.aboutMeText,
                "addedAt": ISO8601DateFormatter().string(from: Date()),
            ]]
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

        return dict
    }

    @MainActor
    static func apply(_ dict: [String: Any], to state: AppState) -> ImportResult {
        var result = ImportResult()

        if let providers = dict["providers"] as? [String: Any] {
            if let openai = providers["openai"] as? [String: Any] {
                if let key = openai["apiKey"] as? String, !key.isEmpty { state.openaiApiKey = key }
                if let model = openai["model"] as? String, !model.isEmpty { state.settings.openaiModel = model }
                result.imported.append("OpenAI key/model")
            }
            if let anthropic = providers["anthropic"] as? [String: Any] {
                if let key = anthropic["apiKey"] as? String, !key.isEmpty { state.anthropicApiKey = key }
                if let model = anthropic["model"] as? String, !model.isEmpty { state.settings.anthropicModel = model }
                result.imported.append("Anthropic key/model")
            }
            if providers["kimi"] != nil || providers["gemini"] != nil {
                result.skipped.append("Kimi/Gemini keys (not supported in this app)")
            }
        }
        if let activeProvider = dict["activeProvider"] as? String, let p = Provider(rawValue: activeProvider) {
            state.settings.defaultProvider = p
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

        if let notes = dict["aboutMeNotes"] as? [[String: Any]], !notes.isEmpty {
            state.aboutMeText = notes.map { note -> String in
                let label = note["label"] as? String ?? "Note"
                let content = note["content"] as? String ?? ""
                return "\(label):\n\(content)"
            }.joined(separator: "\n\n")
            result.imported.append("About me notes (merged into one text field)")
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

        state.saveSettings()
        state.saveCV()
        state.saveCVStyle()
        state.saveCoverLetter()
        state.saveAboutMe()
        state.saveResources()
        state.saveJobs()

        return result
    }
}
