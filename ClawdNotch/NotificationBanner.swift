import AppKit
import SwiftUI

/// Custom notification banner — slides in from top-right with Claw'd pixel art icon
class NotificationBanner {
    static let shared = NotificationBanner()
    private var window: NSWindow?
    private var hideTimer: Timer?

    func show(title: String, body: String, color: NSColor) {
        DispatchQueue.main.async { [weak self] in
            self?.hideTimer?.invalidate()
            self?.window?.orderOut(nil)
            self?.presentBanner(title: title, body: body, color: color)
        }
    }

    private func presentBanner(title: String, body: String, color: NSColor) {
        guard let screen = NSScreen.main else { return }

        let bannerWidth: CGFloat = 320
        let bannerHeight: CGFloat = 72
        let padding: CGFloat = 12

        let startX = screen.frame.maxX - bannerWidth - padding
        let startY = screen.frame.maxY - bannerHeight - padding - 30 // below menu bar

        let swiftColor = Color(nsColor: color)

        let view = NSHostingView(rootView: BannerView(
            title: title,
            message: body,
            color: swiftColor,
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        ))
        view.frame = NSRect(x: 0, y: 0, width: bannerWidth, height: bannerHeight)

        let panel = NSPanel(
            contentRect: NSRect(x: startX + bannerWidth, y: startY, width: bannerWidth, height: bannerHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = false
        panel.contentView = view

        window = panel
        panel.orderFrontRegardless()

        // Slide in
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(
                NSRect(x: startX, y: startY, width: bannerWidth, height: bannerHeight),
                display: true
            )
        }

        // Auto-dismiss after 4 seconds
        hideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func dismiss() {
        guard let window else { return }
        let targetFrame = NSRect(
            x: window.frame.origin.x + window.frame.width,
            y: window.frame.origin.y,
            width: window.frame.width,
            height: window.frame.height
        )
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(targetFrame, display: true)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.window?.orderOut(nil)
            self?.window = nil
        })
    }
}

struct BannerView: View {
    let title: String
    let message: String
    let color: Color
    let onDismiss: () -> Void

    // Claw'd sprite
    private let sprite: [[Int]] = [
        [0,0,1,0,0,0,0,0,1,0,0],
        [0,0,1,1,1,1,1,1,1,0,0],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,1,2,3,2,2,2,3,2,1,0],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,0,1,1,1,1,1,1,1,0,0],
        [0,0,1,0,1,0,1,0,1,0,0],
    ]

    var body: some View {
        HStack(spacing: 12) {
            // Claw'd pixel art icon
            Canvas { context, size in
                let px: CGFloat = 3.5
                let cols = sprite[0].count
                let rows = sprite.count
                let ox = (size.width - CGFloat(cols) * px) / 2
                let oy = (size.height - CGFloat(rows) * px) / 2

                let colors: [Int: Color] = [
                    1: color,
                    2: color.opacity(0.5),
                    3: .white,
                ]

                for (y, row) in sprite.enumerated() {
                    for (x, val) in row.enumerated() {
                        guard val != 0, let c = colors[val] else { continue }
                        let rect = CGRect(x: ox + CGFloat(x) * px, y: oy + CGFloat(y) * px, width: px, height: px)
                        context.fill(Path(rect), with: .color(c))
                    }
                }
            }
            .frame(width: 44, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { onDismiss() }
    }
}
