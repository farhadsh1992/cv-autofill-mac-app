import Foundation

struct UsageStats: Codable, Equatable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var requestCount: Int = 0
}

struct UsageLog: Codable, Equatable {
    var openai: [String: UsageStats] = [:]
    var anthropic: [String: UsageStats] = [:]
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

    static func models(for provider: Provider) -> [String] {
        provider == .openai ? openai : anthropic
    }

    static func displayName(_ model: String) -> String {
        switch model {
        case "gpt-4o-mini": return "gpt-4o-mini (fastest/cheapest)"
        case "claude-sonnet-5": return "claude-sonnet-5 (balanced)"
        case "claude-opus-5": return "claude-opus-5 (most capable)"
        case "claude-haiku-4-5-20251001": return "claude-haiku-4-5 (fastest/cheapest)"
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

    static func estimateCost(provider: Provider, model: String, inputTokens: Int, outputTokens: Int) -> Double {
        let table = provider == .openai ? openai : anthropic
        guard let rates = table[model] else { return 0 }
        return (Double(inputTokens) / 1_000_000 * rates.input) + (Double(outputTokens) / 1_000_000 * rates.output)
    }
}
