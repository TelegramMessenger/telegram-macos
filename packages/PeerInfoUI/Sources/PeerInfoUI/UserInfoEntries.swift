import Cocoa
import TelegramCore
import CurrencyFormat
import SwiftSignalKit
import Postbox
import TGUIKit
import InputView
import AffiliateUI
import AlertsUI
import AvatarEditorUI
import BusinessUI
import CalendarUI
import CallsUI
import ChannelAdminUI
import ChatHistoryModel
import ChatUI
import CommunityUI
import FilePanels
import GeneralRows
import InAppSettings
import InputDataUI
import LocalAnimations
import Localization
import LocationUI
import PremiumUI
import ReportUI
import SelectPeersUI
import ShareUI
import ShortPeerRow
import StarsUI
import TelegramContext
import TelegramMediaUtils
import TelegramTheme
import TelegramUtils
import WebAppUI
import ChatModeTypes
import InlineStickerLayer

struct UserInfoEditingState: Equatable {
    let editingFirstName: String?
    let editingLastName: String?
    let editingNotes: CachedUserData.Note?

    init(editingFirstName:String? = nil, editingLastName:String? = nil, editingNotes:CachedUserData.Note? = nil) {
        self.editingFirstName = editingFirstName
        self.editingLastName = editingLastName
        self.editingNotes = editingNotes
    }
    
    func withUpdatedEditingFirstNameText(_ editingFirstName: String?) -> UserInfoEditingState {
        return UserInfoEditingState(editingFirstName: editingFirstName, editingLastName: self.editingLastName, editingNotes: self.editingNotes)
    }
    func withUpdatedEditingLastNameText(_ editingLastName: String?) -> UserInfoEditingState {
        return UserInfoEditingState(editingFirstName: self.editingFirstName, editingLastName: editingLastName, editingNotes: self.editingNotes)
    }
    func withUpdatedEditingNotesText(_ editingNotes: CachedUserData.Note?) -> UserInfoEditingState {
        return UserInfoEditingState(editingFirstName: self.editingFirstName, editingLastName: self.editingLastName, editingNotes: editingNotes)
    }
    
}



final class UserInfoState : PeerInfoState {
    let editingState: UserInfoEditingState?
    let savingData: Bool
    let updatingPhotoState:PeerInfoUpdatingPhotoState?
    let suggestingPhotoState:PeerInfoUpdatingPhotoState?
    let businessHoursRevealed: Bool
    let businessHoursDisplayMyTimezone: Bool
    init(editingState: UserInfoEditingState?, savingData: Bool, updatingPhotoState:PeerInfoUpdatingPhotoState?, suggestingPhotoState:PeerInfoUpdatingPhotoState?, businessHoursRevealed: Bool, businessHoursDisplayMyTimezone: Bool) {
        self.editingState = editingState
        self.savingData = savingData
        self.updatingPhotoState = updatingPhotoState
        self.suggestingPhotoState = suggestingPhotoState
        self.businessHoursRevealed = businessHoursRevealed
        self.businessHoursDisplayMyTimezone = businessHoursDisplayMyTimezone
    }
    
    override init() {
        self.editingState = nil
        self.savingData = false
        self.updatingPhotoState = nil
        self.suggestingPhotoState = nil
        self.businessHoursRevealed = false
        self.businessHoursDisplayMyTimezone = true
    }
    
    func isEqual(to: PeerInfoState) -> Bool {
        if let to = to as? UserInfoState {
            return self == to
        }
        return false
    }
    
    static func ==(lhs: UserInfoState, rhs: UserInfoState) -> Bool {
        if lhs.editingState != rhs.editingState {
            return false
        }
        if lhs.savingData != rhs.savingData {
            return false
        }
        if lhs.updatingPhotoState != rhs.updatingPhotoState {
            return false
        }
        if lhs.suggestingPhotoState != rhs.suggestingPhotoState {
            return false
        }
        if lhs.businessHoursRevealed != rhs.businessHoursRevealed {
            return false
        }
        if lhs.businessHoursDisplayMyTimezone != rhs.businessHoursDisplayMyTimezone {
            return false
        }
        return true
    }
    
    func withUpdatedSavingData(_ savingData: Bool) -> UserInfoState {
        return UserInfoState(editingState: self.editingState, savingData: savingData, updatingPhotoState: self.updatingPhotoState, suggestingPhotoState: self.suggestingPhotoState, businessHoursRevealed: self.businessHoursRevealed, businessHoursDisplayMyTimezone: self.businessHoursDisplayMyTimezone)
    }
    
    func withUpdatedEditingState(_ editingState: UserInfoEditingState?) -> UserInfoState {
        return UserInfoState(editingState: editingState, savingData: self.savingData, updatingPhotoState: self.updatingPhotoState, suggestingPhotoState: self.suggestingPhotoState, businessHoursRevealed: self.businessHoursRevealed, businessHoursDisplayMyTimezone: self.businessHoursDisplayMyTimezone)
    }
    
    func withUpdatedUpdatingPhotoState(_ f: (PeerInfoUpdatingPhotoState?) -> PeerInfoUpdatingPhotoState?) -> UserInfoState {
        return UserInfoState(editingState: self.editingState, savingData: self.savingData, updatingPhotoState: f(self.updatingPhotoState), suggestingPhotoState: self.suggestingPhotoState, businessHoursRevealed: self.businessHoursRevealed, businessHoursDisplayMyTimezone: self.businessHoursDisplayMyTimezone)
    }
    func withoutUpdatingPhotoState() -> UserInfoState {
        return UserInfoState(editingState: self.editingState, savingData: self.savingData, updatingPhotoState: nil, suggestingPhotoState: self.suggestingPhotoState, businessHoursRevealed: self.businessHoursRevealed, businessHoursDisplayMyTimezone: self.businessHoursDisplayMyTimezone)
    }
    
    func withUpdatedSuggestingPhotoState(_ f: (PeerInfoUpdatingPhotoState?) -> PeerInfoUpdatingPhotoState?) -> UserInfoState {
        return UserInfoState(editingState: self.editingState, savingData: self.savingData, updatingPhotoState: self.updatingPhotoState, suggestingPhotoState: f(self.updatingPhotoState), businessHoursRevealed: self.businessHoursRevealed, businessHoursDisplayMyTimezone: self.businessHoursDisplayMyTimezone)
    }
    func withoutSuggestingPhotoState() -> UserInfoState {
        return UserInfoState(editingState: self.editingState, savingData: self.savingData, updatingPhotoState: self.updatingPhotoState, suggestingPhotoState: nil, businessHoursRevealed: self.businessHoursRevealed, businessHoursDisplayMyTimezone: self.businessHoursDisplayMyTimezone)
    }
    func withBusinessHoursRevealed(_ revealed: Bool) -> UserInfoState {
        return UserInfoState(editingState: self.editingState, savingData: self.savingData, updatingPhotoState: self.updatingPhotoState, suggestingPhotoState: self.suggestingPhotoState, businessHoursRevealed: revealed, businessHoursDisplayMyTimezone: self.businessHoursDisplayMyTimezone)
    }
    func withBusinessHoursTimeZoneUpdated(_ businessHoursDisplayMyTimezone: Bool) -> UserInfoState {
        return UserInfoState(editingState: self.editingState, savingData: self.savingData, updatingPhotoState: self.updatingPhotoState, suggestingPhotoState: self.suggestingPhotoState, businessHoursRevealed: self.businessHoursRevealed, businessHoursDisplayMyTimezone: businessHoursDisplayMyTimezone)
    }
}

enum UserInfoArgumentsSetPhotoType: Int, Equatable {
    case suggest = 0
    case set = 1
}

private enum UpdateError {
    case generic
}

class UserInfoArguments<Context: AccountContextProtocol> : PeerInfoArguments<Context> {
    
    
    typealias SetPhotoType = UserInfoArgumentsSetPhotoType
    

    private let shareDisposable = MetaDisposable()
    private let ownContactShareAction = ProfileOwnContactShareAction()
    private let blockDisposable = MetaDisposable()
    private let startSecretChatDisposable = MetaDisposable()
    private let updatePeerNameDisposable = MetaDisposable()
    private let deletePeerContactDisposable = MetaDisposable()
    private let toggleCopyProtectionDisposable = MetaDisposable()
    private let botEmojiStatusDisposable = MetaDisposable()
    private var botEmojiStatusOperationId: UUID?
    private var acceptsEmojiPermissionRequests = true
    private let callDisposable = MetaDisposable()
    private let updatePhotoDisposable = MetaDisposable()

    var getController: (() -> PeerInfoController<Context>?)? = nil

    private func rowMorphSource(_ stableIndex: Int) -> (() -> NSView?) {
        return { [weak self] in
            return (self?.getController?()?.genericView.tableView.item(stableId: IntPeerInfoEntryStableId(value: stableIndex).hashValue)?.view as? GeneralContainableRowView)?.containerView
        }
    }

    func giftPremium(_ isBirthday: Bool) {
        showModal(with: GiftingController(context: context, peerId: self.effectivePeerId, isBirthday: isBirthday, starGiftsContext: getStarGiftsContext?()), for: context.window)
    }
    
    func editBot(_ payload: String?, action: Bool = true) -> Void {
        let context = self.context
        if let username = peer?.addressName {
            let botFather = showModalProgress(signal: PeerInfoUIHooks.shared.resolveUsername("botfather", context), for: context.window)
            _ = botFather.start(next: { [weak self] peer in
                if let peer = peer {
                    let payload = payload != nil ? "-\(payload!)" : ""
                    let initialAction: ChatInitialAction?
                    if action {
                        initialAction = .start(parameter: username + payload, behavior: .automatic)
                    } else {
                        initialAction = nil
                    }
                    self?.pullNavigation()?.push(ChatAdditionController(context: context, chatLocation: .peer(peer.id), initialAction: initialAction))
                }
            })
        }
    }
    
    func openApp() {
        if let peer {
            BrowserStateContext.get(context).open(tab: .mainapp(bot: .init(peer), source: .generic))
        }
    }
    func openBotfather() {
        self.editBot(nil, action: false)
    }
    func openEditBotUsername() {
        self.pullNavigation()?.push(EditBotUsernameController(context: context, peerId: peerId))
    }
    
    func openAffiliate(starRefProgram: TelegramStarRefProgram?) {
        if let starRefProgram, let peer, peer.botInfo?.flags.contains(.canEdit) == false {
            showModal(with: Affiliate_ProgramPreview(context: context, peerId: context.peerId, program: AffiliateProgram.init(starRefProgram, peer: .init(peer)), joined: { _ in
                
            }), for: context.window)
        } else {
            self.pullNavigation()?.push(Affiliate_StartController(context: context, peerId: peerId, starRefProgram: starRefProgram))
        }
    }
    
