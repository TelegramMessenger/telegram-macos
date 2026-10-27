import Cocoa
import TelegramCore
import InAppSettings
import TGUIKit
import SwiftSignalKit
import Postbox
import ImageCanvasUI
import TelegramTheme
import Localization
import TelegramContext
import TelegramUtils
import TelegramMediaUtils
import MessageUtils
import AvatarEditorUI
import ChatUI

class MediaPreviewRowItem: TableRowItem {
    
    


    let media: Media
    fileprivate let context: any AccountContextProtocol
    private let _stableId = arc4random()
    fileprivate let parameters: ChatMediaLayoutParameters?
    fileprivate let chatInteraction: ChatInteraction
    fileprivate let edit:()->Void
    fileprivate let paint:()->Void
    fileprivate let delete: (()->Void)?
    fileprivate let editedData: EditedImageData?
    fileprivate let theme: TelegramPresentationTheme
    fileprivate let payAmount: Int64?
    fileprivate let renderingPreview: CGImage?
    init(_ initialSize: NSSize, media: Media, context: any AccountContextProtocol, theme: TelegramPresentationTheme, editedData: EditedImageData? = nil, isSpoiler: Bool, payAmount: Int64?, renderingPreview: CGImage? = nil, edit:@escaping()->Void = {}, paint:@escaping()->Void = {}, delete: (()->Void)? = nil) {
        self.renderingPreview = renderingPreview
        self.edit = edit
        self.paint = paint
        self.delete = delete
        self.media = media
        self.context = context
        self.theme = theme
        self.payAmount = payAmount
        self.editedData = editedData
        self.chatInteraction = ChatInteraction(chatLocation: .peer(PeerId(0)), context: context)
        if let media = media as? TelegramMediaFile {
            parameters = ChatMediaLayoutParameters.layout(for: media, isWebpage: false, chatInteraction: chatInteraction, presentation: .make(theme: theme), automaticDownload: true, isIncoming: false, autoplayMedia: AutoplayMediaPreferences.defaultSettings)
        } else {
            parameters = ChatMediaLayoutParameters(presentation: .make(theme: theme), media: media)
        }
        
        parameters?.forceSpoiler = isSpoiler || payAmount != nil
        parameters?.payAmount = payAmount
        
        super.init(initialSize)
        _ = makeSize(initialSize.width, oldWidth: 0)
    }
    
    
    private var overSize: CGFloat? = nil
    override func makeSize(_ width: CGFloat, oldWidth: CGFloat) -> Bool {
        let result = super.makeSize(width, oldWidth: oldWidth)
        parameters?.makeLabelsForWidth(width - (media.isInteractiveMedia ? 20 : 60))
        
        if let table = table, table.count == 1 {
            if contentSize.height > table.frame.height && table.frame.height > 0 {
                overSize = table.frame.height - 12
            } else {
                overSize = nil
            }
        }
        
        return result
    }
    
    override var stableId: AnyHashable {
        return _stableId
    }
    
    override var identifier: String {
        return "\(ChatLayoutUtils.contentNode(for: media))"
    }
    
    override var height: CGFloat {
        return contentSize.height + 12
    }
    
    var contentSize: NSSize {
        let contentSize = layoutSize
        
        let width = self.width - (media.isInteractiveMedia ? 20 : 40)
        
        var height: CGFloat = overSize ?? contentSize.height
        if let media = media as? TelegramMediaFile {
            if media.isSticker || media.isAnimatedSticker {
                height = width
            }
        }
        return NSMakeSize(width, height)
    }
    
    override var layoutSize: NSSize {
        return ChatLayoutUtils.contentSize(for: media, with: initialSize.width - (media.isInteractiveMedia ? 20 : 80))
    }
    
    public func contentNode() -> ChatMediaContentView.Type {
        return ChatLayoutUtils.contentNode(for: media)
    }
    
    override func viewClass() -> AnyClass {
        return MediaPreviewRowView.self
    }

    override var accessibilityLabel: String? {
        return previewSenderAccessibilityLabel(for: media)
    }

    override var accessibilityCustomActions: [NSAccessibilityCustomAction]? {
        var actions: [NSAccessibilityCustomAction] = []
        if media is TelegramMediaImage {
            actions.append(NSAccessibilityCustomAction(name: strings().voiceOverCommonEdit, handler: { [weak self] in
                self?.edit()
                return true
            }))
            actions.append(NSAccessibilityCustomAction(name: strings().voiceOverCommonDraw, handler: { [weak self] in
                self?.paint()
                return true
            }))
        } else if canEditPreviewVideo(media) {
            actions.append(NSAccessibilityCustomAction(name: strings().voiceOverCommonEdit, handler: { [weak self] in
                self?.edit()
                return true
            }))
        }
        if delete != nil {
            actions.append(NSAccessibilityCustomAction(name: strings().voiceOverCommonDelete, handler: { [weak self] in
                self?.delete?()
                return true
            }))
        }
        return actions.isEmpty ? nil : actions
    }
}

