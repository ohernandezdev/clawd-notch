import SwiftUI
import AppKit

// Consistent project colors — same project always gets same color
private let projectColors: [Color] = [
    Color(red: 0.35, green: 0.65, blue: 1.0),   // blue
    Color(red: 0.55, green: 0.85, blue: 0.45),   // green
    Color(red: 1.0,  green: 0.6,  blue: 0.3),    // orange
    Color(red: 0.85, green: 0.45, blue: 0.85),   // purple
    Color(red: 0.4,  green: 0.85, blue: 0.85),   // cyan
    Color(red: 1.0,  green: 0.45, blue: 0.5),    // pink
    Color(red: 0.95, green: 0.8,  blue: 0.3),    // gold
    Color(red: 0.5,  green: 0.7,  blue: 0.5),    // sage
]

func projectColor(for name: String) -> Color {
    let hash = name.utf8.reduce(0) { ($0 &+ UInt32($1)) &* 31 }
    return projectColors[Int(hash) % projectColors.count]
}

struct PanelContentView: View {
    @Bindable var sessionStore: SessionStore
    var onClose: () -> Void
    var onToggleExpand: (() -> Void)?
    @State private var now = Date()

    var body: some View {
        VStack(spacing: 0) {
            if sessionStore.sessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .frame(width: 420)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .onAppear {
            sessionStore.refreshFromFiles()
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                now = Date()
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 14))
                .foregroundColor(.green.opacity(0.6))
            Text("All clear")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var sessionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(sessionStore.sessions.prefix(6).enumerated()), id: \.element.id) { index, session in
                SessionRow(session: session, now: now, privacyMode: sessionStore.privacyMode)
                if index < min(sessionStore.sessions.count, 6) - 1 {
                    Divider()
                        .background(Color.white.opacity(0.06))
                        .padding(.leading, 18)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct SessionRow: View {
    let session: TerminalSession
    let now: Date
    var privacyMode: Bool = true

    private var color: Color {
        projectColor(for: session.projectName)
    }

    private var statusColor: Color {
        switch session.terminalStatus {
        case .working: return Color(red: 1.0, green: 0.85, blue: 0.3)
        case .waitingForInput: return Color(red: 0.55, green: 0.8, blue: 1.0)
        case .taskCompleted: return Color(red: 0.4, green: 0.9, blue: 0.6)
        case .interrupted: return Color(red: 0.9, green: 0.7, blue: 0.4)
        case .idle: return Color(white: 0.35)
        }
    }

    private var timeAgo: String {
        let seconds = Int(now.timeIntervalSince(session.lastUpdatedAt))
        if seconds < 3 { return "now" }
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h"
    }

    private var statusLabel: String {
        switch session.terminalStatus {
        case .working:
            if !session.lastToolName.isEmpty {
                return session.lastToolName
            }
            return "Working"
        case .waitingForInput: return "Your turn"
        case .taskCompleted: return "Done!"
        case .interrupted: return "Sleeping"
        case .idle: return "Idle"
        }
    }

    private var mightBeStuck: Bool {
        session.terminalStatus == .working &&
        now.timeIntervalSince(session.lastUpdatedAt) > 60
    }

    private var toolIcon: String {
        switch session.lastToolName {
        case "Bash": return "terminal"
        case "Edit", "MultiEdit": return "pencil"
        case "Write": return "doc.badge.plus"
        case "Read": return "eye"
        case "Grep": return "magnifyingglass"
        case "Glob": return "folder.badge.magnifyingglass"
        case "Agent": return "person.2"
        case "WebSearch": return "globe"
        case "WebFetch": return "arrow.down.doc"
        case "Task": return "checklist"
        default: return "sparkles"
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        ZStack {
            switch session.terminalStatus {
            case .working:
                Image(systemName: toolIcon)
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 0.85, green: 0.55, blue: 0.2))
            case .waitingForInput:
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 0.4, green: 0.7, blue: 1.0))
            case .taskCompleted:
                Image(systemName: "star.fill")
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.2))
            case .interrupted:
                Image(systemName: "powersleep")
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: 0.5))
            case .idle:
                Circle()
                    .fill(Color(white: 0.25))
                    .frame(width: 8, height: 8)
            }
        }
        .frame(width: 20, height: 18)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Color bar — unique per project
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 3, height: 32)
                .padding(.trailing, 10)

            statusIndicator
                .padding(.trailing, 8)

            VStack(alignment: .leading, spacing: 2) {
                // Row 1: project + time + status
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(session.projectName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text("·")
                        .foregroundColor(.white.opacity(0.15))

                    Text(timeAgo)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))

                    Spacer()

                    if mightBeStuck {
                        Text("Thinking...")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(Color(red: 0.9, green: 0.7, blue: 0.4))
                    } else {
                        Text(statusLabel)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(statusColor)
                    }
                }

                // Row 2: tool activity (privacy mode) or last message (opt-in)
                if privacyMode {
                    if !session.lastToolName.isEmpty {
                        Text(session.lastToolName)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                } else if !session.lastMessage.isEmpty {
                    Text(session.lastMessage)
                        .font(.system(size: 10.5))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            session.terminalStatus == .waitingForInput
                ? Color(red: 0.55, green: 0.8, blue: 1.0).opacity(0.06)
                : Color.clear
        )
    }
}
