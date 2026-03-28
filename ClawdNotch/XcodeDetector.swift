import AppKit
import Foundation

struct XcodeProject: Equatable {
    let sessionId: String
    let name: String
    let path: String
    let status: String
    let lastMessage: String
    let toolName: String
    let updatedAt: TimeInterval
    let hookEvent: String

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

/// Reads Claude Code session state from $TMPDIR/notchy-sessions/
class XcodeDetector {
    static let shared = XcodeDetector()

    private let sessionsDir = NSTemporaryDirectory() + "notchy-sessions"

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

            projects.append(XcodeProject(
                sessionId: sessionId,
                name: projectName,
                path: cwd,
                status: status,
                lastMessage: lastMessage,
                toolName: toolName,
                updatedAt: updatedAt,
                hookEvent: hookEvent
            ))
        }

        // Sort: waitingForInput first, then taskCompleted, working, idle
        return projects.sorted { a, b in
            let order = ["waitingForInput": 0, "taskCompleted": 1, "working": 2, "interrupted": 3, "idle": 4]
            return (order[a.status] ?? 5) < (order[b.status] ?? 5)
        }
    }
}
