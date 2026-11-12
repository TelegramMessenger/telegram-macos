import Cocoa
import TGUIKit
import Postbox
import SwiftSignalKit
import TelegramCore
import TGModernGrowingTextView
import InputView
import ImageCanvasUI
import TelegramContext
import TelegramUtils
import TelegramMediaUtils
import MessageUtils

public struct ChatInterfaceSelectionState: Equatable {
    public let selectedIds: Set<MessageId>
    public let lastSelectedId: MessageId?

    public init(selectedIds: Set<MessageId>, lastSelectedId: MessageId?) {
        self.selectedIds = selectedIds
        self.lastSelectedId = lastSelectedId
    }
    public func withUpdatedSelectedIds(_ ids: Set<MessageId>) -> ChatInterfaceSelectionState {
        return ChatInterfaceSelectionState(selectedIds: ids, lastSelectedId: self.lastSelectedId)
    }
    public func withUpdatedLastSelected(_ lastSelectedId: MessageId?) -> ChatInterfaceSelectionState {
        return ChatInterfaceSelectionState(selectedIds: self.selectedIds, lastSelectedId: lastSelectedId)
    }
}

public struct ChatInterfaceMessageEffect : Equatable, Codable {
    public var effect: AvailableMessageEffects.MessageEffect
    public var fromRect: NSRect?

    public init(effect: AvailableMessageEffects.MessageEffect, fromRect: NSRect?) {
        self.effect = effect
        self.fromRect = fromRect
    }
}

public struct ChatInterfaceMessageActionsState: Codable, Equatable {
    public let closedButtonKeyboardMessageId: MessageId?
    public let processedSetupReplyMessageId: MessageId?

    public var isEmpty: Bool {
        return self.closedButtonKeyboardMessageId == nil && self.processedSetupReplyMessageId == nil
    }

    public init() {
        self.closedButtonKeyboardMessageId = nil
        self.processedSetupReplyMessageId = nil
    }

    public init(closedButtonKeyboardMessageId: MessageId?, processedSetupReplyMessageId: MessageId?) {
        self.closedButtonKeyboardMessageId = closedButtonKeyboardMessageId
        self.processedSetupReplyMessageId = processedSetupReplyMessageId
    }

    public init(from decoder: Decoder) throws {
        
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        
        if let closedMessageIdPeerId = (try? container.decodeIfPresent(Int64.self, forKey: "cb.p")), let closedMessageIdNamespace = (try? container.decodeIfPresent(Int32.self, forKey: "cb.n")), let closedMessageIdId = (try? container.decodeIfPresent(Int32.self, forKey: "cb.i")) {
            self.closedButtonKeyboardMessageId = MessageId(peerId: PeerId(closedMessageIdPeerId), namespace: closedMessageIdNamespace, id: closedMessageIdId)
        } else {
            self.closedButtonKeyboardMessageId = nil
        }

        if let processedMessageIdPeerId = (try? container.decodeIfPresent(Int64.self, forKey: "pb.p")), let processedMessageIdNamespace = (try? container.decodeIfPresent(Int32.self, forKey: "pb.n")), let processedMessageIdId = (try? container.decodeIfPresent(Int32.self, forKey: "pb.i")) {
            self.processedSetupReplyMessageId = MessageId(peerId: PeerId(processedMessageIdPeerId), namespace: processedMessageIdNamespace, id: processedMessageIdId)
        } else {
            self.processedSetupReplyMessageId = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        
        var container = encoder.container(keyedBy: StringCodingKey.self)
        
        
        
        if let id = self.closedButtonKeyboardMessageId {
            try container.encode(id.peerId.toInt64(), forKey: "cb.p")
            try container.encode(id.namespace, forKey: "cb.n")
            try container.encode(id.id, forKey: "cb.i")
        } else {
            try container.encodeNil(forKey: "cb.p")
            try container.encodeNil(forKey: "cb.n")
            try container.encodeNil(forKey: "cb.i")
        }

        if let processedSetupReplyMessageId = self.processedSetupReplyMessageId {
            try container.encode(processedSetupReplyMessageId.peerId.toInt64(), forKey: "pb.p")
            try container.encode(processedSetupReplyMessageId.namespace, forKey: "pb.n")
            try container.encode(processedSetupReplyMessageId.id, forKey: "pb.i")
        } else {
            try container.encodeNil(forKey: "pb.p")
            try container.encodeNil(forKey: "pb.n")
            try container.encodeNil(forKey: "pb.i")
        }
    }


    public func withUpdatedClosedButtonKeyboardMessageId(_ closedButtonKeyboardMessageId: MessageId?) -> ChatInterfaceMessageActionsState {
        return ChatInterfaceMessageActionsState(closedButtonKeyboardMessageId: closedButtonKeyboardMessageId, processedSetupReplyMessageId: self.processedSetupReplyMessageId)
    }

    public func withUpdatedProcessedSetupReplyMessageId(_ processedSetupReplyMessageId: MessageId?) -> ChatInterfaceMessageActionsState {
        return ChatInterfaceMessageActionsState(closedButtonKeyboardMessageId: self.closedButtonKeyboardMessageId, processedSetupReplyMessageId: processedSetupReplyMessageId)
    }
}


public final class ChatEmbeddedInterfaceState {
    public let timestamp: Int32
    public let text: String

