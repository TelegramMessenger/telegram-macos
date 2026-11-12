import Cocoa
import Postbox
import TelegramCore
import TGUIKit
import SwiftSignalKit
import MapKit
import InputView
import CurrencyFormat
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import InAppSettings
import ChatModeTypes
import ChatHistoryModel
import TelegramMediaUtils
import MessageUtils
import AlertsUI
import LocalAnimations
import TelegramCallsCore
import StarsUI
import BoostUI
import AudioPlayerCore
import ShortPeerRow
import AppAnalytics

private final class ComposerAnalyticsScopeReference {
    weak var scope: AnalyticsScope?

    init(_ scope: AnalyticsScope) {
        self.scope = scope
    }
}

private struct ComposerAnalyticsScopeState {
    var revision: UInt64 = 0
    var scopes: [ComposerAnalyticsScopeReference] = []
}

struct ChatMediaReplacementRequest {
    fileprivate let id: UUID
    fileprivate let messageId: MessageId
    fileprivate let journey: AnalyticsMediaEditJourney?
    fileprivate let token: Int?
}

public final class ReplyMarkupInteractions {
    public let context: any AccountContextProtocol
    public let proccess:(ReplyMarkupButton, @escaping(Bool)->Void) -> Void
    
    public init(context: any AccountContextProtocol, proccess:@escaping (ReplyMarkupButton, @escaping(Bool)->Void)->Void) {
        self.context = context
        self.proccess = proccess
    }
    
}


public final class ChatInteraction : InterfaceObserver  {
    
    public var chatLocation: ChatLocation {
        return self.presentation.chatLocation
    }
    
    public var isMonoforum: Bool {
        return presentation.isMonoforum
    }
    
    public func threadInfo(_ peerId: PeerId, holder: Atomic<ChatLocationContextHolder?>) -> ThreadInfo? {
        if (self.presentation.isTopicMode && peerId == self.peerId) || mode.isSavedMessagesThread || self.presentation.monoforumState != nil {
            switch chatLocation {
            case let .thread(data):
                if data.threadId == Message.newTopicThreadId {
                    return nil
                }
                return .init(message: data, isChannelPost: false, isMonoforumPost: chatLocation.threadMessage?.isMonoforumPost == true, isEmpty: false, contextHolder: holder)
            default:
                break
            }
        }
        return nil
    }
    
    public var mode: ChatMode {
        return presentation.chatMode
    }
    public var peerId : PeerId {
        return chatLocation.peerId
    }
    
    public var activitySpace: PeerActivitySpace {
        return .init(peerId: peerId, category: mode.activityCategory(chatLocation.threadId))
    }
    
    public var peer: Peer? {
        return presentation.peer
    }
    
    let context: any AccountContextProtocol
    public var interactionContext: any AccountContextProtocol {
        return context
    }
    public let isLogInteraction:Bool
    public let disableSelectAbility: Bool
    public let isGlobalSearchMessage: Bool
    public let isPeerSavedMessages: Bool
    public let bottomInset: Atomic<CGFloat> = Atomic(value: ChatHistoryBottomRowItem.bottomInset(showsInput: true, inputOverlayHeight: 0))
    public var inheritedAnalyticsContext: AnalyticsContext?
    private var mediaEditJourney: AnalyticsMediaEditJourney?
    private var mediaReplacementId: UUID?
    private var mediaEditSessionId = UUID()
    private var mediaEditSubmissionId: UUID?
    private var deferredSendRevision = UUID()
    private let composerAnalyticsScopes = Atomic(value: ComposerAnalyticsScopeState())
    private let forwardSelection = ChatForwardSelection()
    private let composerForwardPreparation = ChatForwardSendPreparation()
    private let quickForwardAction = ChatQuickForwardAction()

    func quickForward(_ object: ChatHistoryForwardMessagesObject, peerId: PeerId, threadId: Int64?, analyticsContext: AnalyticsContext, action: ChatDeferredSendAction) {
        quickForwardAction.start(context: context, peerId: peerId, threadId: threadId, analyticsContext: analyticsContext, isCurrent: { action.takeIfCurrent() }, request: {
            object.chatHistoryPerformObserved(to: peerId, threadId: threadId)
        })
    }

    func invalidateDeferredSendActions() {
        deferredSendRevision = UUID()
        composerForwardPreparation.reset()
    }

    public func captureDeferredSendAction() -> ChatDeferredSendAction {
        let revision = deferredSendRevision
        let richDraftRevision = ChatInteraction.globalRichTextDrafts.captureRevision(for: richTextDraftKey)
        return ChatDeferredSendAction { [weak self] in
            guard let self else { return false }
            return self.deferredSendRevision == revision && richDraftRevision.isValid
        }
    }

    var isPreparingForwardSend: Bool { composerForwardPreparation.isPending }

    func prepareForwardSend<Value>(onInvalidated: @escaping () -> Void, request: @escaping () -> Signal<Value, NoError>) -> Signal<Value, NoError> {
        let action = captureDeferredSendAction()
        return composerForwardPreparation.prepare(isCurrent: { action.isAvailable }, invalidated: onInvalidated, request: request)
    }

    func beginMediaReplacement(entry: AnalyticsMediaEditJourney.Spec.EntryPoint, mode: AnalyticsMediaEditJourney.Spec.MediaMode, context: AnalyticsContext? = nil) -> ChatMediaReplacementRequest? {
        guard let state = presentation.interfaceState.editState else { return nil }
        let id = UUID()
        mediaReplacementId = id
        let journey = mediaEditAnalyticsJourney(entry: entry, mode: mode, context: context)
        let token = journey?.beginReplacement(entry: entry, mode: mode)
        if mediaEditSubmissionId != nil {
            mediaEditSubmissionId = nil
            editDisposable.set(nil)
            update { $0.updatedInterfaceState { $0.updatedEditState { $0?.withUpdatedLoadingState(.none) } } }
        }
        return ChatMediaReplacementRequest(id: id, messageId: state.message.id, journey: journey, token: token)
    }

    private func mediaEditAnalyticsJourney(entry: AnalyticsMediaEditJourney.Spec.EntryPoint, mode: AnalyticsMediaEditJourney.Spec.MediaMode, context: AnalyticsContext?) -> AnalyticsMediaEditJourney? {
        guard let state = presentation.interfaceState.editState else { return nil }
        let context = Analytics.shared.captureContext(engine: interactionContext.engine, peerId: peerId, inherited: context ?? captureAnalyticsContext()).restricting(peerId: state.message.id.peerId)
        if context.isExcluded || context.scope?.isValid != true {
            mediaEditJourney?.discard()
        }
        if mediaEditJourney == nil {
            switch self.mode {
            case .history, .thread, .scheduled:
                mediaEditJourney = AnalyticsMediaEditJourney(context: context, entry: entry, mode: mode)
            default:
                break
            }
        }
        return mediaEditJourney
    }

    func rejectMediaReplacement(entry: AnalyticsMediaEditJourney.Spec.EntryPoint, mode: AnalyticsMediaEditJourney.Spec.MediaMode, context: AnalyticsContext, reason: AnalyticsMediaEditJourney.Spec.LastBlocker) {
        mediaEditAnalyticsJourney(entry: entry, mode: mode, context: context)?.rejectedReplacement(entry: entry, reason: reason)
    }

    func failMediaReplacement(_ request: ChatMediaReplacementRequest?, reason: AnalyticsMediaEditJourney.Spec.LastBlocker) {
        guard let request, isCurrentMediaReplacement(request) else { return }
        mediaReplacementId = nil
        if let token = request.token { request.journey?.failedReplacement(token, reason: reason) }
    }

    func applyMediaReplacement(_ media: Media, request: ChatMediaReplacementRequest?) {
        guard let request, isCurrentMediaReplacement(request) else { return }
        mediaReplacementId = nil
        update { $0.updatedInterfaceState { $0.updatedEditState { $0?.withUpdatedMedia(media) } } }
        if let token = request.token { request.journey?.appliedReplacement(token) }
    }

    func isCurrentMediaReplacement(_ request: ChatMediaReplacementRequest?) -> Bool {
        guard let request else { return false }
        return request.id == mediaReplacementId && presentation.interfaceState.editState?.message.id == request.messageId
    }

    func cancelMediaReplacement(_ request: ChatMediaReplacementRequest?) {
        guard let request, request.id == mediaReplacementId else { return }
        mediaReplacementId = nil
        if let token = request.token { request.journey?.cancelledSelection(token) }
    }

    func discardMediaReplacement(_ request: ChatMediaReplacementRequest?) {
        guard let request, request.id == mediaReplacementId else { return }
        mediaReplacementId = nil
        request.journey?.discard()
    }

    func beginMediaEditSubmission(context: AnalyticsContext, scheduled: Bool, keepsEditingOnFailure: Bool, media: RequestEditMessageMedia) -> (UUID, AnalyticsMediaEditSubmission?) {
        let id = UUID()
        mediaEditSubmissionId = id
        let journey = mediaEditJourney
        if !keepsEditingOnFailure { mediaEditJourney = nil }
        mediaReplacementId = nil
        guard context.scope?.isValid == true, !context.isExcluded, media != .keep, media == presentation.interfaceState.editState?.editMedia else {
            journey?.discard()
            return (id, nil)
        }
        return (id, journey?.beginSubmission(scheduled: scheduled, allowsRetry: keepsEditingOnFailure))
    }

    func isCurrentMediaEditSubmission(_ id: UUID) -> Bool {
        return mediaEditSubmissionId == id
    }

    func blockMediaEdit(_ reason: AnalyticsMediaEditJourney.Spec.LastBlocker) {
        mediaEditJourney?.blocked(reason)
    }

    public func captureAnalyticsContext(sourcePeerId: PeerId? = nil) -> AnalyticsContext {
        let revision = composerAnalyticsScopes.with { $0.revision }
        let context = Analytics.shared.captureContext(engine: interactionContext.engine, peerId: peerId, inherited: inheritedAnalyticsContext)
        let restricted = restrictComposerAnalyticsContext(context)
        return rememberComposerAnalyticsContext(sourcePeerId.map { restricted.restricting(peerId: $0) } ?? restricted, revision: revision)
    }

    public func captureAnalyticsContext(inherited: AnalyticsContext) -> AnalyticsContext {
        let revision = composerAnalyticsScopes.with { $0.revision }
        let current = captureAnalyticsContext()
        guard !current.isExcluded, current.scope?.isValid == true else { return current }
        return rememberComposerAnalyticsContext(Analytics.shared.captureContext(engine: interactionContext.engine, peerId: peerId, inherited: inherited), revision: revision)
    }

