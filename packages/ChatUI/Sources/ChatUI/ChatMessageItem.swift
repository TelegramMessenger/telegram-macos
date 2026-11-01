import Cocoa
import TGUIKit
import TelegramCore
import InAppVideoServices
import Postbox
import SwiftSignalKit
import InAppSettings
import TGModernGrowingTextView
import Strings
import InputView
import ColorPalette
import TelegramMedia
import ChatHistoryModel
import ChatModeTypes
import ExternalVideoUtils
import InputTextView
import LocalAnimations
import Localization
import MessageUtils
import MessageTextUtils
import TelegramContext
import TelegramMediaUtils
import TelegramTheme
import TelegramUtils
import InlineStickerLayer


private func openCalendarWithEvent(date: Date, title: String) {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withColonSeparatorInTime]
    formatter.timeZone = TimeZone.current

    let startDate = formatter.string(from: date).replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "")
    let endDate = formatter.string(from: date.addingTimeInterval(3600)).replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "")

    let escapedTitle = title.replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: "\n", with: "\\n")

    let icsContent = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//Telegram//macOS//EN",
        "BEGIN:VEVENT",
        "DTSTART:\(startDate)",
        "DTEND:\(endDate)",
        "SUMMARY:\(escapedTitle)",
        "END:VEVENT",
        "END:VCALENDAR"
    ].joined(separator: "\r\n")

    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("telegram_event_\(UUID().uuidString).ics")

    do {
        try icsContent.write(to: tempURL, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(tempURL)
    } catch {
    }
}

private let _streamingStates = Atomic<[MessageId: WeakReference<FoldingTextLayout.StreamingState>]>(value: [:])

public class ChatMessageItem: ChatRowItem {
    public private(set) var messageText:NSAttributedString
    public private(set) var textLayout: FoldingTextLayout
    private var relativeDateTimer: RelativeDateUpdateTimer?
        
    
    public var isFragmentAd: Bool {
        if let adAttribute = message?.adAttribute {
            return adAttribute.canReport
        } else {
            return false
        }
    }
    
    public var webpageAboveContent: Bool {
        if let attr = message?.webpagePreviewAttribute, self.webpageLayout != nil {
            if attr.leadingPreview {
                return true
            }
        }
        return false
    }
    
    public override func tableViewDidUpdated() {
        webpageLayout?.table = self.table
    }
    
    public override var isSharable: Bool {
        if let webpage = webpageLayout {
            if webpage.content.type == "proxy" {
                return true
            }
        }
        return super.isSharable
    }
    
    public override var isBubbleFullFilled: Bool {
        return containsBigEmoji || isUnsupportedCard || super.isBubbleFullFilled
    }

    public override var isStateOverlayLayout: Bool {
        return (containsBigEmoji || isUnsupportedCard) && renderType == .bubble || super.isStateOverlayLayout
    }

    public override var bubbleContentInset: CGFloat {
        return (containsBigEmoji || isUnsupportedCard) && renderType == .bubble ? 0 : super.bubbleContentInset
    }

    public override var rightSize: NSSize {
        if isUnsupportedCard, renderType == .bubble {
            return .zero
        }
        return super.rightSize
    }
    
    public override var defaultContentTopOffset: CGFloat {
        if isBubbled && !hasBubble {
            return 2
        }
        return super.defaultContentTopOffset
    }
    public override var contentOffset: NSPoint {
        var offset = super.contentOffset
        if isBubbled, isAdRow {
            offset.y += 2
        }
        return offset
    }

    public override var height: CGFloat {
        var height = super.height
        if isBubbled, isAdRow {
            height += 3
        }
        return height
    }
    
    public override var hasBubble: Bool {
        get {
            if containsBigEmoji || isUnsupportedCard {
                return false
            } else {
                return super.hasBubble
            }
        }
        set {
            super.hasBubble = newValue
        }
    }

    public let containsBigEmoji: Bool

    /// Mirrors `containsBigEmoji`: a stored flag rather than `unsupported`, because the layout overrides
    /// above are consulted from inside `ChatRowItem.init` — before `entry` is reachable through `self`.
    public let isUnsupportedCard: Bool


    public override var isBigEmoji: Bool {
        return containsBigEmoji
    }
    
    public var actionButtonWidth: CGFloat {
        if let webpage = webpageLayout {
            if webpage.isTheme {
                return webpage.size.width
            }
        } else if message?.adAttribute != nil {
            if isBubbled {
                return bubbleFrame.width - bubbleDefaultInnerInset
            }
        }
        
        return self.contentSize.width
    }
    
    public var hasExternalLink: Bool {
        if let adAtribute = message?.adAttribute {
            let inapp = ChatHistoryLink.inApp(for: adAtribute.url.nsstring, context: context)
            switch inapp.chatHistoryInAppLink {
            case .external:
                return true
            default:
                return false
            }
        }
        return false
    }
    
    /// The `[ icon | title + subtitle | Update ]` row standing in for a message this build cannot
    /// render — a frosted panel on the wallpaper, no bubble and no tear. Non-nil exactly when
    /// `unsupported` holds; it owns the update action, so no separate `actionButtonText` is produced.
    public private(set) var papercutLayout: ChatUnsupportedPapercutLayout?

    public var actionButtonText: String? {
        return nil
    }
    
    public override var isEditMarkVisible: Bool {
        return super.isEditMarkVisible
    }
    
    public func invokeAction(morphSource: (() -> NSView?)? = nil) {
        if let webpage = webpageLayout, webpage.openUniqueGift(morphSource: morphSource) {
            return
        }
        if let webpage = webpageLayout {
            let link = ChatHistoryLink.inApp(for: webpage.content.url.nsstring, context: context, messageId: message?.id, openInfo: chatInteraction.openInfo)
            ChatHistoryLink.execute(inapp: link)
        } else if unsupported {
            invokeUpdateApp()
        }
    }

