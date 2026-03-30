import AppKit
import SwiftUI

/// An invisible window that sits behind the notch area.
/// When the mouse hovers over the notch or any additional hover rect, it fires a callback to show the main panel.
/// Expands downward with a bounce animation when any session is working.
class NotchWindow: NSPanel {
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var screenObserver: Any?
    private var statusObserver: Any?
    var onHover: (() -> Void)?
    /// Additional rects (in screen coordinates) that should also trigger hover.
    /// Each closure is called at check-time so the rect stays up-to-date.
    var additionalHoverRects: [() -> NSRect] = []
    /// Closure to check if the main panel is currently visible.
    /// When the panel is visible, the notch stays in hover-grown size.
    var isPanelVisible: (() -> Bool)?

    /// Detected notch dimensions (updated on screen change).
    private var notchWidth: CGFloat = 180
    private var notchHeight: CGFloat = 37

    /// Whether the notch is currently expanded (wider, for working state)
    private var isExpanded = false

    /// Debounce timer for collapsing — prevents rapid expand/collapse cycling
    /// when terminal status flickers between .working and .idle.
    private var collapseDebounceTimer: Timer?

    /// Whether the mouse is currently hovering over the notch
    private var isHovered = false
    /// The pill-shaped background view shown when expanded
    private let pillView = NotchPillView()

    /// SwiftUI content overlay shown inside the pill when expanded
    private var pillContentHost: NSHostingView<NotchPillContent>?

    init(onHover: @escaping () -> Void) {
        self.onHover = onHover

        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        hasShadow = false
        isOpaque = false
        animationBehavior = .none
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = false
        alphaValue = 1

        // Set up the pill view (always visible)
        if let cv = contentView {
            pillView.frame = cv.bounds
            pillView.autoresizingMask = [.width, .height]
            pillView.alphaValue = 1
            cv.addSubview(pillView)
            cv.wantsLayer = true
            cv.layer?.masksToBounds = false

            // SwiftUI content overlay inside the pill
            let hostView = NSHostingView(rootView: NotchPillContent())
            hostView.frame = cv.bounds
            hostView.autoresizingMask = [.width, .height]
            hostView.alphaValue = 1
            hostView.wantsLayer = true
            hostView.layer?.backgroundColor = .clear
            cv.addSubview(hostView)
            pillContentHost = hostView
        }

        // Accept file drags so hovering a dragged file over the notch opens the panel
        registerForDraggedTypes([.fileURL, .URL])

        detectNotchSize()
        positionAtNotch()
        orderFrontRegardless()
        setupTracking()
        observeScreenChanges()
        observeStatusChanges()
    }

