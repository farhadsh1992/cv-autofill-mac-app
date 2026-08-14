import SwiftUI
import UniformTypeIdentifiers

struct CVView: View {
    @EnvironmentObject var state: AppState
    @State private var status = ""
    @State private var isError = false
    @State private var busy = false
    @State private var jsonText = ""
    @State private var pasteText = ""
    @State private var showImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your CV").font(.title2)
                Text("Upload a PDF or Word (.docx) file, or paste plain text.")
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Upload PDF / .docx / .txt") { showImporter = true }
                    if busy { ProgressView().controlSize(.small) }
                }
                .fileImporter(
                    isPresented: $showImporter,
                    allowedContentTypes: [.pdf, .plainText, UTType(filenameExtension: "docx") ?? .data]
                ) { result in
                    handleImport(result)
                }

                DisclosureGroup("Or paste CV text") {
                    TextEditor(text: $pasteText)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 100)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                    Button("Parse pasted text") { Task { await parseText(pasteText) } }
                }

                Text("Parsed CV data (JSON) — edit if the AI got something wrong, then Save.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                TextEditor(text: $jsonText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 320)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

                HStack {
                    Button("Save CV data") { saveJSON() }
                    Button("Clear CV data", role: .destructive) { clear() }
                    if !status.isEmpty {
                        Text(status).foregroundStyle(isError ? .red : .green)
                    }
                }
            }
            .padding()
        }
        .onAppear { syncFromState() }
        .navigationTitle("CV")
    }

    private func syncFromState() {
        if let cv = state.cvData, let data = try? JSONEncoder.pretty.encode(cv), let s = String(data: data, encoding: .utf8) {
            jsonText = s
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let gotAccess = url.startAccessingSecurityScopedResource()
        let ext = url.pathExtension.lowercased()
        let text: String
        if ext == "pdf" {
            text = DocumentTextExtractor.extractPDFText(url: url) ?? ""
        } else if ext == "docx" {
            text = DocumentTextExtractor.extractDocxText(url: url) ?? ""
        } else {
            text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        if gotAccess { url.stopAccessingSecurityScopedResource() }
        Task { await parseText(text) }
    }

    private func parseText(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Nothing to parse."
            isError = true
            return
        }
        busy = true
        status = "Parsing CV with AI..."
        isError = false
        do {
            let cv = try await state.defaultAIClient.parseCV(fromText: text)
            state.cvData = cv
            state.saveCV()
            syncFromState()
            status = "CV parsed and saved."
        } catch {
            status = error.localizedDescription
            isError = true
        }
        busy = false
    }

    private func saveJSON() {
        guard let data = jsonText.data(using: .utf8),
              let cv = try? JSONDecoder().decode(CVData.self, from: data)
        else {
            status = "Invalid JSON."
            isError = true
            return
        }
        state.cvData = cv
        state.saveCV()
        status = "CV data saved."
        isError = false
    }

    private func clear() {
        state.clearCV()
        jsonText = ""
        status = "CV data cleared."
        isError = false
    }
}
