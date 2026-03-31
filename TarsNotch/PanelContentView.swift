import SwiftUI
import AppKit

func projectColor(for name: String) -> Color {
    let colors: [Color] = [
        .blue, .green, .orange, .purple, .cyan, .pink, .yellow, .mint
    ]
    let hash = name.utf8.reduce(0) { ($0 &+ UInt32($1)) &* 31 }
    return colors[Int(hash) % colors.count]
}

struct PanelContentView: View {
    @Bindable var sessionStore: SessionStore
    var onClose: () -> Void
    var onToggleExpand: (() -> Void)?
    @State private var now = Date()
    @State private var pendingPermission: PermissionInfo?

    struct PermissionInfo: Identifiable {
        let id = UUID()
        let sessionId: String
        let projectName: String
        let toolName: String
        let description: String
        let receivedAt: Date = Date()
        static let timeout: TimeInterval = 300 // 5 minutes
    }

    var body: some View {
        VStack(spacing: 0) {
            if let perm = pendingPermission {
                permissionBanner(perm)
            }

            if sessionStore.sessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .frame(width: 380)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 0)
                .fill(Color.black.opacity(0.92))
        )
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 0))
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 0)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .onAppear {
            sessionStore.refreshFromFiles()
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                now = Date()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .TarsPermissionRequest)) { notif in
            guard let info = notif.userInfo,
                  let sessionId = info["sessionId"] as? String,
                  let projectName = info["projectName"] as? String,
                  let toolName = info["toolName"] as? String,
                  let desc = info["description"] as? String else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                pendingPermission = PermissionInfo(
                    sessionId: sessionId, projectName: projectName,
                    toolName: toolName, description: desc
                )
            }
        }
    }

    private func permissionBanner(_ perm: PermissionInfo) -> some View {
        let elapsed = now.timeIntervalSince(perm.receivedAt)
        let remaining = max(0, PermissionInfo.timeout - elapsed)
        let progress = remaining / PermissionInfo.timeout

        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                Text(perm.projectName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text("\(Int(remaining))s")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            }

            Text(perm.description)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 3)
                        .cornerRadius(1.5)
                    Rectangle()
                        .fill(progress > 0.2 ? Color.orange.opacity(0.5) : Color.red.opacity(0.6))
                        .frame(width: geo.size.width * progress, height: 3)
                        .cornerRadius(1.5)
                        .animation(.linear(duration: 1), value: progress)
                }
            }
            .frame(height: 3)

            HStack(spacing: 8) {
                Button(action: {
                    TarsHTTPServer.shared.resolvePermission(sessionId: perm.sessionId, approved: false, reason: "denied")
                    withAnimation { pendingPermission = nil }
                }) {
                    Text("Deny")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.red.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                Button(action: {
                    TarsHTTPServer.shared.resolvePermission(sessionId: perm.sessionId, approved: true, reason: "approved")
                    withAnimation { pendingPermission = nil }
                }) {
                    Text("Allow")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.green.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.03))
        .transition(.move(edge: .top).combined(with: .opacity))
        .onChange(of: now) {
            if now.timeIntervalSince(perm.receivedAt) >= PermissionInfo.timeout {
                withAnimation { pendingPermission = nil }
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 6, height: 6)
            Text("No active sessions")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var sessionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(sessionStore.sessions.prefix(6).enumerated()), id: \.element.id) { index, session in
                SessionRow(session: session, now: now, privacyMode: sessionStore.privacyMode)
                if index < min(sessionStore.sessions.count, 6) - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.04))
                        .frame(height: 0.5)
                        .padding(.leading, 12)
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

    private var isWaiting: Bool { session.terminalStatus == .waitingForInput }
    private var isWorking: Bool { session.terminalStatus == .working }
    private var isDone: Bool { session.terminalStatus == .taskCompleted }

    private var timeAgo: String {
        let seconds = Int(now.timeIntervalSince(session.lastUpdatedAt))
        if seconds < 3 { return "now" }
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h"
    }

    private var statusText: String {
        switch session.terminalStatus {
        case .working:
            if !session.lastToolName.isEmpty { return session.lastToolName }
            return "Working"
        case .waitingForInput: return "Your turn"
        case .taskCompleted: return "Done"
        case .interrupted: return "Paused"
        case .idle: return "Idle"
        }
    }

    // Dracula palette
    private static let draculaPurple = Color(red: 0.74, green: 0.58, blue: 0.98)   // #bd93f9
    private static let draculaGreen  = Color(red: 0.31, green: 0.98, blue: 0.48)   // #50fa7b
    private static let draculaCyan   = Color(red: 0.55, green: 0.93, blue: 0.93)   // #8be9fd
    private static let draculaOrange = Color(red: 1.0,  green: 0.72, blue: 0.42)   // #ffb86c
    private static let draculaYellow = Color(red: 0.95, green: 0.98, blue: 0.55)   // #f1fa8c
    private static let draculaPink   = Color(red: 1.0,  green: 0.47, blue: 0.65)   // #ff79c6
    private static let draculaRed    = Color(red: 1.0,  green: 0.33, blue: 0.33)   // #ff5555
    private static let draculaFg     = Color(red: 0.97, green: 0.97, blue: 0.95)   // #f8f8f2
    private static let draculaComment = Color(red: 0.38, green: 0.45, blue: 0.55)  // #6272a4

    private var statusColor: Color {
        switch session.terminalStatus {
        case .working: return Self.draculaOrange
        case .waitingForInput: return Self.draculaCyan
        case .taskCompleted: return Self.draculaGreen
        case .interrupted: return Self.draculaYellow
        case .idle: return Self.draculaComment
        }
    }

    private var mightBeStuck: Bool {
        session.terminalStatus == .working &&
        now.timeIntervalSince(session.lastUpdatedAt) > 60 &&
        !session.lastMessage.lowercased().contains("waiting for")
    }

    var body: some View {
        HStack(spacing: 10) {
            // Left: status dot
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            // Center: info
            VStack(alignment: .leading, spacing: 2) {
                // Row 1: name · time
                HStack(spacing: 0) {
                    Text(session.projectName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Self.draculaFg)
                        .lineLimit(1)

                    Text(" · \(timeAgo)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Self.draculaComment.opacity(0.8))

                    Spacer()

                    // Status label
                    Text(mightBeStuck ? "Thinking..." : statusText)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(mightBeStuck ? Self.draculaYellow : statusColor)
                }

                // Row 2: message or tool
                if privacyMode {
                    if !session.lastToolName.isEmpty {
                        Text(session.lastToolName)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Self.draculaFg.opacity(0.4))
                            .lineLimit(1)
                    }
                } else if !session.lastMessage.isEmpty {
                    Text(session.lastMessage)
                        .font(.system(size: 10))
                        .foregroundColor(Self.draculaFg.opacity(0.45))
                        .lineLimit(2)
                        .truncationMode(.tail)
                }

                // Row 3: model + agents + mode
                let hasMetadata = !session.model.isEmpty || session.activeAgents > 0 ||
                    (!session.permissionMode.isEmpty && session.permissionMode != "default")
                if hasMetadata {
                    HStack(spacing: 6) {
                        if !session.model.isEmpty {
                            Text(session.model
                                .replacingOccurrences(of: "claude-", with: "")
                                .replacingOccurrences(of: "-20251022", with: "")
                                .replacingOccurrences(of: "-20250514", with: "")
                                .replacingOccurrences(of: "-20250101", with: ""))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(Self.draculaPurple.opacity(0.5))
                        }
                        if session.activeAgents > 0 {
                            Text("\(session.activeAgents) agent\(session.activeAgents > 1 ? "s" : "")")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(Self.draculaCyan.opacity(0.5))
                        }
                        if !session.permissionMode.isEmpty && session.permissionMode != "default" {
                            Text("▸▸ \(session.permissionMode)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.55))
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
