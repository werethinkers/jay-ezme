// Turns a design into a finished file: a picture, an animated GIF, a PDF, a Word document or an HTML page.
import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

enum DesignFormat: String, CaseIterable, Identifiable {
    case png, gif, pdf, docx, html
    var id: String { rawValue }
    var title: String {
        switch self {
        case .png: return "Image (PNG)"
        case .gif: return "Animated GIF"
        case .pdf: return "PDF"
        case .docx: return "Word document"
        case .html: return "HTML page"
        }
    }
    var symbol: String {
        switch self {
        case .png: return "photo"
        case .gif: return "photo.stack"
        case .pdf: return "doc.richtext"
        case .docx: return "doc.text"
        case .html: return "globe"
        }
    }
    var fileExtension: String { rawValue }
    static func from(_ text: String?) -> DesignFormat? { text.flatMap { DesignFormat(rawValue: $0.lowercased()) } }

    /// Words a person might say for each format.
    static func spoken(_ text: String) -> DesignFormat? {
        let l = text.lowercased()
        if l.contains("gif") { return .gif }
        if l.contains("pdf") { return .pdf }
        if l.contains("word") || l.contains("docx") || l.contains("doc ") { return .docx }
        if l.contains("html") || l.contains("web page") || l.contains("webpage") || l.contains("website") { return .html }
        if l.contains("image") || l.contains("png") || l.contains("picture") || l.contains("photo") { return .png }
        return nil
    }
}

// MARK: - Zip (for Word files)

struct ZipWriter {
    private var entries: [(name: String, data: Data)] = []
    mutating func add(_ name: String, _ data: Data) { entries.append((name, data)) }
    mutating func add(_ name: String, text: String) { entries.append((name, Data(text.utf8))) }

    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 { value = (value & 1) == 1 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1) }
        return value
    }

    private static func crc(_ data: Data) -> UInt32 {
        var value: UInt32 = 0xFFFFFFFF
        for byte in data { value = table[Int((value ^ UInt32(byte)) & 0xFF)] ^ (value >> 8) }
        return value ^ 0xFFFFFFFF
    }

    private static func le16(_ value: UInt16) -> Data { Data([UInt8(value & 0xFF), UInt8(value >> 8)]) }
    private static func le32(_ value: UInt32) -> Data { Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)]) }

    /// A zip file with the entries stored as they are (no compression), which Word reads without trouble.
    func data() -> Data {
        var output = Data()
        var central = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            let checksum = ZipWriter.crc(entry.data)
            let size = UInt32(entry.data.count)
            let offset = UInt32(output.count)
            output.append(ZipWriter.le32(0x04034B50)); output.append(ZipWriter.le16(20)); output.append(ZipWriter.le16(0)); output.append(ZipWriter.le16(0))
            output.append(ZipWriter.le16(0)); output.append(ZipWriter.le16(0x0021))
            output.append(ZipWriter.le32(checksum)); output.append(ZipWriter.le32(size)); output.append(ZipWriter.le32(size))
            output.append(ZipWriter.le16(UInt16(name.count))); output.append(ZipWriter.le16(0))
            output.append(name); output.append(entry.data)
            central.append(ZipWriter.le32(0x02014B50)); central.append(ZipWriter.le16(20)); central.append(ZipWriter.le16(20))
            central.append(ZipWriter.le16(0)); central.append(ZipWriter.le16(0)); central.append(ZipWriter.le16(0)); central.append(ZipWriter.le16(0x0021))
            central.append(ZipWriter.le32(checksum)); central.append(ZipWriter.le32(size)); central.append(ZipWriter.le32(size))
            central.append(ZipWriter.le16(UInt16(name.count))); central.append(ZipWriter.le16(0)); central.append(ZipWriter.le16(0))
            central.append(ZipWriter.le16(0)); central.append(ZipWriter.le16(0)); central.append(ZipWriter.le32(0)); central.append(ZipWriter.le32(offset))
            central.append(name)
        }
        let centralOffset = UInt32(output.count)
        output.append(central)
        output.append(ZipWriter.le32(0x06054B50)); output.append(ZipWriter.le16(0)); output.append(ZipWriter.le16(0))
        output.append(ZipWriter.le16(UInt16(entries.count))); output.append(ZipWriter.le16(UInt16(entries.count)))
        output.append(ZipWriter.le32(UInt32(central.count))); output.append(ZipWriter.le32(centralOffset)); output.append(ZipWriter.le16(0))
        return output
    }
}

