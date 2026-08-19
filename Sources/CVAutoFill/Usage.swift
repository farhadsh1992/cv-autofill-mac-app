import Foundation

struct UsageStats: Codable, Equatable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var requestCount: Int = 0
}

struct UsageLog: Codable, Equatable {
    var openai: [String: UsageStats] = [:]
    var anthropic: [String: UsageStats] = [:]
    var kimi: [String: UsageStats] = [:]
    var gemini: [String: UsageStats] = [:]
    var deepseek: [String: UsageStats] = [:]
    var claudeCode: [String: UsageStats] = [:]
    var openaiCode: [String: UsageStats] = [:]

    init() {}

    // kimi/gemini/deepseek/claudeCode/openaiCode were added after this struct
    // started shipping — see the matching note on AppSettings.init(from:) for
    // why a plain synthesized decoder would break loading an existing
    // usage.json.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        openai = try c.decodeIfPresent([String: UsageStats].self, forKey: .openai) ?? [:]
        anthropic = try c.decodeIfPresent([String: UsageStats].self, forKey: .anthropic) ?? [:]
        kimi = try c.decodeIfPresent([String: UsageStats].self, forKey: .kimi) ?? [:]
        gemini = try c.decodeIfPresent([String: UsageStats].self, forKey: .gemini) ?? [:]
        deepseek = try c.decodeIfPresent([String: UsageStats].self, forKey: .deepseek) ?? [:]
        claudeCode = try c.decodeIfPresent([String: UsageStats].self, forKey: .claudeCode) ?? [:]
        openaiCode = try c.decodeIfPresent([String: UsageStats].self, forKey: .openaiCode) ?? [:]
    }

    func dict(for provider: Provider) -> [String: UsageStats] {
        switch provider {
        case .openai: return openai
        case .anthropic: return anthropic
        case .kimi: return kimi
        case .gemini: return gemini
        case .deepseek: return deepseek
        case .claudeCode: return claudeCode
        case .openaiCode: return openaiCode
        }
    }

    mutating func setDict(_ dict: [String: UsageStats], for provider: Provider) {
        switch provider {
        case .openai: openai = dict
        case .anthropic: anthropic = dict
        case .kimi: kimi = dict
        case .gemini: gemini = dict
        case .deepseek: deepseek = dict
        case .claudeCode: claudeCode = dict
        case .openaiCode: openaiCode = dict
        }
    }
}

struct UsageEntry: Identifiable {
    var id: String { model }
    let model: String
    let stats: UsageStats
    let estimatedCost: Double
}

enum ModelCatalog {
    static let openai = ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini", "gpt-4.1", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"]
    static let anthropic = ["claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5-20251001"]
    static let kimi = ["kimi-k2.5", "kimi-k3"]
    static let gemini = ["gemini-3.5-flash", "gemini-3.1-pro"]
    static let deepseek = ["deepseek-v4-flash", "deepseek-v4-pro"]
    // Aliases the claude CLI's --model flag accepts; "default" omits the
    // flag entirely and lets the CLI pick its own default model.
    static let claudeCode = ["default", "sonnet", "opus", "haiku", "fable"]
    // codex's model aliases weren't independently verified against a live
    // install (not installed on this Mac) — "default" (omit -m, let codex's
    // own config decide) is the only option offered to avoid guessing wrong
    // model names into the picker.
    static let openaiCode = ["default"]

    static func models(for provider: Provider) -> [String] {
        switch provider {
        case .openai: return openai
        case .anthropic: return anthropic
        case .kimi: return kimi
        case .gemini: return gemini
        case .deepseek: return deepseek
        case .claudeCode: return claudeCode
        case .openaiCode: return openaiCode
        }
    }

    static func displayName(_ model: String) -> String {
        switch model {
        case "gpt-4o-mini": return "gpt-4o-mini (fastest/cheapest)"
        case "gpt-5.6-sol": return "gpt-5.6-sol (flagship)"
        case "gpt-5.6-terra": return "gpt-5.6-terra (balanced)"
        case "gpt-5.6-luna": return "gpt-5.6-luna (fast/cheap)"
        case "claude-sonnet-5": return "claude-sonnet-5 (balanced)"
        case "claude-opus-5": return "claude-opus-5 (most capable)"
        case "claude-haiku-4-5-20251001": return "claude-haiku-4-5 (fastest/cheapest)"
        case "kimi-k2.5": return "kimi-k2.5 (cheapest)"
        case "kimi-k3": return "kimi-k3 (most capable)"
        case "gemini-3.5-flash": return "gemini-3.5-flash (fastest/cheapest)"
        case "gemini-3.1-pro": return "gemini-3.1-pro (most capable)"
        case "deepseek-v4-flash": return "deepseek-v4-flash (fastest/cheapest)"
        case "deepseek-v4-pro": return "deepseek-v4-pro-0813 (most capable)"
        case "default": return "Default (whatever the CLI picks)"
        case "sonnet": return "Sonnet"
        case "opus": return "Opus"
        case "haiku": return "Haiku"
        case "fable": return "Fable"
        default: return model
        }
    }
}

// Approximate USD price per 1M tokens. Provider pricing changes over time and
// these numbers are not fetched live — treat estimated costs as a rough
// guide, not your actual bill. Check the provider's own dashboard for that.
enum Pricing {
    static let openai: [String: (input: Double, output: Double)] = [
        "gpt-4o-mini": (0.15, 0.60),
        "gpt-4o": (2.50, 10.00),
        "gpt-4.1-mini": (0.40, 1.60),
        "gpt-4.1": (2.00, 8.00),
    ]

    static let anthropic: [String: (input: Double, output: Double)] = [
        "claude-haiku-4-5-20251001": (1.00, 5.00),
        "claude-sonnet-5": (3.00, 15.00),
        "claude-opus-5": (15.00, 75.00),
    ]

    static let kimi: [String: (input: Double, output: Double)] = [
        "kimi-k2.5": (0.60, 3.00),
        "kimi-k3": (3.00, 15.00),
    ]

    static let gemini: [String: (input: Double, output: Double)] = [
        "gemini-3.5-flash": (1.50, 9.00),
        "gemini-3.1-pro": (2.00, 12.00),
    ]

    // DeepSeek bills peak/off-peak (roughly double during 01:00-04:00 and
    // 06:00-10:00 UTC) — these are the cheaper off-peak rates, so this
    // estimate runs low during peak hours rather than high the rest of the
    // day. Open-weight model, but this hosted API is still paid per token.
    static let deepseek: [String: (input: Double, output: Double)] = [
        "deepseek-v4-flash": (0.22, 0.66),
        "deepseek-v4-pro": (0.66, 1.98),
    ]

    static func estimateCost(provider: Provider, model: String, inputTokens: Int, outputTokens: Int) -> Double {
        // Both CLI-based providers run on a flat-rate subscription, not
        // per-token API billing — there's no meaningful dollar figure here.
        if provider.isCLIBased { return 0 }
        let table: [String: (input: Double, output: Double)]
        switch provider {
        case .openai: table = openai
        case .anthropic: table = anthropic
        case .kimi: table = kimi
        case .gemini: table = gemini
        case .deepseek: table = deepseek
        case .claudeCode, .openaiCode: table = [:]
        }
        guard let rates = table[model] else { return 0 }
        return (Double(inputTokens) / 1_000_000 * rates.input) + (Double(outputTokens) / 1_000_000 * rates.output)
    }
}
