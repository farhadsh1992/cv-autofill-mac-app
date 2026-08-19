import Foundation

enum AIError: Error, LocalizedError {
    case noAPIKey(String)
    case urlShapedKey(String)
    case apiError(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .noAPIKey(let provider): return "No \(provider) API key set. Add one in Settings."
        case .urlShapedKey(let provider):
            return "The saved \(provider) API key looks like a URL, not an API key (it contains \"://\"). Go to Settings and re-paste the actual key."
        case .apiError(let msg): return msg
        case .badResponse: return "Unexpected response from the AI provider."
        }
    }
}

// One AIClient = one specific provider + model, chosen explicitly by the
// caller (Settings holds keys/defaults for both providers at once; Generate
// lets you pick which one to actually use per request).
struct AIClient {
    let provider: Provider
    let model: String
    var onUsage: ((Int, Int) -> Void)?
    // CLI-based providers only — called with text chunks as the CLI streams
    // its response, for the live terminal panel. No-op for the other providers.
    var onTerminalLine: ((String) -> Void)?

    init(provider: Provider, model: String, onUsage: ((Int, Int) -> Void)? = nil, onTerminalLine: ((String) -> Void)? = nil) {
        self.provider = provider
        self.model = model
        self.onUsage = onUsage
        self.onTerminalLine = onTerminalLine
    }

    private var providerName: String { provider.displayName }

    private func apiKey() -> String? {
        switch provider {
        case .openai: return Keychain.get(forKey: "openaiApiKey")
        case .anthropic: return Keychain.get(forKey: "anthropicApiKey")
        case .kimi: return Keychain.get(forKey: "kimiApiKey")
        case .gemini: return Keychain.get(forKey: "geminiApiKey")
        case .deepseek: return Keychain.get(forKey: "deepseekApiKey")
        case .claudeCode, .openaiCode: return nil // uses the local CLI's own login instead of a key
        }
    }

    private func call(text prompt: String) async throws -> [String: Any] {
        // CLI-based providers shell out to a local CLI, authenticated via its
        // own login (subscription, not API key) — no key check needed.
        if provider.isCLIBased {
            return try await callCLI(prompt: prompt)
        }

        guard let key = apiKey(), !key.isEmpty else {
            throw AIError.noAPIKey(providerName)
        }
        if key.contains("://") {
            throw AIError.urlShapedKey(providerName)
        }
        switch provider {
        case .openai: return try await callOpenAI(apiKey: key, prompt: prompt)
        case .anthropic: return try await callAnthropic(apiKey: key, prompt: prompt)
        case .kimi: return try await callKimi(apiKey: key, prompt: prompt)
        case .gemini: return try await callGemini(apiKey: key, prompt: prompt)
        case .deepseek: return try await callDeepSeek(apiKey: key, prompt: prompt)
        case .claudeCode, .openaiCode: return try await callCLI(prompt: prompt)
        }
    }

    private func callCLI(prompt: String) async throws -> [String: Any] {
        do {
            switch provider {
            case .claudeCode:
                let result = try await ClaudeCodeCLI.run(prompt: prompt, model: model, onLine: onTerminalLine)
                onUsage?(result.inputTokens, result.outputTokens)
                return try parseJSONLoose(result.text)
            case .openaiCode:
                let result = try await CodexCLI.run(prompt: prompt, model: model, onLine: onTerminalLine)
                onUsage?(result.inputTokens, result.outputTokens)
                return try parseJSONLoose(result.text)
            default:
                throw AIError.apiError("Not a CLI-based provider.")
            }
        } catch let error as ClaudeCodeCLI.CLIError {
            throw AIError.apiError(error.errorDescription ?? "Claude Code error.")
        } catch let error as CodexCLI.CLIError {
            throw AIError.apiError(error.errorDescription ?? "Codex CLI error.")
        }
    }

