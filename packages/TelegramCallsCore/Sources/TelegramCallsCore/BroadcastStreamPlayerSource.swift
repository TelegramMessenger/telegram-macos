import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramMedia
import TelegramMediaPlayer
import BroadcastPlayback

final class BroadcastStreamPlayerSource: ChunkMediaPlayerSourceImpl {
    private static let liveDuration: Double = 1.0e12

    private struct Part {
        let timestampMs: Int64
        let file: EngineTempBoxFile
        let offset: Double
        let codecName: String?
    }

    private let partsPromise = Promise<ChunkMediaPlayerPartsState>()
    private var parts: [Part] = []
    private var timeline = BroadcastStreamTimeline()

    var partTimestampsMs: [Int64] {
        return self.parts.map(\.timestampMs)
    }

    var partsState: Signal<ChunkMediaPlayerPartsState, NoError> {
        return self.partsPromise.get()
    }

    init() {
        self.publish()
    }

    func add(segmentTimestampMs: Int64, sliceFile: EngineTempBoxFile, audioDurationSeconds: Double?, codecName: String? = nil) {
        let offset = self.timeline.offset(timestampMs: segmentTimestampMs, audioDurationSeconds: audioDurationSeconds)
        self.parts.removeAll(where: { part in
            if part.timestampMs == segmentTimestampMs {
                BroadcastStreamPlayerSource.dispose(part.file)
                return true
            }
            return false
        })
        self.parts.append(Part(timestampMs: segmentTimestampMs, file: sliceFile, offset: offset, codecName: codecName))
        self.parts.sort(by: { $0.timestampMs < $1.timestampMs })
        self.publish()
    }

    func remove(timestampsMs: [Int64]) {
        let removed = Set(timestampsMs)
        self.removeParts(where: { removed.contains($0.timestampMs) })
    }

    func removePlayed(before positionMs: Int64) {
        self.removeParts(where: { $0.timestampMs + BroadcastLivePosition.partDurationMs < positionMs - 1000 })
    }

    deinit {
        for part in self.parts {
            EngineTempBox.shared.dispose(part.file)
        }
    }

    func removeAll() {
        self.removeParts(where: { _ in true })
    }

    func seek(id: Int, position: Double) {
    }

    func updatePlaybackState(seekTimestamp: Double, position: Double, isPlaying: Bool) {
    }

    private func removeParts(where predicate: (Part) -> Bool) {
        var removedAny = false
        self.parts.removeAll(where: { part in
            if predicate(part) {
                BroadcastStreamPlayerSource.dispose(part.file)
                removedAny = true
                return true
            }
            return false
        })
        if removedAny {
            self.publish()
        }
    }

    private static func dispose(_ file: EngineTempBoxFile) {
        DispatchQueue.main.async {
            EngineTempBox.shared.dispose(file)
        }
    }

    private func publish() {
        let playerParts = self.parts.map { part in
            return ChunkMediaPlayerPart(
                startTime: Double(part.timestampMs) / 1000.0,
                endTime: Double(part.timestampMs + BroadcastLivePosition.partDurationMs) / 1000.0,
                content: ChunkMediaPlayerPart.TempFile(file: part.file),
                codecName: part.codecName,
                offsetTime: part.offset
            )
        }
        self.partsPromise.set(.single(ChunkMediaPlayerPartsState(duration: BroadcastStreamPlayerSource.liveDuration, content: .parts(playerParts))))
    }
}
