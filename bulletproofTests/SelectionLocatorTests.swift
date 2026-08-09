import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import bulletproof

struct SelectionLocatorTests {
    @Test func flipsPrimaryScreenRect() {
        // AX rect 100pt from the top of a 1000pt-tall primary screen.
        let flipped = SelectionLocator.flipped(CGRect(x: 50, y: 100, width: 200, height: 20), primaryHeight: 1000)
        #expect(flipped == NSRect(x: 50, y: 880, width: 200, height: 20))
    }

    @Test func flipsRectOnScreenAbovePrimary() {
        // A display above the primary has negative AX y; flipped result lands
        // above primaryHeight in AppKit coords.
        let flipped = SelectionLocator.flipped(CGRect(x: 0, y: -500, width: 100, height: 20), primaryHeight: 1000)
        #expect(flipped == NSRect(x: 0, y: 1480, width: 100, height: 20))
    }

    @Test func flipPreservesNegativeXForScreenLeftOfPrimary() {
        let flipped = SelectionLocator.flipped(CGRect(x: -800, y: 100, width: 100, height: 20), primaryHeight: 1000)
        #expect(flipped.minX == -800)
    }
}

struct ChipFrameTests {
    private let screen = NSRect(x: 0, y: 0, width: 1600, height: 1000)
    private let size = NSSize(width: 140, height: 36)

    @Test func offsetsFromPointer() {
        let frame = SuccessFlashController.chipFrame(near: NSPoint(x: 100, y: 100), size: size, in: screen)
        #expect(frame.origin == NSPoint(x: 112, y: 112))
    }

    @Test func clampsAtRightAndTopEdges() {
        let frame = SuccessFlashController.chipFrame(near: NSPoint(x: 1590, y: 990), size: size, in: screen)
        #expect(frame.maxX <= screen.maxX)
        #expect(frame.maxY <= screen.maxY)
    }

    @Test func clampsAtOrigin() {
        let frame = SuccessFlashController.chipFrame(near: NSPoint(x: -50, y: -50), size: size, in: screen)
        #expect(frame.minX >= screen.minX)
        #expect(frame.minY >= screen.minY)
    }
}