    /// Split out of `invokeAction` so a rich message's inline `.unsupported` block can reach it too:
    /// `unsupported` is false for rich messages by design (ChatRowItem.unsupported), yet the card
    /// inside one offers the same update.
    public func invokeUpdateApp() {
        #if APP_STORE
        LinkHooks.shared.openExternalLink(itunesAppLink, false)
        #else
        ChatHistoryUIHooks.shared.checkForUpdates()
        #endif
    }
    
    
    public private(set) var webpageLayout:WPLayout?
    
    public override init(_ initialSize:NSSize, _ chatInteraction:ChatInteraction,_ context: any AccountContextProtocol, _ entry: ChatHistoryEntry, theme: TelegramPresentationTheme) {
        let relativeDateReferenceTimestamp = Date().timeIntervalSince1970
        
         if let message = entry.message {
             
            
            let isIncoming: Bool = message.isIncoming(context.account, entry.renderType == .bubble)

            var openSpecificTimecodeFromReply:((Double?)->Void)? = nil
            
             
             var text: String = message.text
             var attributes: [MessageAttribute] = message.attributes
             if let translate = entry.additionalData.translate {
                 switch translate {
                 case .loading:
                     self.isTranslateLoading = true
                 case let .complete(toLang: toLang):
                     if let attribute = message.translationAttribute(toLang: toLang) {
                         text = attribute.text
                         attributes = [TextEntitiesMessageAttribute(entities: attribute.entities)]
                     }
                 }
             }
             if let summarize = entry.additionalData.summarize {
                 switch summarize {
                 case .loading:
                     self.isSummarizeLoading = true
                 case let .complete(toLang):
                     if let summary = message.summarizeAttribute?.summaryForLang(toLang) {
                         text = summary.text
                         attributes = [TextEntitiesMessageAttribute(entities: summary.entities)]
                     }
                 }
             }
             
            let messageAttr:NSMutableAttributedString
            if ChatRowItem.isUnsupported(message) {
                // The placeholder is a papercut card built after super.init, not text. The layout stays
                // empty rather than nil because ChatSelectText, lastLineContentWidth and the copy /
                // context-menu paths all dereference `textLayout`.
                messageAttr = NSMutableAttributedString()
            } else {
                
                var mediaDuration: Double? = nil
                var mediaDurationMessage:Message?
                
                var canAssignToReply: Bool = true
                
                if let media = message.anyMedia as? TelegramMediaWebpage {
                    switch media.content {
                    case let .Loaded(content):
                        canAssignToReply = !ExternalVideoLoader.isPlayable(content)
                    default:
                        break
                    }
                }
                
                if canAssignToReply, let reply = message.replyAttribute  {
                    mediaDurationMessage = message.associatedMessages[reply.messageId]
                } else {
                    mediaDurationMessage = message
                }
                if let message = mediaDurationMessage {
                    if let file = message.anyMedia as? TelegramMediaFile, file.isVideo && !file.isAnimated, let duration = file.duration {
                        mediaDuration = Double(duration)
                    } else if let media = message.anyMedia as? TelegramMediaWebpage {
                        switch media.content {
                        case let .Loaded(content):
                            if ExternalVideoLoader.isPlayable(content) {
                                mediaDuration = 10 * 60 * 60
                            }
                        default:
                            break
                        }
                    }
                }
                
                let openInfo:(PeerId, Bool, MessageId?, ChatInitialAction?)->Void = { [weak chatInteraction] peerId, toChat, postId, initialAction in
                    chatInteraction?.openInfoFromMessage(peerId, toChat, postId, toChat ? (initialAction ?? .source(message.id, nil)) : initialAction, message: message)
                }
                
                messageAttr = ChatMessageItem.applyMessageEntities(with: attributes, for: text, message: message, context: context, fontSize: theme.fontSize, openInfo:openInfo, botCommand:chatInteraction.sendPlainText, hashtag: chatInteraction.hashtag, applyProxy: chatInteraction.applyProxy, textColor: theme.chat.textColor(isIncoming, entry.renderType == .bubble), linkColor: theme.chat.linkColor(isIncoming, entry.renderType == .bubble), monospacedPre: theme.chat.monospacedPreColor(isIncoming, entry.renderType == .bubble), monospacedCode: theme.chat.monospacedCodeColor(isIncoming, entry.renderType == .bubble), mediaDuration: mediaDuration, timecode: { timecode in
                    openSpecificTimecodeFromReply?(timecode)
                }, blockColor: theme.chat.blockColor(context.peerNameColors, message: message, isIncoming: isIncoming, bubbled: entry.renderType == .bubble), isDark: theme.colors.isDark, bubbled: entry.renderType == .bubble, codeSyntaxData: entry.additionalData.codeSyntaxData, loadCodeSyntax: chatInteraction.interactionEnqueueCodeSyntax, openPhoneNumber: chatInteraction.openPhoneNumberContextMenu, openTonAddress: chatInteraction.openTonAddressContextMenu, ignoreLinks: !entry.additionalData.canHighlightLinks && isIncoming).mutableCopy() as! NSMutableAttributedString
                
             }
             
            let copy = messageAttr.mutableCopy() as! NSMutableAttributedString
             

            if let peer = message.peers[message.id.peerId] {
                if peer is TelegramSecretChat {
                    ChatHistoryLink.detectLinks(copy, type: [.Links, .Mentions], context: context, color: theme.chat.linkColor(isIncoming, entry.renderType == .bubble), openInfo: chatInteraction.openInfo)
                }
            }

            let containsBigEmoji: Bool
             if message.anyMedia == nil, bigEmojiMessage(context.sharedContext.baseSettings, message: message), entry.additionalData.eventLog == nil {
                containsBigEmoji = true
                switch copy.string.count {
                case 1:
                    copy.addAttribute(.font, value: NSFont.normal(theme.fontSize * 8), range: copy.range)
                case 2:
                    copy.addAttribute(.font, value: NSFont.normal(theme.fontSize * 7), range: copy.range)
                case 3:
                    copy.addAttribute(.font, value: NSFont.normal(theme.fontSize * 6), range: copy.range)
                case 4:
                    copy.addAttribute(.font, value: NSFont.normal(theme.fontSize * 5), range: copy.range)
                case 5:
                    copy.addAttribute(.font, value: NSFont.normal(theme.fontSize * 4), range: copy.range)
                case 6:
                    copy.addAttribute(.font, value: NSFont.normal(theme.fontSize * 3), range: copy.range)
                default:
                    copy.addAttribute(.font, value: NSFont.normal(theme.fontSize * 2), range: copy.range)
                }
            } else {
                containsBigEmoji = false
            }
            
            self.containsBigEmoji = containsBigEmoji
            self.isUnsupportedCard = ChatRowItem.isUnsupported(entry.message)

            
            if message.flags.contains(.Failed) || message.flags.contains(.Unsent) || message.flags.contains(.Sending) {
                ChatHistoryLink.detectLinks(copy, type: [.Links, .Mentions, .Hashtags, .Commands], context: context, color: theme.chat.linkColor(isIncoming, entry.renderType == .bubble), openInfo: chatInteraction.openInfo, hashtag: { _ in }, command: { _ in }, applyProxy: chatInteraction.applyProxy)
            }
           
           
             
             InlineStickerItem.apply(to: copy, associatedMedia: message.associatedMedia)

//             copy.fixUndefinedEmojies()

             
             
             
             let spoilerColor: NSColor
             if entry.renderType == .bubble {
                 spoilerColor = theme.chat.grayText(isIncoming, entry.renderType == .bubble)
             } else {
                 spoilerColor = theme.chat.textColor(isIncoming, entry.renderType == .bubble)
             }
             let isSpoilerRevealed = chatInteraction.presentation.interfaceState.revealedSpoilers.contains(message.id)
             
             copy.removeWhitespaceFromQuoteAttribute()

             
             if let _ = message.adAttribute {
                 messageText = .init()
             } else  if let text = message.restrictedText(context.contentSettings) {
                 self.messageText = .initialize(string: text, color: theme.colors.grayText, font: .italic(theme.fontSize))
             } else {
                 self.messageText = copy
             }
             
             
             let isRichMessage = message.attributes.contains(where: { $0 is RichTextMessageAttribute })
             let isStreaming = !isRichMessage && message.attributes.contains(where: { $0 is TypingDraftMessageAttribute }) && message.adAttribute == nil
             let existingState: FoldingTextLayout.StreamingState?
             if isStreaming, let state = _streamingStates.with({ $0[message.id]?.value }), self.messageText.string.hasPrefix(state.previousString) {
                 existingState = state
             } else {
                 existingState = nil
             }

             textLayout = FoldingTextLayout.make(self.messageText, context: context, revealed: entry.additionalData.quoteRevealed, takeLayout: { [chatInteraction] string in
                 let textLayout = TextViewLayout(string, selectText: theme.chat.selectText(isIncoming, entry.renderType == .bubble), strokeLinks: entry.renderType == .bubble && !containsBigEmoji, alwaysStaticItems: true, disableTooltips: false, mayItems: !message.isCopyProtected(cachedData: chatInteraction.presentation.cachedData), spoilerColor: spoilerColor, isSpoilerRevealed: isSpoilerRevealed, onSpoilerReveal: { [weak chatInteraction] in
                     chatInteraction?.update({
                         $0.updatedInterfaceState({
                             $0.withRevealedSpoiler(message.id)
                         })
                     })
                 })
                 textLayout.mayBlocked = true

                 if let highlightFoundText = entry.additionalData.highlightFoundText {
                    if let range = rangeOfSearch(highlightFoundText.query, in: string.string) {
                        textLayout.additionalSelections = [TextSelectedRange(range: range, color: theme.colors.accentIcon.withAlphaComponent(0.5), def: false)]
                    }
                 }

                 return textLayout
             }, appendingAnimation: isStreaming, streamingState: existingState)

             if isStreaming {
                 let streamingState = textLayout.streamingState
                 _ = _streamingStates.modify { states in
                     var states = states.filter { $0.value.value != nil }
                     states[message.id] = WeakReference(value: streamingState)
                     return states
                 }
             } else {
                 _ = _streamingStates.modify { states in
                     var states = states
                     states.removeValue(forKey: message.id)
                     return states
                 }
             }

             textLayout.applyRanges(selectManager.findAll(entry.stableId))

            
            var media = message.anyMedia
            if let game = media as? TelegramMediaGame {
                media = TelegramMediaWebpage(webpageId: MediaId(namespace: 0, id: 0), content: TelegramMediaWebpageContent.Loaded(TelegramMediaWebpageLoadedContent(url: "", displayUrl: "", hash: 0, type: "photo", websiteName: game.name, title: game.name, text: game.description, embedUrl: nil, embedType: nil, embedSize: nil, duration: nil, author: nil, isMediaLargeByDefault: nil, imageIsVideoCover: false, image: game.image, file: game.file, story: nil, attributes: [], instantPage: nil)))
            }
                        
            
            super.init(initialSize, chatInteraction, context, entry, theme: theme)

            self._isBigEmoji = containsBigEmoji

            if self.unsupported {
                self.papercutLayout = ChatUnsupportedPapercutLayout(
                    title: strings().chatUnsupportedMessageTitle,
                    subtitle: strings().chatUnsupportedMessageInfo,
                    action: strings().chatUnsupportedUpdate,
                    style: .make(presentation: theme, isBubbled: entry.renderType == .bubble, tornEdges: false)
                )
            }

             let ignoreWebpage = !entry.additionalData.canHighlightLinks && isIncoming
            
             if let webpage = media as? TelegramMediaWebpage, !ignoreWebpage {
                 switch webpage.content {
                 case let .Loaded(content):
                     var content = content
                     var forceArticle: Bool = false
                     if let instantPage = content.instantPage?._parse() {
                         if instantPage.blocks.count == 3 {
                             switch instantPage.blocks[2] {
                             case .collage, .slideshow:
                                 forceArticle = true
                             default:
                                 break
                             }
                         }
                     }
                     if content.type == "telegram_background" {
                         forceArticle = true
                     }
                     
                     if let story = content.story, let media = message.associatedStories[story.storyId]?.get(Stories.StoredItem.self) {
                         switch media {
                         case let .item(story):
                             if let image = story.media as? TelegramMediaImage {
                                 content = content.withUpdatedImage(image)
                             } else if let file = story.media as? TelegramMediaFile {
                                 content = content.withUpdatedFile(file)
                             }
                         default:
                             break
                         }
                     }
                     var uniqueGift: StarGift.UniqueGift? = nil
                     for attribute in content.attributes {
                         switch attribute {
                         case let .starGift(gift):
                             switch gift.gift {
                             case let .unique(gift):
                                 uniqueGift = gift
                             default:
                                 break
                             }
                         default:
                             break
                         }
                     }
                     
                     if content.file == nil || forceArticle, content.story == nil, uniqueGift == nil {
                         webpageLayout = WPArticleLayout(with: content, context: context, chatInteraction: chatInteraction, parent:message, fontSize: theme.fontSize, presentation: wpPresentation, approximateSynchronousValue: false, downloadSettings: downloadSettings, autoplayMedia: entry.autoplayMedia, theme: theme, mayCopyText: !message.isCopyProtected(cachedData: chatInteraction.presentation.cachedData))
                     } else if content.file != nil || content.image != nil || uniqueGift != nil {
                         webpageLayout = WPMediaLayout(with: content, context: context, chatInteraction: chatInteraction, parent:message, fontSize: theme.fontSize, presentation: wpPresentation, approximateSynchronousValue: false, downloadSettings: downloadSettings, autoplayMedia: entry.autoplayMedia, theme: theme, mayCopyText: !message.isCopyProtected(cachedData: chatInteraction.presentation.cachedData), uniqueGift: uniqueGift)
                     }
                 default:
                     break
                 }
             } else if let adAttribute = message.adAttribute {
                 
                 let content: TelegramMediaWebpageLoadedContent = .init(url: "", displayUrl: "", hash: 0, type: "telegram_ad", websiteName: adAttribute.messageType == .recommended ? strings().chatMessageRecommendedTitle : strings().chatMessageSponsoredTitle, title: message.author?.displayTitle ?? "", text: message.text, embedUrl: nil, embedType: nil, embedSize: nil, duration: nil, author: nil, isMediaLargeByDefault: adAttribute.hasContentMedia, imageIsVideoCover: false, image: message.media.first as? TelegramMediaImage, file: message.media.first as? TelegramMediaFile, story: nil, attributes: [], instantPage: nil)
                 
                 if adAttribute.hasContentMedia {
                     self.webpageLayout = WPMediaLayout(with: content, context: context, chatInteraction: chatInteraction, parent: message, fontSize: theme.fontSize, presentation: wpPresentation, approximateSynchronousValue: false, downloadSettings: downloadSettings, autoplayMedia: entry.autoplayMedia, theme: theme, mayCopyText: true, entities: message.textEntities?.entities, adAttribute: adAttribute)
                 } else {
                     self.webpageLayout = WPArticleLayout(with: content, context: context, chatInteraction: chatInteraction, parent: message, fontSize: theme.fontSize, presentation: wpPresentation, approximateSynchronousValue: false, downloadSettings: downloadSettings, autoplayMedia: entry.autoplayMedia, theme: theme, mayCopyText: true, entities: message.textEntities?.entities, adAttribute: adAttribute)
                 }
                 
             }
             
            (webpageLayout as? WPMediaLayout)?.parameters?.showMedia = { [weak self] message in
                if let webpage = message.media.first as? TelegramMediaWebpage {
                    switch webpage.content {
                    case let .Loaded(content):
                        if let story = content.story {
                            self?.chatInteraction.openStory(message.id, story.storyId)
                            return
                        }
                    default:
                        break
                    }
                } else if let keybaord = message.replyMarkup {
                    if let button = keybaord.rows.first?.buttons.first {
                        switch button.action {
                        case .openWebApp:
                            self?.chatInteraction.requestMessageActionCallback(message.callbackTargetMessageId, true, nil)
                            return
                        default:
                            break
                        }
                    }
                }
                showChatGallery(context: context, message: message, self?.table, (self?.webpageLayout as? WPMediaLayout)?.parameters, type: .alone, chatMode: chatInteraction.mode, chatLocation: chatInteraction.chatLocation, cachedPeerData: chatInteraction.presentation.cachedData)
            }
            
            openSpecificTimecodeFromReply = { [weak self] timecode in
                if let timecode = timecode {
                    var canAssignToReply: Bool = true
                    if let media = message.anyMedia as? TelegramMediaWebpage {
                        switch media.content {
                        case let .Loaded(content):
                            canAssignToReply = !ExternalVideoLoader.isPlayable(content)
                        default:
                            break
                        }
                    }
                    var assignMessage: Message?
                     if canAssignToReply, let reply = message.replyAttribute  {
                        assignMessage = message.associatedMessages[reply.messageId]
                    } else {
                        assignMessage = message
                    }
                    if let message = assignMessage {
                        let id = ChatHistoryEntryId.message(message)
                        if let item = self?.table?.item(stableId: id) as? ChatMediaItem {
                            item.parameters?.set_timeCodeInitializer(timecode)
                            item.parameters?.showMedia(message)
                        } else if let groupInfo = message.groupInfo {
                            let id = ChatHistoryEntryId.groupedPhotos(groupInfo: groupInfo)
                            if let item = self?.table?.item(stableId: id) as? ChatGroupedItem {
                                item.parameters.first?.set_timeCodeInitializer(timecode)
                                item.parameters.first?.showMedia(message)
                            }
                        } else if let item = self?.table?.item(stableId: id) as? ChatMessageItem {
                            if let content = item.webpageLayout?.content {
                                let content = content.withUpdatedYoutubeTimecode(timecode)
                                LinkHooks.shared.openExternalLink(content.url, false)
                            }
                        }
                    }
                }
            }
            
            let interactions: TextViewInteractions = LinkHooks.shared.globalLinkExecutor()
            if let adAttribute = message.adAttribute {
                interactions.processURL = { [weak chatInteraction] link in
                    chatInteraction?.markAdAction(adAttribute.opaqueId, adAttribute.hasContentMedia)
                    LinkHooks.shared.globalLinkExecutor().processURL(link)
                }
            }
            interactions.copy = {
                selectManager.copy(selectManager)
                return !selectManager.isEmpty
            }
            interactions.copyToClipboard = { text in
                copyToClipboard(text)
            }
            interactions.topWindow = { [weak self] in
                if let strongSelf = self {
                    return strongSelf.menuAdditionView
                } else {
                    return .single(nil)
                }
            }
            interactions.menuItems = { [weak self] type in
                if let strongSelf = self, let message = strongSelf.message {
                    return chatMenuItems(for: message, entry: strongSelf.entry, textLayout: (strongSelf.textLayout.merged, type), chatInteraction: strongSelf.chatInteraction)
                }
                return .complete()
            }
            
            interactions.hoverOnLink = { value in
                
            }
            
            textLayout.set(interactions)

            var relativeDateTimestamps: [Int32] = []
            for attribute in message.attributes {
                if let attribute = attribute as? TextEntitiesMessageAttribute {
                    for entity in attribute.entities {
                        if case let .FormattedDate(format, timestamp) = entity.type, case .relative = format {
                            relativeDateTimestamps.append(timestamp)
                        }
                    }
                    break
                }
            }
            self.relativeDateTimer = RelativeDateUpdateTimer(timestamps: relativeDateTimestamps, relativeTo: relativeDateReferenceTimestamp, update: { [weak self] in
                self?.updateRelativeDates()
            })

            return
        }

        fatalError("entry has not message")
    }

    
    public override var ignoreAtInitialization: Bool {
        return message?.adAttribute != nil
    }
    
