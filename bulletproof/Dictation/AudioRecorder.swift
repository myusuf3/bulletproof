import AVFoundation
import Observation
import Synchronization

/// Recent input loudness for the waveform, oldest first, each in 0...1.
@MainActor @Observable
final class AudioLevelHistory {
    static let capacity = 44

    private(set) var levels = [Float](repeating: 0, count: capacity)

    func push(_ level: Float) {
        levels.removeFirst()
        levels.append(level)
    }

    func reset() {
        levels = [Float](repeating: 0, count: Self.capacity)
    }
}

nonisolated enum AudioLevel {
    /// One waveform bar per 20 ms of audio, whatever buffer size the
    /// hardware delivers.
    static let secondsPerLevel = 0.02

    private static let floorDB: Float = -50

    /// Maps RMS onto 0...1 across -50...0 dBFS: loudness is perceived
    /// logarithmically, and room tone below the floor reads as flat.
    static func normalized(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        return min(max((db - floorDB) / -floorDB, 0), 1)
    }

    static func rms(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        return (sum / Float(samples.count)).squareRoot()
    }
}

/// Accumulates captured audio as 16 kHz mono float, the format both speech
/// engines take. Fed from the audio render thread.
nonisolated final class SampleSink: @unchecked Sendable {
    static let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                            channels: 1, interleaved: false)!

    private struct State {
        var converter: AVAudioConverter?
        var samples: [Float] = []
    }

    private let state = Mutex(State())

    func append(_ buffer: AVAudioPCMBuffer) {
        state.withLock { state in
            if state.converter?.inputFormat != buffer.format {
                state.converter = AVAudioConverter(from: buffer.format, to: Self.targetFormat)
            }
            guard let converter = state.converter else { return }
            let ratio = Self.targetFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
            guard let output = AVAudioPCMBuffer(pcmFormat: Self.targetFormat, frameCapacity: capacity) else { return }
            var supplied = false
            converter.convert(to: output, error: nil) { _, status in
                if supplied {
                    status.pointee = .noDataNow
                    return nil
                }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            guard let channel = output.floatChannelData?[0] else { return }
            state.samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        }
    }

    func drain() -> [Float] {
        state.withLock { state in
            defer { state.samples = [] }
            return state.samples
        }
    }
}

/// Captures from the chosen microphone. A fresh AVAudioEngine per session
/// so a device change applies on the next start and the mic indicator is
/// lit only while recording.
@MainActor final class AudioRecorder {
    let levels = AudioLevelHistory()
    private var engine: AVAudioEngine?
    private var sink: SampleSink?

    var isRunning: Bool { engine != nil }

    /// keepSamples false is the mic test: levels only, no audio retained.
    func start(deviceUID: String?, keepSamples: Bool) throws {
        _ = stop()
        levels.reset()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if let deviceUID, var deviceID = AudioInputDevices.deviceID(forUID: deviceUID),
           let unit = input.audioUnit {
            // An unplugged pick falls through to the system default input.
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global,
                                 0, &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw DictationError.noMicrophone }

        let sink = keepSamples ? SampleSink() : nil
        input.installTap(onBus: 0, bufferSize: 1024, format: format,
                         block: Self.tap(sink: sink, levels: levels))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw DictationError.noMicrophone
        }
        self.engine = engine
        self.sink = sink
    }

    /// Returns everything captured since start, as 16 kHz mono.
    func stop() -> [Float] {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        defer { sink = nil }
        return sink?.drain() ?? []
    }

    /// Built outside the main actor: the block runs on the audio render
    /// thread, where a main-actor-isolated closure would trap.
    private nonisolated static func tap(sink: SampleSink?, levels: AudioLevelHistory) -> AVAudioNodeTapBlock {
        { buffer, _ in
            sink?.append(buffer)
            guard let channel = buffer.floatChannelData?[0] else { return }
            let chunk = max(1, Int(buffer.format.sampleRate * AudioLevel.secondsPerLevel))
            var bars: [Float] = []
            var start = 0
            while start < Int(buffer.frameLength) {
                let count = min(chunk, Int(buffer.frameLength) - start)
                bars.append(AudioLevel.normalized(rms: AudioLevel.rms(
                    UnsafeBufferPointer(start: channel + start, count: count))))
                start += chunk
            }
            Task { @MainActor in bars.forEach(levels.push) }
        }
    }
}
