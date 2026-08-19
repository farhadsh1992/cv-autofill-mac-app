import AppKit
import SwiftUI

struct GenerateView: View {
    @EnvironmentObject var state: AppState
    @State private var jobContext = ""
    @State private var coverLetterDraft = ""
    @State private var busy = false
    @State private var status = ""
    @State private var isError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Generate for a job").font(.title2)
                if state.cvData == nil {
                    Text("Upload a CV first, in the CV tab.").foregroundStyle(.secondary)
                }

                Text("Uses the provider and model set for \"Rebuild / tailor CV\" and \"Rebuild / write cover letter\" in Settings → AI.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if state.settings.tailorCv.provider.isCLIBased || state.settings.coverLetter.provider.isCLIBased {
                    CLITerminalToggle()
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
                        Button("Export as Word") { exportCoverLetterDocx() }
                    }
                }

                if !status.isEmpty { Text(status).foregroundStyle(isError ? .red : .green) }
            }
            .padding()
        }
        .navigationTitle("Generate")
    }

    private func generateCoverLetter() async {
        guard let cv = state.cvData else { return }
        busy = true
        status = "Writing a tailored cover letter with \(state.settings.coverLetter.model)..."
        isError = false
        do {
            let client = state.coverLetterAIClient
            coverLetterDraft = try await client.generateCoverLetter(
                cvData: cv,
                referenceCoverLetter: state.coverLetterText,
                jobContext: jobContext,
                context: state.contextBlock(),
                promptOverride: state.promptOverrides.coverLetterWrite
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
        status = "Tailoring your CV for this job with \(state.settings.tailorCv.model)..."
        isError = false
        do {
            let client = state.tailorCvAIClient
            let tailored = try await client.generateTailoredCV(cvData: cv, jobContext: jobContext, context: state.contextBlock(), promptOverride: state.promptOverrides.cvTailor)
            let data = DocxWriter.generate(cv: tailored, style: state.cvStyle)
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

    private func exportCoverLetterDocx() {
        let data = DocxWriter.generateCoverLetter(coverLetterDraft)
        let name = "\(safeName(state.cvData?.full_name ?? "Cover_Letter"))_Cover_Letter.docx"
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
