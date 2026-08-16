import Foundation

// Per-task AI instruction blocks (Prompts.swift) are editable from the
// Prompts sidebar section. nil means "use the built-in default" — only
// diverging text gets written to disk.
struct PromptOverrides: Codable, Equatable {
    var cvSchema: String?
    var coverLetterWrite: String?
    var cvTailor: String?
    var ask: String?
}

enum PromptTask: String, CaseIterable, Identifiable {
    case cvSchema, coverLetterWrite, cvTailor, ask

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cvSchema: return "Parse CV"
        case .coverLetterWrite: return "Generate cover letter"
        case .cvTailor: return "Tailor CV"
        case .ask: return "Ask AI"
        }
    }

    var subtitle: String {
        switch self {
        case .cvSchema: return "Used whenever a CV is uploaded or pasted, to extract it into structured fields."
        case .coverLetterWrite: return "Used by Generate → Generate cover letter."
        case .cvTailor: return "Used by Generate → Generate tailored CV (Word)."
        case .ask: return "Used by Ask AI."
        }
    }

    var defaultText: String {
        switch self {
        case .cvSchema: return Prompts.cvSchema
        case .coverLetterWrite: return Prompts.coverLetterWrite
        case .cvTailor: return Prompts.cvTailor
        case .ask: return Prompts.ask
        }
    }
}

extension PromptOverrides {
    func text(for task: PromptTask) -> String {
        switch task {
        case .cvSchema: return cvSchema ?? task.defaultText
        case .coverLetterWrite: return coverLetterWrite ?? task.defaultText
        case .cvTailor: return cvTailor ?? task.defaultText
        case .ask: return ask ?? task.defaultText
        }
    }

    mutating func set(_ text: String, for task: PromptTask) {
        switch task {
        case .cvSchema: cvSchema = text
        case .coverLetterWrite: coverLetterWrite = text
        case .cvTailor: cvTailor = text
        case .ask: ask = text
        }
    }

    mutating func reset(_ task: PromptTask) {
        switch task {
        case .cvSchema: cvSchema = nil
        case .coverLetterWrite: coverLetterWrite = nil
        case .cvTailor: cvTailor = nil
        case .ask: ask = nil
        }
    }

    func isOverridden(_ task: PromptTask) -> Bool {
        switch task {
        case .cvSchema: return cvSchema != nil
        case .coverLetterWrite: return coverLetterWrite != nil
        case .cvTailor: return cvTailor != nil
        case .ask: return ask != nil
        }
    }
}
