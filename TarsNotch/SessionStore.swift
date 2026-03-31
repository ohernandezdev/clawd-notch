import AppKit
import AVFoundation
import SwiftUI

extension Notification.Name {
    static let TarsHidePanel = Notification.Name("TarsHidePanel")
    static let TarsExpandPanel = Notification.Name("TarsExpandPanel")
    static let TarsNotchStatusChanged = Notification.Name("TarsNotchStatusChanged")
    static let TarsPermissionRequest = Notification.Name("TarsPermissionRequest")
}

@Observable
class SessionStore {
    static let shared = SessionStore()

    var sessions: [TerminalSession] = []
    var activeSessionId: UUID?
    var isPinned: Bool = {
        if UserDefaults.standard.object(forKey: "isPinned") == nil { return true }
        return UserDefaults.standard.bool(forKey: "isPinned")
    }() {
        didSet {
            UserDefaults.standard.set(isPinned, forKey: "isPinned")
            updatePollingTimer()
        }
    }

    /// Push notifications toggle
    var notificationsEnabled: Bool = {
        if UserDefaults.standard.object(forKey: "notificationsEnabled") == nil { return true }
        return UserDefaults.standard.bool(forKey: "notificationsEnabled")
    }() {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled")
        }
    }

    /// Privacy mode: hides lastMessage content in the panel
    var privacyMode: Bool = {
        // Default to true (conservative) — user opts in to showing message previews
        if UserDefaults.standard.object(forKey: "privacyMode") == nil { return true }
        return UserDefaults.standard.bool(forKey: "privacyMode")
    }() {
        didSet {
            UserDefaults.standard.set(privacyMode, forKey: "privacyMode")
        }
    }
    var isTerminalExpanded = true
    var isWindowFocused = true
    var isShowingDialog = false
    var hasCompletedInitialDetection = false

    /// The most recent checkpoint for the active session, used to show the undo button
    var lastCheckpoint: Checkpoint?
    /// Project name associated with lastCheckpoint
    var lastCheckpointProjectName: String?
    /// Project directory associated with lastCheckpoint
    var lastCheckpointProjectDir: String?

    /// Non-nil while a checkpoint operation is in progress (e.g. "Taking checkpoint…", "Restoring checkpoint…")
    var checkpointStatus: String?

    /// Projects the user explicitly closed.
    /// Value is `false` while the project is still open in Xcode (suppress recreation),
    /// flips to `true` once we observe the project absent — next detection will recreate the tab.
    private var dismissedProjects: [String: Bool] = [:]

    /// Activity token to prevent macOS idle sleep while Claude is working
    private var sleepActivity: NSObjectProtocol?

    /// Sound playback
    private var audioPlayer: AVAudioPlayer?
    private var lastSoundPlayedAt: Date = .distantPast

    /// Timer that periodically checks for new Xcode projects while pinned
    private var pollingTimer: Timer?
    private static let pollingInterval: TimeInterval = 5

    var activeSession: TerminalSession? {
        sessions.first { $0.id == activeSessionId }
    }

    /// Currently open Xcode project names (refreshed on each scan)
    var activeXcodeProjects: Set<String> = []

    /// The status color for the notch (matches tab bar colors)
    var notchStatusColor: NSColor {
        guard let session = activeSession else { return .systemGreen }
        switch session.terminalStatus {
        case .waitingForInput: return .systemRed
        case .working: return .systemYellow
        case .idle, .interrupted, .taskCompleted: return .systemGreen
        }
    }

    private static let sessionsKey = "persistedSessions"
    private static let activeSessionKey = "activeSessionId"

    init() {
        restoreSessions()
        updatePollingTimer()
        TarsHTTPServer.shared.start()
    }

    private func sendNotification(title: String, body: String, color: NSColor = .systemOrange) {
        guard notificationsEnabled else { return }
        NotificationBanner.shared.show(title: title, body: body, color: color)
    }

    // MARK: - Session Persistence

    private func restoreSessions() {
        guard let data = UserDefaults.standard.data(forKey: Self.sessionsKey),
              let persisted = try? JSONDecoder().decode([PersistedSession].self, from: data),
              !persisted.isEmpty else { return }
        sessions = persisted.map { TerminalSession(persisted: $0) }
        if let savedId = UserDefaults.standard.string(forKey: Self.activeSessionKey),
           let uuid = UUID(uuidString: savedId),
           sessions.contains(where: { $0.id == uuid }) {
            activeSessionId = uuid
        } else {
            activeSessionId = sessions.first?.id
        }
        // Mark all restored sessions as started so terminals launch immediately
        for i in sessions.indices {
            sessions[i].hasStarted = true
            sessions[i].hasBeenSelected = true
        }
    }

    private func persistSessions() {
        let persisted = sessions.map { PersistedSession(id: $0.id, projectName: $0.projectName, projectPath: $0.projectPath, workingDirectory: $0.workingDirectory) }
        if let data = try? JSONEncoder().encode(persisted) {
            UserDefaults.standard.set(data, forKey: Self.sessionsKey)
        }
        if let activeId = activeSessionId {
            UserDefaults.standard.set(activeId.uuidString, forKey: Self.activeSessionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.activeSessionKey)
        }
    }

    func updateWorkingDirectory(_ id: UUID, directory: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        guard sessions[index].workingDirectory != directory else { return }
        sessions[index].workingDirectory = directory
        persistSessions()
    }

    /// Always poll for session status changes (reads files, instant)
    private func updatePollingTimer() {
        pollingTimer?.invalidate()
        pollingTimer = nil

        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshFromFiles()
        }
    }

    /// Check for notification request files and show banners
    private func checkNotificationRequests() {
        let sessionsDir = NSTemporaryDirectory() + "tars-sessions"
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: sessionsDir) else { return }

        for file in files where file.hasPrefix("_notify_") && file.hasSuffix(".json") {
            let path = (sessionsDir as NSString).appendingPathComponent(file)
            guard let data = fm.contents(atPath: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let project = json["project"] as? String,
                  let message = json["message"] as? String,
                  let type = json["type"] as? String else {
                try? fm.removeItem(atPath: path)
                continue
            }

            let color: NSColor = type == "taskCompleted" ? .systemGreen : .systemBlue
            sendNotification(title: project, body: message, color: color)

            // Delete after showing
            try? fm.removeItem(atPath: path)
        }
    }

    /// Read session states from /tmp/tars-sessions/ and update
    func refreshFromFiles() {
        checkNotificationRequests()
        let projects = XcodeDetector.shared.detectAllProjects()
        let detectedNames = Set(projects.map(\.name))
        activeXcodeProjects = detectedNames

        if !hasCompletedInitialDetection {
            hasCompletedInitialDetection = true
        }

        for project in projects {
            if let index = sessions.firstIndex(where: { $0.workingDirectory == project.path }) {
                // Update existing session
                var newStatus = Self.mapStatus(project.status)
                // If message says waiting but status doesn't, fix it
                if newStatus == .working && project.lastMessage.lowercased().contains("waiting for") {
                    newStatus = .waitingForInput
                }
                sessions[index].lastMessage = project.lastMessage
                sessions[index].lastToolName = project.toolName
                sessions[index].lastUpdatedAt = Date(timeIntervalSince1970: project.updatedAt)
                sessions[index].model = project.model
                sessions[index].permissionMode = project.permissionMode
                sessions[index].activeAgents = project.activeAgents
                sessions[index].toolCount = project.toolCount
                sessions[index].toolHistory = project.toolHistory
                sessions[index].contextPct = project.contextPct
                if sessions[index].terminalStatus != newStatus {
                    updateTerminalStatus(sessions[index].id, status: newStatus)
                }
                // Always notify so the notch reflects the most recent session
                NotificationCenter.default.post(name: .TarsNotchStatusChanged, object: nil)
            } else if dismissedProjects[project.name] == nil {
                var session = TerminalSession(
                    projectName: project.name,
                    projectPath: project.path,
                    workingDirectory: project.directoryPath,
                    started: true
                )
                session.lastMessage = project.lastMessage
                session.lastToolName = project.toolName
                sessions.append(session)
                if activeSessionId == nil {
                    activeSessionId = session.id
                }
                let newStatus = Self.mapStatus(project.status)
                if newStatus != .idle {
                    updateTerminalStatus(session.id, status: newStatus)
                }
            }
        }

        // Remove gone sessions
        for i in sessions.indices.reversed() {
            guard sessions[i].projectPath != nil else { continue }
            if !detectedNames.contains(sessions[i].projectName) {
                sessions.remove(at: i)
            }
        }
    }

    // MARK: - HTTP Server Updates (instant, no polling delay)

    func updateFromHTTP(
        projectName: String, workingDirectory: String, status: String,
        lastMessage: String, toolName: String, hookEvent: String,
        model: String, permissionMode: String, activeAgents: Int,
        toolCount: Int, toolHistory: [ToolHistoryEntry]
    ) {
        let newStatus = Self.mapStatus(status)

        if let index = sessions.firstIndex(where: { $0.workingDirectory == workingDirectory }) {
            sessions[index].lastMessage = lastMessage
            sessions[index].lastToolName = toolName
            sessions[index].lastUpdatedAt = Date()
            sessions[index].model = model
            sessions[index].permissionMode = permissionMode
            sessions[index].activeAgents = activeAgents
            sessions[index].toolCount = toolCount
            sessions[index].toolHistory = toolHistory
            if sessions[index].terminalStatus != newStatus {
                updateTerminalStatus(sessions[index].id, status: newStatus)
            }
            NotificationCenter.default.post(name: .TarsNotchStatusChanged, object: nil)
        } else if !projectName.isEmpty {
            var session = TerminalSession(
                projectName: projectName,
                projectPath: workingDirectory,
                workingDirectory: workingDirectory,
                started: true
            )
            session.lastMessage = lastMessage
            session.lastToolName = toolName
            session.model = model
            session.permissionMode = permissionMode
            session.activeAgents = activeAgents
            session.toolCount = toolCount
            session.toolHistory = toolHistory
            sessions.append(session)
            if activeSessionId == nil {
                activeSessionId = session.id
            }
            if newStatus != .idle {
                updateTerminalStatus(session.id, status: newStatus)
            }
            NotificationCenter.default.post(name: .TarsNotchStatusChanged, object: nil)
        }
    }

    private static func mapStatus(_ status: String) -> TerminalStatus {
        switch status {
        case "working": return .working
        case "waitingForInput": return .waitingForInput
        case "taskCompleted", "done": return .taskCompleted
        case "interrupted": return .interrupted
        default: return .idle
        }
    }

    /// Called when the panel gains focus
    func panelDidBecomeKey() {
        refreshFromFiles()
    }

    /// Compatibility — just refreshes from files
    func detectAllXcodeProjectsAsync() {
        refreshFromFiles()
    }

    /// Compatibility — just refreshes from files
    func detectAndSwitchAsync() {
        refreshFromFiles()
    }

    /// Auto-switch to existing session for a project.
    func autoSwitchToProject(_ project: XcodeProject) -> Bool {
        guard dismissedProjects[project.name] == nil else { return false }

        if let index = sessions.firstIndex(where: { $0.projectName == project.name }) {
            // Only auto-switch to tabs the user hasn't selected yet
            guard !sessions[index].hasBeenSelected else { return false }
            sessions[index].hasBeenSelected = true
            activeSessionId = sessions[index].id
            startSessionIfNeeded(sessions[index].id)
            return true
        }
        return false
    }

    /// Select a tab — auto-starts the terminal only if the project's Xcode instance is active
    func selectSession(_ id: UUID) {
        activeSessionId = id
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].hasBeenSelected = true
            let session = sessions[index]
            // Auto-start if it's a plain terminal (no project) or the project is open in Xcode
            if session.projectPath == nil || activeXcodeProjects.contains(session.projectName) {
                startSessionIfNeeded(id)
            }
            // Expand terminal if collapsed when user taps a tab
            if !isTerminalExpanded {
                isTerminalExpanded = true
                NotificationCenter.default.post(name: .TarsExpandPanel, object: nil)
            }
        }
        persistSessions()
    }

    /// Mark session as started (terminal will be created when view renders)
    func startSessionIfNeeded(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        if !sessions[index].hasStarted {
            sessions[index].hasStarted = true
        }
    }

    /// "+" button: creates a plain terminal session with no project association
    func createQuickSession() {
        let session = TerminalSession(
            projectName: "Terminal",
            started: true
        )
        sessions.append(session)
        activeSessionId = session.id
        persistSessions()
    }

    func renameSession(_ id: UUID, to newName: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].projectName = newName
        persistSessions()
    }

    func updateTerminalStatus(_ id: UUID, status: TerminalStatus) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].lastUpdatedAt = Date()
        if sessions[index].terminalStatus != status {
            let previous = sessions[index].terminalStatus
            sessions[index].terminalStatus = status
            updateSleepPrevention()

            if status == .working && previous != .working {
                sessions[index].workingStartedAt = Date()
                // Clear sound tracking so next waitingForInput/taskCompleted can sound
                soundPlayedForStatus.removeValue(forKey: id)
            }
            if status == .waitingForInput && previous != .waitingForInput {
                NotificationCenter.default.post(name: .TarsNotchStatusChanged, object: nil)
                if isPinned && !isTerminalExpanded && id == activeSessionId {
                    isTerminalExpanded = true
                    NotificationCenter.default.post(name: .TarsExpandPanel, object: nil)
                }
            }
            else if status == .taskCompleted && previous != .taskCompleted {
                // Notification handled via _notify_ files from the hook
            }
            else if status == .idle && previous == .working {
                // Delay 3s before treating as "task completed" — Claude sometimes
                // goes working → idle → working again briefly.
                let workingStartedAt = sessions[index].workingStartedAt
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    guard let idx = self.sessions.firstIndex(where: { $0.id == id }),
                          self.sessions[idx].terminalStatus == .idle else { return }
                    // Only trigger taskCompleted for tasks that ran >10s
                    if let started = workingStartedAt, Date().timeIntervalSince(started) < 10 {
                        return
                    }
                    SessionStore.shared.updateTerminalStatus(id, status: .taskCompleted)
                    // Auto-clear taskCompleted after 3 seconds
                    try? await Task.sleep(for: .seconds(3))
                    guard let idx2 = self.sessions.firstIndex(where: { $0.id == id }),
                          self.sessions[idx2].terminalStatus == .taskCompleted else { return }
                    self.sessions[idx2].terminalStatus = .idle
                    NotificationCenter.default.post(name: .TarsNotchStatusChanged, object: nil)
                }
            }
        }
    }

    /// Tracks which sessions already played a sound for their current status
    private var soundPlayedForStatus: [UUID: TerminalStatus] = [:]

    /// Stop sounds — called when user hovers the notch (acknowledged)
    func silenceSounds() {
        audioPlayer?.stop()
        // Mark all current statuses as acknowledged
        for session in sessions {
            soundPlayedForStatus[session.id] = session.terminalStatus
        }
    }

    private func playSound(named name: String, for sessionId: UUID? = nil, status: TerminalStatus? = nil) {
        // If this session already played sound for this status, skip
        if let id = sessionId, let st = status, soundPlayedForStatus[id] == st {
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastSoundPlayedAt) >= 30.0 else { return }
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else { return }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
            lastSoundPlayedAt = now
            if let id = sessionId, let st = status {
                soundPlayedForStatus[id] = st
            }
        } catch {}
    }

    private func updateSleepPrevention() {
        let anyWorking = sessions.contains { $0.terminalStatus == .working }
        if anyWorking && sleepActivity == nil {
            sleepActivity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .suddenTerminationDisabled],
                reason: "Claude is working"
            )
        } else if !anyWorking, let activity = sleepActivity {
            ProcessInfo.processInfo.endActivity(activity)
            sleepActivity = nil
        }
    }

    /// Close tab: removes the session entirely and dismisses the project from auto-detection
    /// Refresh the lastCheckpoint for the active session
    func refreshLastCheckpoint() {
        guard let session = activeSession,
              let dir = session.projectPath else {
            lastCheckpoint = nil
            lastCheckpointProjectName = nil
            lastCheckpointProjectDir = nil
            return
        }
        let projectDir = (dir as NSString).deletingLastPathComponent
        let checkpoints = CheckpointManager.shared.checkpoints(for: session.projectName, in: projectDir)
        lastCheckpoint = checkpoints.first
        lastCheckpointProjectName = session.projectName
        lastCheckpointProjectDir = projectDir
    }

    /// Restore the most recent checkpoint for the active session
    func restoreLastCheckpoint() {
        guard let checkpoint = lastCheckpoint,
              let projectDir = lastCheckpointProjectDir else { return }
        checkpointStatus = "Restoring checkpoint…"
        DispatchQueue.global(qos: .userInitiated).async {
            try? CheckpointManager.shared.restoreCheckpoint(checkpoint, to: projectDir)
            DispatchQueue.main.async {
                self.checkpointStatus = nil
                self.lastCheckpoint = nil
            }
        }
    }

    /// Create a checkpoint with progress status
    func createCheckpointForActiveSession() {
        guard let session = activeSession,
              let dir = session.projectPath else { return }
        let projectDir = (dir as NSString).deletingLastPathComponent
        let projectName = session.projectName
        checkpointStatus = "Saving checkpoint…"
        DispatchQueue.global(qos: .userInitiated).async {
            try? CheckpointManager.shared.createCheckpoint(projectName: projectName, projectDirectory: projectDir)
            DispatchQueue.main.async {
                self.refreshLastCheckpoint()
                self.checkpointStatus = nil
            }
        }
    }

    /// Create a checkpoint for a specific session by ID
    func createCheckpoint(for sessionId: UUID) {
        guard let session = sessions.first(where: { $0.id == sessionId }),
              let dir = session.projectPath else { return }
        let projectDir = (dir as NSString).deletingLastPathComponent
        let projectName = session.projectName
        checkpointStatus = "Saving checkpoint…"
        DispatchQueue.global(qos: .userInitiated).async {
            try? CheckpointManager.shared.createCheckpoint(projectName: projectName, projectDirectory: projectDir)
            DispatchQueue.main.async {
                self.refreshLastCheckpoint()
                self.checkpointStatus = nil
            }
        }
    }

    /// Sessions that have a project path (eligible for checkpoints)
    var checkpointEligibleSessions: [TerminalSession] {
        sessions.filter { $0.projectPath != nil }
    }

    /// Restore a specific checkpoint for a session
    func restoreCheckpoint(_ checkpoint: Checkpoint, for sessionId: UUID) {
        guard let session = sessions.first(where: { $0.id == sessionId }),
              let dir = session.projectPath else { return }
        let projectDir = (dir as NSString).deletingLastPathComponent
        checkpointStatus = "Restoring checkpoint…"
        DispatchQueue.global(qos: .userInitiated).async {
            try? CheckpointManager.shared.restoreCheckpoint(checkpoint, to: projectDir)
            DispatchQueue.main.async {
                self.checkpointStatus = nil
                self.refreshLastCheckpoint()
            }
        }
    }

    func restartSession(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        TerminalManager.shared.destroyTerminal(for: id)
        sessions[index].terminalStatus = .idle
        sessions[index].generation += 1
    }

    func closeSession(_ id: UUID) {
        if let session = sessions.first(where: { $0.id == id }) {
            dismissedProjects[session.projectName] = false
        }
        TerminalManager.shared.destroyTerminal(for: id)
        sessions.removeAll { $0.id == id }
        if activeSessionId == id {
            activeSessionId = sessions.first?.id
        }
        persistSessions()
    }
}
