import Cocoa
import TGUIKit
import TelegramCore
import TGModernGrowingTextView
import SwiftSignalKit
import Postbox
import ColorPalette
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMediaUtils
import MessageUtils
import MessageTextUtils
import LocalAnimations
import InlineStickerLayer

public class ReplyModel: ChatAccessoryModel {

    private let parent: Message?
    private let replyMessageId: MessageId
    private(set) var replyMessage:Message?
    private var disposable:MetaDisposable = MetaDisposable()
    private let isPinned:Bool
    private var previousMedia: Media?
    private var isLoading: Bool = false
    private let fetchDisposable = MetaDisposable()
    private let makesizeCallback:(()->Void)?
    private let autodownload: Bool
    private let headerAsName: Bool
    private let customHeader: String?
    private let translate: ChatLiveTranslateContext.State.Result?
    private let forceClassic: Bool
    private(set) var pollIcon: CGImage?
    private let quote: EngineMessageReplyQuote?
    private let innerSubject: EngineMessageReplyInnerSubject?
    public init(message: Message?, replyMessageId:MessageId, context: any AccountContextProtocol, replyMessage:Message? = nil, quote: EngineMessageReplyQuote? = nil, innerSubject: EngineMessageReplyInnerSubject? = nil, isPinned: Bool = false, autodownload: Bool = false, presentation: ChatAccessoryPresentation? = nil, headerAsName: Bool = false, customHeader: String? = nil, drawLine: Bool = true, makesizeCallback: (()->Void)? = nil, dismissReply: (()->Void)? = nil, translate: ChatLiveTranslateContext.State.Result? = nil, forceClassic: Bool = false) {
        self.parent = message
        self.replyMessageId = replyMessageId
        self.isPinned = isPinned
        self.makesizeCallback = makesizeCallback
        self.autodownload = autodownload
        self.replyMessage = replyMessage
        self.headerAsName = headerAsName
        self.customHeader = customHeader
        self.translate = translate
        self.forceClassic = forceClassic
        self.quote = quote
        self.innerSubject = innerSubject
        super.init(context: context, presentation: presentation, drawLine: drawLine)
        
      
        let messageViewSignal: Signal<Message?, NoError> = context.account.postbox.messageView(replyMessageId)
        |> map {
            $0.message
        } |> deliverOnMainQueue
        
        if let replyMessage = replyMessage {
            make(with :replyMessage, display: false)
            self.nodeReady.set(.single(true))
        } else {
            make(with: nil, display: false)
        }
        if replyMessage == nil {
            nodeReady.set(messageViewSignal |> map { [weak self] message -> Bool in
                self?.make(with: message, isLoading: false, display: true)
                if message == nil {
                    dismissReply?()
                }
                return message != nil
             })
        }
       
    }
    
    public override var quoteIcon: CGImage? {
        if quote != nil {
            if self.parent?.replyAttribute?.isQuote == false {
                return super.quoteIcon
            } else {
                return presentation.quoteIcon
            }
        }
        return super.quoteIcon
    }
    
    public override var modelType: ChatAccessoryModel.ModelType {
        if isPinned || forceClassic {
            return .classic
        } else {
            return super.modelType
        }
    }
    
    
    public override weak var view:ChatAccessoryView? {
        didSet {
            updateImageIfNeeded(updatesView: false)
        }
    }
    
    public override var frame: NSRect {
        didSet {
            updateImageIfNeeded()
        }
    }
    
    public override var mediaInset: CGFloat {
        return updatedMedia != nil ? 30 + 6 : 0
    }
    
    deinit {
        disposable.dispose()
        fetchDisposable.dispose()
    }
    
    public func update() {
        self.make(with: replyMessage, isLoading: isLoading, display: true)
    }
    
    public override var updatedMedia: Media? {
        
        let anyMedia: Media? = self.quote?.media ?? (replyMessage?.containsSecretMedia == false ? self.replyMessage?.anyMedia : nil)
        
        if let media = anyMedia {
            if let image = media as? TelegramMediaImage {
                return image
            } else if let file = anyMedia as? TelegramMediaFile, (file.isVideo || file.isSticker || file.isGraphicFile) && !file.isVideoSticker {
                return file
            }
        }
        return nil
    }
    
