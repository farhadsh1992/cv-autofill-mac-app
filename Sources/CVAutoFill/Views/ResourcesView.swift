import SwiftUI

struct ResourcesView: View {
    @EnvironmentObject var state: AppState
    @State private var newURL = ""
    @State private var newNoteLabel = ""
    @State private var newNoteContent = ""
    @State private var busy = false
    @State private var status = ""
    @State private var isError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Resources").font(.title2)

                Group {
                    Text("About me / notes").font(.headline)
                    Text("Free-form background the AI can draw on — used the same way as your CV everywhere in this app.")
                        .foregroundStyle(.secondary)
                    TextEditor(text: $state.aboutMeText)
                        .frame(minHeight: 100)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                    HStack {
                        Button("Save") {
                            state.saveAboutMe()
                            status = "Saved."
                            isError = false
                        }
                        Button("Clear", role: .destructive) {
                            state.aboutMeText = ""
                            state.saveAboutMe()
                        }
                    }
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
                    TextField("Label (optional)", text: $newNoteLabel)
                    TextEditor(text: $newNoteContent)
                        .frame(minHeight: 80)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                    Button("Save note") { addNote() }
                }

                if !status.isEmpty { Text(status).foregroundStyle(isError ? .red : .green) }

                Divider()

                Text("Saved resources").font(.headline)
                if state.resources.isEmpty {
                    Text("None yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(state.resources.reversed()) { r in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(r.label).bold()
                                Spacer()
                                Button("Remove") { remove(r) }
                            }
                            Text(String(r.content.prefix(160)))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Resources")
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

    private func addNote() {
        guard !newNoteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Write something first."
            isError = true
            return
        }
        state.resources.append(ResourceItem(label: newNoteLabel.isEmpty ? "Quick note" : newNoteLabel, url: nil, content: newNoteContent))
        state.saveResources()
        newNoteLabel = ""
        newNoteContent = ""
        status = "Saved."
        isError = false
    }

    private func remove(_ r: ResourceItem) {
        state.resources.removeAll { $0.id == r.id }
        state.saveResources()
    }
}
