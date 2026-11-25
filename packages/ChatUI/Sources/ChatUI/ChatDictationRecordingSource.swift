import Foundation
import AVFoundation
import Accelerate
import SwiftSignalKit
import OpusBinding
import TelegramMedia
import MediaRecorderUI

final class ChatDictationRecordingSource {
    private static let sampleRate: Double = 48000
    private static let readCapacity = 4800

    let inputFormat: AVAudioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: ChatDictationRecordingSource.sampleRate, channels: 1, interleaved: false)!
    var onLevel: ((CGFloat) -> Void)?
    var onEnded: (() -> Void)?

    private let audio: ChatVoiceTranscription.Audio
    private let recordingStartSample: Int
    private let queue = Queue(name: "ChatDictationRecordingSource")
    private let disposable = MetaDisposable()

    private var consume: ((AVAudioPCMBuffer) -> Void)?
    private var snapshotFed = false
    private var pending: [Data] = []
    private var finishing: (() -> Void)?
    private var stopped = false

    init(audio: ChatVoiceTranscription.Audio, recordingStartTime: Double = 0) {
        self.audio = audio
        self.recordingStartSample = Int((max(0, recordingStartTime) * ChatDictationRecordingSource.sampleRate).rounded())
    }

    deinit {
        disposable.dispose()
    }

    func start(_ consume: @escaping (AVAudioPCMBuffer) -> Void) {
        let queue = self.queue
        switch audio {
        case let .recording(recorder):
            queue.async {
                self.consume = consume
            }
            let tap: (Data) -> Void = { [weak self] data in
                queue.async {
                    self?.receive(data)
                }
            }
            disposable.set((recorder.beginPCMTap(tap) |> deliverOn(queue)).start(next: { [weak self] snapshot in
                guard let self else {
                    return
                }
                self.feed(snapshot: snapshot, trimRange: self.recordingStartSample > 0 ? self.recordingStartSample ..< Int.max : nil)
            }))
        case let .clip(clip, trimRange):
            let samples = trimRange.map { Int(($0.lowerBound * ChatDictationRecordingSource.sampleRate).rounded()) ..< Int(($0.upperBound * ChatDictationRecordingSource.sampleRate).rounded()) }
            queue.async {
                self.consume = consume
                self.feed(snapshot: clip, trimRange: samples)
                if !self.stopped {
                    DispatchQueue.main.async { [weak self] in
                        self?.onEnded?()
                    }
                }
            }
        }
    }

    func finish(_ completion: @escaping () -> Void) {
        queue.async {
            if self.snapshotFed || self.stopped {
                self.close()
                DispatchQueue.main.async(execute: completion)
            } else {
                self.finishing = completion
            }
        }
    }

    func stop() {
        queue.async {
            self.close()
            self.finishing = nil
        }
        disposable.set(nil)
    }

    private func close() {
        guard !stopped else {
            return
        }
        stopped = true
        consume = nil
        pending = []
        if case let .recording(recorder) = audio {
            recorder.endPCMTap()
        }
    }

    private func receive(_ data: Data) {
        guard !stopped else {
            return
        }
        if snapshotFed {
            emitLive(data)
        } else {
            pending.append(data)
        }
    }

    private func feed(snapshot: Data?, trimRange: Range<Int>?) {
        guard !stopped else {
            return
        }
        if let snapshot, !snapshot.isEmpty {
            decode(snapshot, trimRange: trimRange)
        }
        snapshotFed = true
        let pending = self.pending
        self.pending = []
        for data in pending {
            emitLive(data)
        }
        if let finishing {
            self.finishing = nil
            close()
            DispatchQueue.main.async(execute: finishing)
        }
    }

    private func decode(_ snapshot: Data, trimRange: Range<Int>?) {
        let path = temporaryMediaPath("transcription", "ogg")
        let url = URL(fileURLWithPath: path)
        guard (try? snapshot.write(to: url)) != nil else {
            return
        }
        defer {
            try? FileManager.default.removeItem(at: url)
        }
        guard let reader = OggOpusReader(path: path) else {
            return
        }
        let capacity = ChatDictationRecordingSource.readCapacity
        let samples = UnsafeMutablePointer<Int16>.allocate(capacity: capacity)
        defer {
            samples.deallocate()
        }
        var position = 0
        while !stopped {
            let count = Int(reader.read(UnsafeMutableRawPointer(samples), bufSize: Int32(capacity)))
            if count <= 0 || count > capacity {
                break
            }
            var lower = 0
            var upper = count
            if let trimRange {
                lower = max(0, trimRange.lowerBound - position)
                upper = min(count, trimRange.upperBound - position)
            }
            if lower < upper, let buffer = makeBuffer(samples.advanced(by: lower), count: upper - lower) {
                consume?(buffer)
            }
            position += count
            if let trimRange, position >= trimRange.upperBound {
                break
            }
        }
    }

    private func emitLive(_ data: Data) {
        let count = data.count / MemoryLayout<Int16>.size
        let buffer: AVAudioPCMBuffer? = data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else {
                return nil
            }
            return makeBuffer(base.assumingMemoryBound(to: Int16.self), count: count)
        }
        guard let buffer else {
            return
        }
        consume?(buffer)
        let level = ChatDictationRecordingSource.level(of: buffer)
        DispatchQueue.main.async { [weak self] in
            self?.onLevel?(level)
        }
    }

    private func makeBuffer(_ samples: UnsafePointer<Int16>, count: Int) -> AVAudioPCMBuffer? {
        guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(count)), let channel = buffer.floatChannelData?[0] else {
            return nil
        }
        var scale: Float = 1 / 32768
        vDSP_vflt16(samples, 1, channel, 1, vDSP_Length(count))
        vDSP_vsmul(channel, 1, &scale, channel, 1, vDSP_Length(count))
        buffer.frameLength = AVAudioFrameCount(count)
        return buffer
    }

    private static func level(of buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else {
            return 0
        }
        var rms: Float = 0
        vDSP_rmsqv(channel, 1, &rms, vDSP_Length(buffer.frameLength))
        guard rms > 0 else {
            return 0
        }
        let decibels = 20 * log10(rms)
        let floor: Float = -50
        return CGFloat(max(0, min(1, (decibels - floor) / -floor)))
    }
}
