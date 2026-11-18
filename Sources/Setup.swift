// Setup window: explains the app, shows live permission status, grants, launch at login.
import Cocoa
import SwiftUI
import ServiceManagement
import ApplicationServices

final class PermissionState: ObservableObject {
    @Published var accessibility = AXIsProcessTrusted()
    @Published var screenRecording = CGPreflightScreenCaptureAccess()
    @Published var openAtLogin = SMAppService.mainApp.status == .enabled
    /// Screen Recording only takes effect after a relaunch; remember that the user asked for it.
    @Published var screenRecordingRequested = false
    private var timer: Timer?

    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }
    func stopPolling() { timer?.invalidate(); timer = nil }

    func refresh() {
        accessibility = AXIsProcessTrusted()
        screenRecording = CGPreflightScreenCaptureAccess()
        openAtLogin = SMAppService.mainApp.status == .enabled
    }

    func grantAccessibility() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        openPane("Privacy_Accessibility")
    }
    func grantScreenRecording() {
        screenRecordingRequested = true
        if !CGRequestScreenCaptureAccess() { openPane("Privacy_ScreenCapture") }
    }
    func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            // Fallback: let the user add it by hand.
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
        }
        refresh()
    }
    private func openPane(_ anchor: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }
}

func relaunchApp() {
    let path = Bundle.main.bundlePath
    let p = Process()
    p.launchPath = "/bin/sh"
    p.arguments = ["-c", "sleep 0.7; /usr/bin/open \"\(path)\""]
    try? p.run()
    NSApp.terminate(nil)
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let required: Bool
    let granted: Bool
    let pendingRelaunch: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .frame(width: 28)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    Text(required ? "Required" : "Optional")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(required ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.15)))
                }
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
                    .font(.callout.weight(.medium))
                    .frame(minWidth: 96, alignment: .trailing)
            } else if pendingRelaunch {
                Button("Relaunch", action: relaunchApp)
                    .frame(minWidth: 96, alignment: .trailing)
            } else {
                Button("Grant…", action: action)
                    .buttonStyle(.borderedProminent)
                    .frame(minWidth: 96, alignment: .trailing)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }
}

struct SetupView: View {
    @ObservedObject var state: PermissionState
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("ExposeLabels").font(.title2.bold())
                    Text("Shows each app’s icon, name and window title on the thumbnails in Mission Control, so you can tell windows apart at a glance.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("macOS needs your permission for this to work. Nothing leaves your Mac: no screenshots, no network.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            PermissionRow(
                icon: "accessibility",
                title: "Accessibility",
                detail: "Reads where Mission Control places each window thumbnail.",
                required: true,
                granted: state.accessibility,
                pendingRelaunch: false,
                action: state.grantAccessibility)

            PermissionRow(
                icon: "rectangle.dashed.badge.record",
                title: "Screen Recording",
                detail: "Reads window titles only. Without it you still get icons and app names.",
                required: false,
                granted: state.screenRecording,
                pendingRelaunch: state.screenRecordingRequested,
                action: state.grantScreenRecording)

            Toggle(isOn: Binding(get: { state.openAtLogin }, set: { state.setOpenAtLogin($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open at login").font(.headline)
                    Text("Start automatically when you turn on your Mac.").font(.callout).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))

            HStack {
                if state.accessibility {
                    Label("Ready — open Mission Control to try it.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green).font(.callout)
                } else {
                    Text("After granting, it starts working right away.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(state.accessibility ? "Done" : "Later", action: close)
                    .keyboardShortcut(.defaultAction)
            }
            Text("You can reopen this window from the menu-bar icon.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(22)
        .frame(width: 520)
    }
}

final class SetupWindowController: NSObject, NSWindowDelegate {
    let state = PermissionState()
    private var window: NSWindow?

    func show() {
        state.refresh()
        state.startPolling()
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "ExposeLabels Setup"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: SetupView(state: state, close: { [weak w] in w?.close() }))
            w.setContentSize(w.contentView!.fittingSize)
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ n: Notification) { state.stopPolling() }
}
