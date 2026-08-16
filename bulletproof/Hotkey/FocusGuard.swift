import AppKit
import ApplicationServices

/// Refuses the hotkey flow when focus sits somewhere a destructive
/// copy/paste round-trip must never touch: secure fields (the text would go
/// to a model) and terminals (a "corrected" shell command changes behavior).
nonisolated enum FocusGuard {
    enum BlockReason: CaseIterable {
        case secureField
        case terminal

        var message: String {
            switch self {
            case .secureField:
                "This looks like a password or code field, so it was left untouched."
            case .terminal:
                "Proofreading a shell command could change what it runs, so terminals are left untouched."
            }
        }

        var telemetryReason: String {
            switch self {
            case .secureField: "secure-field"
            case .terminal: "terminal"
            }
        }
    }

    private static let secureMarkers = [
        "password", "passcode", "passphrase", "cvv", "cvc", "security code",
        "one-time", "one time", "otp", "verification code", "card number",
        "social security", "pin",
    ]

    private static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty", "com.github.wez.wezterm", "com.mitchellh.ghostty",
        "co.zeit.hyper", "org.alacritty",
    ]

    static func isSecureField(subrole: String?, roleDescription: String?, title: String?,
                              description: String?, placeholder: String?) -> Bool {
        if subrole == "AXSecureTextField" { return true }
        // The role description is the only place NSSecureTextField announces
        // itself in some hosts.
        if roleDescription?.lowercased().contains("secure") == true { return true }
        return [title, description, placeholder].compactMap(\.self).contains(where: containsSecureMarker)
    }

    static func isTerminal(bundleID: String?, domClasses: [String]) -> Bool {
        if let bundleID, terminalBundleIDs.contains(bundleID) { return true }
        // VS Code's editor and integrated terminal share one process; only
        // the xterm DOM class tells them apart.
        return domClasses.contains { $0.hasPrefix("xterm") }
    }

    /// Word-bounded so "pin" never fires inside "shipping" or "spinner".
    private static func containsSecureMarker(_ text: String) -> Bool {
        secureMarkers.contains { marker in
            text.range(of: "\\b\(NSRegularExpression.escapedPattern(for: marker))\\b",
                       options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    /// Nil when the focused element is safe to touch. Unknown focus is not a
    /// reason to refuse - plenty of safe hosts expose nothing over AX.
    @MainActor static func blockReason() -> BlockReason? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.25)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return nil
        }
        let element = focusedRef as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.25)

        if isSecureField(subrole: string(kAXSubroleAttribute, of: element),
                         roleDescription: string(kAXRoleDescriptionAttribute, of: element),
                         title: string(kAXTitleAttribute, of: element),
                         description: string(kAXDescriptionAttribute, of: element),
                         placeholder: string(kAXPlaceholderValueAttribute, of: element)) {
            return .secureField
        }

        var pid: pid_t = 0
        let bundleID: String? = AXUIElementGetPid(element, &pid) == .success
            ? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            : nil
        if isTerminal(bundleID: bundleID, domClasses: stringArray("AXDOMClassList", of: element)) {
            return .terminal
        }
        return nil
    }

    private static func string(_ attribute: String, of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else {
            return nil
        }
        return ref as? String
    }

    private static func stringArray(_ attribute: String, of element: AXUIElement) -> [String] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else {
            return []
        }
        return ref as? [String] ?? []
    }
}
