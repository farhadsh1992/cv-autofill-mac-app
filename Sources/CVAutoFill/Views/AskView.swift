import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct AskChatMessage: Identifiable {
    enum Role { case user, ai, error }
    let id = UUID()
    let role: Role
    let text: String
}

private struct AskAttachment {
    let name: String
    let text: String
}

struct AskView: View {
    @EnvironmentObject var state: AppState
    @State private var question = ""
    @State private var messages: [AskChatMessage] = []
    @State private var busy = false
    @State private var status = ""
    @State private var isError = false

    // The currently selected saved task (Settings → Ask AI → Saved tasks),
    // or nil. Its prompt is attached to every message until cleared or
    // swapped — write it once, don't retype it.
    @State private var activePreset: AskPreset?
    @State private var showTasksPopover = false

    // A file staged for the *next* message only (unlike activePreset, this
    // isn't sticky — attach, send, gone).
    @State private var pendingAttachment: AskAttachment?
    @State private var showFileImporter = false

    var body: some View {
        VStack(spacing: 0) {
            topBar

            if state.settings.ask.provider.isCLIBased {
                CLITerminalToggle()
                    .padding(.horizontal)
                    .padding(.top, 6)
            }

            ZStack {
                watermark

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(messages) { message in
                                messageRow(message)
                            }
                            if busy {
                                HStack {
                                    ProgressView().controlSize(.small)
                                    Text("Thinking...").foregroundStyle(.secondary).font(.footnote)
                                }
                                .padding(.leading, 4)
                            }
                        }
                        .padding()
                        .id("bottom")
                    }
                    .onChange(of: messages.count) { _ in
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }

                if let preset = activePreset {
                    VStack {
                        activeTaskChip(preset)
                        Spacer()
                    }
                }
            }

