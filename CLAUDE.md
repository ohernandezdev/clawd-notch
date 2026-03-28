# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build

Open `ClawdNotch.xcodeproj` in Xcode and build (Cmd+B). Or from the command line:

```bash
xcodebuild -project ClawdNotch.xcodeproj -scheme ClawdNotch -configuration Debug build
```

There are no tests or linting configured yet.

## Overview

Claw'd Notch is a macOS menu bar app that provides a floating terminal panel anchored to the MacBook notch, with automatic Xcode project detection. When the user hovers over the notch or clicks the menu bar icon, a floating panel appears with embedded terminal sessions (via SwiftTerm) that auto-`cd` into detected Xcode project directories and launch `claude`.

## Architecture

**App lifecycle**: `ClawdNotchApp` uses `@NSApplicationDelegateAdaptor` to delegate to `AppDelegate`, which owns the `NSStatusItem` (menu bar icon), the `TerminalPanel`, and the `NotchWindow`. The SwiftUI `App` body is an empty `Settings` scene — all UI lives in the panel and notch window.

**Notch integration**: `NotchWindow` is an always-visible `NSPanel` positioned over the MacBook notch. It detects notch dimensions via `NSScreen.auxiliaryTopLeftArea`/`auxiliaryTopRightArea`, tracks mouse hover to trigger the main panel, and expands with a bounce animation (via `CVDisplayLinkWrapper`) when any session is working. `NotchPillContent` (SwiftUI) renders status icons (spinner, checkmark, warning) inside the pill. `NotchDisplayState` computes a priority-based aggregate status across all sessions.

**Session management**: `SessionStore` (singleton, `@Observable`) holds the list of `TerminalSession` values and the active selection. It coordinates with `XcodeDetector` to discover open Xcode projects via AppleScript (with a CGWindow title fallback). Sessions use lazy terminal startup — `hasStarted` is false until the user actually selects a tab. The store also manages sleep prevention (`IOPMAssertion`) while Claude is working, and polls for Xcode projects every 5 seconds when pinned.

**Terminal status detection**: `ClickThroughTerminalView` (subclass of `LocalProcessTerminalView`) reads the terminal buffer on every `dataReceived` (debounced 150ms) and classifies the output into `TerminalStatus` states: `.working` (spinner chars + token counter), `.waitingForInput` (user prompt `❯`), `.interrupted`, `.idle`. The `idle → taskCompleted` transition uses a 3-second delay to avoid false positives from brief working→idle flickers.

**Terminal embedding**: `TerminalManager` (singleton) owns a `[UUID: LocalProcessTerminalView]` dictionary. Terminals are created on demand, spawning the user's login shell, then sending `cd <project-dir> && clear && claude`. `TerminalSessionView` is an `NSViewRepresentable` that attaches/detaches the terminal view to a container based on the active session ID.

**Panel**: `TerminalPanel` is an `NSPanel` (borderless, floating, non-activating) that shows/hides below the notch or status item. It hides on resign-key unless pinned. Supports Cmd+S for checkpoints. `PanelContentView` composes the tab bar and terminal area.

**Tab bar**: `SessionTabBar` renders tabs with a green/gray dot indicating whether the Xcode project is still open. Tabs support rename (via context menu) and close.

**Checkpoints**: `CheckpointManager` creates git snapshots using custom refs (`refs/Notchy-snapshots/<project>/<timestamp>`). It uses a temporary `GIT_INDEX_FILE` to avoid disturbing the user's staging area. Checkpoints can be created (Cmd+S or menu), listed, and restored.

**Hover behavior**: `AppDelegate` manages a dual interaction model — notch hover opens the panel with mouse-tracking that auto-hides when the cursor leaves, while status item click opens normally with resign-key hiding. The backtick key (keyCode 50) is a global hotkey to toggle the panel.

## Dependencies

- **SwiftTerm** (`migueldeicaza/SwiftTerm`) — terminal emulator view (`LocalProcessTerminalView`)

## Entitlements

No special entitlements required. Session data is stored in `$TMPDIR/notchy-sessions/` (per-user, chmod 700).
