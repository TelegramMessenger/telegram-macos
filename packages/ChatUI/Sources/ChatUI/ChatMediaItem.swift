import CoreMedia
import Cocoa
import TelegramCore
import InAppSettings
import Postbox
import TGUIKit
import SwiftSignalKit
import TGModernGrowingTextView
import InputView
import TelegramMedia
import TelegramMediaResources
import ArchiveUtils
import ChatHistoryModel
import InputTextView
import Localization
import MessageUtils
import TelegramContext
import TelegramMediaUtils
import TelegramTheme
import TelegramUtils
import InlineStickerLayer


public class ChatMediaItem: ChatRowItem {

    public let media:Media

    
    public var parameters:ChatMediaLayoutParameters? = nil {
        didSet {
            updateParameters()
        }
    }
    
    
    
    private func updateParameters() {
        
        let context = self.context
        
        parameters?.chatLocationInput = chatInteraction.chatLocationInput
        parameters?.chatMode = chatInteraction.mode
        if let message {
            parameters?.isProtected = message.containsSecretMedia || message.isCopyProtected(cachedData: chatInteraction.presentation.cachedData)
        }
        
        parameters?.getUpdatingMediaProgress = { [weak self] messageId in
            if let media = self?.entry.additionalData.updatingMedia {
                switch media.media {
                case .update:
                    return .single(media.progress)
                default:
                    break
                }
            }
            return .single(nil)
        }

        parameters?.bubbleCorners = { [weak self] in
            guard let self else {
                return nil
            }
            return self.mediaBubbleCorners(inset: self.mediaBubbleCornerInset)
        }

        parameters?.markDiceAsPlayed = { message in
            _ = ApplicationSpecificNotice.addPlayedMessageEffects(accountManager: context.sharedContext.accountManager, values: [message.id]).startStandalone()
        }
        
        parameters?.dicePlayed = { [weak self] message in
            if let presentation = self?.chatInteraction.presentation {
                return presentation.playedMessageEffects.contains(message.id)
            } else {
                return true
            }
        }
        
        
        parameters?.cancelOperation = { [unowned context, weak self] message, media in
            if self?.entry.additionalData.updatingMedia != nil {
                context.account.pendingUpdateMessageManager.cancel(messageId: message.id)
            } else if let media = media as? TelegramMediaFile {
                messageMediaFileCancelInteractiveFetch(context: context, messageId: message.id, file: media)
                if let resource = media.resource as? LocalFileArchiveMediaResource {
                    archiver.remove(.resource(resource))
                }
            } else if let media = media as? TelegramMediaImage {
                chatMessagePhotoCancelInteractiveFetch(account: context.account, photo: media)
            }
        }
        
        parameters?.revealMedia = { [weak self] message in
            self?.chatInteraction.revealMedia(message)
        }
        
        var videoTimestamp: Int32?
        if let parent = message {
            var storedVideoTimestamp: Int32?
            for attribute in parent.attributes {
                if let attribute = attribute as? ForwardVideoTimestampAttribute {
                    videoTimestamp = attribute.timestamp
                } else if let attribute = attribute as? DerivedDataMessageAttribute {
                    if let value = attribute.data["mps"]?.get(MediaPlaybackStoredState.self) {
                        storedVideoTimestamp = Int32(value.timestamp)
                    }
                }
            }
            if let storedVideoTimestamp {
                videoTimestamp = storedVideoTimestamp
            }
        }
        self.parameters?.set_timeCodeInitializer(videoTimestamp.flatMap(Double.init))
    }
    
    
//    override var topInset:CGFloat {
//        return 4
//    }
    
    public var mediaBubbleCornerInset: CGFloat {
        return 1
    }
    
    public override var bubbleFrame: NSRect {
        return fullFilledBubbleFrame(super.bubbleFrame, mediaBubbleCornerInset: self.mediaBubbleCornerInset)
    }
    
