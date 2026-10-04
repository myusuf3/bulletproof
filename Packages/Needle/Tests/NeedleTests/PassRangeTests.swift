import Testing
@testable import Needle

struct PassRangeTests {
    @Test func shortAudioIsOnePass() {
        let samples = [Float](repeating: 0.1, count: 1_000)
        #expect(SpeechEngine.passRanges(for: samples, maxSamples: 2_000) == [0..<1_000])
    }

    @Test func emptyAudioHasNoPasses() {
        #expect(SpeechEngine.passRanges(for: []).isEmpty)
    }

    @Test func longAudioCutsAtTheQuietestFrame() {
        // Loud everywhere except a silent gap at 1_700..<1_800.
        var samples = [Float](repeating: 0.5, count: 3_000)
        for i in 1_700..<1_800 { samples[i] = 0 }
        let ranges = SpeechEngine.passRanges(for: samples, maxSamples: 2_000,
                                             searchWindow: 500, frame: 100)
        #expect(ranges == [0..<1_750, 1_750..<3_000])
    }

    @Test func passesCoverEverySampleWithinTheLimit() {
        let samples = (0..<10_500).map { Float(($0 * 7919) % 101) / 101 }
        let ranges = SpeechEngine.passRanges(for: samples, maxSamples: 2_000,
                                             searchWindow: 600, frame: 100)
        #expect(ranges.first?.lowerBound == 0)
        #expect(ranges.last?.upperBound == samples.count)
        for (a, b) in zip(ranges, ranges.dropFirst()) { #expect(a.upperBound == b.lowerBound) }
        #expect(ranges.allSatisfy { $0.count <= 2_000 && !$0.isEmpty })
    }
}
