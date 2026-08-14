import SwiftUI
import UniformTypeIdentifiers

struct CoverLetterView: View {
    @EnvironmentObject var state: AppState
    @State private var busy = false
    @State private var status = ""
    @State private var isError = false
    @State private var showImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your cover letter").font(.title2)
            Text("Upload a past cover letter (PDF or .docx), or paste/edit below. Used as a style/tone reference when generating a new one — never sent anywhere as-is.")
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

            TextEditor(text: $state.coverLetterText)
                .font(.system(.body))
                .frame(minHeight: 320)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

            HStack {
                Button("Save") {
                    state.saveCoverLetter()
                    status = "Saved."
                    isError = false
                }
                Button("Clear", role: .destructive) {
                    state.coverLetterText = ""
                    state.saveCoverLetter()
                    status = "Cleared."
                    isError = false
                }
                if !status.isEmpty { Text(status).foregroundStyle(isError ? .red : .green) }
            }
        }
        .padding()
        .navigationTitle("Cover letter")
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
        state.coverLetterText = text
        state.saveCoverLetter()
        status = "Cover letter saved."
        isError = false
    }
}
