import AVFAudio
import Foundation
import Needle
import Speech

nonisolated enum SpeechModelChoice: String, Codable, CaseIterable, Sendable {
    case appleSpeech, whistle

    var displayName: String {
        switch self {
        case .appleSpeech: "Apple Speech"
        case .whistle: ModelCatalog.whistle.displayName
        }
    }
}

nonisolated enum DictationError: LocalizedError, Equatable {
    case microphoneDenied
    case noMicrophone
    case modelNotInstalled
    case speechUnavailable(String)
    case accessibilityNeeded

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "bulletproof can't hear you. Allow microphone access in System Settings > Privacy & Security > Microphone."
        case .noMicrophone:
            "No microphone is available. Connect one or pick another in Settings > Dictation."
        case .modelNotInstalled:
            "Whistle isn't downloaded yet. Download it in Settings > Dictation, or switch to Apple Speech."
        case .speechUnavailable(let reason):
            reason
        case .accessibilityNeeded:
            "Grant bulletproof access in System Settings > Privacy & Security > Accessibility so it can type for you."
        }
    }
}

/// Turns a finished recording (16 kHz mono float) into text.
nonisolated protocol SpeechToTextEngine: Sendable {
    func transcribe(_ samples: [Float]) async throws -> String
    /// Loads the model while the user is still talking. Failures stay
    /// silent here and surface on the real request.
    func prewarm() async
}

nonisolated struct WhistleSpeechEngine: SpeechToTextEngine {
    let modelFile: URL

    func prewarm() async {
        try? await SpeechEngine.shared.load(contentsOf: modelFile)
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard FileManager.default.fileExists(atPath: modelFile.path) else {
            throw DictationError.modelNotInstalled
        }
        try await SpeechEngine.shared.load(contentsOf: modelFile)
        return try await SpeechEngine.shared.transcribe(samples).text
    }
}

/// macOS's on-device SpeechAnalyzer. Language assets are shared system-wide
/// and fetched by macOS on first use; nothing lands in bulletproof's storage.
nonisolated struct AppleSpeechEngine: SpeechToTextEngine {
    var locale: Locale = .current

    func prewarm() async {
        _ = try? await readyTranscriber()
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard !samples.isEmpty else { return "" }
        let transcriber = try await readyTranscriber()
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw DictationError.speechUnavailable("Apple Speech can't process audio on this Mac.")
        }
        let buffer = try Self.buffer(samples, as: format)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collected = Task {
            try await transcriber.results.reduce(into: "") { $0 += String($1.text.characters) }
        }
        let (input, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        continuation.yield(AnalyzerInput(buffer: buffer))
        continuation.finish()
        if let end = try await analyzer.analyzeSequence(input) {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await collected.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func readyTranscriber() async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable else {
            throw DictationError.speechUnavailable("Apple Speech isn't available on this Mac. Download Whistle in Settings > Dictation instead.")
        }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw DictationError.speechUnavailable("Apple Speech doesn't support \(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier). Try Whistle in Settings > Dictation.")
        }
        let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        return transcriber
    }

    private static func buffer(_ samples: [Float], as format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let source = SampleSink.targetFormat
        guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(samples.count)),
              let converter = AVAudioConverter(from: source, to: format) else {
            throw DictationError.speechUnavailable("Couldn't prepare the recording for Apple Speech.")
        }
        input.frameLength = input.frameCapacity
        samples.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        let ratio = format.sampleRate / source.sampleRate
        let capacity = AVAudioFrameCount((Double(samples.count) * ratio).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw DictationError.speechUnavailable("Couldn't prepare the recording for Apple Speech.")
        }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .endOfStream
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return input
        }
        if let error { throw error }
        return output
    }
}