            if !status.isEmpty {
                Text(status).foregroundStyle(isError ? .red : .secondary)
                    .font(.footnote)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

            composer
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .plainText, UTType(filenameExtension: "docx") ?? .data]
        ) { result in
            handleAttach(result)
        }
        .navigationTitle("Ask AI")
    }

    // ---- Top bar: provider/model picker ----

    private var topBar: some View {
        HStack {
            Picker("", selection: $state.settings.ask.provider) {
                ForEach(Provider.allCases, id: \.self) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .labelsHidden()
            .frame(minWidth: 160)
            .onChange(of: state.settings.ask.provider) { newProvider in
                state.settings.ask.model = ModelCatalog.models(for: newProvider).first ?? ""
                state.saveSettings()
            }

            Picker("", selection: $state.settings.ask.model) {
                ForEach(ModelCatalog.models(for: state.settings.ask.provider), id: \.self) { m in
                    Text(ModelCatalog.displayName(m)).tag(m)
                }
            }
            .labelsHidden()
            .frame(minWidth: 220)
            .onChange(of: state.settings.ask.model) { _ in state.saveSettings() }

            TextField("or type a custom model ID", text: $state.settings.ask.model)
                .labelsHidden()
                .frame(minWidth: 140, maxWidth: 220)

            Spacer()
        }
        .padding()
    }

    // ---- Watermark ----

    @ViewBuilder
    private var watermark: some View {
        if let url = Bundle.module.url(forResource: "logo", withExtension: "png"),
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 220, height: 220)
                .opacity(0.06)
                .allowsHitTesting(false)
        }
    }

    // ---- Messages ----

    private func messageRow(_ message: AskChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.role == .user { Spacer(minLength: 40) }

            Text(message.text)
                .textSelection(.enabled)
                .padding(10)
                .background(bubbleBackground(message.role))
                .foregroundStyle(message.role == .user ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(message.role == .error ? Color.red : Color.clear, lineWidth: 1)
                )

            if message.role == .ai {
                Button { copy(message.text) } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy answer")
            }

            if message.role != .user { Spacer(minLength: 40) }
        }
    }

    private func bubbleBackground(_ role: AskChatMessage.Role) -> some ShapeStyle {
        switch role {
        case .user: return AnyShapeStyle(Color(hex: state.settings.accentColorHex))
        case .ai: return AnyShapeStyle(Color.secondary.opacity(0.12))
        case .error: return AnyShapeStyle(Color.clear)
        }
    }

    // ---- Saved tasks (#) ----

    private func activeTaskChip(_ preset: AskPreset) -> some View {
        HStack(spacing: 6) {
            Text("#\(preset.label.isEmpty ? "Task" : preset.label)").font(.caption)
            Button {
                activePreset = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.secondary.opacity(0.15)))
        .padding(.top, 8)
    }

    private var tasksPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                activePreset = nil
                showTasksPopover = false
            } label: {
                Text("— No task (clear) —").italic().foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(8)

            if state.askPresets.isEmpty {
                Divider()
                Text("No saved tasks yet — add some in Settings → Ask AI.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(8)
            } else {
                ForEach(state.askPresets) { preset in
                    Divider()
                    Button {
                        activePreset = preset
                        showTasksPopover = false
                    } label: {
                        Text(preset.label.isEmpty ? "Task" : preset.label)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
            }
        }
        .frame(minWidth: 220, maxWidth: 320)
        .padding(4)
    }

    // ---- Composer ----

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let attachment = pendingAttachment {
                HStack(spacing: 6) {
                    Text("📎 \(attachment.name)").font(.caption).lineLimit(1)
                    Button {
                        pendingAttachment = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }

            HStack(alignment: .bottom) {
                Button {
                    showTasksPopover = true
                } label: {
                    Text("#").bold()
                }
                .popover(isPresented: $showTasksPopover) { tasksPopover }

                Button {
                    showFileImporter = true
                } label: {
                    Image(systemName: "paperclip")
                }
                .help("Attach a file (PDF, Word, or text)")

                TextEditor(text: $question)
                    .frame(minHeight: 34, maxHeight: 100)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))

                Button {
                    Task { await ask() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(busy || (question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingAttachment == nil))
            }
        }
        .padding()
    }

    // ---- Actions ----

    private func handleAttach(_ result: Result<URL, Error>) {
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
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Couldn't read anything from that file."
            isError = true
            return
        }
        pendingAttachment = AskAttachment(name: url.lastPathComponent, text: text)

        // Persisted the moment it's attached — not gated on actually
        // sending the message — so future questions (and every other AI
        // task) can use it without re-attaching it each time.
        var note = AboutMeNote()
        note.label = url.lastPathComponent
        note.content = text
        state.aboutMeNotes.append(note)
        state.saveAboutMeNotes()

        status = "Attached — also saved to About Me, so future questions (and other tasks) can use it too."
        isError = false
    }

    private func ask() async {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty || pendingAttachment != nil, !busy else { return }

        busy = true
        status = ""
        isError = false

        let attachment = pendingAttachment
        pendingAttachment = nil

        let displayText = attachment != nil
            ? "📎 \(attachment!.name)" + (trimmedQuestion.isEmpty ? "" : "\n\(trimmedQuestion)")
            : trimmedQuestion
        // The bubble text (including the 📎 marker) doubles as what's sent
        // back as history on later turns — not the extracted file content
        // itself, which is only ever sent fresh on the turn it's attached.
        let history = messages.filter { $0.role != .error }.map { AskHistoryEntry(role: $0.role == .user ? .user : .ai, content: $0.text) }
        messages.append(AskChatMessage(role: .user, text: displayText))
        question = ""

        do {
            let effectiveQuestion = trimmedQuestion.isEmpty ? "What can you tell me about the attached file, \(attachment?.name ?? "")?" : trimmedQuestion
            let answer = try await state.askAIClient.ask(
                question: effectiveQuestion,
                cvData: state.cvData,
                context: state.contextBlock(),
                history: history,
                presetPrompt: activePreset?.prompt,
                attachedFileName: attachment?.name,
                attachedFileText: attachment?.text,
                promptOverride: state.promptOverrides.ask
            )
            messages.append(AskChatMessage(role: .ai, text: answer.isEmpty ? "(no answer)" : answer))
        } catch {
            messages.append(AskChatMessage(role: .error, text: error.localizedDescription))
        }
        busy = false
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
