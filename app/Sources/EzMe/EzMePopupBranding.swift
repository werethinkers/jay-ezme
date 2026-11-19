import AppKit

// Every popup in KeyDo carries the KeyDo icon: sheets (dialogs that slide down) and popovers.
// The icon is a small tile in the top right corner. It never takes clicks. Alerts already show the KeyDo app icon,
// and the backslash popup has its own KeyDo logo button.

final class KeyDoBadgeView: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("keydo.popup.badge")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.973, green: 0.937, blue: 0.882, alpha: 1).cgColor
        layer?.cornerRadius = 7
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor(calibratedWhite: 0, alpha: 0.12).cgColor
        let icon = NSImageView(frame: NSRect(x: 3, y: 3, width: frameRect.width - 6, height: frameRect.height - 6))
        icon.image = keyDoIconImage()
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.autoresizingMask = [.width, .height]
        addSubview(icon)
        toolTip = "KeyDo"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Clicks go to whatever is under the badge.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

enum KeyDoPopupBranding {
    private static var installed = false

    @MainActor static func install() {
        guard !installed else { return }
        installed = true
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                guard let window = note.object as? NSWindow, window.isSheet, !(window is NSSavePanel) else { return }
                // Alerts already show the KeyDo app icon.
                if window.className.contains("Alert") { return }
                badge(window.contentView)
            }
        }
        NotificationCenter.default.addObserver(forName: NSPopover.willShowNotification, object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                guard let popover = note.object as? NSPopover else { return }
                badge(popover.contentViewController?.view)
            }
        }
    }

    @MainActor private static func badge(_ host: NSView?) {
        guard let host else { return }
        if host.subviews.contains(where: { $0.identifier == KeyDoBadgeView.identifier }) { return }
        let tile = KeyDoBadgeView(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
        tile.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(tile, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            tile.widthAnchor.constraint(equalToConstant: 26),
            tile.heightAnchor.constraint(equalToConstant: 26),
            tile.topAnchor.constraint(equalTo: host.topAnchor, constant: 8),
            tile.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -8)
        ])
    }
}
