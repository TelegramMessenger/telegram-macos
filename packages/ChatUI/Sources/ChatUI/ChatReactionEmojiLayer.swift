import Cocoa
import TGUIKit
import InlineStickerLayer

final class ChatReactionEmojiLayer: SimpleLayer {
    #if DEBUG
    static var debugIgnoresKeyWindow = false
    #endif
    private(set) var imageLayer: InlineStickerItemLayer?
    private(set) var isContentPlayable: Bool = false
    var contentPlayableUpdated: ((Bool) -> Void)?
    private var isLite: Bool = false
    private var updatePending: Bool = false

    override init() {
        super.init()
        anchorPoint = .zero
        masksToBounds = true
        isOpaque = true
        edgeAntialiasingMask = []
        if #available(macOS 10.15, *) { cornerCurve = .continuous }
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateLayer(_ imageLayer: InlineStickerItemLayer, isLite: Bool, animated: Bool, host: NSView) {
        if let layer = self.imageLayer {
            performSublayerRemoval(layer, animated: animated)
        }
        self.isLite = isLite
        imageLayer.superview = host
        addSublayer(imageLayer)
        if animated && self.imageLayer != nil {
            imageLayer.animateAlpha(from: 0, to: 1, duration: 0.2)
        }
        self.imageLayer = imageLayer
        layoutImage()
        updateAnimatableContent()
    }

    func layoutImage() {
        guard let imageLayer else { return }
        let size = imageLayer.frame.size
        let frame = CGRect(x: round((bounds.width - size.width) / 2), y: round((bounds.height - size.height) / 2), width: size.width, height: size.height)
        if imageLayer.frame != frame {
            imageLayer.frame = frame
        }
    }

    func updateAnimatableContent() {
        guard !updatePending, let value = imageLayer, value.superview != nil else { return }
        updatePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updatePending = false
            guard let value = self.imageLayer, let superview = value.superview else { return }
            var isKeyWindow = false
            if let window = superview.window {
                isKeyWindow = window.canBecomeKey ? window.isKeyWindow : true
                #if DEBUG
                if ChatReactionEmojiLayer.debugIgnoresKeyWindow {
                    isKeyWindow = true
                }
                #endif
            }
            let isPlayable = !superview.visibleRect.isEmpty && isKeyWindow && !self.isLite
            value.isPlayable = isPlayable
            if self.isContentPlayable != isPlayable {
                self.isContentPlayable = isPlayable
                self.contentPlayableUpdated?(isPlayable)
            }
        }
    }
}
