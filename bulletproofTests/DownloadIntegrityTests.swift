import Foundation
import Testing
@testable import bulletproof

struct DownloadIntegrityTests {
    private func tempFile(bytes: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("integrity-\(UUID().uuidString).bin")
        try Data(repeating: 0xAB, count: bytes).write(to: url)
        return url
    }

    @Test func matchingSizePasses() throws {
        let url = try tempFile(bytes: 1024)
        #expect(DownloadIntegrity.sizeMismatch(at: url, expected: 1024) == nil)
    }

    @Test func truncatedFileIsReported() throws {
        // A transfer that ends cleanly early (HTTP/2 reset, proxy close)
        // returns 200 with fewer bytes - the case an HTTP status check misses.
        let url = try tempFile(bytes: 700)
        let message = DownloadIntegrity.sizeMismatch(at: url, expected: 1024)
        #expect(message?.contains("700") == true)
        #expect(message?.contains("1024") == true)
    }

    @Test func unknownExpectedSizeIsNotChecked() throws {
        let url = try tempFile(bytes: 3)
        #expect(DownloadIntegrity.sizeMismatch(at: url, expected: nil) == nil)
    }

    @Test func missingFileIsReported() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("never-written-\(UUID().uuidString).bin")
        #expect(DownloadIntegrity.sizeMismatch(at: url, expected: 10) != nil)
    }
}
