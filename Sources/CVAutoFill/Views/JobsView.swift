import SwiftUI

enum JobsTab: String, CaseIterable, Identifiable {
    case saved = "Saved Jobs"
    case apply = "Apply Job"

    var id: String { rawValue }
}

struct JobsView: View {
    @EnvironmentObject var state: AppState
    @State private var tab: JobsTab = .saved
    @State private var newTitle = ""
    @State private var newCompany = ""
    @State private var newLocation = ""
    @State private var newRequirements = ""
    @State private var newLink = ""
    @State private var status = ""
    @State private var isError = false

    // "2026-08-15" in UTC — matches the extension's date format exactly (see
    // DocxWriter.jobDateFormatter for why UTC, not local time).
    static let jobDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(JobsTab.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            switch tab {
            case .saved: savedJobsTab
            case .apply: applyJobTab
            }
        }
        .navigationTitle("Jobs")
        .onAppear {
            if let message = state.lastAutoImportMessage {
                status = message
                isError = false
                state.lastAutoImportMessage = nil
            }
        }
    }

    // ---- Saved Jobs ----

    private var savedJobsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Saved jobs").font(.headline)
                    Spacer()
                    Button("Upload from extension") { uploadFromExtension() }
                    Button("Export Word + JSON") { exportFiles() }
                        .disabled(state.jobs.isEmpty)
                }
                Text("\"Upload from extension\" reads an \"applied jobs.json\" file saved by the browser extension's Save this job / Export, and adds those rows here alongside whatever's already in this table (also checked automatically every time this app opens). \"Export Word + JSON\" saves \"applied jobs.docx\" and \"applied jobs.json\" straight to your Downloads folder — no dialog, each export overwrites the previous one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !status.isEmpty { Text(status).foregroundStyle(isError ? .red : .green).font(.footnote) }
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 8)

            Divider()

            jobsTable
        }
    }

    @ViewBuilder
    private var jobsTable: some View {
        if state.jobs.isEmpty {
            VStack {
                Spacer()
                Text("No jobs saved yet.").foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Same column order as the browser extension's Jobs tab / Word export.
            Table(Array(state.jobs.reversed())) {
                TableColumn("Job title") { job in Text(job.title) }
                    .width(min: 110, ideal: 150)
                TableColumn("Company") { job in Text(job.company) }
                    .width(min: 90, ideal: 130)
                TableColumn("Date") { job in Text(Self.jobDateFormatter.string(from: job.addedAt)) }
                    .width(min: 80, ideal: 90)
                TableColumn("Location") { job in Text(job.location) }
                    .width(min: 90, ideal: 130)
                TableColumn("Requirements") { job in Text(job.requirements).lineLimit(2) }
                    .width(min: 160, ideal: 260)
                TableColumn("Link") { job in linkCell(job) }
                    .width(min: 100, ideal: 160)
                TableColumn("Results") { job in
                    TextField("e.g. Interviewed, Rejected, Offer...", text: resultsBinding(for: job))
                        .textFieldStyle(.plain)
                }
                .width(min: 130, ideal: 180)
                TableColumn("") { job in
                    Button("Remove", role: .destructive) { remove(job) }
                }
                .width(70)
            }
        }
    }

    @ViewBuilder
    private func linkCell(_ job: JobItem) -> some View {
        if !job.link.isEmpty, let url = URL(string: job.link) {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Image(systemName: "arrow.up.right.square")
            }
            .buttonStyle(.plain)
            .help(job.link)
        } else {
            Text("")
        }
    }

    private func resultsBinding(for job: JobItem) -> Binding<String> {
        Binding(
            get: { job.results },
            set: { newValue in
                guard let idx = state.jobs.firstIndex(where: { $0.id == job.id }) else { return }
                state.jobs[idx].results = newValue
                state.saveJobs()
            }
        )
    }

    private func remove(_ job: JobItem) {
        state.jobs.removeAll { $0.id == job.id }
        state.saveJobs()
    }

    private func uploadFromExtension() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose the \"applied jobs.json\" file saved by the browser extension."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard let imported = JobsImport.parse(data) else {
                status = "That doesn't look like an applied-jobs JSON file."
                isError = true
                return
            }
            let existingIds = Set(state.jobs.map(\.id))
            let newOnes = imported.filter { !existingIds.contains($0.id) }
            state.jobs.append(contentsOf: newOnes)
            state.saveJobs()
            status = "Added \(newOnes.count) job(s) from the extension" + (newOnes.count < imported.count ? " (\(imported.count - newOnes.count) already here)." : ".")
            isError = false
        } catch {
            status = "Upload failed: \(error.localizedDescription)"
            isError = true
        }
    }

    private func exportFiles() {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            status = "Couldn't find your Downloads folder."
            isError = true
            return
        }
        do {
            let docxData = DocxWriter.generateJobs(state.jobs)
            try docxData.write(to: downloads.appendingPathComponent("applied jobs.docx"))

            let jsonData = try JSONEncoder.pretty.encode(state.jobs)
            try jsonData.write(to: downloads.appendingPathComponent("applied jobs.json"))

            status = "Exported to Downloads."
            isError = false
        } catch {
            status = error.localizedDescription
            isError = true
        }
    }

    // ---- Apply Job ----

    private var applyJobTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add a job").font(.title2)
                Text("Log a job you're applying to — shows up in the Saved Jobs tab right away.")
                    .foregroundStyle(.secondary)

                TextField("Job title", text: $newTitle)
                TextField("Company", text: $newCompany)
                TextField("Location", text: $newLocation)
                TextField("Link", text: $newLink)
                TextEditor(text: $newRequirements)
                    .frame(minHeight: 60)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                    .overlay(alignment: .topLeading) {
                        if newRequirements.isEmpty {
                            Text("Requirements (short summary)")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                Button("Add job") { addJob() }

                if !status.isEmpty { Text(status).foregroundStyle(isError ? .red : .green) }
            }
            .padding()
        }
    }

    private func addJob() {
        guard !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !newCompany.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Add at least a title or company."
            isError = true
            return
        }
        var job = JobItem()
        job.title = newTitle
        job.company = newCompany
        job.location = newLocation
        job.requirements = newRequirements
        job.link = newLink
        state.jobs.append(job)
        state.saveJobs()
        newTitle = ""
        newCompany = ""
        newLocation = ""
        newRequirements = ""
        newLink = ""
        status = "Added — see it in Saved Jobs."
        isError = false
        tab = .saved
    }
}