    public override var defaultContentTopOffset: CGFloat {
        if isBubbled && !hasBubble {
            return 2
        }
        return super.defaultContentTopOffset
    }
    
//    override var topInset: CGFloat {
//        return 4
//    }

    public var hasUpsideSomething: Bool {
        return authorText != nil || replyModel != nil || topicLinkLayout != nil || forwardNameLayout != nil
    }
    
    public override var contentOffset: NSPoint {
        return upsideContentOffset(super.contentOffset, hasUpsideSomething: self.hasUpsideSomething)
    }
    
    
    public override var elementsContentInset: CGFloat {
        if hasBubble && isBubbleFullFilled {
            return bubbleContentInset
        }
        return super.elementsContentInset
    }
    
    
    
    public override var _defaultHeight: CGFloat {
        if hasBubble && isBubbleFullFilled && captionLayouts.isEmpty {
            return contentOffset.y + defaultContentInnerInset - mediaBubbleCornerInset * 2 - 2
        }
        
        return super._defaultHeight
    }
    
    public override var realContentSize: NSSize {
        var size = super.realContentSize
        
        if isBubbleFullFilled {
            size.width -= bubbleContentInset * 2
        }
        return size
    }

    
    public override var instantlyResize: Bool {
        if !captionLayouts.isEmpty && media.isInteractiveMedia {
            return true
        } else {
            return super.instantlyResize
        }
    }
    

    public override var isBubbleFullFilled: Bool {
        if media is TelegramMediaPaidContent {
            return isBubbled
        }
        return (media.isInteractiveMedia || isSticker) && isBubbled
    }
    
    public var positionFlags: LayoutPositionFlags? = nil
    
