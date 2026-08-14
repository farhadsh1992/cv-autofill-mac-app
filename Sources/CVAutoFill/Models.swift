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

enum Provider: String, Codable, CaseIterable, Hashable {
    case openai
    case anthropic
}

enum AppearanceMode: String, Codable, CaseIterable, Hashable {
    case system, light, dark
}

enum ButtonStyleChoice: String, Codable, CaseIterable, Hashable {
    case normal, glass
}

struct AppSettings: Codable, Equatable {
    // Both providers can be configured and used at the same time now — this
    // is just which one pre-fills the picker in Generate/Ask AI on launch.
    var defaultProvider: Provider = .openai
    var openaiModel: String = "gpt-4o-mini"
    var anthropicModel: String = "claude-sonnet-5"

    var appearanceMode: AppearanceMode = .system
    var accentColorHex: String = "#27A6F5"
    var buttonStyle: ButtonStyleChoice = .normal
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}
