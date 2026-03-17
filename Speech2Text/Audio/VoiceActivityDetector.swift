import Accelerate
import AVFoundation
import Foundation

final class VoiceActivityDetector: AudioBufferReceiving {
    private let destination: AudioBufferAccumulator
    private let silenceThresholdDB: Float
    private let preRollDuration: TimeInterval
    private let trailingSilenceDuration: TimeInterval
    private let dateProvider: () -> Date
    
    private var isSpeechDetected = false
    private var lastSpeechTime: Date?
    
    // Ring buffer configuration
    private var preRollBuffers: [AVAudioPCMBuffer] = []
    private var currentPreRollDuration: TimeInterval = 0
    private let lock = NSLock()
    
    init(
        destination: AudioBufferAccumulator,
        silenceThresholdDB: Float = -45.0,
        preRollDuration: TimeInterval = 0.5,
        trailingSilenceDuration: TimeInterval = 0.5,
        dateProvider: @escaping () -> Date = { Date() }
    ) {
        self.destination = destination
        self.silenceThresholdDB = silenceThresholdDB
        self.preRollDuration = preRollDuration
        self.trailingSilenceDuration = trailingSilenceDuration
        self.dateProvider = dateProvider
    }
    
    nonisolated func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        
        let db = calculateRMS(buffer: buffer)
        let isSpeechRegion = db >= silenceThresholdDB
        
        if isSpeechRegion {
            if !isSpeechDetected {
                // Speech just started, emit all pre-roll buffers first
                for preRollBuffer in preRollBuffers {
                    destination.append(preRollBuffer)
                }
                preRollBuffers.removeAll()
                currentPreRollDuration = 0
                isSpeechDetected = true
            }
            lastSpeechTime = dateProvider()
            destination.append(buffer)
        } else {
            if isSpeechDetected {
                // We were in a speech region, but now it's quiet.
                // Check if we've exceeded the trailing silence duration.
                if let lastSpeech = lastSpeechTime {
                    let silenceDuration = dateProvider().timeIntervalSince(lastSpeech)
                    if silenceDuration < trailingSilenceDuration {
                        // Still within trailing silence window, keep appending
                        destination.append(buffer)
                    } else {
                        // Trailing silence exceeded, stop emitting and reset
                        isSpeechDetected = false
                        lastSpeechTime = nil
                        
                        // We transition back to building the pre-roll buffer,
                        // this buffer is technically the first one in the new silence block,
                        // so add it to the pre-roll if needed (though it might just get replaced soon)
                        addPreRoll(buffer)
                    }
                } else {
                    // fallback shouldn't happen, but just in case
                    destination.append(buffer)
                }
            } else {
                // Not in speech region, just keep maintaining the pre-roll buffer
                addPreRoll(buffer)
            }
        }
    }
    
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        preRollBuffers.removeAll()
        currentPreRollDuration = 0
        isSpeechDetected = false
        lastSpeechTime = nil
        destination.reset()
    }
    
    private func addPreRoll(_ buffer: AVAudioPCMBuffer) {
        // Compute duration of this buffer
        let format = buffer.format
        guard format.sampleRate > 0 else { return }
        
        let bufferDuration = TimeInterval(buffer.frameLength) / format.sampleRate
        
        // Add to ring buffer
        if let copy = deepCopy(buffer) {
            preRollBuffers.append(copy)
            currentPreRollDuration += bufferDuration
        }
        
        // Remove oldest buffers until we are within preRollDuration
        while currentPreRollDuration > preRollDuration, !preRollBuffers.isEmpty {
            let oldest = preRollBuffers.removeFirst()
            let oldestDuration = TimeInterval(oldest.frameLength) / format.sampleRate
            currentPreRollDuration -= oldestDuration
            
            // Adjust for float precision drift in simple subtraction
            if currentPreRollDuration < 0 {
                currentPreRollDuration = 0
            }
        }
    }
    
    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0, let samples = buffer.floatChannelData?[0] else {
            return -80.0
        }
        
        var rms: Float = 0.0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(frameLength))
        
        let minDB: Float = -80
        let db = rms > 0 ? 20 * log10(rms) : minDB
        return max(minDB, db)
    }
    
    private func deepCopy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
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
