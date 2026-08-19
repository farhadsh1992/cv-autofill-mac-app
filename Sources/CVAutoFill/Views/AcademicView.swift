import SwiftUI

enum AcademicTab: String, CaseIterable, Identifiable {
    case conferences = "Conferences"
    case journals = "Journals"

    var id: String { rawValue }
}

struct AcademicView: View {
    @EnvironmentObject var state: AppState
    @State private var tab: AcademicTab = .conferences

    // "2026-08-15" in UTC — matches Jobs' own date formatter (see
    // JobsView.jobDateFormatter / DocxWriter.jobDateFormatter for why UTC).
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            Text("Academic").font(.title2)
                .padding([.horizontal, .top])

            Picker("", selection: $tab) {
                ForEach(AcademicTab.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            switch tab {
            case .conferences: ConferencesTab()
            case .journals: JournalsTab()
            }
        }
        .navigationTitle("Academic")
    }
}

// ---- Conferences ----

private struct ConferencesTab: View {
    @EnvironmentObject var state: AppState
    @State private var newName = ""
    @State private var newDeadline = ""
    @State private var newLocation = ""
    @State private var newLink = ""
    @State private var newStatus = ""
    @State private var newNotes = ""
    @State private var status = ""
    @State private var isError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add a conference").font(.headline)
                    TextField("Name", text: $newName)
                    TextField("Deadline (e.g. 2026-03-01 or Rolling)", text: $newDeadline)
                    TextField("Location", text: $newLocation)
                    TextField("Link", text: $newLink)
                    TextField("Status (e.g. Planning to submit, Submitted, Accepted)", text: $newStatus)
                    TextEditor(text: $newNotes)
                        .frame(minHeight: 50)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                        .overlay(alignment: .topLeading) {
                            if newNotes.isEmpty {
                                Text("Notes")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                    Button("Add conference") { addConference() }
                    if !status.isEmpty { Text(status).foregroundStyle(isError ? .red : .green).font(.footnote) }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))

                HStack {
                    Text("Saved conferences").font(.headline)
                    Spacer()
                    Button("Export Word + JSON") { exportFiles() }
                        .disabled(state.conferences.isEmpty)
                }

                conferencesTable
            }
            .padding()
        }
    }

    @ViewBuilder
    private var conferencesTable: some View {
        if state.conferences.isEmpty {
            Text("No conferences saved yet.").foregroundStyle(.secondary)
        } else {
            Table(Array(state.conferences.reversed())) {
                TableColumn("Name") { c in Text(c.name) }
                    .width(min: 110, ideal: 150)
                TableColumn("Deadline") { c in Text(c.deadline) }
                    .width(min: 90, ideal: 110)
                TableColumn("Location") { c in Text(c.location) }
                    .width(min: 90, ideal: 130)
                TableColumn("Status") { c in Text(c.status) }
                    .width(min: 100, ideal: 140)
                TableColumn("Link") { c in linkCell(c.link) }
                    .width(min: 60, ideal: 70)
                TableColumn("Notes") { c in
                    TextField("Notes", text: notesBinding(for: c))
                        .textFieldStyle(.plain)
                }
                .width(min: 130, ideal: 200)
                TableColumn("") { c in
                    Button("Remove", role: .destructive) { remove(c) }
                }
                .width(70)
            }
            .frame(minHeight: 200)
        }
    }

    private func notesBinding(for item: ConferenceItem) -> Binding<String> {
        Binding(
            get: { item.notes },
            set: { newValue in
                guard let idx = state.conferences.firstIndex(where: { $0.id == item.id }) else { return }
                state.conferences[idx].notes = newValue
                state.saveConferences()
            }
        )
    }

    private func remove(_ item: ConferenceItem) {
        state.conferences.removeAll { $0.id == item.id }
        state.saveConferences()
    }

    private func addConference() {
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Add at least a name."
            isError = true
            return
        }
        var item = ConferenceItem()
        item.name = newName
        item.deadline = newDeadline
        item.location = newLocation
        item.link = newLink
        item.status = newStatus
        item.notes = newNotes
        state.conferences.append(item)
        state.saveConferences()
        newName = ""
        newDeadline = ""
        newLocation = ""
        newLink = ""
        newStatus = ""
        newNotes = ""
        status = "Added — see it in Saved conferences below."
        isError = false
    }

    private func exportFiles() {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            status = "Couldn't find your Downloads folder."
            isError = true
            return
        }
        do {
            let docxData = DocxWriter.generateConferences(state.conferences)
            try docxData.write(to: downloads.appendingPathComponent("conferences.docx"))

            let jsonData = try JSONEncoder.pretty.encode(state.conferences)
            try jsonData.write(to: downloads.appendingPathComponent("conferences.json"))

            status = "Exported to Downloads."
            isError = false
        } catch {
            status = error.localizedDescription
            isError = true
        }
    }
}

