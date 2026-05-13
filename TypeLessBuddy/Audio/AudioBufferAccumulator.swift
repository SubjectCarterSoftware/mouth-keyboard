import AVFoundation
import Foundation

enum AudioBufferAccumulatorError: Error {
    case emptyBuffers
    case conversionFailed
    case overflow
}

private let whisperSampleRate: Double = 16_000.0
private let defaultAccumulatorMaxDuration: TimeInterval = 5 * 60
private let trimmingWindowDuration: TimeInterval = 0.1
private let trimmingPreRollDuration: TimeInterval = 0.3
private let speechThresholdRMS: Float = 0.0056

class AudioBufferAccumulator: AudioBufferReceiving {
    private var buffers: [AVAudioPCMBuffer] = []
    private var inputFormat: AVAudioFormat?
    private let lock = NSLock()
    private let maximumDuration: TimeInterval
    private var maximumFrameCount: AVAudioFrameCount?
    private var accumulatedFrameCount: AVAudioFrameCount = 0
    private var overflowed = false

    init(maxDuration: TimeInterval = defaultAccumulatorMaxDuration) {
        self.maximumDuration = maxDuration
    }

    // MARK: - Public Interface

    nonisolated func append(_ buffer: AVAudioPCMBuffer) {
        let storedBuffer = Self.deepCopy(buffer) ?? buffer

        lock.lock()
        defer { lock.unlock() }
        if overflowed {
            return
        }
        if inputFormat == nil {
            inputFormat = storedBuffer.format
            if storedBuffer.format.sampleRate > 0 {
                maximumFrameCount = AVAudioFrameCount(maximumDuration * storedBuffer.format.sampleRate)
            }
        }

        let frameLength = storedBuffer.frameLength
        if let maxFrameCount = maximumFrameCount, accumulatedFrameCount + frameLength > maxFrameCount {
            overflowed = true
            return
        }

        buffers.append(storedBuffer)
        accumulatedFrameCount += frameLength
    }

    var totalFrameCount: AVAudioFrameCount {
        lock.lock()
        defer { lock.unlock() }
        return accumulatedFrameCount
    }

