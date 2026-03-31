import Foundation
import Network

/// Lightweight HTTP server on localhost:7483 that receives hook POST requests instantly.
/// Replaces the 2-second polling delay with real-time updates.
class TarsHTTPServer {
    static let shared = TarsHTTPServer()
    static let port: UInt16 = 7483

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "tars.httpserver")

    /// Pending permission requests waiting for user approval
    struct PendingPermission {
        let sessionId: String
        let projectName: String
        let toolName: String
        let toolInput: [String: Any]
        let connection: NWConnection
        let receivedAt: Date
    }
    private var pendingPermissions: [String: PendingPermission] = [:]
    private let permissionLock = NSLock()

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!)
            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("[TarsHTTP] Listening on localhost:\(Self.port)")
                case .failed(let error):
                    print("[TarsHTTP] Failed: \(error)")
                default:
                    break
                }
            }
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            listener?.start(queue: queue)
        } catch {
            print("[TarsHTTP] Could not start: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        var buffer = Data()
        receiveLoop(connection: connection, buffer: buffer)
    }

    private func receiveLoop(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            var buf = buffer
            if let data = data { buf.append(data) }

            let raw = String(data: buf, encoding: .utf8) ?? ""

            // Wait until we have the full headers + body separator
            guard raw.contains("\r\n\r\n") else {
                if !isComplete && error == nil {
                    self?.receiveLoop(connection: connection, buffer: buf)
                } else {
                    connection.cancel()
                }
                return
            }

            guard let bodyRange = raw.range(of: "\r\n\r\n") else {
                self?.sendResponse(connection: connection, status: 400, body: "{\"error\":\"bad request\"}")
                return
            }
            let body = String(raw[bodyRange.upperBound...])

            if raw.hasPrefix("POST /hook") {
                self?.handleHook(body: body, connection: connection)
            } else if raw.hasPrefix("POST /permission") {
                self?.handlePermission(body: body, connection: connection)
            } else if raw.hasPrefix("GET /health") {
                self?.sendResponse(connection: connection, status: 200, body: "{\"ok\":true}")
            } else {
                self?.sendResponse(connection: connection, status: 404, body: "{\"error\":\"not found\"}")
            }
        }
    }

    private func handleHook(body: String, connection: NWConnection) {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            sendResponse(connection: connection, status: 400, body: "invalid json")
            return
        }

        let projectName = json["project_name"] as? String ?? ""
        let cwd = json["working_directory"] as? String ?? ""
        let status = json["status"] as? String ?? "idle"
        let lastMessage = json["last_message"] as? String ?? ""
        let toolName = json["tool_name"] as? String ?? ""
        let hookEvent = json["hook_event"] as? String ?? ""
        let model = json["model"] as? String ?? ""
        let permissionMode = json["permission_mode"] as? String ?? ""
        let activeAgents = json["active_agents"] as? Int ?? 0
        let toolCount = json["tool_count"] as? Int ?? 0
        let toolDesc = json["tool_desc"] as? String ?? ""

        // Permission request — check if we need approval
        let needsApproval = hookEvent == "PermissionRequest"
        let permToolName = json["tool_name"] as? String ?? ""
        let permToolInput = json["tool_input"] as? [String: Any]

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

        DispatchQueue.main.async {
            SessionStore.shared.updateFromHTTP(
                projectName: projectName,
                workingDirectory: cwd,
                status: status,
                lastMessage: lastMessage,
                toolName: toolName,
                hookEvent: hookEvent,
                model: model,
                permissionMode: permissionMode,
                activeAgents: activeAgents,
                toolCount: toolCount,
                toolHistory: toolHistory
            )
        }

        // For permission requests, we could hold the connection and wait for approval
        // For now, just acknowledge
        sendResponse(connection: connection, status: 200, body: "{\"ok\":true}")
    }

    // MARK: - Permission Request Handling

    private func handlePermission(body: String, connection: NWConnection) {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            sendResponse(connection: connection, status: 400, body: "{\"error\":\"invalid json\"}")
            return
        }

        let sessionId = json["session_id"] as? String ?? UUID().uuidString
        let projectName = json["project_name"] as? String ?? "unknown"
        let toolName = json["tool_name"] as? String ?? "unknown"
        let toolInput = json["tool_input"] as? [String: Any] ?? [:]

        let pending = PendingPermission(
            sessionId: sessionId,
            projectName: projectName,
            toolName: toolName,
            toolInput: toolInput,
            connection: connection,
            receivedAt: Date()
        )

        permissionLock.lock()
        pendingPermissions[sessionId] = pending
        permissionLock.unlock()

        // Build description for the popup
        var desc = toolName
        if toolName == "Bash", let cmd = toolInput["command"] as? String {
            desc = "Bash: " + String(cmd.prefix(100))
        } else if toolName == "Write", let fp = toolInput["file_path"] as? String {
            desc = "Write: " + (fp as NSString).lastPathComponent
        } else if toolName == "Edit", let fp = toolInput["file_path"] as? String {
            desc = "Edit: " + (fp as NSString).lastPathComponent
        }

        // Notify UI on main thread
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .TarsPermissionRequest,
                object: nil,
                userInfo: [
                    "sessionId": sessionId,
                    "projectName": projectName,
                    "toolName": toolName,
                    "description": desc
                ]
            )
        }

        // Don't respond yet — connection stays open until user approves/denies
        // Auto-timeout after 295s (5 min) — don't respond, Claude Code falls back
        DispatchQueue.global().asyncAfter(deadline: .now() + 295) { [weak self] in
            self?.permissionLock.lock()
            if let pending = self?.pendingPermissions.removeValue(forKey: sessionId) {
                self?.permissionLock.unlock()
                pending.connection.cancel()
            } else {
                self?.permissionLock.unlock()
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .TarsPermissionRequest, object: nil, userInfo: ["dismiss": sessionId])
            }
        }
    }

    /// Called from UI when user clicks Approve or Deny
    func resolvePermission(sessionId: String, approved: Bool, reason: String = "") {
        permissionLock.lock()
        guard let pending = pendingPermissions.removeValue(forKey: sessionId) else {
            permissionLock.unlock()
            return
        }
        permissionLock.unlock()

        let decision = approved ? "approve" : "block"
        let body = "{\"decision\":\"\(decision)\",\"reason\":\"\(reason)\"}"
        sendResponse(connection: pending.connection, status: 200, body: body)
    }

    /// Get all pending permissions (for UI display)
    func getPendingPermissions() -> [PendingPermission] {
        permissionLock.lock()
        defer { permissionLock.unlock() }
        return Array(pendingPermissions.values)
    }

    private func sendResponse(connection: NWConnection, status: Int, body: String) {
        let statusText = status == 200 ? "OK" : status == 400 ? "Bad Request" : "Not Found"
        let response = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        let data = response.data(using: .utf8)!
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
