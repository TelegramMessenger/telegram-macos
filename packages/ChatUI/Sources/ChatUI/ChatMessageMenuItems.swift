import Foundation
import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import ObjcUtils
import Translate
import InAppSettings
import InputView
import TelegramMedia
import AlertsUI
import ChatHistoryModel
import ChatModeTypes
import FilePanels
import InputTextView
import LocalAnimations
import Localization
import MessageUtils
import PremiumUI
import StarsUI
import Strings
import TelegramContext
import TelegramMediaUtils
import TelegramTheme
import TelegramUtils
import InlineStickerLayer

public func pollVoteRestrictionText(poll: TelegramMediaPoll, chatPeer: Peer?) -> String? {
    if !poll.countries.isEmpty {
        let locale = appAppearance.locale
        let names: [String] = poll.countries.map { id in
            locale.localizedString(forRegionCode: id) ?? id
        }
        let formatted: String
        if names.count == 1 {
            formatted = names[0]
        } else {
            var out = ""
            for (i, name) in names.enumerated() {
                out.append(name)
                if i == names.count - 2 {
                    out.append(strings().chatMessageMenuItemsAndJoiner)
                } else if i < names.count - 2 {
                    out.append(", ")
                }
            }
            formatted = out
        }
        return strings().chatMessageMenuItemsOnlyUsersFromCountriesCanVote(formatted)
    }
    if poll.restrictToSubscribers {
        let channelName = chatPeer?.displayTitle ?? ""
        if !channelName.isEmpty {
            return strings().chatMessageMenuItemsOnlySubscribersOfCanVote(channelName)
        }
        return strings().chatMessageMenuItemsOnlyOldSubscribersCanVote
    }
    return nil
}


private func pollVoteRestrictionMenuText(poll: TelegramMediaPoll, chatPeer: Peer?) -> String? {
    return pollVoteRestrictionText(poll: poll, chatPeer: chatPeer)
}

public final class ChatMenuItemsData {
    public let chatInteraction: ChatInteraction
    public let message: Message
    public let accountPeer: Peer
    public let resourceData: MediaResourceData?
    public let chatState: ChatState
    public let chatMode: ChatMode
    public let chatLocation: ChatLocation
    public let isLogInteraction: Bool
    public let disableSelectAbility: Bool
    public let canPinMessage: Bool
    public let pinnedMessage: ChatPinnedMessage?
    public let peer: Peer?
    public let peerId: PeerId
    public let fileFinderPath: String?
    public let isStickerSaved: Bool?
    public let savedStickersCount: Int
    public let savedGifsCount: Int
    public let dialogs: [Peer]
    public let recentUsedPeers: [Peer]
    public let favoritePeers: [Peer]
    public let updatingMessageMedia: [MessageId: ChatUpdatingMessageMedia]
    public let recentMedia: [RecentMediaItem]
    public let additionalData: MessageEntryAdditionalData
    public let availableReactions: AvailableReactions?
    public let file: TelegramMediaFile?
    public let image: TelegramMediaImage?
    public let textLayout: (TextViewLayout?, LinkType?)?
    public let notifications: NotificationSoundList?
    public let cachedData: CachedPeerData?
    public let groupped:[Message]?
    public let folders: [(ChatListFilter, [Peer])]
    public let isMediaStory: Bool
    public let isRead: Bool
    public let canViewAuthor: Bool
    public init(chatInteraction: ChatInteraction, message: Message, accountPeer: Peer, resourceData: MediaResourceData?, chatState: ChatState, chatMode: ChatMode, chatLocation: ChatLocation, disableSelectAbility: Bool, isLogInteraction: Bool, canPinMessage: Bool, pinnedMessage: ChatPinnedMessage?, peer: Peer?, peerId: PeerId, fileFinderPath: String?, isStickerSaved: Bool?, dialogs: [Peer], recentUsedPeers: [Peer], favoritePeers: [Peer], recentMedia: [RecentMediaItem], updatingMessageMedia: [MessageId: ChatUpdatingMessageMedia], additionalData: MessageEntryAdditionalData, file: TelegramMediaFile?, image: TelegramMediaImage?, textLayout: (TextViewLayout?, LinkType?)?, availableReactions: AvailableReactions?, notifications: NotificationSoundList?, cachedData: CachedPeerData?, savedStickersCount: Int, savedGifsCount: Int, groupped: [Message]?, folders: [(ChatListFilter, [Peer])], isMediaStory: Bool, isRead: Bool, canViewAuthor: Bool) {
        self.chatInteraction = chatInteraction
        self.message = message
        self.accountPeer = accountPeer
        self.resourceData = resourceData
        self.chatState = chatState
        self.chatMode = chatMode
        self.chatLocation = chatLocation
        self.disableSelectAbility = disableSelectAbility
        self.isLogInteraction = isLogInteraction
        self.canPinMessage = canPinMessage
        self.pinnedMessage = pinnedMessage
        self.peer = peer
        self.peerId = peerId
        self.fileFinderPath = fileFinderPath
        self.isStickerSaved = isStickerSaved
        self.dialogs = dialogs
        self.recentUsedPeers = recentUsedPeers
        self.favoritePeers = favoritePeers
        self.recentMedia = recentMedia
        self.updatingMessageMedia = updatingMessageMedia
        self.additionalData = additionalData
        self.file = file
        self.image = image
        self.textLayout = textLayout
        self.availableReactions = availableReactions
        self.notifications = notifications
        self.cachedData = cachedData
        self.savedStickersCount = savedStickersCount
        self.savedGifsCount = savedGifsCount
        self.groupped = groupped
        self.folders = folders
        self.isMediaStory = isMediaStory
        self.isRead = isRead
        self.canViewAuthor = canViewAuthor
    }
}

public enum ChatMenuItemSource {
    case general
    case todo(taskId: Int32)
    case pollOption(opaqueIdentifier: Data)
}

public func chatMenuItemsData(for message: Message, textLayout: (TextViewLayout?, LinkType?)?, entry: ChatHistoryEntry?, chatInteraction: ChatInteraction, source: ChatMenuItemSource = .general) -> Signal<ChatMenuItemsData, NoError> {
    
    let context = chatInteraction.interactionContext
    let account = context.account
    let chatMode = chatInteraction.presentation.chatMode
    let chatLocation = chatInteraction.presentation.chatLocation
    let chatState = chatInteraction.presentation.state
    let disableSelectAbility = chatInteraction.disableSelectAbility
    let isLogInteraction = chatInteraction.isLogInteraction
    let pinnedMessage = chatInteraction.presentation.pinnedMessageId
    let peerId = chatInteraction.peerId
    let peer = chatInteraction.peer
    let canPinMessage = chatInteraction.presentation.canPinMessage && peerId.namespace != Namespaces.Peer.SecretChat
    let additionalData = entry?.additionalData ?? MessageEntryAdditionalData()
    
    var canViewAuthor: Bool = false
    if let channel = chatInteraction.presentation.peer as? TelegramChannel, channel.isMonoForum, channel.groupAccess.canManageDirect {
        let isIncoming: Bool = message.effectivelyIncoming(context.account.peerId)
        if isIncoming, message.author?.id == channel.linkedMonoforumId {
            canViewAuthor = true
        }
    }

    
    let storyMedia = message.media.first as? TelegramMediaStory
    let isMediaStory = storyMedia?.storyId.peerId == context.peerId ? false : storyMedia != nil
    
    
    let incoming: Bool = message.isIncoming(context.account, false)
    let isRead: Bool
    if case let .MessageEntry(_, _, _isRead, _, _, _, _) = entry {
        isRead = _isRead || incoming
    } else if case let .groupedPhotos(entries, _) = entry, case let .MessageEntry(_, _, _isRead, _, _, _, _) = entries.first {
        isRead = _isRead || incoming
    } else {
        isRead = incoming
    }
    
    var file: TelegramMediaFile? = nil
    var image: TelegramMediaImage? = nil
    if let media = message.anyMedia as? TelegramMediaFile {
        file = media
    } else if let media = message.anyMedia as? TelegramMediaImage {
        image = media
    } else if let media = message.anyMedia as? TelegramMediaWebpage {
        switch media.content {
        case let .Loaded(content):
            file = content.file
            if file == nil {
                image = content.image
            }
        default:
            break
        }
    }
    
    let request:(ChatListFilterPredicate?)->Signal<[Peer], NoError> = { predicate in
        return account.postbox.tailChatListView(groupId: .root, filterPredicate: predicate, count: 25, summaryComponents: .init())
            |> take(1) |> map { view in
                return view.0.entries.compactMap { entry in
                    switch entry {
                    case let .MessageEntry(data):
                        return data.renderedPeer.peer
                    default:
                        return nil
                    }
                }
            }
    }

    let _dialogs: Signal<[Peer], NoError> = request(nil)
    
    let _folders: Signal<[(ChatListFilter, [Peer])], NoError> = combineLatest(
        chatListFilterPreferences(engine: context.engine),
        ChatHistoryUIHooks.shared.communityFilterCategories(account)
    ) |> mapToSignal { value, communityCategories in
        return combineLatest(value.list.filter { !ChatHistoryUIHooks.shared.chatListFilterIsAllChats($0) }.map { item in
            return request(ChatHistoryUIHooks.shared.chatListFilterPredicate(item, communityCategories)) |> map {
                (item, $0)
            }
        })
    }
    
    
    let _recentUsedPeers: Signal<[Peer], NoError> = context.recentlyUserPeerIds |> mapToSignal { ids in
        return account.postbox.transaction { transaction in
            let peers = ids.compactMap { transaction.getPeer($0) }
            return Array(peers.map { $0 })
        }
    }
    let _favoritePeers: Signal<[Peer], NoError> = context.engine.peers.recentPeers() |> map { recent in
        switch recent {
        case .disabled:
            return []
        case let .peers(peers):
            return Array(peers.map { $0 })
        }
    }
    
    let _accountPeer = account.postbox.loadedPeerWithId(context.peerId) |> deliverOnMainQueue
    
    var _resourceData: Signal<MediaResourceData?, NoError> = .single(nil)
    var _fileFinderPath: Signal<String?, NoError> = .single(nil)
    var _getIsStickerSaved: Signal<Bool?, NoError> = .single(nil)
    var _recentMedia: Signal<[RecentMediaItem], NoError> = .single([])
    
    let _savedStickersCount: Signal<Int, NoError> = account.postbox.itemCollectionsView(orderedItemListCollectionIds: [Namespaces.OrderedItemList.CloudSavedStickers], namespaces: [Namespaces.ItemCollection.CloudStickerPacks], aroundIndex: nil, count: 100) |> take(1) |> map {
        $0.orderedItemListsViews[0].items.count
    }
    
    let _savedGifsCount: Signal<Int, NoError> = context.account.postbox.combinedView(keys: [.orderedItemList(id: Namespaces.OrderedItemList.CloudRecentGifs)]) |> take(1) |> map {
        return ($0.views[.orderedItemList(id: Namespaces.OrderedItemList.CloudRecentGifs)] as! OrderedItemListView).items.count
    }

    
    let _updatingMessageMedia = account.pendingUpdateMessageManager.updatingMessageMedia
        
    if let media = file {
        _resourceData = account.postbox.mediaBox.resourceData(media.resource) |> map(Optional.init)
        
        if media.isSticker {
            _getIsStickerSaved = account.postbox.transaction { transaction -> Bool? in
                return getIsStickerSaved(transaction: transaction, fileId: media.fileId)
            }
        }
        
        if media.isAnimated && media.isVideo {
            _recentMedia = account.postbox.transaction { transaction -> [RecentMediaItem] in
                transaction.getOrderedListItems(collectionId: Namespaces.OrderedItemList.CloudRecentGifs).compactMap { $0.contents.get(RecentMediaItem.self) }
            }
        }
        
        _fileFinderPath = fileFinderPath(media, account.postbox)
        
    } else if let media = image {
        if let resource = media.representations.last?.resource {
            _resourceData = account.postbox.mediaBox.resourceData(resource) |> map(Optional.init)
        }
    }
    
    let _groupped: Signal<[Message]?, NoError> = context.account.postbox.transaction { transaction in
        return transaction.getMessageGroup(message.id)
    }
    
    let cachedData = getCachedDataView(peerId: peerId, postbox: context.account.postbox) |> take(1)
    
    let combined = combineLatest(queue: .mainQueue(), _dialogs, _recentUsedPeers, _favoritePeers, _accountPeer, _resourceData, _fileFinderPath, _getIsStickerSaved, _recentMedia, _updatingMessageMedia, context.reactions.stateValue, context.engine.peers.notificationSoundList(), cachedData, _savedStickersCount, _savedGifsCount, _groupped, _folders)
    |> take(1)
    
    
    
    return combined |> map { dialogs, recentUsedPeers, favoritePeers, accountPeer, resourceData, fileFinderPath, isStickerSaved, recentMedia, updatingMessageMedia, availableReactions, notifications, cachedData, savedStickersCount, savedGifsCount, groupped, folders in
        return .init(chatInteraction: chatInteraction, message: message, accountPeer: accountPeer, resourceData: resourceData, chatState: chatState, chatMode: chatMode, chatLocation: chatLocation, disableSelectAbility: disableSelectAbility, isLogInteraction: isLogInteraction, canPinMessage: canPinMessage, pinnedMessage: pinnedMessage, peer: peer, peerId: peerId, fileFinderPath: fileFinderPath, isStickerSaved: isStickerSaved, dialogs: dialogs, recentUsedPeers: recentUsedPeers, favoritePeers: favoritePeers, recentMedia: recentMedia, updatingMessageMedia: updatingMessageMedia, additionalData: additionalData, file: file, image: image, textLayout: textLayout, availableReactions: availableReactions, notifications: notifications, cachedData: cachedData, savedStickersCount: savedStickersCount, savedGifsCount: savedGifsCount, groupped: groupped, folders: folders, isMediaStory: isMediaStory, isRead: isRead, canViewAuthor: canViewAuthor)
    }
}

