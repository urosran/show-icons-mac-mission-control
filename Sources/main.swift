// ExposeLabels — adds app icons, app names and window titles to Mission Control thumbnails.
// No network, no screenshots. Reads the Dock's accessibility tree + the CGWindow list.
import Cocoa
import ApplicationServices

// MARK: - Accessibility helpers

func axAttr(_ e: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}
func axChildren(_ e: AXUIElement) -> [AXUIElement] { axAttr(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
func axFrame(_ e: AXUIElement) -> CGRect? {
    guard let pv = axAttr(e, kAXPositionAttribute), let sv = axAttr(e, kAXSizeAttribute) else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(pv as! AXValue, .cgPoint, &p)
    AXValueGetValue(sv as! AXValue, .cgSize, &s)
    return CGRect(origin: p, size: s)
}
func axIdent(_ e: AXUIElement) -> String { axAttr(e, kAXIdentifierAttribute) as? String ?? "" }

// MARK: - Model

struct Thumb {
    let frame: CGRect          // global, top-left origin (AX / CG coordinates)
    let title: String
    var isSpace = false        // an entry in the Spaces bar at the top (Desktop or full-screen app)
    var barFrame: CGRect = .zero   // the Spaces bar list this entry belongs to (one per display)
    var isFullScreenApp = false
}
struct ThumbLabel {
    let frame: CGRect
    let title: String
    let appName: String
    let icon: NSImage?
    var isSpace = false
    var barFrame: CGRect = .zero
}
struct CGWin {
    let id: Int
    let pid: pid_t
    let owner: String
    let title: String
    let bounds: CGRect
}

final class Reader {
    private var dock: AXUIElement?
    private var dockPID: pid_t = 0

    private func dockElement() -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        if app.processIdentifier != dockPID {   // Dock restarted
            dockPID = app.processIdentifier
            dock = AXUIElementCreateApplication(dockPID)
            AXUIElementSetMessagingTimeout(dock!, 0.25)
        }
        return dock
    }

    /// nil = Mission Control is not open.
    func thumbnails() -> [Thumb]? {
        guard let dock = dockElement() else { return nil }
        guard let mc = axChildren(dock).first(where: { axIdent($0) == "mc" }) else { return nil }
        var out: [Thumb] = []
        for display in axChildren(mc) where axIdent(display) == "mc.display" {
            for group in axChildren(display) where axIdent(group) == "mc.windows" {
                for btn in axChildren(group) {
                    guard let f = axFrame(btn), f.width > 10, f.height > 10 else { continue }
                    out.append(Thumb(frame: f, title: axAttr(btn, kAXTitleAttribute) as? String ?? ""))
                }
            }
            for group in axChildren(display) where axIdent(group) == "mc.spaces" {
                collectSpaces(group, bar: axFrame(group) ?? .zero, into: &out, depth: 0)
            }
        }
        return out
    }

    /// Spaces-bar entries are AXButtons (nested in a list) described "exit to Desktop" / "exit to full screen …".
    /// The Dock reports the same (expanded) frames whether the bar is collapsed or not.
    private func collectSpaces(_ e: AXUIElement, bar: CGRect, into out: inout [Thumb], depth: Int) {
        guard depth < 4 else { return }
        for c in axChildren(e) {
            let role = axAttr(c, kAXRoleAttribute) as? String ?? ""
            let desc = axAttr(c, kAXDescriptionAttribute) as? String ?? ""
            if role == kAXButtonRole, desc.hasPrefix("exit to"), let f = axFrame(c) {
                out.append(Thumb(frame: f, title: axAttr(c, kAXTitleAttribute) as? String ?? "", isSpace: true,
                                 barFrame: bar, isFullScreenApp: desc.hasPrefix("exit to full screen")))
            } else {
                collectSpaces(c, bar: bar, into: &out, depth: depth + 1)
            }
        }
    }

    /// Cheap check used every frame while Mission Control is open.
    func missionControlIsOpen() -> Bool {
        guard let dock = dockElement() else { return false }
        return axChildren(dock).contains { axIdent($0) == "mc" }
    }

    var dockAX: AXUIElement? { dockElement() }
    var dockProcess: pid_t { _ = dockElement(); return dockPID }

    func windows() -> [CGWin] {
        let raw = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let myPID = ProcessInfo.processInfo.processIdentifier
        return raw.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != myPID,
                  let bd = w[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: bd), b.width > 50, b.height > 50 else { return nil }
            return CGWin(id: w[kCGWindowNumber as String] as? Int ?? 0, pid: pid,
                         owner: w[kCGWindowOwnerName as String] as? String ?? "",
                         title: w[kCGWindowName as String] as? String ?? "", bounds: b)
        }
    }

    /// Match each thumbnail to a real window: exact title first, aspect ratio breaks ties.
    func labels(for thumbs: [Thumb]) -> [ThumbLabel] {
        let wins = windows()
        var used = Set<Int>()
        func aspectDiff(_ a: CGRect, _ b: CGRect) -> CGFloat { abs(a.width / a.height - b.width / b.height) }

        return thumbs.map { t in
            if t.isSpace { return spaceLabel(t, wins) }
            var cands = wins.filter { !used.contains($0.id) && !t.title.isEmpty && $0.title == t.title }
            if cands.isEmpty { // title unknown/mismatched: fall back to the closest aspect ratio
                cands = wins.filter { !used.contains($0.id) && aspectDiff($0.bounds, t.frame) < 0.03 }
            }
            let best = cands.min { aspectDiff($0.bounds, t.frame) < aspectDiff($1.bounds, t.frame) }
            if let b = best { used.insert(b.id) }
            let app = best.flatMap { NSRunningApplication(processIdentifier: $0.pid) }
            return ThumbLabel(frame: t.frame,
                         title: t.title,
                         appName: app?.localizedName ?? best?.owner ?? "",
                         icon: app?.icon)
        }
    }

    /// Spaces-bar thumbnails all have the screen's aspect ratio, so match on title only (never guess).
    /// Split View spaces are titled "A & B" or similar: fall back to an app whose name or window title is in it.
    private func spaceLabel(_ t: Thumb, _ wins: [CGWin]) -> ThumbLabel {
        let title = t.title.trimmingCharacters(in: .whitespaces)
        var match = wins.first { !title.isEmpty && $0.title == title }
            ?? wins.first { !title.isEmpty && $0.owner == title }
        if match == nil, !title.isEmpty {
            match = wins.first { !$0.title.isEmpty && title.hasPrefix($0.title) }
                ?? wins.first { !$0.owner.isEmpty && title.hasPrefix($0.owner) }
        }
        let app = t.isFullScreenApp ? match.flatMap { NSRunningApplication(processIdentifier: $0.pid) } : nil
        return ThumbLabel(frame: t.frame, title: t.title, appName: app?.localizedName ?? "", icon: app?.icon,
                          isSpace: true, barFrame: t.barFrame)
    }
}