    public override var isForceRightLine: Bool {
        if actionButtonText != nil || papercutLayout != nil {
            return true
        }
        if textLayout.lastLineIsRtl {
            return true
        }
        if let _ = webpageLayout, !webpageAboveContent || messageText.string.isEmpty {
             return true
        }
        return super.isForceRightLine
    }
    
    
    public override var min_block_width: CGFloat {
        if webpageLayout != nil {
            return 340
        } else {
            return super.min_block_width
        }
    }
    
    
    public private(set) var isTranslateLoading: Bool = false
    public private(set) var isSummarizeLoading: Bool = false
    public override func makeContentSize(_ width: CGFloat) -> NSSize {
        if let papercutLayout = self.papercutLayout {
            papercutLayout.measure(width: width)
            return papercutLayout.size
        }
        let size:NSSize = super.makeContentSize(width)

        webpageLayout?.measure(width: width)
        
        
        let textBlockWidth: CGFloat = isBubbled ? min(webpageLayout?.size.width ?? width, width) : width
       
        textLayout.measure(width: textBlockWidth, isBigEmoji: containsBigEmoji)
        textLayout.updateStreamingStateIfNeeded()
        if isTranslateLoading || isSummarizeLoading {
            textLayout.makeImageBlock(backgroundColor: .blackTransparent)
        }

        let textHeight = textLayout.appendingAnimation ? textLayout.visibleSize.height : textLayout.size.height
        var contentSize = NSMakeSize(max(webpageLayout?.size.width ?? 0, textLayout.size.width), size.height + textHeight)
        
        if let webpageLayout = webpageLayout {
            contentSize.height += webpageLayout.size.height + defaultContentInnerInset
            contentSize.width = max(webpageLayout.size.width, contentSize.width)
            
        }
        if let _ = actionButtonText {
            contentSize.height += actionButtonHeight
            contentSize.width = max(contentSize.width, 200)
        }
        
        
        return contentSize
    }
    
    
    
