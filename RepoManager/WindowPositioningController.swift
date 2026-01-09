import Foundation
import AppKit

@MainActor
final class WindowPositioningController: NSObject, NSWindowDelegate {
    static let shared = WindowPositioningController()

    nonisolated static let autoHideEnabledDefaultsKey = "RepoManager.autoHideMainWindowEnabled"

    var isAutoHideEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.autoHideEnabledDefaultsKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.autoHideEnabledDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.autoHideEnabledDefaultsKey)
        }
    }

    /// Provided by SwiftUI environment so we can recreate the window if it was closed.
    var openMainWindow: (() -> Void)?

    private weak var mainWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []

    func registerMainWindow(_ window: NSWindow) {
        guard mainWindow !== window else { return }
        mainWindow = window

        window.delegate = self
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.moveToActiveSpace)

        installObserversIfNeeded()
    }

    func showMainWindowUnderMouse() {
        if mainWindow == nil {
            openMainWindow?()
        }

        // The window may become available on the next run loop if it was just created.
        DispatchQueue.main.async { [weak self] in
            self?.showUnderMouseIfPossible()
        }
    }

    private func showUnderMouseIfPossible() {
        guard let window = mainWindow else { return }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        let visible = (screen?.visibleFrame ?? NSScreen.main?.visibleFrame) ?? NSRect(x: 0, y: 0, width: 1000, height: 800)

        var frame = window.frame
        var origin = CGPoint(x: mouse.x - frame.width / 2, y: mouse.y - frame.height / 2)

        origin.x = min(max(origin.x, visible.minX), visible.maxX - frame.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - frame.height)

        frame.origin = origin

        window.collectionBehavior.insert(.moveToActiveSpace)
        window.setFrame(frame, display: true, animate: false)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Ask the content view to focus the search field.
        NotificationCenter.default.post(name: .focusRepoSearchField, object: nil)
    }

    func hideMainWindow() {
        mainWindow?.orderOut(nil)
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === mainWindow else { return }
        guard isAutoHideEnabled else { return }
        window.orderOut(nil)
    }

    // MARK: - Observers

    private func installObserversIfNeeded() {
        guard observers.isEmpty else { return }

        observers.append(
            NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.isAutoHideEnabled else { return }
                self.hideMainWindow()
            }
        )
    }
}