// MARK: - Writers

enum DesignOutput {
    private static func xml(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func ordered(_ slots: [TemplateSlot]) -> [TemplateSlot] {
        slots.sorted { abs($0.cy - $1.cy) > 0.012 ? $0.cy < $1.cy : $0.cx < $1.cx }
    }

    /// Writes the design in the chosen format and returns the file.
    @MainActor static func write(format: DesignFormat, pages: [ImageTemplate], values: [String: String], clips: [Clip], title: String, directory: URL, stem: String) throws -> URL {
        guard !pages.isEmpty else { throw NSError(domain: "KeyDoTemplates", code: 3, userInfo: [NSLocalizedDescriptionKey: "The design has no pages."]) }
        let file = directory.appendingPathComponent(stem + "." + format.fileExtension)
        switch format {
        case .png:
            if pages.count == 1 {
                try TemplateFill.renderFile(pages[0], values: values, clips: clips, to: file)
            } else {
                // Several pages as one tall picture would be huge, so the first page is the picture.
                try TemplateFill.renderFile(pages[0], values: values, clips: clips, to: file)
            }
        case .gif: try writeGIF(pages[0], values: values, clips: clips, to: file)
        case .pdf: try writePDF(pages, values: values, clips: clips, to: file)
        case .docx: try writeDocx(pages, values: values, clips: clips, to: file)
        case .html: try Data(html(pages, values: values, clips: clips, title: title).utf8).write(to: file, options: .atomic)
        }
        return file
    }

    // MARK: PDF

    @MainActor static func writePDF(_ pages: [ImageTemplate], values: [String: String], clips: [Clip], to file: URL) throws {
        let document = PDFDocument()
        for page in pages {
            guard let image = TemplateFill.render(page, values: values, clips: clips, maxSide: 2400), let pdfPage = PDFPage(image: image) else { continue }
            document.insert(pdfPage, at: document.pageCount)
        }
        guard document.pageCount > 0, document.write(to: file) else {
            throw NSError(domain: "KeyDoTemplates", code: 4, userInfo: [NSLocalizedDescriptionKey: "The pages could not be made into a PDF."])
        }
    }

    // MARK: GIF (the boxes appear one after another)

    @MainActor static func writeGIF(_ page: ImageTemplate, values: [String: String], clips: [Clip], to file: URL) throws {
        guard let base = TemplateStore.shared.basePicture(for: page) else {
            throw NSError(domain: "KeyDoTemplates", code: 1, userInfo: [NSLocalizedDescriptionKey: "The template picture is missing."])
        }
        let made = TemplateFill.resolved(page, values: values, clips: clips)
        let total = page.slots.count
        let steps = max(1, min(total, 8))
        var frames: [(CGImage, Double)] = []
        for step in 0...steps {
            var partial = page
            let visible = total == 0 ? 0 : Int((Double(total) * Double(step) / Double(steps)).rounded(.up))
            partial.slots = Array(page.slots.prefix(visible))
            guard let image = TemplateRenderer.render(partial, base: base, texts: made.texts, images: made.images, useSamples: false, maxSide: 760),
                  let cg = TemplateImages.cgImage(image) else { continue }
            frames.append((cg, step == steps ? 3.0 : (step == 0 ? 0.5 : 0.45)))
        }
        guard !frames.isEmpty, let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
            throw NSError(domain: "KeyDoTemplates", code: 5, userInfo: [NSLocalizedDescriptionKey: "The GIF could not be made."])
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]] as CFDictionary)
        for frame in frames {
            CGImageDestinationAddImage(destination, frame.0, [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: frame.1]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "KeyDoTemplates", code: 5, userInfo: [NSLocalizedDescriptionKey: "The GIF could not be finished."])
        }
    }

    // MARK: Word

    @MainActor static func writeDocx(_ pages: [ImageTemplate], values: [String: String], clips: [Clip], to file: URL) throws {
        var body = ""
        for (number, page) in pages.enumerated() {
            let made = TemplateFill.resolved(page, values: values, clips: clips)
            for slot in ordered(page.slots) where slot.kind == .text {
                var text = made.texts[TemplateFill.normal(slot.key)] ?? ""
                if text.isEmpty { continue }
                if slot.uppercase { text = text.uppercased() }
                let points = slot.fontSize > 0 ? max(8, min(48, slot.fontSize * 842)) : max(10, min(28, slot.h * 842 * 0.45))
                let alignment = slot.align == "right" ? "right" : (slot.align == "left" ? "left" : "center")
                let lines = text.components(separatedBy: "\n").map { xml($0) }.joined(separator: "</w:t><w:br/><w:t xml:space=\"preserve\">")
                let font = xml(slot.fontName)
                body += "<w:p><w:pPr><w:spacing w:after=\"160\"/><w:jc w:val=\"\(alignment)\"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii=\"\(font)\" w:hAnsi=\"\(font)\" w:cs=\"\(font)\"/>"
                    + (slot.bold ? "<w:b/>" : "") + (slot.italic ? "<w:i/>" : "")
                    + "<w:color w:val=\"\(slot.colorHex.replacingOccurrences(of: "#", with: ""))\"/><w:sz w:val=\"\(Int(points * 2))\"/></w:rPr><w:t xml:space=\"preserve\">\(lines)</w:t></w:r></w:p>"
            }
            if number < pages.count - 1 { body += "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>" }
        }
        if body.isEmpty { body = "<w:p><w:r><w:t></w:t></w:r></w:p>" }
        let document = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>\(body)<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1134\" w:right=\"1134\" w:bottom=\"1134\" w:left=\"1134\" w:header=\"708\" w:footer=\"708\" w:gutter=\"0\"/></w:sectPr></w:body></w:document>"
        var zip = ZipWriter()
        zip.add("[Content_Types].xml", text: "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>")
        zip.add("_rels/.rels", text: "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>")
        zip.add("word/document.xml", text: document)
        try zip.data().write(to: file, options: .atomic)
    }

    // MARK: HTML

    private static func dataURI(_ image: NSImage, maxSide: CGFloat, png: Bool = false) -> String {
        let limited = TemplateImages.limited(image, maxSide: maxSide)
        guard let cg = TemplateImages.cgImage(limited) else { return "" }
        let rep = NSBitmapImageRep(cgImage: cg)
        if png, let data = rep.representation(using: .png, properties: [:]) { return "data:image/png;base64," + data.base64EncodedString() }
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else { return "" }
        return "data:image/jpeg;base64," + data.base64EncodedString()
    }

    private static func css(_ value: Double) -> String { String(format: "%.3f", value) }

    @MainActor static func html(_ pages: [ImageTemplate], values: [String: String], clips: [Clip], title: String) -> String {
        var sections = ""
        for page in pages {
            guard let base = TemplateStore.shared.basePicture(for: page) else { continue }
            let made = TemplateFill.resolved(page, values: values, clips: clips)
            var boxes = ""
            for slot in page.slots {
                var style = "left:\(css((slot.cx - slot.w / 2) * 100))%;top:\(css((slot.cy - slot.h / 2) * 100))%;width:\(css(slot.w * 100))%;height:\(css(slot.h * 100))%;"
                if slot.angle != 0 { style += "transform:rotate(\(css(slot.angle))deg);" }
                switch slot.shape {
                case .circle: style += "border-radius:50%;"
                case .triangle: style += "clip-path:polygon(50% 0,100% 100%,0 100%);"
                case .random:
                    var points: [String] = []
                    var index = 0
                    while index + 1 < slot.points.count { points.append("\(css(slot.points[index] * 100))% \(css(slot.points[index + 1] * 100))%"); index += 2 }
                    if points.count >= 3 { style += "clip-path:polygon(\(points.joined(separator: ",")));" }
                default: break
                }
                if !slot.fillHex.isEmpty { style += "background:\(slot.fillHex);" }
                let key = TemplateFill.normal(slot.key)
                switch slot.kind {
                case .text:
                    var text = made.texts[key] ?? ""
                    if text.isEmpty { continue }
                    var liveHTML: String? = nil
                    if let content = slot.content, content.contains("{="), (values.first { TemplateFill.normal($0.key) == key }?.value ?? "").isEmpty, !slot.uppercase {
                        liveHTML = DesignLiveText.html(content: content, values: values.reduce(into: [:]) { $0[TemplateFill.normal($1.key)] = $1.value }, escape: { xml($0) })
                    }
                    if slot.uppercase { text = text.uppercased() }
                    let justify = slot.align == "left" ? "flex-start" : (slot.align == "right" ? "flex-end" : "center")
                    style += "justify-content:\(justify);text-align:\(slot.align == "center" ? "center" : slot.align);color:\(slot.colorHex);font-family:'\(slot.fontName)',sans-serif;font-weight:\(slot.bold ? 700 : 400);font-style:\(slot.italic ? "italic" : "normal");"
                    boxes += "<div class=\"box\" style=\"\(style)\"><span class=\"t\" data-fs=\"\(css(slot.fontSize))\">\(liveHTML ?? xml(text).replacingOccurrences(of: "\n", with: "<br>"))</span></div>"
                case .image:
                    if let picture = made.images[key] { boxes += "<div class=\"box\" style=\"\(style)\"><img src=\"\(dataURI(picture, maxSide: 900))\"></div>" }
                case .logo:
                    if let logo = TemplateLogos.image(slot.logo, colorHex: slot.colorHex) { boxes += "<div class=\"box\" style=\"\(style)\"><img class=\"logo\" src=\"\(dataURI(logo, maxSide: 400, png: true))\"></div>" }
                }
            }
            sections += "<section class=\"page\" style=\"aspect-ratio:\(page.pixelWidth)/\(page.pixelHeight)\"><img class=\"bg\" src=\"\(dataURI(base, maxSide: 1500))\">\(boxes)</section>"
        }
        let safeTitle = xml(title)
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>\(safeTitle)</title>
        <style>
        body{margin:0;background:#e9e6e1;display:flex;flex-direction:column;align-items:center;gap:20px;padding:20px 0;font-family:-apple-system,Helvetica,Arial,sans-serif}
        .page{position:relative;width:min(94vw,900px);background:#fff;box-shadow:0 6px 24px rgba(0,0,0,.2);overflow:hidden}
        .bg{position:absolute;inset:0;width:100%;height:100%}
        .box{position:absolute;display:flex;align-items:center;overflow:hidden;box-sizing:border-box}
        .box img{width:100%;height:100%;object-fit:cover}.box img.logo{object-fit:contain}
        .t{display:block;width:100%;line-height:1.2;overflow-wrap:normal;word-break:keep-all;white-space:normal}
        @media print{body{background:#fff;padding:0;gap:0}.page{box-shadow:none;width:100%;page-break-after:always}}
        </style></head><body>\(sections)
        <script>
        function fit(){document.querySelectorAll('.page').forEach(function(p){var H=p.clientHeight;p.querySelectorAll('.box').forEach(function(b){var t=b.querySelector('.t');if(!t)return;var fs=parseFloat(t.dataset.fs)||0;var size=fs>0?fs*H:b.clientHeight*0.8;t.style.fontSize=size+'px';var n=0;while((t.scrollHeight>b.clientHeight+1||t.scrollWidth>b.clientWidth+1)&&size>5&&n<80){size*=0.94;t.style.fontSize=size+'px';n++}})})}
        window.addEventListener('load',live);window.addEventListener('resize',fit);
        \(DesignLiveText.script)
        </script></body></html>
        """
    }
}
