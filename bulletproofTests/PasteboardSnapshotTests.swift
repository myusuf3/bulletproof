import AppKit
import Testing
@testable import bulletproof

@MainActor
struct PasteboardSnapshotTests {
    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("snapshot-test-\(UUID().uuidString)"))
    }

    @Test func roundTripsMultipleItemsAndTypes() {
        let pboard = makePasteboard()
        pboard.clearContents()
        let rich = NSPasteboardItem()
        rich.setString("hello", forType: .string)
        rich.setData(Data([0x01, 0x02, 0x03]), forType: NSPasteboard.PasteboardType("com.test.custom"))
        let plain = NSPasteboardItem()
        plain.setString("world", forType: .string)
        pboard.writeObjects([rich, plain])

        let snapshot = PasteboardSnapshot(pboard)
        pboard.clearContents()
        pboard.setString("overwritten by proofread", forType: .string)
        snapshot.restore(to: pboard)

        let items = pboard.pasteboardItems ?? []
        #expect(items.count == 2)
        #expect(items.first?.string(forType: .string) == "hello")
        #expect(items.first?.data(forType: NSPasteboard.PasteboardType("com.test.custom")) == Data([0x01, 0x02, 0x03]))
        #expect(items.last?.string(forType: .string) == "world")
    }

    @Test func restoresEmptyPasteboardAsEmpty() {
        let pboard = makePasteboard()
        pboard.clearContents()

        let snapshot = PasteboardSnapshot(pboard)
        pboard.setString("junk", forType: .string)
        snapshot.restore(to: pboard)

        #expect(pboard.pasteboardItems?.isEmpty ?? true)
    }

    @Test func failedSnapshotNeverWipesPasteboardOnRestore() {
        // pasteboardItems returns nil on a retrieval ERROR - that must not be
        // conflated with an empty clipboard, or restore destroys user data.
        let pboard = makePasteboard()
        pboard.clearContents()
        pboard.setString("precious clipboard data", forType: .string)

        PasteboardSnapshot(items: nil).restore(to: pboard)

        #expect(pboard.string(forType: .string) == "precious clipboard data")
    }
}
