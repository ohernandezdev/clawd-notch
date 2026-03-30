import SwiftUI
import ServiceManagement

enum HookProvider: String, CaseIterable, Identifiable {
    case claudeCode = "Claude Code"
    case copilotCLI = "GitHub Copilot CLI"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .claudeCode: return "terminal"
        case .copilotCLI: return "chevron.left.forwardslash.chevron.right"
        }
    }

    var configPath: String {
        switch self {
        case .claudeCode: return "~/.claude/settings.json"
        case .copilotCLI: return "~/.copilot/hooks/"
        }
    }

    var hookPath: String {
        switch self {
        case .claudeCode: return "~/.claude/hooks/notchy-status.sh"
        case .copilotCLI: return "~/.copilot/hooks/notchy-status-copilot.sh"
        }
    }
}

struct SetupView: View {
    let hookScripts: [HookProvider: String]
    let settingsPreviews: [HookProvider: String]
    let onInstall: (Set<HookProvider>) -> Void
    let onCancel: () -> Void
    @State private var selectedProviders: Set<HookProvider> = Set(HookProvider.allCases)
    @State private var selectedTab = 0
    @State private var previewProvider: HookProvider = .claudeCode

    // Claw'd sprite
    private let sprite: [[Int]] = [
        [0,0,1,0,0,0,0,0,1,0,0],
        [0,0,1,1,1,1,1,1,1,0,0],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,1,2,3,2,2,2,3,2,1,0],
        [0,1,1,1,1,1,1,1,1,1,0],
        [0,0,1,1,1,1,1,1,1,0,0],
        [0,0,1,0,1,0,1,0,1,0,0],
    ]

    private var activeProviders: [HookProvider] {
        HookProvider.allCases.filter { selectedProviders.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Canvas { context, size in
                    let px: CGFloat = 4.0
                    let cols = sprite[0].count
                    let rows = sprite.count
                    let ox = (size.width - CGFloat(cols) * px) / 2
                    let oy = (size.height - CGFloat(rows) * px) / 2
                    let colors: [Int: Color] = [
                        1: Color(red: 0.76, green: 0.45, blue: 0.31),
                        2: Color(red: 0.55, green: 0.29, blue: 0.19),
                        3: .white,
                    ]
                    for (y, row) in sprite.enumerated() {
                        for (x, val) in row.enumerated() {
                            guard val != 0, let c = colors[val] else { continue }
                            let rect = CGRect(x: ox + CGFloat(x) * px, y: oy + CGFloat(y) * px, width: px, height: px)
                            context.fill(Path(rect), with: .color(c))
                        }
                    }
                }
                .frame(width: 50, height: 36)

                Text("Claw'd Notch")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)

                Text("Your MacBook notch dashboard for AI coding agents.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            // Provider selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Install hooks for:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))

                ForEach(HookProvider.allCases) { provider in
                    ProviderToggleRow(
                        provider: provider,
                        isEnabled: selectedProviders.contains(provider),
                        onToggle: {
                            if selectedProviders.contains(provider) {
                                selectedProviders.remove(provider)
                            } else {
                                selectedProviders.insert(provider)
                            }
                            // Update preview to first active provider
                            if let first = activeProviders.first {
                                previewProvider = first
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            // Inspect tabs (only if at least one provider selected)
            if !activeProviders.isEmpty {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        // Provider selector (if multiple)
                        if activeProviders.count > 1 {
                            ForEach(activeProviders) { provider in
                                TabButton(
                                    title: provider == .claudeCode ? "Claude" : "Copilot",
                                    isSelected: previewProvider == provider
                                ) { previewProvider = provider }
                            }
                            Spacer().frame(width: 12)
                        }
                        TabButton(title: "Hook Script", isSelected: selectedTab == 0) { selectedTab = 0 }
                        TabButton(title: "Config Changes", isSelected: selectedTab == 1) { selectedTab = 1 }
                    }
                    .padding(.horizontal, 24)

                    ScrollView {
                        if selectedTab == 0 {
                            SyntaxHighlightedCode(code: hookScripts[previewProvider] ?? "", language: .bash)
                                .padding(12)
                        } else {
                            SyntaxHighlightedCode(code: settingsPreviews[previewProvider] ?? "", language: .json)
                                .padding(12)
                        }
                    }
                    .frame(height: 150)
                    .background(Color(red: 0.08, green: 0.08, blue: 0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                }
            }

            Spacer()

            // Privacy note
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
                Text("No data leaves your machine. No network calls. Local only.")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.bottom, 12)

            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button("Install Hooks") { onInstall(selectedProviders) }
                    .buttonStyle(.plain)
                    .foregroundColor(selectedProviders.isEmpty ? .white.opacity(0.3) : .white)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(selectedProviders.isEmpty ? Color.white.opacity(0.08) : Color(red: 0.35, green: 0.65, blue: 1.0))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .disabled(selectedProviders.isEmpty)
            }
            .padding(.bottom, 20)
        }
        .frame(width: 480, height: 580)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
        )
        .environment(\.colorScheme, .dark)
    }
}

