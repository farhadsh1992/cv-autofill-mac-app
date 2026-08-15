import SwiftUI

enum ResourcesTab: String, CaseIterable, Identifiable {
    case add = "Add"
    case saved = "Saved"

    var id: String { rawValue }
}

struct ResourcesView: View {
    @EnvironmentObject var state: AppState
    @State private var tab: ResourcesTab = .add

    @State private var newNoteLabel = ""
    @State private var newNoteContent = ""
    @State private var newURL = ""
    @State private var newQuickNoteLabel = ""
    @State private var newQuickNoteContent = ""
    @State private var busy = false
    @State private var status = ""
    @State private var isError = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(ResourcesTab.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            switch tab {
            case .add: addTab
            case .saved: savedTab
            }
        }
        .navigationTitle("Resources")
    }

    // ---- Add ----

    private var addTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    Text("About me / notes").font(.headline)
                    Text("Labeled notes the AI can draw on — things not in your CV, availability, preferences, whatever's useful. Used the same way as your CV everywhere in this app.")
                        .foregroundStyle(.secondary)
                    TextField("Title — e.g. Availability", text: $newNoteLabel)
                    TextEditor(text: $newNoteContent)
                        .frame(minHeight: 80)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                    Button("Add note") { addAboutMeNote() }
                }

                Divider()

                Group {
                    Text("Add a website").font(.headline)
                    Text("Its text is fetched once and saved as context.").foregroundStyle(.secondary)
                    HStack {
                        TextField("https://your-site.com", text: $newURL)
                        Button("Fetch & add") { Task { await addWebsite() } }.disabled(busy)
                    }
                }

                Divider()

                Group {
                    Text("Add a quick note").font(.headline)
                    Text("A resource note — separate from About Me above, for anything else worth the AI having as context.")
                        .foregroundStyle(.secondary)
                    TextField("Label (optional)", text: $newQuickNoteLabel)
                    TextEditor(text: $newQuickNoteContent)
                        .frame(minHeight: 80)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                    Button("Save note") { addQuickNote() }
                }

                if !status.isEmpty { Text(status).foregroundStyle(isError ? .red : .green) }
            }
            .padding()
        }
    }

    private func addAboutMeNote() {
        guard !newNoteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Write something first."
            isError = true
            return
        }
        var note = AboutMeNote()
        note.label = newNoteLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Note" : newNoteLabel
        note.content = newNoteContent
        state.aboutMeNotes.append(note)
        state.saveAboutMeNotes()
        newNoteLabel = ""
        newNoteContent = ""
        status = "Note added."
        isError = false
    }

    private func addWebsite() async {
        guard let url = URL(string: newURL), let scheme = url.scheme, scheme.hasPrefix("http") else {
            status = "That doesn't look like a valid URL."
            isError = true
            return
        }
        busy = true
        status = "Fetching..."
        isError = false
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let html = String(data: data, encoding: .utf8) ?? ""
            let text = String(HTMLTextExtractor.plainText(from: html).prefix(6000))
            let title = HTMLTextExtractor.title(from: html) ?? url.host ?? newURL
            state.resources.append(ResourceItem(label: title, url: newURL, content: text))
            state.saveResources()
            newURL = ""
            status = "Added."
        } catch {
            status = error.localizedDescription
            isError = true
        }
        busy = false
    }

    private func addQuickNote() {
        guard !newQuickNoteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Write something first."
            isError = true
            return
        }
        state.resources.append(ResourceItem(
            label: newQuickNoteLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Quick note" : newQuickNoteLabel,
            url: nil, content: newQuickNoteContent
        ))
        state.saveResources()
        newQuickNoteLabel = ""
        newQuickNoteContent = ""
        status = "Saved."
        isError = false
    }

    // ---- Saved ----

    private var savedTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("About Me Notes").font(.headline)
                if state.aboutMeNotes.isEmpty {
                    Text("None yet — add one in the Add tab.").foregroundStyle(.secondary)
                } else {
                    ForEach(state.aboutMeNotes.reversed()) { note in
                        savedRow(label: note.label, content: note.content) { removeAboutMeNote(note) }
                    }
                }

                Divider()

                Text("Resources").font(.headline)
                if state.resources.isEmpty {
                    Text("None yet — add one in the Add tab.").foregroundStyle(.secondary)
                } else {
                    ForEach(state.resources.reversed()) { r in
                        savedRow(label: r.label, content: r.content, url: r.url) { removeResource(r) }
                    }
                }
            }
            .padding()
        }
    }

    // Collapsed by default — just the title. Click to expand and see the
    // full content, matching how the browser extension's saved lists work.
    private func savedRow(label: String, content: String, url: String? = nil, remove: @escaping () -> Void) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                if let url, let u = URL(string: url) {
                    Link(url, destination: u).font(.footnote)
                }
                Text(content)
                    .font(.callout)
                    .textSelection(.enabled)
                Button("Remove", role: .destructive, action: remove)
            }
            .padding(.top, 4)
        } label: {
            Text(label).bold()
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
    }

    private func removeAboutMeNote(_ note: AboutMeNote) {
        state.aboutMeNotes.removeAll { $0.id == note.id }
        state.saveAboutMeNotes()
    }

    private func removeResource(_ r: ResourceItem) {
        state.resources.removeAll { $0.id == r.id }
        state.saveResources()
    }
}
