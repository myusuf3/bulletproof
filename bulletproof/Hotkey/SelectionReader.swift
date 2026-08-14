import AppKit
import ApplicationServices

/// Reads the focused element's selected text straight through AX - no
/// synthetic ⌘C, no pasteboard round-trip, no timeout. Every failure path
/// returns nil and the caller falls back to the copy flow. Writes still go
/// through paste: AX writes silently no-op in Chromium contenteditable, so
/// read-via-AX / write-via-paste is the right asymmetry.
@MainActor enum SelectionReader {
    static func selectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.25)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return nil
        }
        let element = focusedRef as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.25)
        primeChromium(for: element)

        if let text = selectedTextAttribute(of: element) { return text }
        if let text = selectedTextViaRange(of: element) { return text }
        return selectedTextViaTextMarkers(of: element)
    }

    /// Chromium builds its AX tree lazily. AXManualAccessibility asks for it
    /// without AXEnhancedUserInterface's window-manager glitches, and is
    /// re-asserted every flow because Electron editors drop it on
    /// activation. Non-Chromium hosts ignore the attribute.
    private static func primeChromium(for element: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return }
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid),
                                     "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    private static func selectedTextAttribute(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &ref) == .success,
              let text = ref as? String, !text.isEmpty else {
            return nil
        }
        return text
    }

    private static func selectedTextViaRange(of element: AXUIElement) -> String? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() else {
            return nil
        }
        var range = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &range), range.length > 0 else {
            return nil
        }
        var strRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
                element, kAXStringForRangeParameterizedAttribute as CFString,
                rangeRef as! AXValue, &strRef) == .success,
              let text = strRef as? String, !text.isEmpty else {
            return nil
        }
        return text
    }

    /// Chromium and WebKit expose selections through private text-marker
    /// attributes; the plain range API returns nothing there.
    private static func selectedTextViaTextMarkers(of element: AXUIElement) -> String? {
        var markerRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRange) == .success,
              let markerRange else {
            return nil
        }
        var strRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
                element, "AXStringForTextMarkerRange" as CFString,
                markerRange, &strRef) == .success,
              let text = strRef as? String, !text.isEmpty else {
            return nil
        }
        return text
    }
}