    func openVerifyAccounts(_ verification: BotVerifierSettings) {
        let context = self.context
        let botId = self.peerId
        
        
        _ = selectModalPeers(window: context.window, context: context, title: strings().peerInfoVerifyAccounts, limit: 1, behavior: SelectChatsBehavior(settings: [.bots, .channels, .groups, .remote], excludePeerIds: [self.peerId], limit: 1), confirmation: { peerIds in
            
            return Signal { subscriber in
                
                if let peerId = peerIds.first {
                    
                    
                    let peer = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId), TelegramEngine.EngineData.Item.Peer.Verification(id: peerId)) |> deliverOnMainQueue
                    
                    _ = peer.startStandalone(next: { peer, currentVerification in
                        if let peer {
                            
                            let limit = context.appConfiguration.getGeneralValue("bot_verification_description_length_limit", orElse: 70)

                            var text: Updated_ChatTextInputState = .init(inputText: .init())
                            
                            let title: String
                            let info: String
                            let ok: String
                            let footer: ModalAlertData.Footer?
                            if currentVerification?.botId == botId {
                                title = strings().botVerificationRemoveTitle
                                if peer._asPeer().isBot {
                                    info = strings().botVerificationRemoveBotText
                                } else if peer._asPeer().isChannel {
                                    info = strings().botVerificationRemoveChannelText
                                } else if peer._asPeer().isSupergroup {
                                    info = strings().botVerificationRemoveGroupText
                                } else {
                                    info = strings().botVerificationRemoveUserText
                                }
                                ok = strings().botVerificationRemoveRemove
                                footer = nil
                            } else {
                                if peer._asPeer().isBot {
                                    title = strings().botVerificationVerifyBotTitle
                                } else if peer._asPeer().isChannel {
                                    title = strings().botVerificationVerifyChannelTitle
                                } else if peer._asPeer().isSupergroup {
                                    title = strings().botVerificationVerifyGroupTitle
                                } else {
                                    title = strings().botVerificationVerifyUserTitle
                                }
                                if peer._asPeer().isBot {
                                    info = strings().botVerificationVerifyBotText
                                } else if peer._asPeer().isChannel {
                                    info = strings().botVerificationVerifyChannelText
                                } else if peer._asPeer().isSupergroup {
                                    info = strings().botVerificationVerifyGroupText
                                } else {
                                    info = strings().botVerificationVerifyUserText
                                }
                                ok = strings().botVerificationVerifyVerify
                                footer = .init(id: "footer", value: { initialSize, stableId, presentation, updateData in
                                    return InputTextDataRowItem(initialSize, stableId: 0, context: context, state: text, viewType: .singleItem, placeholder: nil, inputPlaceholder: strings().botVerificationVerifyPlaceholder, filter: { $0 }, updateState: { updated in
                                        text = updated
                                        DispatchQueue.main.async(execute: updateData)
                                    }, limit: limit, hasEmoji: true)
                                })
                            }
                                                        
                            let data = ModalAlertData(title: title, info: info, description: nil, ok: ok, options: [], mode: .confirm(text: strings().modalCancel, isThird: false), footer: .init(id: "footer", value: { initialSize, stableId, presentation, _ in
                                return Bot_VerifyAccountRowItem(initialSize, stableId: stableId, peer: peer, context: context, fileId: verification.iconFileId)
                            }), footer1: footer)
                            
                            showModalAlert(for: context.window, data: data, completion: { result in
                                
                                let update: UpdateCustomVerificationValue
                                if currentVerification?.botId == botId {
                                    update = .disabled
                                } else {
                                    let description = text.string
                                    let entities = text.textInputState().messageTextEntities()
                                    update = .enabled(description: description.isEmpty ? nil : description,
                                                      descriptionEntities: description.isEmpty || entities.isEmpty ? nil : entities)
                                }
                                
                                subscriber.putNext(true)
                                subscriber.putCompletion()
                                
                                _ = showModalProgress(signal: context.engine.peers.updateCustomVerification(botId: botId, peerId: peerId, value: update), for: context.window).start(error: { error in
                                    switch error {
                                    case .generic:
                                        showModalText(for: context.window, text: strings().unknownError)
                                    }
                                }, completed: {
                                    if currentVerification?.botId == botId {
                                        showModalText(for: context.window, text: strings().botVerificationRemoved(peer._asPeer().displayTitle))
                                    } else {
                                        showModalText(for: context.window, text: strings().botVerificationAdded(peer._asPeer().displayTitle))
                                    }
                                })
                            })
                        }
                    })
                }
                
                return EmptyDisposable
            }
        }).start(next: { peerIds in
            
            
        })
    }
    
    func openStarsBalance() {
        if let revenueContext = getStarsContext?() {
            self.pullNavigation()?.push(PeerInfoNavigationHooks.shared.makeStarMonetizationController(context, peerId, revenueContext))
        }
    }
    
    func openTonBalance() {
        if let revenueContext = getTonContext?() {
            self.pullNavigation()?.push(PeerInfoNavigationHooks.shared.makeTonMonetizationController(context, peerId, revenueContext))
        }
    }
    
    func shareContact() {
        ownContactShareAction.reset()
        let context = self.context
        let peer = getPeerView(peerId: effectivePeerId, postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue
        shareDisposable.set((peer).start(next: { [weak self] peer in
            guard let context = self?.context else {
                return
            }
            if let peer = peer as? TelegramUser {
                let controller = ShareModalController(ShareContactObject(context, user: peer))
                showModal(with: controller, for: context.window)
            } else {
            }
        }))
    }
    
    func setEmojiPermissionRequestsActive(_ active: Bool) {
        acceptsEmojiPermissionRequests = active
        if !active {
            botEmojiStatusOperationId = nil
            botEmojiStatusDisposable.set(nil)
        }
    }

    func togglePermissionsStatus() {
        guard acceptsEmojiPermissionRequests, botEmojiStatusOperationId == nil else {
            return
        }
        let operationId = UUID()
        botEmojiStatusOperationId = operationId
        let pending = MetaDisposable()
        botEmojiStatusDisposable.set(pending)
        let signal = context.engine.peers.toggleBotEmojiStatusAccess(peerId: peerId, enabled: false)
        |> deliverOnMainQueue
        |> afterDisposed { [weak self] in
            Queue.mainQueue().async { [weak self] in
                if self?.botEmojiStatusOperationId == operationId {
                    self?.botEmojiStatusOperationId = nil
                }
            }
        }
        pending.set(showModalProgress(signal: signal, for: context.window).start(error: { [weak self] _ in
            guard let self, self.botEmojiStatusOperationId == operationId else {
                return
            }
            self.botEmojiStatusOperationId = nil
            alert(for: self.context.window, info: strings().unknownError)
        }, completed: { [weak self] in
            if self?.botEmojiStatusOperationId == operationId {
                self?.botEmojiStatusOperationId = nil
            }
        }))
    }
    func togglePermissionsGeo() {
        let _ = updateWebAppPermissionsStateInteractively(context: context, peerId: peerId) { current in
            return WebAppPermissionsState(location: WebAppPermissionsState.Location(isRequested: true, isAllowed: !(current?.location?.isAllowed ?? false)), emojiStatus: current?.emojiStatus)
        }.start()
    }

    func toggleCopyProtection(_ enabled: Bool) {
        toggleCopyProtectionDisposable.set((context.engine.peers.toggleMessageCopyProtection(peerId: peerId, enabled: enabled) |> deliverOnMainQueue).start(next: { [weak self] result in
            guard let context = self?.context else { return }
            switch result {
            case .applied:
                showModalText(for: context.window, text: enabled ? strings().chatServiceCopyProtectionSharingDisabledToast : strings().chatServiceCopyProtectionSharingEnabledToast)
            case .requested:
                showModalText(for: context.window, text: enabled ? strings().chatServiceCopyProtectionSharingWillBeDisabled : strings().chatServiceCopyProtectionSharingWillBeEnabled)
            }
        }))
    }
    
    func shareMyInfo() {
        shareDisposable.set(nil)
        ownContactShareAction.start(context: context, peerId: peerId)
    }
    
    func addContact() {
        let context = self.context
        let morphSource = rowMorphSource(139)
        let peerView = getPeerView(peerId: peerId, postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue
        _ = peerView.start(next: { peer in
            if let peer = peer {
                showModal(with: NewContactController(context: context, peerId: peer.id), for: context.window, morphSource: morphSource)
            }
        })
    }

    override func updateEditable(_ editable:Bool, peerView:PeerView, controller: PeerInfoController<Context>) -> Bool {
        
        let context = self.context
        let peerId = self.peerId
        let isEditableBot = self.peer?.botInfo?.flags.contains(.canEdit) == true
        let updateState:((UserInfoState)->UserInfoState)->Void = { [weak self] f in
            self?.updateState(f)
        }
        
        let peer = self.peer as? TelegramUser
        
        let firstName: String = peerViewMainPeer(peerView)?.compactDisplayTitle ?? ""
        let lastName = isEditableBot ? (peerView.cachedData as? CachedUserData)?.about : peer?.lastName
        let note = (peerView.cachedData as? CachedUserData)?.note

        if editable {
            updateState { state -> UserInfoState in
                return state.withUpdatedEditingState(UserInfoEditingState(editingFirstName: firstName, editingLastName: lastName, editingNotes: note))
            }
        } else {
            var updateValues: (firstName: String?, lastName: String?, note: CachedUserData.Note?) = (nil, nil, nil)
            updateState { state in
                if let peer = peerViewMainPeer(peerView) as? TelegramUser {
                    if peer.firstName != state.editingState?.editingFirstName {
                        updateValues.firstName = state.editingState?.editingFirstName
                    }
                    if lastName != state.editingState?.editingLastName {
                        updateValues.lastName = state.editingState?.editingLastName
                    }
                    if note != state.editingState?.editingNotes {
                        updateValues.note = state.editingState?.editingNotes
                    }
                    return state.withUpdatedSavingData(true)
                } else {
                    return state.withUpdatedEditingState(nil)
                }
            }
            
            if let firstName = updateValues.firstName, firstName.isEmpty {
                controller.genericView.tableView.item(stableId: IntPeerInfoEntryStableId(value: 101).hashValue)?.view?.shakeView()
                return false
            }
            
            
            if updateValues.firstName != nil || updateValues.lastName != nil || updateValues.note != nil{
                updateState { state in
                    return state.withUpdatedSavingData(true)
                }
            } else {
                updateState { state in
                    return state.withUpdatedEditingState(nil)
                }
            }
            
            
            let updateNames: Signal<Never, UpdateError>
            
            
            if updateValues.firstName != nil || updateValues.lastName != nil || updateValues.note != nil  {
                if isEditableBot {
                    var signals:[Signal<Void, UpdateError>] = []
                    if let firstName = updateValues.firstName {
                        signals.append(context.engine.peers.updateBotName(peerId: peerId, name: firstName) |> mapError { _ in return UpdateError.generic })
                    }
                    
                    if let lastName = updateValues.lastName {
                        signals.append(context.engine.peers.updateBotAbout(peerId: peerId, about: lastName) |> mapError { _ in return UpdateError.generic })
                    }
                    
                    updateNames = combineLatest(signals) |> ignoreValues
                } else {
                    
                    var signals:[Signal<Never, UpdateError>] = []
                    
                    if let note = updateValues.note {
                        signals.append(context.engine.contacts.updateContactNote(peerId: peerId, text: note.text, entities: note.entities) |> mapError { _ in return UpdateError.generic })
                    }
                    if updateValues.firstName != nil || updateValues.lastName != nil {
                        signals.append(context.engine.contacts.updateContactName(peerId: peerId, firstName: updateValues.firstName ?? peer?.firstName ?? "", lastName: updateValues.lastName ?? peer?.lastName ?? "") |> mapError { _ in return UpdateError.generic } |> ignoreValues)
                    }
                    
                    updateNames = showModalProgress(signal: combineLatest(signals), for: context.window) |> ignoreValues
                }
            } else {
                updateNames = .complete()
            }
            
            self.updatePeerNameDisposable.set(updateNames.start(error: { _ in
                updateState { state in
                    return state.withUpdatedSavingData(false)
                }
            }, completed: {
                updateState { state in
                    return state.withUpdatedSavingData(false).withUpdatedEditingState(nil)
                }
            }))
            
        }
        
        return true
    }
    
    func sendMessage() {
        self.peerChat(self.effectivePeerId)
    }
    
    
    func openLocation(_ peer: Peer, _ location: TelegramBusinessLocation) {
        if let coordinates = location.coordinates {
            showModal(with: LocationModalPreview(context, map: .init(latitude: coordinates.latitude, longitude: coordinates.longitude, heading: nil, accuracyRadius: nil, venue: nil, liveBroadcastingTimeout: nil, liveProximityNotificationRadius: nil), peer: peer, messageId: nil), for: context.window, morphSource: rowMorphSource(129))
        }
    }
    func openHours(_ peer: Peer, _ businessHours: TelegramBusinessHours) {
        let updateState:((UserInfoState)->UserInfoState)->Void = { [weak self] f in
            self?.updateState(f)
        }
        updateState { state in
            return state.withBusinessHoursRevealed(!state.businessHoursRevealed)
        }
    }
    
    func toggleDisplayZoneTime() {
        let updateState:((UserInfoState)->UserInfoState)->Void = { [weak self] f in
            self?.updateState(f)
        }
        updateState { state in
            return state.withBusinessHoursTimeZoneUpdated(!state.businessHoursDisplayMyTimezone).withBusinessHoursRevealed(true)
        }
    }
        
    func reportReaction(_ messageId: MessageId) {
        let block: Signal<Never, NoError> = context.blockedPeersContext.add(peerId: peerId) |> `catch` { _ in .complete() }
        let report = context.engine.peers.reportPeerReaction(authorId: self.peerId, messageId: messageId) |> ignoreValues
        let context = self.context
        _ = showModalProgress(signal: combineLatest(block, report), for: context.window).start(completed: {
            showModalText(for: context.window, text: strings().peerInfoReportReactionSuccess)
        })
    }
    
    func call(_ isVideo: Bool) {
        let context = self.context
        let peer = getPeerView(peerId: effectivePeerId, postbox: context.account.postbox) |> take(1) |> map {
            return $0?.id
        } |> filter { $0 != nil } |> map { $0! }
        
        let call = peer |> mapToSignal {
            phoneCall(context: context, peerId: $0, isVideo: isVideo)
        } |> deliverOnMainQueue
        
        self.callDisposable.set(call.start(next: { result in
            applyUIPCallResult(context, result)
        }))
    }
    
    func openPersonalChannel(_ item: UserInfoPersonalChannel) {
        self.pullNavigation()?.push(ChatAdditionController(context: context, chatLocation: .peer(item.peer.id)))
    }
        
    func botAddToGroup() {
        let context = self.context
        let peerId = self.peerId
        
        let result = selectModalPeers(window: context.window, context: context, title: strings().selectPeersTitleSelectGroupOrChannel, behavior: SelectChatsBehavior(settings: [.groups, .channels], limit: 1), confirmation: { peerIds -> Signal<Bool, NoError> in
            return .single(true)
        })
        |> filter { $0.first != nil }
        |> map { $0.first! }
        |> mapToSignal { sourceId in
            return combineLatest(context.account.postbox.loadedPeerWithId(peerId), context.account.postbox.loadedPeerWithId(sourceId)) |> map {
                (dest: $0, source: $1)
            }
        } |> deliverOnMainQueue
        
        
        _ = result.start(next: { [weak self] values in
            
            let addAdmin:()->Void = {
                showModal(with: ChannelBotAdminController(context: context, peer: values.source, admin: values.dest, callback: { [weak self] peerId in
                    self?.peerChat(peerId)
                }), for: context.window)
            }
            let addSimple:()->Void = {
                verifyAlert_button(for: context.window, information: strings().confirmAddBotToGroup(values.dest.displayTitle), successHandler: { [weak self] _ in
                    addBotAsMember(context: context, peer: values.source, to: values.dest, completion: { [weak self] peerId in
                        self?.peerChat(peerId, postId: nil)
                    }, error: { error in 
                        alert(for: context.window, info: error)
                    })
                })
            }
            if let peer = values.source as? TelegramChannel {
                if peer.groupAccess.isCreator {
                    addAdmin()
                } else if let adminRights = peer.adminRights, adminRights.rights.contains(.canAddAdmins) {
                    addAdmin()
                } else {
                    addSimple()
                }
            } else if let peer = values.source as? TelegramGroup {
                switch peer.role {
                case .creator:
                    addAdmin()
                default:
                    addSimple()
                }
            }
        })
    }

    func addBotToCommunity() {
        self.pullNavigation()?.push(CommunitiesController(context, peerId: peerId))
    }

    func openCommunity(_ communityId: PeerId) {
        showCommunityView(context, communityId: communityId)
    }

    func removeBotFromCommunity(_ communityId: PeerId) {
        let context = self.context
        let peerId = self.peerId
        verifyAlert_button(for: context.window, information: strings().userInfoRemoveBotFromCommunity, successHandler: { _ in
            _ = context.engine.peers.toggleCommunityPeerLink(communityId: communityId, peerId: peerId, action: .unlink).start()
        })
    }
    func botShare(_ botName: String) {
        showModal(with: ShareModalController(ShareLinkObject(context, link: context.meUrlPrefix + "\(botName)")), for: context.window)
    }
    
    func giftBirthday() {
        let context = self.context
        
        let peerId = self.peerId
        
        multigift(context: context, selected: [peerId])
        
    }
    
    func botSettings() {
        _ = Sender.enqueue(input: ChatTextInputState(inputText: "/settings"), context: context, peerId: peerId, replyId: nil, threadId: nil).start()
        pullNavigation()?.back()
    }
    func botHelp() {
        _ = Sender.enqueue(input: ChatTextInputState(inputText: "/help"), context: context, peerId: peerId, replyId: nil, threadId: nil).start()
        pullNavigation()?.back()
    }
    
    func reportBot() {
        let peerId = self.peerId
        let context = self.context
        
        reportComplicated(context: context, subject: .peer(peerId), title: strings().reportComplicatedPeerTitle(self.peer?.displayTitle ?? ""))
        
    }
    
    func botPrivacy() {
        _ = Sender.enqueue(input: ChatTextInputState(inputText: "/privacy"), context: context, peerId: peerId, replyId: nil, threadId: nil).start()
        pullNavigation()?.back()
    }
    
    func startSecretChat() {
        let context = self.context
        let peerId = self.peerId
        
        let peer = context.account.postbox.loadedPeerWithId(peerId)
        let premiumRequired = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.IsPremiumRequiredForMessaging(id: peerId))
        
        let signal = combineLatest(peer, premiumRequired) |> castError(CreateSecretChatError.self) |> deliverOnMainQueue |> mapToSignal { peer, premiumRequired -> Signal<PeerId?, CreateSecretChatError> in
            if !context.isPremium && premiumRequired {
                return .single(nil)
            }
            let confirm = verifyAlertSignal(for: context.window, header: strings().peerInfoConfirmSecretChatHeader, information: strings().peerInfoConfirmStartSecretChat(peer.displayTitle), ok: strings().peerInfoConfirmSecretChatOK) |> castError(CreateSecretChatError.self)
            return confirm |> filter { $0 == .basic } |> mapToSignal { _ -> Signal<PeerId?, CreateSecretChatError> in
                return showModalProgress(signal: context.engine.peers.createSecretChat(peerId: peer.id), for: context.window) |> map(Optional.init)
            }
        } |> deliverOnMainQueue
        
        
        
        startSecretChatDisposable.set(signal.start(next: { [weak self] peerId in
            if let strongSelf = self {
                if let peerId = peerId {
                    strongSelf.pushViewController(ChatController(context: strongSelf.context, chatLocation: .peer(peerId)))
                }
            }
        }, error: { error in
            switch error {
            case .generic:
                showModalText(for: context.window, text: strings().unknownError)
            case .limitExceeded:
                showModalText(for: context.window, text: strings().loginFloodWait)
            case let .premiumRequired(peer):
                showModalText(for: context.window, text: strings().chatSecretChatPremiumRequired(peer._asPeer().compactDisplayTitle), button: strings().alertLearnMore, callback: { _ in
                    prem(with: PremiumBoardingController(context: context), for: context.window)
                })
            }
        }))
    }
    
    override func dismissEdition() {
        updateState { state in
            return state.withUpdatedSavingData(false).withUpdatedEditingState(nil)
        }
    }
    
    func updateState(_ f: (UserInfoState) -> UserInfoState) -> Void {
        updateInfoState { state -> PeerInfoState in
            return f(state as! UserInfoState)
        }
    }
    
    func updateEditingNames(firstName: String?, lastName:String?, notes: CachedUserData.Note?) -> Void {
        updateState { state in
            if let editingState = state.editingState {
                return state.withUpdatedEditingState(
                    editingState
                    .withUpdatedEditingFirstNameText(firstName).withUpdatedEditingLastNameText(lastName)
                    .withUpdatedEditingNotesText(notes)
                )
            } else {
                return state
            }
        }
    }
    
    func updateBlocked(peer: Peer,_ blocked:Bool, _ isBot: Bool) {
        let context = self.context
        var peerId = peer.id
        if let peer = peer as? TelegramSecretChat {
            peerId = peer.regularPeerId
        }
        if blocked {
            verifyAlert_button(for: context.window, header: strings().peerInfoBlockHeader, information: strings().peerInfoBlockText(peer.displayTitle), ok: strings().peerInfoBlockOK, successHandler: { [weak self] _ in
                let signal = showModalProgress(signal: context.blockedPeersContext.add(peerId: peerId) |> deliverOnMainQueue, for: context.window)
                self?.blockDisposable.set(signal.start(error: { error in
                    switch error {
                    case .generic:
                        alert(for: context.window, info: strings().unknownError)
                    }
                }, completed: {
                    
                }))
            })
        } else {
            let signal = showModalProgress(signal: context.blockedPeersContext.remove(peerId: peerId) |> deliverOnMainQueue, for: context.window)
            blockDisposable.set(signal.start(error: { error in
                switch error {
                case .generic:
                    alert(for: context.window, info: strings().unknownError)
                }
            }, completed: {
                
            }))
        }
        
        if !blocked && isBot {
            pushViewController(ChatController(context: context, chatLocation: .peer(peer.id), initialAction: ChatInitialAction.start(parameter: "", behavior: .automatic)))
        }

    }
    
    func deleteContact() {
        let context = self.context
        let peerId = self.peerId
        
        verifyAlert(for: context.window, information: strings().peerInfoConfirmDeleteContact, ok: strings().modalDelete, successHandler: { _ in
            _ = showModalProgress(signal: context.engine.contacts.deleteContactPeerInteractively(peerId: peerId) |> deliverOnMainQueue, for: context.window).start()
        })

    }
    
    
    func encryptionKey() {
        pushViewController(SecretChatKeyViewController(context, peerId: peerId))
    }
    
    func suggestBirthday() {
        let context = self.context
        let peerId = self.peerId
        let controller = CalendarController(NSMakeRect(0, 0, 300, 300), context.window, current: Date(), lowYear: 1900, canBeNoYear: true, selectHandler: { date in
            let calendar = Calendar.current
            let day = calendar.component(.day, from: date)
            let month = calendar.component(.month, from: date)
            let year = calendar.component(.year, from: date)

            _ = showModalProgress(signal: context.engine.peers.suggestBirthday(peerId: peerId, birthday: .init(day: Int32(day), month: Int32(month), year: Int32(year))), for: context.window).startStandalone(error: { error in
                switch error {
                case .generic:
                    showModalText(for: context.window, text: strings().unknownError)
                }
            }, completed: {
                showModalText(for: context.window, text: strings().peerInfoBirthdaySuggested)
            })
        })
        
        let nav = NavigationViewController(controller, context.window)

        nav._frameRect = NSMakeRect(0, 0, 300, 310)

        showModal(with: nav, for: context.window, morphSource: rowMorphSource(145))
    }
    
    private func makeUpdatePhotoItems(_ custom: NSImage?, type: SetPhotoType) -> [ContextMenuItem] {
        let context = self.context
        let peerId = self.peerId
        let isEditableBot = self.peer?.botInfo?.flags.contains(.canEdit) == true
        let info = strings().userInfoSetPhotoInfo(peer?.compactDisplayTitle ?? "")
        
        let updatePhoto:(Signal<NSImage, NoError>) -> Void = { [weak self] image in
            let signal = image |> mapToSignal { image in
                return putToTemp(image: image, compress: true)
            } |> deliverOnMainQueue
            _ = signal.start(next: { [weak self] path in
                guard let controller = EditImageModalController(URL(fileURLWithPath: path), context: context, settings: .disableSizes(dimensions: .square, circle: true), confirm: { url, f in
                    if isEditableBot {
                        f()
                    } else {
                        showModal(with: UserInfoPhotoConfirmController(context: context, peerId: peerId, thumb: url, type: type, confirm: f), for: context.window)
                    }
                }) else { return }
                showModal(with: controller, for: context.window, animationType: .scaleCenter)
                _ = (controller.result |> take(1)).start(next: { [weak self] url, _ in
                    DispatchQueue.main.async {
                        self?.updatePhoto(url.path, type: type)
                    }
                })
            })
        }
        if let image = custom {
            updatePhoto(.single(image))
        } else {
            
            let context = self.context
            let updateVideo = self.updateVideo
            
            let _:(MediaObjectToAvatar)->Void = { object in
                makeAvatarVideo(object, updatePhoto: updatePhoto, updateVideo: { updateVideo($0, type) })
            }
            
            
            var items:[ContextMenuItem] = []
            
            items.append(.init(strings().editAvatarPhotoOrVideo, handler: {
                filePanel(with: photoExts + videoExts, allowMultiple: false, canChooseDirectories: false, for: context.window, completion: { paths in
                    if let path = paths?.first, let image = NSImage(contentsOfFile: path) {
                        updatePhoto(.single(image))
                    } else if let path = paths?.first {
                        selectVideoAvatar(context: context, path: path, localize: info, signal: { signal in
                            updateVideo(signal, type)
                        }, confirm: { url, f in
                            if isEditableBot {
                                f()
                            } else {
                                showModal(with: UserInfoPhotoConfirmController(context: context, peerId: peerId, thumb: url, type: type, confirm: f), for: context.window)
                            }
                        })
                    }
                })
            }, itemImage: MenuAnimation.menu_shared_media.value))
//            
//            items.append(.init(strings().editAvatarCustomize, handler: {
//                showModal(with: AvatarConstructorController(context, target: .avatar, videoSignal: makeVideo, confirm: { url, f in
//                    showModal(with: UserInfoPhotoConfirmController(context: context, peerId: peerId, thumb: url, type: type, confirm: f), for: context.window)
//                }), for: context.window)
//            }, itemImage: MenuAnimation.menu_view_sticker_set.value))
            
            return items
        }
        return []
    }
    
    func updateContactPhoto(_ custom: NSImage?, control: Control?, type: SetPhotoType) {
        let context = self.context
        let peerId = self.peerId
        let info = strings().userInfoSetPhotoInfo(peer?.compactDisplayTitle ?? "")
        let updateVideo = self.updateVideo
        let updatePhoto:(Signal<NSImage, NoError>) -> Void = { [weak self] image in
            let signal = image |> mapToSignal { image in
                return putToTemp(image: image, compress: true)
            } |> deliverOnMainQueue
            _ = signal.start(next: { [weak self] path in
                guard let controller = EditImageModalController(URL(fileURLWithPath: path), context: context, settings: .disableSizes(dimensions: .square, circle: true), confirm: { url, f in
                    showModal(with: UserInfoPhotoConfirmController(context: context, peerId: peerId, thumb: url, type: type, confirm: f), for: context.window)
                }) else { return }
                showModal(with: controller, for: context.window, animationType: .scaleCenter)
                _ = (controller.result |> take(1)).start(next: { [weak self] url, _ in
                    DispatchQueue.main.async {
                        self?.updatePhoto(url.path, type: type)
                    }
                })
            })
        }
        let items = self.makeUpdatePhotoItems(custom, type: type)
        
        if let control = control, let event = NSApp.currentEvent, !items.isEmpty {
            let menu = ContextMenu()
            for item in items {
                menu.addItem(item)
            }
            let value = AppMenu(menu: menu)
            value.show(event: event, view: control)
        } else {
            filePanel(with: photoExts + videoExts, allowMultiple: false, canChooseDirectories: false, for: context.window, completion: { paths in
                if let path = paths?.first, let image = NSImage(contentsOfFile: path) {
                    updatePhoto(.single(image))
                } else if let path = paths?.first {
                    selectVideoAvatar(context: context, path: path, localize: info, signal: { signal in
                        updateVideo(signal, type)
                    }, confirm: { url, f in
                        showModal(with: UserInfoPhotoConfirmController(context: context, peerId: peerId, thumb: url, type: type, confirm: f), for: context.window)
                    })
                }
            })
        }
            
    }
    
    
    func updatePhoto(_ path:String, type: SetPhotoType) -> Void {
        
        let updateState:((UserInfoState)->UserInfoState)->Void = { [weak self] f in
            self?.updateState(f)
        }
        
        let cancel = { [weak self] in
            self?.updatePhotoDisposable.set(nil)
            updateState { state -> UserInfoState in
                return state.withoutUpdatingPhotoState()
            }
        }
        
        let context = self.context
        let peerId = self.peerId
        let title = self.peer?.compactDisplayTitle ?? ""
        
        let isEditableBot = self.peer?.botInfo?.flags.contains(.canEdit) == true
        
        let suggestSignal = Signal<String, NoError>.single(path) |> map { path -> TelegramMediaResource in
            return LocalFileReferenceMediaResource(localFilePath: path, randomId: arc4random64())
            } |> castError(UploadPeerPhotoError.self) |> mapToSignal { resource -> Signal<UpdatePeerPhotoStatus, UploadPeerPhotoError> in
                return context.engine.contacts.updateContactPhoto(peerId: peerId, resource: EngineMediaResource(resource), videoResource: nil, videoStartTimestamp: nil, markup: nil, mode: .suggest, mapResourceToAvatarSizes: { resource, representations in
                    return mapResourceToAvatarSizes(engine: context.engine, resource: resource, representations: representations)
                })
        }
        
        let updateSignal = Signal<String, NoError>.single(path) |> map { path -> TelegramMediaResource in
            return LocalFileReferenceMediaResource(localFilePath: path, randomId: arc4random64())
            } |> beforeNext { resource in
                updateState { state in
                    return state.withUpdatedUpdatingPhotoState { previous -> PeerInfoUpdatingPhotoState? in
                        return PeerInfoUpdatingPhotoState(progress: 0, image: NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil), cancel: cancel)
                    }
                }
            } |> castError(UploadPeerPhotoError.self) |> mapToSignal { resource -> Signal<UpdatePeerPhotoStatus, UploadPeerPhotoError> in
                return context.engine.contacts.updateContactPhoto(peerId: peerId, resource: EngineMediaResource(resource), videoResource: nil, videoStartTimestamp: nil, markup: nil, mode: .custom, mapResourceToAvatarSizes: { resource, representations in
                    return mapResourceToAvatarSizes(engine: context.engine, resource: resource, representations: representations)
                })
        }
        
        switch type {
        case .suggest:
            self.updatePhotoDisposable.set((suggestSignal |> deliverOnMainQueue).start(next: { value in
                updateState { current in
                    return current.withUpdatedSuggestingPhotoState({ _ in
                        .init(progress: 0, cancel: {})
                    })
                }
            }, completed: { [weak self] in
                if !isEditableBot {
                    showModalText(for: context.window, text: strings().userInfoSuggestTooltip(title))
                }
                updateState { current in
                    return current.withoutSuggestingPhotoState()
                }
                self?.pullNavigation()?.back()
            }))
        case .set:
            self.updatePhotoDisposable.set((updateSignal |> deliverOnMainQueue).start(next: { status in
                updateState { state in
                    switch status {
                    case .complete:
                        return state
                    case let .progress(progress):
                        return state.withUpdatedUpdatingPhotoState { previous -> PeerInfoUpdatingPhotoState? in
                            return previous?.withUpdatedProgress(progress)
                        }
                    }
                }
            }, error: { error in
                updateState { state in
                    return state.withoutUpdatingPhotoState()
                }
            }, completed: {
                updateState { state in
                    return state.withoutUpdatingPhotoState()
                }
                resetPeerPhotos(peerId: peerId)
                if !isEditableBot {
                    showModalText(for: context.window, text: strings().userInfoSetPhotoTooltip(title))
                }
            }))
        }        
    }
    
    func updateVideo(_ signal:Signal<VideoAvatarGeneratorState, NoError>, type: SetPhotoType) -> Void {
        
        let updateState:((UserInfoState)->UserInfoState)->Void = { [weak self] f in
            self?.updateState(f)
        }
        
        let cancel = { [weak self] in
            self?.updatePhotoDisposable.set(nil)
            updateState { state in
                return state.withoutUpdatingPhotoState()
            }
        }
        
        let context = self.context
        let peerId = self.peerId
        let title = self.peer?.compactDisplayTitle ?? ""
        
        let suggestSignal: Signal<UpdatePeerPhotoStatus, UploadPeerPhotoError> = signal
        |> castError(UploadPeerPhotoError.self)
        |> mapToSignal { state in
            switch state {
            case .error:
                return .fail(.generic)
            case .start:
                return .next(.progress(0))
            case let .progress(value):
                return .next(.progress(value * 0.2))
            case let .complete(thumb, video, keyFrame):
                
                let (thumbResource, videoResource) = (LocalFileReferenceMediaResource(localFilePath: thumb, randomId: arc4random64(), isUniquelyReferencedTemporaryFile: true),
                                                      LocalFileReferenceMediaResource(localFilePath: video, randomId: arc4random64(), isUniquelyReferencedTemporaryFile: true))

                
                return context.engine.contacts.updateContactPhoto(peerId: peerId, resource: EngineMediaResource(thumbResource), videoResource: EngineMediaResource(videoResource), videoStartTimestamp: keyFrame, markup: nil, mode: .suggest, mapResourceToAvatarSizes: { resource, representations in
                    return mapResourceToAvatarSizes(engine: context.engine, resource: resource, representations: representations)
                }) |> mapToSignal { result in
                    switch result {
                    case let .progress(current):
                        if current == 1.0 {
                            return .single(.complete([]))
                        } else {
                            return .next(.progress(0.2 + (current * 0.8)))
                        }
                    default:
                        return .complete()
                    }
                }
            }
        }
        
        
        let updateSignal: Signal<UpdatePeerPhotoStatus, UploadPeerPhotoError> = signal
            |> castError(UploadPeerPhotoError.self)
            |> mapToSignal { state in
                switch state {
                case .error:
                    return .fail(.generic)
                case let .start(path):
                    updateState { state in
                        return state.withUpdatedUpdatingPhotoState { previous -> PeerInfoUpdatingPhotoState? in
                            return PeerInfoUpdatingPhotoState(progress: 0, image: NSImage(contentsOfFile: path)?._cgImage, cancel: cancel)
                        }
                    }
                    return .next(.progress(0))
                case let .progress(value):
                    return .next(.progress(value * 0.2))
                case let .complete(thumb, video, keyFrame):
                    
                    updateState { state in
                        return state.withUpdatedUpdatingPhotoState { previous -> PeerInfoUpdatingPhotoState? in
                            return PeerInfoUpdatingPhotoState(progress: 0.2, image: NSImage(contentsOfFile: thumb)?._cgImage, cancel: cancel)
                        }
                    }
                    
                    let (thumbResource, videoResource) = (LocalFileReferenceMediaResource(localFilePath: thumb, randomId: arc4random64(), isUniquelyReferencedTemporaryFile: true),
                                                          LocalFileReferenceMediaResource(localFilePath: video, randomId: arc4random64(), isUniquelyReferencedTemporaryFile: true))
                                        
                    return context.engine.contacts.updateContactPhoto(peerId: peerId, resource: EngineMediaResource(thumbResource), videoResource: EngineMediaResource(videoResource), videoStartTimestamp: keyFrame, markup: nil, mode: .custom, mapResourceToAvatarSizes: { resource, representations in
                        return mapResourceToAvatarSizes(engine: context.engine, resource: resource, representations: representations)
                    }) |> mapToSignal { result in
                        switch result {
                        case let .progress(current):
                            if current == 1.0 {
                                return .single(.complete([]))
                            } else {
                                return .next(.progress(0.2 + (current * 0.8)))
                            }
                        default:
                            return .complete()
                        }
                    }
                }
        }
        
        switch type {
        case .suggest:
            self.updatePhotoDisposable.set((suggestSignal |> deliverOnMainQueue).start(next: { [weak self] value in
                if case .complete = value {
                    showModalText(for: context.window, text: strings().userInfoSuggestTooltip(title))
                    updateState { current in
                        return current.withoutSuggestingPhotoState()
                    }
                    self?.pullNavigation()?.back()
                } else {
                    updateState { current in
                        return current.withUpdatedSuggestingPhotoState({ _ in
                            .init(progress: 0, cancel: {})
                        })
                    }
                }
            }))
        case .set:
            self.updatePhotoDisposable.set((updateSignal |> deliverOnMainQueue).start(next: { status in
                updateState { state in
                    switch status {
                    case .complete:
                        return state.withoutUpdatingPhotoState()
                    case let .progress(progress):
                        return state.withUpdatedUpdatingPhotoState { previous -> PeerInfoUpdatingPhotoState? in
                            return previous?.withUpdatedProgress(progress)
                        }
                    }
                }
            }, error: { error in
                updateState { state in
                    return state.withoutUpdatingPhotoState()
                }
            }, completed: {
                updateState { state in
                    return state.withoutUpdatingPhotoState()
                }
                resetPeerPhotos(peerId: peerId)
                showModalText(for: context.window, text: strings().userInfoSetPhotoTooltip(title))
            }))
        }
    }
    
    func resetPhoto() {
        let context = self.context
        let peerId = self.peerId
        verifyAlert_button(for: context.window, information: strings().userInfoResetPhotoConfirm(peer?.compactDisplayTitle ?? ""), ok: strings().userInfoResetPhotoConfirmOK, successHandler: { _ in
            let signal = context.engine.contacts.updateContactPhoto(peerId: peerId, resource: nil, videoResource: nil, videoStartTimestamp: nil, markup: nil, mode: .custom, mapResourceToAvatarSizes: { _,_  in
                return .complete()
            })
            _ = showModalProgress(signal: signal, for: context.window).start()
        })
    }
    
   
    func groupInCommon(_ peerId: PeerId) -> Void {
    }
    
    deinit {
        shareDisposable.dispose()
        blockDisposable.dispose()
        startSecretChatDisposable.dispose()
        updatePeerNameDisposable.dispose()
        deletePeerContactDisposable.dispose()
        callDisposable.dispose()
        updatePhotoDisposable.dispose()
        toggleCopyProtectionDisposable.dispose()
        botEmojiStatusDisposable.dispose()
    }
    
}

