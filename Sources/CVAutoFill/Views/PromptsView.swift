import SwiftUI

// Exposes the exact instruction text sent to the AI for each task
// (Prompts.swift) as editable, per-task overrides — stored in
// state.promptOverrides / prompts.json, resolved by AIClient at call time.
struct PromptsView: View {
    @EnvironmentObject var state: AppState
    @State private var drafts: [PromptTask: String] = [:]
    @State private var status: [PromptTask: String] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Prompts").font(.title2)
                Text("The exact instructions sent to the AI for each action. Edit and save to change how a task behaves. \"Reset to default\" clears your edit and goes back to the built-in instructions.")
                    .foregroundStyle(.secondary)

                ForEach(PromptTask.allCases) { task in
                    promptCard(task)
                }
            }
            .padding()
        }
        .navigationTitle("Prompts")
        .onAppear(perform: loadDrafts)
    }

    private func loadDrafts() {
        for task in PromptTask.allCases {
            drafts[task] = state.promptOverrides.text(for: task)
        }
    }

    @ViewBuilder
    private func promptCard(_ task: PromptTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(task.title).font(.headline)
                if state.promptOverrides.isOverridden(task) {
                    Text("Edited")
                        .font(.caption2)
                        .foregroundStyle(Color(hex: state.settings.menuTextColorHex))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(hex: state.settings.accentColorHex)))
                }
                Spacer()
            }
            Text(task.subtitle).font(.footnote).foregroundStyle(.secondary)

            TextEditor(text: Binding(
                get: { drafts[task] ?? task.defaultText },
                set: { drafts[task] = $0 }
            ))
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 160)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

            HStack {
                Button("Save") { save(task) }
                Button("Reset to default") { reset(task) }
                    .disabled(!state.promptOverrides.isOverridden(task))
                if let msg = status[task] {
                    Text(msg).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
    }

    private func save(_ task: PromptTask) {
        let text = (drafts[task] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text == task.defaultText {
            state.promptOverrides.reset(task)
        } else {
            state.promptOverrides.set(text, for: task)
        }
        state.savePromptOverrides()
        drafts[task] = state.promptOverrides.text(for: task)
        status[task] = "Saved."
    }

    private func reset(_ task: PromptTask) {
        state.promptOverrides.reset(task)
        state.savePromptOverrides()
        drafts[task] = task.defaultText
        status[task] = "Reset to default."
    }
}