    private func updateImageIfNeeded(updatesView: Bool = true) {
        if let message = self.replyMessage, let updatedMedia = self.updatedMedia, let view = self.view {
            
            var imageDimensions: CGSize?
            var hasRoundImage = false
            if let image = updatedMedia as? TelegramMediaImage {
                if let representation = largestRepresentationForPhoto(image) {
                    imageDimensions = representation.dimensions.size
                }
            } else if let file = updatedMedia as? TelegramMediaFile {
                if let dimensions = file.dimensions?.size {
                    imageDimensions = dimensions
                } else if let representation = largestImageRepresentation(file.previewRepresentations) {
                    imageDimensions = representation.dimensions.size
                } else if file.isAnimatedSticker {
                    imageDimensions = NSMakeSize(30, 30)
                }
                if file.isInstantVideo {
                    hasRoundImage = true
                }
            }
            
            if let imageDimensions = imageDimensions {
                let boundingSize = CGSize(width: 30.0, height: 30.0)
                let arguments = TransformImageArguments(corners: ImageCorners(radius: 2.0), imageSize: imageDimensions.aspectFilled(boundingSize), boundingSize: boundingSize, intrinsicInsets: NSEdgeInsets())
                
                let imageHost = view.makeAccessoryImage()
                imageHost.accessoryImageFrame = NSRect(origin: NSMakePoint(super.leftInset, self.mediaTopInset), size: boundingSize)
                
                
                let mediaUpdated = true
                
                
                var updateImageSignal: Signal<ImageDataTransformation, NoError>?
                if mediaUpdated {
                    if let image = updatedMedia as? TelegramMediaImage {
                        if message.isMediaSpoilered {
                            updateImageSignal = chatSecretPhoto(account: self.context.account, imageReference: ImageMediaReference.message(message: MessageReference(message), media: image), scale: view.accessoryScale)
                        } else {
                            updateImageSignal = chatMessagePhotoThumbnail(account: self.context.account, imageReference: ImageMediaReference.message(message: MessageReference(message), media: image), scale: view.accessoryScale, synchronousLoad: false)
                        }
                    } else if let file = updatedMedia as? TelegramMediaFile {
                        if file.isVideo {
                            if message.isMediaSpoilered {
                                updateImageSignal = chatSecretMessageVideo(account: self.context.account, fileReference: FileMediaReference.message(message: MessageReference(message), media: file), scale: view.accessoryScale)
                            } else {
                                updateImageSignal = chatMessageVideoThumbnail(account: self.context.account, fileReference: FileMediaReference.message(message: MessageReference(message), media: file), scale: view.accessoryScale, synchronousLoad: false)
                            }
                        } else if file.isAnimatedSticker {
                            updateImageSignal = chatMessageAnimatedSticker(postbox: self.context.account.postbox, file: FileMediaReference.message(message: MessageReference(message), media: file), small: true, scale: view.accessoryScale, size: imageDimensions.aspectFitted(boundingSize), fetched: true, isVideo: file.isVideoSticker)
                        } else if file.isSticker {
                            updateImageSignal = chatMessageSticker(postbox: self.context.account.postbox, file: FileMediaReference.message(message: MessageReference(message), media: file), small: true, scale: view.accessoryScale, fetched: true)
                        } else if let iconImageRepresentation = firstImageRepresentation(file.previewRepresentations) {
                            let tmpImage = TelegramMediaImage(imageId: MediaId(namespace: 0, id: 0), representations: [iconImageRepresentation], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
                            if message.isMediaSpoilered {
                                updateImageSignal = chatSecretPhoto(account: self.context.account, imageReference: ImageMediaReference.message(message: MessageReference(message), media: tmpImage), scale: view.accessoryScale)
                            } else {
                                updateImageSignal = chatWebpageSnippetPhoto(account: self.context.account, imageReference: ImageMediaReference.message(message: MessageReference(message), media: tmpImage), scale: view.accessoryScale, small: true, synchronousLoad: true)
                            }
                        }
                    }
                }
                
                
                if let updateImageSignal = updateImageSignal {
                    
                    imageHost.setAccessoryCachedSignal(cachedMedia(media: updatedMedia, arguments: arguments, scale: System.backingScale))

                    
                    imageHost.setAccessorySignal(updateImageSignal, cacheImage: { [weak updatedMedia] result in
                        if let updatedMedia = updatedMedia {
                            cacheMedia(result, media: updatedMedia, arguments: arguments, scale: System.backingScale)
                        }
                    })
                    
                    if let media = updatedMedia as? TelegramMediaImage {
                        self.fetchDisposable.set(chatMessagePhotoInteractiveFetched(account: self.context.account, imageReference: ImageMediaReference.message(message: MessageReference(message), media: media)).start())
                    }
                    
                    imageHost.setAccessoryArguments(arguments)
                    if hasRoundImage {
                        imageHost.accessoryImageCornerRadius = 15
                    } else {
                        imageHost.accessoryImageCornerRadius = 0
                    }
                }
            } else {
                view.removeAccessoryImage()
            }
            
            self.previousMedia = updatedMedia
        } else {
            self.view?.removeAccessoryImage()
        }
        if updatesView {
            self.view?.updateModel(self, animated: false)
        }
    }
    
    public func make(with message:Message?, isLoading: Bool = true, display: Bool) -> Void {
        self.replyMessage = message
        self.isLoading = isLoading
        
        var display: Bool = display
        updateImageIfNeeded()

        if let message = message {
            
            
            
           
            
            var title: String? = message.effectiveAuthor?.displayTitle
            if let info = message.forwardInfo, quote == nil {
                title = info.authorTitle
            }
            for attr in message.attributes {
                if let _ = attr as? SourceReferenceMessageAttribute {
                    if let info = message.forwardInfo {
                        title = info.authorTitle
                    }
                    break
                }
            }
            if self.parent?.id == message.id {
                for attr in message.attributes {
                    if let attr = attr as? QuotedReplyMessageAttribute {
                        if let name = attr.authorName {
                            title = name
                        } else if let peerId = attr.peerId, let peer = message.peers[peerId] {
                            title = peer.displayTitle
                        } else {
                            title = ""
                        }
                    }
                }
            }
           
            if modelType == .classic {
                if quote != nil {
                    title = strings().chatReplyQuotePanelTitle(title ?? "")
                } else {
                    title = strings().chatReplyMessagePanelTitle(title ?? "")
                }
            }
            
            
            if isPinned {
                title = strings().chatHeaderPinnedMessage
            }
            
            var resetEntities: Bool = true
            
            var text: NSAttributedString
            if let translate = self.translate, let translateText = message.translationAttribute(toLang: translate.toLang)?.text  {
                text = .initialize(string: translateText, color: theme.colors.text, font: .normal(.text))
            } else {
                if let quote = quote {
                    let quoteText = messageReplyQuoteText(quote)
                    if quoteText.text.isEmpty, let media = quote.media {
                        let message = Message(media, stableId: 0, messageId: replyMessageId)
                        text = chatListText(account: context.account, for: message, isPremium: context.isPremium, isReplied: true)
                    } else {
                        let textAttr: NSMutableAttributedString
                    
                        
                        textAttr = ChatHistoryModelHooks.shared.applyMessageEntities([TextEntitiesMessageAttribute(entities: quoteText.entities)], quoteText.text, nil, context, 13, { _,_, _, _ in }, presentation.enabledText, presentation.enabledText, presentation.enabledText, presentation.enabledText, presentation.app.dark, presentation.app.bubbled).mutableCopy() as! NSMutableAttributedString
                        
                        InlineStickerItem.apply(to: textAttr, associatedMedia: [:], entities: quoteText.entities, isPremium: context.isPremium, ignoreSpoiler: true)
                        text = textAttr
                        resetEntities = false
                    }
                    
                } else {
                    text = chatListText(account: context.account, for: message, isPremium: context.isPremium, isReplied: true, innerSubject: self.innerSubject ?? parent?.replyAttribute?.innerSubject)
                    if message.media.first is TelegramMediaPoll {
                        let subject = self.innerSubject ?? parent?.replyAttribute?.innerSubject
                        let isPollOption: Bool
                        if case .pollOption = subject {
                            isPollOption = true
                        } else {
                            isPollOption = false
                        }
                        let isIncoming = parent?.isIncoming(context.account, presentation.app.bubbled) ?? true
                        if isPollOption {
                            let poll = message.media.first as? TelegramMediaPoll
                            let isMultiple: Bool
                            switch poll?.kind {
                            case let .poll(multipleAnswers):
                                isMultiple = multipleAnswers
                            case let .quiz(multipleAnswers):
                                isMultiple = multipleAnswers
                            default:
                                isMultiple = false
                            }
                            self.pollIcon = presentation.app.chat.pollReplyOptionIcon(isIncoming, presentation.app.bubbled, isMultiple: isMultiple)
                        } else {
                            self.pollIcon = presentation.app.chat.pollReplyIcon(isIncoming, presentation.app.bubbled)
                        }
                        if let mutableText = text.mutableCopy() as? NSMutableAttributedString {
                            let range = mutableText.string.nsstring.range(of: "📊 ")
                            if range.location != NSNotFound {
                                mutableText.replaceCharacters(in: range, with: "")
                            }
                            text = mutableText
                        }
                    } else {
                        self.pollIcon = nil
                    }
                }
            }
            
            
            
            if let header = customHeader {
                self.header = .init(.initialize(string: header, color: presentation.colors.main, font: .medium(.text)), maximumNumberOfLines: 1)
            } else {
                let header = NSMutableAttributedString()
                header.append(string: !isPinned || headerAsName ? title : strings().chatHeaderPinnedMessage, color: presentation.colors.secondary ?? presentation.colors.main, font: .medium(.text))
                
                if let parent = self.parent, parent.id.peerId != replyMessageId.peerId {
                    if let peer = message.peers[message.id.peerId] {
                        if peer.isChannel {
                            header.insert(.embedded(name: "Icon_Reply_Channel", color: presentation.colors.main, resize: false), at: 0)
                        } else if peer.isGroup || peer.isSupergroup {
                            header.append(.embedded(name: "Icon_Reply_Group", color: presentation.colors.main, resize: false))
                            header.append(string: peer.compactDisplayTitle, color: presentation.colors.main, font: .medium(.text))
                        } else if peer.isUser {
                            header.insert(.embedded(name: "Icon_Reply_User", color: presentation.colors.main, resize: false), at: 0)
                        }
                    }
                }
                

                self.header = .init(header, maximumNumberOfLines: 1)
            }
            let attr = NSMutableAttributedString()
            attr.append(text)
            if resetEntities {
                attr.addAttribute(.foregroundColor, value: presentation.enabledText, range: attr.range)
                attr.addAttribute(.font, value: NSFont.normal(.text), range: attr.range)
            }
            
            
            self.message = .init(attr, maximumNumberOfLines: quote != nil && message.replyAttribute == nil && self.modelType == .modern ? 8 : 1, cutout: self.cutout)
        } else {
            self.header = nil
            self.message = .init(.initialize(string: isLoading ? strings().messagesReplyLoadingLoading : strings().messagesDeletedMessage, color: presentation.enabledText, font: .normal(.text)), maximumNumberOfLines: 1, cutout: self.cutout)
            display = true
        }
        
       
        
        if !isLoading {
            measureSize(width, sizeToFit: sizeToFit)
            display = true
        }
        if display {
            self.view?.setFrameSize(self.size)
            //self.setNeedDisplay()
        }
    }
    
    private var _shimm: (NSPoint, CGImage?) = (.zero, nil)
    public override var shimm: (NSPoint, CGImage?) {
        return _shimm
    }

    
}







public class StoryReplyModel: ChatAccessoryModel {