    public override init(_ initialSize:NSSize, _ chatInteraction:ChatInteraction, _ context: any AccountContextProtocol, _ object: ChatHistoryEntry, theme: TelegramPresentationTheme) {
        
        let message = object.message!
        
        let isIncoming: Bool = message.isIncoming(context.account, object.renderType == .bubble)

        if let media = message.media[0] as? TelegramMediaInvoice, let extended = media.extendedMedia {
            switch extended {
            case .preview:
                fatalError("not supported")
            case .full(let media):
                self.media = media
            }
        } else if let media = message.media[0] as? TelegramMediaStory, let story = message.associatedStories[media.storyId]?.get(Stories.StoredItem.self) {
            switch story {
            case let .item(item):
                if let media = item.media {
                    self.media = media
                } else {
                    self.media = media
                }
            case .placeholder:
                self.media = media
            }
        } else {
            self.media = message.media[0]
        }
        
        
        super.init(initialSize, chatInteraction, context, object, theme: theme)
        
        var canAddCaption: Bool = true
        if let media = media as? TelegramMediaFile, media.isAnimatedSticker || media.isStaticSticker {
            canAddCaption = false
        }
        if media is TelegramMediaDice {
            canAddCaption = false
        }
        
        
        let parameters = ChatMediaGalleryParameters(showMedia: { [weak self] message in
            guard let `self` = self else {return}
            
            if let media = message.media.first as? TelegramMediaStory {
                self.chatInteraction.openStory(message.id, media.storyId)
            } else {
                var type: ChatGalleryAppearType = .history
                if let parameters = self.parameters as? ChatMediaGalleryParameters, parameters.isWebpage {
                    type = .alone
                } else if message.containsSecretMedia {
                    type = .secret
                }
                if self.chatInteraction.mode.isThreadMode, self.chatInteraction.chatLocation.peerId == message.id.peerId {
                    type = .messages([message])
                }
                showChatGallery(context: context, message: message, self.table, self.parameters, type: type, chatMode: self.chatInteraction.mode, chatLocation: self.chatInteraction.chatLocation, contextHolder: self.chatInteraction.contextHolder(), cachedPeerData: self.chatInteraction.presentation.cachedData, analyticsContext: self.chatInteraction.captureAnalyticsContext())
            }
        }, showMessage: { [weak self] message in
            self?.chatInteraction.focusMessageId(nil, .init(messageId: message.id, string: nil), .CenterEmpty)
        }, isWebpage: chatInteraction.isLogInteraction, presentation: .make(for: message, account: context.account, renderType: object.renderType, theme: theme), media: media, automaticDownload: downloadSettings.isDownloable(message), autoplayMedia: object.autoplayMedia, isRevealed: entry.isRevealed)
        
        self.parameters = parameters
        
        self.updateParameters()
        
        var text: String
        var entities: [MessageTextEntity]
        if let media = message.media[0] as? TelegramMediaStory, let story = message.associatedStories[media.storyId]?.get(Stories.StoredItem.self) {
            switch story {
            case let .item(item):
                text = item.text
                entities = item.entities
            case .placeholder:
                text = ""
                entities = []
            }
        } else {
            text = message.text
            entities = message.textEntities?.entities ?? []
        }
                
       
        if !text.isEmpty, canAddCaption {
            
            var caption:NSMutableAttributedString = NSMutableAttributedString()
            _ = caption.append(string: text, color: theme.chat.textColor(isIncoming, object.renderType == .bubble), font: .normal(theme.fontSize))

                       
            var isLoading: Bool = false
            if let translate = entry.additionalData.translate {
                switch translate {
                case .loading:
                    isLoading = true
                case let .complete(toLang):
                    if let attribute = message.translationAttribute(toLang: toLang) {
                        text = attribute.text
                        entities = attribute.entities
                    }
                }
            }
            if let summarize = entry.additionalData.summarize {
                switch summarize {
                case .loading:
                    isLoading = true
                case let .complete(toLang):
                    if let summary = message.summarizeAttribute?.summaryForLang(toLang) {
                        text = summary.text
                        entities = summary.entities
                    }
                }
            }
            
          
            var mediaDuration: Double? = nil
            if let file = message.anyMedia as? TelegramMediaFile, file.isVideo && !file.isAnimated, let duration = file.duration {
                mediaDuration = Double(duration)
            }
            
            
            caption = ChatMessageItem.applyMessageEntities(with: [TextEntitiesMessageAttribute(entities: entities)], for: text, message: message, context: context, fontSize: theme.fontSize, openInfo:chatInteraction.openInfo, botCommand:chatInteraction.sendPlainText, hashtag: chatInteraction.hashtag, applyProxy: chatInteraction.applyProxy, textColor: theme.chat.textColor(isIncoming, object.renderType == .bubble), linkColor: theme.chat.linkColor(isIncoming, object.renderType == .bubble), monospacedPre: theme.chat.monospacedPreColor(isIncoming, entry.renderType == .bubble), monospacedCode: theme.chat.monospacedCodeColor(isIncoming, entry.renderType == .bubble), mediaDuration: mediaDuration, timecode: { [weak self] timecode in
                self?.parameters?.set_timeCodeInitializer(timecode)
                self?.parameters?.showMedia(message)
            }, openBank: chatInteraction.openBank, blockColor: theme.chat.blockColor(context.peerNameColors, message: message, isIncoming: message.isIncoming(context.account, entry.renderType == .bubble), bubbled: entry.renderType == .bubble), isDark: theme.colors.isDark, bubbled: entry.renderType == .bubble, codeSyntaxData: entry.additionalData.codeSyntaxData, loadCodeSyntax: chatInteraction.interactionEnqueueCodeSyntax, openPhoneNumber: chatInteraction.openPhoneNumberContextMenu, openTonAddress: chatInteraction.openTonAddressContextMenu, ignoreLinks: !entry.additionalData.canHighlightLinks && isIncoming).mutableCopy() as! NSMutableAttributedString
            
            caption.removeWhitespaceFromQuoteAttribute()
            
            
            if !(self is ChatVideoMessageItem) {
                
                InlineStickerItem.apply(to: caption, associatedMedia: message.associatedMedia)
                
                let spoilerColor: NSColor
                if entry.renderType == .bubble {
                    spoilerColor = theme.chat.grayText(isIncoming, entry.renderType == .bubble)
                } else {
                    spoilerColor = theme.chat.textColor(isIncoming, entry.renderType == .bubble)
                }
                let isSpoilerRevealed = chatInteraction.presentation.interfaceState.revealedSpoilers.contains(message.id)
                
                let textLayout = FoldingTextLayout.make(caption, context: context, revealed: object.additionalData.quoteRevealed, takeLayout: { [chatInteraction] string in
                    let textLayout = TextViewLayout(string, alignment: .left, selectText: theme.chat.selectText(isIncoming, object.renderType == .bubble), strokeLinks: object.renderType == .bubble, alwaysStaticItems: true, disableTooltips: false, mayItems: !message.isCopyProtected(cachedData: chatInteraction.presentation.cachedData), spoilerColor: spoilerColor, isSpoilerRevealed: isSpoilerRevealed, onSpoilerReveal: { [weak chatInteraction] in
                        chatInteraction?.update({
                            $0.updatedInterfaceState({
                                $0.withRevealedSpoiler(message.id)
                            })
                        })
                    })
                    
                    if let highlightFoundText = object.additionalData.highlightFoundText {
                       if let range = rangeOfSearch(highlightFoundText.query, in: caption.string) {
                           textLayout.additionalSelections = [TextSelectedRange(range: range, color: theme.colors.accentIcon.withAlphaComponent(0.5), def: false)]
                       }
                    }
                    return textLayout
                })
                
                captionLayouts.append(.init(message: message, id: message.stableId, offset: CGPoint(x: 0, y: 0), layout: textLayout, isLoading: isLoading, contentInset: ChatRowItem.defaultContentInnerInset))
                captionLayouts[0].layout.applyRanges(selectManager.findAll(entry.stableId))

            }
            
            let interactions = LinkHooks.shared.globalLinkExecutor()
            
            interactions.copyToClipboard = { text in
                copyToClipboard(text)
                showModalText(for: context.window, text: strings().shareLinkCopied)
            }
            interactions.topWindow = { [weak self] in
                return self?.menuAdditionView ?? .single(nil)
            }
            if let layout = self.captionLayouts.first {
                interactions.menuItems = { [weak self, weak layout] type in
                    if let interactions = self?.chatInteraction, let entry = self?.entry, let layout {
                        return chatMenuItems(for: layout.message, entry: entry, textLayout: (layout.layout.merged, type), chatInteraction: interactions)
                    }
                    return .complete()
                }
            }
            
            for textLayout in self.captionLayouts.map ({ $0.layout }) {
                textLayout.set(interactions)
            }
        }
        
        if isBubbleFullFilled  {
            var positionFlags: LayoutPositionFlags = []
            if (captionLayouts.isEmpty && commentsBubbleData == nil) || (invertMedia && commentsBubbleData == nil), factCheckLayout == nil {
                positionFlags.insert(.bottom)
                positionFlags.insert(.left)
                positionFlags.insert(.right)
            }
            if !hasUpsideSomething && !invertMedia {
                positionFlags.insert(.top)
                positionFlags.insert(.left)
                positionFlags.insert(.right)
            }
            self.positionFlags = positionFlags
        }

    }
    
