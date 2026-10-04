import CNeedle
import Foundation

public struct Transcription: Decodable, Sendable, Equatable {
    public let text: String
    /// ISO 639-1 code the engine used; empty when the clip held no speech.
    public let language: String

    public init(text: String, language: String) {
        self.text = text
        self.language = language
    }
}

public struct NeedleError: Error, LocalizedError, Equatable {
    public let message: String
    public var errorDescription: String? { message }
}

/// Swift face of Cactus's Needle engine for speech (Whistle). The C engine
/// holds one process-global, non-thread-safe model per kind, so the engine
/// is a singleton actor: every call is serialized through it.
public actor SpeechEngine {
    public static let shared = SpeechEngine()

    /// Whistle takes 16 kHz mono float PCM in [-1, 1].
    public static let sampleRate = 16_000
    /// The engine transcribes at most 30 s per pass.
    public static let maxSamplesPerPass = 30 * sampleRate

    private var loadedURL: URL?
    /// needle_load documents no ownership of the bytes it is handed, so the
    /// blob stays alive for as long as the engine may read it.
    private var loadedBlob: Data?

    public func load(contentsOf url: URL) throws {
        guard loadedURL != url else { return }
        let blob = try Data(contentsOf: url)
        let status = blob.withUnsafeBytes { raw in
            needle_load(raw.bindMemory(to: UInt8.self).baseAddress, UInt64(raw.count))
        }
        guard status >= 0 else { throw Self.lastError(fallback: "Couldn't load \(url.lastPathComponent).") }
        guard needle_models() & NEEDLE_SPEECH != 0 else {
            throw NeedleError(message: "\(url.lastPathComponent) is not a speech model.")
        }
        loadedBlob = blob
        loadedURL = url
    }

    /// Transcribes 16 kHz mono samples of any length, splitting anything
    /// longer than one pass at its quietest moments.
    public func transcribe(_ samples: [Float], language: String? = nil) throws -> Transcription {
        guard loadedURL != nil else { throw NeedleError(message: "No speech model is loaded.") }
        var texts: [String] = []
        var detected = ""
        for range in Self.passRanges(for: samples) {
            let pass = try transcribePass(Array(samples[range]), language: language)
            if !pass.text.isEmpty { texts.append(pass.text) }
            if detected.isEmpty { detected = pass.language }
        }
        return Transcription(text: texts.joined(separator: " "), language: detected)
    }

    private func transcribePass(_ samples: [Float], language: String?) throws -> Transcription {
        var out = [CChar](repeating: 0, count: 64 * 1024)
        let capacity = Int32(out.count)
        let status = samples.withUnsafeBufferPointer { pcm in
            needle_transcribe(pcm.baseAddress, Int32(pcm.count), language, nil, 0, &out, capacity)
        }
        guard status >= 0 else { throw Self.lastError(fallback: "Transcription failed.") }
        let json = out.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        do {
            return try JSONDecoder().decode(Transcription.self, from: Data(json.utf8))
        } catch {
            throw NeedleError(message: "The speech engine returned unreadable output.")
        }
    }

    private static func lastError(fallback: String) -> NeedleError {
        guard let cString = needle_last_error() else { return NeedleError(message: fallback) }
        let message = String(cString: cString)
        return NeedleError(message: message.isEmpty ? fallback : message)
    }

    /// Splits audio into passes of at most maxSamplesPerPass, cutting each
    /// at the quietest 50 ms frame in its last five seconds so a pass
    /// boundary rarely lands mid-word.
    static func passRanges(for samples: [Float],
                           maxSamples: Int = maxSamplesPerPass,
                           searchWindow: Int = 5 * sampleRate,
                           frame: Int = sampleRate / 20) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start = 0
        while samples.count - start > maxSamples {
            let hardEnd = start + maxSamples
            var cut = hardEnd
            var quietest = Float.infinity
            var frameStart = max(start + frame, hardEnd - searchWindow)
            while frameStart + frame <= hardEnd {
                var energy: Float = 0
                for sample in samples[frameStart..<(frameStart + frame)] { energy += sample * sample }
                if energy < quietest {
                    quietest = energy
                    cut = frameStart + frame / 2
                }
                frameStart += frame
            }
            ranges.append(start..<cut)
            start = cut
        }
        if start < samples.count { ranges.append(start..<samples.count) }
        return ranges
    }
}