    private let msg:Message
    private let story: Stories.StoredItem
    private var disposable:MetaDisposable = MetaDisposable()
    private var previousMedia: Media?
    private let fetchDisposable = MetaDisposable()
    private let makesizeCallback:(()->Void)?
    private let storyId: StoryId
    public init(message: Message, storyId: StoryId, story:Stories.StoredItem, context: any AccountContextProtocol, presentation: ChatAccessoryPresentation? = nil, makesizeCallback: (()->Void)? = nil) {
        self.makesizeCallback = makesizeCallback
        self.msg = message
        self.storyId = storyId
        self.story = story
        
        super.init(context: context, presentation: presentation, drawLine: true)
        
        self.make(message: message, display: true)
       
    }
    
    public override weak var view:ChatAccessoryView? {
        didSet {
            updateImageIfNeeded()
        }
    }
    
    public override var frame: NSRect {
        didSet {
            updateImageIfNeeded()
        }
    }
    
    public var isUnsupported: Bool {
        if case let .item(item) = self.story, let media = item.media {
            if media is TelegramMediaUnsupported {
                return true
            }
        }
        return false
    }
    
    public override var mediaInset: CGFloat {
        return 36
    }
    public override var cutout: TextViewCutout? {
        let cutoutSize: CGSize = .init(width: 36, height: 18)
        return TextViewCutout(topLeft: cutoutSize)
    }
    
    
    deinit {
        disposable.dispose()
        fetchDisposable.dispose()
    }
    