// ---- Journals ----

private struct JournalsTab: View {
    @EnvironmentObject var state: AppState
    @State private var newName = ""
    @State private var newFullName = ""
    @State private var newLink = ""
    @State private var newStatus = ""
    @State private var newNotes = ""
    @State private var status = ""
    @State private var isError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add a journal").font(.headline)
                    TextField("Name (short name / abbreviation)", text: $newName)
                    TextField("Full name", text: $newFullName)
                    TextField("Link", text: $newLink)
                    TextField("Status (e.g. Planning to submit, Submitted, Accepted)", text: $newStatus)
                    TextEditor(text: $newNotes)
                        .frame(minHeight: 50)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                        .overlay(alignment: .topLeading) {
                            if newNotes.isEmpty {
                                Text("Notes")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                    Button("Add journal") { addJournal() }
                    if !status.isEmpty { Text(status).foregroundStyle(isError ? .red : .green).font(.footnote) }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))

                HStack {
                    Text("Saved journals").font(.headline)
                    Spacer()
                    Button("Export Word + JSON") { exportFiles() }
                        .disabled(state.journals.isEmpty)
                }

                journalsTable
            }
            .padding()
        }
    }

    @ViewBuilder
    private var journalsTable: some View {
        if state.journals.isEmpty {
            Text("No journals saved yet.").foregroundStyle(.secondary)
        } else {
            Table(Array(state.journals.reversed())) {
                TableColumn("Name") { journal in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(journal.name)
                        if !journal.fullName.isEmpty {
                            Text(journal.fullName).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .width(min: 140, ideal: 220)
                TableColumn("Status") { j in Text(j.status) }
                    .width(min: 100, ideal: 140)
                TableColumn("Link") { j in linkCell(j.link) }
                    .width(min: 60, ideal: 70)
                TableColumn("Notes") { j in
                    TextField("Notes", text: notesBinding(for: j))
                        .textFieldStyle(.plain)
                }
                .width(min: 130, ideal: 200)
                TableColumn("Date") { j in Text(AcademicView.dateFormatter.string(from: j.addedAt)) }
                    .width(min: 80, ideal: 90)
                TableColumn("") { j in
                    Button("Remove", role: .destructive) { remove(j) }
                }
                .width(70)
            }
            .frame(minHeight: 200)
        }
    }

    private func notesBinding(for item: JournalItem) -> Binding<String> {
        Binding(
            get: { item.notes },
            set: { newValue in
                guard let idx = state.journals.firstIndex(where: { $0.id == item.id }) else { return }
                state.journals[idx].notes = newValue
                state.saveJournals()
            }
        )
    }

    private func remove(_ item: JournalItem) {
        state.journals.removeAll { $0.id == item.id }
        state.saveJournals()
    }

    private func addJournal() {
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Add at least a name."
            isError = true
            return
        }
        var item = JournalItem()
        item.name = newName
        item.fullName = newFullName
        item.link = newLink
        item.status = newStatus
        item.notes = newNotes
        state.journals.append(item)
        state.saveJournals()
        newName = ""
        newFullName = ""
        newLink = ""
        newStatus = ""
        newNotes = ""
        status = "Added — see it in Saved journals below."
        isError = false
    }

    private func exportFiles() {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            status = "Couldn't find your Downloads folder."
            isError = true
            return
        }
        do {
            let docxData = DocxWriter.generateJournals(state.journals)
            try docxData.write(to: downloads.appendingPathComponent("journals.docx"))

            let jsonData = try JSONEncoder.pretty.encode(state.journals)
            try jsonData.write(to: downloads.appendingPathComponent("journals.json"))

            status = "Exported to Downloads."
            isError = false
        } catch {
            status = error.localizedDescription
            isError = true
        }
    }
}

// Shared by both tabs — same link-opening button as Jobs' linkCell.
@ViewBuilder
private func linkCell(_ link: String) -> some View {
    if !link.isEmpty, let url = URL(string: link) {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Image(systemName: "arrow.up.right.square")
        }
        .buttonStyle(.plain)
        .help(link)
    } else {
        Text("")
    }
}