    public func openMedia(_ timemark: Int32? = nil) {
        if let message = self.message {
            if let timemark = timemark {
                self.parameters?.set_timeCodeInitializer(Double(timemark))
            }
            self.parameters?.showMedia(message)
        }
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth:CGFloat) -> Bool {
        return super.makeSize(width, oldWidth: oldWidth)
    }
    
    public override func makeContentSize(_ width: CGFloat) -> NSSize {
        let size = ChatLayoutUtils.contentSize(for: media, with: width, hasText: message?.text.isEmpty == false || (isBubbled && (commentsBubbleData != nil || message?.isImported == true)))
        return size
    }
    
    public override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
       
        let caption = self.captionLayouts.first(where: { $0.id == self.firstMessage?.stableId })
        
        if let message = message {
            return chatMenuItems(for: message, entry: entry, textLayout: (caption?.layout.merged, nil), chatInteraction: chatInteraction)
        }
        return super.menuItems(in: location)
    }
    
    public override func canMultiselectTextIn(_ location: NSPoint) -> Bool {
        if let view = view as? ChatMediaView, let content = view.contentNode {
            let point = view.contentView.convert(location, from: nil)
            return !NSPointInRect(point, content.frame)
        }
        return false
    }
    
    public override var identifier: String {
        return super.identifier
    }
   
    public func contentNode() -> ChatMediaContentView.Type {
        if let file = media as? TelegramMediaFile, message?.id.peerId.namespace == Namespaces.Peer.SecretChat, file.isAnimatedSticker, file.stickerReference == nil {
            return ChatFileContentView.self
        }
        return ChatLayoutUtils.contentNode(for: media)
    }
    
    public override func viewClass() -> AnyClass {
        return ChatMediaView.self
    }
    
}