    private func restrictComposerAnalyticsContext(_ context: AnalyticsContext) -> AnalyticsContext {
        guard !presentation.effectiveInput.hasExcludedAnalytics else { return Analytics.shared.unresolvedContext() }
        var context = context
        context = restrictRichTextDraftAnalyticsContext(context)
        if let peer = peer {
            context = context.restricting(peerId: peer.id)
        }
        let interfaceState = presentation.interfaceState
        if let reply = interfaceState.replyMessageId {
            context = context.restricting(peerId: reply.messageId.peerId)
            guard let message = interfaceState.replyMessage, message.id == reply.messageId, !message.containsSecretMedia else {
                return Analytics.shared.unresolvedContext()
            }
            context = context.restricting(peerId: message.id.peerId)
        }
        let forwardIds = Set(interfaceState.forwardMessageIds)
        for messageId in forwardIds {
            context = context.restricting(peerId: messageId.peerId)
        }
        if !forwardIds.isEmpty {
            var resolvedIds = Set<MessageId>()
            for message in interfaceState.forwardMessages {
                guard !message.containsSecretMedia else { return Analytics.shared.unresolvedContext() }
                context = context.restricting(peerId: message.id.peerId)
                resolvedIds.insert(message.id)
            }
            guard resolvedIds == forwardIds else { return Analytics.shared.unresolvedContext() }
        }
        if let message = interfaceState.editState?.message {
            guard !message.containsSecretMedia else { return Analytics.shared.unresolvedContext() }
            context = context.restricting(peerId: message.id.peerId)
        }
        return context
    }

    private func rememberComposerAnalyticsContext(_ context: AnalyticsContext, revision: UInt64) -> AnalyticsContext {
        let current = composerAnalyticsScopes.modify { state in
            var state = state
            state.scopes.removeAll { $0.scope == nil }
            if state.revision == revision, let scope = context.scope, !state.scopes.contains(where: { $0.scope === scope }) {
                state.scopes.append(ComposerAnalyticsScopeReference(scope))
            }
            return state
        }
        if current.revision != revision { context.scope?.exclude() }
        return context
    }

    private func revokePrivateComposerAnalytics() {
        guard restrictComposerAnalyticsContext(Analytics.shared.privacyContext(peerId: peerId)).isExcluded else { return }
        var scopes: [AnalyticsScope] = []
        _ = composerAnalyticsScopes.modify { state in
            var state = state
            state.revision &+= 1
            scopes = state.scopes.compactMap { $0.scope }
            state.scopes.removeAll()
            return state
        }
        for scope in scopes { scope.exclude() }
    }

    public func makeMediaAnalyticsJourney(context: AnalyticsContext?, entry: AnalyticsMediaJourney.Spec.EntryPoint, mode: AnalyticsMediaJourney.Spec.MediaMode, via: AnalyticsValues.Via? = nil, source: AnalyticsScreen? = nil) -> AnalyticsMediaJourney? {
        guard let context = context, presentation.interfaceState.editState == nil else { return nil }
        let origin = captureAnalyticsContext(inherited: context)
        guard origin.scope?.isValid == true else { return nil }
        switch self.mode {
        case .history, .thread, .scheduled:
            return AnalyticsMediaJourney(context: origin, entry: entry, mode: mode, via: via, source: source)
        default:
            return nil
        }
    }
    private let modifyDisposable:MetaDisposable = MetaDisposable()
    private let mediaDisposable:MetaDisposable = MetaDisposable()
    private let recordingMediaDisposable = MetaDisposable()
    private let recordingSubmissionDisposable = MetaDisposable()
    private let startBotDisposable:MetaDisposable = MetaDisposable()
    private var isStartingBot = false
    private let addContactDisposable:MetaDisposable = MetaDisposable()
    private let requestSessionId:MetaDisposable = MetaDisposable()
    public let editDisposable = MetaDisposable()
    private let disableProxyDisposable = MetaDisposable()
    private let enableProxyDisposable = MetaDisposable()
    
    
    
    
    public init(chatLocation: ChatLocation, context: any AccountContextProtocol, mode: ChatMode = .history, isLogInteraction: Bool = false, disableSelectAbility: Bool = false, isGlobalSearchMessage: Bool = false, isPeerSavedMessages: Bool = false) {
        self.context = context
        self.disableSelectAbility = disableSelectAbility
        self.isLogInteraction = isLogInteraction
        self.isGlobalSearchMessage = isGlobalSearchMessage
        self.isPeerSavedMessages = isPeerSavedMessages
        self._presentation = Atomic(value: ChatPresentationInterfaceState(chatLocation: chatLocation, chatMode: mode))
        super.init()
        
        let signal = mediaPromise.get() |> deliverOnMainQueue |> mapToQueue { [weak self] (media) -> Signal<Void, NoError> in
            self?.sendMedia(media)
            return .single(Void())
        }
        mediaDisposable.set(signal.start())
        let recordingSignal = recordingMediaPromise.get() |> deliverOnMainQueue |> mapToQueue { [weak self] media, analyticsContext -> Signal<Void, NoError> in
            self?.sendMediaObserved(media, journey: nil, analyticsContext: analyticsContext)
            return .single(Void())
        }
        recordingMediaDisposable.set(recordingSignal.start())
        let submissionSignal = recordingSubmissionPromise.get() |> deliverOnMainQueue
        recordingSubmissionDisposable.set(submissionSignal.start(next: { [weak self] media, analyticsContext, request in
            guard let self else {
                request?.end()
                return
            }
            self.sendRecordingMediaObserved(media, analyticsContext: analyticsContext, request: request)
        }))
    }
    
    private let _presentation: Atomic<ChatPresentationInterfaceState>
    public var presentation:ChatPresentationInterfaceState {
        return _presentation.with { $0 }
    }
    
    public func update(animated:Bool = true, _ f:(ChatPresentationInterfaceState)->ChatPresentationInterfaceState)->Void {
        let oldValue = self.presentation
        var newValue = f(oldValue)
        if newValue.sendPaidMessageStars != oldValue.sendPaidMessageStars || newValue.peer?.id != oldValue.peer?.id {
            let alwaysPaidMessage = newValue.sendPaidMessageStars.flatMap { FastSettings.needConfirmPaid(newValue.peer?.id ?? peerId, price: Int($0.value)) } ?? false
            newValue = newValue.withUpdatedAlwaysPaidMessage(alwaysPaidMessage)
        }
        if let appliedAIEditorDraft {
            let input = newValue.effectiveInput
            if input.inputText != appliedAIEditorDraft.inputText || input.attributes != appliedAIEditorDraft.attributes ||
                newValue.interfaceState.editState != nil || newValue.chatLocation != oldValue.chatLocation || newValue.chatMode != oldValue.chatMode {
                self.appliedAIEditorDraft = nil
            }
        }
        _ = _presentation.swap(newValue)
        revokePrivateComposerAnalytics()
        if !chatHasSameDeferredSendState(oldValue, presentation) {
            invalidateDeferredSendActions()
        }
        if oldValue.selectionState?.selectedIds != presentation.selectionState?.selectedIds || oldValue.chatLocation != presentation.chatLocation || oldValue.chatMode != presentation.chatMode || (oldValue.reportMode != nil) != (presentation.reportMode != nil) {
            forwardSelection.reset()
        }
        if oldValue.interfaceState.editState?.message.id != presentation.interfaceState.editState?.message.id || oldValue.chatLocation != presentation.chatLocation || oldValue.chatMode != presentation.chatMode {
            mediaEditSessionId = UUID()
            mediaEditSubmissionId = nil
            mediaReplacementId = nil
            mediaEditJourney?.endEditing()
            mediaEditJourney = nil
        }
        if oldValue.chatLocation != presentation.chatLocation || oldValue.chatMode != presentation.chatMode {
            dateHeaderActions.reset()
        }
        if oldValue != presentation {
            notifyObservers(value: presentation, oldValue:oldValue, animated:animated && canAnimateUpdates())
        }
    }
    
    public var withToggledSelectedMessage:((ChatPresentationInterfaceState)->ChatPresentationInterfaceState)->Void = { _ in }
    
    public enum AttachMediaType {
        case photo
        case video
    }
    public struct Schedule {
        public var date: Date
        public var repeatPeriod: Int32?
        public init(date: Date, repeatPeriod: Int32? = nil) {
            self.date = date
            self.repeatPeriod = repeatPeriod
        }
    }
    
    public var setupReplyMessage: (Message?, EngineMessageReplySubject?) -> Void = { _, _ in}
    public var beginMessageSelection: (MessageId?) -> Void = {_ in}
    public var deleteMessages: ([MessageId], (() -> NSView?)?) -> Void = {_, _ in }
    public var forwardMessages: ([Message]) -> Void = {_ in}
    public var forwardMessagesWithContext: (([Message], AnalyticsContext) -> Void)?
    public var forwardMessagesWithSource: (([Message], AnalyticsContext, AnalyticsFlows.ChatForwardPicker.EntryPoint) -> Void)?
    public var forwardMessagesWithJourney: (([Message], AnalyticsContext, AnalyticsFlows.ChatForwardPicker.EntryPoint, AnalyticsForwardPickerJourney) -> Void)?
    public func forwardMessagesObserved(_ messages: [Message], analyticsContext: AnalyticsContext) {
        forwardMessagesObserved(messages, analyticsContext: analyticsContext, entry: nil)
    }
    public func forwardMessagesObserved(_ messages: [Message], analyticsContext: AnalyticsContext, entry: AnalyticsFlows.ChatForwardPicker.EntryPoint?) {
        forwardMessagesObserved(messages, analyticsContext: analyticsContext, entry: entry, journey: nil)
    }
    public func forwardMessagesObserved(_ messages: [Message], analyticsContext: AnalyticsContext, entry: AnalyticsFlows.ChatForwardPicker.EntryPoint?, journey: AnalyticsForwardPickerJourney?) {
        var origin = Analytics.shared.captureContext(engine: context.engine, peerId: peerId, inherited: analyticsContext)
        for message in messages {
            if message.containsSecretMedia { origin = Analytics.shared.unresolvedContext() }
            origin = origin.restricting(peerId: message.id.peerId)
        }
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        if let journey, let entry, let forwardMessagesWithJourney {
            journey.restrict(to: origin)
            forwardMessagesWithJourney(messages, origin, entry, journey)
            return
        }
        journey?.discard()
        if let entry, let forwardMessagesWithSource {
            forwardMessagesWithSource(messages, origin, entry)
        } else if let forwardMessagesWithContext {
            forwardMessagesWithContext(messages, origin)
        } else {
            forwardMessages(messages)
        }
    }
    public var reportMessages:(ReportReasonValue, [MessageId]) -> Void = { _, _ in }
    public var sendMessage: (Bool, Schedule?, AvailableMessageEffects.MessageEffect?) -> Void = { _, _, _ in }
    var sendAIEditorResult: (() -> Void)?
    private(set) var appliedAIEditorDraft: ChatTextInputState?

    func applyAIEditorDraft(_ draft: ChatTextInputState) {
        if alwaysUseAIEditorPeerId != nil, presentation.interfaceState.editState == nil {
            appliedAIEditorDraft = draft
        }
        update { $0.withUpdatedEffectiveInputState(draft) }
    }

