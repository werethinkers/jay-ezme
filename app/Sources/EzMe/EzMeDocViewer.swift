import SwiftUI
import AppKit
import PDFKit
import CryptoKit
import UniformTypeIdentifiers

// KeyDo Document Viewer: opens PDF and Word documents inside KeyDo.
// Notes, highlights, tags and attached pictures are kept beside the document (never written into the original file),
// so they are seen in the KeyDo Document Viewer only, and can be searched from the Database Organizer.

// MARK: - Saved marks

struct DocMark: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    /// "highlight" or "note"
    var kind: String
    var color: String
    var quote: String
    var note: String
    /// PDF page (starting at 0). Word documents use 0.
    var page: Int
    /// Word documents: where the highlighted text starts and how long it is.
    var location: Int
    var length: Int
    /// PDF: one entry per line: [page, x, y, width, height].
    var rects: [[Double]]
    var created = Date()
}

struct DocMedia: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var file: String
    var caption: String
    var page: Int
}

struct DocSidecar: Codable {
    var path: String
    var tags: [String] = []
    var general = ""
    var marks: [DocMark] = []
    var media: [DocMedia] = []
    var updated = Date()
}

enum DocColors {
    static let names = ["yellow", "green", "pink", "blue", "orange"]

    static func ns(_ name: String) -> NSColor {
        switch name {
        case "green": return NSColor(calibratedRed: 0.45, green: 0.85, blue: 0.45, alpha: 1)
        case "pink": return NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.75, alpha: 1)
        case "blue": return NSColor(calibratedRed: 0.45, green: 0.72, blue: 1.0, alpha: 1)
        case "orange": return NSColor(calibratedRed: 1.0, green: 0.68, blue: 0.30, alpha: 1)
        default: return NSColor(calibratedRed: 1.0, green: 0.92, blue: 0.25, alpha: 1)
        }
    }

    static func swiftUI(_ name: String) -> Color { Color(nsColor: ns(name)) }
}

// MARK: - Storage beside the document

enum DocStore {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyDo", isDirectory: true).appendingPathComponent("DocumentNotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func key(_ path: String) -> String {
        SHA256.hash(data: Data(path.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
    }

    static func sidecarURL(_ url: URL) -> URL { folder.appendingPathComponent(key(url.path) + ".json") }

    static func mediaFolder(_ url: URL) -> URL {
        let dir = folder.appendingPathComponent("Media", isDirectory: true).appendingPathComponent(key(url.path), isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func load(_ url: URL) -> DocSidecar {
        if let data = try? Data(contentsOf: sidecarURL(url)), let value = try? JSONDecoder().decode(DocSidecar.self, from: data) { return value }
        return DocSidecar(path: url.path)
    }

    static func save(_ value: DocSidecar, for url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: sidecarURL(url), options: .atomic)
    }

    /// Every document that has notes, highlights, tags or media. Used by the Database Organizer search.
    static func all() -> [DocSidecar] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var result: [DocSidecar] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file), let value = try? JSONDecoder().decode(DocSidecar.self, from: data) { result.append(value) }
        }
        return result
    }
}

enum DocText {
    static let viewable: Set<String> = ["pdf", "doc", "docx", "rtf"]

    static func isViewable(_ path: String) -> Bool { viewable.contains(URL(fileURLWithPath: path).pathExtension.lowercased()) }

    static func attributed(_ url: URL) -> NSAttributedString? {
        let ext = url.pathExtension.lowercased()
        let type: NSAttributedString.DocumentType = ext == "doc" ? .docFormat : (ext == "rtf" ? .rtf : .officeOpenXML)
        return try? NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil)
    }

    /// All the words in a PDF or Word file, for searching.
    static func plain(_ url: URL) -> String {
        if url.pathExtension.lowercased() == "pdf" { return PDFDocument(url: url)?.string ?? "" }
        return attributed(url)?.string ?? ""
    }
}