    public init(timestamp: Int32, text: String) {
        self.timestamp = timestamp
        self.text = text
    }

    public init(decoder: PostboxDecoder) {
        self.timestamp = decoder.decodeInt32ForKey("d", orElse: 0)
        self.text = decoder.decodeStringForKey("t", orElse: "")
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.timestamp, forKey: "d")
        encoder.encodeString(self.text, forKey: "t")
    }

    public func isEqual(to: ChatEmbeddedInterfaceState) -> Bool {
        return self.timestamp == to.timestamp && self.text == to.text
    }
}

public struct ChatInterfaceHistoryScrollState: Codable, Equatable {
    public let messageIndex: MessageIndex
    public let relativeOffset: Double

    public init(messageIndex: MessageIndex, relativeOffset: Double) {
        self.messageIndex = messageIndex
        self.relativeOffset = relativeOffset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        
        let peerId = PeerId(try container.decode(Int64.self, forKey: "m.p"))
        let namespace = try container.decode(Int32.self, forKey: "m.n")
        let id = try container.decode(Int32.self, forKey: "m.i")
        let messageId = MessageId(peerId: peerId, namespace: namespace, id: id)
        let timestamp = try container.decode(Int32.self, forKey: "m.t")
        
        self.messageIndex = MessageIndex(id: messageId, timestamp: timestamp)
        self.relativeOffset = try container.decode(Double.self, forKey: "ro")
    }

    public func encode(to encoder: Encoder) throws {
        
        var container = encoder.container(keyedBy: StringCodingKey.self)

        
        try container.encode(self.messageIndex.timestamp, forKey: "m.t")
        try container.encode(self.messageIndex.id.peerId.toInt64(), forKey: "m.p")
        try container.encode(self.messageIndex.id.namespace, forKey: "m.n")
        try container.encode(self.messageIndex.id.id, forKey: "m.i")
        try container.encode(self.relativeOffset, forKey: "ro")
    }

    public static func ==(lhs: ChatInterfaceHistoryScrollState, rhs: ChatInterfaceHistoryScrollState) -> Bool {
        if lhs.messageIndex != rhs.messageIndex {
            return false
        }
        if !lhs.relativeOffset.isEqual(to: rhs.relativeOffset) {
            return false
        }
        return true
    }
}

public enum EditStateLoading : Equatable {
    case none
    case loading
    case progress(Float)
}

public final class ChatEditState : Equatable {
    public let inputState:ChatTextInputState
    public let originalMedia: Media?
    public let message:Message
    public let editMedia: RequestEditMessageMedia
    public let loadingState: EditStateLoading
    public let editedData: EditedImageData?
    public let invertMedia: Bool
    public let addedMedia: Bool

    public init(message:Message, originalMedia: Media? = nil, state:ChatTextInputState? = nil, loadingState: EditStateLoading = .none, editMedia: RequestEditMessageMedia = .keep, editedData: EditedImageData? = nil, invertMedia: Bool? = nil, addedMedia: Bool = false) {
        self.message = message
        if originalMedia == nil {
            self.originalMedia = message.anyMedia
        } else {
            self.originalMedia = originalMedia
        }
        if let state = state {
            self.inputState = state
        } else {
            var attribute:TextEntitiesMessageAttribute?
            for attr in message.attributes {
                if let attr = attr as? TextEntitiesMessageAttribute {
                    attribute = attr
                }
            }
            var attributes:[ChatTextInputAttribute] = []
            if let attribute = attribute {
                attributes = chatTextAttributes(from: attribute)
            }
            
            let newText = ChatTextInputState(inputText:message.text, selectionRange: message.text.length ..< message.text.length, attributes: attributes).makeAttributeString(addPreAsBlock: true)

            self.inputState = .init(inputText: newText.string, selectionRange: newText.length ..< newText.length, attributes: chatTextAttributes(from: newText))

        }
        if let invertMedia {
            self.invertMedia = invertMedia
        } else {
            self.invertMedia = message.invertMedia
        }
        self.loadingState = loadingState
        self.editMedia = editMedia
        self.editedData = editedData
        self.addedMedia = addedMedia
    }

    public var canEditMedia: Bool {
        return !message.media.isEmpty && (message.media[0] is TelegramMediaImage || message.media[0] is TelegramMediaFile) && message.pendingProcessingAttribute == nil
    }
    public func withUpdatedMedia(_ media: Media) -> ChatEditState {
        return ChatEditState(message: self.message.withUpdatedMedia([media]).withUpdatedStableVersion(stableVersion: self.message.stableVersion + 1), originalMedia: self.originalMedia ?? self.message.anyMedia, state: self.inputState, loadingState: loadingState, editMedia: .update(AnyMediaReference.standalone(media: media)), editedData: self.editedData, invertMedia: self.invertMedia, addedMedia: self.message.media.isEmpty || self.addedMedia)
    }
    public func withUpdatedLoadingState(_ loadingState: EditStateLoading) -> ChatEditState {
        return ChatEditState(message: self.message, originalMedia: self.originalMedia, state: self.inputState, loadingState: loadingState, editMedia: self.editMedia, editedData: self.editedData, invertMedia: self.invertMedia, addedMedia: self.addedMedia)
    }
    public func withUpdated(state:ChatTextInputState) -> ChatEditState {
        return ChatEditState(message: self.message, originalMedia: self.originalMedia, state: state, loadingState: loadingState, editMedia: self.editMedia, editedData: self.editedData, invertMedia: self.invertMedia, addedMedia: self.addedMedia)
    }

