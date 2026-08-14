import AppKit
import ApplicationServices

/// Presses the host app's own Edit menu items (Copy, Paste), found by their
/// ⌘ key equivalent - localization-proof - and cached per app. A menu press
/// cannot have its ⌘ flag stripped by a physically held key the way a
/// synthetic keystroke can.
@MainActor final class MenuActionPoster {
    static let shared = MenuActionPoster()

    private var cache: [pid_t: [String: AXUIElement]] = [:]

    /// True when the item was found, enabled, and pressed. False sends the
    /// caller to the synthetic-keystroke fallback.
    func press(keyEquivalent: String, pid: pid_t) -> Bool {
        if let cached = cache[pid]?[keyEquivalent], press(cached) {
            return true
        }
        cache[pid]?[keyEquivalent] = nil
        guard let item = findItem(keyEquivalent: keyEquivalent, pid: pid) else { return false }
        cache[pid, default: [:]][keyEquivalent] = item
        return press(item)
    }

    /// Plain-⌘ equivalents only: cmdModifiers 0 is ⌘ alone, so ⇧⌘V
    /// (Paste and Match Style) can never be mistaken for Paste.
    nonisolated static func matches(keyEquivalent: String, cmdChar: String?, cmdModifiers: Int?) -> Bool {
        guard let cmdChar, let cmdModifiers else { return false }
        return cmdChar.caseInsensitiveCompare(keyEquivalent) == .orderedSame && cmdModifiers == 0
    }

    private func press(_ item: AXUIElement) -> Bool {
        // A disabled Paste would swallow the press silently and the flow
        // would restore the clipboard over a paste that never happened.
        guard boolValue(kAXEnabledAttribute, of: item) == true else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    private func findItem(keyEquivalent: String, pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let menuBar = element(kAXMenuBarAttribute, of: app) else { return nil }
        // Top-level menu items only: Copy and Paste never live in submenus.
        for barItem in children(of: menuBar) {
            for menu in children(of: barItem) {
                for item in children(of: menu) where Self.matches(
                        keyEquivalent: keyEquivalent,
                        cmdChar: string("AXMenuItemCmdChar", of: item),
                        cmdModifiers: intValue("AXMenuItemCmdModifiers", of: item)) {
                    return item
                }
            }
        }
        return nil
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
              let array = ref as? [AXUIElement] else {
            return []
        }
        return array
    }

    private func element(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else {
            return nil
        }
        return (ref as! AXUIElement)
    }

    private func string(_ attribute: String, of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else {
            return nil
        }
        return ref as? String
    }

    private func intValue(_ attribute: String, of element: AXUIElement) -> Int? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else {
            return nil
        }
        return (ref as? NSNumber)?.intValue
    }

    private func boolValue(_ attribute: String, of element: AXUIElement) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else {
            return nil
        }
        return (ref as? NSNumber)?.boolValue
    }
}
