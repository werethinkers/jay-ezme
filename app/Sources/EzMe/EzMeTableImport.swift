// Turn a picture of a table, a pasted web table (HTML), or copied cells into rows and columns.
import Foundation
import AppKit
import Vision

enum TableImport {
    typealias Table = (headers: [String], rows: [[String]])

    // MARK: HTML

    private static func decode(_ text: String) -> String {
        var out = text
        for (entity, value) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&#160;", " ")] {
            out = out.replacingOccurrences(of: entity, with: value)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripTags(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "(?i)<br\\s*/?>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return decode(text).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    /// The first <table> in the HTML. Works for pages saved from a browser and for pasted tables.
    static func fromHTML(_ html: String) -> Table? {
        let pattern = "(?is)<tr\\b[^>]*>(.*?)</tr>"
        guard let rowRegex = try? NSRegularExpression(pattern: pattern),
              let cellRegex = try? NSRegularExpression(pattern: "(?is)<t[hd]\\b[^>]*>(.*?)</t[hd]>") else { return nil }
        var scope = html
        if let start = html.range(of: "<table", options: .caseInsensitive) {
            scope = String(html[start.lowerBound...])
            if let end = scope.range(of: "</table>", options: .caseInsensitive) { scope = String(scope[..<end.upperBound]) }
        }
        let ns = scope as NSString
        var rows: [[String]] = []
        for match in rowRegex.matches(in: scope, range: NSRange(location: 0, length: ns.length)) {
            let rowHTML = ns.substring(with: match.range(at: 1)) as NSString
            let cells = cellRegex.matches(in: rowHTML as String, range: NSRange(location: 0, length: rowHTML.length)).map { stripTags(rowHTML.substring(with: $0.range(at: 1))) }
            if cells.contains(where: { !$0.isEmpty }) { rows.append(cells) }
        }
        return normalise(rows)
    }

    // MARK: Plain text (copied cells from a sheet, a Markdown table, or CSV)

    static func fromText(_ text: String) -> Table? {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else { return nil }
        var rows: [[String]]
        if lines.contains(where: { $0.contains("\t") }) {
            rows = lines.map { $0.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) } }
        } else if lines.filter({ $0.contains("|") }).count >= 2 {
            rows = lines.filter { !$0.replacingOccurrences(of: "[|\\-: ]", with: "", options: .regularExpression).isEmpty }
                .map { line in
                    var cells = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                    if cells.first == "" { cells.removeFirst() }
                    if cells.last == "" { cells.removeLast() }
                    return cells
                }
        } else if lines.filter({ $0.contains(",") }).count >= 2 {
            rows = EzContactImport.csvRows(text)
        } else {
            return nil
        }
        return normalise(rows)
    }

    /// Whatever is on the clipboard: a picture is read by the Mac's text recognition, HTML and text are parsed.
    @MainActor static func fromClipboard() async -> (table: Table, source: String)? {
        let pasteboard = NSPasteboard.general
        if let html = pasteboard.string(forType: .html), html.localizedCaseInsensitiveContains("<tr"), let table = fromHTML(html) { return (table, "web table") }
        if let text = pasteboard.string(forType: .string), let table = fromText(text) { return (table, "copied cells") }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff), let image = NSImage(data: data),
           let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), let table = await fromImage(cg) { return (table, "picture") }
        return nil
    }

    static func fromFile(_ url: URL) async -> Table? {
        let ext = url.pathExtension.lowercased()
        if ["html", "htm", "xhtml"].contains(ext) {
            guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
            return fromHTML(text)
        }
        if ["png", "jpg", "jpeg", "heic", "tiff", "gif", "bmp", "webp"].contains(ext) {
            guard let image = NSImage(contentsOf: url), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            return await fromImage(cg)
        }
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return nil }
        return fromText(text)
    }

    // MARK: Picture (Vision text recognition)

    private struct Piece { var text: String; var minX: CGFloat; var maxX: CGFloat; var midY: CGFloat; var height: CGFloat }

    static func fromImage(_ image: CGImage) async -> Table? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do { try handler.perform([request]) } catch { continuation.resume(returning: nil); return }
                let pieces = (request.results ?? []).compactMap { observation -> Piece? in
                    guard let text = observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
                    let box = observation.boundingBox
                    return Piece(text: text, minX: box.minX, maxX: box.maxX, midY: box.midY, height: box.height)
                }
                continuation.resume(returning: layout(pieces))
            }
        }
    }

    /// Groups recognised text into rows by height, then into columns by where each piece starts.
    private static func layout(_ pieces: [Piece]) -> Table? {
        guard pieces.count >= 4 else { return nil }
        let typical = pieces.map { $0.height }.sorted()[pieces.count / 2]
        var lines: [[Piece]] = []
        for piece in pieces.sorted(by: { $0.midY > $1.midY }) {
            if let last = lines.indices.last, abs(lines[last].map { $0.midY }.reduce(0, +) / CGFloat(lines[last].count) - piece.midY) < typical * 0.6 {
                lines[last].append(piece)
            } else { lines.append([piece]) }
        }
        lines = lines.map { $0.sorted { $0.minX < $1.minX } }
        // Pieces on one line that nearly touch are one cell ("New" "York").
        let merged: [[Piece]] = lines.map { line in
            var cells: [Piece] = []
            for piece in line {
                if var last = cells.last, piece.minX - last.maxX < typical * 1.1 {
                    last.text += " " + piece.text; last.maxX = piece.maxX
                    cells[cells.count - 1] = last
                } else { cells.append(piece) }
            }
            return cells
        }
        let starts = merged.flatMap { $0.map { $0.minX } }.sorted()
        var anchors: [CGFloat] = []
        for start in starts {
            if let last = anchors.last, start - last < 0.03 { continue }
            anchors.append(start)
        }
        guard anchors.count >= 2 else { return normalise(merged.map { $0.map { $0.text } }) }
        let rows = merged.map { cells -> [String] in
            var row = Array(repeating: "", count: anchors.count)
            for cell in cells {
                let column = anchors.indices.min { abs(anchors[$0] - cell.minX) < abs(anchors[$1] - cell.minX) } ?? 0
                row[column] = row[column].isEmpty ? cell.text : row[column] + " " + cell.text
            }
            return row
        }
        return normalise(rows)
    }

    // MARK: Shape

    /// First row becomes the headers; every row gets the same number of cells.
    private static func normalise(_ rows: [[String]]) -> Table? {
        guard rows.count >= 2 else { return nil }
        let width = rows.map { $0.count }.max() ?? 0
        guard width >= 2 else { return nil }
        let padded = rows.map { row in row + Array(repeating: "", count: width - row.count) }
        var headers = padded[0].enumerated().map { $0.element.isEmpty ? "Column \($0.offset + 1)" : $0.element }
        var seen = Set<String>()
        headers = headers.map { name in
            var candidate = name; var n = 2
            while !seen.insert(candidate.lowercased()).inserted { candidate = "\(name) \(n)"; n += 1 }
            return candidate
        }
        return (headers, Array(padded.dropFirst()))
    }
}