// MARK: - Overlay

final class OverlayView: NSView {
    var labels: [ThumbLabel] = [] { didSet { needsDisplay = true } }
    var iconSize: CGFloat = 56
    override var isFlipped: Bool { true }   // match AX top-left coordinates

    override func draw(_ dirty: NSRect) {
        guard let win = window, let screen = win.screen else { return }
        let primaryH = NSScreen.screens.first?.frame.height ?? screen.frame.height
        // convert global top-left coords -> this view's flipped coords
        let originTL = CGPoint(x: screen.frame.minX, y: primaryH - screen.frame.maxY)

        for l in labels {
            let r = l.frame.offsetBy(dx: -originTL.x, dy: -originTL.y)
            // Collapsed Spaces-bar names report a y above the screen, so test the bar's frame for them.
            let onScreen = l.isSpace ? l.barFrame.offsetBy(dx: -originTL.x, dy: -originTL.y) : r
            guard onScreen.intersects(bounds) else { continue }
            if l.isSpace {   // small icon sitting inside the bottom edge of the Spaces-bar thumbnail
                guard let icon = l.icon else { continue }
                let bar = l.barFrame.offsetBy(dx: -originTL.x, dy: -originTL.y)
                let ir: CGRect
                if bar.height < 120 {
                    // Collapsed bar (names only). The Dock reports each name's exact x and width,
                    // but a bogus y; the names sit 20 pt above the bar's bottom edge.
                    let sz: CGFloat = 18
                    ir = CGRect(x: r.minX - sz - 6, y: bar.maxY - 20 - sz / 2, width: sz, height: sz)
                } else {
                    let sz = min(30, r.height * 0.4)
                    ir = CGRect(x: r.midX - sz / 2, y: r.maxY - sz - 4, width: sz, height: sz)
                }
                NSGraphicsContext.saveGraphicsState()
                let sh = NSShadow(); sh.shadowBlurRadius = 4; sh.shadowColor = .black.withAlphaComponent(0.6); sh.set()
                icon.draw(in: ir, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                NSGraphicsContext.restoreGraphicsState()
                continue
            }
            let size = min(iconSize, r.height * 0.35, r.width * 0.35)

            // icon: centred, straddling the bottom edge of the thumbnail
            let iconRect = CGRect(x: r.midX - size / 2, y: r.maxY - size * 0.6, width: size, height: size)
            if let icon = l.icon {
                NSGraphicsContext.saveGraphicsState()
                let sh = NSShadow(); sh.shadowBlurRadius = 6; sh.shadowColor = .black.withAlphaComponent(0.5); sh.set()
                icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                NSGraphicsContext.restoreGraphicsState()
            }

            // label pill under the icon
            let nameAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white]
            let titleAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white.withAlphaComponent(0.85)]
            let maxW = max(r.width - 16, 80)
            let name = truncate(l.appName, attrs: nameAttrs, maxW: maxW)
            let title = (l.title.isEmpty || l.title == l.appName) ? "" : truncate(l.title, attrs: titleAttrs, maxW: maxW)
            let nameSz = (name as NSString).size(withAttributes: nameAttrs)
            let titleSz = title.isEmpty ? .zero : (title as NSString).size(withAttributes: titleAttrs)
            let pillW = max(nameSz.width, titleSz.width) + 20
            let pillH = nameSz.height + (title.isEmpty ? 0 : titleSz.height + 1) + 8
            let pill = CGRect(x: r.midX - pillW / 2, y: iconRect.maxY + 4, width: pillW, height: pillH)
            guard !name.isEmpty || !title.isEmpty else { continue }
            NSColor.black.withAlphaComponent(0.65).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8).fill()
            (name as NSString).draw(at: CGPoint(x: pill.midX - nameSz.width / 2, y: pill.minY + 4), withAttributes: nameAttrs)
            if !title.isEmpty {
                (title as NSString).draw(at: CGPoint(x: pill.midX - titleSz.width / 2, y: pill.minY + 5 + nameSz.height), withAttributes: titleAttrs)
            }
        }
    }

    private func truncate(_ s: String, attrs: [NSAttributedString.Key: Any], maxW: CGFloat) -> String {
        if (s as NSString).size(withAttributes: attrs).width <= maxW { return s }
        var t = s
        while !t.isEmpty && ((t + "…") as NSString).size(withAttributes: attrs).width > maxW { t.removeLast() }
        return t + "…"
    }
}

