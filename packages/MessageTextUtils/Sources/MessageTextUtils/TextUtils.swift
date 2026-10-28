import Cocoa
import TelegramCore
import TGCurrencyFormatter
import Postbox
import TGUIKit
import SwiftSignalKit
import CurrencyFormat
import ColorPalette
import InputView
import Localization
import TelegramTheme
import TelegramUtils
import TelegramMediaUtils
import MessageUtils
import TelegramContext
import SecureIdUtils
import InlineStickerLayer

public enum MessageTextMediaViewType {
    case emoji
    case text
    case none
}



public func pullText(from message:Message, mediaViewType: MessageTextMediaViewType = .emoji, messagesCount: Int = 1, notifications: Bool = false, innerSubject: EngineMessageReplyInnerSubject? = nil) -> (string: NSString, justSpoiled: String) {
    var messageText: String = message.text

    if messageText.isEmpty, let rich = message.attributes.compactMap({ $0 as? RichTextMessageAttribute }).first {
        messageText = instantPagePreviewText(rich.instantPage)
    }

    if message.text.isEmpty, message.textEntities?.entities.isEmpty == false {
        return (string: "", justSpoiled: "")
    }
    
    for attr in message.attributes {
        if let attr = attr as? TextEntitiesMessageAttribute {
            for entity in attr.entities {
                switch entity.type {
                case .Spoiler:
                    messageText = messageText.spoiler(NSMakeRange(entity.range.lowerBound, entity.range.upperBound - entity.range.lowerBound))
                default:
                    break
                }
            }
        }
    }
    
    
    if message.id.peerId == servicePeerId || message.id.peerId == verifyCodePeerId, message.flags.contains(.Incoming), !notifications, message.id.namespace == Namespaces.Message.Cloud {
        let regexPattern = #"[\d\-]{3,7}"#
        do {
            let regex = try NSRegularExpression(pattern: regexPattern, options: [])
            let range = NSRange(location: 0, length: messageText.utf16.count)
            
            let matches = regex.matches(in: messageText, range: range)
            for match in matches {
                messageText = messageText.spoiler(match.range)
            }
        } catch {
            print("Error creating regular expression: \(error.localizedDescription)")
        }
    }
    
    let justSpoiled = messageText
    
    for media in message.media {
        switch media {
        case let image as TelegramMediaImage:
            
            if message.id.peerId.namespace == Namespaces.Peer.CloudUser, let timer = message.autoremoveAttribute, timer.timeout < 60 {
                messageText = strings().chatListServiceDestructingPhoto
            } else {
                if !message.text.isEmpty {
                    switch mediaViewType {
                    case .emoji:
                        messageText = ("🖼 " + messageText)
                    case .text:
                        break
                    case .none:
                        break
                    }
                } else if messagesCount == 1, image.video != nil {
                    messageText = strings().chatListLivePhoto
                } else {
                    messageText = strings().chatListPhoto1Other(messagesCount)
                }
            }
        case let dice as TelegramMediaDice:
            messageText = dice.emoji
        case _ as TelegramMediaGiveaway:
            if let forwardInfo = message.forwardInfo, let author = forwardInfo.author {
                messageText = strings().messageGiveawayStartedOther(author.displayTitle)
            } else {
                messageText = strings().messageGiveawayStarted
            }
        case let media as TelegramMediaPaidContent:
            if message.text.isEmpty {
                let hasVideo = media.extendedMedia.contains {
                    switch $0 {
                    case let .full(media):
                        return media is TelegramMediaFile
                    case let .preview(_, _, videoDuration):
                        return videoDuration != nil
                    }
                }
                if hasVideo {
                    messageText = strings().chatListVideo1Other(media.extendedMedia.count)
                } else {
                    messageText = strings().chatListPhoto1Other(media.extendedMedia.count)
                }
            }
        case _ as TelegramMediaGiveawayResults:
            messageText = strings().messageGiveawayResult
        case let fileMedia as TelegramMediaFile:
            if fileMedia.probablySticker {
                messageText = strings().chatListSticker(fileMedia.stickerText?.normalizedEmoji ?? "")
            } else if fileMedia.isVoice {
                if !message.text.isEmpty {
                    messageText = ("🎤" + " " + messageText)
                } else {
                    messageText = strings().chatListVoice
                }
            } else if fileMedia.isInstantVideo {
                messageText = strings().chatListInstantVideo
            } else if fileMedia.isVideo {
                
                if message.id.peerId.namespace == Namespaces.Peer.CloudUser, let timer = message.autoremoveAttribute, timer.timeout < 60 {
                    messageText = strings().chatListServiceDestructingVideo
                } else {
                    if fileMedia.isAnimated {
                        if !messageText.isEmpty {
                             messageText = (strings().chatListGIF + ", " + messageText)
                        } else {
                            messageText = strings().chatListGIF
                        }
                    } else {
                        if !message.text.isEmpty {
                            switch mediaViewType {
                            case .emoji:
                                messageText = ("📹 " + messageText)
                            case .text:
                                break
                            case .none:
                                break
                            }
                        } else {
                            messageText = strings().chatListVideo1Other(messagesCount)
                        }
                    }
                }
                
                
            } else if fileMedia.isMusic  {
                messageText = ("🎵 " + fileMedia.musicText.0 + " - " + fileMedia.musicText.1)
            } else {
                if !message.text.isEmpty {
                    switch mediaViewType {
                    case .emoji:
                        messageText = ("📎 " + messageText)
                    case .text:
                        break
                    case .none:
                        break
                    }
                } else {
                    messageText = fileMedia.fileName ?? "File"
                }
            }
        case _ as TelegramMediaMap:
            messageText = strings().chatListMap
        case _ as TelegramMediaContact:
            messageText = strings().chatListContact
        case let game as TelegramMediaGame:
            messageText = "🎮 \(game.title)"
        case let invoice as TelegramMediaInvoice:
            messageText = invoice.title
        case let poll as TelegramMediaPoll:
            if case let .pollOption(opaqueIdentifier) = innerSubject, let option = poll.options.first(where: { $0.opaqueIdentifier == opaqueIdentifier }) {
                messageText = "📊 \(option.text)"
            } else {
                messageText = "📊 \(poll.text)"
            }
        case let todo as TelegramMediaTodo:
            if case let .todoItem(todoItemId) = innerSubject, let item = todo.items.first(where: { $0.id == todoItemId }) {
                let completed = todo.completions.contains(where: { $0.id == todoItemId })
                if completed {
                    messageText = "✅ \(item.text)"
                } else {
                    messageText = "☑️ \(item.text)"
                }
            } else {
                messageText = "☑️ \(todo.text)"
            }
        case let story as TelegramMediaStory:
            if message.isExpiredStory {
                if story.isMention {
                    if message.flags.contains(.Incoming) {
                        messageText = strings().chatServiceStoryExpiredMentionTextIncoming
                    } else if let peer = message.peers[message.id.peerId] {
                        messageText = strings().chatServiceStoryExpiredMentionTextOutgoing(peer.compactDisplayTitle)
                    }
                } else {
                    messageText = strings().chatListStoryExpired
                }
            } else if let peer = message.peers[message.id.peerId] {
                if story.isMention {
                    if message.flags.contains(.Incoming) {
                        messageText = strings().chatServiceStoryMentioned(peer.compactDisplayTitle)
                    } else {
                        messageText = strings().chatServiceStoryMentionedYou(peer.compactDisplayTitle)
                    }
                } else {
                    messageText = strings().chatListStory
                }
            }
        case let webpage as TelegramMediaWebpage:
            if case let .Loaded(content) = webpage.content {
                if let _ = content.image {
                    switch mediaViewType {
                    case .emoji:
                        messageText = ("🖼 " + messageText)
                    case .text:
                        break
                    case .none:
                        break
                    }
                } else if let file = content.file {
                    if (file.isVideo && !file.isInstantVideo)  {
                        switch mediaViewType {
                        case .emoji:
                            messageText = ("🖼 " + messageText)
                        case .text:
                            break
                        case .none:
                            break
                        }
                    } else if file.isGraphicFile {
                        switch mediaViewType {
                        case .emoji:
                            messageText = ("📹 " + messageText)
                        case .text:
                            break
                        case .none:
                            break
                        }
                    }
                }
            }
        case _ as TelegramMediaUnsupported:
            if messageText.isEmpty {
                messageText = strings().chatMessageUnsupported
            }
        default:
            break
        }
    }
    

    if message.storyAttribute != nil, notifications, message.flags.contains(.Incoming) {
        return (string: strings().notificationStoryReply(messageText).nsstring, justSpoiled: justSpoiled)
    }
    
    return (string: messageText.nsstring, justSpoiled: justSpoiled)
    
}