private func copyImageToPasteboard(path: String) -> Bool {
    guard let path = copyToTemp(path: path, ext: "jpg") else {
        return false
    }
    let url = NSURL(fileURLWithPath: path)
    let image = NSImage(contentsOf: url as URL)
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.writeObjects([url, image].compactMap { $0 })
    return true
}

private func copyRichTextMessage(_ message: Message, text: String, page: InstantPage, isTranslated: Bool) {
    copyToClipboard(text)
    guard !isTranslated else {
        return
    }
    if let data = try? JSONEncoder().encode(richTextDocument(from: message)) {
        NSPasteboard.general.addTypes([.kRichTextMessage], owner: nil)
        NSPasteboard.general.setData(data, forType: .kRichTextMessage)
    }
    if !page.media.isEmpty {
        let ref = "\(message.id.peerId.toInt64()):\(message.id.namespace):\(message.id.id)"
        if let data = ref.data(using: .utf8) {
            NSPasteboard.general.addTypes([.kRichTextMessageRef], owner: nil)
            NSPasteboard.general.setData(data, forType: .kRichTextMessageRef)
        }
    }
}


public func chatMenuItems(for message: Message, entry: ChatHistoryEntry?, textLayout: (TextViewLayout?, LinkType?)?, chatInteraction: ChatInteraction, useGroupIfNeeded: Bool = true, fromAdPromo: Bool = false, source: ChatMenuItemSource = .general) -> Signal<[ContextMenuItem], NoError> {
    
    if chatInteraction.interactionContext.isFrozen {
        return .complete()
    }

    if message.id.namespace == Namespaces.Message.Local, message.attributes.contains(where: { $0 is TypingDraftMessageAttribute }) {
        return .complete()
    }

    let selectedIds = chatInteraction.presentation.selectionState?.selectedIds ?? []
    let selectedMessages: Signal<[Message], NoError>
    if selectedIds.count > 1, selectedIds.contains(message.id) {
        selectedMessages = chatInteraction.getMessages(Array(selectedIds), false) |> take(1)
    } else {
        selectedMessages = .single([])
    }

    return combineLatest(chatMenuItemsData(for: message, textLayout: textLayout, entry: entry, chatInteraction: chatInteraction, source: source), selectedMessages) |> map { [chatInteraction] data, selectedMessages in
        
        let peer = data.message.peers[data.message.id.peerId]
        let isNotFailed = !message.flags.contains(.Failed) && !message.flags.contains(.Unsent) && !data.message.flags.contains(.Sending)
        let protected = data.message.containsSecretMedia || data.message.isCopyProtected(cachedData: data.chatInteraction.presentation.cachedData)
        let peerId = data.peerId
        let messageId = data.message.id
        let appConfiguration = data.chatInteraction.interactionContext.appConfiguration
        let context = data.chatInteraction.interactionContext
        let account = context.account
        let mode = chatInteraction.mode
        let isIncoming = data.message.isIncoming(context.account, false)
        let translateConfig = AppConfigTranslateState(rawValue: context.appConfiguration.getStringValue("translations_manual_enabled", orElse: "enabled")) ?? .disabled
        var isService = data.message.extendedMedia is TelegramMediaAction || mode.isSavedMode || mode == .preview || chatInteraction.isLogInteraction
        

        if !isService, let story = data.message.media.first as? TelegramMediaStory {
            isService = story.isMention
        }

        // An ephemeral-namespace message exists only for this account, so it can be neither selected
        // (a selection acts on ids the server does not have) nor pinned. Replying is allowed for the
        // one case iOS permits: an incoming EphemeralLocal message.
        let isEphemeralNamespace = Namespaces.Message.allEphemeral.contains(data.message.id.namespace)
        let canReplyToEphemeral = data.message.id.namespace == Namespaces.Message.EphemeralLocal && data.message.flags.contains(.Incoming)
        let isNonReplyableEphemeral = isEphemeralNamespace && !canReplyToEphemeral

        if let replacementMessage = data.message.activeEphemeralReplacementMessage {
            var items: [ContextMenuItem] = []

            if !protected {
                if let textLayout = data.textLayout?.0, !textLayout.attributedString.string.isEmpty {
                    items.append(ContextMenuItem(strings().chatContextCopyText, handler: { [weak textLayout] in
                        guard let textLayout else {
                            return
                        }
                        let attributedString: NSAttributedString
                        if textLayout.selectedRange.hasSelectText {
                            attributedString = textLayout.attributedString.attributedSubstring(from: textLayout.selectedRange.range)
                        } else {
                            attributedString = textLayout.attributedString
                        }
                        if !LinkHooks.shared.globalLinkExecutor().copyAttributedString(attributedString) {
                            copyToClipboard(attributedString.string)
                        }
                    }, itemImage: MenuAnimation.menu_copy.value))
                } else if let richAttribute = data.message.attributes.first(where: { $0 is RichTextMessageAttribute }) as? RichTextMessageAttribute {
                    let (text, _) = richTextPlainPreview(from: richAttribute.instantPage)
                    if !text.isEmpty {
                        items.append(ContextMenuItem(strings().chatContextCopyText, handler: {
                            copyToClipboard(text)
                        }, itemImage: MenuAnimation.menu_copy.value))
                    }
                } else if !data.message.text.isEmpty {
                    items.append(ContextMenuItem(strings().chatContextCopyText, handler: {
                        copyToClipboard(data.message.text)
                    }, itemImage: MenuAnimation.menu_copy.value))
                } else if data.image != nil, let resourceData = data.resourceData, resourceData.complete {
                    items.append(ContextMenuItem(strings().chatContextCopyMedia, handler: {
                        if copyImageToPasteboard(path: resourceData.path) {
                            showModalText(for: context.window, text: strings().contextAlertCopied)
                        }
                    }, itemImage: MenuAnimation.menu_copy_media.value, keyEquivalent: .cmdc))
                }
            }

            if canForwardMessage(replacementMessage, chatInteraction: data.chatInteraction) {
                let forwardingAction = ChatForwardMenuAction(chatInteraction: data.chatInteraction, sources: [data.message, replacementMessage])
                items.append(ContextMenuItem(strings().messageContextForward, handler: {
                    forwardingAction.openPicker(messages: [replacementMessage])
                }, itemImage: MenuAnimation.menu_forward.value))
            }

            let revertTitle = NSMutableAttributedString()
            revertTitle.append(.initialize(string: strings().chatEphemeralMessageRevert, color: theme.colors.redUI, font: .medium(.text)))
            revertTitle.append(.initialize(string: "\n" + strings().chatEphemeralMessageRevertInfo, color: theme.colors.redUI, font: .normal(.short)))
            let revertItem = ContextMenuItem(strings().chatEphemeralMessageRevert, handler: {
                let _ = context.engine.messages.revertAnchoredEphemeralMessage(messageId: data.message.id).startStandalone()
            }, itemMode: .destruct, itemImage: MenuAnimation.menu_reload.value, removeTail: false, attributedTitle: revertTitle)
            revertItem.attributedTitle = revertTitle
            items.append(revertItem)

            for item in items {
                item.contextObject = data
            }
            return items
        }
        
        if mode.customChatContents?.kind == .welcomeMessages {
            var items: [ContextMenuItem] = []
            if !protected, let textLayout = data.textLayout?.0 {
                items.append(ContextMenuItem(strings().chatContextCopyText, handler: { [weak textLayout] in
                    if let textLayout = textLayout {
                        if !LinkHooks.shared.globalLinkExecutor().copyAttributedString(textLayout.attributedString) {
                            copyToClipboard(textLayout.attributedString.string)
                        }
                    }
                }, itemImage: MenuAnimation.menu_copy.value))
            }
            if canDeleteMessage(data.message, account: account, chatLocation: data.chatLocation, mode: data.chatMode) {
                items.append(ContextMenuItem(strings().messageContextDelete, handler: {
                    data.chatInteraction.deleteMessages([data.message.id], nil)
                }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
            }
            for item in items {
                item.contextObject = data
            }
            return items
        }

        var items:[ContextMenuItem] = []
        var zeroBlock:[ContextMenuItem] = []
        var firstBlock:[ContextMenuItem] = []
        var secondBlock:[ContextMenuItem] = []
        var add_secondBlock:[ContextMenuItem] = []
        var thirdBlock:[ContextMenuItem] = []
        var fourthBlock:[ContextMenuItem] = []
        var fifthBlock:[ContextMenuItem] = []
        var sixBlock:[ContextMenuItem] = []
        var sevenBlock:[ContextMenuItem] = []
        
        

        switch source {
        case let .todo(taskId):
            if let todo = message.media.first as? TelegramMediaTodo {
                
                var items = todo.items

                let taskText = todo.items.first(where: { $0.id == taskId })?.text
                let item = ContextMenuItem(taskText ?? strings().chatContextTodoTaskFallback, handler: {}, itemImage: MenuAnimation.menu_more.value)

                let submenu = ContextMenu()

                let completed = todo.completions.map { $0.id }
                let isCompleted = completed.contains(taskId)

                if let completed = todo.completions.first(where: { $0.id == taskId }), todo.flags.contains(.othersCanComplete) {
                    submenu.addItem(ContextMenuItem(stringForFullDate(timestamp: completed.date), handler: {}, itemImage: MenuAnimation.menu_check_selected.value))
                    submenu.addItem(ContextSeparatorItem())
                }

                if todo.flags.contains(.othersCanComplete) || message.author?.id == context.peerId {
                    submenu.addItem(ContextMenuItem(
                        isCompleted ? strings().chatContextTodoUncheck : strings().chatContextTodoCheck,
                        handler: {
                            _ = context.engine.messages.requestUpdateTodoMessageItems(
                                messageId: message.id,
                                completedIds: !isCompleted ? [taskId] : [],
                                incompletedIds: isCompleted ? [taskId] : []
                            ).start()
                        },
                        itemImage: !isCompleted ? MenuAnimation.menu_check.value : MenuAnimation.menu_uncheck.value
                    ))
                }

                submenu.addItem(ContextMenuItem(strings().contextCopy, handler: {
                    copyToClipboard(taskText ?? "")
                    showModalText(for: context.window, text: strings().shareLinkCopied)
                }, itemImage: MenuAnimation.menu_copy.value))

                if canEditMessage(message, chatInteraction: chatInteraction, context: context) {
                    submenu.addItem(ContextMenuItem(strings().chatContextTodoEdit, handler: { [weak chatInteraction] in
                        if let chatInteraction {
                            ChatNavigationHooks.shared.showNewTodo(chatInteraction, .edit(message, taskId: taskId), context.window, nil)
                        }
                    }, itemImage: MenuAnimation.menu_edit.value))
                }

                if canEditMessage(message, chatInteraction: chatInteraction, context: context) {
                    submenu.addItem(ContextSeparatorItem())

                    submenu.addItem(ContextMenuItem(strings().chatContextTodoDelete, handler: {
                        items.removeAll(where: { $0.id == taskId })
                        let mediaUpdated = todo.withUpdated(items: items)

                        if items.isEmpty {
                            data.chatInteraction.deleteMessages([data.message.id], nil)
                        } else {
                            verifyAlert(
                                for: context.window,
                                information: strings().chatContextTodoDeleteConfirm,
                                successHandler: { _ in
                                    context.account.pendingUpdateMessageManager.add(
                                        messageId: message.id,
                                        text: "",
                                        media: .update(.message(message: MessageReference(message), media: mediaUpdated)),
                                        entities: nil,
                                        richText: nil,
                                        inlineStickers: [:]
                                    )
                                }
                            )
                        }
                    }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
                }
                
                
                item.submenu = submenu
                
                zeroBlock.append(item)
            }
            
        default:
            break
        }
       
        
        if data.canViewAuthor {
            zeroBlock.append(MessageAuthorMenuItem(handler: { [weak chatInteraction] peerId in
                chatInteraction?.openInfo(peerId, false, nil, nil)
            }, messageId: data.message.id, context: context))
        }
        
        if let layout = textLayout?.0, layout.selectedRange.range.location != NSNotFound, layout.selectedRange.range.length > 0, NSMaxRange(layout.selectedRange.range) <= layout.attributedString.length, mode != .pinned, mode != .scheduled, !mode.isSavedMode, mode.customChatContents == nil, entry?.additionalData.translate == nil, !data.isLogInteraction {
            let selectedRange = layout.selectedRange.range
            let selectedString = layout.attributedString.attributedSubstring(from: selectedRange)
            firstBlock.append(ContextMenuItem(strings().chatMessageContextQuote, handler: {

                let quote_length_max = context.appConfiguration.getGeneralValue("quote_length_max", orElse: 1024)
                if selectedString.length > quote_length_max {
                    alert(for: context.window, info: strings().chatMessageContextQuoteLimitExceed)
                } else {
                    let attributed = enititesAttributedStringForText(selectedString).trimmed
                    let entities = messageTextEntitiesInRange(entities: ChatTextInputState(attributedText: attributed, selectionRange: 0..<0).messageTextEntities(), range: attributed.range, onlyQuoteable: true)

                    let quote = EngineMessageReplyQuote(text: attributed.string, offset: selectedRange.location, entities: entities, media: message.media.first)
                    chatInteraction.setupReplyMessage(message, .init(messageId: message.id, quote: quote, innerSubject: nil))

                }

            }, itemImage: MenuAnimation.menu_quote.value))
        }
        if message.attributes.contains(where: { $0 is RichTextMessageAttribute }),
           let quote = selectManager.richSelectedQuote(for: message.id),
           mode != .pinned, mode != .scheduled, !mode.isSavedMode,
           mode.customChatContents == nil, entry?.additionalData.translate == nil, !data.isLogInteraction {
            firstBlock.append(ContextMenuItem(strings().chatMessageContextQuote, handler: {
                let maximumLength = context.appConfiguration.getGeneralValue("quote_length_max", orElse: 1024)
                if quote.text.utf16.count > maximumLength {
                    alert(for: context.window, info: strings().chatMessageContextQuoteLimitExceed)
                } else {
                    chatInteraction.setupReplyMessage(message, .init(messageId: message.id, quote: quote, innerSubject: nil))
                }
            }, itemImage: MenuAnimation.menu_quote.value))
        }

        if let adAttribute = data.message.adAttribute {
            
            if adAttribute.sponsorInfo != nil || adAttribute.additionalInfo != nil {
                
                
                let submenu = ContextMenu()
                let subItem = ContextMenuItem(strings().chatMessageSponsoredAdvertiser, itemImage: MenuAnimation.menu_channel.value)
                
                if let text = adAttribute.sponsorInfo {
                    submenu.addItem(ContextMenuItem(text, handler: {
                        copyToClipboard(text)
                        showModalText(for: context.window, text: strings().contextAlertCopied)
                    }, removeTail: false))
                }
                if let text = adAttribute.additionalInfo {
                    if !submenu.items.isEmpty {
                        submenu.addItem(ContextSeparatorItem())
                    }
                    submenu.addItem(ContextMenuItem(text, handler: {
                        copyToClipboard(text)
                        showModalText(for: context.window, text: strings().contextAlertCopied)
                    }, removeTail: false))
                }
                
             
                
                subItem.submenu = submenu
                
                items.append(subItem)
                
                items.append(ContextSeparatorItem())

            }
            
            if adAttribute.canReport {
                
                if !fromAdPromo {
                    items.append(ContextMenuItem(strings().chatMessageSponsoredAbout, handler: {
                        showModal(with: ChatHistoryUIHooks.shared.makeFragmentAdsInfoController(context, message, chatInteraction), for: context.window)
                    }, itemImage: MenuAnimation.menu_show_info.value))
                    
                    items.append(ContextSeparatorItem())
                }
               
                
                items.append(ContextMenuItem(strings().chatMessageSponsoredReport, handler: {
                    
                    
                    if fromAdPromo {
                        closeAllModals(window: context.window)
                    }
                    
                    ChatNavigationHooks.shared.reportSponsoredAd(context, adAttribute.opaqueId, {
                        chatInteraction.removeAd(adAttribute.opaqueId)
                    }, context.window)
                }, itemImage: MenuAnimation.menu_restrict.value))
            } else {
                items.append(ContextMenuItem(strings().chatMessageSponsoredWhat, handler: {
                    let link = strings().chatMessageAdUrl
                    let text = strings().chatMessageMenuItemsSponsoredInfo
                    let info = text.replacingOccurrences(of: "[url]", with: "[\(link)](\(link))")
                    let data = ModalAlertData(title: strings().chatMessageSponsoredWhat, info: info, alignment: .left, width: 400, showCloseButton: true)
                    showModalAlert(for: context.window, data: data, completion: { _ in })
                }, itemImage: MenuAnimation.menu_report.value))

            }
            
            if !context.premiumIsBlocked {
                items.append(ContextMenuItem(strings().chatContextHideAd, handler: {
                    if context.isPremium, let opaqueId = message.adAttribute?.opaqueId {
                        _ = context.engine.accountData.updateAdMessagesEnabled(enabled: false).startStandalone()
                        chatInteraction.removeAd(opaqueId)
                        showModalText(for: context.window, text: strings().chatDisableAdTooltip)
                    } else {
                        prem(with: PremiumBoardingController(context: context, source: .no_ads, openFeatures: true), for: context.window)
                    }
                }, itemImage: MenuAnimation.menu_clear_history.value))
            }
            
             
            
            
            return items
        }
        
        if data.disableSelectAbility, data.chatState == .selecting {
            return []
        }
        
        if messageId.peerId == repliesPeerId, let author = data.message.chatPeer(context.peerId), author.id != context.peerId, !isService {
            let text = author.isUser ? strings().chatContextBlockUser : strings().chatContextBlockGroup
            firstBlock.append(ContextMenuItem(text, handler: {
                let header = author.isUser ? strings().chatContextBlockUserHeader : strings().chatContextBlockGroupHeader
                let info = author.isUser ? strings().chatContextBlockUserInfo(author.displayTitle) : strings().chatContextBlockGroupInfo(author.displayTitle)
                let third = author.isUser ? strings().chatContextBlockUserThird : strings().chatContextBlockGroupThird
                let ok = author.isUser ? strings().chatContextBlockUserOK : strings().chatContextBlockGroupOK
                let cancel = author.isUser ? strings().chatContextBlockUserCancel : strings().chatContextBlockGroupCancel

                verifyAlert(for: context.window, header: header, information: info, ok: ok, cancel: cancel, option: third, optionIsSelected: true, successHandler: { result in
                    switch result {
                    case .thrid:
                        let block: Signal<Never, NoError> = context.blockedPeersContext.add(peerId: author.id) |> `catch` { _ in return .complete() }
                        _ = showModalProgress(signal: combineLatest(context.engine.peers.reportPeerMessages(messageIds: [messageId], reason: .spam, message: ""), block), for: context.window).start()
                    case .basic:
                        _ = showModalProgress(signal: context.blockedPeersContext.add(peerId: author.id), for: context.window).start()
                    }
                })
            }, itemImage: MenuAnimation.menu_restrict.value))
        }

        if data.message.isScheduledMessage, let peer = data.peer, !isService  {
            firstBlock.append(ContextMenuItem(strings().chatContextScheduledSendNow, handler: {
                if data.message.pendingProcessingAttribute != nil {
                    verifyAlert(for: context.window, header: strings().chatVideoProccessingSendNowHeader, information: strings().chatVideoProccessingSendNowInfo, ok: strings().chatVideoProccessingSendNowOK, successHandler: { _ in
                        _ = context.engine.messages.sendScheduledMessageNowInteractively(messageId: messageId).start()
                    })
                } else {
                    _ = context.engine.messages.sendScheduledMessageNowInteractively(messageId: messageId).start()
                }
            }, itemImage: MenuAnimation.menu_send_now.value))

            if data.message.pendingProcessingAttribute == nil {
                firstBlock.append(ContextMenuItem(strings().chatContextScheduledReschedule, handler: {
                    showModal(with: chatDateSelector(context: context, defaultDate: message.timestamp == scheduleWhenOnlineTimestamp ? Date() : Date(timeIntervalSince1970: TimeInterval(message.timestamp)), repeatPeriod: data.message.scheduleRepeatPeriod, mode: .schedule(peer.id), selectedAt: { date, repeatPeriod in
                        
                        let schedule = Int32(min(date.timeIntervalSince1970, Double(scheduleWhenOnlineTimestamp)))
                        
                        _ = showModalProgress(signal: context.engine.messages.requestEditMessage(messageId: messageId, text: data.message.text, media: .keep, entities: data.message.textEntities, richText: nil, inlineStickers: data.message.associatedMedia, scheduleInfoAttribute: .init(scheduleTime: schedule, repeatPeriod: repeatPeriod)), for: context.window).start()
                   }), for: context.window)
                }, itemImage: MenuAnimation.menu_schedule_message.value))
            }
        }
        
        
        if canReplyMessage(data.message, peerId: data.peerId, chatLocation: data.chatLocation, mode: data.chatMode, threadData: chatInteraction.presentation.threadInfo) && !data.isLogInteraction && !isNonReplyableEphemeral {
            
            let innerSubject: EngineMessageReplyInnerSubject?
            switch source {
            case let .todo(taskId):
                innerSubject = .todoItem(taskId)
            case let .pollOption(opaqueIdentifier):
                innerSubject = .pollOption(opaqueIdentifier)
            default:
                innerSubject = nil
            }

            let replyTitle: String
            if case .pollOption = source {
                replyTitle = strings().chatMenuReplyToOption
            } else {
                replyTitle = strings().messageContextReply1
            }
            firstBlock.append(ContextMenuItem(replyTitle, handler: {
                data.chatInteraction.setupReplyMessage(data.message, .init(messageId: data.message.id, quote: nil, innerSubject: innerSubject))
            }, itemImage: MenuAnimation.menu_reply.value, keyEquivalent: .cmdr))
        }

        if let action = data.message.media.first as? TelegramMediaAction, case .starGift = action.action {
            firstBlock.append(ContextMenuItem(isIncoming ? strings().chatServiceSendGift(message.peers[message.id.peerId]?.displayTitle ?? "") : strings().chatServiceSendAnother, handler: {
                showModal(with: GiftingController(context: context, peerId: message.id.peerId, isBirthday: false), for: context.window)
            }, itemImage: MenuAnimation.menu_gift.value))
        }

        if #available(macOS 10.15, *), let action = data.message.media.first as? TelegramMediaAction, case .gramTransfer = action.action, context.appConfiguration.getBoolValue("wallet_available", orElse: false), let user = message.peers[message.id.peerId] as? TelegramUser {
            firstBlock.append(ContextMenuItem(strings().chatMessageMenuItemsSendMoney, handler: {
                showWalletSendMoney(chatInteraction: data.chatInteraction, user: user, flyIntoChat: false)
            }, itemImage: MenuAnimation.menu_gram.value))
        }
        
        
        if let poll = data.message.anyMedia as? TelegramMediaPoll {
            if !poll.isClosed && isNotFailed {
                if let _ = poll.results.voters?.first(where: {$0.selected}), !poll.isQuiz, !poll.revotingDisabled {
                    let isLoading = data.additionalData.pollStateData.isLoading
                    add_secondBlock.append(ContextMenuItem(strings().chatPollUnvote, handler: {
                        if !isLoading, isNotFailed {
                            data.chatInteraction.vote(messageId, [], true)
                        }
                    }, itemImage: MenuAnimation.menu_retract_vote.value))
                }
                if data.message.forwardInfo == nil {
                    let canClose: Bool = canEditMessage(data.message, chatInteraction: data.chatInteraction, context: context, ignorePoll: true)
                    if canClose {
                        add_secondBlock.append(ContextMenuItem(poll.isQuiz ? strings().chatQuizStop : strings().chatPollStop, handler: { [weak chatInteraction] in
                            verifyAlert_button(for: context.window, header: poll.isQuiz ? strings().chatQuizStopConfirmHeader : strings().chatPollStopConfirmHeader, information: poll.isQuiz ? strings().chatQuizStopConfirmText : strings().chatPollStopConfirmText, ok: strings().alertConfirmStop, successHandler: { [weak chatInteraction] _ in
                                chatInteraction?.closePoll(messageId)
                            })
                        }, itemImage: MenuAnimation.menu_stop_poll.value))
                    }
                }
            }
            if poll.results.canViewStats {
                add_secondBlock.append(ContextMenuItem(strings().chatMessageMenuItemsViewStats, handler: {
                    ChatNavigationHooks.shared.pushMessagePollStats(context, messageId)
                }, itemImage: MenuAnimation.menu_statistics.value))
            }
//            if let restriction = pollVoteRestrictionMenuText(poll: poll, chatPeer: peer) {
//                sevenBlock.append(ContextMenuItem(restriction, handler: nil, itemImage: MenuAnimation.menu_show_info.value, removeTail: false, overrideWidth: 200))
//            }
            if case let .pollOption(opaqueIdentifier) = source {
                if let option = poll.options.first(where: { $0.opaqueIdentifier == opaqueIdentifier }), let date = option.date {
                    let isPollAuthor = poll.isCreator
                    let isOptionAuthor = option.addedBy == context.peerId
                    let deletePeriod = context.appConfiguration.getGeneralValue("poll_answer_delete_period", orElse: 300)
                    let canOptionAuthorDelete = isOptionAuthor && (context.timestamp - date) < deletePeriod
                    if isPollAuthor || canOptionAuthorDelete {
                        add_secondBlock.append(ContextMenuItem(strings().chatMenuDeleteOption, handler: { [weak chatInteraction] in
                            chatInteraction?.deletePollOption(messageId, opaqueIdentifier)
                        }, itemMode: .normal, itemImage: MenuAnimation.menu_delete.value))
                    }
                }
            }
        }
        
        if data.chatLocation.threadMsgId == nil, let peer = peer, peer.isSupergroup {
            if let attr = data.message.threadAttr, attr.count > 0, mode != .scheduled {
                var messageId: MessageId = message.id
                var modeIsReplies = true
                if let source = message.sourceReference {
                    messageId = source.messageId
                    if let peer = message.peers[source.messageId.peerId] {
                        if peer.isChannel {
                            modeIsReplies = false
                        }
                    }
                }
                let text = modeIsReplies ? strings().messageContextViewRepliesOther(Int(attr.count)) : strings().messageContextViewCommentsOther(Int(attr.count))
                secondBlock.append(ContextMenuItem(text, handler: {
                    data.chatInteraction.openReplyThread(messageId, !modeIsReplies, true, modeIsReplies ? .replies(origin: messageId) : .comments(origin: messageId))
                }, itemImage: MenuAnimation.menu_view_replies.value))
            }
        }
        
        var muteTranslate = false
        if let translate = entry?.additionalData.translate {
            switch translate {
            case .loading:
                break
            case let .complete(toLang):
                if let _ = message.translationAttribute(toLang: toLang) {
                    muteTranslate = true
                }
            }
        }
        
        if let richAttribute = message.attributes.compactMap({ $0 as? RichTextMessageAttribute }).first, mode.customChatContents == nil {
            let (text, entities) = richTextPlainPreview(from: richAttribute.instantPage)
            let language = Translate.detectLanguage(for: text)
            let toLang = context.sharedContext.baseSettings.doNotTranslate.union([appAppearance.languageCode])
            if !text.isEmpty, language == nil || !toLang.contains(language!), !muteTranslate, !isService, translateConfig.canTranslate {
                thirdBlock.append(ContextMenuItem(strings().chatContextTranslate, handler: {
                    showModal(with: ChatHistoryUIHooks.shared.makeTranslateModalObserved(context, language, appAppearance.languageCode, text, entities, source: .richMessage(message.id, richAttribute.instantPage), onToneChanged: { tone in
                        data.chatInteraction.setTranslateTone(tone)
                    }, translateEntireChat: {
                        data.chatInteraction.translateTo(appAppearance.languageCode)
                    }), for: context.window)
                    data.chatInteraction.enableTranslatePaywall()
                }, itemImage: MenuAnimation.menu_translate.value))
            }
        }

        if let poll = message.media.first as? TelegramMediaPoll, mode.customChatContents == nil {
            var text = poll.text
            var entities: [MessageTextEntity] = []
            entities.append(contentsOf: poll.textEntities)
            text += "\n"
            
            for option in poll.options {
                text += "\n🔘 \(option.text)"
                for entity in option.entities {
                    var current = entity
                    current.range = entity.range.lowerBound + text.length - option.text.length ..< entity.range.upperBound + text.length - option.text.length
                    entities.append(current)
                }
            }
            let language = Translate.detectLanguage(for: text)
                        
            let toLang = context.sharedContext.baseSettings.doNotTranslate.union([appAppearance.languageCode])
            if language == nil || !toLang.contains(language!), !muteTranslate, !isService, translateConfig.canTranslate {
                _ = peer?.canSendMessage(data.chatMode.isThreadMode) == true
                thirdBlock.append(ContextMenuItem(strings().chatContextTranslate, handler: {
                    showModal(with: ChatHistoryUIHooks.shared.makeTranslateModalObserved(context, language, appAppearance.languageCode, text, entities, source: .poll(message.id), onToneChanged: { tone in
                        data.chatInteraction.setTranslateTone(tone)
                    }, translateEntireChat: {
                        data.chatInteraction.translateTo(appAppearance.languageCode)
                    }), for: context.window)
                    data.chatInteraction.enableTranslatePaywall()
                }, itemImage: MenuAnimation.menu_translate.value))
            }
        }

    //    if !data.message.isCopyProtected() {
        if let textLayout = data.textLayout?.0, (mode.customChatContents == nil || mode.customChatContents?.kind == .welcomeMessages), data.peer?.isSecretChat == false {
            
            if !textLayout.selectedRange.hasSelectText {
                let text = message.text
                let entities = message.textEntities?.entities ?? []
                let language = Translate.detectLanguage(for: text)

                let toLang = context.sharedContext.baseSettings.doNotTranslate.union([appAppearance.languageCode])
                // Rich messages get their own Translate item above (flattened preview + translateRichMessage) —
                // skip the plain-text item so the menu doesn't offer two.
                let isRichMessage = message.attributes.contains(where: { $0 is RichTextMessageAttribute })
                if !isRichMessage, language == nil || !toLang.contains(language!), !muteTranslate, !isService, translateConfig.canTranslate {
                    thirdBlock.append(ContextMenuItem(strings().chatContextTranslate, handler: {
                        showModal(with: ChatHistoryUIHooks.shared.makeTranslateModalObserved(context, language, appAppearance.languageCode, text, entities, source: .message(messageId), onToneChanged: { tone in
                            data.chatInteraction.setTranslateTone(tone)
                        }, translateEntireChat: {
                            data.chatInteraction.translateTo(appAppearance.languageCode)
                        }), for: context.window)
                        data.chatInteraction.enableTranslatePaywall()
                    }, itemImage: MenuAnimation.menu_translate.value))
                }

                if let entry {
                    for message in entry.messages {
                        if let _ = message.summarizeAttribute {
                            if entry.additionalData.summarize == nil {
                                thirdBlock.append(ContextMenuItem(strings().chatContextSummarize, handler: {
                                    data.chatInteraction.summarize(message)
                                }, itemImage: MenuAnimation.menu_collapse.value))
                            }
                            break
                        }
                    }
                }
                
                
                if !protected {
                    if message.attributes.contains(where: { $0 is RichTextMessageAttribute }), selectManager.richSelectedText(for: message.id) != nil {
                        thirdBlock.append(ContextMenuItem(strings().chatCopySelectedText, handler: {
                            selectManager.copy(selectManager)
                        }, itemImage: MenuAnimation.menu_copy.value, keyEquivalent: .cmdc))
                    } else if let richAttribute = message.attributes.compactMap({ $0 as? RichTextMessageAttribute }).first {
                        var translatedPage: InstantPage?
                        if let translate = entry?.additionalData.translate, case let .complete(toLang) = translate {
                            translatedPage = message.translationAttribute(toLang: toLang)?.instantPage
                        }
                        let page = translatedPage ?? richAttribute.fullInstantPage ?? richAttribute.instantPage
                        let (richText, _) = richTextPlainPreview(from: page)
                        if !richText.isEmpty {
                            let isTranslated = translatedPage != nil
                            thirdBlock.append(ContextMenuItem(strings().chatContextCopyText, handler: {
                                copyRichTextMessage(message, text: richText, page: page, isTranslated: isTranslated)
                            }, itemImage: MenuAnimation.menu_copy.value, keyEquivalent: .cmdc))
                        }
                    } else {
                        thirdBlock.append(ContextMenuItem(strings().chatContextCopyText, handler: { [weak textLayout] in
                            if let textLayout = textLayout {
                                if !LinkHooks.shared.globalLinkExecutor().copyAttributedString(textLayout.attributedString) {
                                    copyToClipboard(textLayout.attributedString.string)
                                }
                            }
                        }, itemImage: MenuAnimation.menu_copy.value))
                    }
                }
                
                
            } else {
                let text: String
                if let linkType = data.textLayout?.1, !protected {
                    text = ChatHistoryLink.copyContextText(from: linkType)
                    thirdBlock.append(ContextMenuItem(text, handler: { [weak textLayout] in
                        if let textLayout = textLayout {
                            let attr = textLayout.attributedString.mutableCopy() as! NSMutableAttributedString

                            var effectiveRange = textLayout.selectedRange.range
                            let selectedText = attr.attributedSubstring(from: textLayout.selectedRange.range)
                            
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.declareTypes([.string], owner: textLayout)
                            let attribute = selectedText.attribute(TextInputAttributes.textUrl, at: 0, effectiveRange: &effectiveRange)
                            if let attribute = attribute as? TextInputTextUrlAttribute {
                                pb.setString(attribute.url.isEmpty ? selectedText.string : attribute.url, forType: .string)
                            } else {
                                pb.setString(selectedText.string, forType: .string)
                            }
                        }
                        
                    }, itemImage: MenuAnimation.menu_copy.value))
                } else if !protected {
                    let attr = textLayout.attributedString.mutableCopy() as! NSMutableAttributedString
                    attr.enumerateAttributes(in: attr.range, options: [], using: { data, range, _ in
                        if let value = data[TextInputAttributes.embedded] as? InlineStickerItem {
                            switch value.source {
                            case let .attribute(value):
                                attr.replaceCharacters(in: range, with: value.emoji)
                            default:
                                break
                            }
                        }
                    })
                    if let range = attr.range.intersection(textLayout.selectedRange.range) {
                        let selectedText = attr.attributedSubstring(from: range)
                        
                        let state = ChatTextInputState(attributedText: selectedText, selectionRange: 0..<0)
                        let entities = state.messageTextEntities()

                        let text = state.inputText
                        let language = Translate.detectLanguage(for: text)
                        let toLang = context.sharedContext.baseSettings.doNotTranslate.union([appAppearance.languageCode])
                        
                        
                        if language == nil || !toLang.contains(language!), !muteTranslate, !isService, translateConfig.canTranslate {
                            _ = peer?.canSendMessage(data.chatMode.isThreadMode) == true
                            thirdBlock.append(ContextMenuItem(strings().chatContextTranslate, handler: {
                                showModal(with: ChatHistoryUIHooks.shared.makeTranslateModalObserved(context, language, appAppearance.languageCode, text, entities, source: .selectedText, onToneChanged: { tone in
                                    data.chatInteraction.setTranslateTone(tone)
                                }, translateEntireChat: {
                                    data.chatInteraction.translateTo(appAppearance.languageCode)
                                }), for: context.window)
                                data.chatInteraction.enableTranslatePaywall()
                            }, itemImage: MenuAnimation.menu_translate.value))
                        }
                        thirdBlock.append(ContextMenuItem(strings().chatCopySelectedText, handler: { [weak textLayout] in
                            if let textLayout = textLayout {
                                let attr = textLayout.attributedString
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.declareTypes([.string], owner: textLayout)
                                var effectiveRange = textLayout.selectedRange.range
                                let selectedText = attr.attributedSubstring(from: textLayout.selectedRange.range)
                                let isCopied = LinkHooks.shared.globalLinkExecutor().copyAttributedString(selectedText)
                                if !isCopied {
                                    let attribute = attr.attribute(NSAttributedString.Key.link, at: textLayout.selectedRange.range.location, effectiveRange: &effectiveRange)
                                    if let attribute = attribute as? ChatHistoryInAppLinkValue {
                                        pb.setString(attribute.link.isEmpty ? selectedText.string : attribute.link, forType: .string)
                                    } else {
                                        pb.setString(selectedText.string, forType: .string)
                                    }
                                }
                            }
                        }, itemImage: MenuAnimation.menu_copy.value))

                    }
                }
            }
        }
        if let state = data.message.audioTranscription {
            if !state.text.isEmpty && !state.isPending {
                let text = state.text
                let language = Translate.detectLanguage(for: text)
                let toLang = context.sharedContext.baseSettings.doNotTranslate.union([appAppearance.languageCode])
                if language == nil || !toLang.contains(language!), !isService, translateConfig.canTranslate {
                    _ = peer?.canSendMessage(data.chatMode.isThreadMode) == true
                    thirdBlock.append(ContextMenuItem(strings().chatContextTranslate, handler: {
                        showModal(with: ChatHistoryUIHooks.shared.makeTranslateModalObserved(context, language, appAppearance.languageCode, text, [], source: .transcription(messageId), onToneChanged: { tone in
                            data.chatInteraction.setTranslateTone(tone)
                        }, translateEntireChat: {
                            data.chatInteraction.translateTo(appAppearance.languageCode)
                        }), for: context.window)
                        data.chatInteraction.enableTranslatePaywall()
                    }, itemImage: MenuAnimation.menu_translate.value))
                }
            }
        }

        if let peer = peer as? TelegramChannel, !isService {
            if isNotFailed, !message.isScheduledMessage {
                thirdBlock.append(ContextMenuItem(strings().messageContextCopyMessageLink1, handler: {
                    _ = showModalProgress(signal: context.engine.messages.exportMessageLink(peerId: peer.id, messageId: messageId, isThread: data.chatLocation.threadMsgId != nil), for: context.window).start(next: { link in
                        if var link = link {
                            if case let .pollOption(opaqueIdentifier) = source {
                                let optionBase64 = opaqueIdentifier.base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))
                                link += link.contains("?") ? "&option=\(optionBase64)" : "?option=\(optionBase64)"
                            }
                            copyToClipboard(link)
                        }
                        showSuccess(window: context.window)
                    })
                }, itemImage: MenuAnimation.menu_copy_link.value))
            }
        }
        
        if canEditMessage(data.message, chatInteraction: data.chatInteraction, context: context), !isService {
            let edit = ContextMenuItem(strings().messageContextEdit, handler: {
                data.chatInteraction.beginEditingMessage(data.message)
            }, itemImage: MenuAnimation.menu_edit.value, keyEquivalent: .cmde)
            
            if let groupped = data.groupped, groupped.count > 1, let media = message.media.first as? TelegramMediaFile {
                if !media.isVideo {
                    let menu = ContextMenu()
                    for message in groupped {
                        if let fileName = message.file?.fileName {
                            menu.addItem(ContextMenuItem(fileName, handler: {
                                data.chatInteraction.beginEditingMessage(message)
                            }))
                        }
                    }
                    edit.submenu = menu
                }
            }
            
            secondBlock.append(edit)
            
            
        }
        
        if let media = data.message.media.first as? TelegramMediaTodo {
            let optionsLimit = Int(context.appConfiguration.getGeneralValue("todo_items_max", orElse: 30))
            if data.message.author?.id == context.peerId || media.flags.contains(.othersCanAppend), media.items.count < optionsLimit {
                secondBlock.append(ContextMenuItem(strings().chatContextMenuAddTask, handler: {
                    data.chatInteraction.appendTask(data.message)
                }, itemImage: MenuAnimation.menu_add.value, locked: !context.isPremium))
            }
        }
        
        if !data.message.isScheduledMessage, let peer = peer, !peer.isDeleted, isNotFailed, data.peerId == data.message.id.peerId, !isService, mode.customChatContents == nil, !isNonReplyableEphemeral {

            let needUnpin = data.pinnedMessage?.others.contains(data.message.id) == true
            let pinAndOld: Bool
            if let pinnedMessage = data.pinnedMessage, let last = pinnedMessage.others.last {
                pinAndOld = last > data.message.id
            } else {
                pinAndOld = false
            }
            let pinText = data.message.tags.contains(.pinned) ? strings().messageContextUnpin : strings().messageContextPin
            
            let pinImage = data.message.tags.contains(.pinned) ? MenuAnimation.menu_unpin.value : MenuAnimation.menu_pin.value
            
            let canSendMessage = peer.canSendMessage(data.chatMode.isThreadMode || data.chatMode.isTopicMode, media: data.message.media.first, threadData: data.chatInteraction.presentation.threadInfo)

            if let peer = peer as? TelegramChannel, peer.hasPermission(.pinMessages) || (peer.isChannel && peer.hasPermission(.editAllMessages)), canSendMessage {
                if isNotFailed {
                    if !data.chatMode.isThreadMode, (needUnpin || data.chatMode != .pinned) {
                        secondBlock.append(ContextMenuItem(pinText, handler: {
                            if peer.isSupergroup, !needUnpin {
                                let info = pinAndOld ? strings().chatConfirmPinOld : strings().messageContextConfirmPin1
                                
                                verifyAlert(for: context.window, information: info, ok:  strings().messageContextPin, option: pinAndOld ? nil : strings().messageContextConfirmNotifyPin, successHandler: { result in
                                    data.chatInteraction.updatePinned(data.message.id, needUnpin, result != .thrid, false)
                                })
                            } else {
                                data.chatInteraction.updatePinned(data.message.id, needUnpin, true, false)
                            }
                        }, itemImage: pinImage))
                    }
                }
            } else if data.message.id.peerId == context.peerId {
                secondBlock.append(ContextMenuItem(pinText, handler: {
                    data.chatInteraction.updatePinned(data.message.id, needUnpin, true, false)
                }, itemImage: pinImage))
            } else if let peer = peer as? TelegramGroup, peer.canPinMessage, (needUnpin || data.chatMode != .pinned) {
                secondBlock.append(ContextMenuItem(pinText, handler: {
                    if !needUnpin {
                        verifyAlert(for: context.window, information: pinAndOld ? strings().chatConfirmPinOld : strings().messageContextConfirmPin1, ok: strings().messageContextPin, option: pinAndOld ? nil : strings().messageContextConfirmNotifyPin, successHandler: { result in
                            data.chatInteraction.updatePinned(data.message.id, needUnpin, result == .thrid, false)
                        })
                    } else {
                        data.chatInteraction.updatePinned(data.message.id, needUnpin, false, false)
                    }
                }, itemImage: pinImage))
            } else if data.canPinMessage, let peer = data.peer, (needUnpin || data.chatMode != .pinned) {
                secondBlock.append(ContextMenuItem(pinText, handler: {
                    if !needUnpin {
                        verifyAlert(for: context.window, information: pinAndOld ? strings().chatConfirmPinOld : strings().messageContextConfirmPin1, ok: strings().messageContextPin, option: strings().chatConfirmPinFor(peer.displayTitle), optionIsSelected: false, successHandler: { result in
                            data.chatInteraction.updatePinned(data.message.id, needUnpin, false, result != .thrid)
                        })
                    } else {
                        data.chatInteraction.updatePinned(data.message.id, needUnpin, false, false)
                    }
                }, itemImage: pinImage))
            }
        }
        
        if canForwardMessage(data.message, chatInteraction: data.chatInteraction), !isService {
            let msgs = useGroupIfNeeded ? (data.groupped ?? [data.message]) : [data.message]
            let forwardingAction = ChatForwardMenuAction(chatInteraction: chatInteraction, sources: [data.message] + msgs)
            let forwardItem = ContextMenuItem(strings().messageContextForward, handler: {
                forwardingAction.openPicker(messages: msgs)
            }, itemImage: MenuAnimation.menu_forward.value)
            let forwardMenu = ContextMenu()
            let forwardObject = ChatHistoryUIHooks.shared.makeForwardMessagesObjectObserved(context, [data.message], useGroupIfNeeded, chatInteraction.getMessages)

            let recent = data.recentUsedPeers.filter {
                $0.id != context.peerId && $0.canSendMessage(media: message.media.first) && !$0.isDeleted
            }.prefix(5)
            
            let favorite = data.favoritePeers.filter {
                !recent.map { $0.id }.contains($0.id)
                && $0.id != context.peerId
                && $0.canSendMessage(media: message.media.first)
                && !$0.isDeleted
            }.prefix(5)
            
            let dialogs = data.dialogs.reversed().filter {
                !(recent + favorite).map { $0.id }.contains($0.id)
                    && $0.id != context.peerId
                    && $0.canSendMessage(media: message.media.first)
                    && !$0.isDeleted
            }.prefix(5)
            
            var items:[ContextMenuItem] = []
            
            
            func makeItem(_ peer: Peer) -> ContextMenuItem {
                let title = peer.id == context.peerId ? strings().peerSavedMessages : peer.displayTitle.prefixWithDots(20)
                let item = ReactionPeerMenu(title: title, handler: {
                    if !peer.isCommunity {
                        forwardingAction.forward(forwardObject, peerId: peer.id, threadId: nil)
                    }
                }, peer: peer, context: context, reaction: nil, message: message, destination: .forward(callback: { destinationPeerId, threadId in
                    forwardingAction.forward(forwardObject, peerId: destinationPeerId, threadId: threadId)
                }, canSelect: { destinationPeer in
                    return !destinationPeer.isCommunity && forwardObject.possibilityPerformTo(destinationPeer)
                }))

                
                return item
            }
            
            
            items.append(makeItem(data.accountPeer))
            if !recent.isEmpty || !dialogs.isEmpty || !favorite.isEmpty {
                items.append(ContextSeparatorItem())
            }
            for peer in recent {
                if peer.id.namespace != Namespaces.Peer.SecretChat {
                    items.append(makeItem(peer))
                }
            }
            if !recent.isEmpty {
                items.append(ContextSeparatorItem())
            }
            for peer in favorite {
                items.append(makeItem(peer))
            }
            if (!favorite.isEmpty || !recent.isEmpty) && !dialogs.isEmpty {
                items.append(ContextSeparatorItem())
            }
            for peer in dialogs {
                if peer.id.namespace != Namespaces.Peer.SecretChat {
                    items.append(makeItem(peer))
                }
            }
            if !items.isEmpty {
                
                if !data.folders.isEmpty {
                    items.append(ContextSeparatorItem())
                    let folders = ContextMenuItem(strings().chatContextFolders, itemImage: MenuAnimation.menu_folder.value)
                    
                    let folderSubmenu = ContextMenu()
                    for folder in data.folders {
                        let item = ContextMenuItem(ChatHistoryUIHooks.shared.chatListFilterTitle(folder.0), itemImage: ChatHistoryUIHooks.shared.folderEmoticonDrawable(FolderIcon(folder.0).emoticon).value)
                        let submenu = ContextMenu()
                        
                        for peer in folder.1 {
                            submenu.addItem(makeItem(peer))
                        }
                        item.submenu = submenu
                        folderSubmenu.addItem(item)
                    }
                    folders.submenu = folderSubmenu
                    items.append(folders)
                }
                
                let more = ContextMenuItem(strings().chatContextForwardMore, handler: {
                    forwardingAction.openPicker(messages: [message])
                }, itemImage: MenuAnimation.menu_more.value)
                items.append(more)
            }
            for item in items {
                forwardMenu.addItem(item)
            }
           
            forwardItem.submenu = forwardMenu
            secondBlock.append(forwardItem)
        }
        /*
         else if data.message.id.peerId.namespace == Namespaces.Peer.SecretChat, !data.message.containsSecretMedia {
             secondBlock.append(ContextMenuItem(strings().messageContextShare, handler: {
                 if let data = data {
                     data.chatInteraction.forwardMessages([data.message.id])
                 }
             }))
         }
         */

        
        
        if data.chatLocation.threadMsgId != data.message.id, !isService, message.pendingProcessingAttribute == nil, !isEphemeralNamespace {
            secondBlock.append(ContextMenuItem(strings().messageContextSelect, handler: {
                data.chatInteraction.withToggledSelectedMessage({
                    $0.withToggledSelectedMessage(data.message.id)
                })
            }, itemImage: MenuAnimation.menu_select_messages.value))
        }
        
        if let channel = data.message.peers[message.id.peerId] as? TelegramChannel, channel.isChannel, !isService {
            var views: Int = 0
            for attribute in message.attributes {
                if let attribute = attribute as? ViewCountMessageAttribute {
                    views = attribute.count
                }
            }
            
            if let cachedData = data.cachedData as? CachedChannelData, views >= 100 {
                if cachedData.flags.contains(.canViewStats) {
                    thirdBlock.append(ContextMenuItem.init(strings().chatContextViewStatistics, handler: {
                        ChatNavigationHooks.shared.pushMessageStatsObserved(context, data.message)
                    }, itemImage: MenuAnimation.menu_statistics.value))
                }
            }
        }
        
     
        
        let photoMessages = selectedMessages.isEmpty ? data.groupped ?? [] : selectedMessages
        let photos = ChatPhotoSaveAction.items(from: photoMessages, cachedData: data.cachedData)
        if photos.count > 1 {
            let title = selectedMessages.isEmpty ? strings().chatContextSaveAllPhotos : strings().chatContextSaveSelectedPhotos
            thirdBlock.append(ContextMenuItem(title, handler: {
                ChatPhotoSaveAction.save(photos.map { $0.message }, chatInteraction: chatInteraction)
            }, itemImage: MenuAnimation.menu_save_as.value))
        }

        if let resourceData = data.resourceData, !protected {
            if let file = data.file {
                if file.isVideo && file.isAnimated {
                    if data.recentMedia.contains(where: {$0.media.id == file.fileId}) {
                        thirdBlock.append(ContextMenuItem(strings().messageContextRemoveGif, handler: {
                            showModalText(for: context.window, text: strings().chatContextGifRemoved)
                            _ = removeSavedGif(postbox: account.postbox, mediaId: file.fileId).start()
                        }, itemImage: MenuAnimation.menu_remove_gif.value))
                    } else {
                        thirdBlock.append(ContextMenuItem(strings().messageContextSaveGif, handler: {
                            
                            let limit = context.isPremium ? context.premiumLimits.saved_gifs_limit_premium : context.premiumLimits.saved_gifs_limit_default
                            if limit <= data.savedGifsCount, !context.isPremium, !context.premiumIsBlocked {
                                showModalText(for: context.window, text: strings().chatContextFavoriteGifsLimitInfo("\(context.premiumLimits.saved_gifs_limit_premium)"), title: strings().chatContextFavoriteGifsLimitTitle, callback: { value in
                                    showPremiumLimit(context: context, type: .savedGifs)
                                })
                            } else {
                                showModalText(for: context.window, text: strings().chatContextGifAdded)
                            }
                            _ = addSavedGif(postbox: account.postbox, fileReference: FileMediaReference.message(message: MessageReference(data.message), media: file)).start()
                        }, itemImage: MenuAnimation.menu_add_gif.value))
                    }
                }
                if file.isSticker, let saved = data.isStickerSaved {
                    
                    if let reference = file.stickerReference {
                        thirdBlock.append(ContextMenuItem(strings().contextViewStickerSet, handler: {
                            showModal(with: ChatMediaUIHooks.shared.makeStickerPackPreview(context, peerId, [.stickers(reference)]), for: context.window)
                        }, itemImage: MenuAnimation.menu_view_sticker_set.value))
                    }
                    
                    let image = saved ? MenuAnimation.menu_remove_from_favorites.value : MenuAnimation.menu_add_to_favorites.value
                    thirdBlock.append(ContextMenuItem(!saved ? strings().chatContextAddFavoriteSticker : strings().chatContextRemoveFavoriteSticker, handler: {
                        if !saved {
                            let limit = context.isPremium ? context.premiumLimits.stickers_faved_limit_premium : context.premiumLimits.stickers_faved_limit_default
                            if limit >= data.savedStickersCount, !context.isPremium, !context.premiumIsBlocked {
                                showModalText(for: context.window, text: strings().chatContextFavoriteStickersLimitInfo("\(context.premiumLimits.stickers_faved_limit_premium)"), title: strings().chatContextFavoriteStickersLimitTitle, callback: { value in
                                    showPremiumLimit(context: context, type: .faveStickers)
                                })
                            } else {
                                showModalText(for: context.window, text: strings().chatContextStickerAddedToFavorites)
                            }
                            _ = addSavedSticker(postbox: account.postbox, network: account.network, file: file).start()
                        } else {
                            showModalText(for: context.window, text: strings().chatContextStickerRemovedFromFavorites)
                            _ = removeSavedSticker(postbox: account.postbox, mediaId: file.fileId).start()
                        }
                    }, itemImage: image))
                }
                
                if resourceData.complete {
                    if let file = data.file, file.isMusic || file.isVoice, let list = data.notifications {
                        let settings = NotificationSoundSettings.extract(from: context.appConfiguration)
                        let size = file.size ?? 0
                        let contains = list.sounds.contains(where: { $0.file.fileId.id == file.fileId.id })
                        let duration = file.duration ?? 0
                        if size < settings.maxSize, Int(duration) < settings.maxDuration, list.sounds.count < settings.maxSavedCount, !contains {
                            thirdBlock.append(ContextMenuItem(strings().chatContextSaveRingtoneAdd, handler: {
                                let signal = context.engine.peers.saveNotificationSound(file: .message(message: .init(message), media: file))
                                _ = showModalProgress(signal: signal, for: context.window).start(error: { error in
                                    alert(for: context.window, info: strings().unknownError)
                                }, completed: {
                                    showModalText(for: context.window, text: strings().chatContextSaveRingtoneAddSuccess)
                                })
                                
                            }, itemImage: MenuAnimation.menu_note_download.value))
                        } else if contains {
                            thirdBlock.append(ContextMenuItem(strings().chatContextSaveRingtoneRemove, handler: {
                                let signal = context.engine.peers.removeNotificationSound(file: .message(message: .init(message), media: file))
                                _ = showModalProgress(signal: signal, for: context.window).start(error: { error in
                                    alert(for: context.window, info: strings().unknownError)
                                }, completed: {
                                    showModalText(for: context.window, text: strings().chatContextSaveRingtoneRemoveSuccess)
                                })
                                
                            }, itemImage: MenuAnimation.menu_note_slash.value))
                        }
                    }
                    if !data.isMediaStory, data.message.pendingProcessingAttribute == nil {
                        
                        if isHLSVideo(file: file), let quality = HLSQualitySet(baseFile: FileMediaReference.message(message: .init(message), media: file)) {
                            
                            let download = ContextMenuItem(strings().galleryContextSaveVideo, itemImage: MenuAnimation.menu_save_as.value)
                            let downloadMenu = ContextMenu()

                            let downloadOrShow:(TelegramMediaFile)->Void = { file in
                                
                                let status = chatMessageFileStatus(context: context, message: message, file: file)
                                |> take(1)
                                |> deliverOnMainQueue
                                
                                _ = status.startStandalone(next: { status in
                                    let text: String
                                    if status == .Local {
                                        text = strings().galleryContextAlertDownloaded
                                    } else {
                                        _ = messageMediaFileInteractiveFetched(context: context, messageId: message.id, messageReference: .init(message), file: file, userInitiated: true).startStandalone()
                                        text = strings().galleryContextAlertDownloading
                                    }
                                    showModalText(for: context.window, text: text, callback: { _ in
                                        if status == .Local {
                                            showInFinder(file, account: context.account)
                                        } else {
                                            ChatHistoryUIHooks.shared.makeDownloadSearch(context)
                                        }
                                    })
                                })
                            }
                            if context.isPremium {
                                if let size = file.size {
                                    downloadMenu.addItem(ContextMenuItem(strings().galleryContextOriginal + " (\(String.prettySized(with: size)))", handler: {
                                        downloadOrShow(file)
                                    }))
                                }
                            }
                            let sorted = quality.qualityFiles.sorted(by: { $0.key < $1.key })
                            for (key, value) in sorted {
                                let q = "\(ChatNavigationHooks.shared.roundToStandardQuality(key))p"
                                if let size = value.media.size {
                                    downloadMenu.addItem(ContextMenuItem(q + " (\(String.prettySized(with: size)))", handler: {
                                        downloadOrShow(value.media)
                                    }))
                                }
                            }
                            download.submenu = downloadMenu
                            thirdBlock.append(download)
                        } else {
                            thirdBlock.append(ContextMenuItem(strings().chatContextSaveMedia, handler: {
                                saveAs(file, account: account)
                            }, itemImage: MenuAnimation.menu_save_as.value, keyEquivalent: .cmds))
                        }
                       
                    }
                    
                    if data.fileFinderPath != nil {
                    }
                }
               
            } else if data.image != nil, !data.isMediaStory {
                if resourceData.complete {
                    let text = strings().chatContextCopyMedia
                    thirdBlock.append(ContextMenuItem(text, handler: {
                        if copyImageToPasteboard(path: resourceData.path) {
                            showModalText(for: context.window, text: strings().contextAlertCopied)
                        }
                    }, itemImage: MenuAnimation.menu_copy_media.value, keyEquivalent: .cmdc))
                    thirdBlock.append(ContextMenuItem(strings().chatContextSaveMedia, handler: {
                        savePanel(file: resourceData.path, ext: "jpg", for: context.window)
                    }, itemImage: MenuAnimation.menu_save_as.value, keyEquivalent: .cmds))
                }
            }
        }
        
        if (MessageReadMenuItem.canViewReadStats(message: data.message, chatInteraction: data.chatInteraction, appConfig: appConfiguration)), data.isRead, !data.isLogInteraction {
            fourthBlock.append(MessageReadMenuItem(context: context, chatInteraction: data.chatInteraction, message: message, availableReactions: data.availableReactions))
        }
        
        
        if let peer = peer, peer.isChannel, !peer.isAdmin {
            let userCanFactCheck = context.appConfiguration.getBoolValue("can_edit_factcheck", orElse: false)
            
            if canFactCheck(message), userCanFactCheck {
                fifthBlock.append(ContextMenuItem(strings().factCheckContextEdit, handler: {
                    showModal(with: FactCheckController(context: context, message: message), for: context.window)
                }, itemImage: MenuAnimation.menu_verification.value))
            }
        }
        
        if canReportMessage(data.message, context), data.chatMode != .pinned, !data.isLogInteraction {
            
            let reportItem = ContextMenuItem(strings().messageContextReport, handler: {
                ChatNavigationHooks.shared.reportMessages(context, [message.id], strings().reportComplicatedMessageTitle)
            }, itemImage: MenuAnimation.menu_report.value)
                        
            fifthBlock.append(reportItem)
        }
//        if let peer = data.peer as? TelegramChannel, peer.isSupergroup, data.chatMode == .history {
//            if peer.groupAccess.canEditMembers, let author = data.message.author {
//                if author.id != context.peerId, data.message.flags.contains(.Incoming), author.isUser || author.isBot {
//                    fifthBlock.append(ContextMenuItem(strings().chatContextRestrict, handler: {
//                        _ = showModalProgress(signal: context.engine.peers.fetchChannelParticipant(peerId: chatInteraction.peerId, participantId: author.id), for: context.window).start(next: { participant in
//                            if let participant = participant {
//                                switch participant {
//                                case let .member(memberId, _, _, _, _, _):
//                                    showModal(with: RestrictedModalViewController(context, peerId: peerId, memberId: memberId, initialParticipant: participant, updated: { updatedRights in
//                                        _ = context.peerChannelMemberCategoriesContextsManager.updateMemberBannedRights(peerId: peerId, memberId: author.id, bannedRights: updatedRights).startStandalone()
//                                        _ = showModalSuccess(for: context.window, icon: theme.icons.successModalProgress, delay: 3.0).startStandalone()
//                                    }), for: context.window)
//                                default:
//                                    break
//                                }
//                            }
//                        })
//                    }, itemImage: MenuAnimation.menu_restrict.value))
//                    
//                    if data.isLogInteraction {
//                        fifthBlock.append(ContextMenuItem(strings().chatContextBan, handler: {
//                            _ = context.peerChannelMemberCategoriesContextsManager.updateMemberBannedRights(peerId: peerId, memberId: author.id, bannedRights: TelegramChatBannedRights(flags: .banReadMessages, untilDate: .max)).startStandalone()
//                            _ = showModalSuccess(for: context.window, icon: theme.icons.successModalProgress, delay: 3.0).startStandalone()
//                        }, itemMode: .destruct, itemImage: MenuAnimation.menu_ban.value))
//                    }
//                }
//            }
//        }
        
        if data.updatingMessageMedia[messageId] != nil {
            fifthBlock.append(ContextMenuItem(strings().chatContextCancelEditing, handler: {
                account.pendingUpdateMessageManager.cancel(messageId: messageId)
            }, itemImage: MenuAnimation.menu_clear_history.value))
        }

        if canDeleteMessage(data.message, account: account, chatLocation: data.chatLocation, mode: data.chatMode), !data.isLogInteraction {
            fifthBlock.append(ContextMenuItem(strings().messageContextDelete, handler: {
                data.chatInteraction.deleteMessages([data.message.id], nil)
            }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
        }
        
        if data.isLogInteraction {
            if let adminLog = entry?.additionalData.eventLog {
                let config = ChatHistoryUIHooks.shared.antiSpamBotConfiguration(context.appConfiguration)
                if adminLog.peerId == config.antiSpamBotId {
                    firstBlock.append(ContextMenuItem(strings().chatContextReportFalsePositive, handler: {
                        
                        _ = context.engine.peers.reportAntiSpamFalsePositive(peerId: message.id.peerId, messageId: message.id).start()
                        
                        showModalText(for: context.window, text: strings().chatContextReportFalsePositiveThanks)
                        
                    }, itemImage: MenuAnimation.menu_report_false_positive.value))
                }
            }
        }
        
        #if BETA || DEBUG
        if let mediaId = message.media.first?.id, !data.isLogInteraction {
            fifthBlock.append(ContextSeparatorItem())
            fifthBlock.append(ContextMenuItem("Copy Media Id (dev)", handler: {
                copyToClipboard("\(mediaId.id)")
                showModalText(for: context.window, text: "Copied")
            }, itemMode: .normal, itemImage: MenuAnimation.menu_copy.value))
            
            
           
        }
        #endif
        
        
        if let attr = message.textEntities, !isService {
            var references: [StickerPackReference] = attr.entities.compactMap({ value in
                if case let .CustomEmoji(reference, _) = value.type {
                    return reference
                } else {
                    return nil
                }
            })
            
            references += message.associatedMedia.compactMap {
                ($0.value as? TelegramMediaFile)?.emojiReference
            }
            references = references.uniqueElements
            
            let sources: [ChatMediaStickerPackPreviewSource] = references.map {
                .emoji($0)
            }
            
            if !sources.isEmpty {
                
                let text = strings().chatContextMessageContainsEmojiOther(sources.count)
                
                let item = MessageContainsPacksMenuItem(title: text, handler: {
                    showModal(with: ChatMediaUIHooks.shared.makeStickerPackPreview(context, peerId, sources), for: context.window)
                }, packs: references, context: context)
                
                sixBlock.append(item)
            }
        }
        
        if !isService, let edited = message.editedAttribute {
            
            let message_primary_edited_date = context.appConfiguration.getBoolValue("message_primary_edited_date", orElse: false)
            
            let string: String
            let result: String
            if message_primary_edited_date {
                string = stringForRelativeTimestamp(relativeTimestamp: message.timestamp, relativeTo: context.timestamp)
                result = strings().chatMessageMenuSentAt(string)
            } else {
                string = stringForRelativeTimestamp(relativeTimestamp: edited.date, relativeTo: context.timestamp)
                result = strings().chatContextEditedAt(string)
            }
            sevenBlock.append(ContextMenuItem(result, itemImage: MenuAnimation.menu_edited.value))
        }
        
        
        if message.pendingProcessingAttribute != nil {
            sevenBlock.append(ContextMenuItem(strings().chatVideoProccessingContext, removeTail: false))
        }

        if case let .pollOption(opaqueIdentifier) = source, let poll = data.message.anyMedia as? TelegramMediaPoll {
            if let option = poll.options.first(where: { $0.opaqueIdentifier == opaqueIdentifier }), let addedBy = option.addedBy, let date = option.date, let peer = data.message.peers[addedBy] {
                let dateString = stringForFullDate(timestamp: date)
                let name = addedBy == context.peerId ? strings().chatMenuAddedByYou : peer.displayTitle
                let title = strings().chatMenuAddedBy(name, dateString)
                sevenBlock.append(ReactionPeerMenu(title: title, handler: { [weak chatInteraction] in
                    chatInteraction?.openInfo(addedBy, false, nil, nil)
                }, peer: peer, context: context, reaction: nil, removeTail: false, overrideWidth: 200, selfSaved: false))
            }
        }

        let blocks:[[ContextMenuItem]] = [zeroBlock, firstBlock,
                                          add_secondBlock,
                                          thirdBlock,
                                          secondBlock,
                                          fourthBlock,
                                          fifthBlock,
                                          sixBlock, sevenBlock].filter { !$0.isEmpty }
        
        for (i, block) in blocks.enumerated() {
            if i == 0 {
                items.append(contentsOf: block)
            } else {
                items.append(ContextSeparatorItem())
                items.append(contentsOf: block)
            }
        }
        for item in items {
            item.contextObject = data
        }
        return items
    }

}
