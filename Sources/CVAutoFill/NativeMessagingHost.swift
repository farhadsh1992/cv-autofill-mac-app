import Foundation

// Lets the browser extension use this app's already-built Claude Code /
// Codex integration as a Chrome/Firefox Native Messaging host — a browser
// extension can't spawn a process itself, so the browser instead launches
// this app's own executable in this headless mode (detected by the extra
// command-line argument every native-messaging launch carries — a normal
// double-click launch from Finder gets none) to run one CLI call and hand
// the answer back, reusing the exact same ClaudeCodeCLI/CodexCLI code the
// GUI's own Claude Code / Codex providers use. Each request is a fresh,
// separate launch of this binary — it never touches the GUI app, if one
// happens to be open at the same time.
//
// Wire format (Chrome/Firefox Native Messaging protocol): a 4-byte length
// prefix in host byte order, followed by that many bytes of UTF-8 JSON.
// One request in, one response out, then exit — this is how
// chrome.runtime.sendNativeMessage launches and tears down a host.
//
// Request:  {"cli": "claude"|"codex", "model": "default"|<alias>, "prompt": "..."}
// Response: {"ok": true, "text": "..."} or {"ok": false, "error": "..."}
enum NativeMessagingHost {
    static func run() {
        guard let payload = readMessage(),
              let request = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            writeMessage(["ok": false, "error": "Couldn't read the request from the browser."])
            return
        }

        let cli = (request["cli"] as? String) ?? ""
        let model = (request["model"] as? String) ?? "default"
        let prompt = (request["prompt"] as? String) ?? ""

        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            writeMessage(["ok": false, "error": "Empty prompt."])
            return
        }
        guard cli == "claude" || cli == "codex" else {
            writeMessage(["ok": false, "error": "Unknown cli \"\(cli)\" — expected \"claude\" or \"codex\"."])
            return
        }

        // No onLine callback — nothing here ever touches DispatchQueue.main,
        // so a plain semaphore is enough (no run loop to pump, unlike the
        // GUI's live terminal panel, which does pass one).
        let semaphore = DispatchSemaphore(value: 0)
        var response: [String: Any] = ["ok": false, "error": "No response produced."]

        Task {
            do {
                let text: String
                if cli == "claude" {
                    text = try await ClaudeCodeCLI.run(prompt: prompt, model: model).text
                } else {
                    text = try await CodexCLI.run(prompt: prompt, model: model).text
                }
                response = ["ok": true, "text": text]
            } catch let error as ClaudeCodeCLI.CLIError {
                response = ["ok": false, "error": error.errorDescription ?? "Claude Code error."]
            } catch let error as CodexCLI.CLIError {
                response = ["ok": false, "error": error.errorDescription ?? "Codex CLI error."]
            } catch {
                response = ["ok": false, "error": error.localizedDescription]
            }
            semaphore.signal()
        }
        semaphore.wait()

        writeMessage(response)
    }

    private static func readMessage() -> Data? {
        let stdin = FileHandle.standardInput
        guard let lengthData = try? stdin.read(upToCount: 4), lengthData.count == 4 else { return nil }
        let length = lengthData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        guard length > 0, length < 50_000_000 else { return nil }
        return try? stdin.read(upToCount: Int(length))
    }

    private static func writeMessage(_ dict: [String: Any]) {
        guard let json = try? JSONSerialization.data(withJSONObject: dict) else { return }
        var length = UInt32(json.count)
        let lengthData = Data(bytes: &length, count: 4)
        FileHandle.standardOutput.write(lengthData)
        FileHandle.standardOutput.write(json)
    }
}
