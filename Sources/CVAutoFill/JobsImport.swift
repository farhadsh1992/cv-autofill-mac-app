import Foundation

// Parses the plain JSON array the browser extension writes for
// "applied jobs.json" (Save this job / Export Word + JSON). Shared by the
// Jobs view's manual "Upload from extension" button and AppState's
// check-on-launch auto-import, so both read the file the same way.
enum JobsImport {
    static func parse(_ data: Data) -> [JobItem]? {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        return array.map { o in
            var job = JobItem()
            job.id = (o["id"] as? String).flatMap { UUID(uuidString: $0) } ?? UUID()
            job.title = o["title"] as? String ?? ""
            job.company = o["company"] as? String ?? ""
            job.location = o["location"] as? String ?? ""
            job.requirements = o["requirements"] as? String ?? ""
            job.link = o["link"] as? String ?? ""
            job.results = o["results"] as? String ?? ""
            job.addedAt = parseFlexibleDate(o["addedAt"]) ?? Date()
            return job
        }
    }

    // The extension writes addedAt as epoch-ms numbers; this app's own
    // exports use ISO8601 strings — accept either.
    static func parseFlexibleDate(_ value: Any?) -> Date? {
        if let ms = value as? Double { return Date(timeIntervalSince1970: ms / 1000) }
        if let ms = value as? Int { return Date(timeIntervalSince1970: Double(ms) / 1000) }
        if let s = value as? String { return ISO8601DateFormatter().date(from: s) }
        return nil
    }
}
