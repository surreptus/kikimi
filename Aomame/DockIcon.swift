import AppKit
import SwiftUI

/// The Dock icon follows the app's light or dark appearance while it runs. Finder and the Applications folder always
/// show the dark icon from the asset catalog, since the system draws those from the app bundle.
@MainActor
enum DockIcon {
    private static var dark: NSImage?

    static func show(for scheme: ColorScheme) {
        dark = dark ?? NSApp.applicationIconImage   // the catalog icon, before it is ever replaced
        NSApp.applicationIconImage = scheme == .dark ? dark : NSImage(named: "IconLight") ?? dark
    }
}
