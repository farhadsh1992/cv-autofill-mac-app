import Compression
import Foundation

// Best-effort style extraction from an uploaded .docx: an embedded photo
// (word/media/imageN.*) and an accent color (theme, or repeated run
// colors). Hand-rolled ZIP reader — same approach as lib/docx.js on the
// extension side, kept in sync deliberately. Verified that Apple's
// Compression framework's COMPRESSION_ZLIB algorithm decodes raw DEFLATE
// (the format ZIP entries use, no zlib/gzip wrapper) before relying on it
// here — no need to link libz manually.

struct DocxStyle: Equatable {
    var photoData: Data?
    var photoMimeType: String?
    var accentColorHex: String?

    var isEmpty: Bool { photoData == nil && accentColorHex == nil }
}

struct CVStyleMeta: Codable {
    var photoExt: String?
    var photoMimeType: String?
    var accentColorHex: String?
}

enum DocxStyleExtractor {
    private struct ZipEntry {
        let name: String
        let compMethod: UInt16
        let compSize: UInt32
        let localHeaderOffset: UInt32
    }

    private static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[data.startIndex + offset]) | (UInt16(data[data.startIndex + offset + 1]) << 8)
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[data.startIndex + offset])
            | (UInt32(data[data.startIndex + offset + 1]) << 8)
            | (UInt32(data[data.startIndex + offset + 2]) << 16)
            | (UInt32(data[data.startIndex + offset + 3]) << 24)
    }

    private static func parseEntries(_ data: Data) -> [ZipEntry] {
        let count = data.count
        guard count >= 22 else { return [] }
        let maxBack = min(count, 65557)
        var eocdOffset = -1
        var i = count - 22
        while i >= count - maxBack, i >= 0 {
            if u32(data, i) == 0x0605_4b50 {
                eocdOffset = i
                break
            }
            i -= 1
        }
        guard eocdOffset >= 0 else { return [] }

        let cdOffset = Int(u32(data, eocdOffset + 16))
        let entryCount = Int(u16(data, eocdOffset + 10))

        var entries: [ZipEntry] = []
        var pos = cdOffset
        for _ in 0..<entryCount {
            guard pos + 46 <= count, u32(data, pos) == 0x0201_4b50 else { break }
            let compMethod = u16(data, pos + 10)
            let compSize = u32(data, pos + 20)
            let nameLen = Int(u16(data, pos + 28))
            let extraLen = Int(u16(data, pos + 30))
            let commentLen = Int(u16(data, pos + 32))
            let localHeaderOffset = u32(data, pos + 42)
            guard pos + 46 + nameLen <= count else { break }
            let nameData = data.subdata(in: (data.startIndex + pos + 46)..<(data.startIndex + pos + 46 + nameLen))
            let name = String(data: nameData, encoding: .utf8) ?? ""
            entries.append(ZipEntry(name: name, compMethod: compMethod, compSize: compSize, localHeaderOffset: localHeaderOffset))
            pos += 46 + nameLen + extraLen + commentLen
        }
        return entries
    }

    private static func readEntryData(_ data: Data, _ entry: ZipEntry) -> Data? {
        let lh = Int(entry.localHeaderOffset)
        guard lh + 30 <= data.count, u32(data, lh) == 0x0403_4b50 else { return nil }
        let nameLen = Int(u16(data, lh + 26))
        let extraLen = Int(u16(data, lh + 28))
        let dataStart = data.startIndex + lh + 30 + nameLen + extraLen
        let dataEnd = dataStart + Int(entry.compSize)
        guard dataEnd <= data.endIndex, dataStart <= dataEnd else { return nil }
        let compressed = data.subdata(in: dataStart..<dataEnd)

        if entry.compMethod == 0 { return compressed }
        if entry.compMethod == 8 { return inflateRaw(compressed) }
        return nil
    }

    private static func inflateRaw(_ compressed: Data) -> Data? {
        let dstCapacity = max(compressed.count * 8, 1 << 16)
        var capacity = dstCapacity
        while true {
            let result: Data? = compressed.withUnsafeBytes { (srcPtr: UnsafeRawBufferPointer) -> Data? in
                guard let srcBase = srcPtr.bindMemory(to: UInt8.self).baseAddress else { return nil }
                let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
                defer { dstBuffer.deallocate() }
                let decodedCount = compression_decode_buffer(dstBuffer, capacity, srcBase, compressed.count, nil, COMPRESSION_ZLIB)
                if decodedCount == 0 { return nil }
                if decodedCount == capacity { return nil } // possibly truncated — caller retries larger
                return Data(bytes: dstBuffer, count: decodedCount)
            }
            if let result { return result }
            if capacity > 64 * 1024 * 1024 { return nil } // safety cap
            capacity *= 4
        }
    }

    private static let imageMimeByExt: [String: String] = [
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "bmp": "image/bmp",
    ]

    static func fileExtension(forMimeType mime: String) -> String {
        imageMimeByExt.first(where: { $0.value == mime })?.key ?? "png"
    }

    static func extractStyle(from url: URL) -> DocxStyle {
        var style = DocxStyle()
        guard let data = try? Data(contentsOf: url) else { return style }
        let entries = parseEntries(data)
        guard !entries.isEmpty else { return style }

        if let imageEntry = entries.first(where: { $0.name.range(of: #"^word/media/image1\.(png|jpe?g|gif|bmp)$"#, options: [.regularExpression, .caseInsensitive]) != nil })
            ?? entries.first(where: { $0.name.range(of: #"^word/media/image\d+\.(png|jpe?g|gif|bmp)$"#, options: [.regularExpression, .caseInsensitive]) != nil }) {
            let ext = (imageEntry.name as NSString).pathExtension.lowercased()
            if let mime = imageMimeByExt[ext], let bytes = readEntryData(data, imageEntry) {
                style.photoData = bytes
                style.photoMimeType = mime
            }
        }

        if let themeEntry = entries.first(where: { $0.name == "word/theme/theme1.xml" }),
           let themeBytes = readEntryData(data, themeEntry),
           let xml = String(data: themeBytes, encoding: .utf8) {
            style.accentColorHex = firstMatch(in: xml, pattern: #"<a:accent1>\s*<a:srgbClr val="([0-9A-Fa-f]{6})""#)
                .map { "#\($0.uppercased())" }
        }

        if style.accentColorHex == nil,
           let docEntry = entries.first(where: { $0.name == "word/document.xml" }),
           let docBytes = readEntryData(data, docEntry),
           let xml = String(data: docBytes, encoding: .utf8) {
            style.accentColorHex = mostCommonRunColor(in: xml).map { "#\($0)" }
        }

        return style
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    private static func mostCommonRunColor(in xml: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"w:color w:val="([0-9A-Fa-f]{6})""#) else { return nil }
        var counts: [String: Int] = [:]
        regex.enumerateMatches(in: xml, range: NSRange(xml.startIndex..., in: xml)) { match, _, _ in
            guard let match, let range = Range(match.range(at: 1), in: xml) else { return }
            let hex = String(xml[range]).uppercased()
            guard hex != "000000", hex != "FFFFFF" else { return }
            counts[hex, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}