struct UserInfoAddress : Equatable {
    let username: String
    let collectable: Bool
}

private final class UnofficialWarningItem: GeneralRowItem {
    fileprivate let textLayout: TextViewLayout
    fileprivate let context: any AccountContextProtocol
    init(_ initialSize: NSSize, stableId: AnyHashable, text: String, context: any AccountContextProtocol, viewType: GeneralViewType) {
        self.context = context
        let attr = NSMutableAttributedString()
        attr.append(.embedded(name: "Icon_DialogSendingError", color: theme.colors.redUI, resize: false))
        attr.append(string: " " + text, color: theme.colors.text, font: .normal(.text))
        self.textLayout = TextViewLayout(attr)
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }
    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        textLayout.measure(width: blockWidth - viewType.innerInset.left - viewType.innerInset.right)
        return true
    }
    override var height: CGFloat {
        return textLayout.layoutSize.height + viewType.innerInset.top + viewType.innerInset.bottom
    }
    override func viewClass() -> AnyClass {
        return UnofficialWarningView.self
    }
    override var accessibilityLabel: String? {
        let text = textLayout.attributedString.string.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FFFC}")))
        return text.isEmpty ? nil : text
    }
    override var accessibilityRole: NSAccessibility.Role? {
        return .staticText
    }
    override var accessibilityIncludesChildren: Bool {
        return false
    }
}