    /// Total duration of accumulated audio in seconds.
    var duration: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        guard let format = inputFormat, format.sampleRate > 0 else { return 0 }
        return Double(buffers.reduce(0) { $0 + $1.frameLength }) / format.sampleRate
    }

    func convertToWhisperFormat() throws -> [Float] {
        lock.lock()
        let isOverflowed = overflowed
        lock.unlock()
        if isOverflowed {
            throw AudioBufferAccumulatorError.overflow
        }
        let snapshot = try snapshot()
        return try Self.convertToWhisperFormat(buffers: snapshot.buffers, format: snapshot.format)
    }

    static func prepareForTranscription(
        _ samples: [Float],
        minimumDuration: TimeInterval,
        trailingSilenceDuration: TimeInterval
    ) -> [Float] {
        guard !samples.isEmpty else {
            return samples
        }

        let minimumSampleCount = max(0, Int(ceil(minimumDuration * whisperSampleRate)))
        let trailingSilenceSampleCount = max(0, Int(ceil(trailingSilenceDuration * whisperSampleRate)))
        let trimmed = trimBoundarySilence(from: samples)

        var prepared = trimmed
        prepared.reserveCapacity(max(trimmed.count + trailingSilenceSampleCount, minimumSampleCount))

        if trailingSilenceSampleCount > 0 {
            prepared.append(contentsOf: repeatElement(0, count: trailingSilenceSampleCount))
        }

        if prepared.count < minimumSampleCount {
            prepared.append(contentsOf: repeatElement(0, count: minimumSampleCount - prepared.count))
        }

        return prepared
    }

    private static func trimBoundarySilence(from samples: [Float]) -> [Float] {
        let windowSampleCount = max(1, Int(ceil(trimmingWindowDuration * whisperSampleRate)))
        let preRollSampleCount = max(0, Int(ceil(trimmingPreRollDuration * whisperSampleRate)))

        guard let firstSpeechRange = firstSpeechWindow(in: samples, windowSampleCount: windowSampleCount),
              let lastSpeechRange = lastSpeechWindow(in: samples, windowSampleCount: windowSampleCount) else {
            return samples
        }

        let startIndex = max(0, firstSpeechRange.lowerBound - preRollSampleCount)
        let endIndex = max(startIndex, lastSpeechRange.upperBound)
        return Array(samples[startIndex..<endIndex])
    }

    private static func firstSpeechWindow(in samples: [Float], windowSampleCount: Int) -> Range<Int>? {
        var lowerBound = 0
        while lowerBound < samples.count {
            let upperBound = min(samples.count, lowerBound + windowSampleCount)
            if rms(of: samples[lowerBound..<upperBound]) > speechThresholdRMS {
                return lowerBound..<upperBound
            }
            lowerBound += windowSampleCount
        }
        return nil
    }

    private static func lastSpeechWindow(in samples: [Float], windowSampleCount: Int) -> Range<Int>? {
        var lowerBound = max(0, samples.count - windowSampleCount)
        while true {
            let upperBound = min(samples.count, lowerBound + windowSampleCount)
            if rms(of: samples[lowerBound..<upperBound]) > speechThresholdRMS {
                return lowerBound..<upperBound
            }
            if lowerBound == 0 {
                return nil
            }
            lowerBound = max(0, lowerBound - windowSampleCount)
        }
    }

    private static func rms(of samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        let meanSquare = samples.reduce(into: Float.zero) { partialResult, sample in
            partialResult += sample * sample
        } / Float(samples.count)
        return sqrt(meanSquare)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        buffers.removeAll()
        inputFormat = nil
        accumulatedFrameCount = 0
        maximumFrameCount = nil
        overflowed = false
    }

    private func snapshot() throws -> (buffers: [AVAudioPCMBuffer], format: AVAudioFormat, totalFrameCount: AVAudioFrameCount) {
        lock.lock()
        let localBuffers = buffers
        let localFormat = inputFormat
        let totalFrames = accumulatedFrameCount
        lock.unlock()

        guard !localBuffers.isEmpty, let format = localFormat else {
            throw AudioBufferAccumulatorError.emptyBuffers
        }

        return (
            buffers: localBuffers,
            format: format,
            totalFrameCount: totalFrames
        )
    }

    private static func convertToWhisperFormat(buffers: [AVAudioPCMBuffer], format: AVAudioFormat) throws -> [Float] {
        guard !buffers.isEmpty else {
            throw AudioBufferAccumulatorError.emptyBuffers
        }

        if format.sampleRate == whisperSampleRate,
           format.channelCount == 1,
           format.commonFormat == .pcmFormatFloat32,
           !format.isInterleaved {
            let totalFrames = buffers.reduce(0) { $0 + Int($1.frameLength) }
            var samples: [Float] = []
            samples.reserveCapacity(totalFrames)

            for buffer in buffers {
                guard let channelData = buffer.floatChannelData else {
                    throw AudioBufferAccumulatorError.conversionFailed
                }
                samples.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
            }

            return samples
        }

        let totalFrames = buffers.reduce(0) { $0 + $1.frameLength }
        guard let combined = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            throw AudioBufferAccumulatorError.conversionFailed
        }
        combined.frameLength = totalFrames

        var offset: AVAudioFrameCount = 0
        for buffer in buffers {
            let frameLength = buffer.frameLength
            guard frameLength > 0 else { continue }
            guard let srcData = buffer.floatChannelData, let dstData = combined.floatChannelData else {
                throw AudioBufferAccumulatorError.conversionFailed
            }

            for channel in 0..<Int(format.channelCount) {
                let src = srcData[channel]
                let dst = dstData[channel].advanced(by: Int(offset))
                dst.update(from: src, count: Int(frameLength))
            }
            offset += frameLength
        }

        let whisperFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: whisperSampleRate,
            channels: 1,
            interleaved: false
        )!

        guard let converter = AVAudioConverter(from: format, to: whisperFormat) else {
            throw AudioBufferAccumulatorError.conversionFailed
        }

        let ratio = whisperFormat.sampleRate / format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(totalFrames) * ratio + 1)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: whisperFormat, frameCapacity: outputFrameCapacity) else {
            throw AudioBufferAccumulatorError.conversionFailed
        }

        var conversionError: NSError?
        var inputConsumed = false

        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }

            outStatus.pointee = .haveData
            inputConsumed = true
            return combined
        }

        if let error = conversionError {
            throw error
        }
        guard status != .error, let channelData = outputBuffer.floatChannelData else {
            throw AudioBufferAccumulatorError.conversionFailed
        }

        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
    }

    private static func deepCopy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }

        copy.frameLength = buffer.frameLength
        guard let sourceChannels = buffer.floatChannelData, let destinationChannels = copy.floatChannelData else {
            return nil
        }

        for channel in 0..<Int(buffer.format.channelCount) {
            destinationChannels[channel].update(from: sourceChannels[channel], count: Int(buffer.frameLength))
        }

        return copy
    }
}