public func chatListText(account:Account, for message:Message?, messagesCount: Int = 1, renderedPeer:EngineRenderedPeer? = nil, draft:EngineChatList.Draft? = nil, folder: Bool = false, applyUserName: Bool = false, isPremium: Bool = false, isReplied: Bool = false, notifications: Bool = false, innerSubject: EngineMessageReplyInnerSubject? = nil) -> NSAttributedString {
    
    
    if let draft = draft, !draft.text.isEmpty {
        let mutableAttributedText = NSMutableAttributedString()
        _ = mutableAttributedText.append(string: "\(strings().chatListDraft) ", color: theme.colors.redUI, font: .normal(.text))
        
        let textAttr = NSMutableAttributedString()
        _ = textAttr.append(string: draft.text, color: theme.chatList.grayTextColor, font: .normal(.text))
        
        InlineStickerItem.apply(to: textAttr, associatedMedia: [:], entities:  draft.entities, isPremium: isPremium, ignoreSpoiler: true)

        mutableAttributedText.append(textAttr)
        
        mutableAttributedText.setSelected(color: theme.colors.underSelectedColor, range: mutableAttributedText.range)
        
        return mutableAttributedText.trimNewLinesToSpace
    }
        
    if let renderedPeer = renderedPeer {
        if let peer = renderedPeer.peers[renderedPeer.peerId]?._asPeer() as? TelegramSecretChat {
            let subAttr = NSMutableAttributedString()
            switch peer.embeddedState {
            case .terminated:
                _ = subAttr.append(string: strings().chatListSecretChatTerminated, color: theme.chatList.grayTextColor, font: .normal(.text))
            case .handshake:
            _ = subAttr.append(string: strings().chatListSecretChatExKeys, color: theme.chatList.grayTextColor, font: .normal(.text))
            case .active:
                if message == nil {
                    let title:String = renderedPeer.chatMainPeer?._asPeer().displayTitle ?? strings().peerDeletedUser
                    switch peer.role {
                    case .creator:
                        _ = subAttr.append(string: strings().chatListSecretChatJoined(title), color: theme.chatList.grayTextColor, font: .normal(.text))
                    case .participant:
                        _ = subAttr.append(string: strings().chatListSecretChatCreated(title), color: theme.chatList.grayTextColor, font: .normal(.text))
                    }
                    
                }
            }
            subAttr.setSelected(color: theme.colors.underSelectedColor, range: subAttr.range)
            if subAttr.length > 0 {
                return subAttr
            }
        }
    }

    if let message = message {
    
        
           
        
        if message.text.isEmpty, message.media.isEmpty, let rich = message.attributes.compactMap({ $0 as? RichTextMessageAttribute }).first {
            let preview = instantPagePreview(rich.instantPage)
            if !preview.text.isEmpty {
                let attr = NSMutableAttributedString()
                _ = attr.append(string: preview.text, color: theme.chatList.grayTextColor, font: .normal(.text))
                InlineStickerItem.apply(to: attr, associatedMedia: message.associatedMedia, entities: preview.entities, isPremium: isPremium, ignoreSpoiler: true)
                attr.setSelected(color: theme.colors.underSelectedColor, range: attr.range)
                return attr
            }
        }

        if message.text.isEmpty && message.media.isEmpty {
            let attr = NSMutableAttributedString()
            _ = attr.append(string: strings().chatListUnsupportedMessage, color: theme.chatList.grayTextColor, font: .normal(.text))
            attr.setSelected(color: theme.colors.underSelectedColor, range: attr.range)
            return attr
        }
        
        let peer = coreMessageMainPeer(message)
        
        
        var mediaViewType: MessageTextMediaViewType = .emoji
        if !message.containsSecretMedia {
            for media in message.media {
                if let _ = media as? TelegramMediaImage {
                    mediaViewType = .text
                } else if let file = media as? TelegramMediaFile {
                    if (file.isVideo && !file.isInstantVideo) || file.isGraphicFile {
                        mediaViewType = .text
                    }
                } else if let webpage = media as? TelegramMediaWebpage, case let .Loaded(content) = webpage.content {
                    if let _ = content.image {
                        mediaViewType = .text
                    } else if let file = content.file {
                        if (file.isVideo && !file.isInstantVideo) || file.isGraphicFile {
                            mediaViewType = .text
                        }
                    }
                }
            }
        }
        
        let (messageText, justSpoiled) = pullText(from: message, mediaViewType: mediaViewType, messagesCount: messagesCount, notifications: notifications, innerSubject: innerSubject)
        let attributedText: NSMutableAttributedString = NSMutableAttributedString()

        
        if messageText.length > 0 {
            
            if !isReplied {
                if folder, let peer = peer {
                    _ = attributedText.append(string: peer.displayTitle + "\r", color: theme.chatList.peerTextColor, font: .normal(.text))
                }
                if let author = message.author as? TelegramChannel, let peer = peer, peer.isGroup || peer.isSupergroup, applyUserName {
                    var peerText: String = (!message.flags.contains(.Incoming) ? "\(strings().chatListYou)" : author.displayTitle)
                    
                    peerText += (folder ? ": " : "\r")
                    _ = attributedText.append(string: peerText, color: theme.chatList.peerTextColor, font: .normal(.text))
                    _ = attributedText.append(string: messageText as String, color: theme.chatList.grayTextColor, font: .normal(.text))
                } else if let author = message.author as? TelegramUser, let peer = peer, peer as? TelegramUser == nil, !peer.isChannel, applyUserName {
                    var peerText: String = (author.id == account.peerId ? "\(strings().chatListYou)" : author.displayTitle)
                    
                    peerText += (folder ? ": " : "\r")
                    _ = attributedText.append(string: peerText, color: theme.chatList.peerTextColor, font: .normal(.text))
                    _ = attributedText.append(string: messageText as String, color: theme.chatList.grayTextColor, font: .normal(.text))
                } else {
                    _ = attributedText.append(string: messageText as String, color: theme.chatList.grayTextColor, font: .normal(.text))
                }
            } else {
                _ = attributedText.append(string: messageText as String, color: theme.chatList.grayTextColor, font: .normal(.text))
            }
            
            attributedText.setSelected(color: theme.colors.underSelectedColor, range: attributedText.range)
            
            if let media = message.media.first as? TelegramMediaPoll, !notifications {
                InlineStickerItem.apply(to: attributedText, associatedMedia: message.associatedMedia, entities: media.textEntities, isPremium: true, offset: 3)
            }
            if let media = message.media.first as? TelegramMediaTodo, !notifications {
                InlineStickerItem.apply(to: attributedText, associatedMedia: message.associatedMedia, entities: media.textEntities, isPremium: true, offset: 3)
            }
            
//            var replacements:[String: TelegramMediaFile] = [:]
//            replacements["📊"] = LocalAnimatedSticker.chatlist_poll.file
//            replacements["🎮"] = LocalAnimatedSticker.chatlist_game.file
//            replacements["🎵"] = LocalAnimatedSticker.chatlist_music.file
//            replacements["🎤"] = LocalAnimatedSticker.chatlist_voice.file
//
//            for (key, value) in replacements {
//                let range = attributedText.string.nsstring.range(of: key)
//                if range.location == 0, !message.media.isEmpty {
//                    attributedText.insertEmbedded(.embeddedAnimated(value, playPolicy: .once), for: key)
//                }
//            }
           
        } else if let action = message.extendedMedia as? TelegramMediaAction {
            let service = serviceMessageText(message, account:account, isReplied: isReplied)
            let gramTransferText = isReplied || folder ? nil : incomingGramTransferPreviewText(message, accountPeerId: account.peerId, includeDiamond: notifications)
            _ = attributedText.append(string: gramTransferText ?? service.0, color: theme.chatList.grayTextColor, font: .normal(.text))
            attributedText.detectBoldColorInString(with: .normal(.text))
            attributedText.setSelected(color: theme.colors.underSelectedColor, range: attributedText.range)
            
            if case let .paymentSent(currency, _, _, _, _) = action.action {
                if currency == XTR {
                    attributedText.insertEmbedded(.embedded(name: XTR_ICON, color: theme.chatList.grayTextColor, resize: false), for: XTR)
                }
            } else if case let .paymentRefunded(_, currency, _, _, _) = action.action {
                if currency == XTR {
                    attributedText.insertEmbedded(.embedded(name: XTR_ICON, color: theme.chatList.grayTextColor, resize: false), for: XTR)
                }
            }
            
            InlineStickerItem.apply(to: attributedText, associatedMedia: service.2, entities: service.1, isPremium: isPremium)
            
        } else if let media = message.anyMedia as? TelegramMediaExpiredContent {
            let text:String
            switch media.data {
            case .image:
                text = strings().serviceMessageExpiredPhoto
            case .file:
                text = strings().serviceMessageExpiredVideo
            case .voiceMessage:
                text = strings().serviceMessageExpiredVoiceMessage
            case .videoMessage:
                text = strings().serviceMessageExpiredVideoMessage
            }
            _ = attributedText.append(string: text, color: theme.chatList.grayTextColor, font: .normal(.text))
            attributedText.setSelected(color: theme.colors.underSelectedColor,range: attributedText.range)
        }
        
        var effective: Message = message
        if !(message.extendedMedia is TelegramMediaAction) {
            for attribute in message.attributes {
                if let attribute = attribute as? ReplyMessageAttribute, let message = message.associatedMessages[attribute.messageId] {
                    if let action = message.extendedMedia as? TelegramMediaAction {
                        switch action.action {
                        case .pinnedMessageUpdated:
                            effective = message
                        default:
                            break
                        }
                    }
                }
            }
        }
        if !applyUserName {
            let range = attributedText.string.nsstring.range(of: justSpoiled)
        
            if range.location != NSNotFound {
                InlineStickerItem.apply(to: attributedText, associatedMedia: effective.associatedMedia, entities:  effective.entities, isPremium: isPremium, ignoreSpoiler: true, offset: range.location)
                
                var fontAttributes: [(NSRange, ChatTextFontAttributes)] = []
                
                for entity in effective.entities {
                    let lower = entity.range.lowerBound + range.location
                    let upper = entity.range.upperBound + range.location
                    let range = NSRange(location: lower, length: upper - lower)
                    
                    inner: switch entity.type {
                    case .Strikethrough:
                        let intersection = attributedText.range.intersection(range)
                        if let range = intersection {
                            attributedText.addAttribute(.strikethroughStyle, value: true, range: range)
                        }
                    case .Underline:
//                        let intersection = attributedText.range.intersection(range)
//                        if let range = intersection {
//                            attributedText.addAttribute(.underlineStyle, value: true, range: range)
//                        }
                        break
                    case .Bold:
                       // fontAttributes.append((range, .bold))
                        break
                    case .Italic:
                        fontAttributes.append((range, .italic))
                        break
                    case .Code, .Pre:
                        fontAttributes.append((range, .monospace))
                        break
                    default:
                        break inner
                    }
                    
                }
                
                for (i, (range, attr)) in fontAttributes.enumerated() {
                    var font: NSFont?
                    var intersects:[(NSRange, ChatTextFontAttributes)] = []
                    
                    for (j, value) in fontAttributes.enumerated() {
                        if j != i {
                            if let intersection = value.0.intersection(range) {
                                intersects.append((intersection, value.1))
                            }
                        }
                    }
                                
                    switch attr {
                    case .monospace, .blockQuote:
                        font = .code(.text)
                    case .italic:
                        font = .italic(.text)
                    case .bold:
                        font = .bold(.text)
                    default:
                        break
                    }
                    if let font = font {
                        let intersection = attributedText.range.intersection(range)
                        if let range = intersection {
                            attributedText.addAttribute(.font, value: font, range: range)
                        }
                    }
                    
                     for intersect in intersects {
                         var font: NSFont? = nil
                         loop: switch intersect.1 {
                         case .italic:
                             switch attr {
                             case .bold:
                                 font = .boldItalic(.text)
                             default:
                                 break loop
                             }
                         case .bold:
                            switch attr {
                            case .bold:
                                font = .boldItalic(.text)
                            default:
                                break loop
                            }
                         default:
                             break loop
                             
                         }
                         if let font = font {
                             let intersection = attributedText.range.intersection(range)
                             if let range = intersection {
                                 attributedText.addAttribute(.font, value: font, range: range)
                             }
                         }
                     }
                }

                var formattedDateReplacements: [(NSRange, String, Int32, Bool)] = []
                for entity in effective.entities {
                    if case let .FormattedDate(format, date) = entity.type {
                        let effectiveFormat = format ?? .full(timeFormat: .long, dateFormat: .long, dayOfWeek: false)
                        let formattedDate = formatDateTimeEntity(format: effectiveFormat, date: date)
                        let isRelative: Bool
                        if case .relative = format {
                            isRelative = true
                        } else {
                            isRelative = false
                        }
                        let lower = entity.range.lowerBound + range.location
                        let upper = entity.range.upperBound + range.location
                        let entityRange = NSRange(location: lower, length: upper - lower)
                        if let intersection = attributedText.range.intersection(entityRange) {
                            formattedDateReplacements.append((intersection, formattedDate, date, isRelative))
                        }
                    }
                }
                for (entityRange, formattedDate, date, isRelative) in formattedDateReplacements.reversed() {
                    let currentAttributes = attributedText.attributes(at: entityRange.location, effectiveRange: nil)
                    var updatedAttributes = currentAttributes
                    updatedAttributes[TextInputAttributes.formattedDate] = TextViewFormattedDateData(text: formattedDate, date: date, isRelative: isRelative)
                    if isRelative {
                        attributedText.replaceCharacters(in: entityRange, with: NSAttributedString(string: formattedDate, attributes: updatedAttributes))
                    } else {
                        attributedText.addAttributes(updatedAttributes, range: entityRange)
                    }
                }

            }
            return attributedText.trimNewLinesToSpace
        } else {
            return attributedText
        }
        

    }
    return NSAttributedString()
}

