import Cocoa
import TGUIKit

enum ReferenceIcon { case iconQuote, iconCopyCode }
struct TelegramThemeHooks {
    static let shared = TelegramThemeHooks()
    static var imageOverride: ((ReferenceIcon) -> NSImage)?
    func image(_ icon: ReferenceIcon) -> NSImage {
        if let imageOverride = Self.imageOverride { return imageOverride(icon) }
        return NSImage(named: icon == .iconQuote ? "Icon_Quote" : "Icon_CopyCode")!
    }
}
struct LottieColor {
    let keyPath: String
    let color: NSColor
}
struct LottieAnimation {
    struct Key {
        enum Source { case bundle(String) }
        let key: Source
        let size: NSSize
        let colors: [LottieColor]
    }
    let compressed: Data
    let key: Key
    let playPolicy: PlayPolicy
    let colors: [LottieColor]
}
class LottiePlayerView: View {
    private(set) var animation: LottieAnimation?
    func set(_ animation: LottieAnimation) { self.animation = animation }
}
enum LocalAnimatedSticker: String {
    case voice_dots
    var data: Data? { Data([1]) }
}
