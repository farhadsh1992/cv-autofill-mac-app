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

    init(provider: Provider, model: String, onUsage: ((Int, Int) -> Void)? = nil) {
        self.provider = provider
        self.model = model
        self.onUsage = onUsage
    }

    private var providerName: String { provider.displayName }

    private func apiKey() -> String? {
        switch provider {
        case .openai: return Keychain.get(forKey: "openaiApiKey")
        case .anthropic: return Keychain.get(forKey: "anthropicApiKey")
        case .kimi: return Keychain.get(forKey: "kimiApiKey")
        case .gemini: return Keychain.get(forKey: "geminiApiKey")
        }
    }

    private func call(text prompt: String) async throws -> [String: Any] {
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

    func parseCV(fromText text: String) async throws -> CVData {
        let prompt = "\(Prompts.cvSchema)\n\nCV TEXT:\n\(text)"
        let json = try await call(text: prompt)
        return try decodeCV(from: json)
    }

    func generateCoverLetter(cvData: CVData, referenceCoverLetter: String, jobContext: String, context: String) async throws -> String {
        let prompt = """
        \(Prompts.coverLetterWrite)

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

    func generateTailoredCV(cvData: CVData, jobContext: String, context: String) async throws -> CVData {
        let prompt = """
        \(Prompts.cvTailor)

        \(context)

        CV_DATA:
        \(try jsonString(cvData))

        JOB_CONTEXT:
        \(jobContext.isEmpty ? "(not available)" : jobContext)
        """
        let json = try await call(text: prompt)
        return try decodeCV(from: json)
    }

    func ask(question: String, cvData: CVData?, context: String) async throws -> String {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.apiError("Type a question first.")
        }
        let prompt = """
        \(Prompts.ask)

        \(context)

        CV_DATA:
        \(try jsonString(cvData ?? CVData()))

        QUESTION:
        \(question)
        """
        let json = try await call(text: prompt)
        return (json["answer"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