    var alwaysUseAIEditorPeerId: PeerId? {
        switch mode {
        case .history, .thread, .scheduled:
            return peerId.namespace == Namespaces.Peer.SecretChat ? nil : peerId
        default:
            return nil
        }
    }
    public var sendMessageWithAnalytics: ((Bool, Schedule?, AvailableMessageEffects.MessageEffect?, AnalyticsMediaSubmission?, Int) -> Void)?
    public func sendMessageObserved(_ silent: Bool, _ schedule: Schedule?, _ effect: AvailableMessageEffects.MessageEffect?, submission: AnalyticsMediaSubmission?, part: Int) {
        let origin = captureAnalyticsContext(inherited: submission?.context ?? Analytics.shared.unresolvedContext())
        submission?.restrict(to: origin)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        if let sendMessageWithAnalytics = sendMessageWithAnalytics {
            sendMessageWithAnalytics(silent, schedule, effect, submission, part)
        } else {
            submission?.discard()
            sendMessage(silent, schedule, effect)
        }
    }
    public var sendPlainText: (String) -> Void = {_ in}
    public var sendPlainTextWithAnalytics: ((String, AnalyticsContext, AnalyticsRecordingRequest?) -> Void)?
    public func sendPlainTextObserved(_ text: String, analyticsContext: AnalyticsContext, request: AnalyticsRecordingRequest?) {
        if let sendPlainTextWithAnalytics {
            sendPlainTextWithAnalytics(text, analyticsContext, request)
        } else {
            request?.end()
            sendPlainText(text)
        }
    }
    
    public var focusMessageId: (MessageId?, ChatFocusTarget, TableScrollState) -> Void = { _, _, _  in}
    public var focusPinnedMessageId: (MessageId) -> Void = { _ in}
    public var sendMedia:([MediaSenderContainer]) -> Void = {_ in}
    public var sendMediaWithJourney: (([MediaSenderContainer], AnalyticsMediaJourney?, AnalyticsContext?) -> Void)?
    public var sendRecordingMediaWithAnalytics: (([MediaSenderContainer], AnalyticsContext, AnalyticsRecordingRequest?) -> Void)?
    public func sendRecordingMediaObserved(_ media: [MediaSenderContainer], analyticsContext: AnalyticsContext, request: AnalyticsRecordingRequest?) {
        let origin = captureAnalyticsContext(inherited: analyticsContext)
        request?.restrict(to: origin)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        if let sendRecordingMediaWithAnalytics {
            sendRecordingMediaWithAnalytics(media, origin, request)
        } else {
            request?.end()
            sendMediaObserved(media, journey: nil, analyticsContext: origin)
        }
    }
    public func sendMediaObserved(_ media: [MediaSenderContainer], journey: AnalyticsMediaJourney?) {
        sendMediaObserved(media, journey: journey, analyticsContext: nil)
    }
    public func sendMediaObserved(_ media: [MediaSenderContainer], journey: AnalyticsMediaJourney?, analyticsContext: AnalyticsContext?) {
        let origin = captureAnalyticsContext(inherited: analyticsContext ?? Analytics.shared.unresolvedContext())
        journey?.restrict(to: origin)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        if let sendMediaWithJourney = sendMediaWithJourney {
            sendMediaWithJourney(media, journey, origin)
        } else {
            journey?.discard()
            sendMedia(media)
        }
    }
    public var sendCreatedStickerWithAnalytics: ((TelegramMediaFile, AnalyticsContext, AnalyticsStickerSendRequest?) -> Void)?
    public var sendAppFile:(TelegramMediaFile, Bool, String?, Bool, ItemCollectionId?, ChatTextInputState?, ChatInteraction.Schedule?) -> Void = { _,_, _, _, _, _, _ in}
    public var sendAppFileWithContext: ((TelegramMediaFile, Bool, String?, Bool, ItemCollectionId?, ChatTextInputState?, Schedule?, AnalyticsContext) -> Void)?
    public func sendAppFileObserved(_ file: TelegramMediaFile, _ silent: Bool, _ query: String?, _ scheduled: Bool, _ collectionId: ItemCollectionId?, _ caption: ChatTextInputState?, _ schedule: Schedule?, analyticsContext: AnalyticsContext) {
        let origin = captureAnalyticsContext(inherited: analyticsContext)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        if let sendAppFileWithContext {
            sendAppFileWithContext(file, silent, query, scheduled, collectionId, caption, schedule, origin)
        } else {
            sendAppFile(file, silent, query, scheduled, collectionId, caption, schedule)
        }
    }
    public var sendMedias:([Media], ChatTextInputState, Bool, ChatTextInputState?, Bool, Schedule?, Bool, AvailableMessageEffects.MessageEffect?, Bool) -> Void = {_,_,_,_,_,_,_,_, _ in}
    public var sendMediasWithAnalytics: (([Media], ChatTextInputState, Bool, ChatTextInputState?, Bool, Schedule?, Bool, AvailableMessageEffects.MessageEffect?, Bool, AnalyticsMediaSubmission?, Int) -> Void)?
    public func sendMediasObserved(_ medias: [Media], _ caption: ChatTextInputState, _ collage: Bool, _ additionalText: ChatTextInputState?, _ silent: Bool, _ schedule: Schedule?, _ spoiler: Bool, _ effect: AvailableMessageEffects.MessageEffect?, _ leadingText: Bool, submission: AnalyticsMediaSubmission?, part: Int) {
        let origin = captureAnalyticsContext(inherited: submission?.context ?? Analytics.shared.unresolvedContext())
        submission?.restrict(to: origin)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        if let sendMediasWithAnalytics = sendMediasWithAnalytics {
            sendMediasWithAnalytics(medias, caption, collage, additionalText, silent, schedule, spoiler, effect, leadingText, submission, part)
        } else {
            submission?.discard()
            sendMedias(medias, caption, collage, additionalText, silent, schedule, spoiler, effect, leadingText)
        }
    }
    public var focusInputField:()->Void = {}
    public var openInfo:(PeerId, Bool, MessageId?, ChatInitialAction?) -> Void = {_,_,_,_  in}
    public var openInfoWithAnalytics: ((PeerId, Bool, MessageId?, ChatInitialAction?, AnalyticsContext) -> Void)?
    public func openInfoObserved(_ peerId: PeerId, _ toChat: Bool, _ postId: MessageId?, _ action: ChatInitialAction?, analyticsContext: AnalyticsContext) {
        let inherited = Analytics.shared.captureContext(engine: interactionContext.engine, peerId: peerId, inherited: analyticsContext)
        let current = captureAnalyticsContext(inherited: inherited)
        let origin = inherited.isExcluded ? inherited : current
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        if let openInfoWithAnalytics {
            openInfoWithAnalytics(peerId, toChat, postId, action, origin)
        } else {
            openInfo(peerId, toChat, postId, action)
        }
    }
    public func openInfoFromMessage(_ peerId: PeerId, _ toChat: Bool, _ postId: MessageId?, _ action: ChatInitialAction?, message: Message?) {
        let origin: AnalyticsContext
        if let message, !message.containsSecretMedia {
            origin = captureAnalyticsContext(sourcePeerId: message.id.peerId)
        } else {
            origin = Analytics.shared.unresolvedContext()
        }
        openInfoObserved(peerId, toChat, postId, action, analyticsContext: origin)
    }
    public var beginEditingMessage:(Message?) -> Void = {_ in}
    public var requestMessageActionCallback:(MessageId, Bool, (requiresPassword: Bool, data: MemoryBuffer)?) -> Void = {_,_,_  in}
    public var inlineAudioPlayer:(APController) -> Void = {_ in}
    public var movePeerToInput:(Peer) -> Void = {_ in}
    public var sendInlineResult:(ChatContextResultCollection,ChatContextResult) -> Void = {_,_  in}
    public var scrollToLatest:(Bool)->Void = {_ in}
    public var shareSelfContact:(MessageId?)->Void = {_ in}
    public var shareLocation:()->Void = {}
    public var modalSearch:(String)->Void = {_ in }
    public var sendCommand:(ChatInputCommand)->Void = {_ in }
    public var setNavigationAction:(NavigationModalAction)->Void = {_ in}
    public var switchInlinePeer:(PeerId, ChatInitialAction)->Void = {_,_  in}
    public var presentPreviewSender:([URL], Bool, NSAttributedString?, AnalyticsContext)->Void = {_,_,_,_ in}
    public var presentPreviewSenderWithJourney: (([URL], Bool, NSAttributedString?, AnalyticsContext, AnalyticsMediaJourney?) -> Void)?
    public func showPreviewSender(_ urls: [URL], _ asMedia: Bool, _ attributedString: NSAttributedString?, analyticsContext: AnalyticsContext? = nil) {
        let origin = captureAnalyticsContext(inherited: analyticsContext ?? captureAnalyticsContext())
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        presentPreviewSender(urls, asMedia, attributedString, origin)
    }
    public func showPreviewSender(_ urls: [URL], _ asMedia: Bool, _ attributedString: NSAttributedString?, analyticsContext: AnalyticsContext?, journey: AnalyticsMediaJourney?) {
        let origin = captureAnalyticsContext(inherited: analyticsContext ?? captureAnalyticsContext())
        journey?.restrict(to: origin)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        if let presentPreviewSenderWithJourney = presentPreviewSenderWithJourney {
            presentPreviewSenderWithJourney(urls, asMedia, attributedString, origin, journey)
        } else {
            journey?.discard()
            presentPreviewSender(urls, asMedia, attributedString, origin)
        }
    }
    public var setChatMessageAutoremoveTimeout:(Int32?)->Void = {_ in}
    public var toggleNotifications:(Bool?)->Void = { _ in }
    public var removeAndCloseChat:()->Void = {}
    public var joinChannel:()->Void = {}
    public var returnGroup:()->Void = {}
    public var shareContact:(TelegramUser)->Void = {_ in}
    public var unblock:()->Void = {}
    public var updatePinned:(MessageId, Bool, Bool, Bool)->Void = {_,_,_,_ in}
    public var reportSpamAndClose:()->Void = {}
    public var dismissPeerStatusOptions:()->Void = {}
    public var dismissRequestChat: ()->Void = {}
    public var toggleSidebar:()->Void = {}
    public var mentionPressed:()->Void = {}
    let dateHeaderActions = ChatDateHeaderActions()
    public var jumpToDate:(Date)->Void = {_ in}
    public var showNextPost:()->Void = {}
    public var startRecording:(Bool, NSView?)->Void = {_,_ in}
    public var startDictation:()->Void = {}
    public var startRecordingWithAnalytics: ((Bool, NSView?, AnalyticsValues.Via?) -> Void)?
    public func startRecordingObserved(_ hold: Bool, _ view: NSView?, via: AnalyticsValues.Via?) {
        if let startRecordingWithAnalytics {
            startRecordingWithAnalytics(hold, view, via)
        } else {
            startRecording(hold, view)
        }
    }
    public var openProxySettings: ()->Void = {}
    public var sendLocation: (CLLocationCoordinate2D, MapVenue?) -> Void = {_, _ in}
    public var clearMentions:()->Void = {}
    public var reactionPressed:()->Void = {}
    public var showToaster:(NSAttributedString)->Void = { _ in }
    public var previewTopic:(Int64)->Void = { _ in }
    public var showRestrictionToast:(String)->Void = { _ in }
    public var removeToaster:()->Void = {}
    public var clearReactions:()->Void = {}
    public var attachFile:(Bool)->Void = { _ in }
    public var attachPhotoOrVideo:(AttachMediaType?)->Void = { _ in }
    public var attachPicture:()->Void = {}
    public var attachLocation:((() -> NSView?)?)->Void = { _ in }
    public var attachAudio:((() -> NSView?)?)->Void = { _ in }
    public var updateEditingMessageMedia:([String]?, Bool) -> Void = { _, _ in}
    public var editEditingMessagePhoto:(TelegramMediaImage) -> Void = { _ in}
    public var removeChatInteractively:()->Void = { }
    public var updateSearchRequest: (SearchMessagesResultState)->Void = { _ in }
    public var searchPeerMessages: (Peer) -> Void = { _ in }
    public var vote:(MessageId, [Data], Bool) -> Void = { _, _, _ in }
    public var closePoll:(MessageId) -> Void = { _ in }
    public var addPollOption:(MessageId, TelegramMediaPollOption) -> Void = { _, _ in }
    public var deletePollOption:(MessageId, Data) -> Void = { _, _ in }
    public var openDiscussion:()->Void = { }
    public var addContact:()->Void = {}
    public var blockContact: ()->Void = {}
    public var openScheduledMessages: ()->Void = {}
    public var openBank: (String)->Void = { _ in }
    public var afterSentTransition:()->Void = {}
    public var getGradientOffsetRect:()->NSRect = {  return .zero }
    public var markAdAction:(Data, Bool)->Void = { _, _ in }
    public var contextHolder:()->Atomic<ChatLocationContextHolder?> = { Atomic(value: nil) }