    // MARK: - Drag destination (treat drag-over like hover)

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onHover?()
        return .generic
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .generic
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        // We don't actually accept the drop — just trigger the hover
        return false
    }

    deinit {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Expand / Collapse

    private func observeStatusChanges() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NotchyNotchStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if !(self?.isExpanded ?? false) {
                self?.updateExpansionState()
            }
            else {
                self?.collapseDebounceTimer?.invalidate()
                self?.collapseDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
                    guard let self, self.isExpanded else { return }
                    self.collapseDebounceTimer = nil
                    self.updateExpansionState()
                }
            }
        }
        // Also poll on a timer to catch status changes from the observation timer
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.updateExpansionState()
        }
    }

    private func updateExpansionState() {
        let shouldExpand = NotchDisplayState.current != .idle

        if shouldExpand && !isExpanded {
            collapseDebounceTimer?.invalidate()
            collapseDebounceTimer = nil
            expandWithBounce()
        } else if !shouldExpand && isExpanded {
            // Debounce collapse to avoid rapid cycling when terminal status
            // flickers between .working and .idle during transitions.
            guard collapseDebounceTimer == nil else { return }
            collapseDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.collapseDebounceTimer = nil
                // Re-check — state may have changed during the debounce
                if NotchDisplayState.current == .idle && self.isExpanded {
                    self.collapse()
                }
            }
        } else if shouldExpand && isExpanded {
            // Still expanded and should be — cancel any pending collapse
            collapseDebounceTimer?.invalidate()
            collapseDebounceTimer = nil
        }
    }

    private func expandWithBounce() {
        isExpanded = true
        guard let screen = NSScreen.builtIn else { return }
        let screenFrame = screen.frame

        let targetWidth: CGFloat = notchWidth + 80
        var targetFrame = NSRect(
            x: screenFrame.midX - targetWidth / 2,
            y: screenFrame.maxY - notchHeight,
            width: targetWidth,
            height: notchHeight
        )
        if isHovered {
            targetFrame = applyHoverGrow(to: targetFrame)
        }

        // Show pill view and content
        pillView.alphaValue = 1
        pillContentHost?.alphaValue = 1

        // Smooth ease-out animation (no bounce)
        let startWidth = frame.width
        let startTime = CACurrentMediaTime()
        let duration: Double = 0.3
        let midX = screen.frame.midX

        let displayLink = CVDisplayLinkWrapper { [weak self] in
            guard let self else { return false }
            let elapsed = CACurrentMediaTime() - startTime
            let t = min(elapsed / duration, 1.0)

            let ease = 1.0 - pow(1.0 - t, 3.0)

            let currentWidth = startWidth + (targetFrame.width - startWidth) * ease
            let currentX = midX - currentWidth / 2

            DispatchQueue.main.async {
                self.setFrame(
                    NSRect(x: currentX, y: targetFrame.origin.y, width: currentWidth, height: targetFrame.height),
                    display: true
                )
            }
            return t < 1.0
        }
        displayLink.start()
    }

    private func collapse() {
        isExpanded = false

        // Fade out the status content but keep the pill visible
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.pillContentHost?.animator().alphaValue = 0
        }

        guard let screen = NSScreen.builtIn else { return }
        let screenFrame = screen.frame

        var targetFrame = NSRect(
            x: screenFrame.midX - notchWidth / 2,
            y: screenFrame.maxY - notchHeight,
            width: notchWidth,
            height: notchHeight
        )
        if isHovered {
            targetFrame = applyHoverGrow(to: targetFrame)
        }

        let startFrame = frame
        let startTime = CACurrentMediaTime()
        let duration: Double = 0.3

        let displayLink = CVDisplayLinkWrapper { [weak self] in
            guard let self else { return false }
            let elapsed = CACurrentMediaTime() - startTime
            let t = min(elapsed / duration, 1.0)

            // Ease out
            let ease = 1.0 - pow(1.0 - t, 3.0)

            let currentX = startFrame.origin.x + (targetFrame.origin.x - startFrame.origin.x) * ease
            let currentWidth = startFrame.width + (targetFrame.width - startFrame.width) * ease

            DispatchQueue.main.async {
                self.setFrame(
                    NSRect(x: currentX, y: targetFrame.origin.y, width: currentWidth, height: targetFrame.height),
                    display: true
                )
                if t >= 1.0 {
                    // Show the idle content once collapse animation finishes
                    self.pillContentHost?.alphaValue = 1
                }
            }
            return t < 1.0
        }
        displayLink.start()
    }

    /// Spring / bounce easing — overshoots then settles
    private static func bounceEase(_ t: Double) -> Double {
        let omega = 12.0  // frequency
        let zeta = 0.4    // damping
        return 1.0 - exp(-zeta * omega * t) * cos(sqrt(1.0 - zeta * zeta) * omega * t)
    }

    // MARK: - Notch size detection

    private func detectNotchSize() {
        guard let screen = NSScreen.builtIn else { return }

        if #available(macOS 12.0, *),
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            // Notch spans the gap between the two auxiliary areas
            notchWidth = right.minX - left.maxX
            notchHeight = screen.frame.maxY - min(left.minY, right.minY)
        } else {
            // No notch (external display, older Mac) — use sensible defaults
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            notchWidth = 180
            notchHeight = max(menuBarHeight, 25)
        }
    }

    // MARK: - Positioning

    private func positionAtNotch() {
        guard let screen = NSScreen.builtIn else { return }
        let screenFrame = screen.frame
        let x = screenFrame.midX - notchWidth / 2
        let y = screenFrame.maxY - notchHeight
        setFrame(NSRect(x: x, y: y, width: notchWidth, height: notchHeight), display: true)
    }

    // MARK: - Mouse tracking

    private func setupTracking() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.checkMouse()
        }
        // Local monitor catches events when the mouse is over this window itself
        // (global monitors only fire for events outside the app's windows)
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.checkMouse()
            return event
        }
    }

    private func checkMouse() {
        let mouseLocation = NSEvent.mouseLocation

        // Check the notch area itself
        guard let screen = NSScreen.builtIn else { return }
        let screenFrame = screen.frame
        let effectiveWidth = isExpanded ? notchWidth + 80 : notchWidth
        let notchRect = NSRect(
            x: screenFrame.midX - effectiveWidth / 2,
            y: screenFrame.maxY - notchHeight,
            width: effectiveWidth,
            height: notchHeight + 1  // +1 so the top screen edge (maxY) is inside the rect
        )

        let mouseInNotch = notchRect.contains(mouseLocation)
        let mouseInAdditional = additionalHoverRects.contains { $0().contains(mouseLocation) }

        if mouseInNotch || mouseInAdditional {
            if !isHovered {
                isHovered = true
                hoverGrow()
            }
            onHover?()
            return
        }

        if isHovered {
            // Keep hover-grown size while the panel is visible
            let panelShowing = isPanelVisible?() ?? false
            if !panelShowing {
                isHovered = false
                hoverShrink()
            }
        }
    }

    /// Called when the panel hides — forces the notch back to normal size.
    func endHover() {
        guard isHovered else { return }
        isHovered = false
        hoverShrink()
    }

    // MARK: - Hover grow / shrink

    private static let hoverGrowX: CGFloat = 0 + NotchPillView.earRadius * 2  // extra width for ear protrusions
    private static let hoverGrowY: CGFloat = 2

    /// Applies hover grow offset to any frame.
    private func applyHoverGrow(to rect: NSRect) -> NSRect {
        NSRect(
            x: rect.origin.x - Self.hoverGrowX / 2,
            y: rect.origin.y - Self.hoverGrowY,
            width: rect.width + Self.hoverGrowX,
            height: rect.height + Self.hoverGrowY
        )
    }

    private func hoverGrow() {
        pillView.isHovered = true
        pillContentHost?.rootView = NotchPillContent(isHovering: true)
        setFrame(applyHoverGrow(to: frame), display: true)
    }

    private func hoverShrink() {
        pillView.isHovered = false
        pillContentHost?.rootView = NotchPillContent(isHovering: false)
        guard let screen = NSScreen.builtIn else { return }
        let screenFrame = screen.frame
        let baseWidth = isExpanded ? notchWidth + 80 : notchWidth
        let targetFrame = NSRect(
            x: screenFrame.midX - baseWidth / 2,
            y: screenFrame.maxY - notchHeight,
            width: baseWidth,
            height: notchHeight
        )
        setFrame(targetFrame, display: true)
    }

    // MARK: - Observers

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.detectNotchSize()
            self?.positionAtNotch()
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - NSScreen helper