struct ProviderToggleRow: View {
    let provider: HookProvider
    let isEnabled: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isEnabled ? Color(red: 0.35, green: 0.65, blue: 1.0) : .white.opacity(0.3))

                Image(systemName: provider.icon)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(isEnabled ? 0.9 : 0.4))
                    Text(provider.configPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(isEnabled ? 0.4 : 0.2))
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isEnabled ? Color.white.opacity(0.05) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

struct SetupStep: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(Color(red: 0.35, green: 0.65, blue: 1.0))
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .white.opacity(0.4))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.white.opacity(0.1) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Syntax Highlighting

enum CodeLanguage {
    case bash
    case json
}

struct SyntaxHighlightedCode: View {
    let code: String
    let language: CodeLanguage

    private static let commentColor = Color(red: 0.4, green: 0.7, blue: 0.4)    // green
    private static let stringColor = Color(red: 0.9, green: 0.6, blue: 0.3)      // orange
    private static let keywordColor = Color(red: 0.7, green: 0.5, blue: 0.9)     // purple
    private static let variableColor = Color(red: 0.4, green: 0.8, blue: 0.9)    // cyan
    private static let numberColor = Color(red: 0.85, green: 0.7, blue: 0.4)     // gold
    private static let keyColor = Color(red: 0.55, green: 0.8, blue: 1.0)        // blue
    private static let defaultColor = Color.white.opacity(0.75)