    public func update() {
        self.make(message: self.msg, display: true)
    }
    
    public override var updatedMedia: Media? {
        if case let .item(item) = self.story, let media = item.media {
            var updatedMedia: Media?
            
            if let image = media as? TelegramMediaImage {
                updatedMedia = image
            } else if let file = media as? TelegramMediaFile, (file.isVideo || file.isSticker || file.isGraphicFile) && !file.isVideoSticker {
                updatedMedia = file
            }
            return updatedMedia
        }
        return nil
    }
    
    private func updateImageIfNeeded() {
        guard let peer = msg.peers[storyId.peerId], let peerReference = PeerReference(peer) else {
            return
        }
       
        if let view = self.view, let media = updatedMedia, case let .item(item) = self.story {
            var imageDimensions: CGSize?
            
            if let image = media as? TelegramMediaImage {
                if let representation = largestRepresentationForPhoto(image) {
                    imageDimensions = representation.dimensions.size
                }
            } else if let file = media as? TelegramMediaFile {
            
                if let dimensions = file.dimensions?.size {
                    imageDimensions = dimensions
                } else if let representation = largestImageRepresentation(file.previewRepresentations) {
                    imageDimensions = representation.dimensions.size
                } else if file.isAnimatedSticker {
                    imageDimensions = NSMakeSize(30, 30)
                }
            }
            
            if let imageDimensions = imageDimensions {
                let boundingSize = CGSize(width: 30.0, height: 30.0)
                let arguments = TransformImageArguments(corners: ImageCorners(radius: 2.0), imageSize: imageDimensions.aspectFilled(boundingSize), boundingSize: boundingSize, intrinsicInsets: NSEdgeInsets())
                
                if view.imageView == nil {
                    view.imageView = TransformImageView()
                }
                view.imageView?.setFrameSize(boundingSize)
                if view.imageView?.superview == nil {
                    view.addSubview(view.imageView!)
                }
                
                view.imageView?.setFrameOrigin(super.leftInset, floorToScreenPixels(System.backingScale, self.topOffset + (max(34, self.size.height) - self.topOffset - boundingSize.height)/2))
                
                
                let mediaUpdated = true
                
                var updateImageSignal: Signal<ImageDataTransformation, NoError>?
                if mediaUpdated {
                    if let image = updatedMedia as? TelegramMediaImage {
                        updateImageSignal = chatMessagePhotoThumbnail(account: self.context.account, imageReference: .story(peer: peerReference, id: item.id, media: image), scale: view.backingScaleFactor, synchronousLoad: false)
                    } else if let file = updatedMedia as? TelegramMediaFile {
                        if file.isVideo {
                            updateImageSignal = chatMessageVideoThumbnail(account: self.context.account, fileReference: .story(peer: peerReference, id: item.id, media: file), scale: view.backingScaleFactor, synchronousLoad: false)
                        } else  if let iconImageRepresentation = firstImageRepresentation(file.previewRepresentations) {
                            let tmpImage = TelegramMediaImage(imageId: MediaId(namespace: 0, id: 0), representations: [iconImageRepresentation], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
                            updateImageSignal = chatWebpageSnippetPhoto(account: self.context.account, imageReference: .story(peer: peerReference, id: item.id, media: tmpImage), scale: view.backingScaleFactor, small: true, synchronousLoad: true)
                        }
                    }
                }
                
                if let updateImageSignal = updateImageSignal, let media = updatedMedia {
                    
                    view.imageView?.setSignal(signal: cachedMedia(media: media, arguments: arguments, scale: System.backingScale), clearInstantly: false)

                    
                    view.imageView?.setSignal(updateImageSignal, animate: true, synchronousLoad: true, cacheImage: { [weak media] result in
                        if let media = media {
                            cacheMedia(result, media: media, arguments: arguments, scale: System.backingScale)
                        }
                    })
                    
                    if let media = media as? TelegramMediaImage {
                        self.fetchDisposable.set(chatMessagePhotoInteractiveFetched(account: self.context.account, imageReference: .story(peer: peerReference, id: story.id, media: media)).start())
                    }
                    
                    view.imageView?.set(arguments: arguments)
                }
            } else {
                view.imageView?.removeFromSuperview()
                view.imageView = nil
            }
            
            self.previousMedia = updatedMedia
        } else {
            self.view?.imageView?.removeFromSuperview()
            self.view?.imageView = nil
        }
        self.view?.updateModel(self, animated: false)
    }
    
    public func make(message: Message, display: Bool) -> Void {
        
        guard let peer = message.peers[storyId.peerId] else {
            return
        }
        
        var display: Bool = display
        updateImageIfNeeded()
        
        let title: String = peer.displayTitle
        let text: NSAttributedString = .initialize(string: isUnsupported ? strings().chatListStoryUnsupported : strings().chatListStory, color: presentation.disabledText, font: .normal(.text))
        self.header = .init(.initialize(string: title, color: presentation.colors.main, font: .medium(.text)), maximumNumberOfLines: 1)
        self.message = .init(text, maximumNumberOfLines: 1, cutout: cutout)
        
        measureSize(width, sizeToFit: sizeToFit)
        display = true

        if display {
            self.view?.setFrameSize(self.size)
            self.setNeedDisplay()
        }
    }
    
    public override func measureSize(_ width: CGFloat = 0, sizeToFit: Bool = false) {
        super.measureSize(width, sizeToFit: sizeToFit)
    }
    
    private var _shimm: (NSPoint, CGImage?) = (.zero, nil)
    public override var shimm: (NSPoint, CGImage?) {
        return _shimm
    }
}



public class SummarizeReplyModel: ChatAccessoryModel {

