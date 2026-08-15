import SwiftUI

struct JobsView: View {
    @EnvironmentObject var state: AppState
    @State private var newTitle = ""
    @State private var newCompany = ""
    @State private var newLocation = ""
    @State private var newRequirements = ""
    @State private var newLink = ""
    @State private var status = ""
    @State private var isError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Applied Jobs").font(.title2)
                Text("Track jobs you've applied to. Shares the same table columns as the browser extension's Jobs tab.")
                    .foregroundStyle(.secondary)

                Group {
                    Text("Add a job").font(.headline)
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
                }

                if !status.isEmpty { Text(status).foregroundStyle(isError ? .red : .green) }

                Divider()

                HStack {
                    Text("Saved jobs").font(.headline)
                    Spacer()
                    Button("Export Word + JSON") { exportFiles() }
                        .disabled(state.jobs.isEmpty)
                }
                Text("Saves \"applied jobs.docx\" and \"applied jobs.json\" straight to your Downloads folder — no dialog, each export overwrites the previous one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if state.jobs.isEmpty {
                    Text("None yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(state.jobs.reversed()) { job in
                        jobRow(job)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Jobs")
    }

    private func jobRow(_ job: JobItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.title.isEmpty ? "(no title)" : job.title).bold()
                    Text([job.company, job.location].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Remove", role: .destructive) { remove(job) }
            }
            if !job.requirements.isEmpty {
                Text(job.requirements).font(.footnote)
            }
            if !job.link.isEmpty, let url = URL(string: job.link) {
                Link(job.link, destination: url).font(.footnote).lineLimit(1)
            }
            HStack {
                Text("Results:").font(.footnote).foregroundStyle(.secondary)
                TextField("e.g. Interviewed, Rejected, Offer...", text: resultsBinding(for: job))
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
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
        status = "Added."
        isError = false
    }

    private func remove(_ job: JobItem) {
        state.jobs.removeAll { $0.id == job.id }
        state.saveJobs()
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
}
