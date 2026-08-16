import AppKit
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

                if state.settings.other.provider.isCLIBased {
                    CLITerminalToggle()
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

                if !state.cvStyle.isEmpty {
                    styleSection
                }
            }
            .padding()
        }
        .onAppear { syncFromState() }
        .navigationTitle("CV")
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.vertical, 4)
            Text("Photo and accent color found in your uploaded .docx — used when generating a tailored CV so it isn't just plain black-and-white text. (Only works for .docx uploads; PDFs don't expose this the same way.)")
                .foregroundStyle(.secondary)
                .font(.footnote)
            HStack(spacing: 10) {
                if let data = state.cvStyle.photoData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                if let hex = state.cvStyle.accentColorHex {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: hex))
                        .frame(width: 24, height: 24)
                    Text(hex).font(.footnote).foregroundStyle(.secondary)
                }
                Button("Clear style") { state.clearCVStyle() }
            }
        }
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
            let style = DocxStyleExtractor.extractStyle(from: url)
            if !style.isEmpty {
                state.cvStyle = style
                state.saveCVStyle()
            }
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
            let cv = try await state.defaultAIClient.parseCV(fromText: text, promptOverride: state.promptOverrides.cvSchema)
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