    public func withUpdatedEditedData(_ editedData: EditedImageData?) -> ChatEditState {
        return ChatEditState(message: self.message, originalMedia: self.originalMedia, state: self.inputState, loadingState: self.loadingState, editMedia: self.editMedia, editedData: editedData, invertMedia: self.invertMedia, addedMedia: self.addedMedia)
    }
    public func withUpdatedInvertMedia(_ invertMedia: Bool) -> ChatEditState {
        return ChatEditState(message: self.message, originalMedia: self.originalMedia, state: self.inputState, loadingState: self.loadingState, editMedia: self.editMedia, editedData: self.editedData, invertMedia: invertMedia, addedMedia: self.addedMedia)
    }

    public static func ==(lhs:ChatEditState, rhs:ChatEditState) -> Bool {
        return lhs.message.id == rhs.message.id && lhs.message.stableId == rhs.message.stableId && lhs.inputState == rhs.inputState && lhs.loadingState == rhs.loadingState && lhs.editMedia == rhs.editMedia && lhs.editedData == rhs.editedData && lhs.invertMedia == rhs.invertMedia && lhs.addedMedia == rhs.addedMedia
    }

}


public struct ChatInterfaceTempState: Equatable {
    public let editState: ChatEditState?

    public init(editState: ChatEditState?) {
        self.editState = editState
    }
}


public struct ChatInterfaceState: Codable, Equatable {
    
    public struct ChannelSuggestPost: Equatable {
        
        public enum Mode : Equatable {
            case new
            case suggest(MessageId)
            case edit(MessageId)
        }
        
        public var amount: CurrencyAmount?
        public var date: Int32?
        public var mode: Mode

        public init(amount: CurrencyAmount?, date: Int32?, mode: Mode) {
            self.amount = amount
            self.date = date
            self.mode = mode
        }
        
        public var attribute: SuggestedPostMessageAttribute {
            return SuggestedPostMessageAttribute(amount: amount, timestamp: date, state: nil)
        }
    }
    
    
    public static func == (lhs: ChatInterfaceState, rhs: ChatInterfaceState) -> Bool {
        return lhs.associatedMessageIds == rhs.associatedMessageIds && lhs.historyScrollMessageIndex == rhs.historyScrollMessageIndex && lhs.historyScrollState == rhs.historyScrollState && lhs.editState == rhs.editState && lhs.timestamp == rhs.timestamp && lhs.inputState == rhs.inputState && lhs.replyMessageId == rhs.replyMessageId && lhs.forwardMessageIds == rhs.forwardMessageIds && lhs.dismissedPinnedMessageId == rhs.dismissedPinnedMessageId && lhs.composeDisableUrlPreview == rhs.composeDisableUrlPreview && lhs.dismissedForceReplyId == rhs.dismissedForceReplyId && lhs.messageActionsState == rhs.messageActionsState && isEqualMessageList(lhs: lhs.forwardMessages, rhs: rhs.forwardMessages) && lhs.hideSendersName == rhs.hideSendersName && lhs.themeEditing == rhs.themeEditing && lhs.hideCaptions == rhs.hideCaptions && lhs.revealedSpoilers == rhs.revealedSpoilers && lhs.tempSenderName == rhs.tempSenderName && lhs.linkBelowMessage == rhs.linkBelowMessage && lhs.largeMedia == rhs.largeMedia && lhs.messageEffect == rhs.messageEffect && lhs.suggestPost == rhs.suggestPost
    }

    public var associatedMessageIds: [MessageId] {
        return []
    }



    public var historyScrollMessageIndex: MessageIndex? {
        return self.historyScrollState?.messageIndex
    }

    public let historyScrollState: ChatInterfaceHistoryScrollState?
    public let editState:ChatEditState?
    public let timestamp: Int32
    public let inputState: ChatTextInputState
    public let replyMessageId: EngineMessageReplySubject?
    public let replyMessage: Message?
    public let themeEditing: Bool

    public let forwardMessageIds: [MessageId]
    public let hideSendersName: Bool
    public let hideCaptions: Bool
    
    public let suggestPost: ChannelSuggestPost?
    
    public let linkBelowMessage: Bool
    public let largeMedia: Bool?

    public let tempSenderName: Bool?
    public let forwardMessages: [Message]
    public let dismissedPinnedMessageId:[MessageId]
    public let composeDisableUrlPreview: String?
    public let dismissedForceReplyId: MessageId?
    public let revealedSpoilers:Set<MessageId>

    public let messageActionsState: ChatInterfaceMessageActionsState
    public let messageEffect: ChatInterfaceMessageEffect?
    
