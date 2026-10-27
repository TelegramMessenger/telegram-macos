import Cocoa
import TGUIKit
import TelegramContext

public struct EditImageCanvasStickerPick {
    public let image: CGImage
    public let fileId: Int64?
    public let animation: EditImageCanvasStickerAnimation?
    public init(image: CGImage, fileId: Int64?, animation: EditImageCanvasStickerAnimation? = nil) {
        self.image = image
        self.fileId = fileId
        self.animation = animation
    }
}

public enum EditImageCanvasStickerDrag {
    case moved(CGImage?, NSPoint)
    case preview(EditImageCanvasStickerPick)
    case ended
    case dropped(EditImageCanvasStickerPick, NSPoint)
}

public protocol EditImageCanvasStickerPicker: AnyObject {
    var visibilityChanged: ((Bool) -> Void)? { get set }
    func show(for control: Control, select: @escaping (EditImageCanvasStickerPick) -> Void, drag: @escaping (EditImageCanvasStickerDrag) -> Void)
    func close()
}

public struct ImageCanvasUIHooks {
    public let makeStickerPicker: (any AccountContextProtocol) -> EditImageCanvasStickerPicker?
    public let confirm: ((Window, String, String, @escaping () -> Void) -> Void)?

    public init(makeStickerPicker: @escaping (any AccountContextProtocol) -> EditImageCanvasStickerPicker?, confirm: ((Window, String, String, @escaping () -> Void) -> Void)?) {
        self.makeStickerPicker = makeStickerPicker
        self.confirm = confirm
    }

    public static func emojiImage(_ emoji: String) -> CGImage? {
        return editImageCanvasEmojiImage(emoji)
    }

    private static var _shared: ImageCanvasUIHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: ImageCanvasUIHooks {
        return _shared ?? .placeholder
    }

    public static func install(_ hooks: ImageCanvasUIHooks) {
        assert(Thread.isMainThread, "ImageCanvasUIHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = ImageCanvasUIHooks(makeStickerPicker: { _ in
        return nil
    }, confirm: nil)
}
