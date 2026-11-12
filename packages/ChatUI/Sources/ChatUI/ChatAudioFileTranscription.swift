import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramMedia
import OpusBinding
import Localization

func audioFileTranscriptionErrorText(_ error: AudioFileTranscriptionError) -> String {
    switch error {
    case .premiumRequired:
        return strings().chatAudioFileTranscriptionPremiumRequired
    case let .limitExceeded(seconds):
        return strings().chatAudioFileTranscriptionLimitExceededOther(Int(seconds))
    case .tooBig:
        return strings().chatAudioFileTranscriptionTooBig
    case .tooLong:
        return strings().chatAudioFileTranscriptionTooLong
    case .invalidAudio, .inputFileInvalid:
        return strings().chatAudioFileTranscriptionInvalidAudio
    case .failed, .generic, .timedOut:
        return strings().chatAudioFileTranscriptionFailed
    }
}

func prepareAudioFileTranscription(_ data: Data, trimRange: Range<Double>?) -> Signal<(Data, Double), AudioFileTranscriptionError> {
    return Signal { subscriber in
        let source = URL(fileURLWithPath: temporaryMediaPath("transcription_source", "ogg"))
        let trimmed = URL(fileURLWithPath: temporaryMediaPath("transcription_trimmed", "ogg"))
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: trimmed)
        }
        do {
            try data.write(to: source)
            let path: String
            let audio: Data
            if let trimRange {
                guard trimOpusFile(source.path, to: trimmed.path, start: trimRange.lowerBound, end: trimRange.upperBound) else {
                    subscriber.putError(.invalidAudio)
                    return EmptyDisposable
                }
                path = trimmed.path
                audio = try Data(contentsOf: trimmed)
            } else {
                path = source.path
                audio = data
            }
            guard audio.count <= 1024 * 1024 else {
                subscriber.putError(.tooBig)
                return EmptyDisposable
            }
            guard let reader = OggOpusReader(path: path) else {
                subscriber.putError(.invalidAudio)
                return EmptyDisposable
            }
            let capacity = 4800
            let samples = UnsafeMutablePointer<Int16>.allocate(capacity: capacity)
            defer { samples.deallocate() }
            var total = 0
            while true {
                let count = Int(reader.read(UnsafeMutableRawPointer(samples), bufSize: Int32(capacity)))
                guard count >= 0, count <= capacity else {
                    subscriber.putError(.invalidAudio)
                    return EmptyDisposable
                }
                if count == 0 { break }
                total += count
                if total > 1800 * 48000 {
                    subscriber.putError(.tooLong)
                    return EmptyDisposable
                }
            }
            let duration = Double(total) / 48000
            guard duration >= 1 else {
                subscriber.putError(.invalidAudio)
                return EmptyDisposable
            }
            subscriber.putNext((audio, duration))
            subscriber.putCompletion()
        } catch {
            subscriber.putError(.invalidAudio)
        }
        return EmptyDisposable
    } |> runOn(Queue.concurrentDefaultQueue())
}
