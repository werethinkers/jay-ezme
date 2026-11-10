// Puts an image on the clipboard so it can be pasted straight into other apps.
import AppKit

enum EzClipboard {
    /// Copies the picture at `path` as PNG and TIFF, which covers nearly every Mac app. Returns false if it cannot be read.
    @discardableResult
    static func copyImage(atPath path: String) -> Bool {
        guard let image = NSImage(contentsOfFile: path) else { return false }
        let board = NSPasteboard.general
        board.clearContents()
        board.declareTypes([.png, .tiff], owner: nil)
        var wrote = false
        if let rep = image.representations.first as? NSBitmapImageRep ?? image.tiffRepresentation.flatMap({ NSBitmapImageRep(data: $0) }),
           let png = rep.representation(using: .png, properties: [:]) {
            wrote = board.setData(png, forType: .png) || wrote
        }
        if let tiff = image.tiffRepresentation {
            wrote = board.setData(tiff, forType: .tiff) || wrote
        }
        return wrote
    }
}
