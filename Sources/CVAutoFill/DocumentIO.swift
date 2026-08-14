import AppKit
import CoreText
import Foundation
import PDFKit

enum DocumentTextExtractor {
    static func extractPDFText(url: URL) -> String? {
        PDFDocument(url: url)?.string
    }

    static func extractDocxText(url: URL) -> String? {
        guard let attributed = try? NSAttributedString(
            url: url,
            options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
            documentAttributes: nil
        ) else { return nil }
        return attributed.string
    }
}

enum HTMLTextExtractor {
    static func plainText(from html: String) -> String {
        guard let data = html.data(using: .utf8) else { return "" }
        guard let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
        ) else { return "" }
        return attributed.string
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func title(from html: String) -> String? {
        guard let range = html.range(of: "<title>", options: .caseInsensitive),
              let endRange = html.range(of: "</title>", options: .caseInsensitive, range: range.upperBound..<html.endIndex)
        else { return nil }
        return String(html[range.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// Native pagination/word-wrap via CoreText — much simpler than hand-rolling a
// PDF writer the way the browser extension has to (no CoreText in a JS sandbox).
enum PDFExporter {
    static func makePDF(text: String) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 72
        let textRect = pageRect.insetBy(dx: margin, dy: margin)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle,
        ])

        let data = NSMutableData()
        var mediaBox = pageRect
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return Data() }

        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var textPosition = 0
        let fullLength = attributed.length
        let path = CGPath(rect: CGRect(origin: .zero, size: textRect.size), transform: nil)

        repeat {
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: margin, y: margin)
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(textPosition, 0), path, nil)
            CTFrameDraw(frame, context)
            context.restoreGState()
            context.endPDFPage()

            let frameRange = CTFrameGetVisibleStringRange(frame)
            if frameRange.length <= 0 { break }
            textPosition += frameRange.length
        } while textPosition < fullLength

        context.closePDF()
        return data as Data
    }
}