    public var actionButtonHeight: CGFloat {
        return 36
    }
    
    
    public override var instantlyResize: Bool {
        return true
    }
    
    public override var bubbleFrame: NSRect {
        var frame = super.bubbleFrame
        
        
        
        if isBubbleFullFilled {
            frame.size.width = contentSize.width + additionBubbleInset
            return frame
        }
        
        // `papercutLayout != nil` implies an empty `textLayout`, which would otherwise pass the
        // `< 200` test and stretch the bubble of any unsupported message carrying a keyboard.
        if replyMarkupModel != nil, webpageLayout == nil, papercutLayout == nil, textLayout.size.width < 200 {
            frame.size.width = max(blockWidth, frame.width)
        }
                
        return frame
    }
    
   
    
    public override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        if let message = message {
            return chatMenuItems(for: message, entry: entry, textLayout: (self.textLayout.merged, nil), chatInteraction: self.chatInteraction)
        }
        return super.menuItems(in: location)
        
    }
    
    private func updateRelativeDates() {
        var hasChanges = false
        for block in textLayout.blocks {
            let layout = block.text
            let mutable = layout.attributedString.mutableCopy() as! NSMutableAttributedString
            var replacements: [(NSRange, String, TextViewFormattedDateData)] = []
            mutable.enumerateAttribute(TextInputAttributes.formattedDate, in: NSRange(location: 0, length: mutable.length), options: []) { value, range, _ in
                if let data = value as? TextViewFormattedDateData, data.isRelative {
                    let newText = formatDateTimeEntity(format: .relative, date: data.date)
                    if newText != data.text {
                        replacements.append((range, newText, data))
                    }
                }
            }
            for (range, newText, oldData) in replacements.reversed() {
                let currentAttributes = mutable.attributes(at: range.location, effectiveRange: nil)
                var updatedAttributes = currentAttributes
                updatedAttributes[TextInputAttributes.formattedDate] = TextViewFormattedDateData(text: newText, date: oldData.date, isRelative: true, contextMenuItems: oldData.contextMenuItems)
                mutable.replaceCharacters(in: range, with: NSAttributedString(string: newText, attributes: updatedAttributes))
                hasChanges = true
            }
            if !replacements.isEmpty {
                layout.setAttributedString(mutable)
                if layout.selectedRange.hasSelectText {
                    layout.selectedRange.range = mutable.range.intersection(layout.selectedRange.range) ?? NSMakeRange(NSNotFound, 0)
                }
            }
        }
        if hasChanges {
            let width = textLayout.blocks.first?.text.constrainedWidth ?? 0
            if width > 0 {
                textLayout.measure(width: width)
            }
            redraw(animated: false)
        }
    }

    deinit {
        relativeDateTimer?.invalidate()
    }

    public override func viewClass() -> AnyClass {
        return ChatMessageView.self
    }
    
    public static func applyMessageEntities(with attributes:[MessageAttribute], for sourceText:String, message: Message?, context: any AccountContextProtocol, fontSize: CGFloat, openInfo:@escaping (PeerId, Bool, MessageId?, ChatInitialAction?)->Void, botCommand:@escaping (String)->Void = { _ in }, hashtag:@escaping (String)->Void = { _ in }, applyProxy:@escaping (ProxyServerSettings)->Void = { _ in }, textColor: NSColor = theme.colors.text, linkColor: NSColor = theme.colors.link, monospacedPre:NSColor = theme.colors.monospacedPre, monospacedCode: NSColor = theme.colors.monospacedCode, mediaDuration: Double? = nil, timecode: @escaping(Double?)->Void = { _ in }, openBank: @escaping(String)->Void = { _ in }, underlineLinks: Bool = false, blockColor: PeerNameColors.Colors = .init(main: theme.colors.accent), isDark: Bool, bubbled: Bool, codeSyntaxData: [CodeSyntaxKey : CodeSyntaxResult] = [:], loadCodeSyntax: @escaping(MessageId, NSRange, String, String, ChatInterfaceSyntaxTheme)->Void = { _, _, _, _, _ in }, openPhoneNumber: ((String)->Void)? = nil, openTonAddress: ((String)->Void)? = nil, confirm: Bool = true, ignoreLinks: Bool = false) -> NSAttributedString {
        var sourceEntities: [MessageTextEntity] = []
        for attribute in attributes {
            if let attribute = attribute as? TextEntitiesMessageAttribute {
                sourceEntities = attribute.entities
                break
            }
        }
        let (text, resolvedEntities) = resolveFormattedDateEntities(sourceText, entities: sourceEntities)
        var entities = resolvedEntities

        var fontAttributes: [(NSRange, ChatTextFontAttributes)] = []


        
        let string = NSMutableAttributedString(string: text, attributes: [NSAttributedString.Key.font: NSFont.normal(fontSize), NSAttributedString.Key.foregroundColor: textColor])
        
        let new = addLocallyGeneratedEntities(text, enabledTypes: [.timecode], entities: entities, mediaDuration: mediaDuration)
        var nsString: NSString?
        entities = entities + (new ?? [])
        
        entities = concatMessageAttributes(entities).filter({ entity in
            if ignoreLinks {
                switch entity.type {
                case .Url, .TextUrl, .TextMention, .Email, .PhoneNumber, .BankCard, .TonAddress, .BotCommand, .Mention:
                    return false
                default:
                    return true
                }
            } else {
                if let message, message.peers[message.id.peerId]?.isMonoForum == true {
                    switch entity.type {
                    case .BotCommand:
                        return false
                    default:
                        return true
                    }
                }
                return true
            }
        })
        
        
    
        
        for entity in resolvedEntities {
            guard case .Spoiler = entity.type else {
                continue
            }
            let range = NSMakeRange(entity.range.lowerBound, entity.range.upperBound - entity.range.lowerBound)
            if let range = string.range.intersection(range) {
                string.addAttribute(TextInputAttributes.spoiler, value: true as NSNumber, range: range)
            }
        }
        
        entities = entities.sorted(by: { lhs, rhs in
            return lhs.range.lowerBound > rhs.range.lowerBound
        })
        
        for entity in entities {
            let r = string.trimRange(NSRange(location: entity.range.lowerBound, length: entity.range.upperBound - entity.range.lowerBound))
            
            guard let range = string.range.intersection(r) else {
                continue
            }
            
            switch entity.type {
            case .Url:
                string.addAttribute(NSAttributedString.Key.foregroundColor, value: linkColor, range: range)
                if nsString == nil {
                    nsString = text as NSString
                }
                let link = ChatHistoryLink.inApp(for:nsString!.substring(with: range) as NSString, context:context, messageId: message?.id, openInfo:openInfo, applyProxy: applyProxy)
                string.addAttribute(NSAttributedString.Key.link, value: link, range: range)
                if underlineLinks {
                    string.addAttribute(NSAttributedString.Key.underlineStyle, value: true, range: range)
                }
            case .Email:
                string.addAttribute(NSAttributedString.Key.foregroundColor, value: linkColor, range: range)
                if nsString == nil {
                    nsString = text as NSString
                }
                string.addAttribute(NSAttributedString.Key.link, value: LinkHooks.shared.externalLink("mailto:\(nsString!.substring(with: range))", false), range: range)
                if underlineLinks {
                    string.addAttribute(NSAttributedString.Key.underlineStyle, value: true, range: range)
                }
            case let .TextUrl(url):
                string.addAttribute(NSAttributedString.Key.foregroundColor, value: linkColor, range: range)
                if nsString == nil {
                    nsString = text as NSString
                }
                string.addAttribute(NSAttributedString.Key.link, value: ChatHistoryLink.inApp(for: url as NSString, context: context, messageId: message?.id, openInfo: openInfo, hashtag: hashtag, command: botCommand,  applyProxy: applyProxy, confirm: confirm ? nsString?.substring(with: range).trimmed != url : false), range: range)
                if underlineLinks {
                    string.addAttribute(NSAttributedString.Key.underlineStyle, value: true, range: range)
                }
                string.addAttribute(TextInputAttributes.textUrl, value: TextInputTextUrlAttribute(url: url), range: range)
            case .Bold:
                fontAttributes.append((range, .bold))
                string.addAttribute(TextInputAttributes.bold, value: true as NSNumber, range: range)
            case .Italic:
                fontAttributes.append((range, .italic))
                string.addAttribute(TextInputAttributes.italic, value: true as NSNumber, range: range)
            case .Mention:
                string.addAttribute(NSAttributedString.Key.foregroundColor, value: linkColor, range: range)
                if nsString == nil {
                    nsString = text as NSString
                }
                string.addAttribute(NSAttributedString.Key.link, value: ChatHistoryLink.followResolvedName(link: nsString!.substring(with: range), username: nsString!.substring(with: range), postId:nil, forceProfile: false, context:context, action:nil, callback: openInfo), range: range)
                if underlineLinks {
                    string.addAttribute(NSAttributedString.Key.underlineStyle, value: true, range: range)
                }
            case let .TextMention(peerId):
                string.addAttribute(NSAttributedString.Key.foregroundColor, value: linkColor, range: range)
                string.addAttribute(NSAttributedString.Key.link, value: ChatHistoryLink.peerInfo(link: "", peerId: peerId, action:nil, openChat: false, postId: nil, callback: openInfo), range: range)
                if underlineLinks {
                    string.addAttribute(NSAttributedString.Key.underlineStyle, value: true, range: range)
                }
                string.addAttribute(TextInputAttributes.textMention, value: ChatTextInputTextMentionAttribute(peerId: peerId), range: range)

            case .BotCommand:
                string.addAttribute(NSAttributedString.Key.foregroundColor, value: textColor, range: range)
                if nsString == nil {
                    nsString = text as NSString
                }
                string.addAttribute(NSAttributedString.Key.foregroundColor, value: linkColor, range: range)
                string.addAttribute(NSAttributedString.Key.link, value: ChatHistoryLink.botCommand(nsString!.substring(with: range), botCommand), range: range)
            case .Code:
//                string.addAttribute(.preformattedPre, value: 4.0, range: range)
                fontAttributes.append((range, .monospace))

                string.addAttribute(NSAttributedString.Key.foregroundColor, value: monospacedCode, range: range)
                string.addAttribute(NSAttributedString.Key.link, value: ChatHistoryLink.code(text.nsstring.substring(with: range), {  link in
                    copyToClipboard(link.trimmed)
                    showModalText(for: context.window, text: strings().shareLinkCopied)
                }), range: range)
                string.addAttribute(TextInputAttributes.monospace, value: true as NSNumber, range: range)
            case let .Pre(language: language):
                
                var lg: String = language ?? ""
                
                if lg.isEmpty {
                    lg = strings().contextCopy.lowercased()
                }
                let isIncoming = message?.isIncoming(context.account, bubbled) ?? false
                let color = theme.chat.activityColor(isIncoming, bubbled)

                
                let header: (TextNodeLayout, TextNode)?
                header = TextNode.layoutText(.initialize(string: lg.prefixWithDots(15), color: color, font: .medium(.text)), nil, 1, .end, NSMakeSize(.greatestFiniteMagnitude, .greatestFiniteMagnitude), nil, false, .left)
                
                string.addAttribute(TextInputAttributes.quote, value: TextViewBlockQuoteData(id: Int(arc4random64()), colors: .init(main: color, secondary: nil, tertiary: theme.colors.isDark ? .black : color), isCode: true, space: 4, header: header), range: range)
                string.addAttribute(TextInputAttributes.code, value: language ?? "", range: range)
                fontAttributes.append((range, .monospace))
                string.addAttribute(NSAttributedString.Key.foregroundColor, value: monospacedPre, range: range)
                string.addAttribute(TextInputAttributes.monospace, value: true as NSNumber, range: range)
                
                
                ChatHistoryUIHooks.shared.applyCodeSyntax(string, range, language, message, isIncoming, bubbled, isDark, textColor, fontSize, codeSyntaxData, loadCodeSyntax)

            case .Hashtag:
                string.addAttribute(NSAttributedString.Key.foregroundColor, value: linkColor, range: range)
                if nsString == nil {
                    nsString = text as NSString
                }
                string.addAttribute(NSAttributedString.Key.link, value: ChatHistoryLink.hashtag(nsString!.substring(with: range), hashtag), range: range)
                if underlineLinks {
                    string.addAttribute(NSAttributedString.Key.underlineStyle, value: true, range: range)
                }
            case .Strikethrough:
                string.addAttribute(NSAttributedString.Key.strikethroughStyle, value: true, range: range)
                string.addAttribute(TextInputAttributes.strikethrough, value: true as NSNumber, range: range)
            case .Underline:
                string.addAttribute(NSAttributedString.Key.underlineStyle, value: true, range: range)
                string.addAttribute(TextInputAttributes.underline, value: true as NSNumber, range: range)
            case .BankCard:
                if nsString == nil {
                    nsString = text as NSString
                }
                 string.addAttribute(NSAttributedString.Key.foregroundColor, value: linkColor, range: range)
                string.addAttribute(NSAttributedString.Key.link, value: LinkHooks.shared.callbackLink(nsString!.substring(with: range), { bankCard in
                    openBank(bankCard)
                }), range: range)
            case .PhoneNumber:
                if nsString == nil {
                    nsString = text as NSString
                }
                 string.addAttribute(NSAttributedString.Key.foregroundColor, value: linkColor, range: range)
                string.addAttribute(NSAttributedString.Key.link, value: LinkHooks.shared.callbackLink(nsString!.substring(with: range), { phoneNumber in
                    openPhoneNumber?(phoneNumber)
                }), range: range)
            case .TonAddress:
                if nsString == nil {
                    nsString = text as NSString
                }
                string.addAttribute(NSAttributedString.Key.foregroundColor, value: linkColor, range: range)
                if range.length == 48, let openTonAddress {
                    string.addAttribute(NSAttributedString.Key.link, value: LinkHooks.shared.callbackLink(nsString!.substring(with: range), openTonAddress), range: range)
                }
            case let .BlockQuote(collapsable):
                string.addAttribute(TextInputAttributes.quote, value: TextViewBlockQuoteData(id: Int(arc4random64()), colors: blockColor, space: 4, collapsable: collapsable), range: range)
            case let .CustomEmoji(_, fileId: fileId):
                string.addAttribute(TextInputAttributes.customEmoji, value: TextInputTextCustomEmojiAttribute(fileId: fileId, file: nil, emoji: string.attributedSubstring(from: range).string), range: range)
            case let .FormattedDate(format, date):

                let effectiveFormat = format ?? .full(timeFormat: .long, dateFormat: .long, dayOfWeek: false)
                let formattedDate = formatDateTimeEntity(format: effectiveFormat, date: date)
                let isRelative: Bool
                if case .relative = format {
                    isRelative = true
                } else {
                    isRelative = false
                }
                string.addAttribute(NSAttributedString.Key.foregroundColor, value: linkColor, range: range)
                string.addAttribute(TextInputAttributes.formattedDate, value: TextViewFormattedDateData(text: formattedDate, date: date, isRelative: isRelative, contextMenuItems: {
                    
                    let formattedDate = formatDateTimeEntity(format: format ?? .full(timeFormat: .long, dateFormat: .long, dayOfWeek: false), date: date)

                    var items: [ContextMenuItem] = []
                    items.append(ContextMenuItem(stringForFullDate(timestamp: date), handler: {
                        copyToClipboard(stringForFullDate(timestamp: date))
                        showModalText(for: context.window, text: strings().shareLinkCopied)
                    }, removeTail: false))
                    items.append(ContextSeparatorItem())
                    items.append(ContextMenuItem(strings().chatSendSetReminder, handler: {
                        showModal(with: chatDateSelector(context: context, defaultDate: Date(timeIntervalSince1970: TimeInterval(date)), mode: .schedule(context.peerId), selectedAt: { date, repeatPeriod in
                            
                            
                            if let message {
                                _ = Sender.forwardMessages(messageIds: [message.id], context: context, peerId: context.peerId, replyId: nil, threadId: nil, atDate: date, repeatPeriod: repeatPeriod).start()
                            }
                                                            
                            ChatHistoryUIHooks.shared.navigateToScheduledChat(context.bindings.rootNavigation(), context, .peer(context.peerId))
                            
                            
                        }), for: context.window)
                    }, itemImage: MenuAnimation.menu_schedule_message.value))
                    
                    items.append(ContextMenuItem(strings().chatSendAddToCalendar, handler: {
                        let eventDate = Date(timeIntervalSince1970: TimeInterval(date))
                        openCalendarWithEvent(date: eventDate, title: formattedDate)
                    }, itemImage: MenuAnimation.menu_calendar.value))
                    return items
                }), range: range)
            case let .Custom(type):
                if type == ApplicationSpecificEntityType.Timecode {
                    string.addAttribute(NSAttributedString.Key.foregroundColor, value: linkColor, range: range)
                    if nsString == nil {
                        nsString = text as NSString
                    }
                    let code = parseTimecodeString(nsString!.substring(with: range))
                    
                    var link = ""
                    if let message = message {
                        var peer: Peer?
                        var messageId: MessageId?
                        if let info = message.forwardInfo {
                            peer = info.author
                            messageId = info.sourceMessageId
                        } else {
                            peer = message.effectiveAuthor
                            messageId = message.id
                        }
                        if let peer = peer, let messageId = messageId {
                            if let code = code, peer.isChannel || peer.isSupergroup {
                                let code = Int(round(code))
                                let address = peer.addressName ?? "\(messageId.peerId.id)"
                                link = context.meUrlDisplayPrefix + "\(address)/\(messageId.id)?t=\(code)"
                            }
                        }
                    }
                    
                    string.addAttribute(NSAttributedString.Key.link, value: LinkHooks.shared.callbackLink(link, { _ in
                        timecode(code)
                    }), range: range)

                }
            default:
                break
            }
        }
        for (range, attr) in fontAttributes {
            var font: NSFont?

            switch attr {
            case .monospace, .blockQuote:
                font = .code(fontSize)
            case .italic:
                font = .italic(fontSize)
            case .bold:
                font = .bold(fontSize)
            default:
                break
            }
            if let font = font {
                string.addAttribute(.font, value: font, range: range)
            }
        }

        let boldRanges = fontAttributes.compactMap { range, attr -> NSRange? in
            return attr == .bold ? range : nil
        }
        let italicRanges = fontAttributes.compactMap { range, attr -> NSRange? in
            return attr == .italic ? range : nil
        }
        chatForEachBoldItalicRange(bold: boldRanges, italic: italicRanges) { intersection in
            string.addAttribute(.font, value: NSFont.boldItalic(fontSize), range: intersection)
        }

        return string.copy() as! NSAttributedString
    }

    public override func inset(for text: String, range: NSRange?) -> CGFloat {
        if let rect = self.textLayout.rect(for: text, range: range) {
            return rect.maxY
        } else {
            return super.inset(for: text, range: range)
        }
    }

}
