import AppKit
import SwiftUI

class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

class TerminalPanel: NSPanel {
    private let sessionStore: SessionStore

    init(sessionStore: SessionStore) {
        self.sessionStore = sessionStore

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 10),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        isFloatingPanel = true
        level = .floating
        isMovableByWindowBackground = false
        backgroundColor = .clear
        hasShadow = true
        isOpaque = false
        animationBehavior = .none
        hidesOnDeactivate = false

        let contentView = PanelContentView(
            sessionStore: sessionStore,
            onClose: { [weak self] in self?.hidePanel() },
            onToggleExpand: nil
        )
        let hosting = ClickThroughHostingView(rootView: contentView)
        self.contentView = hosting

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: self
        )
    }

    func showPanel(below rect: NSRect) {
        if let screen = NSScreen.main {
            let panelWidth: CGFloat = 380
            let x = rect.midX - panelWidth / 2
            let y = screen.visibleFrame.maxY - frame.height
            setFrameOrigin(NSPoint(x: x, y: y))
        }
        makeKeyAndOrderFront(nil)
    }

    func showPanelCentered(on screen: NSScreen) {
        let screenFrame = screen.frame
        let x = screenFrame.midX - frame.width / 2
        // Position flush against notch: use visible frame top (accounts for menu bar)
        let menuBarBottom = screenFrame.maxY - (screenFrame.height - screen.visibleFrame.height - screen.visibleFrame.origin.y)
        let y = menuBarBottom - frame.height
        setFrameOrigin(NSPoint(x: x, y: y))
        makeKeyAndOrderFront(nil)
    }

    func hidePanel() {
        orderOut(nil)
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        hidePanel()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
