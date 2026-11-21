// A picture filter for a Wish Studio app's artwork, using the same Prism filters as the Video Editor.
// Change it and the app's templates are redrawn with the filter, and a published app is refreshed.
import SwiftUI
import AppKit
import CoreImage

@MainActor enum WishFilterStore {
    private static let context = CIContext()
    private static func idKey(_ appID: String) -> String { "wishFilter.id." + appID }
    private static func amountKey(_ appID: String) -> String { "wishFilter.amount." + appID }

    static func selection(_ appID: String) -> (filter: PrismFilter, amount: Double)? {
        guard let id = UserDefaults.standard.string(forKey: idKey(appID)), let filter = PrismFilter.all.first(where: { $0.id == id }) else { return nil }
        let stored = UserDefaults.standard.object(forKey: amountKey(appID)) as? Double
        return (filter, min(filter.range.upperBound, max(filter.range.lowerBound, stored ?? filter.start)))
    }

    static func set(_ filterID: String?, appID: String) {
        UserDefaults.standard.set(filterID, forKey: idKey(appID))
        UserDefaults.standard.removeObject(forKey: amountKey(appID))
    }

    static func setAmount(_ amount: Double, appID: String) { UserDefaults.standard.set(amount, forKey: amountKey(appID)) }

    /// The picture with the app's filter, or the same picture when none is chosen.
    static func apply(_ image: NSImage, appID: String) -> NSImage {
        guard let chosen = selection(appID), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let source = CIImage(cgImage: cg)
        let changed = chosen.filter.apply(source.clampedToExtent(), chosen.amount).cropped(to: source.extent)
        guard let out = context.createCGImage(changed, from: source.extent) else { return image }
        return NSImage(cgImage: out, size: image.size)
    }
}
