import Foundation

enum TerminalStatus: Equatable {
    /// Default — no special activity detected
    case idle
    /// Claude is working (status line matches token counter pattern)
    case working
    /// Claude is waiting for user input ("Esc to cancel")
    case waitingForInput
    /// Claude was interrupted by the user (Esc pressed)
    case interrupted
    /// Claude finished a task (confirmed via idle timer line after working)
    case taskCompleted
}

struct TerminalSession: Identifiable {
    let id: UUID
    var projectName: String
    var projectPath: String?
    var workingDirectory: String
    var hasStarted: Bool
    var terminalStatus: TerminalStatus
    var generation: Int
    /// Whether the user has ever manually selected this tab
    var hasBeenSelected: Bool
    let createdAt: Date
    /// When the session most recently entered the .working state
    var workingStartedAt: Date?
    /// Last message from Claude (from hook)
    var lastMessage: String = ""
    /// Last tool used
    var lastToolName: String = ""
    /// When the hook last updated this session
    var lastUpdatedAt: Date = Date()
    /// Model being used (e.g. "claude-sonnet-4-5")
    var model: String = ""
    /// Permission mode (plan, auto, default, etc.)
    var permissionMode: String = ""
    /// Number of active subagents
    var activeAgents: Int = 0
    /// Total tools used this session
    var toolCount: Int = 0
    /// Recent tool history
    var toolHistory: [ToolHistoryEntry] = []
    /// Estimated context window usage (0-99%)
    var contextPct: Int = 0

    init(projectName: String, projectPath: String? = nil, workingDirectory: String? = nil, started: Bool = false) {
        self.id = UUID()
        self.projectName = projectName
        self.projectPath = projectPath
        self.workingDirectory = workingDirectory ?? projectPath ?? NSHomeDirectory()
        self.hasStarted = started
        self.terminalStatus = .idle
        self.generation = 0
        self.hasBeenSelected = started // if started immediately (e.g. "+" button), mark as selected
        self.createdAt = Date()
    }

    /// Restore a session from persisted data
    init(persisted: PersistedSession) {
        self.id = persisted.id
        self.projectName = persisted.projectName
        self.projectPath = persisted.projectPath
        self.workingDirectory = persisted.workingDirectory
        self.hasStarted = false
        self.terminalStatus = .idle
        self.generation = 0
        self.hasBeenSelected = false
        self.createdAt = Date()
    }
}

/// Lightweight Codable representation for UserDefaults persistence
struct PersistedSession: Codable {
    let id: UUID
    let projectName: String
    let projectPath: String?
    let workingDirectory: String
}
