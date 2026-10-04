import AVFAudio
import Testing
@testable import bulletproof

struct AudioLevelTests {
    @Test func silenceIsFlatAndFullScaleIsFull() {
        #expect(AudioLevel.normalized(rms: 0) == 0)
        #expect(AudioLevel.normalized(rms: 1) == 1)
        #expect(AudioLevel.normalized(rms: 2) == 1)
    }

    @Test func roomToneBelowTheFloorReadsAsFlat() {
        // -60 dBFS is below the -50 dB floor.
        #expect(AudioLevel.normalized(rms: 0.001) == 0)
    }

    @Test func levelsScaleWithDecibelsNotAmplitude() {
        // -25 dBFS is halfway between the floor and full scale.
        let halfway = AudioLevel.normalized(rms: pow(10, -25 / 20))
        #expect(abs(halfway - 0.5) < 0.001)
    }

    @Test func rmsOfASquareWaveIsItsAmplitude() {
        let samples: [Float] = [0.5, -0.5, 0.5, -0.5]
        let rms = samples.withUnsafeBufferPointer(AudioLevel.rms)
        #expect(abs(rms - 0.5) < 0.0001)
    }

    @Test func waveformPutsTheNewestLevelInTheCenter() {
        let bars = WaveformView.bars(from: [0.1, 0.2, 0.3, 0.4, 0.5, 1.0], count: 100)
        #expect(bars.count == 6)
        // Mirrored around the middle, newest (1.0) innermost, untapered.
        #expect(bars[2] == 1.0 && bars[3] == 1.0)
        #expect(bars == Array(bars.reversed()))
        // Older readings taper toward the edges.
        #expect(bars[0] < 0.4)
    }

    @Test func waveformOfNothingIsEmpty() {
        #expect(WaveformView.bars(from: [], count: 10).isEmpty)
        #expect(WaveformView.bars(from: [0.5, 0.5], count: 0).isEmpty)
    }

    @Test func waveformNeverHasMoreBarsThanFit() {
        let history = [Float](repeating: 0.5, count: 44)
        #expect(WaveformView.bars(from: history, count: 20).count == 20)
        #expect(WaveformView.bars(from: history, count: 21).count == 20)
        #expect(WaveformView.bars(from: history, count: 500).count == 44)
    }

    @Test func sinkResamplesToSixteenKilohertzMono() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
        buffer.frameLength = 4_800
        let sink = SampleSink()
        for _ in 0..<10 { sink.append(buffer) }  // one second
        let samples = sink.drain()
        // The resampler holds back a few milliseconds of filter latency.
        #expect(abs(samples.count - 16_000) < 400)
        #expect(sink.drain().isEmpty)
    }

    @MainActor @Test func historyKeepsAFixedWindowOldestFirst() {
        let history = AudioLevelHistory()
        history.push(0.7)
        history.push(0.9)
        #expect(history.levels.count == AudioLevelHistory.capacity)
        #expect(history.levels.suffix(2) == [0.7, 0.9])
        history.reset()
        #expect(history.levels.allSatisfy { $0 == 0 })
    }

    @Test func overlaySitsBottomCenterAboveTheDock() {
        let visible = NSRect(x: 0, y: 80, width: 1440, height: 800)
        let frame = DictationOverlayController.frame(on: visible)
        #expect(frame.midX == visible.midX)
        #expect(frame.minY > visible.minY)
        #expect(frame.maxY < visible.midY)
    }

    @Test func defaultDictationShortcutIsValidAndDistinct() {
        #expect(KeyComboValidator.validate(.dictationDefault) == .ok)
        #expect(KeyCombo.dictationDefault != .default)
        #expect(KeyCombo.dictationDefault.displayString == "⌥Space")
    }
}