extension NSScreen {
    /// Returns the built-in display (the one with the notch), or the main screen as fallback.
    static var builtIn: NSScreen? {
        screens.first { screen in
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            return CGDisplayIsBuiltin(id) != 0
        } ?? main
    }
}

// MARK: - Notch pill background view

/// A view that draws a rounded pill shape extending below the notch.
/// When hovered, curved protrusions ("ears") appear at the bottom-left and bottom-right,
/// creating a smooth concave transition out from the notch body.
class NotchPillView: NSView {
    var isHovered: Bool = false {
        didSet {
            guard isHovered != oldValue else { return }
            needsDisplay = true
            needsLayout = true
        }
    }

    private let shapeLayer = CAShapeLayer()
    static let earRadius: CGFloat = 10

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.backgroundColor = .clear
        shapeLayer.fillColor = NSColor.black.cgColor
        layer?.addSublayer(shapeLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateShape()
    }

    private func updateShape() {
        let w = bounds.width
        let h = bounds.height
        guard w > 0, h > 0 else { return }

        let ear = Self.earRadius
        shapeLayer.frame = CGRect(x: 0, y: 0, width: w, height: h)

        let path = CGMutablePath()

        if isHovered {
            // Main body is inset by ear on each side; ears fill the extra space
            let bodyLeft = ear
            let bodyRight = w - ear

            // Left ear tip (bottom-left corner of view)
            path.move(to: CGPoint(x: 0, y: 0))
            // Concave curve up into the main body's left edge
            path.addQuadCurve(
                to: CGPoint(x: bodyLeft, y: ear),
                control: CGPoint(x: bodyLeft , y: 0)
            )
            // Left edge up to top
            path.addLine(to: CGPoint(x: bodyLeft, y: h))
            // Top edge
            path.addLine(to: CGPoint(x: bodyRight, y: h))
            // Right edge down
            path.addLine(to: CGPoint(x: bodyRight, y: ear))
            // Concave curve out to right ear tip
            path.addQuadCurve(
                to: CGPoint(x: w, y: 0),
                control: CGPoint(x: bodyRight, y: 0)
            )
        } else {
            let cr: CGFloat = 9.5
            path.move(to: CGPoint(x: 0, y: h))
            path.addLine(to: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: w, y: cr))
            path.addQuadCurve(
                to: CGPoint(x: w - cr, y: 0),
                control: CGPoint(x: w, y: 0)
            )
            path.addLine(to: CGPoint(x: cr, y: 0))
            path.addQuadCurve(
                to: CGPoint(x: 0, y: cr),
                control: CGPoint(x: 0, y: 0)
            )
            path.closeSubpath()
        }

