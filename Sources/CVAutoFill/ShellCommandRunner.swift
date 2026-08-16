import Foundation

// Runs an arbitrary shell command the user typed themselves (install/login
// commands in the CLI setup guide) through their real login shell, streaming
// combined stdout+stderr live — this is the "terminal" in the setup window.
// Deliberately different from ClaudeCodeCLI/CodexCLI, which run one fixed,
// tool-restricted completion call; this runs whatever the user asks, exactly
// like they'd typed it into Terminal.app themselves (same trust boundary —
// their own local input, their own shell, their own privileges).
enum ShellCommandRunner {
    @discardableResult
    static func run(command: String, onLine: @escaping (String) -> Void) async -> Int32 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
                let process = Process()
                process.executableURL = URL(fileURLWithPath: shell)
                process.arguments = ["-l", "-c", command]

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                } catch {
                    DispatchQueue.main.async { onLine("Failed to start: \(error.localizedDescription)\n") }
                    continuation.resume(returning: -1)
                    return
                }

                // stdout and stderr are read concurrently on their own
                // threads (a single sequential loop can only drain one pipe
                // at a time, and a slow/quiet stream would starve the other)
                // — real terminals show the same non-deterministic
                // interleaving when merging two independent streams.
                let group = DispatchGroup()
                for pipe in [outPipe, errPipe] {
                    group.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        while true {
                            let chunk = pipe.fileHandleForReading.availableData
                            if chunk.isEmpty { break }
                            if let text = String(data: chunk, encoding: .utf8) {
                                DispatchQueue.main.async { onLine(text) }
                            }
                        }
                        group.leave()
                    }
                }
                group.wait()
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus)
            }
        }
    }
}