    var voiceSendFlight: ChatVoiceSendFlight?
    var voiceTranscription: ChatVoiceTranscription?
    public var mediaSendFlight: ChatMediaSendFlight?

    private var walletTransferAnimationStorage: AnyObject?
    @available(macOS 10.15, *)
    var walletTransferAnimation: ChatWalletTransferAnimation? {
        get {
            return self.walletTransferAnimationStorage as? ChatWalletTransferAnimation
        }
        set {
            self.walletTransferAnimationStorage = newValue
        }
    }
    
    public var freezeAccountAlert:()->Void = { }
    
    public var openFocusedMedia:(Int32?)->Void = { _ in return }
    
    public var push:(ViewController)->Void = { _ in }
    public var back:()->Void = { }
    
    public var openPinnedMessages: (MessageId)->Void = { _ in }
    public var unpinAllMessages: ()->Void = {}
    public var setLocation: (ChatHistoryLocation)->Void = { _ in }
    public var scrollToTheFirst: () -> Void = {}
    public var openReplyThread:(MessageId, Bool, Bool, ReplyThreadMode)->Void = {  _, _, _, _ in }
    
    public var transcribeAudio:(Message)->Void = { _ in }
    
    public var joinGroupCall:(CachedChannelData.ActiveCall, String?)->Void = { _, _ in }
    
    public var runEmojiScreenEffect:(String, Message, Bool, Bool)->Void = { _, _, _, _ in }
    public var runPremiumScreenEffect:(Message, Bool, Bool)->Void = { _, _, _ in }
    public var runReactionEffect:(MessageReaction.Reaction, MessageId, Bool)->Void = { _, _, _ in }
    
    public var toggleSendAs: (PeerId)->Void = { _ in }
    
    public var showDeleterSetup:(Control)->Void = { _ in }
    
    public var showEmojiUseTooltip:()->Void = { }
    public var restartTopic: ()->Void = { }
    public var openSetPeerAvatar: ()->Void = { }
    public var revealMedia:(Message)->Void = { _ in }
    public var toggleTranslate:()->Void = { }
    public var hideTranslation:()->Void = { }
    public var openStories: (_ f:@escaping(PeerId, MessageId?, Int32?)-> NSView?, ((Signal<Never, NoError>)->Void)?)->Void = { _, _ in }
    public var openChatPeerStories: (MessageId, PeerId, ((Signal<Never, NoError>)->Void)?)->Void = { _, _, _ in }
    public var doNotTranslate:(String)->Void = { _ in }
    public var translateTo:(String)->Void = { _ in }
    public var setTranslateTone:(TranslationTone)->Void = { _ in }
    public var enableTranslatePaywall:()->Void = { }
    public var summarize:(Message)->Void = { _ in }
    public var clearSummarize:(MessageId)->Void = { _ in }
    public var openPendingRequests:()->Void = { }
    public var dismissPendingRequests:([PeerId])->Void = { _ in }
    public var setupChatThemes:()->Void = { }
    public var closeChatThemes:()->Void = { }
    public var appendAttributedText:(NSAttributedString)->Void = { _ in }
    public var setLocationTag:(HistoryViewInputTag?)->Void = { _ in }
    public var revealFactCheck:(MessageId)->Void = { _ in }
    public var togglePollSolution:(MessageId)->Void = { _ in }

    public var hashtag:(String)->Void = { _ in }
    
    public var sendMessageMenu:(Bool)->Signal<ContextMenu?, NoError> = { _ in .single(nil) }
    
    public var removeAd:(Data)->Void = { _ in }
    
    public var canAnimateUpdates:()->Bool = { true }
    
    public var boostToUnrestrict:(BoostChannelSource)->Void = { _ in }
    
    public var executeReplymarkup:(MessageId)->Void = { _ in }
    public var toggleUnderMouseMessage:()->Void = { }
    
    public var openStory:(MessageId, StoryId)->Void = { _, _ in }
    public var openStoryWithAnalytics: ((MessageId, StoryId, AnalyticsContext) -> Void)?
    public func openStoryObserved(_ messageId: MessageId, _ storyId: StoryId, analyticsContext: AnalyticsContext) {
        let inherited = Analytics.shared.captureContext(engine: interactionContext.engine, peerId: messageId.peerId, inherited: analyticsContext).restricting(peerId: storyId.peerId)
        let current = captureAnalyticsContext(inherited: inherited)
        let origin = inherited.isExcluded ? inherited : current
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        if let openStoryWithAnalytics {
            openStoryWithAnalytics(messageId, storyId, origin)
        } else {
            openStory(messageId, storyId)
        }
    }
    
    public var sendMessageShortcut:(ShortcutMessageList.Item)->Void = { _ in }
    
    public var replyToAnother:(EngineMessageReplySubject, Bool)->Void = { _, _ in }
    
    var enqueueCodeSyntax:(MessageId, NSRange, String, String, ChatInterfaceSyntaxTheme)->Void = { _, _, _, _, _ in }
    public var interactionEnqueueCodeSyntax:(MessageId, NSRange, String, String, ChatInterfaceSyntaxTheme)->Void {
        get {
            return enqueueCodeSyntax
        }
        set {
            enqueueCodeSyntax = newValue
        }
    }
    
    public var openPhoneNumberContextMenu: (String)->Void = { _ in }
    public var openTonAddressContextMenu: (String)->Void = { _ in }
    
    public var toggleQuote: (QuoteMessageIndex)->Void = { _ in }
    public var toggleDetails: (DetailsMessageIndex)->Void = { _ in }

    public var markAdAsSeen:(Data)->Void = { _ in }
    
    public var openMonoforum:(PeerId)->Void = { peerId in }
    public var toggleMonoforumState:()->Void = { }
    public var monoforumMenuItems:(MonoforumItem) -> Signal<[ContextMenuItem], NoError> = { _ in return .single([]) }

    public var sendGift:((() -> NSView?)?)->Void = { _ in }
    public var editPostSuggestion:(ChatInterfaceState.ChannelSuggestPost)->Void = { _ in }
    public var diceRoll:()->Void = { }
    public var sendDiceWithStake:(Int64)->Void = { _ in }

    public var updateChatLocationThread:(Int64?)->Void = { _ in }
    
    public var appendTask:(Message)->Void = { _ in }
    
    
    public func chatLocationInput(_ message: Message) -> ChatLocationInput {
        if mode.isThreadMode, chatLocation.threadMsgId == message.id {
            return context.chatLocationInput(for: .peer(message.id.peerId), contextHolder: contextHolder())
        } else {
            return context.chatLocationInput(for: self.chatLocation, contextHolder: contextHolder())
        }
    }
    
    public func suggestPost() {
        self.update({
            $0.updatedInterfaceState {
                $0.withUpdatedSuggestPost(.init(amount: nil, date: nil, mode: .new))
            }
        })
        if let data = self.presentation.interfaceState.suggestPost {
            showModal(with: EditPostSuggestionController(chatInteraction: self, data: data), for: self.context.window)
        }
    }
    
    public var updateFrame:(NSRect, ContainedViewLayoutTransition) -> Void = { _, _ in }
    
    public var unarchive: ()->Void = { }
    
    public var closeAfterPeek:(Int32)->Void = { _ in }
    
    public var updateReactions: (MessageId, String, @escaping(Bool)->Void)->Void = { _, _, _ in }
    
    
    public let loadingMessage: Promise<Bool> = Promise()
    public let mediaPromise:Promise<[MediaSenderContainer]> = Promise()
    public let recordingMediaPromise = Promise<([MediaSenderContainer], AnalyticsContext)>()
    public let recordingSubmissionPromise = Promise<([MediaSenderContainer], AnalyticsContext, AnalyticsRecordingRequest?)>()