        shapeLayer.path = path
    }
}

// MARK: - Notch display state

enum NotchDisplayState: Equatable {
    case idle
    case working
    case waitingForInput
    case taskCompleted

    /// Shows the state of the most recently updated active session.
    /// Stale sessions (>5 min) are ignored for notch display.
    static var current: NotchDisplayState {
        let sessions = SessionStore.shared.sessions
        let staleThreshold = Date().addingTimeInterval(-300) // 5 minutes

        // Find the most recently updated non-idle session that isn't stale
        let active = sessions
            .filter { $0.terminalStatus != .idle && $0.lastUpdatedAt > staleThreshold }
            .sorted { $0.lastUpdatedAt > $1.lastUpdatedAt }

        guard let latest = active.first else { return .idle }

        switch latest.terminalStatus {
        case .working: return .working
        case .waitingForInput: return .waitingForInput
        case .taskCompleted: return .taskCompleted
        default: return .idle
        }
    }
}

// MARK: - Notch pill SwiftUI content

struct NotchPillContent: View {
    var isHovering: Bool = false
    @State private var displayState: NotchDisplayState = .idle

    private var allSessions: [TerminalSession] {
        SessionStore.shared.sessions
    }

    var body: some View {
        ZStack {
            HStack {
                // Left: Claude logo
                NotchLogo(state: displayState)

                Spacer()

                // Right: tool-specific icon or status (persists last state)
                NotchToolIcon(state: displayState, sessions: allSessions)
            }
            .padding(.horizontal, 12 + (isHovering ? NotchPillView.earRadius : 0))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .offset(y: isHovering ? -3 : -2)
        .onAppear { displayState = .current }
        .onReceive(NotificationCenter.default.publisher(for: .NotchyNotchStatusChanged)) { _ in
            displayState = .current
        }
        .onChange(of: displayState) {
            NotificationCenter.default.post(name: .NotchyNotchStatusChanged, object: nil)
        }
    }
}

/// 8-bit pixel bear that lives in the notch
/// Claw'd — pixel art mascot with animation frames
struct NotchLogoOLD: View {
    let state: NotchDisplayState
    @State private var bounce = false
    @State private var clawWiggle = false

    private var color: Color {
        switch state {
        case .working: return Color(red: 0.9, green: 0.45, blue: 0.2)
        case .waitingForInput: return Color(red: 0.4, green: 0.75, blue: 1.0)
        case .taskCompleted: return Color(red: 0.4, green: 0.9, blue: 0.5)
        case .idle: return Color(white: 0.3)
        }
    }

    private var eyeColor: Color {
        state == .idle ? Color(white: 0.45) : .white
    }

