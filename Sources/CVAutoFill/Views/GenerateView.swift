import AppKit
import SwiftUI

struct GenerateView: View {
    @EnvironmentObject var state: AppState
    @State private var jobContext = ""
    @State private var coverLetterDraft = ""
    @State private var busy = false
    @State private var status = ""
    @State private var isError = false
    @State private var selectedProvider: Provider = .openai
    @State private var selectedModel: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Generate for a job").font(.title2)
                if state.cvData == nil {
                    Text("Upload a CV first, in the CV tab.").foregroundStyle(.secondary)
                }

                HStack {
                    Picker("Use", selection: $selectedProvider) {
                        Text("OpenAI").tag(Provider.openai)
                        Text("Anthropic (Claude)").tag(Provider.anthropic)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)

                    Picker("Model", selection: $selectedModel) {
                        ForEach(ModelCatalog.models(for: selectedProvider), id: \.self) { m in
                            Text(ModelCatalog.displayName(m)).tag(m)
                        }
                    }
                    .frame(maxWidth: 280)
                }
                .onChange(of: selectedProvider) { newValue in
                    selectedModel = state.modelFor(newValue)
                }

                Text("Paste the job description — title, company, requirements, whatever you have.")
                    .foregroundStyle(.secondary)
                TextEditor(text: $jobContext)
                    .frame(minHeight: 160)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

                HStack {
                    Button("Generate cover letter") { Task { await generateCoverLetter() } }
                        .disabled(state.cvData == nil || busy)
                    Button("Generate tailored CV (Word)") { Task { await generateTailoredCV() } }
                        .disabled(state.cvData == nil || busy)
                    if busy { ProgressView().controlSize(.small) }
                }

                if !coverLetterDraft.isEmpty {
                    Text("Cover letter draft").foregroundStyle(.secondary).padding(.top, 8)
                    TextEditor(text: $coverLetterDraft)
                        .frame(minHeight: 260)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                    HStack {
                        Button("Copy") { copyToClipboard(coverLetterDraft) }
                        Button("Export as PDF") { exportCoverLetterPDF() }
                    }
                }

                if !status.isEmpty { Text(status).foregroundStyle(isError ? .red : .green) }
            }
            .padding()
        }
        .navigationTitle("Generate")
        .onAppear {
            selectedProvider = state.settings.defaultProvider
            selectedModel = state.modelFor(selectedProvider)
        }
    }

    private func generateCoverLetter() async {
        guard let cv = state.cvData else { return }
        busy = true
        status = "Writing a tailored cover letter with \(selectedModel)..."
        isError = false
        do {
            let client = state.aiClient(provider: selectedProvider, model: selectedModel)
            coverLetterDraft = try await client.generateCoverLetter(
                cvData: cv,
                referenceCoverLetter: state.coverLetterText,
                jobContext: jobContext,
                context: state.contextBlock()
            )
            status = "Draft ready — review before using it."
        } catch {
            status = error.localizedDescription
            isError = true
        }
        busy = false
    }

    private func generateTailoredCV() async {
        guard let cv = state.cvData else { return }
        busy = true
        status = "Tailoring your CV for this job with \(selectedModel)..."
        isError = false
        do {
            let client = state.aiClient(provider: selectedProvider, model: selectedModel)
            let tailored = try await client.generateTailoredCV(cvData: cv, jobContext: jobContext, context: state.contextBlock())
            let data = DocxWriter.generate(cv: tailored)
            saveWithPanel(data: data, suggestedName: "\(safeName(tailored.full_name))_Tailored_CV.docx")
            status = "Tailored CV saved. Review it before sending."
        } catch {
            status = error.localizedDescription
            isError = true
        }
        busy = false
    }

    private func exportCoverLetterPDF() {
        let data = PDFExporter.makePDF(text: coverLetterDraft)
        let name = "\(safeName(state.cvData?.full_name ?? "Cover_Letter"))_Cover_Letter.pdf"
        saveWithPanel(data: data, suggestedName: name)
    }

    private func safeName(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let replaced = trimmed.replacingOccurrences(of: " ", with: "_")
        return replaced.isEmpty ? "CV" : replaced
    }

    private func saveWithPanel(data: Data, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