    private let messageId: MessageId
    public let dismiss: ()->Void
    public let showInfo: ()->Void

    public init(messageId: MessageId, context: any AccountContextProtocol, presentation: ChatAccessoryPresentation? = nil, dismiss: @escaping ()->Void) {
        self.messageId = messageId
        self.dismiss = dismiss
        self.showInfo = { [weak context] in
            if let context = context {
                ChatHistoryModelHooks.shared.showAboutCocoonModal(context)
            }
        }
        super.init(context: context, presentation: presentation, drawLine: true)
        self.isSummarize = true
        make()
    }

    private func make() {
        self.header = .init(.initialize(string: strings().aiSummaryTitle, color: presentation.colors.main, font: .medium(.text)), maximumNumberOfLines: 1)
        self.message = .init(.initialize(string: strings().aiSummaryClickToSeeOriginal, color: presentation.colors.main.withAlphaComponent(0.8), font: .normal(.text)), maximumNumberOfLines: 1)
        measureSize(width, sizeToFit: sizeToFit)
    }
}

public class ExpiredStoryReplyModel: ChatAccessoryModel {

    private let msg:Message
    private var disposable:MetaDisposable = MetaDisposable()
    private var previousMedia: Media?
    private let fetchDisposable = MetaDisposable()
    private let makesizeCallback:(()->Void)?
    private let storyId: StoryId
    private let bubbled: Bool
    public init(message: Message, storyId: StoryId, bubbled: Bool, context: any AccountContextProtocol, presentation: ChatAccessoryPresentation? = nil, makesizeCallback: (()->Void)? = nil) {
        self.makesizeCallback = makesizeCallback
        self.msg = message
        self.bubbled = bubbled
        self.storyId = storyId
        super.init(context: context, presentation: presentation, drawLine: true)
        
        self.make(message: message, display: true)
       
    }
    
    
    deinit {
        disposable.dispose()
        fetchDisposable.dispose()
    }
    