private final class UnofficialWarningView: GeneralContainableRowView {
    private let textView = InteractiveTextView(frame: .zero)
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textView.userInteractionEnabled = false
        addSubview(textView)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? UnofficialWarningItem else { return }
        textView.set(text: item.textLayout, context: item.context)
    }
    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        guard let item = item as? UnofficialWarningItem else { return }
        transition.updateFrame(view: textView, frame: CGRect(origin: CGPoint(x: item.viewType.innerInset.left, y: item.viewType.innerInset.top), size: textView.frame.size))
    }
}

enum UserInfoEntry<Context: AccountContextProtocol>: PeerInfoEntry {
    case info(sectionId:Int, peerView: PeerView, editable:Bool, updatingPhotoState:PeerInfoUpdatingPhotoState?, stories: PeerExpiringStoryListContext.State?, savedMuicProfileState: ProfileSavedMusicContext.State?, viewType: GeneralViewType)
    case personalChannelInfo(sectionId:Int, left: String, right: String, viewType: GeneralViewType)
    case personalChannel(sectionId:Int, item: UserInfoPersonalChannel, viewType: GeneralViewType)
    case setFirstName(sectionId:Int, text: String, viewType: GeneralViewType)
    case setLastName(sectionId:Int, text: String, placeholder: String, viewType: GeneralViewType)
    case setNotes(sectionId:Int, note: CachedUserData.Note, placeholder: String, viewType: GeneralViewType)
    case setNotesInfo(sectionId:Int, text: String, viewType: GeneralViewType)
    case about(sectionId:Int, text: String, launchApp: Bool, viewType: GeneralViewType)
    case aboutInfo(sectionId:Int, text: String, viewType: GeneralViewType)
    case botManager(sectionId:Int, peer: EnginePeer, viewType: GeneralViewType)
    case botStarsBalance(sectionId:Int, text: String, viewType: GeneralViewType)
    case botTonBalance(sectionId:Int, text: String, viewType: GeneralViewType)
    case botPermissionsHeader(sectionId:Int, text: String, viewType: GeneralViewType)
    case botPermissionsStatus(sectionId:Int, value: Bool, viewType: GeneralViewType)
    case botPermissionsGeo(sectionId:Int, value: Bool, viewType: GeneralViewType)
    case botEditUsername(sectionId:Int, text: String, viewType: GeneralViewType)
    case botAffiliate(sectionId:Int, text: String, starRefProgram: TelegramStarRefProgram?, viewType: GeneralViewType)
    case verifyAccounts(sectionId:Int, verification: BotVerifierSettings, viewType: GeneralViewType)
    case botEditIntro(sectionId:Int, viewType: GeneralViewType)
    case botEditCommands(sectionId:Int, viewType: GeneralViewType)
    case botEditSettings(sectionId:Int, viewType: GeneralViewType)
    case botEditInfo(sectionId:Int, viewType: GeneralViewType)
    case bio(sectionId:Int, text: String, PeerEquatable, viewType: GeneralViewType)
    case birthday(sectionId:Int, text: String, Bool, viewType: GeneralViewType)
    case scam(sectionId:Int, title: String, text: String, viewType: GeneralViewType)
    case unofficialWarning(sectionId:Int, text: String, viewType: GeneralViewType)
    case phoneNumber(sectionId:Int, index: Int, value: PhoneNumberWithLabel, canCopy: Bool, viewType: GeneralViewType)
    case notes(sectionId:Int, index: Int, value: CachedUserData.Note, viewType: GeneralViewType)
    case peerId(sectionId:Int, value: String, viewType: GeneralViewType)
    case userName(sectionId:Int, value: [UserInfoAddress], viewType: GeneralViewType)
    case verifiedInfo(sectionId: Int, value: PeerVerification, viewType: GeneralViewType)
    case businessLocation(sectionId:Int, peer: EnginePeer, businessLocation: TelegramBusinessLocation, viewType: GeneralViewType)
    case businessHours(sectionId:Int, peer: EnginePeer, businessHours: TelegramBusinessHours, revealed: Bool, displayMyZone: Bool, viewType: GeneralViewType)
    case reportReaction(sectionId: Int, value: MessageId, viewType: GeneralViewType)
    case sendMessage(sectionId:Int, viewType: GeneralViewType)
    case shareContact(sectionId:Int, viewType: GeneralViewType)
    case shareMyInfo(sectionId:Int, viewType: GeneralViewType)
    case addContact(sectionId:Int, viewType: GeneralViewType)
    case botAddToGroup(sectionId: Int, viewType: GeneralViewType)
    case botAddToGroupInfo(sectionId: Int, viewType: GeneralViewType)
    case botAddToCommunity(sectionId: Int, viewType: GeneralViewType)
    case botAddToCommunityInfo(sectionId: Int, viewType: GeneralViewType)
    case botLinkedCommunity(sectionId: Int, peer: Peer, viewType: GeneralViewType)
    case botRemoveFromCommunity(sectionId: Int, communityId: PeerId, viewType: GeneralViewType)
    case botShare(sectionId: Int, name: String, viewType: GeneralViewType)
    case botHelp(sectionId: Int, viewType: GeneralViewType)
    case botSettings(sectionId: Int, viewType: GeneralViewType)
    case botPrivacy(sectionId: Int, viewType: GeneralViewType)
    case startSecretChat(sectionId:Int, viewType: GeneralViewType)
    case sharedMedia(sectionId:Int, viewType: GeneralViewType)
    case notifications(sectionId:Int, settings: PeerNotificationSettings?, viewType: GeneralViewType)
    case groupInCommon(sectionId:Int, count:Int, peerId: PeerId, viewType: GeneralViewType)
    case suggestBirthday(sectionId:Int, string: String, nextType: GeneralInteractedType, viewType: GeneralViewType)
    case setPhoto(sectionId:Int, string: String, type: UserInfoArgumentsSetPhotoType, nextType: GeneralInteractedType, viewType: GeneralViewType)
    case resetPhoto(sectionId:Int, string: String, image: TelegramMediaImage, user: TelegramUser, viewType: GeneralViewType)
    case setPhotoInfo(sectionId:Int, string: String, viewType: GeneralViewType)
    case copyProtection(sectionId: Int, selected: Bool, viewType: GeneralViewType)
    case copyProtectionInfo(sectionId: Int, text: String, viewType: GeneralViewType)
    case block(sectionId:Int, peer: Peer, blocked: Bool, isBot: Bool, viewType: GeneralViewType)
    case deleteChat(sectionId: Int, viewType: GeneralViewType)
    case deleteContact(sectionId: Int, viewType: GeneralViewType)
    case encryptionKey(sectionId: Int, viewType: GeneralViewType)
    case media(sectionId: Int, controller: PeerMediaController<Context>, isVisible: Bool, viewType: GeneralViewType)
    case section(sectionId:Int)
    
    var viewType: GeneralViewType {
        switch self {
        case .info(_, _, _, _, _, _, let viewType):
            return viewType
        case .personalChannelInfo(_, _, _, let viewType):
            return viewType
        case .personalChannel(_, _, let viewType):
            return viewType
        case .setFirstName(_, _, let viewType):
            return viewType
        case .setLastName(_, _, _, let viewType):
            return viewType
        case .setNotes(_, _, _, let viewType):
            return viewType
        case .setNotesInfo(_, _, let viewType):
            return viewType
        case .about(_, _, _, let viewType):
            return viewType
        case .aboutInfo(_, _, let viewType):
            return viewType
        case .botManager(_, _, let viewType):
            return viewType
        case .botStarsBalance(_, _, let viewType):
            return viewType
        case .botTonBalance(_, _, let viewType):
            return viewType
        case .botPermissionsHeader(_, _, let viewType):
            return viewType
        case .botPermissionsStatus(_, _, let viewType):
            return viewType
        case .botPermissionsGeo(_, _, let viewType):
            return viewType
        case .botEditUsername(_, _, let viewType):
            return viewType
        case .botAffiliate(_, _, _, let viewType):
            return viewType
        case .verifyAccounts(_, _, let viewType):
            return viewType
        case .botEditIntro(_, let viewType):
            return viewType
        case .botEditCommands(_, let viewType):
            return viewType
        case .botEditSettings(_, let viewType):
            return viewType
        case .botEditInfo(_, let viewType):
            return viewType
        case .bio(_, _, _, let viewType):
            return viewType
        case .birthday(_, _, _, let viewType):
            return viewType
        case .scam(_, _, _, let viewType):
            return viewType
        case .unofficialWarning(_, _, let viewType):
            return viewType
        case .phoneNumber(_, _, _, _, let viewType):
            return viewType
        case .notes(_, _, _, let viewType):
            return viewType
        case .peerId(_, _, let viewType):
            return viewType
        case .userName(_, _, let viewType):
            return viewType
        case .verifiedInfo(_, _, let viewType):
            return viewType
        case .businessLocation(_, _, _, let viewType):
            return viewType
        case .businessHours(_, _, _, _, _, let viewType):
            return viewType
        case .reportReaction(_,_, let viewType):
            return viewType
        case .sendMessage(_, let viewType):
            return viewType
        case .shareContact(_, let viewType):
            return viewType
        case .shareMyInfo(_, let viewType):
            return viewType
        case .addContact(_, let viewType):
            return viewType
        case .botAddToGroup(_, let viewType):
            return viewType
        case .botAddToGroupInfo(_, let viewType):
            return viewType
        case .botAddToCommunity(_, let viewType):
            return viewType
        case .botAddToCommunityInfo(_, let viewType):
            return viewType
        case .botLinkedCommunity(_, _, let viewType):
            return viewType
        case .botRemoveFromCommunity(_, _, let viewType):
            return viewType
        case .botShare(_, _, let viewType):
            return viewType
        case .botHelp(_, let viewType):
            return viewType
        case .botSettings(_, let viewType):
            return viewType
        case .botPrivacy(_, let viewType):
            return viewType
        case .startSecretChat(_, let viewType):
            return viewType
        case .sharedMedia(_, let viewType):
            return viewType
        case .notifications(_, _, let viewType):
            return viewType
        case .groupInCommon(_, _, _, let viewType):
            return viewType
        case .suggestBirthday(_, _, _, let viewType):
            return viewType
        case .setPhoto(_, _, _, _, let viewType):
            return viewType
        case .resetPhoto(_, _, _, _, let viewType):
            return viewType
        case .setPhotoInfo(_, _, let viewType):
            return viewType
        case .copyProtection(_, _, let viewType):
            return viewType
        case .copyProtectionInfo(_, _, let viewType):
            return viewType
        case .block(_, _, _, _, let viewType):
            return viewType
        case .deleteChat(_, let viewType):
            return viewType
        case .deleteContact(_, let viewType):
            return viewType
        case .encryptionKey(_, let viewType):
            return viewType
        case .media(_, _, _, let viewType):
            return viewType
        case .section(_):
            return .legacy
        }
    }
    
