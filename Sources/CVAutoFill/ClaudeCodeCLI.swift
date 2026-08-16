import Foundation

// Shells out to the locally-installed `claude` CLI (Claude Code) instead of
// calling an HTTP API — uses whatever account is already logged in via
// `claude login` (Pro/Max subscription), not an API key.
//
// Always runs with --tools "" (all tools disabled) from a fresh, empty temp
// directory: this integration is used for plain text-in/JSON-out completions
// (parse CV, write cover letter, tailor CV, answer a question), the same
// shape as the other providers — it deliberately does not get bash/file/web
// tool access, so a CV-parsing prompt can't turn into an agent poking around
// the filesystem.
//
// Runs in --output-format stream-json so callers can watch it work live (the
// Prompts sidebar's terminal panel) instead of blocking silently until the
// whole response is ready.
enum ClaudeCodeCLI {
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
                return "Couldn't find the \"claude\" command. Install Claude Code (claude.ai/code) and make sure `claude login` works in Terminal, then try again."
            case .processFailed(let message):
                return "Claude Code error: \(message)"
            case .badOutput:
                return "Claude Code returned something that wasn't valid JSON."
            }
        }
    }

    // Resolved once per launch — GUI apps don't inherit a Terminal PATH, so
    // this checks common install locations first, then falls back to asking
    // the user's actual login shell (whatever $SHELL is, not assumed to be
    // zsh) to resolve it the same way Terminal would.
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
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.claude/local/claude",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "command -v claude"]
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

    /// `onLine`, when given, is called on the main thread with small text
    /// chunks as the CLI streams its response — meant to be appended
    /// directly to a growing terminal-style text view (not one call per
    /// visual line; text arrives in whatever chunks the model streams).
    static func run(prompt: String, model: String, onLine: ((String) -> Void)? = nil) async throws -> Result {
        guard let claudePath = resolvePath() else { throw CLIError.notFound }

        var arguments = ["-p", "--output-format", "stream-json", "--include-partial-messages", "--verbose", "--tools", ""]
        if model != "default", !model.isEmpty {
            arguments += ["--model", model]
        }

        // Fresh empty cwd each call — nothing for the (tool-less) session to
        // discover, and nothing left behind afterward.
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cvautofill-claude-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: claudePath)
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
                    let commandLine = (["$ claude"] + arguments.map { $0.isEmpty ? "\"\"" : $0 }).joined(separator: " ")
                    DispatchQueue.main.async { onLine("\(commandLine)\n\n") }
                }

                if let data = prompt.data(using: .utf8) {
                    stdinPipe.fileHandleForWriting.write(data)
                }
                try? stdinPipe.fileHandleForWriting.close()

                // Blocking read loop on this background thread — no locks
                // needed since everything here runs sequentially on one
                // thread; UI updates are the only thing hopped to main.
                var buffer = Data()
                var finalResultLine: [String: Any]?
                let newline = UInt8(ascii: "\n")

                while true {
                    let chunk = stdoutPipe.fileHandleForReading.availableData
                    if chunk.isEmpty { break } // EOF
                    buffer.append(chunk)
                    while let idx = buffer.firstIndex(of: newline) {
                        let lineData = Data(buffer[buffer.startIndex..<idx])
                        buffer.removeSubrange(buffer.startIndex...idx)
                        guard !lineData.isEmpty,
                              let lineJson = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
                        if let onLine, let formatted = formatStreamLine(lineJson) {
                            DispatchQueue.main.async { onLine(formatted) }
                        }
                        if lineJson["type"] as? String == "result" {
                            finalResultLine = lineJson
                        }
                    }
                }

                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    let message = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(throwing: CLIError.processFailed(message.isEmpty ? "exit code \(process.terminationStatus)" : message))
                    return
                }

                guard let result = finalResultLine else {
                    continuation.resume(throwing: CLIError.badOutput)
                    return
                }

                if (result["is_error"] as? Bool) == true {
                    let message = (result["result"] as? String) ?? "Claude Code reported an error."
                    continuation.resume(throwing: CLIError.processFailed(message))
                    return
                }

                let text = (result["result"] as? String) ?? ""
                let usage = result["usage"] as? [String: Any]
                let inputTokens = (usage?["input_tokens"] as? Int) ?? 0
                let outputTokens = (usage?["output_tokens"] as? Int) ?? 0
                continuation.resume(returning: Result(text: text, inputTokens: inputTokens, outputTokens: outputTokens))
            }
        }
    }

    // Turns one line of the CLI's stream-json output into a readable chunk
    // for the live terminal panel — text deltas are returned raw (meant to
    // be appended directly, word by word, like real streamed output);
    // everything else becomes a short bracketed status line. Returns nil
    // for events not worth surfacing (thinking signatures, rate-limit
    // pings, full message snapshots that duplicate the deltas, etc.).
    private static func formatStreamLine(_ json: [String: Any]) -> String? {
        guard let type = json["type"] as? String else { return nil }
        switch type {
        case "system":
            switch json["subtype"] as? String {
            case "init":
                let model = json["model"] as? String ?? "?"
                return "[session started — model: \(model)]\n"
            default:
                return nil
            }
        case "stream_event":
            guard let event = json["event"] as? [String: Any],
                  event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String, !text.isEmpty else { return nil }
            return text
        case "result":
            let ms = json["duration_ms"] as? Int ?? 0
            let cost = json["total_cost_usd"] as? Double ?? 0
            return String(format: "\n\n[done — %dms, ~$%.4f]\n", ms, cost)
        default:
            return nil
        }
    }
}
