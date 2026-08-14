import Foundation

struct WorkExperience: Codable, Equatable {
    var title: String = ""
    var company: String = ""
    var start: String = ""
    var end: String = ""
    var description: String = ""
    var bullets: [String] = []
}

struct Education: Codable, Equatable {
    var degree: String = ""
    var institution: String = ""
    var start: String = ""
    var end: String = ""
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