    // A structural rich-text draft (composed in the rich editor) that the plain `ChatTextInputState` can't
    // represent (lists/tables/media). Stored as its compiled `InstantPage` so it renders read-only in the
    // composer (InstantPageV2) and sends as a `RichTextMessageAttribute`. nil when there is no rich draft.
    //
    // Backed by a process-global per-chat store so the draft survives the chat controller being torn down
    // and reopened, with its contents stored in the item cache across launches.
    private static let globalRichTextDrafts = ChatRichTextDraftStore<InstantPage, AnalyticsContext>()
    private var richTextDraftKey: ChatRichTextDraftKey {
        return richTextDraftKey(threadId: chatLocation.threadId)
    }
    private func richTextDraftKey(threadId: Int64?) -> ChatRichTextDraftKey {
        let isWelcome: Bool
        if case .welcomeMessages = mode.customChatContents?.kind {
            isWelcome = true
        } else {
            isWelcome = false
        }
        return ChatRichTextDraftKey(accountId: context.account.id.int64, peerId: peerId.toInt64(), threadId: threadId, isWelcome: isWelcome, isCustomEditor: mode.customChatContents != nil || mode.customChatLink != nil)
    }
    private let richTextDraftPromise = ValuePromise<InstantPage?>(nil, ignoreRepeated: false)
    private var persistentRichTextDraftId: EngineDataBuffer? {
        return persistentRichTextDraftId(threadId: chatLocation.threadId)
    }
    private func persistentRichTextDraftId(threadId: Int64?) -> EngineDataBuffer? {
        guard mode.customChatContents == nil, mode.customChatLink == nil else {
            return nil
        }
        let id = EngineDataBuffer(length: 16)
        id.setInt64(0, value: peerId.toInt64())
        id.setInt64(8, value: threadId ?? 0)
        return id
    }
    public var richTextDraft: InstantPage? { ChatInteraction.globalRichTextDrafts.value(for: richTextDraftKey) }
    public var richTextDraftSignal: Signal<InstantPage?, NoError> { richTextDraftPromise.get() }
    public var flushRichTextDraft: (() -> Void)?
    public var storePendingRichTextDraft: (() -> Void)?
    public var storePendingRichTextEditorDraft: (() -> Void)?
    private var unshownPersistentRichTextDraftKey: ChatRichTextDraftKey?
    private func restrictRichTextDraftAnalyticsContext(_ context: AnalyticsContext) -> AnalyticsContext {
        guard let draft = ChatInteraction.globalRichTextDrafts.entry(for: richTextDraftKey) else { return context }
        guard let origin = draft.origin, !origin.isExcluded, origin.scope?.isValid == true else {
            return Analytics.shared.unresolvedContext()
        }
        guard !context.isExcluded else { return context }
        guard let scope = context.scope else { return context }
        guard scope.isValid else { return Analytics.shared.unresolvedContext() }
        return Analytics.shared.captureContext(engine: interactionContext.engine, peerId: peerId, inherited: origin)
    }
    public func setRichTextDraft(_ page: InstantPage?, analyticsContext: AnalyticsContext? = nil, persist: Bool = true) {
        let origin = page == nil ? nil : captureAnalyticsContext(inherited: analyticsContext ?? Analytics.shared.unresolvedContext())
        if ChatInteraction.globalRichTextDrafts.set(page, for: richTextDraftKey, origin: origin) {
            invalidateDeferredSendActions()
        }
        revokePrivateComposerAnalytics()
        richTextDraftPromise.set(page)
        if persist, page != nil || unshownPersistentRichTextDraftKey != richTextDraftKey {
            unshownPersistentRichTextDraftKey = nil
            storePersistentRichTextDraft(page, threadId: chatLocation.threadId)
        }
    }
    public func storeRichTextDraftSnapshot(_ page: InstantPage, threadId: Int64?) {
        let key = richTextDraftKey(threadId: threadId)
        guard let existing = ChatInteraction.globalRichTextDrafts.entry(for: key), ChatInteraction.globalRichTextDrafts.set(page, for: key, origin: existing.origin) else {
            return
        }
        invalidateDeferredSendActions()
        storePersistentRichTextDraft(page, threadId: threadId)
    }
    public func persistRichTextDraft(_ page: InstantPage?) {
        guard unshownPersistentRichTextDraftKey != richTextDraftKey else {
            return
        }
        storePersistentRichTextDraft(page, threadId: chatLocation.threadId)
    }
    public func reloadRichTextDraft() {
        richTextDraftPromise.set(richTextDraft)
    }
    public func loadPersistentRichTextDraft() {
        guard richTextDraft == nil, let id = persistentRichTextDraftId else {
            return
        }
        let key = richTextDraftKey
        _ = (context.engine.data.get(TelegramEngine.EngineData.Item.ItemCache.Item(collectionId: ApplicationSpecificItemCacheCollectionId.richTextComposerDraft, id: id))
        |> deliverOnMainQueue).start(next: { [weak self] entry in
            guard let self, self.richTextDraftKey == key, let page = entry?.get(ChatRichTextDraftEntry.self)?.page else {
                return
            }
            guard self.context.appConfiguration.isRichTextEditorEnabled, self.presentation.effectiveInput.inputText.isEmpty else {
                self.unshownPersistentRichTextDraftKey = key
                return
            }
            guard ChatInteraction.globalRichTextDrafts.value(for: key) == nil else {
                return
            }
            self.unshownPersistentRichTextDraftKey = nil
            if ChatInteraction.globalRichTextDrafts.set(page, for: key) {
                self.invalidateDeferredSendActions()
            }
            self.richTextDraftPromise.set(page)
        })
    }
    private func storePersistentRichTextDraft(_ page: InstantPage?, threadId: Int64?) {
        guard let id = persistentRichTextDraftId(threadId: threadId) else {
            return
        }
        if let page {
            _ = context.engine.itemCache.put(collectionId: ApplicationSpecificItemCacheCollectionId.richTextComposerDraft, id: id, item: ChatRichTextDraftEntry(page: page)).start()
        } else {
            _ = context.engine.itemCache.remove(collectionId: ApplicationSpecificItemCacheCollectionId.richTextComposerDraft, id: id).start()
        }
    }

    func excludeRichTextDraftAnalytics() {
        guard let draft = ChatInteraction.globalRichTextDrafts.entry(for: richTextDraftKey) else { return }
        draft.origin?.scope?.exclude()
        if ChatInteraction.globalRichTextDrafts.set(draft.value, for: richTextDraftKey, origin: Analytics.shared.unresolvedContext()) {
            invalidateDeferredSendActions()
        }
        revokePrivateComposerAnalytics()
    }
    
    public var hasSetDestructiveTimer: Bool {
        return presentation.hasSetDestructiveTimer
    }
    
    public var peerIsAccountPeer: Bool {
        return self.presentation.currentSendAsPeerId == nil || self.presentation.currentSendAsPeerId == self.context.peerId
    }
    
    public static let maxInput:Int32 = 50000
    public static let textLimit: Int32 = 4096
    public var maxInputCharacters:Int32 {
        if presentation.state == .normal {
            return ChatInteraction.maxInput
        } else if let editState = presentation.interfaceState.editState {
            if editState.message.media.count == 0 {
                return ChatInteraction.textLimit
            } else {
                for media in editState.message.media {
                    if !(media is TelegramMediaWebpage) {
                        return Int32(context.isPremium ? context.premiumLimits.caption_length_limit_premium : context.premiumLimits.caption_length_limit_default)
                    }
                }
                return ChatInteraction.textLimit
            }
        }
        
        return ChatInteraction.maxInput
    }
    
    
    
    public func disableProxy() {
        disableProxyDisposable.set(updateProxySettingsInteractively(accountManager: context.sharedContext.accountManager, { current -> ProxySettings in
            return current.withUpdatedEnabled(false)
        }).start())
        
    }
    
    public func applyProxy(_ server:ProxyServerSettings) -> Void {
        ChatNavigationHooks.shared.applyExternalProxy(server, context.sharedContext.accountManager)
    }
    
    
    public func call(isVideo: Bool = false) {
        
        
        guard !context.isFrozen else {
            ChatInterfaceHooks.shared.freezeAlert(context)
            return
        }
        
        if let peer = presentation.peer {
            let peerId:PeerId
            if let peer = peer as? TelegramSecretChat {
                peerId = peer.regularPeerId
            } else {
                peerId = peer.id
            }
            let context = self.context
            requestSessionId.set(ChatNavigationHooks.shared.startPhoneCall(context, peerId, isVideo))
        }
    }
    
    public func startBot(_ payload:String? = nil) {
        guard !isStartingBot else {
            return
        }
        isStartingBot = true

        let start = context.engine.messages.requestStartBot(botPeerId: self.peerId, payload: payload)
        if presentation.isBlocked == true {
            let request = (context.blockedPeersContext.remove(peerId: self.peerId)
            |> map { _ -> Void in () })
            |> then(start |> castError(BlockedPeersContextRemoveError.self))
            |> deliverOnMainQueue
            startBotDisposable.set(request.start(error: { [weak self] _ in
                self?.isStartingBot = false
            }, completed: { [weak self] in
                self?.isStartingBot = false
                self?.update({$0.updatedInitialAction(nil)})
            }))
        } else {
            startBotDisposable.set((start |> deliverOnMainQueue).start(completed: { [weak self] in
                self?.isStartingBot = false
                self?.update({$0.updatedInitialAction(nil)})
            }))
        }
    }
    
    public func clearInput() {
        self.update({$0.updatedInterfaceState({$0.withUpdatedInputState(ChatTextInputState())})})
    }
    public func clearContextQuery() {
        if case let .contextRequest(addressName, _) = self.presentation.inputContext {
            let str = "@" + addressName + " "
            let state = ChatTextInputState(inputText: str, selectionRange: str.length ..< str.length, attributes: [])
            self.update({$0.updatedInterfaceState({$0.withUpdatedInputState(state)})})
        }
    }
    
    public func forwardSelectedMessages() {
        guard let ids = presentation.selectionState?.selectedIds, !ids.isEmpty else { return }
        var origin = captureAnalyticsContext()
        for id in ids { origin = origin.restricting(peerId: id.peerId) }
        forwardSelection.load(ids: ids, analyticsContext: origin, trackForwarding: presentation.reportMode == nil, request: {
            context.account.postbox.messagesAtIds(Array(ids))
        }, completion: { [weak self] messages, journey in
            guard let self, self.presentation.selectionState?.selectedIds == ids else { journey?.discard(); return }
            self.forwardMessagesObserved(messages, analyticsContext: origin, entry: .messageSelection, journey: journey)
        })
    }
    
    public func deleteSelectedMessages(morphSource: (() -> NSView?)? = nil) {
        if let ids = presentation.selectionState?.selectedIds {
            deleteMessages(Array(ids), morphSource)
        }
    }
    
    public func updateInput(with text:String) {
        if self.presentation.state == .normal {
            let state = ChatTextInputState(inputText: text, selectionRange: text.length ..< text.length, attributes: [])
            self.update({$0.updatedInterfaceState({$0.withUpdatedInputState(state)})})
        }
    }
    public func updateInput(with attributedText: NSAttributedString) {
        if self.presentation.state == .normal {
            let state = ChatTextInputState(attributedText: attributedText, selectionRange: attributedText.length ..< attributedText.length)
            self.update({$0.updatedInterfaceState({$0.withUpdatedInputState(state)})})
        }
    }
    @discardableResult public func appendTextObserved(_ text: NSAttributedString, selectedRange: Range<Int>? = nil, analyticsContext: AnalyticsContext) -> Range<Int> {
        let origin = captureAnalyticsContext(inherited: analyticsContext)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        let input = origin.isExcluded || origin.scope?.isValid != true ? chatInputTextExcludingAnalytics(text) : text
        return appendText(input, selectedRange: selectedRange)
    }

    @discardableResult public func appendText(_ text: NSAttributedString, selectedRange:Range<Int>? = nil) -> Range<Int> {
        
        let text = text.mutableCopy() as! NSMutableAttributedString
        
        var selectedRange = selectedRange ?? presentation.effectiveInput.selectionRange
        let inputText = presentation.effectiveInput.attributedString().mutableCopy() as! NSMutableAttributedString
        
        if self.presentation.state != .normal && presentation.state != .editing {
            return selectedRange.lowerBound ..< selectedRange.lowerBound
        }
        
        if selectedRange.lowerBound - 1 >= 0 && chatTextAttributes(from: text).allSatisfy({ attribute in
            switch attribute {
            case .animated, .uid, .url, .date:
                return true
            default:
                return false
            }
        }) {
            let attributes = inputText.attributes(at: selectedRange.lowerBound - 1, effectiveRange: nil)
                .filter { (key, value) in
                    switch key {
                    case TextInputAttributes.customEmoji, TextInputAttributes.embedded:
                        return false
                    case TextInputAttributes.textMention, TextInputAttributes.textUrl, TextInputAttributes.formattedDate:
                        var semanticRange = NSRange()
                        _ = inputText.attribute(key, at: selectedRange.lowerBound - 1, longestEffectiveRange: &semanticRange, in: inputText.range)
                        return selectedRange.lowerBound > semanticRange.location && selectedRange.lowerBound < NSMaxRange(semanticRange) && selectedRange.upperBound <= NSMaxRange(semanticRange) && (text.length == 0 || text.attribute(key, at: 0, effectiveRange: nil) == nil)
                    default:
                        return true
                    }
                }
            text.addAttributes(attributes, range: text.range)
        }
        
//        if selectedRange.lowerBound == 0 {
//            let attributes = inputText.attributes(at: selectedRange.lowerBound, effectiveRange: nil).filter {
//                $0.key == TextInputAttributes.quote
//            }
//            text.addAttributes(attributes, range: text.range)
//        }
        
        if selectedRange.upperBound - selectedRange.lowerBound > 0 {
            inputText.replaceCharacters(in: NSMakeRange(selectedRange.lowerBound, selectedRange.upperBound - selectedRange.lowerBound), with: text)
            selectedRange = selectedRange.lowerBound ..< selectedRange.lowerBound
        } else {
            inputText.insert(text, at: selectedRange.lowerBound)
        }
        
        let nRange:Range<Int> = selectedRange.lowerBound + text.length ..< selectedRange.lowerBound + text.length
        let state = ChatTextInputState(inputText: inputText.string, selectionRange: nRange, attributes: chatTextAttributes(from: inputText))
        self.update({$0.withUpdatedEffectiveInputState(state)})
        
        return selectedRange.lowerBound ..< selectedRange.lowerBound + text.length
    }
    
    
    public func appendText(_ text:String, selectedRange:Range<Int>? = nil) -> Range<Int> {
        return self.appendText(NSAttributedString(string: text, font: .normal(theme.fontSize)), selectedRange: selectedRange)
    }
    
