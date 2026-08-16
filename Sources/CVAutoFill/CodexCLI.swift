import Foundation

// Shells out to OpenAI's `codex` CLI instead of calling the OpenAI HTTP API —
// uses whatever account is logged in via `codex login` (ChatGPT Plus/Pro/Team
// subscription), not an API key. Mirrors ClaudeCodeCLI.swift's shape and
// safety scoping (read-only, no approval prompts, plain text-in/JSON-out).
//
// Command syntax verified against OpenAI's own docs (learn.chatgpt.com/docs)
// — unlike ClaudeCodeCLI, this was NOT empirically tested against a live
// `codex` install (not installed on this Mac), since installing new global
// software wasn't something to do without asking first.
enum CodexCLI {
    struct Result {
        let text: String
        let inputTokens: Int
        let outputTokens: Int
    }

    enum CLIError: Error, LocalizedError {
        case notFound
        case processFailed(String)
        case badOutput

        var errorDescription: String? {
            switch self {
            case .notFound:
                return "Couldn't find the \"codex\" command. Install OpenAI's Codex CLI and make sure `codex login` works in Terminal, then try again."
            case .processFailed(let message):
                return "Codex CLI error: \(message)"
            case .badOutput:
                return "Codex CLI didn't return a usable response."
            }
        }
    }

    private static var cachedPath: String??

    static func resolvePath() -> String? {
        if let cached = cachedPath { return cached }
        let resolved = resolvePathUncached()
        cachedPath = resolved
        return resolved
    }

    /// Forces the next resolvePath() to re-check disk — used by "Check
    /// again" in the setup guide after installing/logging in, since the
    /// cache would otherwise hold a stale "not found" for the rest of launch.
    static func invalidateCache() {
        cachedPath = nil
    }

    private static func resolvePathUncached() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.codex/bin/codex",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "command -v codex"]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        } catch {
            return nil
        }
        return nil
    }

    /// `onLine` is called on the main thread with raw text chunks as the CLI
    /// prints progress to stderr — `codex exec` sends only its final answer
    /// to stdout, so unlike ClaudeCodeCLI there's no JSON-event stream to
    /// parse here; stderr already reads like normal terminal output.
    static func run(prompt: String, model: String, onLine: ((String) -> Void)? = nil) async throws -> Result {
        guard let codexPath = resolvePath() else { throw CLIError.notFound }

        var arguments = ["exec", "-s", "read-only", "--ask-for-approval", "never", "--skip-git-repo-check"]
        if model != "default", !model.isEmpty {
            arguments += ["-m", model]
        }
        arguments.append("-") // read the prompt from stdin

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cvautofill-codex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: codexPath)
                process.arguments = arguments
                process.currentDirectoryURL = workDir

                let stdinPipe = Pipe()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardInput = stdinPipe
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: CLIError.processFailed(error.localizedDescription))
                    return
                }

                if let onLine {
                    let commandLine = (["$ codex"] + arguments).joined(separator: " ")
                    DispatchQueue.main.async { onLine("\(commandLine)\n\n") }
                }

                if let data = prompt.data(using: .utf8) {
                    stdinPipe.fileHandleForWriting.write(data)
                }
                try? stdinPipe.fileHandleForWriting.close()

                // stderr streams live (progress text); stdout is read in
                // full at the end (the final answer, sent only once codex
                // is done — nothing to stream there).
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    while true {
                        let chunk = stderrPipe.fileHandleForReading.availableData
                        if chunk.isEmpty { break }
                        if let onLine, let text = String(data: chunk, encoding: .utf8) {
                            DispatchQueue.main.async { onLine(text) }
                        }
                    }
                    group.leave()
                }

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()

                let text = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                guard process.terminationStatus == 0 else {
                    continuation.resume(throwing: CLIError.processFailed(text.isEmpty ? "exit code \(process.terminationStatus)" : text))
                    return
                }
                guard !text.isEmpty else {
                    continuation.resume(throwing: CLIError.badOutput)
                    return
                }

                if let onLine {
                    DispatchQueue.main.async { onLine("\n[done]\n") }
                }

                // Codex CLI doesn't report token usage the way the claude
                // CLI's JSON result does — zeros here just mean "not
                // reported", not "free"; the request still counts.
                continuation.resume(returning: Result(text: text, inputTokens: 0, outputTokens: 0))
            }
        }
    }
}
