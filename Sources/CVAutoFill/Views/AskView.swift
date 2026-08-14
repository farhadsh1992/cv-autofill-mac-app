import AppKit
import SwiftUI

struct AskView: View {
    @EnvironmentObject var state: AppState
    @State private var question = ""
    @State private var answer = ""
    @State private var busy = false
    @State private var status = ""
    @State private var isError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask AI directly").font(.title2)
            Text("For when a form question is unclear or your CV doesn't obviously answer it. Uses your saved CV and resources as context, via your default provider (change it in Settings, or per-request in Generate).")
                .foregroundStyle(.secondary)
            TextEditor(text: $question)
                .frame(minHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

            HStack {
                Button("Ask") { Task { await ask() } }.disabled(busy)
                if busy { ProgressView().controlSize(.small) }
            }

            if !answer.isEmpty {
                Text(answer)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                Button("Copy answer") { copy(answer) }
            }

            if !status.isEmpty { Text(status).foregroundStyle(isError ? .red : .green) }
            Spacer()
        }
        .padding()
        .navigationTitle("Ask AI")
    }

    private func ask() async {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Type a question first."
            isError = true
            return
        }
        busy = true
        status = "Asking..."
        isError = false
        do {
            answer = try await state.defaultAIClient.ask(question: question, cvData: state.cvData, context: state.contextBlock())
            status = ""
        } catch {
            status = error.localizedDescription
            isError = true
        }
        busy = false
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