    public func cancelEditing(_ force: Bool = false) {
        cancelEditing(force, userInitiated: false)
    }

    func cancelEditing(_ force: Bool = false, userInitiated: Bool) {
        let analyticsContext = captureAnalyticsContext()
        let analyticsPresentation = analyticsContext.beginPresentation()
        defer { analyticsPresentation.end() }
        let sessionId = mediaEditSessionId
        if let editState = self.presentation.interfaceState.editState {
            let oldState = ChatEditState(message: editState.message)
            if force {
                self.update({$0.withoutEditMessage().updatedUrlPreview(nil)})
            } else {
                switch editState.loadingState {
                case .loading, .progress:
                    if userInitiated { mediaEditJourney?.cancelSubmission() }
                    mediaEditSubmissionId = nil
                    editDisposable.set(nil)
                    self.update({$0.updatedInterfaceState({$0.updatedEditState({$0?.withUpdatedLoadingState(.none)})})})
                    return
                default:
                    if oldState.inputState.inputText != editState.inputState.inputText, !editState.inputState.inputText.isEmpty {
                        verifyAlert_button(for: context.window, information: strings().chatEditCancelText, ok: strings().alertDiscard, cancel: strings().alertNO, successHandler: { [weak self] _ in
                            let presentation = analyticsContext.beginPresentation()
                            defer { presentation.end() }
                            guard let self, self.mediaEditSessionId == sessionId else { return }
                            if userInitiated { self.mediaEditJourney?.cancel() }
                            self.update({$0.withoutEditMessage().updatedUrlPreview(nil)})
                        })
                    } else {
                        if userInitiated { mediaEditJourney?.cancel() }
                        self.update({$0.withoutEditMessage().updatedUrlPreview(nil)})
                    }
                }
            }
        }
        
    }
    
    public func invokeInitialAction(includeAuto:Bool = false, animated: Bool = true, action: ChatInitialAction? = nil) {
        if let action = action ?? presentation.initialAction {
            switch action {
            case let .start(parameter: parameter, behavior: behavior):
                var invoke:Bool = !includeAuto
                if includeAuto {
                    switch behavior {
                    case .automatic:
                        invoke = true
                    default:
                        if let count = presentation.historyCount, count > 1 {
                            invoke = true
                        }
                    }
                }
                if invoke {
                    startBot(parameter)
                    update({
                        $0.withoutInitialAction()
                    })
                }
            case let .inputText(text: text, behavior: behavior):
                var invoke:Bool = !includeAuto
                if includeAuto {
                    switch behavior {
                    case .automatic:
                        invoke = true
                    default:
                        break
                    }
                }
                if invoke {
                    self.update({$0.updatedInterfaceState({$0.withUpdatedInputState(text)})})
                    update({
                        $0.withoutInitialAction()
                    })
                }
            case let .files(list: list, behavior: behavior):
                var invoke:Bool = !includeAuto
                if includeAuto {
                    switch behavior {
                    case .automatic:
                        invoke = true
                    default:
                        break
                    }
                }
                if invoke {
                    showPreviewSender( list.map { URL(fileURLWithPath: $0) }, true, nil )
                    update({
                        $0.withoutInitialAction()
                    })
                }
            case let .forward(messageIds, inputState, _):
                update(animated: animated, {
                    $0.updatedInterfaceState({
                        $0.withUpdatedForwardMessageIds(messageIds).withUpdatedInputState(inputState ?? $0.inputState)
                    }).withoutInitialAction()
                })
            case let .reply(subject, _):
                update(animated: animated, {
                    $0.updatedInterfaceState({
                        $0.withUpdatedReplyMessageId(subject)
                    }).withoutInitialAction()
                })
            case .ad:
                break
            case .source:
                break
            case .closeAfter(_):
                break
            case let .openMedia(timemark):
                self.openFocusedMedia(timemark)
                update({
                    $0.withoutInitialAction()
                })
            case let .selectToReport(reason):
                update(animated: animated, {
                    $0.withSelectionState().withoutInitialAction().withUpdatedRepotMode(reason)
                })
            case let .attachBot(botname, payload, _):
                let analyticsContext = captureAnalyticsContext()
                let context = self.context
                let peerId = self.peerId
                let analyticsPresentation = analyticsContext.beginPresentation()
                defer { analyticsPresentation.end() }
                let replyId = presentation.interfaceState.replyMessageId?.messageId
                let threadId = presentation.chatLocation.threadId
                update({ $0.withoutInitialAction() })
                chatOpenAttachBot(context: context, peerId: peerId, threadId: threadId, replyId: replyId, botname: botname, payload: payload, analyticsContext: analyticsContext)
            case let .openWebview(botPeer, botApp, result):
                let analyticsContext = captureAnalyticsContext().restricting(peerId: botPeer.id)
                let context = self.context
                let peerId = self.peerId
                let analyticsPresentation = analyticsContext.beginPresentation()
                defer { analyticsPresentation.end() }
                update(animated: animated, {
                    $0.withoutInitialAction()
                })
                ChatNavigationHooks.shared.openBrowserTabObserved(context, .straight(bot: .init(botPeer.peer), peerId: peerId, title: botApp.title, result: result), analyticsContext: analyticsContext)
            case .makeWebview:
                update(animated: animated, {
                    $0.withoutInitialAction()
                })
            case .openTopic:
                update(animated: animated, {
                    $0.withoutInitialAction()
                })
            case .direct:
                update(animated: animated, {
                    $0.withoutInitialAction()
                })
            case .album:
                update(animated: animated, {
                    $0.withoutInitialAction()
                })
            case let .joinVoiceChat(joinHash):
                update(animated: animated, {
                    $0.updatedGroupCall { $0?.withUpdatedJoinHash(joinHash) }.withoutInitialAction()
                })
                
                let peerId = self.peerId
                let context = self.context
                let isChannel = self.peer?.isChannel == true
                
                let joinCall:(GroupCallPanelData)->Void = { [weak self] data in
                    if data.groupCall?.call.peerId != peerId, let peer = self?.peer {
                        ChatNavigationHooks.shared.showJoinVoiceChatAlert(context, data, peer, { [weak self] in
                            if let call = data.info {
                                self?.joinGroupCall(CachedChannelData.ActiveCall(id: call.id, accessHash: call.accessHash, title: call.title, scheduleTimestamp: call.scheduleTimestamp, subscribedToScheduled: call.subscribedToScheduled, isStream: call.isStream), joinHash)
                            }
                        }, context.window)
                    } else {
                        if let call = data.info {
                            self?.joinGroupCall(CachedChannelData.ActiveCall(id: call.id, accessHash: call.accessHash, title: call.title, scheduleTimestamp: call.scheduleTimestamp, subscribedToScheduled: call.subscribedToScheduled, isStream: call.isStream), joinHash)
                        }
                    }
                }
                let call: Signal<GroupCallPanelData?, GetCurrentGroupCallError> = context.engine.calls.updatedCurrentPeerGroupCall(peerId: peerId) |> mapToSignalPromotingError { call -> Signal<GroupCallSummary?, GetCurrentGroupCallError> in
                    if let call = call {
                        return context.engine.calls.getCurrentGroupCall(reference: .id(id: call.id, accessHash: call.accessHash), peerId: peerId)
                    } else {
                        return .single(nil)
                    }
                } |> mapToSignal { data in
                    if let data = data {
                        return ChatInterfaceHooks.shared.makeGroupCallPanelData(context, peerId, isChannel, data)
                    } else {
                        return .single(nil)
                    }
                }
                _ = showModalProgress(signal: call, for: context.window).start(next: {  data in
                    if let data = data {
                        joinCall(data)
                    } else {
                        alert(for: context.window, info: strings().chatVoiceChatJoinLinkUnavailable)
                    }
                })
            case .pollOption(_):
                break
            }
            
        }
    }
    
    
    public func openWebviewFromMenu(buttonText: String, url: String) {
        if let bot = peer {
            ChatNavigationHooks.shared.openBrowserTab(context, .webapp(bot: .init(bot), peerId: peerId, buttonText: buttonText, url: url, payload: nil, threadId: nil, replyTo: nil, fromMenu: true))
        }
    }
    
    public func loadAndOpenInlineWebview(botId: PeerId, url: String) {
        let context = self.context
        
        let bot = context.account.postbox.loadedPeerWithId(botId) |> deliverOnMainQueue
        _ = bot.start(next: { [weak self] peer in
            self?.openWebview(bot: peer, title: nil, buttonText: "", url: url, simple: true, inline: true)
        })
        
    }
    
    public func openEditReplies() {
        ChatNavigationHooks.shared.pushBusinessQuickReplies(context)
    }
    
    public func openWebview(bot:Peer, title: String?, buttonText: String, url: String, simple: Bool, inline: Bool) {
        let replyTo = self.presentation.interfaceState.replyMessageId?.messageId
        let threadId = self.presentation.chatLocation.threadId
        let context = self.context
        let peerId = self.peerId
        
        let tab: ChatBrowserTab
        if simple {
            tab = .simple(bot: .init(bot), url: url, buttonText: buttonText, source: inline ? .inline(startParam: nil) : .generic)
        } else {
            tab = .webapp(bot: .init(bot), peerId: peerId, buttonText: buttonText, url: url, payload: nil, threadId: threadId, replyTo: replyTo, fromMenu: false)
        }
        ChatNavigationHooks.shared.openBrowserTab(context, tab)
    }
    
    func allowMessageButtonAction(_ message: Message) -> Bool {
        if message.flags.contains(.Incoming), presentation.peer?.isUser == true, presentation.peerStatus?.peerStatusSettings?.flags.isDisjoint(with: .suspiciousPeer) == false {
            return false
        }
        return true
    }

