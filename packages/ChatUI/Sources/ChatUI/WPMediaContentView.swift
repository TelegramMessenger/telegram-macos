import Cocoa
import TGUIKit
import TelegramCore
import TelegramContext
import TelegramMediaUtils
import TelegramTheme
import TelegramUtils
import UniqueGiftBackground

private final class GiftView: View {
    private let backgroundView = UniqueGiftBackgroundView(frame: .zero)
    private var content: UniqueGiftBackgroundContent?
    private var context: (any AccountContextProtocol)?

    var giftCenterY: CGFloat = 0 {
        didSet {
            if self.giftCenterY != oldValue {
                self.needsLayout = true
            }
        }
    }

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(self.backgroundView)
    }

    func set(_ uniqueGift: StarGift.UniqueGift, context: any AccountContextProtocol, animated: Bool) {
        self.content = UniqueGiftBackgroundContent(gift: uniqueGift)
        self.context = context
        self.needsLayout = true
    }

    override func layout() {
        super.layout()
        self.backgroundView.frame = bounds
        if let content = self.content, let context = self.context {
            self.backgroundView.update(context: context, content: content, style: .item(giftCenterY: self.giftCenterY, cornerRadius: 10))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


public class WPMediaContentView: WPContentView {
    
    public private(set) var contentNode:ChatMediaContentView?
    private var giftView: GiftView?
    
    public override func fileAtPoint(_ point: NSPoint) -> (QuickPreviewMedia, NSView?)? {
        if let contentNode = contentNode {
            if contentNode is ChatStickerContentView {
                if let file = contentNode.media as? TelegramMediaFile {
                    let reference = contentNode.parent != nil ? FileMediaReference.message(message: MessageReference(contentNode.parent!), media: file) : FileMediaReference.standalone(media: file)
                    return (.file(reference, StickerPreviewModalView.self), contentNode)
                }
            } else if contentNode is VideoStickerContentView {
                if let file = contentNode.media as? TelegramMediaFile {
                    let reference = contentNode.parent != nil ? FileMediaReference.message(message: MessageReference(contentNode.parent!), media: file) : FileMediaReference.standalone(media: file)
                    return (.file(reference, GifPreviewModalView.self), contentNode)
                }
            } else if contentNode is ChatInteractiveContentView {
                if let image = contentNode.media as? TelegramMediaImage {
                    let reference = contentNode.parent != nil ? ImageMediaReference.message(message: MessageReference(contentNode.parent!), media: image) : ImageMediaReference.standalone(media: image)
                    return (.image(reference, ImagePreviewModalView.self), contentNode)
                }
            } else if contentNode is ChatFileContentView {
                if let file = contentNode.media as? TelegramMediaFile, file.isGraphicFile, let mediaId = file.id, let dimension = file.dimensions {
                    var representations: [TelegramMediaImageRepresentation] = []
                    representations.append(contentsOf: file.previewRepresentations)
                    representations.append(TelegramMediaImageRepresentation(dimensions: dimension, resource: file.resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))
                    let image = TelegramMediaImage(imageId: mediaId, representations: representations, immediateThumbnailData: file.immediateThumbnailData, reference: nil, partialReference: file.partialReference, flags: [])
                    let reference = contentNode.parent != nil ? ImageMediaReference.message(message: MessageReference(contentNode.parent!), media: image) : ImageMediaReference.standalone(media: image)
                    return (.image(reference, ImagePreviewModalView.self), contentNode)
                }
            }
        }
        
        return nil
    }
    
    public override func previewMediaIfPossible() -> Bool {
        guard  let window = self._window, let content = content as? WPArticleLayout, content.isFullImageSize, let table = content.table, let contentNode = contentNode, contentNode.mouseInside() else {return false}
        startModalPreviewHandle(table, window: window, context: content.context)
        return true
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        
        // Drawing code here.
    }
    
    
    public override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview == nil {
            self.contentNode?.willRemove()
        }
    }

    
    public override func update(with layout: WPLayout, animated: Bool) {
        super.update(with: layout, animated: animated)
        
        if let layout = layout as? WPMediaLayout {
            if contentNode == nil || !contentNode!.isKind(of: layout.contentNode())  {
                self.contentNode?.removeFromSuperview()
                let node = layout.contentNode()
                self.contentNode = node.init(frame:NSZeroRect)
                self.addSubview(self.contentNode!)
            }
            contentNode?.userInteractionEnabled = layout.isMediaClickable
            
            self.contentNode?.update(with: layout.media, size: layout.mediaSize, context: layout.context, parent:layout.parent, table:layout.table, parameters: layout.parameters, approximateSynchronousValue: layout.approximateSynchronousValue)
        }
        
        if let uniqueGift = layout.uniqueGift {
            let current: GiftView
            if let view = self.giftView {
                current = view
            } else {
                current = GiftView(frame: layout.contentRect)
                current.isEventLess = true
                self.containerView.addSubview(current, positioned: .below, relativeTo: self.contentNode)
                self.giftView = current
            }
            current.set(uniqueGift, context: layout.context, animated: animated)
            
        } else if let giftView {
            performSubviewRemoval(giftView, animated: animated)
            self.giftView = nil
        }
        self.contentNode?.userInteractionEnabled = self.giftView == nil
    }
    
    public override func updateMouse() {
        contentNode?.updateMouse()
    }
    
    static func giftBackgroundFrame(contentRect: NSRect, textFrame: NSRect) -> NSRect {
        let frame = contentRect.insetBy(dx: 0, dy: 35).offsetBy(dx: -8, dy: -2)
        let minY = max(frame.minY, textFrame.maxY + 6)
        return NSMakeRect(frame.minX, minY, frame.width, max(0, frame.maxY - minY))
    }

    public override func layout() {
        super.layout()
        if let contentNode = contentNode, let content = content as? WPMediaLayout {
            let y: CGFloat
            if !content.isLeadingMedia {
                y = containerView.frame.height - content.mediaSize.height - (content.action_text != nil ? 36 : 0)
            } else {
                y = content.insets.top
            }
            
            let rect = CGRect(origin: NSMakePoint(0, y), size: content.mediaSize)
            contentNode.frame = rect
            
            giftView?.frame = Self.giftBackgroundFrame(contentRect: content.contentRect, textFrame: textView.frame)
            
            if let giftView {
                contentNode.frame = contentNode.frame.offsetBy(dx: 0, dy: -28)
                giftView.giftCenterY = contentNode.frame.midY - giftView.frame.minY
            }
        }
        
    }
    
    public override func interactionContentView(for innerId: AnyHashable, animateIn: Bool ) -> NSView {
        return contentNode?.interactionContentView(for: innerId, animateIn: animateIn) ?? self
    }
    
    public override var mediaContentView: NSView? {
        return contentNode
    }
    
}
