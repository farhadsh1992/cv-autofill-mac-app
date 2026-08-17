import Foundation

// Custom init(from:) everywhere below because the AI occasionally returns
// JSON `null` for a field instead of "" / [] (despite the prompt asking for
// the latter). A plain synthesized Decodable throws DecodingError.valueNotFound
// for that — surfaced to the user as the wonderfully unhelpful "The data
// couldn't be read because it is missing." decodeIfPresent(...) ?? default
// treats a present-but-null value the same as a missing key: falls back
// instead of throwing.

struct WorkExperience: Codable, Equatable {
    var title: String = ""
    var company: String = ""
    var start: String = ""
    var end: String = ""
    var description: String = ""
    var bullets: [String] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        company = try c.decodeIfPresent(String.self, forKey: .company) ?? ""
        start = try c.decodeIfPresent(String.self, forKey: .start) ?? ""
        end = try c.decodeIfPresent(String.self, forKey: .end) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        bullets = try c.decodeIfPresent([String].self, forKey: .bullets) ?? []
    }
}

struct Education: Codable, Equatable {
    var degree: String = ""
    var institution: String = ""
    var start: String = ""
    var end: String = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        degree = try c.decodeIfPresent(String.self, forKey: .degree) ?? ""
        institution = try c.decodeIfPresent(String.self, forKey: .institution) ?? ""
        start = try c.decodeIfPresent(String.self, forKey: .start) ?? ""
        end = try c.decodeIfPresent(String.self, forKey: .end) ?? ""
    }
}

struct CVData: Codable, Equatable {
    var full_name: String = ""
    var email: String = ""
    var phone: String = ""
    var location: String = ""
    var linkedin: String = ""
    var github: String = ""
    var portfolio: String = ""
    var summary: String = ""
    var work_experience: [WorkExperience] = []
    var education: [Education] = []
    var skills: [String] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        full_name = try c.decodeIfPresent(String.self, forKey: .full_name) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        linkedin = try c.decodeIfPresent(String.self, forKey: .linkedin) ?? ""
        github = try c.decodeIfPresent(String.self, forKey: .github) ?? ""
        portfolio = try c.decodeIfPresent(String.self, forKey: .portfolio) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        work_experience = try c.decodeIfPresent([WorkExperience].self, forKey: .work_experience) ?? []
        education = try c.decodeIfPresent([Education].self, forKey: .education) ?? []
        skills = try c.decodeIfPresent([String].self, forKey: .skills) ?? []
    }
}

struct ResourceItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var label: String
    var url: String?
    var content: String
    var addedAt: Date = Date()
}

// Same shape as the browser extension's aboutMeNotes entries — labeled
// notes instead of one free-text blob.
struct AboutMeNote: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var label: String = "Note"
    var content: String = ""
    var addedAt: Date = Date()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? "Note"
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
    }
}

struct JobItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String = ""
    var company: String = ""
    var location: String = ""
    var requirements: String = ""
    var link: String = ""
    var results: String = ""
    var addedAt: Date = Date()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        company = try c.decodeIfPresent(String.self, forKey: .company) ?? ""
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        requirements = try c.decodeIfPresent(String.self, forKey: .requirements) ?? ""
        link = try c.decodeIfPresent(String.self, forKey: .link) ?? ""
        results = try c.decodeIfPresent(String.self, forKey: .results) ?? ""
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
    }
}

enum Provider: String, Codable, CaseIterable, Hashable {
    case openai
    case anthropic
    case kimi
    case gemini
    case deepseek
    case claudeCode
    case openaiCode

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .kimi: return "Kimi"
        case .gemini: return "Gemini"
        case .deepseek: return "DeepSeek"
        case .claudeCode: return "Claude Code (Terminal)"
        case .openaiCode: return "OpenAI Codex (Terminal)"
        }
    }

    /// Providers that shell out to a local CLI (Pro/Max or Plus/Pro
    /// subscription login) instead of calling an HTTP API with a key.
    var isCLIBased: Bool {
        self == .claudeCode || self == .openaiCode
    }
}

enum AppearanceMode: String, Codable, CaseIterable, Hashable {
    case system, light, dark
}

enum ButtonStyleChoice: String, Codable, CaseIterable, Hashable {
    case normal, glass
}

// One task's AI choice — which provider, and which of that provider's
// models. Each of the three tasks below (other/tailorCv/coverLetter) has
// its own independent instance, so the same provider can be used for two
// tasks with two different models — a single shared "this provider's
// model" setting couldn't represent that.
struct TaskProviderChoice: Codable, Equatable {
    var provider: Provider = .openai
    var model: String = "gpt-4o-mini"

    init() {}

    init(provider: Provider, model: String) {
        self.provider = provider
        self.model = model
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = try c.decodeIfPresent(Provider.self, forKey: .provider) ?? .openai
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? "gpt-4o-mini"
    }
}

struct AppSettings: Codable, Equatable {
    // Each AI action has its own independent provider+model choice, set in
    // Settings → AI — not a single blanket "default provider" anymore, and
    // not one model per provider shared across every task that happens to
    // use it. Mirrors the browser extension's "Model per action" pattern,
    // one step further (there, a task picks only the provider and follows
    // that provider's own single model; here each task also picks its own
    // model).
    var other: TaskProviderChoice = TaskProviderChoice() // Ask AI + Parse CV
    var tailorCv: TaskProviderChoice = TaskProviderChoice()
    var coverLetter: TaskProviderChoice = TaskProviderChoice()

    var appearanceMode: AppearanceMode = .system
    var accentColorHex: String = "#27A6F5"
    var menuTextColorHex: String = "#FFFFFF"
    var buttonStyle: ButtonStyleChoice = .normal
    var windowStyle: ButtonStyleChoice = .normal

    init() {}

    // Replaces the older single defaultProvider + per-provider model fields
    // (openaiModel/anthropicModel/...) — decodeIfPresent so an existing
    // settings.json from before this change loads fine, just starting all
    // three tasks at the same openai/gpt-4o-mini default rather than
    // attempting a three-way migration from one old value (see the note on
    // TaskProviderChoice for why one old value can't map cleanly to three).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        other = try c.decodeIfPresent(TaskProviderChoice.self, forKey: .other) ?? TaskProviderChoice()
        tailorCv = try c.decodeIfPresent(TaskProviderChoice.self, forKey: .tailorCv) ?? TaskProviderChoice()
        coverLetter = try c.decodeIfPresent(TaskProviderChoice.self, forKey: .coverLetter) ?? TaskProviderChoice()
        appearanceMode = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearanceMode) ?? .system
        accentColorHex = try c.decodeIfPresent(String.self, forKey: .accentColorHex) ?? "#27A6F5"
        menuTextColorHex = try c.decodeIfPresent(String.self, forKey: .menuTextColorHex) ?? "#FFFFFF"
        buttonStyle = try c.decodeIfPresent(ButtonStyleChoice.self, forKey: .buttonStyle) ?? .normal
        windowStyle = try c.decodeIfPresent(ButtonStyleChoice.self, forKey: .windowStyle) ?? .normal
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}