    public func processBotKeyboard(with keyboardMessage:Message) ->ReplyMarkupInteractions {
        if let attribute = keyboardMessage.replyMarkup, !isLogInteraction {
            
            let context = self.context
            _ = self.peerId
            let threadId = self.chatLocation.threadId
            let callbackTargetMessageId = keyboardMessage.callbackTargetMessageId
            
            return ReplyMarkupInteractions(context: context, proccess: { [weak self] (button, progress) in
                if let strongSelf = self {
                    if attribute.flags.contains(.inline), !strongSelf.allowMessageButtonAction(keyboardMessage) {
                        return
                    }
                    switch button.action {
                    case let .url(url):
                        
                        ChatInterfaceHooks.shared.executeConfirmedUrl(strongSelf, url)
                       
                    case .text:
                        let replyId = strongSelf.presentation.interfaceState.messageActionsState.processedSetupReplyMessageId
                        _ = (enqueueMessages(account: strongSelf.context.account, peerId: strongSelf.peerId, messages: [EnqueueMessage.message(text: button.title, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: threadId, replyToMessageId: replyId.flatMap { .init(messageId: $0, quote: nil, innerSubject: nil) }, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])]) |> deliverOnMainQueue).start(next: { [weak strongSelf] _ in
                            strongSelf?.scrollToLatest(true)
                        })
                    case .requestPhone:
                        FastSettings.requstPermission(with: .contact, for: keyboardMessage.id.peerId, success: { [weak strongSelf] in
                            strongSelf?.shareSelfContact(nil)
                            if attribute.flags.contains(.once) {
                                strongSelf?.update({$0.updatedInterfaceState({$0.withUpdatedMessageActionsState({$0.withUpdatedClosedButtonKeyboardMessageId(keyboardMessage.id)})})})
                            }
                        })
                        
                        return
                    case .openWebApp:
                        strongSelf.requestMessageActionCallback(callbackTargetMessageId, true, nil)
                    case let .callback(requiresPassword, data):
                        strongSelf.requestMessageActionCallback(callbackTargetMessageId, false, (requiresPassword: requiresPassword, data: data))
                    case let .switchInline(samePeer: same, query: query, peerTypes):
                        let text = "@\(keyboardMessage.inlinePeer?.username ?? keyboardMessage.author?.username ?? "") \(query)"
                        if same {
                            strongSelf.updateInput(with: text)
                        } else {
                            
                            ChatInterfaceHooks.shared.shareSwitchInlineQuery(context, peerTypes, text)
                            
                        }
                    case .payment:
                        if let invoice = keyboardMessage.anyMedia as? TelegramMediaInvoice {
                            let origin = strongSelf.captureAnalyticsContext(sourcePeerId: keyboardMessage.id.peerId)
                            openChatMessagePayment(context: context, messageId: keyboardMessage.id, invoice: invoice, analyticsContext: origin)
                        }
                    case let .urlAuth(url, buttonId):
                        let context = strongSelf.context
                        _ = showModalProgress(signal: context.engine.messages.requestMessageActionUrlAuth(subject: .message(id: callbackTargetMessageId, buttonId: buttonId)), for: context.window).start(next: { result in
                            switch result {
                            case let .accepted(url):
                                if let url {
                                    ChatInterfaceHooks.shared.executeUrl(strongSelf, url)
                                }
                            case .default:
                                ChatInterfaceHooks.shared.executeConfirmedUrl(strongSelf, url)
                            case let .request(domain, bot, clientData, flags, matchCodes, userIdHint):
                                ChatInterfaceHooks.shared.showLoginWidgetConfirmation(
                                    context,
                                    domain,
                                    EnginePeer(bot),
                                    clientData,
                                    flags,
                                    .message(id: callbackTargetMessageId, buttonId: buttonId),
                                    matchCodes,
                                    userIdHint
                                )
                            }
                        })
                    case let .setupPoll(isQuiz):
                        showModal(with: ChatInterfaceHooks.shared.makeNewPollController(strongSelf, isQuiz), for: strongSelf.context.window)
                    case let .openUserProfile(peerId: peerId):
                        strongSelf.openInfo(peerId, false, nil, nil)
                    case let .openWebView(hashUrl, simple):
                        let bot = keyboardMessage.inlinePeer ?? keyboardMessage.author
                        if let bot = bot {
                            strongSelf.openWebview(bot: bot, title: bot.displayTitle, buttonText: button.title, url: hashUrl, simple: simple, inline: false)
                        }
                    case let .requestPeer(peerType, buttonId, maxQuantity):
                        ChatNavigationHooks.shared.selectSpecificPeer(context, peerType, keyboardMessage.id, buttonId, maxQuantity)
                    case let .copyText(payload):
                        copyToClipboard(payload)
                        showModalText(for: context.window, text: strings().shareLinkCopied)
                    default:
                        break
                    }
                    if attribute.flags.contains(.once) {
                        strongSelf.update({$0.updatedInterfaceState({$0.withUpdatedMessageActionsState({$0.withUpdatedClosedButtonKeyboardMessageId(keyboardMessage.id)})})})
                    }
                }
            })
        } else if let attribute = keyboardMessage.suggestPostAttribute, !isLogInteraction {
            let schedulingAnalyticsContext = captureAnalyticsContext().restricting(peerId: keyboardMessage.id.peerId)
            
            let context = self.context
            let peer = presentation.peer
            let amount = attribute.amount
            
            return ReplyMarkupInteractions(context: context, proccess: { [weak self] button, progress in
                
                switch button.action {
                case let .url(url):
                    switch url {
                    case SuggestedPostMessageAttribute.commandApprove:
                        
                        if let peer, !peer.groupAccess.canPostMessages {
                            _ = context.engine.messages.monoforumPerformSuggestedPostAction(
                                id: keyboardMessage.id,
                                action: .approve(timestamp: nil)
                            ).start()
                        } else {
                            let comission = context.appConfiguration.getGeneralValue("ton_suggested_post_commission_permille", orElse: 850)
                            
                            let formatted: String
                            if let amount {
                                let totalAmount = "\(Double(formatCurrencyAmount(amount.amount.value, currency: TON))! * Double(comission.decemial / 100.0))".prettyCurrencyNumberUsd

                                switch amount.currency {
                                case .ton:
                                    formatted = "\(totalAmount) \(TON)"
                                case .stars:
                                    formatted = strings().starListItemCountOther(Int(amount.amount.totalValue))
                                }
                            } else {
                                formatted = strings().chatServiceSuggestPostHeaderPriceFree
                            }
                            

                            if attribute.timestamp == nil {
                                let infoText = TextViewLayout(
                                    .initialize(
                                        string: amount != nil ? strings().chatSuggestPostPublishInfo(formatted, "\(comission.decemial.string)%") : strings().chatSuggestPostPublishInfoFree,
                                        color: theme.colors.text,
                                        font: .normal(.text)
                                    ),
                                    alignment: .center
                                )
                                infoText.measure(width: 260)

                                showModal(
                                    with: chatDateSelector(
                                        context: context,
                                        mode: .dateAction(
                                            title: strings().chatSuggestPostPublishAcceptTitle,
                                            done: { date in
                                                strings().chatSuggestPostPublishDateConfirm(stringForDate(timestamp: Int32(date.timeIntervalSince1970)))
                                            },
                                            action: .init(
                                                string: strings().chatSuggestPostPublishActionNow,
                                                callback: {
                                                    _ = context.engine.messages.monoforumPerformSuggestedPostAction(
                                                        id: keyboardMessage.id,
                                                        action: .approve(timestamp: nil)
                                                    ).start()
                                                }
                                            )
                                        ),
                                        analyticsContext: schedulingAnalyticsContext,
                                        selectedAt: { date, _ in
                                            _ = context.engine.messages.monoforumPerformSuggestedPostAction(
                                                id: keyboardMessage.id,
                                                action: .approve(timestamp: Int32(date.timeIntervalSince1970))
                                            ).start()
                                        },
                                        infoText: infoText
                                    ),
                                    for: context.window
                                )
                            } else {
                                let author = keyboardMessage.author?.displayTitle ?? ""
                                let info: String
                                if amount != nil {
                                    info = strings().chatSuggestPostPublishConfirmInfo(author, formatted, "\(comission.decemial.string)%")
                                } else {
                                    info = strings().chatSuggestPostPublishConfirmInfoFree(author)
                                }
                                verifyAlert(
                                    for: context.window,
                                    header: strings().chatSuggestPostPublishConfirmHeader,
                                    information: info,
                                    ok: strings().chatSuggestPostPublishConfirmButton,
                                    successHandler: { _ in
                                        _ = context.engine.messages.monoforumPerformSuggestedPostAction(
                                            id: keyboardMessage.id,
                                            action: .approve(timestamp: nil)
                                        ).start()
                                    }
                                )
                            }
                        }
                        
                    case SuggestedPostMessageAttribute.commandDecline:
                        showModal(with: DeclineSuggestPostModalController(context: context, callback: { comment in
                            _ = context.engine.messages.monoforumPerformSuggestedPostAction(id: keyboardMessage.id, action: .reject(comment: comment.isEmpty ? nil : comment)).start()
                        }), for: context.window)
                        
                    case SuggestedPostMessageAttribute.commandChanges:
                        self?.beginEditingMessage(keyboardMessage)
                    default:
                        break
                    }
                default:
                    break
                }
            })
            
        }

