import Foundation

// Swift port of cv_autofill_extension/lib/docx-writer.js — same minimal,
// dependency-free .docx (OOXML/ZIP) writer, kept in sync deliberately.
enum DocxWriter {
    private static let crcTable: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for n in 0..<256 {
            var c = UInt32(n)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xedb88320 ^ (c >> 1)) : (c >> 1)
            }
            table[n] = c
        }
        return table
    }()

    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for b in bytes {
            crc = crcTable[Int((crc ^ UInt32(b)) & 0xff)] ^ (crc >> 8)
        }
        return crc ^ 0xffffffff
    }

    private struct Entry { let name: String; let data: [UInt8] }

    private static func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)] }
    private static func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)]
    }

    private static func buildZip(_ entries: [Entry]) -> Data {
        var localParts: [[UInt8]] = []
        var centralParts: [[UInt8]] = []
        var offset: UInt32 = 0

        for entry in entries {
            let nameBytes = Array(entry.name.utf8)
            let data = entry.data
            let crc = crc32(data)

            var local = [UInt8]()
            local += le32(0x04034b50)
            local += le16(20)
            local += le16(0)
            local += le16(0)
            local += le16(0)
            local += le16(0x21)
            local += le32(crc)
            local += le32(UInt32(data.count))
            local += le32(UInt32(data.count))
            local += le16(UInt16(nameBytes.count))
            local += le16(0)
            local += nameBytes
            localParts.append(local)
            localParts.append(data)

            var central = [UInt8]()
            central += le32(0x02014b50)
            central += le16(20)
            central += le16(20)
            central += le16(0)
            central += le16(0)
            central += le16(0)
            central += le16(0x21)
            central += le32(crc)
            central += le32(UInt32(data.count))
            central += le32(UInt32(data.count))
            central += le16(UInt16(nameBytes.count))
            central += le16(0)
            central += le16(0)
            central += le16(0)
            central += le16(0)
            central += le32(0)
            central += le32(offset)
            central += nameBytes
            centralParts.append(central)

            offset += UInt32(local.count + data.count)
        }

        let centralStart = offset
        let centralSize = UInt32(centralParts.reduce(0) { $0 + $1.count })

        var eocd = [UInt8]()
        eocd += le32(0x06054b50)
        eocd += le16(0)
        eocd += le16(0)
        eocd += le16(UInt16(entries.count))
        eocd += le16(UInt16(entries.count))
        eocd += le32(centralSize)
        eocd += le32(centralStart)
        eocd += le16(0)

        var out = [UInt8]()
        for part in localParts { out += part }
        for part in centralParts { out += part }
        out += eocd
        return Data(out)
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private struct Run {
        let text: String
        var bold: Bool = false
        var size: Int = 22
    }

    private static func paragraph(_ runs: [Run], spacingAfter: Int? = nil) -> String {
        let pPr = spacingAfter.map { "<w:pPr><w:spacing w:after=\"\($0)\"/></w:pPr>" } ?? ""
        let runsXml = runs.filter { !$0.text.isEmpty }.map { r -> String in
            let rPr = "<w:rPr>\(r.bold ? "<w:b/>" : "")<w:sz w:val=\"\(r.size)\"/></w:rPr>"
            return "<w:r>\(rPr)<w:t xml:space=\"preserve\">\(xmlEscape(r.text))</w:t></w:r>"
        }.joined()
        return "<w:p>\(pPr)\(runsXml)</w:p>"
    }

    static func generate(cv: CVData) -> Data {
        var paragraphs: [String] = []

        paragraphs.append(paragraph([Run(text: cv.full_name.isEmpty ? "Your Name" : cv.full_name, bold: true, size: 36)], spacingAfter: 60))

        let contact = [cv.email, cv.phone, cv.location, cv.linkedin, cv.github, cv.portfolio]
            .filter { !$0.isEmpty }.joined(separator: "   |   ")
        if !contact.isEmpty { paragraphs.append(paragraph([Run(text: contact)], spacingAfter: 240)) }

        if !cv.summary.isEmpty {
            paragraphs.append(paragraph([Run(text: "Summary", bold: true, size: 26)], spacingAfter: 80))
            paragraphs.append(paragraph([Run(text: cv.summary)], spacingAfter: 240))
        }

        if !cv.work_experience.isEmpty {
            paragraphs.append(paragraph([Run(text: "Experience", bold: true, size: 26)], spacingAfter: 80))
            for job in cv.work_experience {
                let heading = [job.title, job.company].filter { !$0.isEmpty }.joined(separator: ", ")
                let dates = [job.start, job.end].filter { !$0.isEmpty }.joined(separator: " – ")
                var headingRuns = [Run(text: heading, bold: true)]
                if !dates.isEmpty { headingRuns.append(Run(text: "   (\(dates))")) }
                paragraphs.append(paragraph(headingRuns, spacingAfter: 40))

                let bullets = !job.bullets.isEmpty ? job.bullets : (job.description.isEmpty ? [] : [job.description])
                for (i, bullet) in bullets.enumerated() {
                    paragraphs.append(paragraph([Run(text: "•  \(bullet)")], spacingAfter: i == bullets.count - 1 ? 160 : 40))
                }
            }
        }

        if !cv.education.isEmpty {
            paragraphs.append(paragraph([Run(text: "Education", bold: true, size: 26)], spacingAfter: 80))
            for edu in cv.education {
                let line = [edu.degree, edu.institution].filter { !$0.isEmpty }.joined(separator: ", ")
                let dates = [edu.start, edu.end].filter { !$0.isEmpty }.joined(separator: " – ")
                var runs = [Run(text: line, bold: true)]
                if !dates.isEmpty { runs.append(Run(text: "   (\(dates))")) }
                paragraphs.append(paragraph(runs, spacingAfter: 120))
            }
        }

        if !cv.skills.isEmpty {
            paragraphs.append(paragraph([Run(text: "Skills", bold: true, size: 26)], spacingAfter: 80))
            paragraphs.append(paragraph([Run(text: cv.skills.joined(separator: ", "))]))
        }

        let sectPr = "<w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgMar w:top=\"1080\" w:right=\"1080\" w:bottom=\"1080\" w:left=\"1080\"/></w:sectPr>"

        let documentXml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" +
            "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">" +
            "<w:body>\(paragraphs.joined())\(sectPr)</w:body></w:document>"

        let contentTypesXml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" +
            "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">" +
            "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>" +
            "<Default Extension=\"xml\" ContentType=\"application/xml\"/>" +
            "<Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/>" +
            "</Types>"

        let relsXml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" +
            "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
            "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/>" +
            "</Relationships>"

        return buildZip([
            Entry(name: "[Content_Types].xml", data: Array(contentTypesXml.utf8)),
            Entry(name: "_rels/.rels", data: Array(relsXml.utf8)),
            Entry(name: "word/document.xml", data: Array(documentXml.utf8)),
        ])
    }
}