// MARK: - Model

@MainActor final class DocViewerModel: ObservableObject {
    let url: URL
    let isPDF: Bool
    @Published var side: DocSidecar
    @Published var query = ""
    @Published var matchCount = 0
    @Published var matchIndex = 0
    @Published var status = ""
    @Published var errorText: String?
    @Published var noteDraft = ""
    @Published var tagDraft = ""
    @Published var sideTab = "Notes"
    var onClose: (() -> Void)?

    var pdfDoc: PDFDocument?
    var wordText: NSAttributedString?
    weak var pdfView: PDFView?
    weak var textView: NSTextView?
    private var pdfMatches: [PDFSelection] = []
    private var wordMatches: [NSRange] = []

    init(url: URL) {
        self.url = url
        self.isPDF = url.pathExtension.lowercased() == "pdf"
        self.side = DocStore.load(url)
        self.side.path = url.path
        if isPDF {
            pdfDoc = PDFDocument(url: url)
            if pdfDoc == nil { errorText = "This PDF could not be opened." }
            else if pdfDoc?.isLocked == true { errorText = "This PDF is password protected. Unlock it in Preview first." }
        } else {
            wordText = DocText.attributed(url)
            if wordText == nil { errorText = "This document could not be read. Word files (.docx, .doc) and .rtf are supported." }
        }
    }

    func persist() {
        side.updated = Date()
        DocStore.save(side, for: url)
    }

    // MARK: Showing saved highlights

    func applyPDFMarks() {
        guard let doc = pdfDoc else { return }
        for mark in side.marks { addPDFAnnotations(mark, in: doc) }
    }

    private func addPDFAnnotations(_ mark: DocMark, in doc: PDFDocument) {
        for rect in mark.rects where rect.count == 5 {
            guard let page = doc.page(at: Int(rect[0])) else { continue }
            let annotation = PDFAnnotation(bounds: CGRect(x: rect[1], y: rect[2], width: rect[3], height: rect[4]), forType: .highlight, withProperties: nil)
            annotation.color = DocColors.ns(mark.color).withAlphaComponent(0.5)
            annotation.userName = mark.id
            page.addAnnotation(annotation)
        }
    }

    private func removePDFAnnotations(_ mark: DocMark) {
        guard let doc = pdfDoc else { return }
        for index in 0..<doc.pageCount {
            guard let page = doc.page(at: index) else { continue }
            for annotation in page.annotations where annotation.userName == mark.id { page.removeAnnotation(annotation) }
        }
    }

    func applyWordMarks() {
        guard let storage = textView?.textStorage else { return }
        for mark in side.marks where mark.length > 0 && mark.location + mark.length <= storage.length {
            storage.addAttribute(.backgroundColor, value: DocColors.ns(mark.color), range: NSRange(location: mark.location, length: mark.length))
        }
    }

    // MARK: Selection, highlight, notes

    var selectedText: String {
        if isPDF { return pdfView?.currentSelection?.string ?? "" }
        guard let view = textView else { return "" }
        let range = view.selectedRange()
        guard range.length > 0, range.location + range.length <= view.string.utf16.count else { return "" }
        return (view.string as NSString).substring(with: range)
    }

    var currentPage: Int {
        guard let view = pdfView, let doc = pdfDoc, let page = view.currentPage else { return 0 }
        return doc.index(for: page)
    }