        return ReplyMarkupInteractions(context: context, proccess: { [weak self] _,_ in
            self?.executeReplymarkup(keyboardMessage.id)
        })
    }
    
    
    
    public func saveState(_ force:Bool = true, scrollState: ChatInterfaceHistoryScrollState? = nil, sync: Bool = false) {
        if sync {
            storePendingRichTextDraft?()
            storePendingRichTextEditorDraft?()
        }
        
        if mode.customChatContents != nil || mode.customChatLink != nil {
            return
        }
        
        let peerId = self.peerId
        let context = self.context
        let timestamp = Int32(Date().timeIntervalSince1970)
        let interfaceState = presentation.interfaceState.withUpdatedTimestamp(timestamp).withUpdatedHistoryScrollState(scrollState)
        
        let threadId = chatLocation.threadId
        var s:Signal<Never, NoError> = deferred {
            let updatedOpaqueData = try? EngineEncoder.encode(interfaceState)
            return context.engine.peers.setOpaqueChatInterfaceState(peerId: peerId, threadId: threadId, state: .init(opaqueData: updatedOpaqueData, historyScrollMessageIndex: interfaceState.historyScrollMessageIndex, mediaDraftState: nil, synchronizeableInputState: interfaceState.synchronizeableInputState))
        }

        if !force && !interfaceState.inputState.inputText.isEmpty {
            s = s |> delay(10, queue: Queue.mainQueue())
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        
        let disposable = s.start(completed: {
            ChatInterfaceHooks.shared.setChatInterfaceTempState(context, ChatInterfaceTempState(editState: interfaceState.editState), peerId)
            if sync {
                semaphore.signal()
            }
        })
        modifyDisposable.set(disposable)

        if sync {
            semaphore.wait()
        }
    }
    
    

    deinit {
       clean()
    }
    
    public func clean() {
        invalidateDeferredSendActions()
        dateHeaderActions.reset()
        forwardSelection.reset()
        quickForwardAction.reset()

        addContactDisposable.dispose()
        mediaDisposable.dispose()
        recordingMediaDisposable.dispose()
        recordingSubmissionDisposable.dispose()
        startBotDisposable.dispose()
        requestSessionId.dispose()
        disableProxyDisposable.dispose()
        enableProxyDisposable.dispose()
        editDisposable.dispose()
        mediaPromise.set(.complete())
        recordingMediaPromise.set(.complete())
        recordingSubmissionPromise.set(.complete())
        update({ _ in
            return ChatPresentationInterfaceState(chatLocation: self.chatLocation, chatMode: self.mode)
        })
        nilAllHandlers()
    }

    public func nilAllHandlers() {
        forwardSelection.reset()
        quickForwardAction.reset()
        self.withToggledSelectedMessage = { _ in }
        self.setupReplyMessage = { _, _ in }
        self.beginMessageSelection = { _ in }
        self.deleteMessages = { _, _ in }
        self.forwardMessages = { _ in }
        self.forwardMessagesWithContext = nil
        self.forwardMessagesWithSource = nil
        self.forwardMessagesWithJourney = nil
        self.reportMessages = { _, _ in }
        self.sendMessage = { _, _, _ in }
        self.sendAIEditorResult = nil
        self.sendMessageWithAnalytics = nil
        self.sendPlainText = { _ in }
        self.sendPlainTextWithAnalytics = nil
        self.focusMessageId = { _, _, _ in }
        self.focusPinnedMessageId = { _ in }
        self.sendMedia = { _ in }
        self.sendMediaWithJourney = nil
        self.sendRecordingMediaWithAnalytics = nil
        self.sendCreatedStickerWithAnalytics = nil
        self.sendAppFileWithContext = nil
        self.sendAppFile = { _, _, _, _, _, _, _ in }
        self.sendMedias = { _, _, _, _, _, _, _, _, _ in }
        self.sendMediasWithAnalytics = nil
        self.focusInputField = { }
        self.openInfo = { _, _, _, _ in }
        self.openInfoWithAnalytics = nil
        self.beginEditingMessage = { _ in }
        self.requestMessageActionCallback = { _, _, _ in }
        self.inlineAudioPlayer = { _ in }
        self.movePeerToInput = { _ in }
        self.sendInlineResult = { _, _ in }
        self.scrollToLatest = { _ in }
        self.shareSelfContact = { _ in }
        self.shareLocation = { }
        self.modalSearch = { _ in }
        self.sendCommand = { _ in }
        self.setNavigationAction = { _ in }
        self.switchInlinePeer = { _, _ in }
        self.presentPreviewSender = { _, _, _, _ in }
        self.presentPreviewSenderWithJourney = nil
        self.setChatMessageAutoremoveTimeout = { _ in }
        self.toggleNotifications = { _ in }
        self.removeAndCloseChat = { }
        self.joinChannel = { }
        self.returnGroup = { }
        self.shareContact = { _ in }
        self.unblock = { }
        self.updatePinned = { _, _, _, _ in }
        self.reportSpamAndClose = { }
        self.dismissPeerStatusOptions = { }
        self.dismissRequestChat = { }
        self.toggleSidebar = { }
        self.mentionPressed = { }
        self.jumpToDate = { _ in }
        self.showNextPost = { }
        self.startRecording = { _, _ in }
        self.startRecordingWithAnalytics = nil
        self.openProxySettings = { }
        self.sendLocation = { _, _ in }
        self.clearMentions = { }
        self.reactionPressed = { }
        self.showToaster = { _ in }
        self.previewTopic = { _ in }
        self.showRestrictionToast = { _ in }
        self.removeToaster = { }
        self.clearReactions = { }
        self.attachFile = { _ in }
        self.attachPhotoOrVideo = { _ in }
        self.attachPicture = { }
        self.attachLocation = { _ in }
        self.attachAudio = { _ in }
        self.updateEditingMessageMedia = { _, _ in }
        self.editEditingMessagePhoto = { _ in }
        self.removeChatInteractively = { }
        self.updateSearchRequest = { _ in }
        self.searchPeerMessages = { _ in }
        self.vote = { _, _, _ in }
        self.closePoll = { _ in }
        self.addPollOption = { _, _ in }
        self.deletePollOption = { _, _ in }
        self.openDiscussion = { }
        self.addContact = { }
        self.blockContact = { }
        self.openScheduledMessages = { }
        self.openBank = { _ in }
        self.afterSentTransition = { }
        self.getGradientOffsetRect = { return .zero }
        self.voiceTranscription?.dismiss(animated: false)
        self.voiceTranscription = nil
        self.markAdAction = { _, _ in }
        self.contextHolder = { Atomic(value: nil) }
        self.freezeAccountAlert = { }
        self.openFocusedMedia = { _ in return }
        self.push = { _ in }
        self.back = { }
        self.openPinnedMessages = { _ in }
        self.unpinAllMessages = { }
        self.setLocation = { _ in }
        self.scrollToTheFirst = { }
        self.openReplyThread = { _, _, _, _ in }
        self.transcribeAudio = { _ in }
        self.joinGroupCall = { _, _ in }
        self.runEmojiScreenEffect = { _, _, _, _ in }
        self.runPremiumScreenEffect = { _, _, _ in }
        self.runReactionEffect = { _, _, _ in }
        self.toggleSendAs = { _ in }
        self.showDeleterSetup = { _ in }
        self.showEmojiUseTooltip = { }
        self.restartTopic = { }
        self.openSetPeerAvatar = { }
        self.revealMedia = { _ in }
        self.toggleTranslate = { }
        self.hideTranslation = { }
        self.openStories = { _, _ in }
        self.openChatPeerStories = { _, _, _ in }
        self.doNotTranslate = { _ in }
        self.translateTo = { _ in }
        self.setTranslateTone = { _ in }
        self.enableTranslatePaywall = { }
        self.summarize = { _ in }
        self.clearSummarize = { _ in }
        self.openPendingRequests = { }
        self.dismissPendingRequests = { _ in }
        self.setupChatThemes = { }
        self.closeChatThemes = { }
        self.appendAttributedText = { _ in }
        self.setLocationTag = { _ in }
        self.revealFactCheck = { _ in }
        self.togglePollSolution = { _ in }
        self.hashtag = { _ in }
        self.sendMessageMenu = { _ in .single(nil) }
        self.removeAd = { _ in }
        self.canAnimateUpdates = { true }
        self.boostToUnrestrict = { _ in }
        self.executeReplymarkup = { _ in }
        self.toggleUnderMouseMessage = { }
        self.openStory = { _, _ in }
        self.sendMessageShortcut = { _ in }
        self.replyToAnother = { _, _ in }
        self.enqueueCodeSyntax = { _, _, _, _, _ in }
        self.openPhoneNumberContextMenu = { _ in }
        self.openTonAddressContextMenu = { _ in }
        self.toggleQuote = { _ in }
        self.toggleDetails = { _ in }
        self.markAdAsSeen = { _ in }
        self.openMonoforum = { _ in }
        self.toggleMonoforumState = { }
        self.monoforumMenuItems = { _ in return .single([]) }
        self.sendGift = { _ in }
        self.editPostSuggestion = { _ in }
        self.diceRoll = { }
        self.sendDiceWithStake = { _ in }
        self.updateChatLocationThread = { _ in }
        self.appendTask = { _ in }
        self.updateFrame = { _, _ in }
        self.unarchive = { }
        self.closeAfterPeek = { _ in }
        self.updateReactions = { _, _, _ in }
    }
    
    
    
    public func applyAction(action:NavigationModalAction) {
        if let action = action as? ChatInterfaceForwardAction {
            self.update({$0.updatedInterfaceState({$0.withUpdatedForwardMessageIds(action.ids)})})
            saveState(false)
        } else if let action = action as? ChatInterfaceInlineResultAction {
            updateInput(with: action.payload)
        }
    }
    
    public func getMessages(_ messageIds: [MessageId], _ album: Bool) -> Signal<[Message], NoError> {
        if let hashtags = self.mode.customChatContents {
            return hashtags.messagesAtIds(messageIds, album: album)
        } else {
            return context.account.postbox.transaction { transaction in
                var list:[Message] = []
                for messageId in messageIds {
                    if let messages = transaction.getMessageGroup(messageId), album {
                        list.append(contentsOf: messages)
                    } else if let message = transaction.getMessage(messageId) {
                        list.append(message)
                    }
                }
                return list
            }
        }
    }

    
}

public func sendMessageMenuItems(chatInteraction: ChatInteraction, send: @escaping (Bool, ChatInteraction.Schedule?) -> Void) -> [ContextMenuItem]? {
    return sendMessageMenuItems(chatInteraction: chatInteraction, analyticsContext: chatInteraction.captureAnalyticsContext(), send: send)
}

public func sendMessageMenuItems(chatInteraction: ChatInteraction, analyticsContext: AnalyticsContext, send: @escaping (Bool, ChatInteraction.Schedule?) -> Void) -> [ContextMenuItem]? {
    let schedulingAnalyticsContext = chatInteraction.captureAnalyticsContext(inherited: analyticsContext)
    let getAnalyticsContext = { [weak chatInteraction] in
        guard let chatInteraction else { return Analytics.shared.unresolvedContext() }
        return chatInteraction.captureAnalyticsContext(inherited: schedulingAnalyticsContext)
    }
    let analyticsPresentation = getAnalyticsContext().beginPresentation()
    defer { analyticsPresentation.end() }
    let deferredSendAction = chatInteraction.captureDeferredSendAction()
    let presentation = chatInteraction.presentation
    let context = chatInteraction.context

    guard let peer = presentation.peer else {
        return nil
    }
    if let slowMode = presentation.slowMode, slowMode.hasLocked {
        return nil
    }
    if presentation.state != .normal {
        return nil
    }

    var items:[ContextMenuItem] = []

    if peer.id != context.account.peerId {
        items.append(ContextMenuItem(strings().chatSendWithoutSound, handler: {
            guard deferredSendAction.takeIfCurrent() else { return }
            let presentation = getAnalyticsContext().beginPresentation()
            defer { presentation.end() }
            send(true, nil)
        }, itemImage: MenuAnimation.menu_mute.value))
    }

    switch chatInteraction.mode {
    case .history, .thread:
        if !peer.isSecretChat {
            if peer.id != context.peerId, presentation.canScheduleWhenOnline, presentation.sendPaidMessageStars == nil {
                items.append(ContextMenuItem(strings().chatSendSendWhenOnline, handler: {
                    guard deferredSendAction.takeIfCurrent() else { return }
                    let presentation = getAnalyticsContext().beginPresentation()
                    defer { presentation.end() }
                    send(false, .init(date: scheduleWhenOnlineDate))
                }, itemImage: MenuAnimation.menu_online.value))
            }

            if presentation.sendPaidMessageStars == nil {
                let text = peer.id == context.peerId ? strings().chatSendSetReminder : strings().chatSendScheduledMessage
                items.append(ContextMenuItem(text, handler: {
                    guard deferredSendAction.isAvailable else { return }
                    let presentation = getAnalyticsContext().beginPresentation()
                    defer { presentation.end() }
                    showModal(with: chatDateSelector(context: context, mode: .schedule(peer.id), analyticsContext: schedulingAnalyticsContext, selectedAt: { date, repeatPeriod in
                        guard deferredSendAction.takeIfCurrent() else { return }
                        let presentation = getAnalyticsContext().beginPresentation()
                        defer { presentation.end() }
                        send(false, .init(date: date, repeatPeriod: repeatPeriod))
                    }), for: context.window)
                }, itemImage: MenuAnimation.menu_schedule_message.value))
            }
        }
    default:
        break
    }

    return items
}