public class ChatMediaView: ChatRowView, ModalPreviewRowViewProtocol {
    
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    
    public func fileAtPoint(_ point: NSPoint) -> (QuickPreviewMedia, NSView?)? {
        if let contentNode = contentNode {
            if contentNode is StickerMediaContentView {
                if let file = contentNode.media as? TelegramMediaFile {
                    let reference = contentNode.parent != nil ? FileMediaReference.message(message: MessageReference(contentNode.parent!), media: file) : FileMediaReference.standalone(media: file)
                    if file.isVideoSticker && !file.isWebm {
                        return (.file(reference, GifPreviewModalView.self), contentNode)
                    } else if file.isAnimatedSticker || file.isWebm {
                        return (.file(reference, AnimatedStickerPreviewModalView.self), contentNode)
                    } else if file.isStaticSticker {
                        return (.file(reference, StickerPreviewModalView.self), contentNode)
                    }
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
                } else if let file = contentNode.media as? TelegramMediaFile {
                    let reference = contentNode.parent != nil ? FileMediaReference.message(message: MessageReference(contentNode.parent!), media: file) : FileMediaReference.standalone(media: file)
                    return (.file(reference, VideoPreviewModalView.self), contentNode)
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
            } else if contentNode is MediaAnimatedStickerView {
                if let file = contentNode.media as? TelegramMediaFile {
                    let reference = contentNode.parent != nil ? FileMediaReference.message(message: MessageReference(contentNode.parent!), media: file) : FileMediaReference.standalone(media: file)
                    return (.file(reference, AnimatedStickerPreviewModalView.self), contentNode)
                }
            }
        }
        
        return nil
    }
    
    public override func previewMediaIfPossible() -> Bool {
        
        return contentNode?.previewMediaIfPossible() ?? false
    }
    
    public override func forceClick(in location: NSPoint) {
        
        if contentNode?.mouseInside() == true {
            let result = previewMediaIfPossible()
            if !result {
                super.forceClick(in: location)
            }
        } else {
            super.forceClick(in: location)
        }
        
    }
    
    
    public override func focusAnimation(_ innerId: AnyHashable?, text: String?) {
        focusAnimation(innerId, text: text, range: nil)
    }

    public override func focusAnimation(_ innerId: AnyHashable?, text: String?, range: NSRange?) {
        super.focusAnimation(innerId, text: text)
        
        guard let item = item as? ChatRowItem else {
            return
        }
        if let text = text, !text.isEmpty {
            self.captionViews.first?.highlight(text: text, color: item.presentation.colors.focusAnimationColor, range: range)
        }
    }
    
    public fileprivate(set) var contentNode:ChatMediaContentView?
    
    
    public override var backgroundColor: NSColor {
        didSet {
            
            contentNode?.backgroundColor = contentColor
        }
    }
    
    public override func shakeView() {
        contentNode?.shake()
    }
    
    
    public override func updateMouse(animated: Bool) {
        super.updateMouse(animated: animated)
        self.contentNode?.updateMouse()
    }
    
    public override func contentFrame(_ item: ChatRowItem) -> NSRect {
        var rect = super.contentFrame(item)
        guard let item = item as? ChatMediaItem else {
            return rect
        }
        if item.isBubbled, item.isBubbleFullFilled {
            rect.origin.x -= item.bubbleContentInset
            if item.hasBubble {
                rect.origin.x += item.mediaBubbleCornerInset
            }
        }
        
        if item.invertMedia {
            if let layout = item.captionLayouts.last {
                rect.origin.y += layout.invertedSize
            }
        }
        
        return rect
    }
    
    public override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview == nil {
            self.contentNode?.willRemove()
        }
    }
    