    var body: some View {
        ZStack {
            // Claw'd drawn with SwiftUI shapes
            Canvas { context, size in
                let px: CGFloat = 2.0
                let ox: CGFloat = 0  // offset x
                let oy: CGFloat = 1  // offset y

                let c = color
                let dark = Color(white: 0.08)
                let eye = eyeColor

                // Row 0: claws up    _  ████  _
                //                   /          \
                // Simplified Claw'd sprite:
                let sprite: [(Int, Int, Color)] = [
                    // Claws (top)
                    (1, 0, c), (2, 0, c),                               // left claw
                    (7, 0, c), (8, 0, c),                               // right claw
                    (0, 1, c), (1, 1, c),                               // left claw lower
                    (8, 1, c), (9, 1, c),                               // right claw lower

                    // Head top
                    (2, 1, c), (3, 1, c), (4, 1, c), (5, 1, c), (6, 1, c), (7, 1, c),

                    // Head body
                    (1, 2, c), (2, 2, c), (3, 2, c), (4, 2, c), (5, 2, c), (6, 2, c), (7, 2, c), (8, 2, c),

                    // Eyes row
                    (1, 3, c), (2, 3, c),
                    (3, 3, eye), (4, 3, dark),  // left eye
                    (5, 3, c),
                    (6, 3, eye), (7, 3, dark),  // right eye
                    (8, 3, c),

                    // Body
                    (1, 4, c), (2, 4, c), (3, 4, c), (4, 4, c), (5, 4, c), (6, 4, c), (7, 4, c), (8, 4, c),

                    // Bottom body
                    (2, 5, c), (3, 5, c), (4, 5, c), (5, 5, c), (6, 5, c), (7, 5, c),

                    // Legs
                    (2, 6, c), (3, 6, c),       // left legs
                    (6, 6, c), (7, 6, c),       // right legs
                ]

                for (x, y, col) in sprite {
                    let rect = CGRect(
                        x: ox + CGFloat(x) * px,
                        y: oy + CGFloat(y) * px,
                        width: px,
                        height: px
                    )
                    context.fill(Path(rect), with: .color(col))
                }
            }
            .frame(width: 22, height: 16)
        }
        .shadow(color: color.opacity(state == .idle ? 0 : 0.5), radius: 4)
        .offset(y: bounce ? -1 : 1)
        .rotationEffect(.degrees(clawWiggle ? 3 : -3))
        .animation(
            state == .working
                ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                : state == .waitingForInput
                    ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                    : .easeInOut(duration: 0.3),
            value: bounce
        )
        .animation(
            state == .waitingForInput
                ? .easeInOut(duration: 0.4).repeatForever(autoreverses: true)
                : .default,
            value: clawWiggle
        )
        .onAppear {
            bounce = true
            clawWiggle = true
        }
    }
}

/// Tool-specific icon for the notch right side
struct NotchToolIcon: View {
    let state: NotchDisplayState
    let sessions: [TerminalSession]

    private var latestTool: String {
        // Prefer working session with a real tool name, then any session with a tool, sorted by recency
        let sorted = sessions.sorted(by: { $0.lastUpdatedAt > $1.lastUpdatedAt })
        if let active = sorted.first(where: { $0.terminalStatus == .working && !$0.lastToolName.isEmpty }) {
            return active.lastToolName
        }
        return sorted.first(where: { !$0.lastToolName.isEmpty })?.lastToolName ?? ""
    }

    private var iconName: String {
        switch latestTool {
        case "Bash": return "terminal"
        case "Edit", "MultiEdit": return "pencil"
        case "Write": return "doc.badge.plus"
        case "Read": return "eye"
        case "Grep": return "magnifyingglass"
        case "Glob": return "folder"
        case "Agent": return "person.2"
        case "WebSearch": return "globe"
        case "WebFetch": return "arrow.down.doc"
        case "Task": return "checklist"
        default: return "sparkles"
        }
    }

