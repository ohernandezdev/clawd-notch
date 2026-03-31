import AppKit
import Foundation

struct ToolHistoryEntry: Equatable {
    let tool: String
    let desc: String
    let time: TimeInterval
    let ok: Bool
}

struct XcodeProject: Equatable {
    let sessionId: String
    let name: String
    let path: String
    let status: String
    let lastMessage: String
    let toolName: String
    let updatedAt: TimeInterval
    let hookEvent: String
    let permissionMode: String
    let agentType: String
    let model: String
    let activeAgents: Int
    let toolCount: Int
    let toolHistory: [ToolHistoryEntry]
    let contextPct: Int

    var directoryPath: String {
        if path.isEmpty { return NSHomeDirectory() }
        return path
    }

    /// How long since last update
    var age: TimeInterval {
        Date().timeIntervalSince1970 - updatedAt
    }

    /// Human-readable age
    var ageText: String {
        let seconds = Int(age)
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }

    /// Whether this session might be stuck (working for >2min without update)
    var mightBeStuck: Bool {
        status == "working" && age > 120
    }

    static func == (lhs: XcodeProject, rhs: XcodeProject) -> Bool {
        lhs.sessionId == rhs.sessionId
    }
}

/// Reads Claude Code session state from $TMPDIR/tars-sessions/
class XcodeDetector {
    static let shared = XcodeDetector()

    private let sessionsDir = NSTemporaryDirectory() + "tars-sessions"

    func detectFrontmostProject() -> XcodeProject? {
        detectAllProjects().first
    }

    func detectAllProjects() -> [XcodeProject] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: sessionsDir) else { return [] }

        let now = Date().timeIntervalSince1970
        var projects: [XcodeProject] = []

        for file in files where file.hasSuffix(".json") {
            let filePath = (sessionsDir as NSString).appendingPathComponent(file)
            guard let data = fm.contents(atPath: filePath),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let projectName = json["project_name"] as? String,
                  let cwd = json["working_directory"] as? String,
                  let updatedAt = json["updated_at"] as? TimeInterval else {
                continue
            }

            // Remove stale sessions (>10min without hook update)
            if now - updatedAt > 600 {
                try? fm.removeItem(atPath: filePath)
                continue
            }

            var status = json["status"] as? String ?? "idle"
            let lastMessage = json["last_message"] as? String ?? ""
            let toolName = json["tool_name"] as? String ?? ""
            let hookEvent = json["hook_event"] as? String ?? ""
            let sessionId = json["session_id"] as? String ?? file.replacingOccurrences(of: ".json", with: "")

            let permissionMode = json["permission_mode"] as? String ?? ""
            let agentType = json["agent_type"] as? String ?? ""
            let model = json["model"] as? String ?? ""
            let activeAgents = json["active_agents"] as? Int ?? 0
            let toolCount = json["tool_count"] as? Int ?? 0
            let contextPct = json["context_pct"] as? Int ?? 0

            var toolHistory: [ToolHistoryEntry] = []
            if let historyArray = json["tool_history"] as? [[String: Any]] {
                toolHistory = historyArray.compactMap { entry in
                    guard let tool = entry["tool"] as? String else { return nil }
                    return ToolHistoryEntry(
                        tool: tool,
                        desc: entry["desc"] as? String ?? "",
                        time: entry["time"] as? TimeInterval ?? 0,
                        ok: entry["ok"] as? Bool ?? true
                    )
                }
            }

            projects.append(XcodeProject(
                sessionId: sessionId,
                name: projectName,
                path: cwd,
                status: status,
                lastMessage: lastMessage,
                toolName: toolName,
                updatedAt: updatedAt,
                hookEvent: hookEvent,
                permissionMode: permissionMode,
                agentType: agentType,
                model: model,
                activeAgents: activeAgents,
                toolCount: toolCount,
                toolHistory: toolHistory,
                contextPct: contextPct
            ))
        }

        // Deduplicate: keep only the most recently updated session per working directory
        var byPath: [String: XcodeProject] = [:]
        for project in projects {
            if let existing = byPath[project.path] {
                if project.updatedAt > existing.updatedAt {
                    // Delete the older file
                    let oldFile = (sessionsDir as NSString).appendingPathComponent(existing.sessionId + ".json")
                    try? fm.removeItem(atPath: oldFile)
                    byPath[project.path] = project
                } else {
                    let oldFile = (sessionsDir as NSString).appendingPathComponent(project.sessionId + ".json")
                    try? fm.removeItem(atPath: oldFile)
                }
            } else {
                byPath[project.path] = project
            }
        }

        // Sort: waitingForInput first, then taskCompleted, working, idle
        return Array(byPath.values).sorted { a, b in
            let order = ["waitingForInput": 0, "taskCompleted": 1, "working": 2, "interrupted": 3, "idle": 4]
            return (order[a.status] ?? 5) < (order[b.status] ?? 5)
        }
    }
}