final class Overlay {
    private var windows: [NSWindow] = []

    func show(_ labels: [ThumbLabel]) {
        if windows.count != NSScreen.screens.count || zip(windows, NSScreen.screens).contains(where: { $0.frame != $1.frame }) {
            rebuild()
        }
        for w in windows {
            (w.contentView as! OverlayView).labels = labels
            w.orderFrontRegardless()
        }
    }

    func hide() { windows.forEach { $0.orderOut(nil) } }

    private func rebuild() {
        windows.forEach { $0.close() }
        windows = NSScreen.screens.map { s in
            let w = NSWindow(contentRect: s.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            w.setFrame(s.frame, display: false)
            w.contentView = OverlayView(frame: CGRect(origin: .zero, size: s.frame.size))
            return w
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    let reader = Reader()
    let overlay = Overlay()
    var status: NSStatusItem!
    var timer: Timer?
    var enabled = true
    var wasOpen = false
    var lastThumbs: [CGRect] = []
    let setup = SetupWindowController()

    func applicationDidFinishLaunching(_ n: Notification) {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "ExposeLabels")
        rebuildMenu()

        // Single instance: a manual login item + "Open at login" could both launch us.
        let me = ProcessInfo.processInfo.processIdentifier
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .contains(where: { $0.processIdentifier != me }) { NSApp.terminate(nil); return }

        // Show setup on first launch, and whenever the required permission is missing.
        let firstRun = !UserDefaults.standard.bool(forKey: "didShowSetup")
        if firstRun || !AXIsProcessTrusted() {
            UserDefaults.standard.set(true, forKey: "didShowSetup")
            setup.show()
        }

        observeDock()
        schedule(open: false)
    }

    // MARK: Mission Control tracking

    /// Idle: check every 250 ms (the Dock's open notification usually beats it).
    /// Open: every 30 ms, so labels vanish the moment Mission Control starts closing.
    func schedule(open: Bool) {
        let interval = open ? 0.03 : 0.25
        if let t = timer, t.timeInterval == interval { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = open ? 0.005 : 0.05
    }

    var observer: AXObserver?
    var observedDock: pid_t = 0
    var exiting = false          // Dock said "exit": stay hidden until Mission Control is fully gone

    func observeDock() {
        guard AXIsProcessTrusted(), let dock = reader.dockAX else { return }
        let pid = reader.dockProcess
        guard pid != observedDock else { return }
        var obs: AXObserver?
        let cb: AXObserverCallback = { _, _, name, ctx in
            let me = Unmanaged<AppDelegate>.fromOpaque(ctx!).takeUnretainedValue()
            if (name as String) == "AXExposeExit" { me.hideNow(exiting: true) } else { me.tick() }
        }
        guard AXObserverCreate(pid, cb, &obs) == .success, let obs else { return }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        for n in ["AXExposeShowAllWindows", "AXExposeShowFrontWindows", "AXExposeShowDesktop", "AXExposeExit"] {
            AXObserverAddNotification(obs, dock, n as CFString, ctx)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
        observedDock = pid
    }

    func hideNow(exiting: Bool = false) {
        overlay.hide()
        wasOpen = false
        lastThumbs = []
        self.exiting = exiting
        schedule(open: exiting)
    }

    func tick() {
        guard enabled, AXIsProcessTrusted() else { if wasOpen { hideNow() }; return }
        observeDock()   // no-op unless the Dock restarted or permission just arrived
        guard reader.missionControlIsOpen() else {
            if wasOpen || exiting { hideNow() }
            exiting = false
            return
        }
        schedule(open: true)
        if exiting { return }
        guard let thumbs = reader.thumbnails(), !thumbs.isEmpty else { if wasOpen { hideNow() }; return }
        let frames = thumbs.map(\.frame)
        if frames == lastThumbs && wasOpen { return }   // layout unchanged (the bar collapsing/expanding changes it)
        lastThumbs = frames
        wasOpen = true
        overlay.show(reader.labels(for: thumbs))
    }

    func rebuildMenu() {
        let m = NSMenu()
        let toggle = NSMenuItem(title: "Show labels in Mission Control", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.state = enabled ? .on : .off
        toggle.target = self
        m.addItem(toggle)
        m.addItem(.separator())
        let setupItem = NSMenuItem(title: "Setup & Permissions…", action: #selector(showSetup), keyEquivalent: ",")
        setupItem.target = self
        m.addItem(setupItem)
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "Quit ExposeLabels", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        status.menu = m
    }

    @objc func toggleEnabled() { enabled.toggle(); if !enabled { overlay.hide(); wasOpen = false }; rebuildMenu() }
    @objc func showSetup() { setup.show() }

    // Opening the app again from Finder/Launchpad while it is running brings the setup window up.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        setup.show(); return false
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
