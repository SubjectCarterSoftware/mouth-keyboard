import AVFoundation
import Foundation

enum AudioBufferAccumulatorError: Error {
    case emptyBuffers
    case conversionFailed
}

private let whisperSampleRate: Double = 16_000.0

class AudioBufferAccumulator {
    private var buffers: [AVAudioPCMBuffer] = []
    private var inputFormat: AVAudioFormat?
    private let lock = NSLock()

    // MARK: - Public Interface

    nonisolated func append(_ buffer: AVAudioPCMBuffer) {
        let storedBuffer = Self.deepCopy(buffer) ?? buffer

        lock.lock()
        defer { lock.unlock() }
        if inputFormat == nil {
            inputFormat = storedBuffer.format
        }
        buffers.append(storedBuffer)
    }

    var totalFrameCount: AVAudioFrameCount {
        lock.lock()
        defer { lock.unlock() }
        return buffers.reduce(0) { $0 + $1.frameLength }
    }

    /// Total duration of accumulated audio in seconds.
    var duration: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        guard let format = inputFormat, format.sampleRate > 0 else { return 0 }
        return Double(buffers.reduce(0) { $0 + $1.frameLength }) / format.sampleRate
    }

    func convertToWhisperFormat() throws -> [Float] {
        let snapshot = try snapshot()
        return try Self.convertToWhisperFormat(buffers: snapshot.buffers, format: snapshot.format)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        buffers.removeAll()
        inputFormat = nil
    }

    private func snapshot() throws -> (buffers: [AVAudioPCMBuffer], format: AVAudioFormat, totalFrameCount: AVAudioFrameCount) {
        lock.lock()
        let localBuffers = buffers
        let localFormat = inputFormat
        lock.unlock()

        guard !localBuffers.isEmpty, let format = localFormat else {
            throw AudioBufferAccumulatorError.emptyBuffers
        }

        return (
            buffers: localBuffers,
            format: format,
            totalFrameCount: localBuffers.reduce(0) { $0 + $1.frameLength }
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
