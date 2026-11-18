import Cocoa
import ApplicationServices

func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}
func frame(_ e: AXUIElement) -> String {
    var p = CGPoint.zero, s = CGSize.zero
    if let pv = attr(e, kAXPositionAttribute) { AXValueGetValue(pv as! AXValue, .cgPoint, &p) }
    if let sv = attr(e, kAXSizeAttribute) { AXValueGetValue(sv as! AXValue, .cgSize, &s) }
    return "(\(Int(p.x)),\(Int(p.y)) \(Int(s.width))x\(Int(s.height)))"
}
func dump(_ e: AXUIElement, _ depth: Int) {
    if depth > 8 { return }
    let role = attr(e, kAXRoleAttribute) as? String ?? "?"
    let ident = attr(e, kAXIdentifierAttribute) as? String ?? ""
    let title = attr(e, kAXTitleAttribute) as? String ?? ""
    let desc = attr(e, kAXDescriptionAttribute) as? String ?? ""
    var names: CFArray?
    AXUIElementCopyAttributeNames(e, &names)
    let extra = (names as? [String] ?? []).filter { !["AXRole","AXChildren","AXParent","AXPosition","AXSize","AXTitle","AXDescription","AXIdentifier","AXTopLevelUIElement","AXWindow","AXFrame","AXRoleDescription","AXSubrole","AXEnabled","AXFocused","AXSelected"].contains($0) }
    print(String(repeating: "  ", count: depth) + "\(role) id=\(ident) title=\"\(title)\" desc=\"\(desc)\" \(frame(e)) extra=\(extra)")
    for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? []) { dump(c, depth + 1) }
}

print("AX trusted:", AXIsProcessTrusted())
print("Screen capture access:", CGPreflightScreenCaptureAccess())
guard AXIsProcessTrusted() else { print("NO ACCESSIBILITY — grant your terminal in System Settings > Privacy & Security > Accessibility"); exit(1) }

guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { exit(1) }
let dockAX = AXUIElementCreateApplication(dock.processIdentifier)

print("=== Dock tree BEFORE Mission Control ===")
dump(dockAX, 0)

let t = Process(); t.launchPath = "/usr/bin/open"; t.arguments = ["-a", "Mission Control"]; try! t.run(); t.waitUntilExit()
Thread.sleep(forTimeInterval: 1.5)

print("=== Dock tree DURING Mission Control ===")
dump(dockAX, 0)

// window list for matching
print("=== CGWindowList (on-screen, layer 0) ===")
let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where (w[kCGWindowLayer as String] as? Int) == 0 {
    print(w[kCGWindowNumber as String] ?? "", w[kCGWindowOwnerName as String] ?? "", "title=\"\(w[kCGWindowName as String] ?? "<nil>")\"", w[kCGWindowBounds as String] ?? "")
}

let t2 = Process(); t2.launchPath = "/usr/bin/open"; t2.arguments = ["-a", "Mission Control"]; try! t2.run(); t2.waitUntilExit()
