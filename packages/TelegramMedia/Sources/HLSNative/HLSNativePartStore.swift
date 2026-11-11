import Foundation
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramMediaPlayer
import HLSPlayback

final class HLSNativePartStore {
    private static let readTimeout: Double = 10.0

    private let engine: TelegramEngine
    private let files: [HLSNativeQualityFile]
    private let queue = Queue(name: "HLSNativePartStore")

    private var parts: [HLSSegmentKey: ChunkMediaPlayerPart] = [:]
    private var pendingDisposal: [TempBoxFile] = []
    private var makeDisposables: [HLSSegmentKey: Disposable] = [:]

    init(engine: TelegramEngine, files: [HLSNativeQualityFile]) {
        self.engine = engine
        self.files = files
    }

    deinit {
        self.removeAll()
    }

    func makePart(level: Int, request: HLSAppendRequest, completion: @escaping (HLSAppendOutcome) -> Void) {
        guard level >= 0 && level < self.files.count else {
            completion(.failed)
            return
        }
        let qualityFile = self.files[level]
        let resource = EngineMediaResource(qualityFile.file.media.resource)
        let size = qualityFile.size
        let queue = self.queue

        let initData: Signal<Data?, NoError>
        if let initRange = request.initRange {
            initData = self.engine.resources.rangeData(resource: resource, size: size, range: initRange)
            |> take(1)
            |> map { data, isComplete -> Data? in
                return isComplete ? data : nil
            }
        } else {
            initData = .single(Data())
        }
        let segmentData = self.engine.resources.rangeData(resource: resource, size: size, range: request.dataRange)
        |> take(1)
        |> map { data, isComplete -> Data? in
            return isComplete ? data : nil
        }
        let bytes = combineLatest(initData, segmentData)
        |> take(1)
        |> map { initData, segmentData -> (Data, Data)? in
            guard let initData, let segmentData else {
                return nil
            }
            return (initData, segmentData)
        }
        |> timeout(HLSNativePartStore.readTimeout, queue: queue, alternate: .single(nil))

        let part: Signal<ChunkMediaPlayerPart?, NoError> = Signal { subscriber in
            let isCancelled = Atomic<Bool>(value: false)
            let disposable = (bytes |> deliverOn(queue)).start(next: { value in
                guard let (initData, segmentData) = value else {
                    subscriber.putNext(nil)
                    subscriber.putCompletion()
                    return
                }
                let tempFile = TempBox.shared.tempFile(fileName: "data.mp4")
                var combined = Data()
                combined.reserveCapacity(initData.count + segmentData.count)
                combined.append(initData)
                combined.append(segmentData)
                guard let _ = try? combined.write(to: URL(fileURLWithPath: tempFile.path), options: .atomic), let trackTiming = HLSNativePartStore.trackTiming(data: combined, path: tempFile.path), let timing = HLSPartTiming.range(audio: trackTiming.audio, video: trackTiming.video) else {
                    TempBox.shared.dispose(tempFile)
                    subscriber.putNext(nil)
                    subscriber.putCompletion()
                    return
                }
                if isCancelled.with({ $0 }) {
                    TempBox.shared.dispose(tempFile)
                    return
                }
                subscriber.putNext(ChunkMediaPlayerPart(
                    startTime: timing.start,
                    endTime: timing.end,
                    content: ChunkMediaPlayerPart.TempFile(file: tempFile, ignoreAudioEditList: true),
                    codecName: trackTiming.videoCodecName,
                    offsetTime: 0.0
                ))
                subscriber.putCompletion()
            })
            return ActionDisposable {
                let _ = isCancelled.swap(true)
                disposable.dispose()
            }
        }

        let key = request.key
        self.makeDisposables.removeValue(forKey: key)?.dispose()
        self.makeDisposables[key] = (part |> deliverOnMainQueue).startStrict(next: { [weak self] part in
            guard let self else {
                if let part {
                    TempBox.shared.dispose(part.content.file)
                }
                return
            }
            self.makeDisposables.removeValue(forKey: key)?.dispose()
            if let part {
                if let previous = self.parts[key] {
                    self.pendingDisposal.append(previous.content.file)
                }
                self.parts[key] = part
                completion(.appended(start: part.startTime, end: part.endTime))
            } else {
                completion(.failed)
            }
        })
    }

    static func trackTiming(data: Data, path: String) -> (audio: (start: Double, duration: Double)?, video: (start: Double, duration: Double)?, videoCodecName: String?)? {
        if let info = HLSFragmentTiming.parse(data) {
            return (info.audio.map { ($0.start, $0.duration) }, info.video.map { ($0.start, $0.duration) }, info.videoCodecName)
        }
        guard let mediaInfo = extractFFMpegMediaInfo(path: path) else {
            return nil
        }
        return (mediaInfo.audio.map { ($0.startTime.seconds, $0.duration.seconds) }, mediaInfo.video.map { ($0.startTime.seconds, $0.duration.seconds) }, mediaInfo.video?.codecName)
    }

    func parts(for buffered: [HLSBufferedPart]) -> [ChunkMediaPlayerPart] {
        let bufferedKeys = Set(buffered.map(\.key))
        for key in Array(self.parts.keys) where !bufferedKeys.contains(key) && self.makeDisposables[key] == nil {
            if let part = self.parts.removeValue(forKey: key) {
                self.pendingDisposal.append(part.content.file)
            }
        }
        let result = buffered.compactMap({ self.parts[$0.key] }).sorted(by: { $0.startTime < $1.startTime })
        self.scheduleDisposal()
        return result
    }

    func remove(keys: [HLSSegmentKey]) {
        for key in keys {
            self.makeDisposables.removeValue(forKey: key)?.dispose()
            if let part = self.parts.removeValue(forKey: key) {
                self.pendingDisposal.append(part.content.file)
            }
        }
    }

    func removeAll() {
        for (_, disposable) in self.makeDisposables {
            disposable.dispose()
        }
        self.makeDisposables.removeAll()
        for (_, part) in self.parts {
            TempBox.shared.dispose(part.content.file)
        }
        self.parts.removeAll()
        for file in self.pendingDisposal {
            TempBox.shared.dispose(file)
        }
        self.pendingDisposal.removeAll()
    }

    private func scheduleDisposal() {
        if self.pendingDisposal.isEmpty {
            return
        }
        let files = self.pendingDisposal
        self.pendingDisposal.removeAll()
        DispatchQueue.main.async {
            for file in files {
                TempBox.shared.dispose(file)
            }
        }
    }
}