    var body: some View {
        switch state {
        case .working:
            Image(systemName: iconName)
                .font(.system(size: 11))
                .foregroundColor(Color(red: 0.85, green: 0.55, blue: 0.2))
                .transition(.scale.combined(with: .opacity))
        case .waitingForInput:
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 11))
                .foregroundColor(Color(red: 0.4, green: 0.8, blue: 1.0))
                .transition(.scale.combined(with: .opacity))
        case .taskCompleted:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(red: 0.4, green: 0.9, blue: 0.5))
                .transition(.scale.combined(with: .opacity))
        case .idle:
            Image(systemName: iconName)
                .font(.system(size: 11))
                .foregroundColor(Color(white: 0.35))
                .transition(.scale.combined(with: .opacity))
        }
    }
}

/// Claw'd — pixel art mascot with animation frames
struct NotchLogo: View {
    let state: NotchDisplayState
    @State private var frame: Int = 0
    @State private var timer: Timer?

    private static let idle: [[Int]] = [
        [0,0,1,0,0,0,0,0,1,0,0],
        [0,0,1,1,1,1,1,1,1,0,0],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,1,2,3,2,2,2,3,2,1,0],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,0,1,1,1,1,1,1,1,0,0],
        [0,0,5,0,5,0,5,0,5,0,0],
    ]
    private static let work1: [[Int]] = [
        [0,4,1,0,0,4,0,0,1,4,0],
        [0,0,1,1,1,1,1,1,1,0,0],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,1,2,3,2,2,2,3,2,1,0],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,0,1,1,1,1,1,1,1,0,0],
        [0,0,5,0,5,0,5,0,5,0,0],
    ]
    private static let work2: [[Int]] = [
        [4,0,1,0,4,0,4,0,1,0,4],
        [0,0,1,1,1,1,1,1,1,0,0],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,1,2,2,2,2,2,2,2,1,0],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,0,1,1,1,1,1,1,1,0,0],
        [0,0,0,5,0,5,0,5,0,0,0],
    ]
    private static let wait1: [[Int]] = [
        [0,4,1,0,0,4,0,0,1,4,0],
        [0,0,1,1,1,1,1,1,1,0,0],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,1,2,3,2,2,2,3,2,1,0],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,0,1,1,1,1,1,1,1,0,0],
        [0,5,0,0,5,0,5,0,0,5,0],
    ]
    private static let wait2: [[Int]] = [
        [4,0,1,4,0,0,0,4,1,0,4],
        [0,0,1,1,1,1,1,1,1,0,0],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,1,2,3,2,2,2,3,2,1,0],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,0,1,1,1,1,1,1,1,0,0],
        [0,0,5,0,5,0,5,0,5,0,0],
    ]
    private static let done: [[Int]] = [
        [4,4,1,0,4,4,4,0,1,4,4],
        [4,0,1,1,1,1,1,1,1,0,4],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,1,2,3,2,2,2,3,2,1,0],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,0,1,1,1,1,1,1,1,0,0],
        [0,0,5,0,5,0,5,0,5,0,0],
    ]
    private static let sleep: [[Int]] = [
        [0,0,1,0,0,0,0,0,1,4,4],
        [0,0,1,1,1,1,1,1,1,0,4],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,1,2,2,2,2,2,2,2,1,0],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,0,1,1,1,1,1,1,1,0,0],
        [0,0,5,0,5,0,5,0,5,0,0],
    ]

    private var currentSprite: [[Int]] {
        switch state {
        case .working: return frame % 2 == 0 ? Self.work1 : Self.work2
        case .waitingForInput: return frame % 2 == 0 ? Self.wait1 : Self.wait2
        case .taskCompleted: return Self.done
        case .idle: return Self.idle
        }
    }

    private var colors: [Int: Color] {
        switch state {
        case .idle:
            return [1:.init(white:0.53), 2:.init(white:0.35), 3:.init(white:0.85), 4:.init(white:0.4), 5:.init(white:0.4)]
        case .working:
            return [1:.init(red:0.76,green:0.45,blue:0.31), 2:.init(red:0.55,green:0.29,blue:0.19), 3:.white, 4:.init(red:1,green:0.84,blue:0), 5:.init(red:0.63,green:0.35,blue:0.23)]
        case .waitingForInput:
            return [1:.init(red:0.29,green:0.56,blue:0.85), 2:.init(red:0.16,green:0.35,blue:0.54), 3:.white, 4:.init(red:0.49,green:0.78,blue:0.97), 5:.init(red:0.23,green:0.48,blue:0.73)]
        case .taskCompleted:
            return [1:.init(red:0.35,green:0.73,blue:0.37), 2:.init(red:0.21,green:0.48,blue:0.22), 3:.white, 4:.init(red:1,green:0.84,blue:0), 5:.init(red:0.27,green:0.6,blue:0.29)]
        }
    }

    var body: some View {
        Canvas { context, size in
            let px: CGFloat = 2.0
            let sprite = currentSprite
            let cols = colors
            for (y, row) in sprite.enumerated() {
                for (x, val) in row.enumerated() {
                    guard val != 0, let color = cols[val] else { continue }
                    let rect = CGRect(x: CGFloat(x)*px, y: CGFloat(y)*px, width: px, height: px)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(width: 22, height: 16)
        .shadow(color: (colors[1] ?? .clear).opacity(state == .idle ? 0 : 0.5), radius: 4)
        .onAppear { startAnim() }
        .onDisappear { timer?.invalidate() }
        .onChange(of: state) { startAnim() }
    }

    private func startAnim() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: state == .working ? 0.5 : 0.7, repeats: true) { _ in frame += 1 }
    }
}

