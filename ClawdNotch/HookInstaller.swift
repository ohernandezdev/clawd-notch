import AppKit

/// Auto-configures Claude Code hooks on first launch
class HookInstaller {
    static let shared = HookInstaller()

    private let hookFileName = "notchy-status.sh"
    private var hookDir: String { NSHomeDirectory() + "/.claude/hooks" }
    private var hookPath: String { hookDir + "/" + hookFileName }
    private var settingsPath: String { NSHomeDirectory() + "/.claude/settings.json" }

    /// Returns true if hooks are already configured
    var isConfigured: Bool {
        FileManager.default.fileExists(atPath: hookPath)
    }

    private var setupWindow: SetupWindowController?

    /// Check and prompt for setup if needed
    func checkAndSetup() {
        moveToApplicationsIfNeeded()
        guard !isConfigured else { return }

        DispatchQueue.main.async {
            let hookContent: String
            if let url = Bundle.main.url(forResource: "notchy-status", withExtension: "sh"),
               let content = try? String(contentsOf: url) {
                hookContent = content
            } else {
                hookContent = "(hook script not found in bundle)"
            }

            let settingsPreview = """
            The following hooks will be added to ~/.claude/settings.json:

            "PostToolUse": [{
              "matcher": "",
              "hooks": [{
                "type": "command",
                "command": "bash ~/.claude/hooks/notchy-status.sh",
                "timeout": 3
              }]
            }]

            "Notification": [same structure as above]
            "Stop": [same structure as above]

            Your existing settings will be backed up to:
            ~/.claude/settings.json.backup.<timestamp>
            """

            self.setupWindow = SetupWindowController()
            self.setupWindow?.show(
                hookScript: hookContent,
                settingsPreview: settingsPreview,
                onInstall: {
                    self.install()
                    self.setupWindow = nil
                },
                onCancel: {
                    self.setupWindow = nil
                    NSApplication.shared.terminate(nil)
                }
            )
        }
    }

    /// Move app to /Applications if running from elsewhere (DMG, Downloads, etc.)
    private func moveToApplicationsIfNeeded() {
        let bundlePath = Bundle.main.bundlePath
        let appName = (bundlePath as NSString).lastPathComponent
        let applicationsPath = "/Applications/" + appName

        // Already in /Applications
        guard !bundlePath.hasPrefix("/Applications") else { return }

        let alert = NSAlert()
        alert.messageText = "Move to Applications?"
        alert.informativeText = "Claw'd Notch needs to be in your Applications folder to work properly.\n\nMove it now?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Quit")
        alert.icon = NSImage(named: "AppIcon")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            NSApplication.shared.terminate(nil)
            return
        }

        let fm = FileManager.default
        do {
            // Remove old version if exists
            if fm.fileExists(atPath: applicationsPath) {
                try fm.removeItem(atPath: applicationsPath)
            }
            // Copy to /Applications
            try fm.copyItem(atPath: bundlePath, toPath: applicationsPath)

            // Relaunch from /Applications
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = [applicationsPath]
            try task.run()

            NSApplication.shared.terminate(nil)
        } catch {
            let err = NSAlert()
            err.messageText = "Could not move to Applications"
            err.informativeText = error.localizedDescription
            err.alertStyle = .warning
            err.addButton(withTitle: "Quit")
            err.runModal()
            NSApplication.shared.terminate(nil)
        }
    }

    private func install() {
        let fm = FileManager.default

        // Create hooks directory
        try? fm.createDirectory(atPath: hookDir, withIntermediateDirectories: true)

        // Copy hook script from app bundle
        guard let bundledHook = Bundle.main.url(forResource: "notchy-status", withExtension: "sh") else {
            showError("Could not find hook script in app bundle.")
            return
        }

        do {
            // Remove old hook if exists
            if fm.fileExists(atPath: hookPath) {
                try fm.removeItem(atPath: hookPath)
            }
            try fm.copyItem(at: bundledHook, to: URL(fileURLWithPath: hookPath))

            // Make executable
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookPath)
        } catch {
            showError("Failed to install hook: \(error.localizedDescription)")
            return
        }

        // Configure settings.json
        configureSettings()

        // Show success
        let alert = NSAlert()
        alert.messageText = "Hooks Installed!"
        alert.informativeText = "Claw'd is ready. Hover over the notch to see your Claude Code sessions.\n\nStart a Claude Code session anywhere and it will appear automatically."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.icon = NSImage(named: "AppIcon")
        alert.runModal()
    }

    private func configureSettings() {
        let fm = FileManager.default
        let hookCmd = "bash ~/.claude/hooks/notchy-status.sh"

        // Ensure .claude directory exists
        let claudeDir = NSHomeDirectory() + "/.claude"
        try? fm.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)

        var settings: [String: Any] = [:]

        if fm.fileExists(atPath: settingsPath) {
            // Backup existing settings
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let backup = settingsPath + ".backup." + dateFormatter.string(from: Date())
            try? fm.copyItem(atPath: settingsPath, toPath: backup)

            // Read existing settings
            if let data = fm.contents(atPath: settingsPath),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                settings = json
            }
        }

        // Check if already configured
        if let hooks = settings["hooks"] as? [String: Any],
           let postToolUse = hooks["PostToolUse"] as? [[String: Any]],
           postToolUse.contains(where: { entry in
               (entry["hooks"] as? [[String: Any]])?.contains(where: { ($0["command"] as? String)?.contains("notchy-status.sh") == true }) == true
           }) {
            return // Already configured
        }

        // Add hooks
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        let hookEntry: [String: Any] = [
            "matcher": "",
            "hooks": [["type": "command", "command": hookCmd, "timeout": 3]]
        ]

        for event in ["PostToolUse", "Notification", "Stop"] {
            var eventHooks = hooks[event] as? [[String: Any]] ?? []
            eventHooks.append(hookEntry)
            hooks[event] = eventHooks
        }
        settings["hooks"] = hooks

        // Write settings
        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: settingsPath))
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Setup Failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
