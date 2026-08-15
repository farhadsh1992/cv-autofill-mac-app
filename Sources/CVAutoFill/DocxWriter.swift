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
        var color: String? = nil
    }

    private static func paragraph(_ runs: [Run], spacingAfter: Int? = nil) -> String {
        let pPr = spacingAfter.map { "<w:pPr><w:spacing w:after=\"\($0)\"/></w:pPr>" } ?? ""
        let runsXml = runs.filter { !$0.text.isEmpty }.map { r -> String in
            let colorXml = r.color.map { "<w:color w:val=\"\($0)\"/>" } ?? ""
            let rPr = "<w:rPr>\(r.bold ? "<w:b/>" : "")\(colorXml)<w:sz w:val=\"\(r.size)\"/></w:rPr>"
            return "<w:r>\(rPr)<w:t xml:space=\"preserve\">\(xmlEscape(r.text))</w:t></w:r>"
        }.joined()
        return "<w:p>\(pPr)\(runsXml)</w:p>"
    }

    // A single inline photo paragraph referencing a relationship id already
    // declared in word/_rels/document.xml.rels. sizeEmu ~ 914400 EMU = 1 inch.
    private static func photoParagraph(relId: String, sizeEmu: Int, spacingAfter: Int) -> String {
        let pPr = "<w:pPr><w:spacing w:after=\"\(spacingAfter)\"/></w:pPr>"
        let drawing = """
        <w:drawing>
        <wp:inline distT="0" distB="0" distL="0" distR="0" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">
        <wp:extent cx="\(sizeEmu)" cy="\(sizeEmu)"/>
        <wp:docPr id="1" name="Photo"/>
        <a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
        <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
        <pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
        <pic:nvPicPr><pic:cNvPr id="1" name="Photo"/><pic:cNvPicPr/></pic:nvPicPr>
        <pic:blipFill>
        <a:blip r:embed="\(relId)" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/>
        <a:stretch><a:fillRect/></a:stretch>
        </pic:blipFill>
        <pic:spPr>
        <a:xfrm><a:off x="0" y="0"/><a:ext cx="\(sizeEmu)" cy="\(sizeEmu)"/></a:xfrm>
        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
        </pic:spPr>
        </pic:pic>
        </a:graphicData>
        </a:graphic>
        </wp:inline>
        </w:drawing>
        """
        return "<w:p>\(pPr)<w:r>\(drawing)</w:r></w:p>"
    }

    private static let imageContentType: [String: String] = [
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "bmp": "image/bmp",
    ]

    /// style: optional, extracted from an uploaded .docx via DocxStyleExtractor.
    /// Any part may be absent; the template falls back to plain black headings
    /// and no photo.
    static func generate(cv: CVData, style: DocxStyle? = nil) -> Data {
        let accent = style?.accentColorHex?.replacingOccurrences(of: "#", with: "").uppercased()
        func heading(_ text: String, size: Int = 26) -> [Run] { [Run(text: text, bold: true, size: size, color: accent)] }

        var paragraphs: [String] = []
        var mediaEntry: Entry?
        var relsXml: String?

        if let style, let photoData = style.photoData, let mime = style.photoMimeType,
           let ext = imageContentType.first(where: { $0.value == mime })?.key {
            mediaEntry = Entry(name: "word/media/image1.\(ext)", data: Array(photoData))
            paragraphs.append(photoParagraph(relId: "rId100", sizeEmu: 1_080_000, spacingAfter: 120))
            relsXml = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId100" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image1.\(ext)"/></Relationships>
            """
        }

        paragraphs.append(paragraph([Run(text: cv.full_name.isEmpty ? "Your Name" : cv.full_name, bold: true, size: 36, color: accent)], spacingAfter: 60))

        let contact = [cv.email, cv.phone, cv.location, cv.linkedin, cv.github, cv.portfolio]
            .filter { !$0.isEmpty }.joined(separator: "   |   ")
        if !contact.isEmpty { paragraphs.append(paragraph([Run(text: contact)], spacingAfter: 240)) }

        if !cv.summary.isEmpty {
            paragraphs.append(paragraph(heading("Summary"), spacingAfter: 80))
            paragraphs.append(paragraph([Run(text: cv.summary)], spacingAfter: 240))
        }

        if !cv.work_experience.isEmpty {
            paragraphs.append(paragraph(heading("Experience"), spacingAfter: 80))
            for job in cv.work_experience {
                let jobHeading = [job.title, job.company].filter { !$0.isEmpty }.joined(separator: ", ")
                let dates = [job.start, job.end].filter { !$0.isEmpty }.joined(separator: " – ")
                var headingRuns = [Run(text: jobHeading, bold: true)]
                if !dates.isEmpty { headingRuns.append(Run(text: "   (\(dates))")) }
                paragraphs.append(paragraph(headingRuns, spacingAfter: 40))

                let bullets = !job.bullets.isEmpty ? job.bullets : (job.description.isEmpty ? [] : [job.description])
                for (i, bullet) in bullets.enumerated() {
                    paragraphs.append(paragraph([Run(text: "•  \(bullet)")], spacingAfter: i == bullets.count - 1 ? 160 : 40))
                }
            }
        }

        if !cv.education.isEmpty {
            paragraphs.append(paragraph(heading("Education"), spacingAfter: 80))
            for edu in cv.education {
                let line = [edu.degree, edu.institution].filter { !$0.isEmpty }.joined(separator: ", ")
                let dates = [edu.start, edu.end].filter { !$0.isEmpty }.joined(separator: " – ")
                var runs = [Run(text: line, bold: true)]
                if !dates.isEmpty { runs.append(Run(text: "   (\(dates))")) }
                paragraphs.append(paragraph(runs, spacingAfter: 120))
            }
        }

        if !cv.skills.isEmpty {
            paragraphs.append(paragraph(heading("Skills"), spacingAfter: 80))
            paragraphs.append(paragraph([Run(text: cv.skills.joined(separator: ", "))]))
        }

        let sectPr = "<w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgMar w:top=\"1080\" w:right=\"1080\" w:bottom=\"1080\" w:left=\"1080\"/></w:sectPr>"

        let documentXml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" +
            "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">" +
            "<w:body>\(paragraphs.joined())\(sectPr)</w:body></w:document>"

        let imageDefaults = mediaEntry.map { entry -> String in
            let ext = (entry.name as NSString).pathExtension
            let ct = imageContentType[ext] ?? "image/png"
            return "<Default Extension=\"\(ext)\" ContentType=\"\(ct)\"/>"
        } ?? ""

        let contentTypesXml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" +
            "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">" +
            "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>" +
            "<Default Extension=\"xml\" ContentType=\"application/xml\"/>" +
            imageDefaults +
            "<Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/>" +
            "</Types>"

        let packageRelsXml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" +
            "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
            "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/>" +
            "</Relationships>"

        var entries = [
            Entry(name: "[Content_Types].xml", data: Array(contentTypesXml.utf8)),
            Entry(name: "_rels/.rels", data: Array(packageRelsXml.utf8)),
            Entry(name: "word/document.xml", data: Array(documentXml.utf8)),
        ]
        if let relsXml { entries.append(Entry(name: "word/_rels/document.xml.rels", data: Array(relsXml.utf8))) }
        if let mediaEntry { entries.append(mediaEntry) }

        return buildZip(entries)
    }

    // ---- Simple bordered table doc (used for the "applied jobs" export) ----

    private static func tableCell(_ text: String, widthDxa: Int, bold: Bool = false) -> String {
        let tcPr = "<w:tcPr><w:tcW w:w=\"\(widthDxa)\" w:type=\"dxa\"/></w:tcPr>"
        return "<w:tc>\(tcPr)\(paragraph([Run(text: text, bold: bold)]))</w:tc>"
    }

    private static func tableRow(_ cells: [String]) -> String { "<w:tr>\(cells.joined())</w:tr>" }

    private static func table(headers: [String], rows: [[String]], widths: [Int]) -> String {
        let grid = widths.map { "<w:gridCol w:w=\"\($0)\"/>" }.joined()
        let edges = ["top", "left", "bottom", "right", "insideH", "insideV"]
        let borders = "<w:tblBorders>" + edges.map { "<w:\($0) w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"999999\"/>" }.joined() + "</w:tblBorders>"
        let tblPr = "<w:tblPr><w:tblW w:w=\"0\" w:type=\"auto\"/>\(borders)</w:tblPr>"
        let headerRow = tableRow(zip(headers, widths).map { tableCell($0, widthDxa: $1, bold: true) })
        let dataRows = rows.map { row in tableRow(zip(row, widths).map { tableCell($0, widthDxa: $1) }) }.joined()
        return "<w:tbl>\(tblPr)<w:tblGrid>\(grid)</w:tblGrid>\(headerRow)\(dataRows)</w:tbl>"
    }

    /// jobs: applied-job rows for the landscape table export.
    // "2026-08-15" in UTC — matches the extension's `.toISOString().slice(0,10)`
    // exactly (JS's toISOString is always UTC, not local time), so the same
    // addedAt timestamp formats to the same date string on either side —
    // otherwise a job saved late at night could show different days in the
    // two apps' tables depending on which side of midnight UTC it landed on.
    private static let jobDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static func generateJobs(_ jobs: [JobItem]) -> Data {
        let headers = ["Job title", "Company", "Date", "Location", "Requirements", "Link", "Results"]
        // dxa (twentieths of a point); landscape letter minus 1" margins each side = 13680 dxa available.
        let widths = [1700, 1500, 1300, 1300, 4000, 2180, 1700]
        let rows = jobs.map {
            [$0.title, $0.company, jobDateFormatter.string(from: $0.addedAt), $0.location, $0.requirements, $0.link, $0.results]
        }

        let paragraphs = [
            paragraph([Run(text: "Applied Jobs", bold: true, size: 32)], spacingAfter: 200),
            table(headers: headers, rows: rows, widths: widths),
            // OOXML requires a paragraph after a table that's the last block in the body.
            paragraph([]),
        ]

        let sectPr = "<w:sectPr><w:pgSz w:w=\"15840\" w:h=\"12240\" w:orient=\"landscape\"/>" +
            "<w:pgMar w:top=\"1080\" w:right=\"1080\" w:bottom=\"1080\" w:left=\"1080\"/></w:sectPr>"

        let documentXml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" +
            "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">" +
            "<w:body>\(paragraphs.joined())\(sectPr)</w:body></w:document>"

        let contentTypesXml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" +
            "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">" +
            "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>" +
            "<Default Extension=\"xml\" ContentType=\"application/xml\"/>" +
            "<Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/>" +
            "</Types>"

        let packageRelsXml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" +
            "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
            "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/>" +
            "</Relationships>"

        let entries = [
            Entry(name: "[Content_Types].xml", data: Array(contentTypesXml.utf8)),
            Entry(name: "_rels/.rels", data: Array(packageRelsXml.utf8)),
            Entry(name: "word/document.xml", data: Array(documentXml.utf8)),
        ]

        return buildZip(entries)
    }
}