/// Scrolling marquee text for the notch
struct NotchMarquee: View {
    let text: String
    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let needsScroll = textWidth > geo.size.width

            Text(text)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
                .fixedSize()
                .background(GeometryReader { textGeo in
                    Color.clear.onAppear {
                        textWidth = textGeo.size.width
                        containerWidth = geo.size.width
                    }
                })
                .offset(x: needsScroll ? offset : 0)
                .onAppear {
                    guard needsScroll else { return }
                    startScrolling()
                }
                .onChange(of: text) {
                    offset = 0
                    textWidth = 0
                }
        }
        .clipped()
    }

    private func startScrolling() {
        // Wait 2s, then scroll, then reset
        let scrollDistance = textWidth - containerWidth + 20
        guard scrollDistance > 0 else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.linear(duration: Double(scrollDistance) / 30.0)) {
                offset = -scrollDistance
            }
            try? await Task.sleep(for: .seconds(2))
            offset = 0
            try? await Task.sleep(for: .seconds(1))
            startScrolling()
        }
    }
}

struct SpinnerView: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .trim(from: 0.05, to: 0.8)
            .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: isAnimating)
            .onAppear { isAnimating = true }
    }
}

// MARK: - CVDisplayLink wrapper for smooth animation

/// Drives a frame-by-frame animation callback on the display refresh rate.
class CVDisplayLinkWrapper {
    private var displayLink: CVDisplayLink?
    private let callback: () -> Bool  // return true to keep running
    private var stopped = false

    init(callback: @escaping () -> Bool) {
        self.callback = callback
    }

    func start() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let displayLink else { return }

        let opaqueWrapper = Unmanaged.passRetained(self)
        CVDisplayLinkSetOutputCallback(displayLink, { (_, _, _, _, _, userInfo) -> CVReturn in
            guard let userInfo else { return kCVReturnError }
            let wrapper = Unmanaged<CVDisplayLinkWrapper>.fromOpaque(userInfo).takeUnretainedValue()
            guard !wrapper.stopped else { return kCVReturnSuccess }
            let keepRunning = wrapper.callback()
            if !keepRunning {
                // Stop immediately on this thread to prevent further callbacks
                wrapper.stopped = true
                if let link = wrapper.displayLink {
                    CVDisplayLinkStop(link)
                }
                // Release the retained reference on main
                DispatchQueue.main.async {
                    wrapper.displayLink = nil
                    Unmanaged<CVDisplayLinkWrapper>.fromOpaque(userInfo).release()
                }
            }
            return kCVReturnSuccess
        }, opaqueWrapper.toOpaque())

        CVDisplayLinkStart(displayLink)
    }

    func stop() {
        stopped = true
        guard let displayLink else { return }
        CVDisplayLinkStop(displayLink)
        self.displayLink = nil
    }
}
