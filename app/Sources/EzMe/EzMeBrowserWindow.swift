// The browser in its own window. Every window has its own tab list, selected tab, split view and web pages
// (its own EzMeBrowserTabs). Sign-ins are shared with the main browser, because all windows use the same website data.
// A separate window does not save its tabs: closing it closes them. Bookmarks are read from the main browser.
import SwiftUI
import AppKit

struct BrowserWindowView: View {
    @StateObject private var state = EzMeBrowserTabs.standaloneInstance()
    @State private var showControls = true

    var body: some View {
        BrowserWorkspace(state: state, showControls: $showControls)
            .padding(10)
            .frame(minWidth: 720, minHeight: 520)
    }
}

extension EzMeBrowserTabs {
    /// A browser that starts on its own Home tab and never writes to the main browser's saved tabs.
    static func standaloneInstance() -> EzMeBrowserTabs {
        let browser = EzMeBrowserTabs()
        browser.standalone = true
        browser.resetForWindow()
        return browser
    }

    func resetForWindow() {
        let home = EzMeBrowserTab(id: Self.homeTabID, title: "Home", url: Self.homeURL)
        tabs = [home]
        selectedID = Self.homeTabID
        address = Self.homeURL
        splitEnabled = false
        secondaryID = ""
    }
}