    public func update() {
        self.make(message: self.msg, display: true)
    }
    
    public func make(message: Message, display: Bool) -> Void {
        
        guard let peer = message.peers[storyId.peerId] else {
            return
        }
                
        let title: String = peer.displayTitle
        let text: NSMutableAttributedString = .init()
        text.append(string: clown_space, color: presentation.disabledText, font: .normal(.text))
        text.append(string: strings().chatReplyExpiredStory, color: presentation.disabledText, font: .normal(.text))
        

        let file = LocalAnimatedSticker.expired_story.monochromeFile
        
        text.addAttribute(TextInputAttributes.embedded, value: InlineStickerItem(source: .attribute(.init(fileId: file.fileId.id, file: file, emoji: clown))), range: NSMakeRange(0, 2))


        
        self.header = .init(.initialize(string: title, color: presentation.colors.main, font: .medium(.text)), maximumNumberOfLines: 1)
        self.message = .init(text, maximumNumberOfLines: 1)
        
        measureSize(width, sizeToFit: sizeToFit)
        
    }
    
    public override func measureSize(_ width: CGFloat = 0, sizeToFit: Bool = false) {
        super.measureSize(width, sizeToFit: sizeToFit)
    }
    
    private var _shimm: (NSPoint, CGImage?) = (.zero, nil)
    public override var shimm: (NSPoint, CGImage?) {
        return _shimm
    }

    
}