fileprivate class MediaPreviewRowView : TableRowView, ModalPreviewRowViewProtocol {
    
    func fileAtPoint(_ point: NSPoint) -> (QuickPreviewMedia, NSView?)? {
        if let contentNode = contentNode {
            if contentNode is VideoStickerContentView {
                if let file = contentNode.media as? TelegramMediaFile {
                    let reference = contentNode.parent != nil ? FileMediaReference.message(message: MessageReference(contentNode.parent!), media: file) : FileMediaReference.standalone(media: file)
                    return (.file(reference, GifPreviewModalView.self), contentNode)
                }
            } else if contentNode is ChatInteractiveContentView {
                if let image = contentNode.media as? TelegramMediaImage {
                    let reference = contentNode.parent != nil ? ImageMediaReference.message(message: MessageReference(contentNode.parent!), media: image) : ImageMediaReference.standalone(media: image)
                    return (.image(reference, ImagePreviewModalView.self), contentNode)
                }
            } else if contentNode is MediaAnimatedStickerView {
                if let file = contentNode.media as? TelegramMediaFile {
                    let reference = contentNode.parent != nil ? FileMediaReference.message(message: MessageReference(contentNode.parent!), media: file) : FileMediaReference.standalone(media: file)
                    return (.file(reference, AnimatedStickerPreviewModalView.self), contentNode)
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
    
    var contentNode:ChatMediaContentView?
    let editControl: MediaPreviewEditControl = MediaPreviewEditControl()
    override var needsDisplay: Bool {
        get {
            return super.needsDisplay
        }
        set {
            super.needsDisplay = true
            contentNode?.needsDisplay = true
        }
    }
    
    override func forceClick(in location: NSPoint) {
        _ = contentNode?.previewMediaIfPossible()
    }
    
    override func draw(_ dirtyRect: NSRect) {
        
    }
    
    override func updateMouse(animated: Bool) {
        guard let window = window, let table = item?.table else {
            editControl.isHidden = true
            return
        }
        
        let row = table.row(at: table.documentView!.convert(window.mouseLocationOutsideOfEventStream, from: nil))

        if row == item?.index {
            editControl.isHidden = false
        } else {
            editControl.isHidden = true
        }
    }
    
    override func shakeView() {
        contentNode?.shake()
    }
    override var backdorColor: NSColor {
        return .clear
    }
    
    override func set(item:TableRowItem, animated:Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? MediaPreviewRowItem else { return }
        
        if contentNode == nil || !contentNode!.isKind(of: item.contentNode())  {
            self.contentNode?.removeFromSuperview()
            let node = item.contentNode()
            self.contentNode = node.init(frame:NSZeroRect)
            self.addSubview(self.contentNode!)
            addSubview(editControl)
            updateMouse(animated: animated)
        }
        
        
        editControl.isVideo = canEditPreviewVideo(item.media)
        editControl.canEdit = item.media is TelegramMediaImage || editControl.isVideo
        editControl.isInteractiveMedia = item.media.isInteractiveMedia || item.media.probablySticker
        editControl.canDelete = item.delete != nil
        editControl.set(edit: { [weak item] in
            item?.edit()
        }, paint: { [weak item] in
            item?.paint()
        }, delete: { [weak item] in
            item?.delete?()
        }, editedData: item.editedData)
        
        self.contentNode?.update(with: item.media, size: item.contentSize, context: item.context, parent: nil, table: item.table, parameters: item.parameters, animated: animated)
        if let contentNode {
            updateMediaPreviewRendering(item.renderingPreview, in: contentNode, animated: animated)
        }
    }
    
    override func layout() {
        super.layout()
        guard let contentNode = contentNode else {return}
        contentNode.setFrameOrigin(12, 6)
        if editControl.isInteractiveMedia {
            editControl.setFrameOrigin(NSMakePoint(frame.width - editControl.frame.width - 20, frame.height - editControl.frame.height - 20))
        } else {
            editControl.centerY(x: frame.width - editControl.frame.width - 10)
        }
    }
    
    open override func interactionContentView(for innerId: AnyHashable, animateIn: Bool ) -> NSView {
        if let content = self.contentNode?.interactionContentView(for: innerId, animateIn: animateIn) {
            return content
        }
        return self
    }
    
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
    }
    
    override var backgroundColor: NSColor {
        didSet {
            contentNode?.backgroundColor = backdorColor
        }
    }
    
    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview == nil {
            self.contentNode?.willRemove()
        }
    }
    
}

final class MediaPreviewRenderingView: View {
    private let imageView = ImageView()
    private let progressBackground = View(frame: NSMakeRect(0, 0, 48, 48))
    private let progress = ProgressIndicator(frame: NSMakeRect(0, 0, 28, 28))

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView.contentGravity = .resizeAspectFill
        addSubview(imageView)
        progressBackground.backgroundColor = NSColor.black.withAlphaComponent(0.5)
        progressBackground.layer?.cornerRadius = progressBackground.frame.height / 2
        progress.progressColor = .white
        progressBackground.addSubview(progress)
        addSubview(progressBackground)
        autoresizingMask = [.width, .height]
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(image: CGImage) {
        imageView.image = image
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds
        progressBackground.center()
        progress.center()
    }
}

func updateMediaPreviewRendering(_ image: CGImage?, in view: NSView, animated: Bool) {
    let current = view.subviews.compactMap { $0 as? MediaPreviewRenderingView }.first
    if let image {
        let overlay = current ?? MediaPreviewRenderingView(frame: view.bounds)
        overlay.frame = view.bounds
        overlay.update(image: image)
        view.addSubview(overlay)
    } else if let current {
        performSubviewRemoval(current, animated: animated)
    }
}

func previewSenderAccessibilityLabel(for media: Media) -> String {
    if media is TelegramMediaImage {
        return strings().voiceOverCommonPhoto
    }
    if let file = media as? TelegramMediaFile {
        if file.isVideo {
            return strings().voiceOverCommonVideo
        }
        if file.isVoice {
            return strings().voiceOverCommonVoiceMessage
        }
        if file.isMusic {
            return file.fileName ?? strings().voiceOverCommonMusic
        }
        if file.isSticker || file.isAnimatedSticker {
            return strings().voiceOverCommonSticker
        }
        return file.fileName ?? strings().voiceOverCommonFile
    }
    return strings().voiceOverCommonFile
}