    public static func parse(_ state: OpaqueChatInterfaceState?, peerId: PeerId?, context: (any AccountContextProtocol)?) -> ChatInterfaceState? {
        guard let state = state else {
            return nil
        }
        guard let opaqueData = state.opaqueData else {
            return ChatInterfaceState().withUpdatedSynchronizeableInputState(state.synchronizeableInputState).updatedEditState({ _ in
                return ChatHistoryModelHooks.shared.getChatInterfaceTempState(context, peerId)?.editState
            })
        }
        guard var decodedState = try? EngineDecoder.decode(ChatInterfaceState.self, from: opaqueData) else {
            return ChatInterfaceState().withUpdatedSynchronizeableInputState(state.synchronizeableInputState).updatedEditState({ _ in
                return ChatHistoryModelHooks.shared.getChatInterfaceTempState(context, peerId)?.editState
            })
        }
        decodedState = decodedState
            .withUpdatedSynchronizeableInputState(state.synchronizeableInputState)
            .updatedEditState({ _ in
                return ChatHistoryModelHooks.shared.getChatInterfaceTempState(context, peerId)?.editState
            })
        return decodedState

    }

    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encode(self.timestamp, forKey: "ts")
        try container.encode(self.inputState, forKey: "is")
        if let reply = self.replyMessageId {
            try container.encode(reply, forKey: "reply")
        }

        try container.encode(EngineMessage.Id.encodeArrayToData(self.forwardMessageIds), forKey: "fm")
        try container.encode(self.hideCaptions, forKey: "f.hc")
        try container.encode(self.hideSendersName, forKey: "f.sn")


        if self.messageActionsState.isEmpty {
            try container.encodeNil(forKey: "as")
        } else {
            try container.encode(self.messageActionsState, forKey: "as")
        }

        try container.encode(EngineMessage.Id.encodeArrayToData(dismissedPinnedMessageId), forKey: "dpl")


        if let composeDisableUrlPreview = self.composeDisableUrlPreview {
            try container.encode(composeDisableUrlPreview, forKey: "dup")
        } else {
            try container.encodeNil(forKey: "dup")
        }

        if let historyScrollState = self.historyScrollState {
            try container.encode(historyScrollState, forKey: "hss")
        } else {
            try container.encodeNil(forKey: "hss")
        }

        if let dismissedForceReplyId = self.dismissedForceReplyId {
            try container.encode(dismissedForceReplyId, forKey: "dismissed_force_reply")
        }
        