    /// Highlights the selected text. Returns the new mark.
    @discardableResult func highlight(color: String, note: String = "") -> DocMark? {
        let quote = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !quote.isEmpty else { status = "Select some text in the document first."; return nil }
        var mark = DocMark(kind: note.isEmpty ? "highlight" : "note", color: color, quote: String(quote.prefix(600)), note: note, page: 0, location: 0, length: 0, rects: [])
        if isPDF {
            guard let doc = pdfDoc, let selection = pdfView?.currentSelection else { return nil }
            for line in selection.selectionsByLine() {
                for page in line.pages {
                    let box = line.bounds(for: page)
                    if box.width < 1 || box.height < 1 { continue }
                    mark.rects.append([Double(doc.index(for: page)), Double(box.origin.x), Double(box.origin.y), Double(box.size.width), Double(box.size.height)])
                }
            }
            guard !mark.rects.isEmpty else { status = "That selection could not be highlighted."; return nil }
            mark.page = Int(mark.rects[0][0])
            addPDFAnnotations(mark, in: doc)
            pdfView?.clearSelection()
        } else {
            guard let view = textView, let storage = view.textStorage else { return nil }
            let range = view.selectedRange()
            guard range.length > 0, range.location + range.length <= storage.length else { return nil }
            mark.location = range.location
            mark.length = range.length
            storage.addAttribute(.backgroundColor, value: DocColors.ns(color), range: range)
            view.setSelectedRange(NSRange(location: range.location + range.length, length: 0))
        }
        side.marks.append(mark)
        persist()
        status = note.isEmpty ? "Highlighted in \(color)." : "Note added."
        return mark
    }

    /// A note on the selected text, or a loose note on this page when nothing is selected.
    func addNote(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if !selectedText.isEmpty {
            _ = highlight(color: "yellow", note: clean)
        } else {
            side.marks.append(DocMark(kind: "note", color: "blue", quote: "", note: clean, page: currentPage, location: 0, length: 0, rects: []))
            persist()
            status = isPDF ? "Note added to page \(currentPage + 1)." : "Note added."
        }
        noteDraft = ""
        sideTab = "Notes"
    }

    func remove(_ mark: DocMark) {
        if isPDF { removePDFAnnotations(mark) }
        else if let storage = textView?.textStorage, mark.length > 0, mark.location + mark.length <= storage.length {
            storage.removeAttribute(.backgroundColor, range: NSRange(location: mark.location, length: mark.length))
            // Another highlight may overlap, so put the others back.
            applyWordMarks(except: mark.id)
        }
        side.marks.removeAll { $0.id == mark.id }
        persist()
    }

    private func applyWordMarks(except id: String) {
        guard let storage = textView?.textStorage else { return }
        for mark in side.marks where mark.id != id && mark.length > 0 && mark.location + mark.length <= storage.length {
            storage.addAttribute(.backgroundColor, value: DocColors.ns(mark.color), range: NSRange(location: mark.location, length: mark.length))
        }
    }

    func removeHighlightAtSelection() {
        if let target = side.marks.reversed().first(where: { mark in
            if isPDF { return false }
            guard let range = textView?.selectedRange() else { return false }
            return mark.length > 0 && NSIntersectionRange(range, NSRange(location: mark.location, length: mark.length)).length > 0
        }) ?? side.marks.last(where: { $0.kind == "highlight" }) {
            remove(target)
            status = "Highlight removed."
        } else {
            status = "There is no highlight to remove."
        }
    }

    func jump(to mark: DocMark) {
        if isPDF {
            guard let doc = pdfDoc, let view = pdfView, let page = doc.page(at: mark.page) else { return }
            if let first = mark.rects.first, first.count == 5 {
                view.go(to: CGRect(x: first[1], y: first[2] + first[4], width: max(first[3], 1), height: 1), on: page)
            } else {
                view.go(to: page)
            }
        } else if let view = textView, mark.length > 0, mark.location + mark.length <= view.string.utf16.count {
            let range = NSRange(location: mark.location, length: mark.length)
            view.scrollRangeToVisible(range)
            view.showFindIndicator(for: range)
        }
    }

    func goToPage(_ number: Int) {
        guard isPDF, let doc = pdfDoc, let view = pdfView else { status = "Page numbers are for PDF files."; return }
        let index = min(max(number, 1), doc.pageCount) - 1
        if let page = doc.page(at: index) { view.go(to: page); status = "Page \(index + 1) of \(doc.pageCount)." }
    }

