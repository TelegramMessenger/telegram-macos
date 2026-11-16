import Foundation
import SwiftSignalKit
import TelegramMediaPlayer

final class HLSNativePlayerSource: ChunkMediaPlayerSourceImpl {
    let partsPromise = Promise<ChunkMediaPlayerPartsState>(ChunkMediaPlayerPartsState(duration: nil, content: .parts([])))
    let partsState: Signal<ChunkMediaPlayerPartsState, NoError>

    var onSeek: ((Double) -> Void)?
    var onPlaybackState: ((_ position: Double, _ isPlaying: Bool) -> Void)?

    private var lastReported: (position: Double, isPlaying: Bool)?

    init() {
        self.partsState = self.partsPromise.get()
    }

    func seek(id: Int, position: Double) {
        self.lastReported = nil
        DispatchQueue.main.async { [weak self] in
            self?.onSeek?(position)
        }
    }

    func updatePlaybackState(seekTimestamp: Double, position: Double, isPlaying: Bool) {
        if let lastReported = self.lastReported, lastReported.isPlaying == isPlaying, abs(lastReported.position - position) < 0.25 {
            return
        }
        self.lastReported = (position, isPlaying)
        DispatchQueue.main.async { [weak self] in
            self?.onPlaybackState?(position, isPlaying)
        }
    }
}