    public override func set(item:TableRowItem, animated:Bool = false) {
        super.set(item: item, animated: animated)
        if let item:ChatMediaItem = item as? ChatMediaItem {
            if contentNode == nil || !contentNode!.isKind(of: item.contentNode()) || (contentNode?.parent?.stableId != item.message?.stableId && ChatRowView.debugMediaReuse == false) {
                if let view = self.contentNode {
                    performSubviewRemoval(view, animated: animated)
                }
                let node = item.contentNode()
                bindStep("mediaCreate") {
                    self.contentNode = node.init(frame: item.contentSize.bounds)
                    self.addSubview(self.contentNode!)
                }
            }
           
            bindStep("mediaUpdate") {
                self.contentNode?.update(with: item.media, size: item.contentSize, context: item.context, parent:item.message, table:item.table, parameters:item.parameters, animated: animated, positionFlags: item.positionFlags, approximateSynchronousValue: item.approximateSynchronousValue)
            }
            
            
            let transition: ContainedViewLayoutTransition
            if animated {
                transition = .animated(duration: 0.2, curve: .easeOut)
            } else {
                transition = .immediate
            }
            if let contentNode = contentNode {
                transition.updateFrame(view: contentNode, frame: item.contentSize.bounds)
                contentNode.updateLayout(size: item.contentSize, transition: transition)
            }
            
        }
    }
        
    open override func interactionContentView(for innerId: AnyHashable, animateIn: Bool ) -> NSView {
         if let content = self.contentNode?.interactionContentView(for: innerId, animateIn: animateIn) {
            return content
        }
        return self
    }
    
    public override func videoTimebase(for innerId: AnyHashable) -> CMTimebase? {
       return self.contentNode?.videoTimebase()
    }
    public override func applyTimebase(for stableId: AnyHashable, timebase: CMTimebase?) {
        self.contentNode?.applyTimebase(timebase: timebase)
    }
    
    public override func interactionControllerDidFinishAnimation(interactive: Bool, innerId: AnyHashable) {
       
        if interactive {
            self.contentNode?.interactionControllerDidFinishAnimation(interactive: interactive)
        }
    }
    
    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        if let view = contentNode, let item = self.item as? ChatMediaItem {
            transition.updateFrame(view: view, frame: item.contentSize.bounds)
            view.updateLayout(size: item.contentSize, transition: transition)
        }
    }
    
    public override func addAccesoryOnCopiedView(innerId: AnyHashable, view: NSView) {
        guard let item = item as? ChatRowItem, let contentNode = contentNode else {return}

        
        
        
        let rightView = ChatRightView(frame: NSZeroRect)
        rightView.set(item: item, animated: false)
        rightView.blurBackground = self.rightView.blurBackground
        rightView.layer?.cornerRadius = self.rightView.layer!.cornerRadius
        var rect = self.rightView.convert(self.rightView.bounds, to: contentNode)
        
        if contentNode.effectiveVisibleRect.minY < rect.midY && contentNode.effectiveVisibleRect.minY + contentNode.effectiveVisibleRect.height > rect.midY {
            rect.origin.y = contentNode.frame.height - rect.maxY
            rightView.frame = rect
            view.addSubview(rightView)
        }
        
        
        contentNode.addAccesoryOnCopiedView(view: view)
    }


    
    public override var storyMediaControl: NSView? {
        return self.contentNode
    }
}