    func withUpdatedViewType(_ viewType: GeneralViewType) -> UserInfoEntry {
        switch self {
        case let .info(sectionId, peerView, editable, updatingPhotoState, stories, savedMusic, _): return .info(sectionId: sectionId, peerView: peerView, editable: editable, updatingPhotoState: updatingPhotoState, stories: stories, savedMuicProfileState: savedMusic, viewType: viewType)
        case let .personalChannelInfo(sectionId, left, right, _): return .personalChannelInfo(sectionId: sectionId, left: left, right: right, viewType: viewType)
        case let .personalChannel(sectionId, item, _): return .personalChannel(sectionId: sectionId, item: item, viewType: viewType)
        case let .setFirstName(sectionId, text, _): return .setFirstName(sectionId: sectionId, text: text, viewType: viewType)
        case let .setLastName(sectionId, text, placeholder, _): return .setLastName(sectionId: sectionId, text: text, placeholder: placeholder, viewType: viewType)
        case let .setNotes(sectionId, note, placeholder, _): return .setNotes(sectionId: sectionId, note: note, placeholder: placeholder, viewType: viewType)
        case let .setNotesInfo(sectionId, text, _): return .setNotesInfo(sectionId: sectionId, text: text, viewType: viewType)
        case let .botStarsBalance(sectionId, text, _): return .botStarsBalance(sectionId: sectionId, text: text, viewType: viewType)
        case let .botTonBalance(sectionId, text, _): return .botTonBalance(sectionId: sectionId, text: text, viewType: viewType)
        case let .botPermissionsHeader(sectionId, text, _): return .botPermissionsHeader(sectionId: sectionId, text: text, viewType: viewType)
        case let .botPermissionsStatus(sectionId, value, _): return .botPermissionsStatus(sectionId: sectionId, value: value, viewType: viewType)
        case let .botPermissionsGeo(sectionId, value, _): return .botPermissionsGeo(sectionId: sectionId, value: value, viewType: viewType)
        case let .botEditUsername(sectionId, text, _): return .botEditUsername(sectionId: sectionId, text: text, viewType: viewType)
        case let .botAffiliate(sectionId, text, starRefProgram, _): return .botAffiliate(sectionId: sectionId, text: text, starRefProgram: starRefProgram, viewType: viewType)
        case let .verifyAccounts(sectionId, verification, _): return .verifyAccounts(sectionId: sectionId, verification: verification, viewType: viewType)
        case let .botEditIntro(sectionId, _): return .botEditIntro(sectionId: sectionId, viewType: viewType)
        case let .botEditCommands(sectionId, _): return .botEditCommands(sectionId: sectionId, viewType: viewType)
        case let .botEditSettings(sectionId, _): return .botEditSettings(sectionId: sectionId, viewType: viewType)
        case let .botEditInfo(sectionId, _): return .botEditInfo(sectionId: sectionId, viewType: viewType)
        case let .about(sectionId, text, launchApp, _): return .about(sectionId: sectionId, text: text, launchApp: launchApp, viewType: viewType)
        case let .aboutInfo(sectionId, text, _): return .aboutInfo(sectionId: sectionId, text: text, viewType: viewType)
        case let .botManager(sectionId, peer, _): return .botManager(sectionId: sectionId, peer: peer, viewType: viewType)
        case let .bio(sectionId, text, peer, _): return .bio(sectionId: sectionId, text: text, peer, viewType: viewType)
        case let .birthday(sectionId, text, peer, _): return .birthday(sectionId: sectionId, text: text, peer, viewType: viewType)
        case let .scam(sectionId, title, text, _): return .scam(sectionId: sectionId, title: title, text: text, viewType: viewType)
        case let .unofficialWarning(sectionId, text, _): return .unofficialWarning(sectionId: sectionId, text: text, viewType: viewType)
        case let .phoneNumber(sectionId, index, value, canCopy, _): return .phoneNumber(sectionId: sectionId, index: index, value: value, canCopy: canCopy, viewType: viewType)
        case let .notes(sectionId, index, value, _): return .notes(sectionId: sectionId, index: index, value: value, viewType: viewType)
        case let .userName(sectionId, value, _): return .userName(sectionId: sectionId, value: value, viewType: viewType)
        case let .verifiedInfo(sectionId, value, _): return .verifiedInfo(sectionId: sectionId, value: value, viewType: viewType)
        case let .peerId(sectionId, value, _): return .peerId(sectionId: sectionId, value: value, viewType: viewType)
        case let .businessLocation(sectionId, peer, location, _): return .businessLocation(sectionId: sectionId, peer: peer, businessLocation: location, viewType: viewType)
        case let .businessHours(sectionId, peer, businessHours, revealed, displayMyZone, _): return .businessHours(sectionId: sectionId, peer: peer, businessHours: businessHours, revealed: revealed, displayMyZone: displayMyZone, viewType: viewType)
        case let .reportReaction(sectionId, value, _): return .reportReaction(sectionId: sectionId, value: value, viewType: viewType)
        case let .sendMessage(sectionId, _): return .sendMessage(sectionId: sectionId, viewType: viewType)
        case let .shareContact(sectionId, _): return .shareContact(sectionId: sectionId, viewType: viewType)
        case let .shareMyInfo(sectionId, _): return .shareMyInfo(sectionId: sectionId, viewType: viewType)
        case let .addContact(sectionId, _): return .addContact(sectionId: sectionId, viewType: viewType)
        case let .botAddToGroup(sectionId, _): return .botAddToGroup(sectionId: sectionId, viewType: viewType)
        case let .botAddToGroupInfo(sectionId, _): return .botAddToGroupInfo(sectionId: sectionId, viewType: viewType)
        case let .botAddToCommunity(sectionId, _): return .botAddToCommunity(sectionId: sectionId, viewType: viewType)
        case let .botAddToCommunityInfo(sectionId, _): return .botAddToCommunityInfo(sectionId: sectionId, viewType: viewType)
        case let .botLinkedCommunity(sectionId, peer, _): return .botLinkedCommunity(sectionId: sectionId, peer: peer, viewType: viewType)
        case let .botRemoveFromCommunity(sectionId, communityId, _): return .botRemoveFromCommunity(sectionId: sectionId, communityId: communityId, viewType: viewType)
        case let .botShare(sectionId, name, _): return .botShare(sectionId: sectionId, name: name, viewType: viewType)
        case let .botHelp(sectionId, _): return .botHelp(sectionId: sectionId, viewType: viewType)
        case let .botSettings(sectionId, _): return .botSettings(sectionId: sectionId, viewType: viewType)
        case let .botPrivacy(sectionId, _): return .botPrivacy(sectionId: sectionId, viewType: viewType)
        case let .startSecretChat(sectionId, _): return .startSecretChat(sectionId: sectionId, viewType: viewType)
        case let .sharedMedia(sectionId, _): return .sharedMedia(sectionId: sectionId, viewType: viewType)
        case let .notifications(sectionId, settings, _): return .notifications(sectionId: sectionId, settings: settings, viewType: viewType)
        case let .groupInCommon(sectionId, count, peerId, _): return .groupInCommon(sectionId: sectionId, count: count, peerId: peerId, viewType: viewType)
        case let .suggestBirthday(sectionId, string, nextType, _): return .suggestBirthday(sectionId: sectionId, string: string, nextType: nextType, viewType: viewType)
        case let .setPhoto(sectionId, string, type, nextType, _): return .setPhoto(sectionId: sectionId, string: string, type: type, nextType: nextType, viewType: viewType)
        case let .resetPhoto(sectionId, string, image, user, _): return .resetPhoto(sectionId: sectionId, string: string, image: image, user: user, viewType: viewType)
        case let .setPhotoInfo(sectionId, string, viewType): return .setPhotoInfo(sectionId: sectionId, string: string, viewType: viewType)
        case let .copyProtection(sectionId, selected, _): return .copyProtection(sectionId: sectionId, selected: selected, viewType: viewType)
        case let .copyProtectionInfo(sectionId, text, _): return .copyProtectionInfo(sectionId: sectionId, text: text, viewType: viewType)
        case let .block(sectionId, peer, blocked, isBot, _): return .block(sectionId: sectionId, peer: peer, blocked: blocked, isBot: isBot, viewType: viewType)
        case let .deleteChat(sectionId, _): return .deleteChat(sectionId: sectionId, viewType: viewType)
        case let .deleteContact(sectionId, _): return .deleteContact(sectionId: sectionId, viewType: viewType)
        case let .encryptionKey(sectionId, _): return .encryptionKey(sectionId: sectionId, viewType: viewType)
        case let .media(sectionId, controller, isVisible, _): return .media(sectionId: sectionId, controller: controller, isVisible: isVisible, viewType: viewType)
        case .section: return self
        }
    }
    
    var stableId: PeerInfoEntryStableId {
        return IntPeerInfoEntryStableId(value: self.stableIndex)
    }
    
