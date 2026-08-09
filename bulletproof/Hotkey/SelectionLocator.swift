import AppKit
import ApplicationServices

/// Finds the on-screen rectangle of the focused app's text selection via the
/// Accessibility API, so the success flash can land exactly on the replaced
/// text. Every failure path returns nil - callers fall back to a cursor chip.
@MainActor enum SelectionLocator {
    static func selectionScreenRect() -> NSRect? {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        let systemWide = AXUIElementCreateSystemWide()
        // A hung or slow target app must not stall the paste flow.
        AXUIElementSetMessagingTimeout(systemWide, 0.25)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return nil
        }
        let element = focusedRef as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.25)

        guard let axRect = selectionBounds(of: element) ?? plausibleFieldFrame(of: element) else {
            return nil
        }
        let rect = flipped(axRect, primaryHeight: primaryHeight)
        // A selection scrolled offscreen can report bounds on no display.
        guard NSScreen.screens.contains(where: { $0.frame.intersects(rect) }) else { return nil }
        return rect
    }

    /// AX y grows downward from the top of the primary display; AppKit y grows
    /// upward from its bottom. Both anchor to the primary screen, so one flip
    /// against the primary height is correct on every display.
    nonisolated static func flipped(_ axRect: CGRect, primaryHeight: CGFloat) -> NSRect {
        NSRect(x: axRect.minX, y: primaryHeight - axRect.maxY,
               width: axRect.width, height: axRect.height)
    }

    private static func selectionBounds(of element: AXUIElement) -> CGRect? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() else {
            return nil
        }
        let rangeValue = rangeRef as! AXValue
        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range), range.length > 0 else { return nil }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
                element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &boundsRef) == .success,
              let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID() else {
            return nil
        }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect),
              rect.width > 0, rect.height > 0 else {
            return nil
        }
        return rect
    }

    /// Fallback when the selection bounds are unavailable: the focused
    /// element's own frame, but only when it plausibly is a text field -
    /// flashing an entire editor pane reads as a glitch.
    private static func plausibleFieldFrame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef,
              CFGetTypeID(positionRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size),
              size.width > 0, size.height > 0,
              size.width <= 700, size.height <= 300 else {
            return nil
        }
        return CGRect(origin: point, size: size)
    }
}
