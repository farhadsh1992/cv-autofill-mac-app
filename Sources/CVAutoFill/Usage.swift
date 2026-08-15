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

    init() {}

    // kimi/gemini were added after this struct started shipping — see the
    // matching note on AppSettings.init(from:) for why a plain synthesized
    // decoder would break loading an existing usage.json.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        openai = try c.decodeIfPresent([String: UsageStats].self, forKey: .openai) ?? [:]
        anthropic = try c.decodeIfPresent([String: UsageStats].self, forKey: .anthropic) ?? [:]
        kimi = try c.decodeIfPresent([String: UsageStats].self, forKey: .kimi) ?? [:]
        gemini = try c.decodeIfPresent([String: UsageStats].self, forKey: .gemini) ?? [:]
    }

    func dict(for provider: Provider) -> [String: UsageStats] {
        switch provider {
        case .openai: return openai
        case .anthropic: return anthropic
        case .kimi: return kimi
        case .gemini: return gemini
        }
    }

    mutating func setDict(_ dict: [String: UsageStats], for provider: Provider) {
        switch provider {
        case .openai: openai = dict
        case .anthropic: anthropic = dict
        case .kimi: kimi = dict
        case .gemini: gemini = dict
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
    static let openai = ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini", "gpt-4.1"]
    static let anthropic = ["claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5-20251001"]
    static let kimi = ["kimi-k2.5", "kimi-k3"]
    static let gemini = ["gemini-3.5-flash", "gemini-3.1-pro"]

    static func models(for provider: Provider) -> [String] {
        switch provider {
        case .openai: return openai
        case .anthropic: return anthropic
        case .kimi: return kimi
        case .gemini: return gemini
        }
    }

    static func displayName(_ model: String) -> String {
        switch model {
        case "gpt-4o-mini": return "gpt-4o-mini (fastest/cheapest)"
        case "claude-sonnet-5": return "claude-sonnet-5 (balanced)"
        case "claude-opus-5": return "claude-opus-5 (most capable)"
        case "claude-haiku-4-5-20251001": return "claude-haiku-4-5 (fastest/cheapest)"
        case "kimi-k2.5": return "kimi-k2.5 (cheapest)"
        case "kimi-k3": return "kimi-k3 (most capable)"
        case "gemini-3.5-flash": return "gemini-3.5-flash (fastest/cheapest)"
        case "gemini-3.1-pro": return "gemini-3.1-pro (most capable)"
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

    static func estimateCost(provider: Provider, model: String, inputTokens: Int, outputTokens: Int) -> Double {
        let table: [String: (input: Double, output: Double)]
        switch provider {
        case .openai: table = openai
        case .anthropic: table = anthropic
        case .kimi: table = kimi
        case .gemini: table = gemini
        }
        guard let rates = table[model] else { return 0 }
        return (Double(inputTokens) / 1_000_000 * rates.input) + (Double(outputTokens) / 1_000_000 * rates.output)
    }
}
