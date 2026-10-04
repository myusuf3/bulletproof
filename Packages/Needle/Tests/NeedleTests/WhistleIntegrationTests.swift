import AVFAudio
import Foundation
import Testing
@testable import Needle

/// Runs the real engine end to end. Needs a downloaded whistle.cact:
/// WHISTLE_MODEL=/path/to/whistle.cact swift test
struct WhistleIntegrationTests {
    private static let modelPath = ProcessInfo.processInfo.environment["WHISTLE_MODEL"]

    @Test(.enabled(if: modelPath != nil, "set WHISTLE_MODEL to a whistle.cact"))
    func transcribesSpokenEnglish() async throws {
        try await SpeechEngine.shared.load(contentsOf: URL(fileURLWithPath: Self.modelPath!))
        let samples = try Self.speak("Turn off the kitchen lights and send the report tomorrow morning.")
        let result = try await SpeechEngine.shared.transcribe(samples)
        #expect(result.language == "en")
        #expect(result.text.lowercased().contains("kitchen lights"))
    }

    @Test(.enabled(if: modelPath != nil, "set WHISTLE_MODEL to a whistle.cact"))
    func silenceTranscribesToNothing() async throws {
        try await SpeechEngine.shared.load(contentsOf: URL(fileURLWithPath: Self.modelPath!))
        let result = try await SpeechEngine.shared.transcribe([Float](repeating: 0, count: SpeechEngine.sampleRate * 2))
        #expect(result.text.isEmpty)
    }

    /// Synthesizes speech with macOS `say` as 16 kHz mono samples. The voice
    /// is explicit: the system default may be a Siri voice, which `say -o`
    /// renders as silence.
    private static func speak(_ text: String) throws -> [Float] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", "Samantha", "-o", url.path, "--file-format=WAVE", "--data-format=LEF32@16000", text]
        try say.run()
        say.waitUntilExit()
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                   frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try #require(buffer.floatChannelData?[0])
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }
}