func incomingGramTransferPreviewText(_ message: Message, accountPeerId: PeerId, includeDiamond: Bool) -> String? {
    guard message.effectivelyIncoming(accountPeerId) else {
        return nil
    }
    for media in message.media {
        guard let action = media as? TelegramMediaAction, case let .gramTransfer(amount, _, _, _, _) = action.action else {
            continue
        }
        let amountText = (includeDiamond ? "💎" : "") + formatGramsText(amount, maxDecimalPositions: 3)
        if message.id.peerId == servicePeerId {
            return strings().chatServiceGramTransferUnknown(amountText)
        }
        return strings().chatServiceGramTransferIncoming(amountText)
    }
    return nil
}

public func serviceMessageText(_ message:Message, account:Account, isReplied: Bool = false) -> (String, [MessageTextEntity], [MediaId : Media]) {
    
    var authorName:String = ""
    if let displayTitle = message.author?.displayTitle {
        if message.author?.id == account.peerId {
            authorName = strings().chatServiceYou
        } else {
            authorName = displayTitle
        }
    }
    
    
    var text: String = ""
    var entities: [MessageTextEntity] = []
    let media: [MediaId : Media] = [:]
    
    if let media = message.anyMedia as? TelegramMediaExpiredContent {
        switch media.data {
        case .image:
            text = strings().chatListPhoto
        case .file:
            text = strings().chatListVideo
        case .voiceMessage:
            text = strings().chatListVoice
        case .videoMessage:
            text = strings().chatListInstantVideo
        }
        return (text, [], [:])
    }
   
    
    let authorId:PeerId? = message.author?.id
    
    if let action = message.extendedMedia as? TelegramMediaAction, let peer = coreMessageMainPeer(message) {
        switch action.action {
        case let .communityChanged(communityId):
            var communityName = ""
            if let communityId = communityId, let community = message.peers[communityId] as? TelegramCommunity {
                communityName = community.title
            }
            if !communityName.isEmpty {
                text = strings().textUtilsAddedToCommunity(communityName)
            } else {
                text = strings().textUtilsRemovedFromCommunity
            }
        case .joinedViaCommunity:
            if authorId == account.peerId {
                text = strings().textUtilsJoinedViaCommunityYou
            } else {
                text = strings().textUtilsJoinedViaCommunity(authorName)
            }
        case let .addedMembers(peerIds: peerIds):
            if peerIds.first == authorId {
                text = strings().chatServiceGroupAddedSelf(authorName)
            } else {
                text = strings().chatServiceGroupAddedMembers1(authorName, peerDebugDisplayTitles(peerIds, message.peers))
            }
        case .phoneNumberRequest:
            text = strings().chatServicePhoneNumberRequest
        case .channelMigratedFromGroup:
            text = ""
        case let .groupCreated(title: title):
            if peer.isChannel {
                text = strings().chatServiceChannelCreated
            } else {
                text = strings().chatServiceGroupCreated1(authorName, title)
            }
        case .groupMigratedToChannel:
            text = ""
        case .historyCleared:
            text = ""
        case .historyScreenshot:
            text = strings().chatServiceGroupTookScreenshot(authorName)
        case let .joinedByLink(inviter: peerId):
            if peerId == authorId {
                text = strings().chatServiceGroupJoinedByLink(strings().chatServiceYou)
            } else {
                text = strings().chatServiceGroupJoinedByLink(authorName)
            }
        case let .messageAutoremoveTimeoutUpdated(seconds, _):
            if seconds > 0 {
                text = strings().chatServiceSecretChatSetTimer1(authorName, autoremoveLocalized(Int(seconds)))
            } else {
                text = strings().chatServiceSecretChatDisabledTimer1(authorName)
            }
        case let .photoUpdated(image: image):
            if let image = image {
                if image.videoRepresentations.isEmpty {
                    text = peer.isChannel ? strings().chatServiceChannelUpdatedPhoto : strings().chatServiceGroupUpdatedPhoto(authorName)
                } else {
                    text = peer.isChannel ? strings().chatServiceChannelUpdatedVideo : strings().chatServiceGroupUpdatedVideo(authorName)
                }
            } else {
                text = peer.isChannel ? strings().chatServiceChannelRemovedPhoto : strings().chatServiceGroupRemovedPhoto(authorName)
            }
        case .pinnedMessageUpdated:
            if !isReplied {
                var authorName:String = ""
                if let displayTitle = message.author?.displayTitle {
                    authorName = displayTitle
                    if account.peerId == message.author?.id {
                        authorName = strings().chatServiceYou
                    }
                }
                
                var replyMessageText = ""
                for attribute in message.attributes {
                    if let attribute = attribute as? ReplyMessageAttribute, let message = message.associatedMessages[attribute.messageId] {
                        replyMessageText = pullText(from: message).string as String
                    }
                }
                text = strings().chatServiceGroupUpdatedPinnedMessage1(authorName, replyMessageText.prefixWithDots(15))
            } else {
                text = strings().chatServicePinnedMessage
            }
            
        case let .removedMembers(peerIds: peerIds):
            if peerIds.first == authorId {
                text = strings().chatServiceGroupRemovedSelf(authorName)
            } else {
                text = strings().chatServiceGroupRemovedMembers1(authorName, peerCompactDisplayTitles(peerIds, message.peers))
            }

        case let .titleUpdated(title: title):
            text = peer.isChannel ? strings().chatServiceChannelUpdatedTitle(title) : strings().chatServiceGroupUpdatedTitle1(authorName, title)
        case let .phoneCall(callId: _, discardReason: reason, duration: duration, isVideo):
            
            if let duration = duration, duration > 0 {
                if message.author?.id == account.peerId {
                    text = isVideo ? strings().chatListServiceVideoCallOutgoing(.stringForShortCallDurationSeconds(for: duration)) : strings().chatListServiceCallOutgoing(.stringForShortCallDurationSeconds(for: duration))
                } else {
                    text = isVideo ? strings().chatListServiceVideoCallIncoming(.stringForShortCallDurationSeconds(for: duration)) : strings().chatListServiceCallIncoming(.stringForShortCallDurationSeconds(for: duration))
                }
            } else {
                if let reason = reason {
                    let outgoing = !message.flags.contains(.Incoming)
                    
                    switch reason {
                    case .busy:
                        text = outgoing ? (isVideo ? strings().chatListServiceVideoCallCancelled : strings().chatListServiceCallCancelled) : (isVideo ? strings().chatListServiceVideoCallMissed : strings().chatListServiceCallMissed)
                    case .disconnect:
                        text = isVideo ? strings().chatListServiceVideoCallMissed : strings().chatListServiceCallMissed
                    case .hangup:
                        text = outgoing ? (isVideo ? strings().chatListServiceVideoCallCancelled : strings().chatListServiceCallCancelled) : (isVideo ? strings().chatListServiceVideoCallMissed : strings().chatListServiceCallMissed)
                    case .missed:
                        text = outgoing ? (isVideo ? strings().chatListServiceVideoCallCancelled : strings().chatListServiceCallCancelled) : (isVideo ? strings().chatListServiceVideoCallMissed : strings().chatListServiceCallMissed)
                    }
                }
            }
           
        case let .gameScore(gameId: _, score: score):
            var gameName:String = ""
            for attr in message.attributes {
                if let attr = attr as? ReplyMessageAttribute {
                    if let message = message.associatedMessages[attr.messageId], let gameMedia = message.anyMedia as? TelegramMediaGame {
                        gameName = gameMedia.name
                    }
                }
            }
            text = strings().chatListServiceGameScored1Other(Int(score), gameName)
            if let peer = coreMessageMainPeer(message) {
                if peer.isGroup || peer.isSupergroup {
                    text = (message.author?.compactDisplayTitle ?? "") + " " + text
                }
            }
        case let .paymentSent(currency, totalAmount, _,  _, _):
            text = strings().chatListServicePaymentSent(TGCurrencyFormatter.shared().formatAmount(totalAmount, currency: currency))
        case .unknown:
            break
        case .customText(let value, _, _):
            text = value
        case let .botDomainAccessGranted(domain):
            text = strings().chatServiceBotPermissionAllowed(domain)
        case  let .botAppAccessGranted(appName, _):
            text = strings().authSessionsMessageApp(appName ?? "")
        case let .botSentSecureValues(types):
            let permissions = types.map({$0.rawValue}).joined(separator: ", ")
            text = strings().chatServiceSecureIdAccessGranted(peer.displayTitle, permissions)
        case .peerJoined:
            text = strings().chatServicePeerJoinedTelegram(authorName)
        case let .geoProximityReached(fromId, toId, distance):
            let distanceString = stringForDistance(distance: Double(distance))
            if toId == account.peerId {
                text = strings().notificationProximityReachedYou1(message.peers[fromId]?.displayTitle ?? "", distanceString)
            } else if fromId == account.peerId {
                text = strings().notificationProximityYouReached1(message.peers[toId]?.displayTitle ?? "", distanceString)
            } else {
                text = strings().notificationProximityReached1(message.peers[fromId]?.displayTitle ?? "", distanceString, message.peers[toId]?.displayTitle ?? "")
            }
        case let .groupPhoneCall(_, _, scheduledDate, duration):
            if let duration = duration {
                if peer.isChannel {
                    text = strings().chatServiceVoiceChatFinishedChannel1(autoremoveLocalized(Int(duration)))
                } else if authorId == account.peerId {
                    text = strings().chatServiceVoiceChatFinishedYou(autoremoveLocalized(Int(duration)))
                } else {
                    text = strings().chatServiceVoiceChatFinished(authorName, autoremoveLocalized(Int(duration)))
                }
            } else {
                if peer.isChannel {
                    if let scheduledDate = scheduledDate {
                        text = strings().chatListServiceVoiceChatScheduledChannel1(stringForMediumDate(timestamp: scheduledDate))
                    } else {
                        text = strings().chatListServiceVoiceChatStartedChannel1
                    }
                } else if authorId == account.peerId {
                    if let scheduledDate = scheduledDate {
                        text = strings().chatListServiceVoiceChatScheduledYou(stringForMediumDate(timestamp: scheduledDate))
                    } else {
                        text = strings().chatListServiceVoiceChatStartedYou
                    }
                } else {
                    if let scheduledDate = scheduledDate {
                        text = strings().chatListServiceVoiceChatScheduled(authorName, stringForMediumDate(timestamp: scheduledDate))
                    } else {
                        text = strings().chatListServiceVoiceChatStarted(authorName)
                    }
                }
            }
        case  let .inviteToGroupPhoneCall(_, _, peerIds):
            
            var list = ""
            for peerId in peerIds {
                if let peer = message.peers[peerId] {
                    list += peer.displayTitle
                    if peerId != peerIds.last {
                        list += ", "
                    }
                }
            }
            
            if authorId == account.peerId {
                text = strings().chatListServiceVoiceChatInvitationByYou(list)
            } else if peerIds.first == account.peerId {
                text = strings().chatListServiceVoiceChatInvitationForYou(authorName)
            } else {
                text = strings().chatListServiceVoiceChatInvitation(authorName, list)
            }
        case let .setChatTheme(chatTheme):
            
            var emoji: String = ""
            var file: TelegramMediaFile? = nil
            switch chatTheme {
            case let .emoticon(emoticon):
                emoji = emoticon
            case let .gift(starGift, _):
                if case let .unique(uniqueGift) = starGift {
                    for attribute in uniqueGift.attributes {
                        if case let .model(_, fileValue, _, _) = attribute {
                            file = fileValue
                            emoji = clown
                            break
                        }
                    }
                }
            }
            
            if authorId == account.peerId {
                if emoji.isEmpty {
                    text = strings().chatServiceDisabledThemeYou
                } else {
                    text = strings().chatServiceUpdateThemeYou(emoji)
                }
            } else {
                if emoji.isEmpty {
                    text = strings().chatServiceDisabledTheme(authorName)
                } else {
                    text = strings().chatServiceUpdateTheme(authorName, emoji)
                }
            }
            let range = text.nsstring.range(of: clown)
            if range.location != NSNotFound, let file {
                entities.append(.init(range: range.lowerBound ..< range.upperBound, type: .CustomEmoji(stickerPack: nil, fileId: file.fileId.id)))
            }
        case .joinedByRequest:
            if authorId == account.peerId {
                if message.peers[message.id.peerId]?.isChannel == true {
                    text = strings().chatServiceJoinedChannelByRequest
                } else {
                    text = strings().chatServiceJoinedGroupByRequest
                }
            } else {
                if message.peers[message.id.peerId]?.isChannel == true {
                    text = strings().chatServiceUserJoinedChannelByRequest(authorName)
                } else {
                    text = strings().chatServiceUserJoinedGroupByRequest(authorName)
                }
            }
        case let .webViewData(data):
            text = strings().chatServiceWebData(data)
        case let .giftPremium(currency, amount, _, _, _, _, _):
            let formatted: String
            if currency == XTR {
                formatted = strings().starListItemCountOther(Int(amount))
            } else {
                formatted = formatCurrencyAmount(amount, currency: currency)
            }
            if authorId == account.peerId {
                text = strings().chatServicePremiumGiftSentYou(formatted)
            } else {
                text = strings().chatServicePremiumGiftSent(authorName, formatted)
            }
        case .giftCode(_, _, _, _, _, _, _, _, _, _, _):
            if authorId == account.peerId {
                text = strings().chatServiceGiftLinkSent
            } else {
                text = strings().chatServiceGiftLink
            }
        case .giveawayLaunched:
            text = strings().chatServiceGiveawayStarted(authorName)
        case let .topicEdited(components):
            var fileId: Int64?
            if let component = components.first {
                switch component {
                case let .title(title):
                    if authorId == account.peerId {
                        text = strings().chatServiceGroupTopicEditedYouTitle(title)
                    } else {
                        text = strings().chatServiceGroupTopicEditedTitle(authorName, title)
                    }
                case let .iconFileId(iconFileId):
                    fileId = iconFileId
                    if let iconFileId = iconFileId {
                        if authorId == account.peerId {
                            text = strings().chatServiceGroupTopicEditedYouIcon("~~\(iconFileId)~~")
                        } else {
                            text = strings().chatServiceGroupTopicEditedIcon(authorName, "~~\(iconFileId)~~")
                        }
                    } else {
                        if authorId == account.peerId {
                            text = strings().chatServiceGroupTopicEditedYouIconRemoved
                        } else {
                            text = strings().chatServiceGroupTopicEditedIconRemoved(authorName)
                        }
                    }
                case let .isClosed(closed):
                    if authorId == account.peerId {
                        if closed {
                            text = strings().chatServiceGroupTopicEditedYouPaused
                        } else {
                            text = strings().chatServiceGroupTopicEditedYouResumed
                        }
                    } else {
                        if closed {
                            text = strings().chatServiceGroupTopicEditedPaused(authorName)
                        } else {
                            text = strings().chatServiceGroupTopicEditedResumed(authorName)
                        }
                    }
                case let .isHidden(isHidden):
                    if authorId == account.peerId {
                        if isHidden {
                            text = strings().chatServiceGroupTopicEditedYouHided
                        } else {
                            text = strings().chatServiceGroupTopicEditedYouUnhided
                        }
                    } else {
                        if isHidden {
                            text = strings().chatServiceGroupTopicEditedHided(authorName)
                        } else {
                            text = strings().chatServiceGroupTopicEditedUnhided(authorName)
                        }
                    }
                }
            } else {
                var title: String = ""
                for component in components {
                    switch component {
                    case let .title(value):
                        title = value.prefixWithDots(30)
                    case .iconFileId:
                        break
                    case .isClosed:
                        break
                    case .isHidden:
                        break
                    }
                }
                if let fileId = fileId {
                    if authorId == account.peerId {
                        text = strings().chatServiceGroupTopicEditedYouMixed("~~\(fileId)~~", title)
                    } else {
                        text = strings().chatServiceGroupTopicEditedMixed(authorName, "~~\(fileId)~~", title)
                    }
                } else {
                    if authorId == account.peerId {
                        text = strings().chatServiceGroupTopicEditedYouTitle(title)
                    } else {
                        text = strings().chatServiceGroupTopicEditedTitle(authorName, title)
                    }
                }
            }
            let range = text.nsstring.range(of: "~~\(fileId ?? 0)~~")
            if range.location != NSNotFound, let fileId = fileId {
                entities.append(.init(range: range.lowerBound ..< range.upperBound, type: .CustomEmoji(stickerPack: nil, fileId: fileId)))
            }
        case let .topicCreated(title, _, iconFileId):
            let iconText: String?
            if let iconFileId = iconFileId {
                iconText = "~~\(iconFileId)~~"
            } else {
                iconText = nil
            }
            if let iconText = iconText {
                text = strings().chatServiceGroupTopicCreatedIcon(iconText, title)
            } else {
                text = strings().chatServiceGroupTopicCreated(title)
            }
            if let iconText = iconText, let iconFileId = iconFileId {
                let range = text.nsstring.range(of: iconText)
                if range.location != NSNotFound {
                    entities.append(.init(range: range.lowerBound ..< range.upperBound, type: .CustomEmoji(stickerPack: nil, fileId: iconFileId)))
                }
            }
        case .suggestedProfilePhoto:
            if authorId == account.peerId {
                text = strings().chatServiceYouSuggestedPhoto
            } else {
                text = strings().chatServiceSuggestedPhoto(authorName)
            }
        case .attachMenuBotAllowed:
            text = strings().chatServiceBotWriteAllowed
        case let .requestedPeer(_, peerIds):
            if let botPeer = message.peers[message.id.peerId] {
                if peerIds.count == 1, let peer = message.peers[peerIds[0]] {
                    text = strings().chatServicePeerRequested(peer.displayTitle, botPeer.displayTitle)
                } else {
                    let string: String = peerIds.compactMap { message.peers[$0]?.displayTitle }.joined(separator: ", ")
                    text = strings().chatServicePeerRequestedMultiple(string, botPeer.displayTitle)
                }
            }
        case .setChatWallpaper:
            if authorId == account.peerId {
                text = strings().chatServiceYouChangedWallpaper
            } else {
                text = strings().chatServiceChangedWallpaper(authorName)
            }
        case .setSameChatWallpaper:
            if authorId == account.peerId {
                text = strings().chatServiceYouChangedToSameWallpaper
            } else {
                text = strings().chatServiceChangedToSameWallpaper(authorName)
            }
        case .joinedChannel:
            text = strings().chatServiceJoinedChannel
        case let .giveawayResults(winners, unclaimed, stars):
            if winners == 0 {
                text = stars ? strings().chatServiceGiveawayResultsNoWinnersStarsOther(Int(unclaimed)) : strings().chatServiceGiveawayResultsNoWinnersOther(Int(unclaimed))
            } else if unclaimed > 0 {
                text = stars ? strings().chatServiceGiveawayResultsStarsOther(Int(winners)) : strings().chatServiceGiveawayResultsOther(Int(winners))
                let winnersString = stars ? strings().chatServiceGiveawayResultsMixedWinnersStarsOther(Int(winners)) : strings().chatServiceGiveawayResultsMixedWinnersOther(Int(winners))
                let unclaimedString = stars ? strings().chatServiceGiveawayResultsMixedUnclaimedStarsOther(Int(unclaimed)) : strings().chatServiceGiveawayResultsMixedUnclaimedOther(Int(unclaimed))
                text = winnersString + "\n" + unclaimedString
            } else {
                text = stars ? strings().chatServiceGiveawayResultsStarsOther(Int(winners)) : strings().chatServiceGiveawayResultsOther(Int(winners))
            }
        case let .boostsApplied(boosts):
            if message.author?.id == account.peerId {
                if boosts == 1 {
                    text = strings().notificationBoostSingleYou
                } else {
                    let boostsString = strings().notificationBoostTimesOther(Int(boosts), "\(boosts)")
                    text = strings().notificationBoostMultipleYou(boostsString)
                }
            } else {
                let peerName = message.author?.compactDisplayTitle ?? ""
                if boosts == 1 {
                    text = strings().notificationBoostSingle(peerName)
                } else {
                    let boostsString = strings().notificationBoostTimesOther(Int(boosts), "\(boosts)")
                    text = strings().notificationBoostMultiple(peerName, boostsString)
                }
            }
        case let .giftStars(currency, amount, _, _, _, _):
            let formatted = formatCurrencyAmount(amount, currency: currency)
            if authorId == account.peerId {
                text = strings().chatServicePremiumGiftSentYou(formatted)
            } else {
                text = strings().chatServicePremiumGiftSent(authorName, formatted)
            }
        case let .paymentRefunded(_, currency, totalAmount, _, _):
            let peerName = message.author?.compactDisplayTitle ?? ""
            text = strings().chatServiceRefundedBackOther(peerName, currency + TINY_SPACE, Int(totalAmount))
        case let .prizeStars(amount, _, _, _, _):
            text = strings().chatServiceStarsPrize(authorName, strings().channelBoostBoosterStarsOther(Int(amount)))
        case let .starGift(gift, _, _, _, _, _, _, _, _, upgradeStars, _, isPrepaidUpgrade, _, peerId, senderId, _, _, _, upgradeSeparate, auctionAcquired, _, _):

            if let gift = gift.generic {
                var finalPrice = gift.price
                if let upgradeStars, !upgradeSeparate {
                    finalPrice += upgradeStars
                }
                if authorId == account.peerId {
                    if message.id.peerId == account.peerId {
                        text = strings().notificationStarsGiftSelfBought(
                            strings().starListItemCountOther(Int(finalPrice))
                        )
                    } else {
                        if isPrepaidUpgrade, let upgradeStars {
                            text = strings().chatStarsGiftUpgradeSent(
                                strings().starListItemCountOther(Int(upgradeStars))
                            )
                        } else {
                            text = strings().chatStarsGiftSentYou(
                                strings().starListItemCountOther(Int(finalPrice))
                            )
                        }
                    }

                } else {
                    if auctionAcquired {
                        text = strings().notificationStarsGiftSelfAuctionBought(
                            strings().starListItemCountOther(Int(gift.price)))
                    } else if isPrepaidUpgrade, let upgradeStars {
                        text = strings().chatStarsGiftUpgradeSentBy(
                            authorName,
                            strings().starListItemCountOther(Int(upgradeStars))
                        )
                    } else {
                        if let senderId, let author = message.peers[senderId], let peerId = peerId, let toPeer = message.peers[peerId] {
                            text = strings().chatServiceStarGiftChannelSelt(author.displayTitle, toPeer.displayTitle, strings().starListItemCountOther(Int(finalPrice)))
                        } else {
                            text = strings().chatServiceStarGiftSent(authorName, strings().starListItemCountOther(Int(finalPrice)))
                        }
                    }

                }
            } else {
                if authorId == account.peerId {
                    text = strings().chatServiceStarGiftSentYou(strings().starListItemCountOther(Int(gift.generic!.price)))
                } else {
                    text = strings().chatServiceStarGiftSent(authorName, strings().starListItemCountOther(Int(gift.generic!.price)))
                }
            }
        case let .starGiftUnique(gift, isUpgrade, isTransferred, _, _, _, _, isPrepaidUpgrade, _, senderId, _, _, _, _, _, _, _, _, isCrafted, giftText, _, _):

            let authorName = senderId.flatMap { message.peers[$0]?.displayTitle } ?? authorName

            if case let .unique(gift) = gift {
                if let giftText, !giftText.isEmpty {
                    text = giftText
                } else if isCrafted {
                    text = strings().chatServiceCraftedUniqueCollectible
                } else if isTransferred {
                    if authorId == account.peerId {
                        text = strings().notificationStarsGiftTransferYou
                    } else {
                        text = strings().notificationStarsGiftTransfer(authorName)
                    }
                } else if isUpgrade {
                    if authorId == account.peerId {
                        if isPrepaidUpgrade {
                            text = strings().notificationStarsGiftUpgradePrepaidYou(authorName)
                        } else {
                            text = strings().notificationStarsGiftUpgradeYou(authorName)
                        }
                    } else {
                        if isPrepaidUpgrade {
                            text = strings().notificationStarsGiftUpgradePrepaid(authorName)
                        } else if let _ = senderId {
                            text = strings().notificationStarsGiftUpgradeChannel(authorName)
                        } else {
                            text = strings().notificationStarsGiftUpgrade(authorName)
                        }
                    }
                } else {
                    text = strings().chatListTextUniqueGift(gift.title + " #\(gift.number)")
                }
            }
        case let .paidMessagesRefunded(_, stars):
            let starsString = strings().starListItemCountOther(Int(stars))
            if authorId == account.peerId {
                text = strings().notificationPaidMessageRefundYou(starsString, authorName)
            } else {
                text = strings().notificationPaidMessageRefund(authorName, starsString)
            }
        case .paidMessagesPriceEdited(let stars, _):
            let starsString = strings().starListItemCountOther(Int(stars))
            
            if authorId == account.peerId {
                text = strings().notificationPaidMessagePriceChangedYou(starsString)
            } else {
                text = strings().notificationPaidMessagePriceChanged(authorName, starsString)
            }
        case .conferenceCall(_):
            if authorId == account.peerId {
                text = strings().notificationGroupCallOutgoing
            } else {
                text = strings().notificationGroupCallIncoming
            }
        case let .todoCompletions(completed, incompleted):
            
            let todo: Message?
            if let replyAttribute = message.replyAttribute {
                todo = message.associatedMessages[replyAttribute.messageId]
            } else {
                todo = nil
            }
            
            guard let todo, let todoMedia = todo.media.first as? TelegramMediaTodo else {
                break
            }
            
            let marked = !completed.isEmpty ? todoMedia.items.filter({ completed.contains($0.id) }) : todoMedia.items.filter({ incompleted.contains($0.id) })
            
            let makeValues: ([TelegramMediaTodo.Item]) -> (String, [MessageTextEntity]) = { items in
                var resultString = ""
                var entities: [MessageTextEntity] = []
                var offset = 0

                for (index, item) in items.enumerated() {
                    resultString += "'"
                    offset += 1

                    for entity in item.entities {
                        let adjustedRange = (entity.range.lowerBound + offset)..<(entity.range.upperBound + offset)
                        entities.append(MessageTextEntity(range: adjustedRange, type: entity.type))
                    }

                    resultString += item.text
                    offset += item.text.count

                    resultString += "'"
                    offset += 1

                    if index < items.count - 1 {
                        resultString += ", "
                        offset += 2
                    }
                }

                return (resultString, entities)
            }

            var rawString: String

                        
            if !completed.isEmpty {
                if authorId == account.peerId {
                    rawString = strings().chatServiceTodoMarkedDoneYou
                } else {
                    rawString = strings().chatServiceTodoMarkedDone
                }
            } else if !incompleted.isEmpty {
                if authorId == account.peerId {
                    rawString = strings().chatServiceTodoMarkedUndoneYou
                } else {
                    rawString = strings().chatServiceTodoMarkedUndone
                }
            } else {
                rawString = ""
            }
            
            if !rawString.isEmpty {
                
                let values = makeValues(marked)
                
                let valuesRange = rawString.nsstring.range(of: "{values}")
                if valuesRange.location != NSNotFound {
                    rawString = rawString.nsstring.replacingCharacters(in: valuesRange, with: values.0)
                }
                let authorRange = rawString.nsstring.range(of: "{author}")
                if authorRange.location != NSNotFound {
                    rawString = rawString.nsstring.replacingCharacters(in: authorRange, with: authorName)
                }
                
                var offset = valuesRange.location
                if authorRange.location != NSNotFound {
                    offset += (authorName.length - authorRange.length)
                }
                
                for entity in values.1 {
                    entities.append(.init(range: entity.range.lowerBound + offset ..< entity.range.upperBound + offset, type: entity.type))
                }
            }
            text = rawString
        case let .todoAppendTasks(tasks):
            let todo: Message?
            if let replyAttribute = message.replyAttribute {
                todo = message.associatedMessages[replyAttribute.messageId]
            } else {
                todo = nil
            }

            guard let todo, let todoMedia = todo.media.first as? TelegramMediaTodo else {
                break
            }

            let makeValues: ([TelegramMediaTodo.Item]) -> (String, [MessageTextEntity]) = { items in
                var resultString = ""
                var entities: [MessageTextEntity] = []
                var offset = 0

                for (index, item) in items.enumerated() {
                    resultString += "'"
                    offset += 1

                    for entity in item.entities {
                        let adjustedRange = (entity.range.lowerBound + offset)..<(entity.range.upperBound + offset)
                        entities.append(MessageTextEntity(range: adjustedRange, type: entity.type))
                    }

                    resultString += item.text
                    offset += item.text.count

                    resultString += "'"
                    offset += 1

                    if index < items.count - 1 {
                        resultString += ", "
                        offset += 2
                    }
                }

                return (resultString, entities)
            }

            var rawString: String

            let isMultiple = tasks.count > 1

            if authorId == account.peerId {
                rawString = isMultiple ? strings().chatServiceTodoAddedMultiYou : strings().chatServiceTodoAddedYou
            } else {
                rawString = isMultiple ? strings().chatServiceTodoAddedMulti : strings().chatServiceTodoAdded
            }

            let values = makeValues(tasks)

            let valuesRange = rawString.nsstring.range(of: "{values}")
            if valuesRange.location != NSNotFound {
                rawString = rawString.nsstring.replacingCharacters(in: valuesRange, with: values.0)
            }

            let authorRange = rawString.nsstring.range(of: "{author}")
            if authorRange.location != NSNotFound {
                rawString = rawString.nsstring.replacingCharacters(in: authorRange, with: authorName)
            }

            let taskTitle = "'\(todoMedia.text)'"
            let taskRange = rawString.nsstring.range(of: "{task}")
            if taskRange.location != NSNotFound {
                rawString = rawString.nsstring.replacingCharacters(in: taskRange, with: taskTitle)
            }

            // Adjust offset for text entities
            var offset = valuesRange.location
            if authorRange.location != NSNotFound {
                offset += (authorName.length - authorRange.length)
            }
            if taskRange.location != NSNotFound {
                offset += (taskTitle.length - taskRange.length)
            }

            for entity in values.1 {
                entities.append(.init(range: entity.range.lowerBound + offset ..< entity.range.upperBound + offset, type: entity.type))
            }

            text = rawString
        case let .suggestedPostApprovalStatus(status):
            switch status {
            case .approved:
                text = strings().chatServiceSuggestPostStatusApproved
            case .rejected:
                text = strings().chatServiceSuggestPostStatusRejected
            }
        case let .giftTon(currency, amount, cryptoCurrency, cryptoAmount, _):
            let formatted: String
            
            if let cryptoCurrency, let cryptoAmount {
                formatted = formatCurrencyAmount(cryptoAmount, currency: cryptoCurrency).prettyCurrencyNumberUsd + " " + cryptoCurrency
            } else {
                formatted = formatCurrencyAmount(amount, currency: currency)
            }
            
            if authorId == account.peerId {
                text = strings().chatServicePremiumGiftSentYou(formatted)
            } else {
                text = strings().chatServicePremiumGiftSent(authorName, formatted)
            }
        case let .gramTransfer(amount, _, _, _, _):
            let amountText = formatGramsText(amount, maxDecimalPositions: 3)
            if authorId == account.peerId {
                text = strings().chatServiceGramTransferYou(peer.compactDisplayTitle, amountText)
            } else if message.id.peerId == servicePeerId {
                text = strings().chatServiceGramTransferUnknown(amountText)
            } else {
                text = strings().chatServiceGramTransfer(authorName, amountText)
            }
        case let .walletTonConnectRequest(flags, _, _, _, _, dappName):
            if flags & (1 << 3) != 0 {
                text = dappName.map { strings().chatServiceWalletRequestFromDeclined($0) } ?? strings().chatServiceWalletRequestDeclined
            } else if flags & (1 << 2) != 0 {
                text = dappName.map { strings().chatServiceWalletRequestFromAccepted($0) } ?? strings().chatServiceWalletRequestAccepted
            } else {
                text = dappName.map { strings().chatServiceWalletRequestFrom($0) } ?? strings().chatServiceWalletRequest
            }
        case let .suggestedPostSuccess(amount):
            var isUser = true
            var channelName: String = ""
            if let peer = message.peers[message.id.peerId] as? TelegramChannel {
                channelName = peer.title
                if peer.isMonoForum, let linkedMonoforumId = peer.linkedMonoforumId, let mainChannel = message.peers[linkedMonoforumId] as? TelegramChannel, mainChannel.hasPermission(.manageDirect) {
                    isUser = false
                }
            }
            let _ = isUser
            
            let amountString: String = amount.fullyFormatted
            text = strings().chatServiceSuggestPostSuccessReceived(channelName, amountString)

        case let .suggestedPostRefund(info):
            var isUser = true
            if let peer = message.peers[message.id.peerId] as? TelegramChannel {
                if peer.isMonoForum, let linkedMonoforumId = peer.linkedMonoforumId, let mainChannel = message.peers[linkedMonoforumId] as? TelegramChannel, mainChannel.hasPermission(.manageDirect) {
                    isUser = false
                }
            }
            if info.isUserInitiated {
                if isUser {
                    text = strings().chatServiceSuggestPostRefundedUser
                } else {
                    text = strings().chatServiceSuggestPostRefundedOther
                }
            } else {
                text = strings().chatServiceSuggestPostRefundedDeleted
            }
        case .suggestedBirthday(_):
            if authorId != account.peerId {
                text = strings().chatServiceBirthdaySuggestedToYou(authorName)
            } else if let peer = message.peers[message.id.peerId] {
                text = strings().chatServiceBirthdaySuggestedToOther(peer.compactDisplayTitle)
            } else {
                text = ""
            }
        case let .starGiftPurchaseOfferDeclined(gift, amount, hasExpired):
            if let gift = gift.unique {
                let giftString = "\(gift.title) #\(gift.number)"
                let peerName = message.peers[message.id.peerId]?.compactDisplayTitle ?? ""
                if hasExpired {
                    if authorId == account.peerId {
                        text = strings().chatServiceOfferExpiredYou(peerName, giftString, amount.fullyFormatted)
                    } else {
                        text = strings().chatServiceOfferExpiredOther(peerName, giftString, amount.fullyFormatted)
                    }
                } else {
                    if authorId == account.peerId {
                        text = strings().chatServiceOfferRejectedYou(peerName, giftString, amount.fullyFormatted)
                    } else {
                        text = strings().chatServiceOfferRejectedOther(peerName, giftString, amount.fullyFormatted)
                    }
                }
            }
        case let .starGiftPurchaseOffer(gift, amount, _, _, _):
            if let gift = gift.unique {
                let giftString = "\(gift.title) #\(gift.number)"
                let peerName = message.peers[message.id.peerId]?.compactDisplayTitle ?? ""
                if authorId != account.peerId {
                    text = strings().chatServiceOfferReceivedOffer(peerName, amount.fullyFormatted, giftString)
                } else {
                    text = strings().chatServiceOfferSentOffer(amount.fullyFormatted, peerName, giftString)
                }
            }
        case let .groupCreatorChange(groupCreatorChange):
            var targetName = ""
            if let peer = message.peers[groupCreatorChange.targetPeerId] {
                targetName = peer.displayTitle
            }
            switch groupCreatorChange.kind {
            case .pending:
                text = strings().notificationGroupCreatorChangePending(authorName, targetName)
            case .applied:
                text = strings().notificationGroupCreatorChangeApplied(authorName, targetName)
            }
        case .copyProtectionToggle(previousValue: _, newValue: let newValue):
            let name = authorId == account.peerId ? strings().chatServiceYou : authorName
            if newValue {
                text = strings().chatServiceCopyProtectionSharingDisabled(name)
            } else {
                text = strings().chatServiceCopyProtectionSharingEnabled(name)
            }
        case .copyProtectionRequest(hasExpired: let hasExpired, previousValue: _, newValue: let newValue):
            let context = MessageTextHooks.shared.currentContext()
            let timestamp = context?.timestamp ?? Int32(Date().timeIntervalSince1970)
            
            let expirePeriod = context?.appConfiguration.getGeneralValue("no_forwards_request_expire_period", orElse: 86400) ?? 86400
            
            let isTimedOut = message.timestamp + expirePeriod < timestamp
            if hasExpired || isTimedOut {
                text = strings().chatServiceCopyProtectionRequestExpired
            } else {
                let name = authorId == account.peerId ? strings().chatServiceYou : authorName
                if newValue {
                    text = strings().chatServiceCopyProtectionWouldLikeDisable(name)
                } else {
                    text = strings().chatServiceCopyProtectionWouldLikeEnable(name)
                }
            }
        case .noPaidMessagesTokenUsed:
            let peerName = message.peers[message.id.peerId]?.compactDisplayTitle ?? ""
            let serviceText = noPaidMessagesTokenUsedText(peerName: peerName, isAuthor: authorId == account.peerId)
            text = serviceText.text
            if serviceText.peerRange.location != NSNotFound, serviceText.peerRange.length > 0 {
                entities.append(.init(range: serviceText.peerRange.location ..< NSMaxRange(serviceText.peerRange), type: .TextMention(peerId: message.id.peerId)))
            }
        case let .managedBotCreated(botId):
            let botName = message.peers[botId]?.displayTitle ?? ""
            text = strings().textUtilsManagedBotCreated(authorName, botName)
        case let .pollOptionAppended(option):
            text = strings().textUtilsPollOptionAppended(authorName, option.text)
        case let .pollOptionDeleted(option):
            text = strings().textUtilsPollOptionDeleted(authorName, option.text)
        }
    }
    return (text, entities, media)
}









