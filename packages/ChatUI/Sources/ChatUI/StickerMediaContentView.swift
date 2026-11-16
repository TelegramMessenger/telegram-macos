import Foundation
import Cocoa
import CoreMedia
import TGUIKit
import TelegramCore
import SwiftSignalKit
import Postbox
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMedia
import TelegramMediaUtils
import TelegramMediaResources
import InAppSettings
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils


public class StickerMediaContentView: ChatMediaContentView {
    
    private class LockView : NSVisualEffectView {
        private let lockedView: ImageView = ImageView()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(lockedView)
            lockedView.isAccessibilityDecorative = true
            
            wantsLayer = true
            self.blendingMode = .withinWindow
            self.state = .active
            self.material = .dark
            
            lockedView.image = theme.icons.premium_lock
            lockedView.sizeToFit()
            lockedView.setFrameSize(lockedView.frame.width * 0.7, lockedView.frame.height * 0.7)
            self.layer?.cornerRadius = frameRect.height / 2
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func layout() {
            super.layout()
            lockedView.center()
        }
    }

    private var lockedView: LockView?
    
    private var content: ChatMediaContentView? {
        didSet {
            if isLocked {
                content?.layer?.opacity = 0.7
            } else {
                content?.layer?.opacity = 1.0
            }
        }
    }
    
    
    public override var isHidden: Bool {
        didSet {
            if let content = content as? MediaAnimatedStickerView {
                content.updatePlayerIfNeeded()
            }
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private let animationEffectDisposable = DisposableSet()
    
    deinit {
        animationEffectDisposable.dispose()
    }
    
    
    private var isLocked: Bool = false
    public func set(locked: Bool, animated: Bool) {
        self.isLocked = locked
        if isLocked {
            content?.layer?.opacity = 0.7
        } else {
            content?.layer?.opacity = 1.0
        }
        if isLocked {
            let current: LockView
            if let view = self.lockedView {
                current = view
            } else {
                current = LockView(frame: NSMakeRect(0, 0, 17, 17))
                self.lockedView = current
                addSubview(current, positioned: .above, relativeTo: content)
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
        } else if let view = lockedView {
            performSubviewRemoval(view, animated: animated)
            self.lockedView = nil
        }
        
        needsLayout = true
    }
    
    public func play() {
        if let content = content as? MediaAnimatedStickerView {
            content.play()
        }
    }
    
    public var playOnHover: Bool? = nil {
        didSet {
            if let content = content as? MediaAnimatedStickerView {
                content.playOnHover = playOnHover
            }
        }
    }
    
    public var overridePlayValue: Bool? = nil {
        didSet {
            if let content = content as? MediaAnimatedStickerView {
                content.overridePlayValue = overridePlayValue
            }
        }
    }
    
    public override func clean() {
        content?.clean()
    }
    
    public override var backgroundColor: NSColor {
        didSet {
            content?.backgroundColor = backgroundColor
        }
    }
    
    public override func mouseInside() -> Bool {
        return content?.mouseInside() ?? super.mouseInside()
    }
    
    public override func previewMediaIfPossible() -> Bool {
        return content?.previewMediaIfPossible() ?? false
    }
    
    public required init(frame frameRect: NSRect) {
        super.init(frame:frameRect)
    }
    
    public override var canSpamClicks: Bool {
        return content?.canSpamClicks ?? super.canSpamClicks
    }
    
    private var suggestOpenPremiumPack: Bool = false
    
    public override func executeInteraction(_ isControl: Bool) {
        if let window = window as? Window, let context = self.context, let media = media as? TelegramMediaFile, let peerId = parent?.id.peerId {
            
            if suggestOpenPremiumPack, let reference = media.stickerReference {
                
                let title: String?
                switch reference {
                case let .name(name):
                    title = name
                default:
                    title = nil
                }
                
                showModalText(for: context.window, text: strings().stickerPremiumClickInfo, title: title, callback: { _ in
                    showModal(with:ChatMediaUIHooks.shared.makeStickerPackPreview(context, peerId, [.stickers(reference)]), for:window)
                })
                suggestOpenPremiumPack = false
            } else {
                if media.isPremiumSticker, !context.premiumIsBlocked {
                    if !suggestOpenPremiumPack {
                        suggestOpenPremiumPack = true
                    }
                }
            }
            
            if media.isPremiumSticker, !media.noPremium, !context.premiumIsBlocked, let parent = parent {
                self.playIfNeeded(true)
                parameters?.runPremiumScreenEffect(parent)
                return
            }
            
            if let reference = media.stickerReference, media.fileName != "telegram-animoji.tgs" {
                showModal(with:ChatMediaUIHooks.shared.makeStickerPackPreview(context, peerId, [.stickers(reference)]), for: context.window)
            } else if let sticker = media.stickerText, !sticker.isEmpty {
                let signal = context.diceCache.animationEffect(for: sticker.emojiUnmodified) |> deliverOnMainQueue
                animationEffectDisposable.add(signal.start(next: { [weak self] files in
                    if files.isEmpty || media.customEmojiText != nil {
                        if let reference = media.emojiReference {
                            showModal(with:ChatMediaUIHooks.shared.makeStickerPackPreview(context, peerId, [.emoji(reference)]), for: context.window)
                        }
                    } else {
                        self?.parameters?.runEmojiScreenEffect(sticker)
                    }
                    self?.playIfNeeded(true)
                }))
            }
        }
    }
    
    public override func playIfNeeded(_ playSound: Bool = false) {
        content?.playIfNeeded(playSound)
    }
    
    
    public override func update(with media: Media, size: NSSize, context: any AccountContextProtocol, parent:Message?, table:TableView?, parameters:ChatMediaLayoutParameters? = nil, animated: Bool = false, positionFlags: LayoutPositionFlags? = nil, approximateSynchronousValue: Bool = false) {
        
        
        let prev = self.media as? TelegramMediaFile
        let prevParent = self.parent
        
        suggestOpenPremiumPack = false
                      
        super.update(with: media, size: size, context: context, parent:parent,table:table, parameters:parameters, animated: animated, positionFlags: positionFlags)
        
        self.fetchStatus = .Local
        
        let file = media as! TelegramMediaFile
        
        var contentClass: ChatMediaContentView.Type
        if file.isAnimatedSticker || (!file.isChatStaticSticker && file.mimeType == "image/webp") || file.isWebm {
            contentClass = MediaAnimatedStickerView.self
        } else if file.isVideoSticker {
            contentClass = VideoStickerContentView.self
        } else {
            contentClass = ChatStickerContentView.self
        }
        if content == nil || !content!.isKind(of: contentClass)  {
            if let view = self.content {
                performSubviewRemoval(view, animated: animated)
            }
            let content = contentClass.init(frame:size.bounds)
            self.content = content
            self.addSubview(content, positioned: .below, relativeTo: lockedView)
        }
        
        guard let content = self.content else {
            return
        }
        if let content = content as? MediaAnimatedStickerView {
            content.playOnHover = playOnHover
        }
        
        let aspectSize = file.dimensions?.size.aspectFitted(size) ?? size

        content.update(with: file, size: aspectSize, context: context, parent: parent, table: table, parameters: parameters, animated: animated, positionFlags: positionFlags, approximateSynchronousValue: approximateSynchronousValue)
        
        content.userInteractionEnabled = false
        
        if let prevParent = prevParent, let parent = parent {
            let prevSending = prevParent.flags.contains(.Sending) || prevParent.flags.contains(.Unsent)
            let sending = parent.flags.contains(.Sending) || parent.flags.contains(.Unsent)
            if prevSending && !sending, file.fileId == prev?.fileId {
                if file.isPremiumSticker, !file.noPremium {
                    parameters?.runPremiumScreenEffect(parent)
                }
            }
        }
    
        
        
        needsLayout = true
    }
    
    
    public override func layout() {
        super.layout()
        if let view = lockedView {
            view.centerX(y: frame.height - view.frame.height)
        }
        self.content?.center()
    }
    
    public override func copy() -> Any {
        return content?.copy() ?? super.copy()
    }
    
    public override func interactionContentView(for innerId: AnyHashable, animateIn: Bool ) -> NSView {
        return content?.interactionContentView(for: innerId, animateIn: animateIn) ?? self
    }
    
    public override func interactionControllerDidFinishAnimation(interactive: Bool) {
        content?.interactionControllerDidFinishAnimation(interactive: interactive)
    }
    
    public override func videoTimebase() -> CMTimebase? {
        return content?.videoTimebase()
    }
    public override func applyTimebase(timebase: CMTimebase?) {
        content?.applyTimebase(timebase: timebase)
    }
    
    public override func addAccesoryOnCopiedView(view: NSView) {
        content?.addAccesoryOnCopiedView(view: view)
    }

    public override var contents: Any? {
        return content?.contents
    }
    
    public override func willRemove() -> Void {
        content?.willRemove()
    }
    
    public override func cancel() -> Void {
        content?.cancel()
    }
    
    public override func open() -> Void {
        content?.open()
    }
    
    public override func fetch(userInitiated: Bool) -> Void {
        content?.fetch(userInitiated: true)
    }
    
    public override func preloadStreamblePart() {
        content?.preloadStreamblePart()
    }
    
    public override func updateMouse() {
        content?.updateMouse()
    }
}