    func copySelection() {
        let text = selectedText
        guard !text.isEmpty else { status = "Select some text first."; return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        status = "Copied."
    }

    // MARK: Search inside the document

    func search() {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        pdfMatches = []
        wordMatches = []
        matchIndex = 0
        if isPDF { pdfView?.highlightedSelections = nil }
        else if let view = textView, let layout = view.layoutManager {
            layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: view.string.utf16.count))
        }
        guard !needle.isEmpty else { matchCount = 0; return }
        if isPDF {
            pdfMatches = pdfDoc?.findString(needle, withOptions: .caseInsensitive) ?? []
            for match in pdfMatches { match.color = NSColor.orange.withAlphaComponent(0.6) }
            pdfView?.highlightedSelections = pdfMatches
            matchCount = pdfMatches.count
        } else if let view = textView {
            let text = view.string as NSString
            var from = 0
            while from < text.length {
                let found = text.range(of: needle, options: .caseInsensitive, range: NSRange(location: from, length: text.length - from))
                if found.location == NSNotFound { break }
                wordMatches.append(found)
                from = found.location + max(found.length, 1)
                if wordMatches.count >= 2000 { break }
            }
            for range in wordMatches { view.layoutManager?.addTemporaryAttribute(.backgroundColor, value: NSColor.orange.withAlphaComponent(0.6), forCharacterRange: range) }
            matchCount = wordMatches.count
        }
        status = matchCount == 0 ? "Nothing found for “\(needle)”." : "\(matchCount) match\(matchCount == 1 ? "" : "es") for “\(needle)”."
        showMatch()
    }

    func step(_ direction: Int) {
        if matchCount == 0 { search(); return }
        matchIndex = (matchIndex + direction + matchCount) % matchCount
        showMatch()
    }

    private func showMatch() {
        guard matchCount > 0 else { return }
        if isPDF, matchIndex < pdfMatches.count {
            pdfView?.setCurrentSelection(pdfMatches[matchIndex], animate: true)
            pdfView?.go(to: pdfMatches[matchIndex])
        } else if let view = textView, matchIndex < wordMatches.count {
            view.scrollRangeToVisible(wordMatches[matchIndex])
            view.showFindIndicator(for: wordMatches[matchIndex])
        }
    }

    // MARK: Tags

    func addTags(_ text: String) {
        let parts = text.replacingOccurrences(of: " and ", with: ",").split(whereSeparator: { ",;\n".contains($0) })
        var added: [String] = []
        for part in parts {
            let tag = part.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !tag.isEmpty, !side.tags.contains(tag) { side.tags.append(tag); added.append(tag) }
        }
        if !added.isEmpty { persist(); status = "Tagged: " + added.joined(separator: ", ") + "." }
        tagDraft = ""
    }

    func removeTag(_ tag: String) {
        let clean = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        side.tags.removeAll { $0 == clean }
        persist()
        status = "Removed the tag “\(clean)”."
    }

    // MARK: Pictures and media kept with the document

    func addMedia(_ urls: [URL]) {
        var count = 0
        for source in urls {
            let name = String(UUID().uuidString.prefix(8)) + "-" + source.lastPathComponent
            let target = DocStore.mediaFolder(url).appendingPathComponent(name)
            if (try? FileManager.default.copyItem(at: source, to: target)) != nil {
                side.media.append(DocMedia(file: name, caption: "", page: isPDF ? currentPage : 0))
                count += 1
            }
        }
        if count > 0 { persist(); status = "\(count) file\(count == 1 ? "" : "s") kept with this document."; sideTab = "Media" }
    }

    func pickMedia() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose pictures, video or other files to keep with this document. They are shown in the KeyDo Document Viewer only."
        if panel.runModal() == .OK { addMedia(panel.urls) }
    }

    func pasteMedia() {
        let pasteboard = NSPasteboard.general
        if let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !files.isEmpty {
            addMedia(files)
            return
        }
        if let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            let name = "pasted-" + String(UUID().uuidString.prefix(8)) + ".png"
            let target = DocStore.mediaFolder(url).appendingPathComponent(name)
            if (try? png.write(to: target)) != nil {
                side.media.append(DocMedia(file: name, caption: "", page: isPDF ? currentPage : 0))
                persist()
                status = "Picture kept with this document."
                sideTab = "Media"
            }
        } else {
            status = "There is no picture or file on the clipboard."
        }
    }

    func mediaURL(_ item: DocMedia) -> URL { DocStore.mediaFolder(url).appendingPathComponent(item.file) }

    func removeMedia(_ item: DocMedia) {
        try? FileManager.default.removeItem(at: mediaURL(item))
        side.media.removeAll { $0.id == item.id }
        persist()
    }

    // MARK: Voice and typed commands

    func handleVoice(_ spoken: String) {
        let raw = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,!? "))
        guard !lower.isEmpty else { return }
        func after(_ prefixes: [String]) -> String? {
            for prefix in prefixes where lower == prefix || lower.hasPrefix(prefix + " ") {
                return String(raw.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: " :,-.!?"))
            }
            return nil
        }
        if lower.hasPrefix("remove highlight") || lower.hasPrefix("clear highlight") || lower.hasPrefix("delete highlight") || lower == "unhighlight" {
            removeHighlightAtSelection(); return
        }
        if lower.hasPrefix("highlight") || lower.hasPrefix("mark this") {
            let color = DocColors.names.first(where: { lower.contains($0) }) ?? "yellow"
            _ = highlight(color: color); return
        }
        if let tag = after(["remove tag", "untag", "delete tag"]) { if tag.isEmpty { status = "Say which tag to remove." } else { removeTag(tag) }; return }
        if let tag = after(["add tag", "add tags", "tag this", "tag"]) { if tag.isEmpty { status = "Say the tag after the word tag." } else { addTags(tag) }; return }
        if let text = after(["add a note", "add note", "note this", "new note", "comment", "note"]) {
            if text.isEmpty { status = "Say the note after the word note, for example “note check the date”." } else { addNote(text) }
            return
        }
        if lower.hasPrefix("go to page") || lower.hasPrefix("page ") || lower.hasPrefix("open page") {
            let digits = lower.filter { $0.isNumber }
            if let number = Int(digits) { goToPage(number) } else { status = "Say the page number, for example “go to page 4”." }
            return
        }
        if lower == "first page" { goToPage(1); return }
        if lower == "last page" { goToPage(pdfDoc?.pageCount ?? 1); return }
        if lower == "next" || lower == "next match" || lower == "find next" { step(1); return }
        if lower == "previous" || lower == "previous match" || lower == "find previous" { step(-1); return }
        if let text = after(["search for", "find", "search"]) {
            if text.isEmpty { status = "Say what to find." } else { query = text; sideTab = "Find"; search() }
            return
        }
        if lower.hasPrefix("copy") { copySelection(); return }
        if lower == "close" || lower == "close document" || lower == "go back" || lower == "close viewer" { onClose?(); return }
        if lower.hasPrefix("show notes") || lower == "notes" { sideTab = "Notes"; return }
        if lower.hasPrefix("show tags") || lower == "tags" { sideTab = "Tags"; return }
        if lower.hasPrefix("show media") || lower.hasPrefix("show pictures") { sideTab = "Media"; return }
        if lower.hasPrefix("paste image") || lower.hasPrefix("paste picture") || lower.hasPrefix("paste media") { pasteMedia(); return }
        if lower.hasPrefix("add image") || lower.hasPrefix("attach image") || lower.hasPrefix("add media") || lower.hasPrefix("attach media") || lower.hasPrefix("add picture") { pickMedia(); return }
        status = "Not understood: “\(raw)”. Try: highlight green, note check the date, tag invoice, find total, go to page 3, copy."
    }
}

