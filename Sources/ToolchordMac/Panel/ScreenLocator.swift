import AppKit

/// Chooses the display for the palette: the one holding the frontmost app's
/// key window when it can be determined, otherwise the pointer's display.
///
/// `NSScreen.main` is unreliable here: in an accessory (LSUIElement) app it
/// can report the menu-bar display instead of the display with the active
/// window (FB11506568). Window bounds from `CGWindowListCopyWindowInfo` are
/// available without Screen Recording or Accessibility permission.
@MainActor
enum ScreenLocator {
    static func targetScreen(for application: NSRunningApplication?) -> NSScreen {
        if let pid = application?.processIdentifier,
           let frame = frontmostWindowFrame(ownedBy: pid),
           let screen = screen(bestContaining: frame) {
            return screen
        }
        return pointerScreen()
    }

    static func pointerScreen() -> NSScreen {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    /// The topmost normal-level window of `pid`, in Cocoa (bottom-left origin) coordinates.
    static func frontmostWindowFrame(ownedBy pid: pid_t) -> CGRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        // The list is ordered front to back.
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  bounds.width >= 80, bounds.height >= 60 else {
                continue
            }
            return cocoaRect(fromQuartz: bounds)
        }
        return nil
    }

    /// Quartz window bounds use a top-left origin on the primary display.
    static func cocoaRect(fromQuartz rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func screen(bestContaining rect: CGRect) -> NSScreen? {
        var best: (screen: NSScreen, area: CGFloat)?
        for screen in NSScreen.screens {
            let overlap = screen.frame.intersection(rect)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > (best?.area ?? 0) { best = (screen, area) }
        }
        return best?.screen
    }

    /// A frame of `size`, horizontally centered and placed in the upper part
    /// of `screen`'s visible area, clamped to fit.
    static func frame(for size: CGSize, on screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        let width = min(size.width, visible.width - 32)
        let height = min(size.height, visible.height - 32)
        let x = visible.midX - width / 2
        // Keep the top edge about a fifth of the way down, like Spotlight.
        let top = visible.maxY - max(16, (visible.height - height) * 0.28)
        return CGRect(x: x.rounded(), y: (top - height).rounded(), width: width.rounded(), height: height.rounded())
    }
}
