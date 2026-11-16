import Cocoa
import TGUIKit

enum LiteMode { case emoji }
protocol AccountContextProtocol: AnyObject {
    var account: Int { get }
    var inlinePacksContext: Int { get }
    func isLite(_ mode: LiteMode) -> Bool
}
final class BlockContext: AccountContextProtocol {
    var account = 0
    var inlinePacksContext = 0
    var lite = false
    func isLite(_ mode: LiteMode) -> Bool { lite }
}
struct ThemeColors { let text = NSColor.black }
struct BlockTheme { let colors = ThemeColors() }
let theme = BlockTheme()

struct Emoji {
    let fileId: Int64
    var color: NSColor?
}
struct PeerId {
    let value: Int64
    func toInt64() -> Int64 { value }
}
struct Peer { let id: PeerId }
enum PlayPolicy: Equatable { case loop, framesCount(Int) }
final class InlineStickerItem: NSObject {
    enum Source {
        case attribute(Emoji)
        case avatar(Peer)
        case unsupported
    }
    let source: Source
    var playPolicy: PlayPolicy?
    init(_ source: Source) { self.source = source }
}
final class InlineStickerItemLayer: SimpleLayer {
    struct Key: Hashable {
        let id: Int64
        let index: Int
        var color: NSColor?
    }
    weak var superview: NSView?
    let textColor: NSColor
    var isPlayable = false
    init(account: Int, inlinePacksContext: Int, emoji: Emoji, size: NSSize, playPolicy: PlayPolicy, textColor: NSColor) {
        self.textColor = textColor
        super.init()
        frame.size = size
    }
    required init?(coder: NSCoder) { fatalError() }
}
protocol InputInlineAvatarLayer: SimpleLayer {}
final class AvatarLayer: SimpleLayer, InputInlineAvatarLayer {}
struct InputTextViewHooks {
    static let shared = InputTextViewHooks()
    func makeInlineAvatarLayer(_ context: any AccountContextProtocol, _ rect: NSRect, _ peer: Peer) -> any InputInlineAvatarLayer {
        AvatarLayer(frame: rect)
    }
}
enum PlaybackCounters {
    static var calls = 0
    static var layers = 0
}
func updateInlineStickerPlayback<Layers: Collection>(_ layers: Layers, window: NSWindow?, isLite: Bool) where Layers.Element: CALayer {
    PlaybackCounters.calls += 1
    PlaybackCounters.layers += layers.count
    performInlineStickerPlayback(layers, window: window, isLite: isLite)
}