// MARK: - The document itself

struct DocPDFView: NSViewRepresentable {
    @ObservedObject var model: DocViewerModel

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.document = model.pdfDoc
        model.pdfView = view
        model.applyPDFMarks()
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {}
}

struct DocWordView: NSViewRepresentable {
    @ObservedObject var model: DocViewerModel

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.appearance = NSAppearance(named: .aqua)
        if let view = scroll.documentView as? NSTextView {
            view.isEditable = false
            view.isSelectable = true
            view.drawsBackground = true
            view.backgroundColor = .white
            view.textContainerInset = NSSize(width: 32, height: 28)
            view.textStorage?.setAttributedString(model.wordText ?? NSAttributedString(string: ""))
            model.textView = view
            model.applyWordMarks()
        }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

// MARK: - The viewer screen

struct DocumentViewerView: View {
    @StateObject private var model: DocViewerModel
    var onClose: () -> Void
    @State private var typed = ""

    init(url: URL, onClose: @escaping () -> Void) {
        _model = StateObject(wrappedValue: DocViewerModel(url: url))
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                documentArea
                Divider()
                sidebar.frame(width: 320)
            }
            if !model.status.isEmpty {
                Divider()
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 6)
            }
        }
        .onAppear { model.onClose = onClose }
    }

    @ViewBuilder private var documentArea: some View {
        if let message = model.errorText {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                Text(message).multilineTextAlignment(.center)
                Button("Open with another app") { NSWorkspace.shared.open(model.url) }
            }
            .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.isPDF {
            DocPDFView(model: model)
        } else {
            DocWordView(model: model)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { onClose() } label: { Label("Back", systemImage: "chevron.left") }.buttonStyle(.bordered)
            Image(systemName: model.isPDF ? "doc.richtext.fill" : "doc.text.fill").foregroundStyle(Butter.coral)
            Text(model.url.lastPathComponent).font(.system(size: 14, weight: .bold, design: .rounded)).lineLimit(1)
            Spacer(minLength: 8)
            TextField("Find in document", text: $model.query)
                .textFieldStyle(.roundedBorder).frame(width: 190)
                .onSubmit { model.search() }
            Button { model.step(-1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.bordered).help("Previous match")
            Button { model.step(1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.bordered).help("Next match")
            if model.matchCount > 0 { Text("\(model.matchIndex + 1)/\(model.matchCount)").font(.caption).foregroundStyle(.secondary) }
            Divider().frame(height: 22)
            ForEach(DocColors.names, id: \.self) { name in
                Button { _ = model.highlight(color: name) } label: {
                    Circle().fill(DocColors.swiftUI(name)).frame(width: 20, height: 20)
                        .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain).help("Highlight the selected text in \(name)")
            }
            Button { model.copySelection() } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.bordered).help("Copy the selected text")
            Button { NSWorkspace.shared.activateFileViewerSelecting([model.url]) } label: { Image(systemName: "folder") }.buttonStyle(.bordered).help("Show in Finder")
            VoiceDictationButton(onTranscript: { text in model.handleVoice(text) })
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.sideTab) {
                ForEach(["Notes", "Tags", "Media", "Find"], id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().padding(10)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch model.sideTab {
                    case "Tags": tagsPane
                    case "Media": mediaPane
                    case "Find": findPane
                    default: notesPane
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "waveform").foregroundStyle(Butter.coral)
                TextField("Type or say: highlight green, note …, tag …", text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.handleVoice(typed); typed = "" }
            }
            .padding(10)
        }
        .background(Butter.cream.opacity(0.5))
    }

    private var notesPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes about this document").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            TextEditor(text: $model.side.general)
                .font(.callout).frame(height: 90)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                .onChange(of: model.side.general) { _ in model.persist() }
            Text("Note on the selected text").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            HStack {
                TextField("Select text, then write a note", text: $model.noteDraft).textFieldStyle(.roundedBorder)
                    .onSubmit { model.addNote(model.noteDraft) }
                Button("Add") { model.addNote(model.noteDraft) }.buttonStyle(.borderedProminent).tint(Butter.coral).disabled(model.noteDraft.isEmpty)
            }
            Divider()
            Text("Highlights and notes (\(model.side.marks.count))").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            if model.side.marks.isEmpty {
                Text("Select text in the document and press a colour to highlight it, or say “highlight green”.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.side.marks) { mark in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(DocColors.swiftUI(mark.color)).frame(width: 10, height: 10).padding(.top, 4)
                    VStack(alignment: .leading, spacing: 3) {
                        if !mark.quote.isEmpty { Text("“\(mark.quote)”").font(.caption).lineLimit(3) }
                        if !mark.note.isEmpty { Text(mark.note).font(.callout) }
                        if model.isPDF { Text("Page \(mark.page + 1)").font(.caption2).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 4)
                    Button { model.jump(to: mark) } label: { Image(systemName: "arrow.right.circle") }.buttonStyle(.plain).help("Go to it")
                    Button { model.remove(mark) } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(.secondary).help("Remove")
                }
                .padding(8).background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var tagsPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tags help you find this document in the Database Organizer.").font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Add tags, separated by commas", text: $model.tagDraft).textFieldStyle(.roundedBorder)
                    .onSubmit { model.addTags(model.tagDraft) }
                Button("Add") { model.addTags(model.tagDraft) }.buttonStyle(.borderedProminent).tint(Butter.coral).disabled(model.tagDraft.isEmpty)
            }
            if model.side.tags.isEmpty {
                Text("No tags yet. Say “tag invoice” to add one by voice.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.side.tags, id: \.self) { tag in
                HStack {
                    Label(tag, systemImage: "tag.fill").font(.callout)
                    Spacer()
                    Button { model.removeTag(tag) } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(8).background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var mediaPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pictures and media kept with this document. They are seen in the KeyDo Document Viewer only; the original file is not changed.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button { model.pickMedia() } label: { Label("Add files", systemImage: "plus") }.buttonStyle(.bordered)
                Button { model.pasteMedia() } label: { Label("Paste", systemImage: "doc.on.clipboard") }.buttonStyle(.bordered)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                ForEach(model.side.media) { item in
                    VStack(spacing: 4) {
                        mediaThumb(item)
                        if model.isPDF { Text("Page \(item.page + 1)").font(.caption2).foregroundStyle(.secondary) }
                        HStack(spacing: 10) {
                            Button { NSWorkspace.shared.open(model.mediaURL(item)) } label: { Image(systemName: "arrow.up.forward.square") }.buttonStyle(.plain).help("Open")
                            if model.isPDF { Button { model.goToPage(item.page + 1) } label: { Image(systemName: "doc.text.magnifyingglass") }.buttonStyle(.plain).help("Go to its page") }
                            Button { model.removeMedia(item) } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(.secondary).help("Remove")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func mediaThumb(_ item: DocMedia) -> some View {
        if let image = NSImage(contentsOf: model.mediaURL(item)) {
            Image(nsImage: image).resizable().scaledToFill().frame(width: 120, height: 90).clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: "doc.fill").font(.largeTitle).foregroundStyle(.secondary)
                .frame(width: 120, height: 90).background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var findPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Find in this document", text: $model.query).textFieldStyle(.roundedBorder).onSubmit { model.search() }
                Button("Find") { model.search() }.buttonStyle(.borderedProminent).tint(Butter.coral)
            }
            if model.matchCount > 0 {
                HStack {
                    Text("Match \(model.matchIndex + 1) of \(model.matchCount)").font(.callout)
                    Spacer()
                    Button { model.step(-1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.bordered)
                    Button { model.step(1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.bordered)
                }
            }
            Text("To search across all your documents, notes and tags, use the Organizer tab.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