        if let messageEffect {
            try container.encode(messageEffect, forKey: "me")
        }
    }
    

    public var synchronizeableInputState: SynchronizeableChatInputState? {
        if self.inputState.inputText.isEmpty && self.replyMessageId == nil {
            return nil
        } else {
            return SynchronizeableChatInputState(replySubject: self.replyMessageId, text: self.inputState.inputText, entities: self.inputState.messageTextEntities(), timestamp: self.timestamp, textSelection: self.inputState.selectionRange, messageEffectId: self.messageEffect?.effect.id, suggestedPost: self.suggestPost.flatMap { value in
                switch value.mode {
                case .new:
                    return .init(price: value.amount, timestamp: value.date)
                default:
                    return nil
                }
            })
        }
    }

    public func withUpdatedSynchronizeableInputState(_ state: SynchronizeableChatInputState?) -> ChatInterfaceState {
        var result = self
        if let state = state {
            let selectRange = state.textSelection ?? state.text.length ..< state.text.length
            let inputState: ChatTextInputState
            if self.inputState.inputText == state.text && self.inputState.messageTextEntities() == state.entities {
                inputState = self.inputState.withUpdatedRange(selectRange)
            } else {
                let restored = ChatTextInputState(inputText: state.text, selectionRange: selectRange, attributes: chatTextAttributes(from: TextEntitiesMessageAttribute(entities: state.entities)))
                inputState = ChatTextInputState(attributedText: chatInputTextExcludingAnalytics(restored.attributedString()), selectionRange: selectRange)
            }
            result = result.withUpdatedInputState(inputState)
                .withUpdatedReplyMessageId(state.replySubject)
                .withUpdatedTimestamp(timestamp)
        } else {
            result = result.withUpdatedInputState(.init()).withUpdatedHistoryScrollState(self.historyScrollState)
        }
        return result
    }


    public init() {
        self.timestamp = 0
        self.inputState = ChatTextInputState()
        self.replyMessageId = nil
        self.replyMessage = nil
        self.forwardMessageIds = []
        self.forwardMessages = []
        self.messageActionsState = ChatInterfaceMessageActionsState()
        self.dismissedPinnedMessageId = []
        self.composeDisableUrlPreview = nil
        self.historyScrollState = nil
        self.dismissedForceReplyId = nil
        self.editState = nil
        self.hideSendersName = false
        self.themeEditing = false
        self.hideCaptions = false
        self.tempSenderName = nil
        self.revealedSpoilers = Set()
        self.linkBelowMessage = true
        self.largeMedia = nil
        self.messageEffect = nil
        self.suggestPost = nil
    }

    public init(timestamp: Int32, inputState: ChatTextInputState, replyMessageId: EngineMessageReplySubject?, replyMessage: Message?, forwardMessageIds: [MessageId], messageActionsState:ChatInterfaceMessageActionsState, dismissedPinnedMessageId: [MessageId], composeDisableUrlPreview: String?, historyScrollState: ChatInterfaceHistoryScrollState?, dismissedForceReplyId: MessageId?, editState: ChatEditState?, forwardMessages:[Message], hideSendersName: Bool, themeEditing: Bool, hideCaptions: Bool, revealedSpoilers: Set<MessageId>, tempSenderName: Bool?, linkBelowMessage: Bool, largeMedia: Bool?, messageEffect: ChatInterfaceMessageEffect?, suggestPost: ChannelSuggestPost?) {
        self.timestamp = timestamp
        self.inputState = inputState
        self.replyMessageId = replyMessageId
        self.forwardMessageIds = forwardMessageIds
        self.messageActionsState = messageActionsState
        self.dismissedPinnedMessageId = dismissedPinnedMessageId
        self.composeDisableUrlPreview = composeDisableUrlPreview
        self.historyScrollState = historyScrollState
        self.dismissedForceReplyId = dismissedForceReplyId
        self.editState = editState
        self.replyMessage = replyMessage
        self.forwardMessages = forwardMessages
        self.hideSendersName = hideSendersName
        self.themeEditing = themeEditing
        self.hideCaptions = hideCaptions
        self.revealedSpoilers = revealedSpoilers
        self.tempSenderName = tempSenderName
        self.linkBelowMessage = linkBelowMessage
        self.largeMedia = largeMedia
        self.messageEffect = messageEffect
        self.suggestPost = suggestPost
    }

    public init(from decoder: Decoder) throws {
        
        let container = try decoder.container(keyedBy: StringCodingKey.self)


        
        self.timestamp = (try? container.decode(Int32.self, forKey: "ts")) ?? 0
        if let inputState = try? container.decode(ChatTextInputState.self, forKey: "is") {
            self.inputState = inputState
        } else {
            self.inputState = ChatTextInputState()
        }

        self.replyMessageId = try container.decodeIfPresent(EngineMessageReplySubject.self, forKey: "reply")

        if let forwardMessageIdsData = try container.decodeIfPresent(Data.self, forKey: "fm") {
            self.forwardMessageIds = EngineMessage.Id.decodeArrayFromData(forwardMessageIdsData)
        } else {
            self.forwardMessageIds = []
        }
        if let hideCaptions = try container.decodeIfPresent(Bool.self, forKey: "f.hc") {
            self.hideCaptions = hideCaptions
        } else {
            self.hideCaptions = false
        }
        if let hideSendersName = try container.decodeIfPresent(Bool.self, forKey: "f.sn") {
            self.hideSendersName = hideSendersName
        } else {
            self.hideSendersName = false
        }

        if let messageActionsState = try container.decodeIfPresent(ChatInterfaceMessageActionsState.self, forKey: "as") {
            self.messageActionsState = messageActionsState
        } else {
            self.messageActionsState = ChatInterfaceMessageActionsState()
        }


        if let dismissedPinnedData = try container.decodeIfPresent(Data.self, forKey: "dpl") {
            self.dismissedPinnedMessageId = EngineMessage.Id.decodeArrayFromData(dismissedPinnedData)
        } else {
            self.dismissedPinnedMessageId = []
        }

        self.composeDisableUrlPreview = try container.decodeIfPresent(String.self, forKey: "dup")
        

        self.historyScrollState = try container.decodeIfPresent(ChatInterfaceHistoryScrollState.self, forKey: "hss")


        self.dismissedForceReplyId = try container.decodeIfPresent(MessageId.self, forKey: "dismissed_force_reply")
        self.messageEffect = try container.decodeIfPresent(ChatInterfaceMessageEffect.self, forKey: "me")
        
        self.editState = nil
        self.replyMessage = nil
        self.forwardMessages = []
        self.themeEditing = false
        self.revealedSpoilers = Set()
        self.tempSenderName = nil
        self.linkBelowMessage = true
        self.largeMedia = nil
        self.suggestPost = nil
    }


    public func withUpdatedInputState(_ inputState: ChatTextInputState) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.editState == nil ? inputState : self.inputState, replyMessageId: self.replyMessageId, replyMessage: self.replyMessage, forwardMessageIds: self.forwardMessageIds, messageActionsState:self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: self.historyScrollState, dismissedForceReplyId: self.dismissedForceReplyId, editState: self.editState?.withUpdated(state: inputState), forwardMessages: self.forwardMessages, hideSendersName: self.hideSendersName, themeEditing: self.themeEditing, hideCaptions: self.hideCaptions, revealedSpoilers: self.revealedSpoilers, tempSenderName: self.tempSenderName,  linkBelowMessage: self.linkBelowMessage, largeMedia: self.largeMedia, messageEffect: self.messageEffect, suggestPost: self.suggestPost)
    }

    public func withAddedDismissedPinnedIds(_ dismissedPinnedId: [MessageId]) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, replyMessage: self.replyMessage, forwardMessageIds: self.forwardMessageIds, messageActionsState:self.messageActionsState, dismissedPinnedMessageId: (self.dismissedPinnedMessageId + dismissedPinnedId).uniqueElements, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: self.historyScrollState, dismissedForceReplyId: self.dismissedForceReplyId, editState: self.editState, forwardMessages: self.forwardMessages, hideSendersName: self.hideSendersName, themeEditing: self.themeEditing, hideCaptions: self.hideCaptions, revealedSpoilers: self.revealedSpoilers, tempSenderName: self.tempSenderName,  linkBelowMessage: self.linkBelowMessage, largeMedia: self.largeMedia, messageEffect: self.messageEffect, suggestPost: self.suggestPost)
    }

    public func withUpdatedDismissedForceReplyId(_ dismissedId: MessageId?) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, replyMessage: self.replyMessage, forwardMessageIds: self.forwardMessageIds, messageActionsState:self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: self.historyScrollState, dismissedForceReplyId: dismissedId, editState: self.editState, forwardMessages: self.forwardMessages, hideSendersName: self.hideSendersName, themeEditing: self.themeEditing, hideCaptions: self.hideCaptions, revealedSpoilers: self.revealedSpoilers, tempSenderName: self.tempSenderName,  linkBelowMessage: self.linkBelowMessage, largeMedia: self.largeMedia, messageEffect: self.messageEffect, suggestPost: self.suggestPost)
    }

    public func updatedEditState(_ f:(ChatEditState?)->ChatEditState?) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, replyMessage: self.replyMessage, forwardMessageIds: self.forwardMessageIds, messageActionsState:self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: self.historyScrollState, dismissedForceReplyId: self.dismissedForceReplyId, editState: f(self.editState), forwardMessages: self.forwardMessages, hideSendersName: self.hideSendersName, themeEditing: self.themeEditing, hideCaptions: self.hideCaptions, revealedSpoilers: self.revealedSpoilers, tempSenderName: self.tempSenderName,  linkBelowMessage: self.linkBelowMessage, largeMedia: self.largeMedia, messageEffect: self.messageEffect, suggestPost: self.suggestPost)
    }

    public func withEditMessage(_ message:Message) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, replyMessage: self.replyMessage, forwardMessageIds: self.forwardMessageIds, messageActionsState:self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: self.historyScrollState, dismissedForceReplyId: self.dismissedForceReplyId, editState: ChatEditState(message: message), forwardMessages: self.forwardMessages, hideSendersName: self.hideSendersName, themeEditing: self.themeEditing, hideCaptions: self.hideCaptions, revealedSpoilers: self.revealedSpoilers, tempSenderName: self.tempSenderName,  linkBelowMessage: self.linkBelowMessage, largeMedia: self.largeMedia, messageEffect: self.messageEffect, suggestPost: self.suggestPost)
    }

    public func withoutEditMessage() -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, replyMessage: self.replyMessage, forwardMessageIds: self.forwardMessageIds, messageActionsState:self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: self.historyScrollState, dismissedForceReplyId: self.dismissedForceReplyId, editState: nil, forwardMessages: self.forwardMessages, hideSendersName: self.hideSendersName, themeEditing: self.themeEditing, hideCaptions: self.hideCaptions, revealedSpoilers: self.revealedSpoilers, tempSenderName: self.tempSenderName,  linkBelowMessage: self.linkBelowMessage, largeMedia: self.largeMedia, messageEffect: self.messageEffect, suggestPost: self.suggestPost)
    }

    public func withUpdatedReplyMessageId(_ replyMessageId: EngineMessageReplySubject?) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: replyMessageId, replyMessage: nil, forwardMessageIds: self.forwardMessageIds, messageActionsState:self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: self.historyScrollState, dismissedForceReplyId: self.dismissedForceReplyId, editState: self.editState, forwardMessages: self.forwardMessages, hideSendersName: self.hideSendersName, themeEditing: self.themeEditing, hideCaptions: self.hideCaptions, revealedSpoilers: self.revealedSpoilers, tempSenderName: self.tempSenderName,  linkBelowMessage: self.linkBelowMessage, largeMedia: self.largeMedia, messageEffect: self.messageEffect, suggestPost: self.suggestPost)
    }

    public func withUpdatedReplyMessage(_ replyMessage: Message?) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, replyMessage: replyMessage, forwardMessageIds: self.forwardMessageIds, messageActionsState:self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: self.historyScrollState, dismissedForceReplyId: self.dismissedForceReplyId, editState: self.editState, forwardMessages: self.forwardMessages, hideSendersName: self.hideSendersName, themeEditing: self.themeEditing, hideCaptions: self.hideCaptions, revealedSpoilers: self.revealedSpoilers, tempSenderName: self.tempSenderName,  linkBelowMessage: self.linkBelowMessage, largeMedia: self.largeMedia, messageEffect: self.messageEffect, suggestPost: self.suggestPost)
    }

    public func withUpdatedForwardMessageIds(_ forwardMessageIds: [MessageId]) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, replyMessage: self.replyMessage, forwardMessageIds: forwardMessageIds, messageActionsState:self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: self.historyScrollState, dismissedForceReplyId: self.dismissedForceReplyId, editState: self.editState, forwardMessages: self.forwardMessages, hideSendersName: forwardMessageIds.isEmpty ? false : self.hideSendersName, themeEditing: self.themeEditing, hideCaptions: forwardMessageIds.isEmpty ? false : self.hideCaptions, revealedSpoilers: self.revealedSpoilers, tempSenderName: self.tempSenderName,  linkBelowMessage: self.linkBelowMessage, largeMedia: self.largeMedia, messageEffect: self.messageEffect, suggestPost: self.suggestPost)
    }

    public func withUpdatedForwardMessages(_ forwardMessages: [Message]) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, replyMessage: self.replyMessage, forwardMessageIds: forwardMessageIds, messageActionsState:self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: self.historyScrollState, dismissedForceReplyId: self.dismissedForceReplyId, editState: self.editState, forwardMessages: forwardMessages, hideSendersName: hideSendersName, themeEditing: self.themeEditing, hideCaptions: self.hideCaptions, revealedSpoilers: self.revealedSpoilers, tempSenderName: self.tempSenderName,  linkBelowMessage: self.linkBelowMessage, largeMedia: self.largeMedia, messageEffect: self.messageEffect, suggestPost: self.suggestPost)
    }
    
   

    public func withoutForwardMessages() -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, replyMessage: self.replyMessage, forwardMessageIds: [], messageActionsState:self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: self.historyScrollState, dismissedForceReplyId: self.dismissedForceReplyId, editState: self.editState, forwardMessages: self.forwardMessages, hideSendersName: self.hideSendersName, themeEditing: self.themeEditing, hideCaptions: self.hideCaptions, revealedSpoilers: self.revealedSpoilers, tempSenderName: self.tempSenderName,  linkBelowMessage: self.linkBelowMessage, largeMedia: self.largeMedia, messageEffect: self.messageEffect, suggestPost: self.suggestPost)
    }

    public func withUpdatedTimestamp(_ timestamp: Int32) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, replyMessage: self.replyMessage, forwardMessageIds: self.forwardMessageIds, messageActionsState:self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: self.historyScrollState, dismissedForceReplyId: self.dismissedForceReplyId, editState: self.editState, forwardMessages: self.forwardMessages, hideSendersName: self.hideSendersName, themeEditing: self.themeEditing, hideCaptions: self.hideCaptions, revealedSpoilers: self.revealedSpoilers, tempSenderName: self.tempSenderName,  linkBelowMessage: self.linkBelowMessage, largeMedia: self.largeMedia, messageEffect: self.messageEffect, suggestPost: self.suggestPost)
    }


    public func withUpdatedMessageActionsState(_ f: (ChatInterfaceMessageActionsState) -> ChatInterfaceMessageActionsState) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, replyMessage: self.replyMessage, forwardMessageIds: self.forwardMessageIds, messageActionsState:f(self.messageActionsState), dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: self.historyScrollState, dismissedForceReplyId: self.dismissedForceReplyId, editState: self.editState, forwardMessages: self.forwardMessages, hideSendersName: self.hideSendersName, themeEditing: self.themeEditing, hideCaptions: self.hideCaptions, revealedSpoilers: self.revealedSpoilers, tempSenderName: self.tempSenderName,  linkBelowMessage: self.linkBelowMessage, largeMedia: self.largeMedia, messageEffect: self.messageEffect, suggestPost: self.suggestPost)
    }

    public func withUpdatedComposeDisableUrlPreview(_ disableUrlPreview: String?) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, replyMessage: self.replyMessage, forwardMessageIds: self.forwardMessageIds, messageActionsState: self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: disableUrlPreview, historyScrollState: self.historyScrollState, dismissedForceReplyId: self.dismissedForceReplyId, editState: self.editState, forwardMessages: self.forwardMessages, hideSendersName: self.hideSendersName, themeEditing: self.themeEditing, hideCaptions: self.hideCaptions, revealedSpoilers: self.revealedSpoilers, tempSenderName: self.tempSenderName,  linkBelowMessage: self.linkBelowMessage, largeMedia: self.largeMedia, messageEffect: self.messageEffect, suggestPost: self.suggestPost)
    }

    public func withUpdatedHistoryScrollState(_ historyScrollState: ChatInterfaceHistoryScrollState?) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, replyMessage: self.replyMessage, forwardMessageIds: self.forwardMessageIds, messageActionsState: self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: historyScrollState, dismissedForceReplyId: self.dismissedForceReplyId, editState: self.editState, forwardMessages: self.forwardMessages, hideSendersName: self.hideSendersName, themeEditing: self.themeEditing, hideCaptions: self.hideCaptions, revealedSpoilers: self.revealedSpoilers, tempSenderName: self.tempSenderName,  linkBelowMessage: self.linkBelowMessage, largeMedia: self.largeMedia, messageEffect: self.messageEffect, suggestPost: self.suggestPost)
    }
    
    public func withUpdatedThemeEditing(_ themeEditing: Bool) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, replyMessage: self.replyMessage, forwardMessageIds: self.forwardMessageIds, messageActionsState: self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: historyScrollState, dismissedForceReplyId: self.dismissedForceReplyId, editState: self.editState, forwardMessages: self.forwardMessages, hideSendersName: self.hideSendersName, themeEditing: themeEditing, hideCaptions: self.hideCaptions, revealedSpoilers: self.revealedSpoilers, tempSenderName: self.tempSenderName,  linkBelowMessage: self.linkBelowMessage, largeMedia: self.largeMedia, messageEffect: self.messageEffect, suggestPost: self.suggestPost)
    }
    
    public func withRevealedSpoiler(_ messageId: MessageId) -> ChatInterfaceState {
        var set = self.revealedSpoilers
        set.insert(messageId)
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, replyMessage: self.replyMessage, forwardMessageIds: self.forwardMessageIds, messageActionsState: self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: historyScrollState, dismissedForceReplyId: self.dismissedForceReplyId, editState: self.editState, forwardMessages: self.forwardMessages, hideSendersName: self.hideSendersName, themeEditing: self.themeEditing, hideCaptions: self.hideCaptions, revealedSpoilers: set, tempSenderName: self.tempSenderName,  linkBelowMessage: self.linkBelowMessage, largeMedia: self.largeMedia, messageEffect: self.messageEffect, suggestPost: self.suggestPost)
    }

    public func withUpdatedHideCaption(_ hideCaption: Bool) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, replyMessage: self.replyMessage, forwardMessageIds: self.forwardMessageIds, messageActionsState: self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: historyScrollState, dismissedForceReplyId: self.dismissedForceReplyId, editState: self.editState, forwardMessages: self.forwardMessages, hideSendersName: self.hideSendersName, themeEditing: self.themeEditing, hideCaptions: hideCaption, revealedSpoilers: self.revealedSpoilers, tempSenderName: self.tempSenderName,  linkBelowMessage: self.linkBelowMessage, largeMedia: self.largeMedia, messageEffect: self.messageEffect, suggestPost: self.suggestPost)
    }
    
    public func withUpdatedHideSendersName(_ hideSendersName: Bool, saveTempValue: Bool) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, replyMessage: self.replyMessage, forwardMessageIds: forwardMessageIds, messageActionsState:self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: self.historyScrollState, dismissedForceReplyId: self.dismissedForceReplyId, editState: self.editState, forwardMessages: self.forwardMessages, hideSendersName: hideSendersName, themeEditing: self.themeEditing, hideCaptions: self.hideCaptions, revealedSpoilers: self.revealedSpoilers, tempSenderName: saveTempValue ? hideSendersName : self.tempSenderName, linkBelowMessage: self.linkBelowMessage, largeMedia: self.largeMedia, messageEffect: self.messageEffect, suggestPost: self.suggestPost)
    }
    
    public func withUpdatedLinkBelowMessage(_ linkBelowMessage: Bool) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, replyMessage: self.replyMessage, forwardMessageIds: forwardMessageIds, messageActionsState:self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: self.historyScrollState, dismissedForceReplyId: self.dismissedForceReplyId, editState: self.editState, forwardMessages: self.forwardMessages, hideSendersName: hideSendersName, themeEditing: self.themeEditing, hideCaptions: self.hideCaptions, revealedSpoilers: self.revealedSpoilers, tempSenderName: self.tempSenderName, linkBelowMessage: linkBelowMessage, largeMedia: self.largeMedia, messageEffect: self.messageEffect, suggestPost: self.suggestPost)
    }
    
    public func withUpdatedLargeMedia(_ largeMedia: Bool) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, replyMessage: self.replyMessage, forwardMessageIds: forwardMessageIds, messageActionsState:self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: self.historyScrollState, dismissedForceReplyId: self.dismissedForceReplyId, editState: self.editState, forwardMessages: self.forwardMessages, hideSendersName: hideSendersName, themeEditing: self.themeEditing, hideCaptions: self.hideCaptions, revealedSpoilers: self.revealedSpoilers, tempSenderName: self.tempSenderName, linkBelowMessage: self.linkBelowMessage, largeMedia: largeMedia, messageEffect: self.messageEffect, suggestPost: self.suggestPost)
    }
    
    public func withUpdatedMessageEffect(_ messageEffect: ChatInterfaceMessageEffect?) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, replyMessage: self.replyMessage, forwardMessageIds: forwardMessageIds, messageActionsState:self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: self.historyScrollState, dismissedForceReplyId: self.dismissedForceReplyId, editState: self.editState, forwardMessages: self.forwardMessages, hideSendersName: hideSendersName, themeEditing: self.themeEditing, hideCaptions: self.hideCaptions, revealedSpoilers: self.revealedSpoilers, tempSenderName: self.tempSenderName, linkBelowMessage: self.linkBelowMessage, largeMedia: self.largeMedia, messageEffect: messageEffect, suggestPost: self.suggestPost)
    }
    
    public func withRemovedEffectRect() -> ChatInterfaceState {
        let messageEffect: ChatInterfaceMessageEffect?
        if let effect = self.messageEffect {
            messageEffect = .init(effect: effect.effect, fromRect: nil)
        } else {
            messageEffect = nil
        }
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, replyMessage: self.replyMessage, forwardMessageIds: forwardMessageIds, messageActionsState:self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: self.historyScrollState, dismissedForceReplyId: self.dismissedForceReplyId, editState: self.editState, forwardMessages: self.forwardMessages, hideSendersName: hideSendersName, themeEditing: self.themeEditing, hideCaptions: self.hideCaptions, revealedSpoilers: self.revealedSpoilers, tempSenderName: self.tempSenderName, linkBelowMessage: self.linkBelowMessage, largeMedia: self.largeMedia, messageEffect: messageEffect, suggestPost: self.suggestPost)
    }
    
    
    public func withUpdatedSuggestPost(_ suggestPost: ChannelSuggestPost?) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, replyMessage: self.replyMessage, forwardMessageIds: forwardMessageIds, messageActionsState:self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: self.historyScrollState, dismissedForceReplyId: self.dismissedForceReplyId, editState: self.editState, forwardMessages: self.forwardMessages, hideSendersName: hideSendersName, themeEditing: self.themeEditing, hideCaptions: self.hideCaptions, revealedSpoilers: self.revealedSpoilers, tempSenderName: self.tempSenderName, linkBelowMessage: self.linkBelowMessage, largeMedia: self.largeMedia, messageEffect: self.messageEffect, suggestPost: suggestPost)
    }
}
