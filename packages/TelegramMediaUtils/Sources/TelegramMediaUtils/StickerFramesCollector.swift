import Foundation
import TelegramMedia

public protocol StickerFramesCollector {
    func collect() -> [Int : LottiePlayerView]
    func revealDidStart()
}

public extension StickerFramesCollector {
    func revealDidStart() {
    }
}