    private func callOpenAI(apiKey: String, prompt: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": model,
            "input": [["role": "user", "content": [["type": "input_text", "text": prompt]]]],
            "text": ["format": ["type": "json_object"]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw AIError.apiError("OpenAI API error \(http.statusCode): \(text.prefix(300))")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.badResponse
        }
        if let usage = json["usage"] as? [String: Any] {
            let input = (usage["input_tokens"] as? Int) ?? 0
            let output = (usage["output_tokens"] as? Int) ?? 0
            onUsage?(input, output)
        }
        return try parseJSONLoose(extractOpenAIText(json))
    }

    private func extractOpenAIText(_ json: [String: Any]) -> String {
        if let outputText = json["output_text"] as? String { return outputText }
        var parts: [String] = []
        if let output = json["output"] as? [[String: Any]] {
            for item in output {
                if let content = item["content"] as? [[String: Any]] {
                    for c in content where c["type"] as? String == "output_text" {
                        if let t = c["text"] as? String { parts.append(t) }
                    }
                }
            }
        }
        return parts.joined()
    }

    private func callAnthropic(apiKey: String, prompt: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": [["role": "user", "content": [["type": "text", "text": prompt]]]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw AIError.apiError("Anthropic API error \(http.statusCode): \(text.prefix(300))")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.badResponse
        }
        if let usage = json["usage"] as? [String: Any] {
            let input = (usage["input_tokens"] as? Int) ?? 0
            let output = (usage["output_tokens"] as? Int) ?? 0
            onUsage?(input, output)
        }
        var text = ""
        if let content = json["content"] as? [[String: Any]] {
            for c in content where c["type"] as? String == "text" {
                text += (c["text"] as? String) ?? ""
            }
        }
        return try parseJSONLoose(text)
    }

    // Kimi (Moonshot) exposes an OpenAI-compatible chat completions endpoint.
    private func callKimi(apiKey: String, prompt: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://api.moonshot.ai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "response_format": ["type": "json_object"],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw AIError.apiError("Kimi API error \(http.statusCode): \(text.prefix(300))")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.badResponse
        }
        if let usage = json["usage"] as? [String: Any] {
            let input = (usage["prompt_tokens"] as? Int) ?? 0
            let output = (usage["completion_tokens"] as? Int) ?? 0
            onUsage?(input, output)
        }
        let text = ((json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String ?? ""
        return try parseJSONLoose(text)
    }

    // DeepSeek's API is OpenAI-compatible chat completions, same shape as
    // Kimi's above. The weights are open-source, but this hosted API is
    // still billed per token like every other provider here — only
    // DeepSeek's own consumer chat app (chat.deepseek.com) is free; that's
    // a separate product from this API.
    private func callDeepSeek(apiKey: String, prompt: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "response_format": ["type": "json_object"],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw AIError.apiError("DeepSeek API error \(http.statusCode): \(text.prefix(300))")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.badResponse
        }
        if let usage = json["usage"] as? [String: Any] {
            let input = (usage["prompt_tokens"] as? Int) ?? 0
            let output = (usage["completion_tokens"] as? Int) ?? 0
            onUsage?(input, output)
        }
        let text = ((json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String ?? ""
        return try parseJSONLoose(text)
    }

    private func callGemini(apiKey: String, prompt: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": ["responseMimeType": "application/json"],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw AIError.apiError("Gemini API error \(http.statusCode): \(text.prefix(300))")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.badResponse
        }
        if let usage = json["usageMetadata"] as? [String: Any] {
            let input = (usage["promptTokenCount"] as? Int) ?? 0
            let output = (usage["candidatesTokenCount"] as? Int) ?? 0
            onUsage?(input, output)
        }
        var text = ""
        if let candidates = json["candidates"] as? [[String: Any]],
           let content = candidates.first?["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]] {
            for p in parts { text += (p["text"] as? String) ?? "" }
        }
        return try parseJSONLoose(text)
    }

    private func parseJSONLoose(_ text: String) throws -> [String: Any] {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fenceStart = t.range(of: "```") {
            let afterFence = t[fenceStart.upperBound...]
            let bodyStart = afterFence.hasPrefix("json") ? afterFence.index(afterFence.startIndex, offsetBy: 4) : afterFence.startIndex
            if let fenceEnd = t.range(of: "```", range: bodyStart..<t.endIndex) {
                t = String(t[bodyStart..<fenceEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        guard let start = t.firstIndex(of: "{"), let end = t.lastIndex(of: "}") else {
            throw AIError.apiError("The model didn't return JSON: \(t.prefix(200))")
        }
        t = String(t[start...end])
        guard let data = t.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.apiError("Couldn't parse the model's response as JSON.")
        }
        return json
    }

    private func decodeCV(from json: [String: Any]) throws -> CVData {
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(CVData.self, from: data)
    }

    private func jsonString(_ value: some Encodable) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func parseCV(fromText text: String, promptOverride: String? = nil) async throws -> CVData {
        let instructions = promptOverride ?? Prompts.cvSchema
        let prompt = "\(instructions)\n\nCV TEXT:\n\(text)"
        let json = try await call(text: prompt)
        return try decodeCV(from: json)
    }

    func generateCoverLetter(cvData: CVData, referenceCoverLetter: String, jobContext: String, context: String, promptOverride: String? = nil) async throws -> String {
        let instructions = promptOverride ?? Prompts.coverLetterWrite
        let prompt = """
        \(instructions)

        \(context)

        CV_DATA:
        \(try jsonString(cvData))

        REFERENCE_COVER_LETTER:
        \(referenceCoverLetter.isEmpty ? "(none provided — write in a clear, professional default voice)" : referenceCoverLetter)

        JOB_CONTEXT:
        \(jobContext.isEmpty ? "(not available)" : jobContext)
        """
        let json = try await call(text: prompt)
        return (json["cover_letter"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func generateTailoredCV(cvData: CVData, jobContext: String, context: String, promptOverride: String? = nil) async throws -> CVData {
        let instructions = promptOverride ?? Prompts.cvTailor
        let prompt = """
        \(instructions)

        \(context)

        CV_DATA:
        \(try jsonString(cvData))

        JOB_CONTEXT:
        \(jobContext.isEmpty ? "(not available)" : jobContext)
        """
        let json = try await call(text: prompt)
        return try decodeCV(from: json)
    }

    /// `history` is the chat's prior turns — sent fresh on every call since
    /// these are stateless HTTP APIs with no server-side memory between
    /// requests. `presetPrompt` is a saved task's instructions (Ask AI's #
    /// button), layered on top of the base ask prompt. `attachedFileText` is
    /// a file's text, already extracted locally (PDFKit for .pdf, the same
    /// way CVs are parsed — this app never sends raw PDF bytes to the AI).
    func ask(
        question: String, cvData: CVData?, context: String,
        history: [AskHistoryEntry] = [], presetPrompt: String? = nil,
        attachedFileName: String? = nil, attachedFileText: String? = nil,
        promptOverride: String? = nil
    ) async throws -> String {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.apiError("Type a question first.")
        }
        let instructions = promptOverride ?? Prompts.ask
        let historyBlock = history.map { "\($0.role == .user ? "APPLICANT" : "YOU"): \($0.content)" }.joined(separator: "\n\n")
        let trimmedPreset = presetPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let taskBlock = trimmedPreset.isEmpty ? "" : "\nTASK_INSTRUCTIONS (apply these for this conversation):\n\(trimmedPreset)\n"
        let trimmedAttachment = attachedFileText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let attachedBlock = trimmedAttachment.isEmpty ? "" : "\nATTACHED_FILE (\(attachedFileName ?? "file")):\n\(trimmedAttachment)\n"
        let prompt = """
        \(instructions)
        \(taskBlock)\(attachedBlock)
        \(context)

        CV_DATA:
        \(try jsonString(cvData ?? CVData()))

        CONVERSATION_SO_FAR:
        \(historyBlock.isEmpty ? "(none — this is the first message)" : historyBlock)

        NEW_QUESTION:
        \(question)
        """
        let json = try await call(text: prompt)
        return (json["answer"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AskHistoryEntry {
    enum Role { case user, ai }
    let role: Role
    let content: String
}
