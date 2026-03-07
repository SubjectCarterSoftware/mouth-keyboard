import AVFoundation

enum AudioBufferAccumulatorError: Error {
    case emptyBuffers
    case conversionFailed
}

class AudioBufferAccumulator {
    private var buffers: [AVAudioPCMBuffer] = []
    private var inputFormat: AVAudioFormat?
    private let lock = NSLock()

    // MARK: - Public Interface

    nonisolated func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        if inputFormat == nil {
            inputFormat = buffer.format
        }
        buffers.append(buffer)
    }

    var totalFrameCount: AVAudioFrameCount {
        lock.lock()
        defer { lock.unlock() }
        return buffers.reduce(0) { $0 + $1.frameLength }
    }

    func convertToWhisperFormat() throws -> [Float] {
        lock.lock()
        let localBuffers = buffers
        let localFormat = inputFormat
        lock.unlock()

        guard !localBuffers.isEmpty, let format = localFormat else {
            throw AudioBufferAccumulatorError.emptyBuffers
        }

        // Combine all buffers into one
        let totalFrames = localBuffers.reduce(0) { $0 + $1.frameLength }
        guard let combined = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            throw AudioBufferAccumulatorError.conversionFailed
        }
        combined.frameLength = totalFrames

        var offset: AVAudioFrameCount = 0
        for buf in localBuffers {
            let frameLength = buf.frameLength
            guard frameLength > 0 else { continue }
            if let srcData = buf.floatChannelData, let dstData = combined.floatChannelData {
                let channelCount = Int(format.channelCount)
                for ch in 0..<channelCount {
                    let src = srcData[ch]
                    let dst = dstData[ch].advanced(by: Int(offset))
                    dst.assign(from: src, count: Int(frameLength))
                }
            }
            offset += frameLength
        }

        // Convert to 16kHz mono Float32
        let whisperFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
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
        guard status != .error else {
            throw AudioBufferAccumulatorError.conversionFailed
        }

        let frameCount = Int(outputBuffer.frameLength)
        guard let channelData = outputBuffer.floatChannelData else {
            throw AudioBufferAccumulatorError.conversionFailed
        }
        return Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        buffers.removeAll()
        inputFormat = nil
    }
}