    func isEqual(to: PeerInfoEntry) -> Bool {
        guard let entry = to as? UserInfoEntry else {
            return false
        }
        
        switch self {
        case let .info(lhsSectionId, lhsPeerView, lhsEditable, lhsUpdatingPhotoState, lhsStories, lhsSavedMusic, lhsViewType):
            switch entry {
            case let .info(rhsSectionId, rhsPeerView, rhsEditable, rhsUpdatingPhotoState, rhsStories, rhsSavedMusic, rhsViewType):
                
                if lhsSectionId != rhsSectionId {
                    return false
                }
                if lhsViewType != rhsViewType {
                    return false
                }
                if lhsUpdatingPhotoState != rhsUpdatingPhotoState {
                    return false
                }
                if lhsEditable != rhsEditable {
                    return false
                }
                if lhsStories != rhsStories {
                    return false
                }
                if lhsSavedMusic != rhsSavedMusic {
                    return false
                }
                let lhsPeer = peerViewMainPeer(lhsPeerView)
                let lhsCachedData = lhsPeerView.cachedData
                let lhsNotificationSettings = lhsPeerView.notificationSettings

                let rhsPeer = peerViewMainPeer(rhsPeerView)
                let rhsCachedData = rhsPeerView.cachedData
                let rhsNotificationSettings = rhsPeerView.notificationSettings
                if let lhsPeer = lhsPeer, let rhsPeer = rhsPeer {
                    if !lhsPeer.isEqual(rhsPeer) {
                        return false
                    }
                } else if (lhsPeer != nil) != (rhsPeer != nil) {
                    return false
                }
                
                if let lhsNotificationSettings = lhsNotificationSettings, let rhsNotificationSettings = rhsNotificationSettings {
                    if !lhsNotificationSettings.isEqual(to: rhsNotificationSettings) {
                        return false
                    }
                } else if (lhsNotificationSettings != nil) != (rhsNotificationSettings != nil) {
                    return false
                }
                
                if let lhsCachedData = lhsCachedData, let rhsCachedData = rhsCachedData {
                    if !lhsCachedData.isEqual(to: rhsCachedData) {
                        return false
                    }
                } else if (lhsCachedData != nil) != (rhsCachedData != nil) {
                    return false
                }
                return true
            default:
                return false
            }
        case let .personalChannelInfo(sectionId, left, right, viewType):
            if case .personalChannelInfo(sectionId, left, right, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .personalChannel(sectionId, item, viewType):
            if case .personalChannel(sectionId, item, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .setFirstName(sectionId, text, viewType):
            switch entry {
            case .setFirstName(sectionId, text, viewType):
                return true
            default:
                return false
            }
        case let .setLastName(sectionId, text, placeholder, viewType):
            switch entry {
            case .setLastName(sectionId, text, placeholder, viewType):
                return true
            default:
                return false
            }
        case let .setNotes(sectionId, text, placeholder, viewType):
            switch entry {
            case .setNotes(sectionId, text, placeholder, viewType):
                return true
            default:
                return false
            }
        case let .setNotesInfo(sectionId, text, viewType):
            switch entry {
            case .setNotesInfo(sectionId, text, viewType):
                return true
            default:
                return false
            }
        case let .botStarsBalance(sectionId, text, viewType):
            switch entry {
            case .botStarsBalance(sectionId, text, viewType):
                return true
            default:
                return false
            }
        case let .botTonBalance(sectionId, text, viewType):
            switch entry {
            case .botTonBalance(sectionId, text, viewType):
                return true
            default:
                return false
            }
        case let .botPermissionsHeader(sectionId, text, viewType):
            switch entry {
            case .botPermissionsHeader(sectionId, text, viewType):
                return true
            default:
                return false
            }
        case let .botPermissionsStatus(sectionId, value, viewType):
            switch entry {
            case .botPermissionsStatus(sectionId, value, viewType):
                return true
            default:
                return false
            }
        case let .botPermissionsGeo(sectionId, value, viewType):
            switch entry {
            case .botPermissionsGeo(sectionId, value, viewType):
                return true
            default:
                return false
            }
        case let .botEditUsername(sectionId, text, viewType):
            switch entry {
            case .botEditUsername(sectionId, text, viewType):
                return true
            default:
                return false
            }
        case let .botAffiliate(sectionId, text, starRefProgram, viewType):
            switch entry {
            case .botAffiliate(sectionId, text, starRefProgram, viewType):
                return true
            default:
                return false
            }
        case let .verifyAccounts(sectionId, text, viewType):
            switch entry {
            case .verifyAccounts(sectionId, text, viewType):
                return true
            default:
                return false
            }
        case let .botEditIntro(sectionId, viewType):
            switch entry {
            case .botEditIntro(sectionId, viewType):
                return true
            default:
                return false
            }
        case let .botEditCommands(sectionId, viewType):
            switch entry {
            case .botEditCommands(sectionId, viewType):
                return true
            default:
                return false
            }
        case let .botEditSettings(sectionId, viewType):
            switch entry {
            case .botEditSettings(sectionId, viewType):
                return true
            default:
                return false
            }
        case let .botEditInfo(sectionId, viewType):
            switch entry {
            case .botEditInfo(sectionId, viewType):
                return true
            default:
                return false
            }
        case let .about(sectionId, text, launchLink, viewType):
            switch entry {
            case .about(sectionId, text, launchLink, viewType):
                return true
            default:
                return false
            }
        case let .aboutInfo(sectionId, text, viewType):
            switch entry {
            case .aboutInfo(sectionId, text, viewType):
                return true
            default:
                return false
            }
        case let .botManager(sectionId, peer, viewType):
            switch entry {
            case .botManager(sectionId, peer, viewType):
                return true
            default:
                return false
            }
        case let .bio(sectionId, text, peer, viewType):
            switch entry {
            case .bio(sectionId, text, peer, viewType):
                return true
            default:
                return false
            }
        case let .birthday(sectionId, text, peer, viewType):
            switch entry {
            case .birthday(sectionId, text, peer, viewType):
                return true
            default:
                return false
            }
        case let .scam(sectionId, title, text, viewType):
            switch entry {
            case .scam(sectionId, title, text, viewType):
                return true
            default:
                return false
            }
        case let .unofficialWarning(sectionId, text, viewType):
            switch entry {
            case .unofficialWarning(sectionId, text, viewType):
                return true
            default:
                return false
            }
        case let .phoneNumber(sectionid, index, value, canCopy, viewType):
            switch entry {
            case .phoneNumber(sectionid, index, value, canCopy, viewType):
                return true
            default:
                return false
            }
        case let .notes(sectionid, index, value, viewType):
            switch entry {
            case .notes(sectionid, index, value, viewType):
                return true
            default:
                return false
            }
        case let .userName(sectionId, value, viewType):
            switch entry {
            case .userName(sectionId, value, viewType):
                return true
            default:
                return false
            }
        case let .verifiedInfo(sectionId, value, viewType):
            switch entry {
            case .verifiedInfo(sectionId, value, viewType):
                return true
            default:
                return false
            }
        case let .peerId(sectionId, value, viewType):
            switch entry {
            case .peerId(sectionId, value, viewType):
                return true
            default:
                return false
            }
        case let .businessLocation(sectionId, peer, location, viewType):
            switch entry {
            case .businessLocation(sectionId, peer: peer, businessLocation: location, viewType):
                return true
            default:
                return false
            }
        case let .businessHours(sectionId, peer, businessHours, revealed, displayMyZone, viewType):
            switch entry {
            case .businessHours(sectionId, peer, businessHours, revealed, displayMyZone, viewType):
                return true
            default:
                return false
            }
        case let .reportReaction(sectionId, value, viewType):
            switch entry {
            case .reportReaction(sectionId, value, viewType):
                return true
            default:
                return false
            }
        case let .sendMessage(sectionId, viewType):
            switch entry {
            case .sendMessage(sectionId, viewType):
                return true
            default:
                return false
            }
        case let .botAddToGroup(sectionId, viewType):
            switch entry {
            case .botAddToGroup(sectionId, viewType):
                return true
            default:
                return false
            }
        case let .botAddToGroupInfo(sectionId, viewType):
            switch entry {
            case .botAddToGroupInfo(sectionId, viewType):
                return true
            default:
                return false
            }
        case let .botAddToCommunity(sectionId, viewType):
            switch entry {
            case .botAddToCommunity(sectionId, viewType):
                return true
            default:
                return false
            }
        case let .botAddToCommunityInfo(sectionId, viewType):
            switch entry {
            case .botAddToCommunityInfo(sectionId, viewType):
                return true
            default:
                return false
            }
        case let .botLinkedCommunity(sectionId, lhsPeer, viewType):
            switch entry {
            case .botLinkedCommunity(sectionId, let rhsPeer, viewType):
                return lhsPeer.isEqual(rhsPeer)
            default:
                return false
            }
        case let .botRemoveFromCommunity(sectionId, communityId, viewType):
            switch entry {
            case .botRemoveFromCommunity(sectionId, communityId, viewType):
                return true
            default:
                return false
            }
        case let .botShare(sectionId, botName, viewType):
            switch entry {
            case .botShare(sectionId, botName, viewType):
                return true
            default:
                return false
            }
        case let .botHelp(sectionId, viewType):
            switch entry {
            case .botHelp(sectionId, viewType):
                return true
            default:
                return false
            }
        case let .botSettings(sectionId, viewType):
            switch entry {
            case .botSettings(sectionId, viewType):
                return true
            default:
                return false
            }
        case let .botPrivacy(sectionId, viewType):
            if case .botPrivacy(sectionId, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .shareContact(sectionId, viewType):
            switch entry {
            case .shareContact(sectionId, viewType):
                return true
            default:
                return false
            }
        case let .shareMyInfo(sectionId, viewType):
            switch entry {
            case .shareMyInfo(sectionId, viewType):
                return true
            default:
                return false
            }
        case let .addContact(sectionId, viewType):
            switch entry {
            case .addContact(sectionId, viewType):
                return true
            default:
                return false
            }
        case let .startSecretChat(sectionId, viewType):
            switch entry {
            case .startSecretChat(sectionId, viewType):
                return true
            default:
                return false
            }
        case let .sharedMedia(sectionId, viewType):
            switch entry {
            case .sharedMedia(sectionId, viewType):
                return true
            default:
                return false
            }
        case let .notifications(sectionId, lhsSettings, viewType):
            switch entry {
            case  .notifications(sectionId, let rhsSettings, viewType):
                if let lhsSettings = lhsSettings, let rhsSettings = rhsSettings {
                    return lhsSettings.isEqual(to: rhsSettings)
                } else if (lhsSettings != nil) != (rhsSettings != nil) {
                    return false
                } else {
                    return true
                }
            default:
                return false
            }
        case let .suggestBirthday(sectionId, string, nextType, viewType):
            switch entry {
            case .suggestBirthday(sectionId, string, nextType, viewType):
                return true
            default:
                return false
            }
        case let .setPhoto(sectionId, string, type, nextType, viewType):
            switch entry {
            case .setPhoto(sectionId, string, type, nextType, viewType):
                return true
            default:
                return false
            }
        case let .resetPhoto(sectionId, string, image, user, viewType):
            switch entry {
            case .resetPhoto(sectionId, string, image, user, viewType):
                return true
            default:
                return false
            }
        case let .setPhotoInfo(sectionId, string, viewType):
            switch entry {
            case .setPhotoInfo(sectionId, string, viewType):
                return true
            default:
                return false
            }
        case let .copyProtection(sectionId, selected, viewType):
            switch entry {
            case .copyProtection(sectionId, selected, viewType):
                return true
            default:
                return false
            }
        case let .copyProtectionInfo(sectionId, text, viewType):
            switch entry {
            case .copyProtectionInfo(sectionId, text, viewType):
                return true
            default:
                return false
            }
        case let .block(sectionId, lhsPeer, isBlocked, isBot, viewType):
            switch entry {
            case .block(sectionId, let rhsPeer, isBlocked, isBot, viewType):
                return lhsPeer.isEqual(rhsPeer)
            default:
                return false
            }
        case let .groupInCommon(sectionId, count, peerId, viewType):
            switch entry {
            case .groupInCommon(sectionId, count, peerId, viewType):
                return true
            default:
                return false
            }
        case let .deleteChat(sectionId, viewType):
            switch entry {
            case .deleteChat(sectionId, viewType):
                return true
            default:
                return false
            }
        case let .deleteContact(sectionId, viewType):
            switch entry {
            case .deleteContact(sectionId, viewType):
                return true
            default:
                return false
            }
        case let .encryptionKey(sectionId, viewType):
            switch entry {
            case .encryptionKey(sectionId, viewType):
                return true
            default:
                return false
            }
        case let .media(sectionId, _, isVisible, viewType):
            switch entry {
            case .media(sectionId, _, isVisible, viewType):
                return true
            default:
                return false
            }
        case let .section(lhsId):
            switch entry {
            case let .section(rhsId):
                return lhsId == rhsId
            default:
                return false
            }
        }
    }
    
    private var stableIndex: Int {
        switch self {
        case .info:
            return 100
        case .personalChannelInfo:
            return 101
        case .personalChannel:
            return 102
        case .setFirstName:
            return 103
        case .setLastName:
            return 104
        case .setNotes:
            return 105
        case .setNotesInfo:
            return 106
        case .botEditUsername:
            return 107
        case .botAffiliate:
            return 108
        case .verifyAccounts:
            return 109
        case .botStarsBalance:
            return 110
        case .botTonBalance:
            return 111
        case .botPermissionsHeader:
            return 112
        case .botPermissionsStatus:
            return 113
        case .botPermissionsGeo:
            return 114
        case .botEditIntro:
            return 115
        case .botEditCommands:
            return 116
        case .botEditSettings:
            return 117
        case .botEditInfo:
            return 118
        case .userName:
            return 119
        case .unofficialWarning:
            return 99
        case .scam:
            return 120
        case .about:
            return 121
        case .aboutInfo:
            return 122
        case .botManager:
            return 160
        case .bio:
            return 123
        case .phoneNumber:
            return 124
        case .birthday:
            return 125
        case .peerId:
            return 126
        case .notes:
            return 127
        case .businessHours:
            return 128
        case .businessLocation:
            return 129
        case .sendMessage:
            return 130
        case .botAddToGroup:
            return 131
        case .botAddToGroupInfo:
            return 132
        case .botAddToCommunity:
            return 161
        case .botAddToCommunityInfo:
            return 162
        case .botLinkedCommunity:
            return 163
        case .botRemoveFromCommunity:
            return 164
        case .botShare:
            return 133
        case .botSettings:
            return 134
        case .botHelp:
            return 135
        case .botPrivacy:
            return 136
        case .shareContact:
            return 137
        case .shareMyInfo:
            return 138
        case .addContact:
            return 139
        case .startSecretChat:
            return 140
        case .sharedMedia:
            return 141
        case .notifications:
            return 142
        case .encryptionKey:
            return 143
        case .groupInCommon:
            return 144
        case .suggestBirthday:
            return 145
        case let .setPhoto(_, _, type, _, _):
            return 146 + type.rawValue
        case .resetPhoto:
            return 150
        case .setPhotoInfo:
            return 151
        case .copyProtection:
            return 152
        case .copyProtectionInfo:
            return 153
        case .block:
            return 154
        case .reportReaction:
            return 155
        case .deleteChat:
            return 156
        case .deleteContact:
            return 157
        case .verifiedInfo:
            return 158
        case .media:
            return 159
        case let .section(id):
            return (id + 1) * 1000 - id
        }
    }
    
    private var sortIndex:Int {
        switch self {
        case let .info(sectionId, _, _, _, _, _, _):
            return (sectionId * 1000) + stableIndex
        case let .personalChannelInfo(sectionId, _, _, _):
            return (sectionId * 1000) + stableIndex
        case let .personalChannel(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .setFirstName(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .setLastName(sectionId, _, _, _):
            return (sectionId * 1000) + stableIndex
        case let .setNotes(sectionId, _, _, _):
            return (sectionId * 1000) + stableIndex
        case let .setNotesInfo(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .botEditUsername(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .botAffiliate(sectionId, _, _, _):
            return (sectionId * 1000) + stableIndex
        case let .verifyAccounts(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .botStarsBalance(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .botTonBalance(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .botPermissionsHeader(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .botPermissionsStatus(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .botPermissionsGeo(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .botEditIntro(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .botEditCommands(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .botEditSettings(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .botEditInfo(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .about(sectionId, _, _, _):
            return (sectionId * 1000) + stableIndex
        case let .aboutInfo(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .botManager(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .bio(sectionId, _, _, _):
            return (sectionId * 1000) + stableIndex
        case let .birthday(sectionId, _, _, _):
            return (sectionId * 1000) + stableIndex
        case let .phoneNumber(sectionId, _, _, _, _):
            return (sectionId * 1000) + stableIndex
        case let .notes(sectionId, _, _, _):
            return (sectionId * 1000) + stableIndex
        case let .userName(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .verifiedInfo(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .peerId(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .businessHours(sectionId, _, _, _, _, _):
            return (sectionId * 1000) + stableIndex
        case let .businessLocation(sectionId, _, _, _):
            return (sectionId * 1000) + stableIndex
        case let .reportReaction(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .scam(sectionId, _, _, _):
            return (sectionId * 1000) + stableIndex
        case let .unofficialWarning(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .sendMessage(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .botAddToGroup(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .botAddToGroupInfo(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .botAddToCommunity(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .botAddToCommunityInfo(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .botLinkedCommunity(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .botRemoveFromCommunity(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .botShare(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .botSettings(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .botPrivacy(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .botHelp(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .shareContact(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .shareMyInfo(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .addContact(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .startSecretChat(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .sharedMedia(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .groupInCommon(sectionId, _, _, _):
            return (sectionId * 1000) + stableIndex
        case let .notifications(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .encryptionKey(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .suggestBirthday(sectionId, _, _, _):
            return (sectionId * 1000) + stableIndex
        case let .setPhoto(sectionId, _, _, _, _):
            return (sectionId * 1000) + stableIndex
        case let .resetPhoto(sectionId, _, _, _, _):
            return (sectionId * 1000) + stableIndex
        case let .setPhotoInfo(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .copyProtection(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .copyProtectionInfo(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .block(sectionId, _, _, _, _):
            return (sectionId * 1000) + stableIndex
        case let .deleteChat(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .deleteContact(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .media(sectionId, _, _, _):
            return (sectionId * 1000) + stableIndex
        case let .section(id):
            return (id + 1) * 1000 - id
        }
        
    }
    
    func isOrderedBefore(_ entry: PeerInfoEntry) -> Bool {
        guard let other = entry as? UserInfoEntry else {
            return false
        }
        
        return self.sortIndex < other.sortIndex
    }
    
    
    
    func item<C: AccountContextProtocol>( initialSize:NSSize, arguments:PeerInfoArguments<C>) -> TableRowItem {
        
        let arguments = arguments as! UserInfoArguments<Context>
        var state:UserInfoState {
            return arguments.state as! UserInfoState
        }
        
        switch self {
        case let .info(_, peerView, editable, updatingPhotoState, stories, savedMusic, viewType):
            return PeerInfoHeadItem(initialSize, stableId:stableId.hashValue, context: arguments.context, arguments: arguments, peerView: peerView, threadData: nil, threadId: nil, stories: stories, viewType: viewType, editing: editable, updatingPhotoState: updatingPhotoState, updatePhoto: { image, control in
                arguments.updateContactPhoto(image, control: control, type: .set)
            }, giftsContext: arguments.getStarGiftsContext?(), savedMusic: savedMusic, profileSavedMusic: arguments.getSavedMusicContext?())
        case let .personalChannelInfo(_, left, right, viewType):
            return GeneralTextRowItem(initialSize, text: left, viewType: viewType, rightItem: .init(isLoading: false, text: .initialize(string: right, color: theme.colors.listGrayText, font: .normal(.small))))
        case let .personalChannel(_, item, viewType):
            return PersonalChannelRowItem(initialSize, stableId: stableId.hashValue, context: arguments.context, item: item, viewType: viewType, action: {
                arguments.openPersonalChannel(item)
            })
        case let .setFirstName(_, text, viewType):
            return InputDataRowItem(initialSize, stableId: stableId.hashValue, mode: .plain, error: nil, viewType: viewType, currentText: text, placeholder: nil, inputPlaceholder: strings().peerInfoFirstNamePlaceholder, filter: { $0 }, updated: {
                arguments.updateEditingNames(firstName: $0, lastName: state.editingState?.editingLastName, notes: state.editingState?.editingNotes)
            }, limit: 255)
        case let .setLastName(_, text, placeholder, viewType):
            return InputDataRowItem(initialSize, stableId: stableId.hashValue, mode: .plain, error: nil, viewType: viewType, currentText: text, placeholder: nil, inputPlaceholder: placeholder, filter: { $0 }, updated: {
                arguments.updateEditingNames(firstName: state.editingState?.editingFirstName, lastName: $0, notes: state.editingState?.editingNotes)
            }, limit: 255)
        case let .setNotes(_, note, placeholder, viewType):
            
            let attrs = chatTextAttributes(from: TextEntitiesMessageAttribute(entities: note.entities), associatedMedia: [:])
            let inputState = ChatTextInputState(inputText: note.text, selectionRange: note.text.length ..< note.text.length, attributes: attrs)
            
            return InputTextDataRowItem(initialSize, stableId: stableIndex, context: arguments.context, state: inputState.textInputState(), viewType: viewType, placeholder: nil, inputPlaceholder: placeholder, canMakeTransformations: true, filter: { $0 }, updateState: { updated in
                let textState = updated.textInputState()
                let text = textState.inputText
                let entities = textState.messageTextEntities()
                arguments.updateEditingNames(firstName: state.editingState?.editingFirstName, lastName: state.editingState?.editingLastName, notes: .init(text: text, entities: entities))
            }, limit: 128, hasEmoji: true)
        case let .setNotesInfo(_, text, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId.hashValue, text: .markdown(text, linkHandler: { _ in
               
            }), viewType: viewType, context: arguments.context)
        case let .botEditUsername(_, text, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoBotEditUsername, icon: theme.icons.peerInfoBotUsername, type: .nextContext("@\(text)"), viewType: viewType, action: arguments.openEditBotUsername)
        case let .botAffiliate(_, text, starRefProgram, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoBotAffiliate, icon: TelegramThemeHooks.shared.image(.iconBotAffiliate).precomposed(flipVertical: true), type: .nextContext(text), viewType: viewType, action: {
                arguments.openAffiliate(starRefProgram: starRefProgram)
            })
        case let .verifyAccounts(_, verification, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoVerifyAccounts, icon: TelegramThemeHooks.shared.image(.iconPeerInfoVerifyAccounts).precomposed(theme.colors.accent, flipVertical: true), type: .nextContext(""), viewType: viewType, action: {
                arguments.openVerifyAccounts(verification)
            })
        case let .botStarsBalance(_, text, viewType):
            let icon = generateStarBalanceIcon(text)
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoBotEditStarsBalanceNew, icon: theme.icons.peerInfoStarsBalance, type: .nextImage(icon), viewType: viewType, action: arguments.openStarsBalance)
        case let .botTonBalance(_, text, viewType):
            let icon = generateTonBalanceIcon(text)
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoBotEditTonBalance, icon: theme.icons.peerInfoTonBalance, type: .nextImage(icon), viewType: viewType, action: arguments.openTonBalance)
        case let .botPermissionsHeader(_, text, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId.hashValue, text: .plain(text), viewType: viewType)
        case let .botPermissionsStatus(_, value, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoBotPermissionsStatus, icon: TelegramThemeHooks.shared.image(.iconPeerInfoBotStatus).precomposed(flipVertical: true), type: .switchable(value), viewType: viewType, action: {
                arguments.togglePermissionsStatus()
            }, autoswitch: false)
        case let .botPermissionsGeo(_, value, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoBotPermissionsGeo, icon: TelegramThemeHooks.shared.image(.iconPeerInfoBotLocation).precomposed(flipVertical: true), type: .switchable(value), viewType: viewType, action: {
                arguments.togglePermissionsGeo()
            })
        case let .botEditIntro(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoBotEditIntro, icon: TelegramThemeHooks.shared.image(.iconPeerInfoBotIntro).precomposed(theme.colors.accent, flipVertical: true), nameStyle: blueActionButton, viewType: viewType, action: {
                arguments.editBot("intro")
            })
        case let .botEditCommands(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoBotEditCommands, icon: TelegramThemeHooks.shared.image(.iconPeerInfoBotCommands).precomposed(theme.colors.accent, flipVertical: true), nameStyle: blueActionButton, viewType: viewType, action: {
                arguments.editBot("commands")
            })
        case let .botEditSettings(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoBotEditSettings, icon: TelegramThemeHooks.shared.image(.iconPeerInfoBotSettings).precomposed(theme.colors.accent, flipVertical: true), nameStyle: blueActionButton, viewType: viewType, action: {
                arguments.editBot(nil)
            })
        case let .botEditInfo(_, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId.hashValue, text: .markdown(strings().peerInfoBotEditInfo, linkHandler: { _ in
                arguments.openBotfather()
            }), viewType: viewType)
        case let .about(_, text, launchApp, viewType):
            if text.isEmpty {
                return GeneralActionButtonRowItem.init(initialSize, stableId: stableId.hashValue, text: strings().botInfoOpenApp, viewType: viewType, action: arguments.openApp)
            } else {
                return  TextAndLabelItem(initialSize, stableId:stableId.hashValue, label: strings().peerInfoAbout, copyMenuText: strings().textCopyLabelAbout, text:text, context: arguments.context, viewType: viewType, detectLinks: true, openInfo: { peerId, toChat, postId, _ in
                    if toChat {
                        arguments.peerChat(peerId, postId: postId)
                    } else {
                        arguments.peerInfo(peerId)
                    }
                }, hashtag: { hashtag in
                    arguments.context.bindings.globalSearch(hashtag, arguments.peerId, nil)
                }, launchApp: launchApp ? arguments.openApp : nil, canTranslate: true)
            }
        case let .aboutInfo(_, text, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId.hashValue, text: .markdown(text, linkHandler: { link in
                LinkHooks.shared.openExternalLink(link, false)
            }), viewType: viewType)
        case let .botManager(_, peer, viewType):
            let managerName = "@\(peer.addressName ?? peer._asPeer().displayTitle)"
            let attr = NSMutableAttributedString()
            _ = attr.append(string: "</> ", color: theme.colors.grayText, font: .normal(.text))
            _ = attr.append(string: strings().userInfoManagedBotCreatedBy, color: theme.colors.grayText, font: .normal(.text))
            let linkRange = attr.append(string: managerName, color: theme.colors.accent, font: .normal(.text))
            attr.add(link: ChatHistoryLink.peerInfo(link: "", peerId: peer.id, action: nil, openChat: false, postId: nil, callback: { peerId, toChat, postId, action in
                arguments.peerInfo(peerId)
            }), for: linkRange)
            return GeneralTextRowItem(initialSize, stableId: stableId.hashValue, text: .attributed(attr), viewType: viewType)
        case let .bio(_, text, peer, viewType):
            return TextAndLabelItem(initialSize, stableId:stableId.hashValue, label: strings().peerInfoBio, copyMenuText: strings().textCopyLabelBio, text:text, context: arguments.context, viewType: viewType, detectLinks: true, onlyInApp: !peer.peer.isPremium, openInfo: { peerId, toChat, postId, _ in
                if toChat {
                    arguments.peerChat(peerId, postId: postId)
                } else {
                    arguments.peerInfo(peerId)
                }
            }, hashtag: { value in
                arguments.context.bindings.globalSearch(value, nil, nil)
            }, canTranslate: true)
        case let .verifiedInfo(_, value, viewType):
            let prefix = "\(clown) "
            let prefixLength = prefix.utf16.count
            var descriptionEntities = value.descriptionEntities
            for entity in generateTextEntities(value.description, enabledTypes: [.url]) {
                let hasOverlappingLink = descriptionEntities.contains(where: { current in
                    switch current.type {
                    case .Url, .TextUrl, .Email:
                        return current.range.overlaps(entity.range)
                    default:
                        return false
                    }
                })
                if !hasOverlappingLink {
                    descriptionEntities.append(entity)
                }
            }
            let entities = [MessageTextEntity(range: 0..<2, type: .CustomEmoji(stickerPack: nil, fileId: value.iconFileId))] + descriptionEntities.map {
                MessageTextEntity(range: ($0.range.lowerBound + prefixLength) ..< ($0.range.upperBound + prefixLength), type: $0.type)
            }
            let attr = ChatMessageItem.applyMessageEntities(with: [TextEntitiesMessageAttribute(entities: entities)], for: prefix + value.description, message: nil, context: arguments.context, fontSize: FontSize.text, openInfo: { peerId, _, _, _ in
                arguments.peerInfo(peerId)
            }, textColor: theme.colors.listGrayText, linkColor: theme.colors.listGrayText, underlineLinks: true, isDark: theme.colors.isDark, bubbled: false).mutableCopy() as! NSMutableAttributedString
            InlineStickerItem.apply(to: attr, associatedMedia: [:], entities: entities, isPremium: true)

            return GeneralTextRowItem(initialSize, stableId: stableId.hashValue, text: .attributed(attr), viewType: viewType, context: arguments.context)
        case let .birthday(_, text, canBirth, viewType):
            return  TextAndLabelItem(initialSize, stableId:stableId.hashValue, label: strings().peerInfoBirthday, copyMenuText: strings().contextCopy, text:text, context: arguments.context, viewType: viewType, gift: canBirth ? arguments.giftBirthday : nil)
        case let .phoneNumber(_, _, value, canCopy, viewType):
            var items:[ContextMenuItem] = []
            if value.number.hasPrefix("888") {
                if canCopy {
                    items.append(ContextSeparatorItem())
                }
                items.append(ContextMenuItem(strings().peerInfoPhoneAnonymousInfo, handler: {
                    LinkHooks.shared.openExternalLink("https://fragment.com", false)
                }, itemImage: MenuAnimation.menu_show_info.value, removeTail: false, overrideWidth: 200))
            }
            return TextAndLabelItem(initialSize, stableId: stableId.hashValue, label:value.label, copyMenuText: strings().textCopyLabelPhoneNumber, text: PeerInfoUIHooks.shared.formatPhoneNumber(arguments.context, value.number), context: arguments.context, viewType: viewType, canCopy: canCopy, _copyToClipboard: {
                
                if value.number.hasPrefix("888") {
                    arguments.openFragment(.phoneNumber(value.number))
                } else {
                    arguments.copy("+\(value.number)")
                }
            }, contextItems: items)
        case let .notes(_, _, value, viewType):
            return TextAndLabelItem(
                initialSize,
                stableId: stableId.hashValue,
                label: strings().peerInfoNotesLabel,
                copyMenuText: strings().peerInfoNotesCopy,
                text: value.text,
                context: arguments.context,
                viewType: viewType,
                openInfo: { peerId, toChat, postId, _ in
                    if toChat {
                        arguments.peerChat(peerId, postId: postId)
                    } else {
                        arguments.peerInfo(peerId)
                    }
                },
                description: strings().peerInfoNotesDescription,
                entities: value.entities
            )
        case let .userName(_, value, viewType):
            
            let link = "@\(value[0].username)"
            
            let text: String
            if value.count > 1 {
                text = strings().peerInfoUsernamesList("@\(value[0].username)", value.suffix(value.count - 1).map { "@\($0.username)" }.joined(separator: ", "))
            } else {
                text = "@\(value[0].username)"
            }
            
            let interactions = TextViewInteractions()
            interactions.processURL = { link in
                if let link = link as? ChatHistoryInAppLinkValue {
                    let found = value.first(where: {  $0.username == link.link.replacingOccurrences(of: "@", with: "") })
                    if let found {
                        arguments.openFragment(.username(found.username))
                    } else {
                        arguments.copy(link.link)
                    }
                }
            }
            interactions.localizeLinkCopy = LinkHooks.shared.globalLinkExecutor().localizeLinkCopy
            
            return TextAndLabelItem(initialSize, stableId: stableId.hashValue, label: strings().peerInfoUsername, copyMenuText: strings().textCopyLabelUsername, labelColor: theme.colors.text, text: text, context: arguments.context, viewType: viewType, detectLinks: true, isTextSelectable: true, _copyToClipboard: {
                arguments.copy(link)
            }, linkInteractions: interactions, qrCode: { control in
                arguments.openQrStudio(from: control)
            })
        case let .peerId(_, value, viewType):
            return  TextAndLabelItem(initialSize, stableId: stableId.hashValue, label: "PEER ID", copyMenuText: strings().textCopyText, text: value, context: arguments.context, viewType: viewType, canCopy: true, _copyToClipboard: {
                arguments.copy(value)
            })
        case let .businessLocation(_, peer, location, viewType):
            return PeerInfoLocationRowItem(initialSize, stableId: stableId.hashValue, context: arguments.context, peer: peer._asPeer(), location: location, viewType: viewType, open: {
                arguments.openLocation(peer._asPeer(), location)
            })
        case let .businessHours(_, peer, businessHours, revealed, displayMyZone, viewType):
            return PeerInfoHoursRowItem(initialSize, stableId: stableId.hashValue, context: arguments.context, revealed: revealed, peer: peer._asPeer(), businessHours: businessHours, displayLocalTimezone: displayMyZone, viewType: viewType, open: {
                arguments.openHours(peer._asPeer(), businessHours)
            }, toggleDisplayZoneTime: arguments.toggleDisplayZoneTime)
        case let .reportReaction(_, value, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoReportReaction, nameStyle: redActionButton, type: .none, viewType: viewType, action: {
                arguments.reportReaction(value)
            })
        case let .scam(_, title, text, viewType):
            return  TextAndLabelItem(initialSize, stableId:stableId.hashValue, label: title, copyMenuText: strings().textCopy, labelColor: theme.colors.redUI, text: text, context: arguments.context, viewType: viewType, detectLinks:false)
        case let .unofficialWarning(_, text, viewType):
            return UnofficialWarningItem(initialSize, stableId: stableId.hashValue, text: text, context: arguments.context, viewType: viewType)
        case let .sendMessage(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoSendMessage, nameStyle: blueActionButton, type: .none, viewType: viewType, action: {
                arguments.peerChat(arguments.peerId)
            })
        case let .botAddToGroup(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoBotAddTo, nameStyle: blueActionButton, type: .none, viewType: viewType, action: {
                arguments.botAddToGroup()
            })
        case let .botAddToGroupInfo(_, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId.hashValue, text: strings().peerInfoBotAddToInfo, viewType: viewType)
        case let .botAddToCommunity(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().userInfoAddBotToCommunity, icon: NSImage(named: "Icon_Community_AddTo")?.precomposed(theme.colors.accent, flipVertical: true), nameStyle: blueActionButton, type: .none, viewType: viewType, action: {
                arguments.addBotToCommunity()
            })
        case let .botAddToCommunityInfo(_, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId.hashValue, text: strings().userInfoAddBotToCommunityInfo, viewType: viewType)
        case let .botLinkedCommunity(_, peer, viewType):
            return ShortPeerRowItem(initialSize, peer: peer, account: arguments.context.account, context: arguments.context, stableId: stableId.hashValue, inset: NSEdgeInsets(left: 20, right: 20), generalType: .next, viewType: viewType, action: {
                arguments.openCommunity(peer.id)
            })
        case let .botRemoveFromCommunity(_, communityId, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().userInfoRemoveBotFromCommunityButton, nameStyle: redActionButton, type: .none, viewType: viewType, action: {
                arguments.removeBotFromCommunity(communityId)
            })
        case let .botShare(_, name, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoBotShare, nameStyle: blueActionButton, type: .none, viewType: viewType, action: {
                arguments.botShare(name)
            })
        case let .botSettings(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoBotSettings, nameStyle: blueActionButton, type: .none, viewType: viewType, action: {
                arguments.botSettings()
            })
        case let .botHelp(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoBotHelp, nameStyle: blueActionButton, type: .none, viewType: viewType, action: {
                arguments.botHelp()
            })
        case let .botPrivacy(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoBotPrivacy, nameStyle: blueActionButton, type: .none, viewType: viewType, action: {
                arguments.botPrivacy()
            })
        case let .shareContact(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoShareContact, nameStyle: blueActionButton, type: .none, viewType: viewType, action: {
                arguments.shareContact()
            })
        case let .shareMyInfo(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoShareMyInfo, nameStyle: blueActionButton, type: .none, viewType: viewType, action: {
                arguments.shareMyInfo()
            })
        case let .addContact(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoAddContact, nameStyle: blueActionButton, type: .none, viewType: viewType, action: {
                arguments.addContact()
            })
        case let .startSecretChat(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoStartSecretChat, nameStyle: blueActionButton, type: .none, viewType: viewType, action: {
                arguments.startSecretChat()
            })
        case let .sharedMedia(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoSharedMedia, type: .next, viewType: viewType, action: {
                arguments.sharedMedia()
            })
        case let .groupInCommon(sectionId: _, count, peerId, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoGroupsInCommon, type: .nextContext("\(count)"), viewType: viewType, action: {
                arguments.groupInCommon(peerId)
            })
            
        case let .notifications(_, settings, viewType):
            let settings = settings as? TelegramPeerNotificationSettings
            let enabled = !(settings?.isMuted ?? false)
            
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoNotifications, type: .switchable(enabled), viewType: viewType, action: {}, enabled: settings != nil)
        case let .encryptionKey(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoEncryptionKey, type: .next, viewType: viewType, action: {
                arguments.encryptionKey()
            })
        case let .suggestBirthday(_, string, nextType, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: string, icon: TelegramThemeHooks.shared.image(.iconBirthdaySuggest).precomposed(blueActionButton.foregroundColor, flipVertical: true), nameStyle: blueActionButton, type: nextType, viewType: viewType, action: {
                arguments.suggestBirthday()
            })
        case let .setPhoto(_, string, type, nextType, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: string, icon: type == .set ? theme.icons.contact_set_photo : theme.icons.contact_suggest_photo, nameStyle: blueActionButton, type: nextType, viewType: viewType, action: {
                arguments.updateContactPhoto(nil, control: nil, type: type)
            })
        case let .resetPhoto(_, string, image, user, viewType):
            return UserInfoResetPhotoItem(initialSize, stableId: stableId.hashValue, context: arguments.context, string: string, user: user, image: image, viewType: viewType, action: arguments.resetPhoto)
        case let .setPhotoInfo(_, string, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId.hashValue, text: string, viewType: viewType)
        case let .copyProtection(_, selected, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoCopyProtectionRestrict, type: .switchable(selected), viewType: viewType, action: {
                arguments.toggleCopyProtection(!selected)
            })
        case let .copyProtectionInfo(_, text, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId.hashValue, text: text, viewType: viewType)
        case let .block(_, peer, isBlocked, isBot, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: isBot ? (!isBlocked ? strings().peerInfoStopBot : strings().peerInfoRestartBot) : (!isBlocked ? strings().peerInfoBlockUser : strings().peerInfoUnblockUser), nameStyle:redActionButton, type: .none, viewType: viewType, action: {
                arguments.updateBlocked(peer: peer, !isBlocked, isBot)
            })
        case let .deleteChat(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoDeleteSecretChat, nameStyle: redActionButton, type: .none, viewType: viewType, action: {
                arguments.delete()
            })
        case let .deleteContact(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoDeleteContact, nameStyle: redActionButton, type: .none, viewType: viewType, action: {
                arguments.deleteContact()
            })
        case let .media(_, controller, isVisible, viewType):
            return PeerMediaBlockRowItem(initialSize, stableId: stableId.hashValue, controller: controller, isVisible: isVisible, viewType: viewType)
        case .section(_):
            return GeneralRowItem(initialSize, height: 20, stableId: stableId.hashValue, viewType: .separator, backgroundColor: .clear)
        }
        
    }
    
}



func userInfoEntries<Context: AccountContextProtocol>(view: PeerView, arguments: PeerInfoArguments<Context>, mediaTabsData: PeerMediaTabsData, source: PeerInfoController<Context>.Source, stories: PeerExpiringStoryListContext.State?, personalChannel: UserInfoPersonalChannel?, revenueState: StarsRevenueStatsContextState?, tonRevenueState: StarsRevenueStatsContextState?, webAppPermissionsState: WebAppPermissionsState?, savedMuicProfileState: ProfileSavedMusicContext.State?) -> [PeerInfoEntry] {
    
    if savedMuicProfileState != nil {
        var bp = 0
        bp += 1
    }
    
    let arguments = arguments as! UserInfoArguments<Context>
    let state = arguments.state as! UserInfoState
    
    var entries: [PeerInfoEntry] = []
    
    var sectionId:Int = 0
    
    let editing = state.editingState != nil

    entries.append(UserInfoEntry<Context>.info(sectionId: sectionId, peerView: view, editable: editing, updatingPhotoState: state.updatingPhotoState, stories: stories, savedMuicProfileState: savedMuicProfileState, viewType: .singleItem))

    
    if let personalChannel, !editing {
        entries.append(UserInfoEntry<Context>.section(sectionId: sectionId))
        sectionId += 1
        
        let right: String
        if let subscribers = personalChannel.subscribers {
            let membersLocalized: String = strings().peerStatusSubscribersOther(Int(subscribers))
            right = membersLocalized.replacingOccurrences(of: "\(subscribers)", with: subscribers.formattedWithSeparator).uppercased()
        } else {
            right = ""
        }
        
        entries.append(UserInfoEntry<Context>.personalChannelInfo(sectionId: sectionId, left: strings().peerInfoPersonalChannelTitle, right: right, viewType: .textTopItem))
        entries.append(UserInfoEntry<Context>.personalChannel(sectionId: sectionId, item: personalChannel, viewType: .singleItem))
    }
    
    func applyBlock(_ block:[UserInfoEntry<Context>]) {
        let block = block.sorted { (p1, p2) -> Bool in
            return p1.isOrderedBefore(p2)
        }
        
        var filtered = block.filter({
            return $0.viewType == .singleItem || $0.viewType == .firstItem || $0.viewType == .lastItem || $0.viewType == .innerItem
        })
        
        let restItems = block.filter({
            return $0.viewType != .singleItem && $0.viewType != .firstItem && $0.viewType != .lastItem && $0.viewType != .innerItem
        })
        
        for (i, item) in filtered.enumerated() {
            filtered[i] = item.withUpdatedViewType(bestGeneralViewType(filtered, for: i))
        }
        if filtered.count != block.count {
            filtered.append(contentsOf: restItems)
        }
        entries.append(contentsOf: filtered)
    }
    
    var headerBlock: [UserInfoEntry<Context>] = []
    
        
    
    if editing {
        headerBlock.append(.setFirstName(sectionId: sectionId, text: state.editingState?.editingFirstName ?? "", viewType: .singleItem))
        headerBlock.append(.setLastName(sectionId: sectionId, text: state.editingState?.editingLastName ?? "", placeholder: peerViewMainPeer(view)?.isBot == true ? strings().peerInfoDescriptionPlaceholder : strings().peerInfoLastNamePlaceholder, viewType: .singleItem))
    }
    
    applyBlock(headerBlock)
    
    if editing, view.peerIsContact {
        
        entries.append(UserInfoEntry<Context>.section(sectionId: sectionId))
        sectionId += 1

        entries.append(
            UserInfoEntry<Context>.setNotes(
                sectionId: sectionId,
                note: state.editingState?.editingNotes ?? .init(text: "", entities: []),
                placeholder: strings().peerInfoNotesPlaceholder,
                viewType: .singleItem
            )
        )

        entries.append(
            UserInfoEntry<Context>.setNotesInfo(
                sectionId: sectionId,
                text: strings().peerInfoNotesDescription,
                viewType: .textBottomItem
            )
        )
    }
    
    
    
    entries.append(UserInfoEntry<Context>.section(sectionId: sectionId))
    sectionId += 1
    

    
    if let peer = view.peers[view.peerId] {
        
        if let user = peerViewMainPeer(view) as? TelegramUser {
            
            var destructBlock:[UserInfoEntry<Context>] = []
            var photoBlock:[UserInfoEntry<Context>] = []
            var firstBlock:[UserInfoEntry<Context>] = []
            var infoBlock:[UserInfoEntry<Context>] = []

            if state.editingState == nil {
                if let cachedData = view.cachedData as? CachedUserData, cachedData.flags.contains(.unofficialSecurityRisk) {
                    let name = user.compactDisplayTitle
                    firstBlock.append(UserInfoEntry<Context>.unofficialWarning(sectionId: sectionId, text: strings().peerInfoUnofficialClientText(name), viewType: .singleItem))
                    
                    applyBlock(firstBlock)

                    entries.append(UserInfoEntry<Context>.section(sectionId: sectionId))
                    sectionId += 1
                }

                if user.isScam {
                    infoBlock.append(UserInfoEntry<Context>.scam(sectionId: sectionId, title: strings().peerInfoScam, text: strings().peerInfoScamWarning, viewType: .singleItem))
                } else if user.isFake {
                    infoBlock.append(UserInfoEntry<Context>.scam(sectionId: sectionId, title: strings().peerInfoFake, text: strings().peerInfoFakeWarning, viewType: .singleItem))
                }
                if let phoneNumber = user.phone, !phoneNumber.isEmpty {
                    infoBlock.append(.phoneNumber(sectionId: sectionId, index: 0, value: PhoneNumberWithLabel(label: phoneNumber.hasPrefix("888") ? strings().peerInfoAnonymousPhone : strings().peerInfoPhone, number: phoneNumber), canCopy: true, viewType: .singleItem))
                } else if view.peerIsContact {
                    infoBlock.append(.phoneNumber(sectionId: sectionId, index: 0, value: PhoneNumberWithLabel(label: strings().peerInfoPhone, number: strings().newContactPhoneHidden), canCopy: false, viewType: .singleItem))
                }

                
                
                if let cachedUserData = view.cachedData as? CachedUserData {
                    
                    if let note = cachedUserData.note {
                        infoBlock.append(.notes(sectionId: sectionId, index: 0, value: note, viewType: .singleItem))
                    }
                    
                    if let about = cachedUserData.about, !about.isEmpty, !user.isScam && !user.isFake {
                        if let botInfo = peer.botInfo {
                            infoBlock.append(UserInfoEntry<Context>.about(sectionId: sectionId, text: about, launchApp: botInfo.flags.contains(.hasWebApp), viewType: .singleItem))
                            if botInfo.flags.contains(.canEdit) {
                                infoBlock.append(UserInfoEntry<Context>.aboutInfo(sectionId: sectionId, text: strings().botInfoLaunchInfo, viewType: .textBottomItem))
                            } else if botInfo.flags.contains(.hasWebApp) {
                                let privacyPolicyUrl = cachedUserData.botInfo?.privacyPolicyUrl ?? strings().botInfoLaunchInfoPrivacyUrl
                                infoBlock.append(UserInfoEntry<Context>.aboutInfo(sectionId: sectionId, text: strings().botInfoLaunchInfoUser(privacyPolicyUrl), viewType: .textBottomItem))
                            }
                        } else {
                            infoBlock.append(UserInfoEntry<Context>.bio(sectionId: sectionId, text: about, PeerEquatable(peer), viewType: .singleItem))
                        }
                    } else if cachedUserData.about == nil, let botInfo = peer.botInfo, botInfo.flags.contains(.hasWebApp) {
                        infoBlock.append(UserInfoEntry<Context>.about(sectionId: sectionId, text: "", launchApp: botInfo.flags.contains(.hasWebApp), viewType: .singleItem))
                        if botInfo.flags.contains(.canEdit) {
                            infoBlock.append(UserInfoEntry<Context>.aboutInfo(sectionId: sectionId, text: strings().botInfoLaunchInfo, viewType: .textBottomItem))
                        } else {
                            let privacyPolicyUrl = cachedUserData.botInfo?.privacyPolicyUrl ?? strings().botInfoLaunchInfoPrivacyUrl
                            infoBlock.append(UserInfoEntry<Context>.aboutInfo(sectionId: sectionId, text: strings().botInfoLaunchInfoUser(privacyPolicyUrl), viewType: .textBottomItem))

                        }
                    }

                    if let botManagerId = cachedUserData.botManagerId, let managerPeer = view.peers[botManagerId] {
                        infoBlock.append(UserInfoEntry<Context>.botManager(sectionId: sectionId, peer: EnginePeer(managerPeer), viewType: .textBottomItem))
                    }

                }
                

                
                var usernames:[UserInfoAddress] = user.usernames.filter { $0.isActive }.map {
                    .init(username: $0.username, collectable: $0.flags.contains(.isEditable))
                }
                if usernames.isEmpty, let address = user.addressName {
                    usernames.append(.init(username: address, collectable: false))
                }
                if !usernames.isEmpty {
                    infoBlock.append(.userName(sectionId: sectionId, value: usernames, viewType: .singleItem))
                }
                
          
                
                if let cachedUserData = view.cachedData as? CachedUserData {
                    if let birthday = cachedUserData.birthday {
                        infoBlock.append(.birthday(sectionId: sectionId, text: birthday.formattedYears, birthday.isEligble, viewType: .singleItem))
                    }
                }
                if let cachedUserData = view.cachedData as? CachedUserData {
                    if let hours = cachedUserData.businessHours {
                        infoBlock.append(.businessHours(sectionId: sectionId, peer: .init(peer), businessHours: hours, revealed: state.businessHoursRevealed, displayMyZone: state.businessHoursDisplayMyTimezone, viewType: .singleItem))
                    }
                    if let location = cachedUserData.businessLocation {
                        infoBlock.append(.businessLocation(sectionId: sectionId, peer: .init(peer), businessLocation: location, viewType: .singleItem))
                    }
                }
                
                if !user.isBot {
                    if !view.peerIsContact, user.id != arguments.context.peerId {
                        infoBlock.append(.addContact(sectionId: sectionId, viewType: .singleItem))
                    }
                }
                if (peer is TelegramSecretChat) {
                    infoBlock.append(.encryptionKey(sectionId: sectionId, viewType: .singleItem))
                }
                if !user.isBot {
                    if !view.peerIsContact, user.id != arguments.context.peerId {
                        if let cachedData = view.cachedData as? CachedUserData {
                            var addBlock = true
                            switch source {
                            case let .reaction(messageId):
                                if !cachedData.isBlocked {
                                    infoBlock.append(.reportReaction(sectionId: sectionId, value: messageId, viewType: .singleItem))
                                    addBlock = false
                                }
                            default:
                                break
                            }
                            if addBlock {
                                infoBlock.append(.block(sectionId: sectionId, peer: peer, blocked: cachedData.isBlocked, isBot: peer.isBot, viewType: .singleItem))
                            }
                        }
                    }
                }
               
                let verification = (view.cachedData as? CachedUserData)?.verification
                if case .none = source, user.id != arguments.context.peerId, let verification {
                    infoBlock.append(UserInfoEntry<Context>.verifiedInfo(sectionId: sectionId, value: verification, viewType: .textBottomItem))
                }

                applyBlock(infoBlock)

                let cachedUserData = view.cachedData as? CachedUserData
                let affiliateEnabled = arguments.context.appConfiguration.getBoolValue("starref_connect_allowed", orElse: false)
                let hasAffiliate = peer.botInfo?.flags.contains(.canEdit) == false && cachedUserData?.starRefProgram != nil && affiliateEnabled
                let canAddToGroup = verification == nil && user.botInfo?.flags.contains(.worksWithGroups) == true

                if hasAffiliate || canAddToGroup {
                    entries.append(UserInfoEntry<Context>.section(sectionId: sectionId))
                    sectionId += 1

                    if hasAffiliate, let program = cachedUserData?.starRefProgram {
                        let localizedDuration: String
                        if let duration = program.durationMonths {
                            localizedDuration = duration < 12 ? strings().timerMonthsOther(Int(duration)) : strings().timerYearsOther(Int(duration / 12))
                        } else {
                            localizedDuration = strings().affiliateProgramDurationLifetime
                        }
                        let text = "\(program.commissionPermille.decemial)%, \(localizedDuration)"
                        entries.append(UserInfoEntry<Context>.botAffiliate(sectionId: sectionId, text: text, starRefProgram: program, viewType: canAddToGroup ? .firstItem : .singleItem))
                    }

                    if canAddToGroup {
                        entries.append(UserInfoEntry<Context>.botAddToGroup(sectionId: sectionId, viewType: hasAffiliate ? .lastItem : .singleItem))
                        entries.append(UserInfoEntry<Context>.botAddToGroupInfo(sectionId: sectionId, viewType: .textBottomItem))
                    }
                }

            }
            
            if let cachedData = view.cachedData as? CachedUserData, arguments.context.account.peerId != arguments.peerId {
                if let _ = state.editingState {
                    
                    if peer.botInfo?.flags.contains(.canEdit) == true {
                        let affiliateEnabled = arguments.context.appConfiguration.getBoolValue("starref_program_allowed", orElse: false)

                        entries.append(UserInfoEntry<Context>.botEditUsername(sectionId: sectionId, text: peer.addressName ?? "", viewType: affiliateEnabled ? .firstItem : .singleItem))
                        let text: String
                        if let program = cachedData.starRefProgram {
                            let localizedDuration: String
                            if let duration = program.durationMonths {
                                localizedDuration = duration < 12 ? strings().timerMonthsOther(Int(duration)) : strings().timerYearsOther(Int(duration / 12))
                            } else {
                                localizedDuration = strings().affiliateProgramDurationLifetime
                            }
                            text = "\(program.commissionPermille.decemial)%, \(localizedDuration)"
                        } else {
                            text = strings().affiliateProgramOff
                        }
                        if affiliateEnabled {
                            entries.append(UserInfoEntry<Context>.botAffiliate(sectionId: sectionId, text: text, starRefProgram: cachedData.starRefProgram, viewType: .lastItem))
                        }
                        entries.append(UserInfoEntry<Context>.section(sectionId: sectionId))
                        sectionId += 1

                        if peer.isBot, let info = cachedData.botInfo, let settings = info.verifierSettings {
                            entries.append(UserInfoEntry<Context>.verifyAccounts(sectionId: sectionId, verification: settings, viewType: .singleItem))
                            entries.append(UserInfoEntry<Context>.section(sectionId: sectionId))
                            sectionId += 1
                        }

                        
                        destructBlock.append(.botEditIntro(sectionId: sectionId, viewType: .singleItem))
                        destructBlock.append(.botEditCommands(sectionId: sectionId, viewType: .singleItem))
                        destructBlock.append(.botEditSettings(sectionId: sectionId, viewType: .singleItem))

                    } else if view.peerIsContact, peer.sendPaidMessageStars == nil {
                        if cachedData.birthday == nil {
                            photoBlock.append(
                                .suggestBirthday(
                                    sectionId: sectionId,
                                    string: strings().peerInfoSuggestBirthday,
                                    nextType: .none,
                                    viewType: .singleItem
                                )
                            )
                        }
                        photoBlock.append(.setPhoto(sectionId: sectionId, string: strings().userInfoSuggestPhoto(user.compactDisplayTitle), type: .suggest, nextType: state.suggestingPhotoState != nil ? .loading : .none, viewType: .singleItem))
                        photoBlock.append(.setPhoto(sectionId: sectionId, string: strings().userInfoSetPhoto(user.compactDisplayTitle), type: .set, nextType: .none, viewType: .singleItem))

                        if user.photo.contains(where: { $0.isPersonal }), let image = cachedData.photo {
                            photoBlock.append(.resetPhoto(sectionId: sectionId, string: strings().userInfoResetPhoto, image: image, user: user, viewType: .lastItem))
                        }
                    }
                    
                    
                   
                   
                    
                    if !photoBlock.isEmpty {
                        entries.append(UserInfoEntry<Context>.setPhotoInfo(sectionId: sectionId, string: strings().userInfoSetPhotoBlockInfo(user.compactDisplayTitle), viewType: .textBottomItem))
                    }
                    
                    
                    
                    if !photoBlock.isEmpty, peer is TelegramSecretChat || view.peerIsContact {
                        entries.append(UserInfoEntry<Context>.section(sectionId: sectionId))
                        sectionId += 1
                    }


                    if peer is TelegramSecretChat || view.peerIsContact {
                        destructBlock.append(.deleteContact(sectionId: sectionId, viewType: .singleItem))
                    }
                }

            }
            applyBlock(photoBlock)
            
            
            
            
            applyBlock(destructBlock)
            
            if peer.botInfo?.flags.contains(.canEdit) == true, state.editingState != nil {
                entries.append(UserInfoEntry<Context>.botEditInfo(sectionId: sectionId, viewType: .textBottomItem))

                entries.append(UserInfoEntry<Context>.section(sectionId: sectionId))
                sectionId += 1
                if let communityId = user.linkedCommunityId {
                    if let community = view.peers[communityId] {
                        entries.append(UserInfoEntry<Context>.botLinkedCommunity(sectionId: sectionId, peer: community, viewType: .firstItem))
                        entries.append(UserInfoEntry<Context>.botRemoveFromCommunity(sectionId: sectionId, communityId: communityId, viewType: .lastItem))
                    } else {
                        entries.append(UserInfoEntry<Context>.botRemoveFromCommunity(sectionId: sectionId, communityId: communityId, viewType: .singleItem))
                    }
                } else {
                    entries.append(UserInfoEntry<Context>.botAddToCommunity(sectionId: sectionId, viewType: .singleItem))
                    entries.append(UserInfoEntry<Context>.botAddToCommunityInfo(sectionId: sectionId, viewType: .textBottomItem))
                }
            }
            
            
            if let cachedData = (view.cachedData as? CachedUserData) {
                
               
                
                let starBalance = (revenueState?.stats?.balances.currentBalance.amount.value ?? 0)
                let tonBalance = (tonRevenueState?.stats?.balances.currentBalance.amount.value ?? 0)

                let hasStars = (revenueState?.stats?.balances.overallRevenue.amount.value ?? 0) > 0
                let hasTon = (tonRevenueState?.stats?.balances.overallRevenue.amount.value ?? 0) > 0

                
                if hasStars || hasTon {
                    entries.append(UserInfoEntry<Context>.section(sectionId: sectionId))
                    sectionId += 1
                    

                    if hasStars {
                        entries.append(UserInfoEntry<Context>.botStarsBalance(sectionId: sectionId, text: starBalance == 0 ? "" : strings().peerInfoBotEditStarsCountOther(Int(starBalance)).replacingOccurrences(of: "\(starBalance)", with: starBalance.formattedWithSeparator), viewType: hasTon ? .firstItem : .singleItem))
                    }
                    
                    if hasTon {
                        let balance = formatCurrencyAmount(tonBalance, currency: TON).prettyCurrencyNumberUsd
                        entries.append(UserInfoEntry<Context>.botTonBalance(sectionId: sectionId, text: "\(balance)", viewType: hasStars ? .lastItem : .singleItem))
                    }
                }
                
                var addHeader: Bool = true
                
                let addPermissionHeader:()->Void = {
                    entries.append(UserInfoEntry<Context>.section(sectionId: sectionId))
                    sectionId += 1
                    
                    entries.append(UserInfoEntry<Context>.botPermissionsHeader(sectionId: sectionId, text: strings().peerInfoBotPermissionsHeader, viewType: .textTopItem))
                }
                if cachedData.flags.contains(.botCanManageEmojiStatus) {
                    addPermissionHeader()
                    addHeader = false
                    entries.append(UserInfoEntry<Context>.botPermissionsStatus(sectionId: sectionId, value: cachedData.flags.contains(.botCanManageEmojiStatus), viewType: webAppPermissionsState?.location == nil ? .singleItem : .firstItem))
                }
                
                if let location = webAppPermissionsState?.location {
                    if addHeader {
                        addPermissionHeader()
                    }
                    entries.append(UserInfoEntry<Context>.botPermissionsGeo(sectionId: sectionId, value: location.isAllowed, viewType: addHeader ? .singleItem : .lastItem))
                }
                
            }
            
            if FastSettings.canViewPeerId, state.editingState == nil {
                entries.append(UserInfoEntry<Context>.section(sectionId: sectionId))
                sectionId += 1
                entries.append(UserInfoEntry<Context>.peerId(sectionId: sectionId, value: "\(user.id.id._internalGetInt64Value())", viewType: .singleItem))
            }
            
            if mediaTabsData.loaded && !mediaTabsData.collections.isEmpty, let controller = arguments.mediaController() {
                if state.editingState != nil {
                    entries.append(UserInfoEntry<Context>.section(sectionId: sectionId))
                }
                sectionId += 1
                entries.append(UserInfoEntry<Context>.media(sectionId: sectionId, controller: controller, isVisible: state.editingState == nil, viewType: .singleItem))
            } else {
                entries.append(UserInfoEntry<Context>.section(sectionId: sectionId))
                sectionId += 1
            }
        }
    }
    
    
    return entries.sorted(by: { (p1, p2) -> Bool in
        return p1.isOrderedBefore(p2)
    })
}