    private static let bashKeywords: Set<String> = [
        "if", "then", "else", "elif", "fi", "for", "do", "done", "while",
        "case", "esac", "in", "function", "return", "exit", "import",
        "def", "class", "try", "except", "with", "as", "from", "pass",
        "True", "False", "None", "not", "and", "or", "is"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(code.components(separatedBy: "\n").enumerated()), id: \.offset) { index, line in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.2))
                        .frame(width: 28, alignment: .trailing)

                    highlightedLine(line)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func highlightedLine(_ line: String) -> some View {
        switch language {
        case .bash:
            bashHighlight(line)
        case .json:
            jsonHighlight(line)
        }
    }

    private func bashHighlight(_ line: String) -> Text {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Full-line comment
        if trimmed.hasPrefix("#") {
            return Text(line)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(Self.commentColor)
        }

        // Inline — tokenize simply
        var result = Text("")
        let chars = Array(line)
        var i = 0

        while i < chars.count {
            let ch = chars[i]

            // String (double quote)
            if ch == "\"" {
                var str = String(ch)
                i += 1
                while i < chars.count && chars[i] != "\"" {
                    str.append(chars[i])
                    i += 1
                }
                if i < chars.count { str.append(chars[i]); i += 1 }
                result = result + Text(str).font(.system(size: 10.5, design: .monospaced)).foregroundColor(Self.stringColor)
                continue
            }

            // String (single quote)
            if ch == "'" {
                var str = String(ch)
                i += 1
                while i < chars.count && chars[i] != "'" {
                    str.append(chars[i])
                    i += 1
                }
                if i < chars.count { str.append(chars[i]); i += 1 }
                result = result + Text(str).font(.system(size: 10.5, design: .monospaced)).foregroundColor(Self.stringColor)
                continue
            }

            // Variable ($...)
            if ch == "$" {
                var v = String(ch)
                i += 1
                if i < chars.count && chars[i] == "{" {
                    while i < chars.count && chars[i] != "}" {
                        v.append(chars[i]); i += 1
                    }
                    if i < chars.count { v.append(chars[i]); i += 1 }
                } else {
                    while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") {
                        v.append(chars[i]); i += 1
                    }
                }
                result = result + Text(v).font(.system(size: 10.5, design: .monospaced)).foregroundColor(Self.variableColor)
                continue
            }

            // Inline comment
            if ch == "#" {
                let rest = String(chars[i...])
                result = result + Text(rest).font(.system(size: 10.5, design: .monospaced)).foregroundColor(Self.commentColor)
                break
            }

            // Word (keyword check)
            if ch.isLetter || ch == "_" {
                var word = String(ch)
                i += 1
                while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") {
                    word.append(chars[i]); i += 1
                }
                let color = Self.bashKeywords.contains(word) ? Self.keywordColor : Self.defaultColor
                result = result + Text(word).font(.system(size: 10.5, design: .monospaced)).foregroundColor(color)
                continue
            }

            // Number
            if ch.isNumber {
                var num = String(ch)
                i += 1
                while i < chars.count && (chars[i].isNumber || chars[i] == ".") {
                    num.append(chars[i]); i += 1
                }
                result = result + Text(num).font(.system(size: 10.5, design: .monospaced)).foregroundColor(Self.numberColor)
                continue
            }

            // Default character
            result = result + Text(String(ch)).font(.system(size: 10.5, design: .monospaced)).foregroundColor(Self.defaultColor)
            i += 1
        }

        return result
    }

    private func jsonHighlight(_ line: String) -> Text {
        var result = Text("")
        let chars = Array(line)
        var i = 0

        while i < chars.count {
            let ch = chars[i]

            if ch == "\"" {
                var str = String(ch)
                i += 1
                while i < chars.count && chars[i] != "\"" {
                    str.append(chars[i]); i += 1
                }
                if i < chars.count { str.append(chars[i]); i += 1 }
                // Keys vs values: key if followed by ':'
                let rest = String(chars[i...]).trimmingCharacters(in: .whitespaces)
                let color = rest.hasPrefix(":") ? Self.keyColor : Self.stringColor
                result = result + Text(str).font(.system(size: 10.5, design: .monospaced)).foregroundColor(color)
                continue
            }

            if ch.isNumber {
                var num = String(ch)
                i += 1
                while i < chars.count && (chars[i].isNumber || chars[i] == ".") {
                    num.append(chars[i]); i += 1
                }
                result = result + Text(num).font(.system(size: 10.5, design: .monospaced)).foregroundColor(Self.numberColor)
                continue
            }

            // true/false/null
            if ch.isLetter {
                var word = String(ch)
                i += 1
                while i < chars.count && chars[i].isLetter {
                    word.append(chars[i]); i += 1
                }
                let color = ["true", "false", "null"].contains(word) ? Self.keywordColor : Self.defaultColor
                result = result + Text(word).font(.system(size: 10.5, design: .monospaced)).foregroundColor(color)
                continue
            }

            result = result + Text(String(ch)).font(.system(size: 10.5, design: .monospaced)).foregroundColor(Self.defaultColor)
            i += 1
        }

        return result
    }
}

/// Manages the setup window
class SetupWindowController {
    private var window: NSWindow?

    func show(hookScripts: [HookProvider: String], settingsPreviews: [HookProvider: String], onInstall: @escaping (Set<HookProvider>) -> Void, onCancel: @escaping () -> Void) {
        let view = NSHostingView(rootView: SetupView(
            hookScripts: hookScripts,
            settingsPreviews: settingsPreviews,
            onInstall: { [weak self] providers in
                self?.close()
                onInstall(providers)
            },
            onCancel: { [weak self] in
                self?.close()
                onCancel()
            }
        ))

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 580),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false
        panel.contentView = view
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window = panel
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }
}