public func showSlowModeTimeoutTooltip(_ slowMode: SlowMode, for view: NSView) {
    if let errorText = slowMode.errorText {
        if let validUntil = slowMode.validUntil {
            tooltip(for: view, text: errorText, updateText: { f in
                var timer:SwiftSignalKit.Timer?
                timer = SwiftSignalKit.Timer(timeout: 0.1, repeat: true, completion: {
                    
                    let timeout = (validUntil - Int32(Date().timeIntervalSince1970))
                    
                    var result: Bool = false
                    if timeout > 0 {
                        result = f(slowModeTooltipText(timeout))
                    }
                    if !result {
                        timer?.invalidate()
                        timer = nil
                    }
                    
                }, queue: .mainQueue())
                
                timer?.start()
            })
        } else {
            tooltip(for: view, text: errorText)
        }
        
    }
}

public let preCharacter = "`"
public func parseTextEntities(_ message:String) -> (String, [MessageTextEntity]) {
    let entities:[MessageTextEntity] = []
    let message = message
   // let regex = Regex("`")
    
    
//    let pattern = "(`([\\w]+)`)"
//    let regex = try! NSRegularExpression(pattern: pattern, options: [])
//    let matches = regex.matches(in: message, options: [], range: NSRange(location: 0, length: message.characters.count))
//
//    for match in matches {
//        for n in 0 ..< match.numberOfRanges {
//            let range = match.rangeAt(n)
//            var bp:Int = 0
//            bp += 1
//        }
//    }
//    
//    let converted = regex.stringByReplacingMatches(in: message, options: .anchored, range: NSRange(location: 0, length: message.characters.count), withTemplate: "$2")
    
//    var currentIndex:String.Index? = nil
//    while true {
//        
//        if let startRange = message.range(of: preCharacter) {
//            if let endRange = message.range(of: preCharacter, options: .caseInsensitive, range: startRange.upperBound ..< message.endIndex, locale: nil)  {
//                
//                let text = message.substring(with: startRange.lowerBound ..< endRange.upperBound)
//                var bp:Int = 0
//                bp += 1
//                entities.append(.init(range: <#T##Range<Int>#>, type: <#T##MessageTextEntityType#>))
//                
//            }
//            //if let endIndex =
//        }
//        break
//    }
    return (message, entities)
    
}
