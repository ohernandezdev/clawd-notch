import AppKit

/// Auto-configures hooks for Claude Code and/or GitHub Copilot CLI on first launch
class HookInstaller {
    static let shared = HookInstaller()

    // Claude Code paths
    private var claudeHookDir: String { NSHomeDirectory() + "/.claude/hooks" }
    private var claudeHookPath: String { claudeHookDir + "/notchy-status.sh" }
    private var claudeSettingsPath: String { NSHomeDirectory() + "/.claude/settings.json" }

    // Copilot CLI paths
    private var copilotHookDir: String { NSHomeDirectory() + "/.copilot/hooks" }
    private var copilotHookPath: String { copilotHookDir + "/notchy-status-copilot.sh" }
    private var copilotConfigPath: String { copilotHookDir + "/clawd-notch.json" }

    /// Returns true if any hooks are already configured
    var isConfigured: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: claudeHookPath) || fm.fileExists(atPath: copilotHookPath)
    }

    private var setupWindow: SetupWindowController?

    /// Check and prompt for setup if needed
    func checkAndSetup() {
        moveToApplicationsIfNeeded()
        guard !isConfigured else { return }

        DispatchQueue.main.async {
            // Load hook scripts from bundle
            var hookScripts: [HookProvider: String] = [:]
            var settingsPreviews: [HookProvider: String] = [:]

            if let url = Bundle.main.url(forResource: "notchy-status", withExtension: "sh"),
               let content = try? String(contentsOf: url) {
                hookScripts[.claudeCode] = content
            } else {
                hookScripts[.claudeCode] = "(hook script not found in bundle)"
            }

            if let url = Bundle.main.url(forResource: "notchy-status-copilot", withExtension: "sh"),
               let content = try? String(contentsOf: url) {
                hookScripts[.copilotCLI] = content
            } else {
                hookScripts[.copilotCLI] = "(hook script not found in bundle)"
            }

            settingsPreviews[.claudeCode] = """
            Hooks added to ~/.claude/settings.json:

            "PostToolUse": [{
              "matcher": "",
              "hooks": [{
                "type": "command",
                "command": "bash ~/.claude/hooks/notchy-status.sh",
                "timeout": 3
              }]
            }]

            "Notification": [same structure]
            "Stop": [same structure]

            Your existing settings will be backed up first.
            """

            settingsPreviews[.copilotCLI] = """
            Creates ~/.copilot/hooks/clawd-notch.json:

            {
              "version": 1,
              "hooks": {
                "postToolUse": [{
                  "type": "command",
                  "bash": "bash ~/.copilot/hooks/notchy-status-copilot.sh",
                  "timeoutSec": 3
                }],
                "sessionEnd": [{
                  "type": "command",
                  "bash": "bash ~/.copilot/hooks/notchy-status-copilot.sh",
                  "timeoutSec": 3
                }]
              }
            }
            """

            self.setupWindow = SetupWindowController()
            self.setupWindow?.show(
                hookScripts: hookScripts,
                settingsPreviews: settingsPreviews,
                onInstall: { providers in
                    self.install(providers: providers)
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
            if fm.fileExists(atPath: applicationsPath) {
                try fm.removeItem(atPath: applicationsPath)
            }
            try fm.copyItem(atPath: bundlePath, toPath: applicationsPath)

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

    private func install(providers: Set<HookProvider>) {
        var installed: [String] = []

        if providers.contains(.claudeCode) {
            if installClaudeCode() {
                installed.append("Claude Code")
            }
        }

        if providers.contains(.copilotCLI) {
            if installCopilotCLI() {
                installed.append("GitHub Copilot CLI")
            }
        }

        guard !installed.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Hooks Installed!"
        alert.informativeText = "Claw'd is ready for \(installed.joined(separator: " and ")).\n\nHover over the notch to see your sessions."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.icon = NSImage(named: "AppIcon")
        alert.runModal()
    }

    // MARK: - Claude Code

    private func installClaudeCode() -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: claudeHookDir, withIntermediateDirectories: true)

        guard let bundledHook = Bundle.main.url(forResource: "notchy-status", withExtension: "sh") else {
            showError("Could not find Claude Code hook script in app bundle.")
            return false
        }

        do {
            if fm.fileExists(atPath: claudeHookPath) {
                try fm.removeItem(atPath: claudeHookPath)
            }
            try fm.copyItem(at: bundledHook, to: URL(fileURLWithPath: claudeHookPath))
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claudeHookPath)
        } catch {
            showError("Failed to install Claude Code hook: \(error.localizedDescription)")
            return false
        }

        configureClaudeSettings()
        return true
    }

    private func configureClaudeSettings() {
        let fm = FileManager.default
        let hookCmd = "bash ~/.claude/hooks/notchy-status.sh"
        let claudeDir = NSHomeDirectory() + "/.claude"
        try? fm.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)

        var settings: [String: Any] = [:]

        if fm.fileExists(atPath: claudeSettingsPath) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let backup = claudeSettingsPath + ".backup." + dateFormatter.string(from: Date())
            try? fm.copyItem(atPath: claudeSettingsPath, toPath: backup)

            if let data = fm.contents(atPath: claudeSettingsPath),
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
            return
        }

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

        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: claudeSettingsPath))
        }
    }

    // MARK: - Copilot CLI

    private func installCopilotCLI() -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: copilotHookDir, withIntermediateDirectories: true)

        guard let bundledHook = Bundle.main.url(forResource: "notchy-status-copilot", withExtension: "sh") else {
            showError("Could not find Copilot CLI hook script in app bundle.")
            return false
        }

        do {
            if fm.fileExists(atPath: copilotHookPath) {
                try fm.removeItem(atPath: copilotHookPath)
            }
            try fm.copyItem(at: bundledHook, to: URL(fileURLWithPath: copilotHookPath))
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: copilotHookPath)
        } catch {
            showError("Failed to install Copilot CLI hook: \(error.localizedDescription)")
            return false
        }

        configureCopilotHooks()
        return true
    }

    private func configureCopilotHooks() {
        let hookCmd = "bash ~/.copilot/hooks/notchy-status-copilot.sh"
        let hookEntry: [String: Any] = ["type": "command", "bash": hookCmd, "timeoutSec": 3]

        // Read existing config or create new
        var config: [String: Any] = ["version": 1]
        var hooks: [String: Any] = [:]

        if let data = FileManager.default.contents(atPath: copilotConfigPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            config = json
            hooks = json["hooks"] as? [String: Any] ?? [:]
        }

        // Add to postToolUse and sessionEnd
        for event in ["postToolUse", "sessionEnd"] {
            var eventHooks = hooks[event] as? [[String: Any]] ?? []
            // Check if already configured
            if eventHooks.contains(where: { ($0["bash"] as? String)?.contains("notchy-status-copilot") == true }) {
                continue
            }
            eventHooks.append(hookEntry)
            hooks[event] = eventHooks
        }

        config["hooks"] = hooks

        if let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: copilotConfigPath))
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
