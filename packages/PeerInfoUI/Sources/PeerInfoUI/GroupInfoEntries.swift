import Cocoa
import Postbox
import TelegramCore

import SwiftSignalKit
import TGUIKit
import AlertsUI
import AvatarEditorUI
import ChannelAdminUI
import ChatHistoryModel
import ChatUI
import CommunityUI
import FilePanels
import GeneralRows
import InAppSettings
import InactiveChannelsUI
import InputDataUI
import InviteLinksUI
import LocalAnimations
import Localization
import ReportUI
import ShareUI
import SelectPeersUI
import ShortPeerRow
import StatisticsUI
import TelegramContext
import TelegramMediaUtils
import TelegramTheme
import TelegramUtils
import InlineStickerLayer
import AppAnalytics

extension AddGroupMemberError {
    var channelError: AddChannelMemberError {
        switch self {
        case .generic:
            return .generic
        case .groupFull:
            return .generic
        case let .privacy(result):
            return .restricted(result?.forbiddenPeers.first)
        case .notMutualContact:
            return .notMutualContact
        case .tooManyChannels:
            return .tooMuchJoined
        }
    }
}

enum TopicsLimitedReason : Equatable {
    case participants(Int)
    case discussion
}



private func valuesRequiringUpdate(state: GroupInfoState, view: PeerView) -> (title: String?, description: String?) {
    if let peer = view.peers[view.peerId] as? TelegramGroup {
        var titleValue: String?
        var descriptionValue: String?
        if let editingState = state.editingState {
            if let title = editingState.editingName, title != peer.title {
                titleValue = title
            }
            if let cachedData = view.cachedData as? CachedGroupData {
                if let about = cachedData.about {
                    if about != editingState.editingDescriptionText {
                        descriptionValue = editingState.editingDescriptionText
                    }
                } else if !editingState.editingDescriptionText.isEmpty {
                    descriptionValue = editingState.editingDescriptionText
                }
            }
        }
        
        return (titleValue, descriptionValue)
    } else if let peer = view.peers[view.peerId] as? TelegramChannel {
        var titleValue: String?
        var descriptionValue: String?
        if let editingState = state.editingState {
            if let title = editingState.editingName, title != peer.title {
                titleValue = title
            }
            if let cachedData = view.cachedData as? CachedChannelData {
                if let about = cachedData.about {
                    if about != editingState.editingDescriptionText {
                        descriptionValue = editingState.editingDescriptionText
                    }
                } else if !editingState.editingDescriptionText.isEmpty {
                    descriptionValue = editingState.editingDescriptionText
                }
            }
        }
        
        return (titleValue, descriptionValue)
    } else {
        return (nil, nil)
    }
}

struct GroupInfoEditingState: Equatable {
    let editingName: String?
    let editingDescriptionText: String
    
    init(editingName:String? = nil, editingDescriptionText:String = "") {
        self.editingName = editingName
        self.editingDescriptionText = editingDescriptionText
    }
    
    func withUpdatedEditingDescriptionText(_ editingDescriptionText: String) -> GroupInfoEditingState {
        return GroupInfoEditingState(editingName: self.editingName, editingDescriptionText: editingDescriptionText)
    }
}

public func selectForumMembers<Context: AccountContextProtocol>(context: Context, peerId: PeerId) -> Disposable {
    let arguments = GroupInfoArguments(context: context, peerId: peerId, state: GroupInfoState(), isAd: false, pushViewController: { context.bindings.rootNavigation().push($0) }, pullNavigation: { context.bindings.rootNavigation() }, mediaController: { nil })
    arguments.addMember(true)
    return ActionDisposable { withExtendedLifetime(arguments) {} }
}

private struct Result {
    let success:[PeerId]
    let failed:[(PeerId, AddChannelMemberError)]
}

final class GroupInfoArguments<Context: AccountContextProtocol> : PeerInfoArguments<Context> {
    
    private let addMemberDisposable = MetaDisposable()
    private let removeMemberDisposable = MetaDisposable()
    private let updatePeerNameDisposable = MetaDisposable()
    private let updatePhotoDisposable = MetaDisposable()
    private let reportPeerDisposable = MetaDisposable()
    private let visibilitySetupDisposable = MetaDisposable()
        
    func updateState(_ f: (GroupInfoState) -> GroupInfoState) -> Void {
        updateInfoState { state -> PeerInfoState in
            let result = f(state as! GroupInfoState)
            return result
        }
    }
    
    
    var loadMore: (()->Void)? = nil
    
    private var _linksManager:InviteLinkPeerManager?
    var linksManager: InviteLinkPeerManager {
        if let _linksManager = _linksManager {
            return _linksManager
        } else {
            _linksManager = InviteLinkPeerManager(context: context, peerId: peerId)
            _linksManager!.loadNext()
            return _linksManager!
        }
    }
    
    private var _requestManager:PeerInvitationImportersContext?
    var requestManager: PeerInvitationImportersContext {
        if let _requestManager = _requestManager {
            return _requestManager
        } else {
            let importersContext = context.engine.peers.peerInvitationImporters(peerId: peerId, subject: .requests(query: nil))
            _requestManager = importersContext
            _requestManager!.loadMore()
            return _requestManager!
        }
    }
    
    override func updateEditable(_ editable:Bool, peerView:PeerView, controller: PeerInfoController<Context>) -> Bool {
        
        let context = self.context
        let peerId = self.peerId
        let updateState:((GroupInfoState)->GroupInfoState)->Void = { [weak self] f in
            self?.updateState(f)
        }
        if editable {
            if let peer = peerViewMainPeer(peerView) {
                 if peer.isSupergroup, let cachedData = peerView.cachedData as? CachedChannelData {
                    updateState { state -> GroupInfoState in
                        return state.withUpdatedEditingState(GroupInfoEditingState(editingName: peer.displayTitle, editingDescriptionText: cachedData.about ?? ""))
                    }
                } else if let cachedData = peerView.cachedData as? CachedGroupData {
                    updateState { state -> GroupInfoState in
                        return state.withUpdatedEditingState(GroupInfoEditingState(editingName: peer.displayTitle, editingDescriptionText: cachedData.about ?? ""))
                    }
                }
            }
        } else {
            
          
            
            var updateValues: (title: String?, description: String?) = (nil, nil)
            updateState { state in
                updateValues = valuesRequiringUpdate(state: state, view: peerView)
                return state
            }
            
            if let titleValue = updateValues.title, titleValue.isEmpty {
                controller.genericView.tableView.item(stableId: IntPeerInfoEntryStableId(value: 1).hashValue)?.view?.shakeView()
                return false
            }
            
            updateState { state in
                if updateValues.0 != nil || updateValues.1 != nil {
                    return state.withUpdatedSavingData(true)
                } else {
                    return state.withUpdatedEditingState(nil)
                }
            }
            
            
            let updateTitle: Signal<Void, NoError>
            if let titleValue = updateValues.title {
                updateTitle = context.engine.peers.updatePeerTitle(peerId: peerId, title: titleValue)
                     |> `catch` {_ in return .complete()}
            } else {
                updateTitle = .complete()
            }
            
            let updateDescription: Signal<Void, NoError>
            if let descriptionValue = updateValues.description {
                updateDescription = context.engine.peers.updatePeerDescription(peerId: peerId, description: descriptionValue.isEmpty ? nil : descriptionValue)
                     |> `catch` {_ in return .complete()}
            } else {
                updateDescription = .complete()
            }
            
            let signal = combineLatest(updateTitle, updateDescription)
            
            updatePeerNameDisposable.set(showModalProgress(signal: (signal |> deliverOnMainQueue), for: context.window).start(completed: {
                updateState { state in
                    return state.withUpdatedSavingData(false).withUpdatedEditingState(nil)
                }
            }))
        }
        
        return true
    }
    
    override func dismissEdition() {
        updateState { state in
            return state.withUpdatedSavingData(false).withUpdatedEditingState(nil)
        }
    }
    
    func updateEditingName(_ name:String) -> Void {
        manageStep?(.changeTitle)
        updateState { state in
            if let editingState = state.editingState {
                return state.withUpdatedEditingState(GroupInfoEditingState(editingName: name, editingDescriptionText: editingState.editingDescriptionText))
            } else {
                return state
            }
        }
    }
    func updateEditingDescriptionText(_ text:String) -> Void {
        manageStep?(.changeDescription)
        updateState { state in
            if let editingState = state.editingState {
                return state.withUpdatedEditingState(editingState.withUpdatedEditingDescriptionText(text))
            }
            return state
        }
    }
    
    func visibilitySetup() {
        manageStep?(.changeType)
        let setup = PeerInfoNavigationHooks.shared.makeChannelVisibilityController(context, peerId, false, linksManager)
        let context = context
        let signal: Signal<Peer?, NoError> = setup.onComplete |> take(1) |> mapToSignal { peerId in
            if let peerId = peerId {
                return context.account.postbox.loadedPeerWithId(peerId) |> map(Optional.init)
            } else {
                return .single(nil)
            }
        } |> deliverOnMainQueue
        
        visibilitySetupDisposable.set(signal.start(next: { [weak self] peer in
            self?.changeControllers(peer)
            self?.pullNavigation()?.back()
        }))
        pushViewController(setup.controller)

    }

    func autoremoveController() {
        //pushViewController(AutoremoveMessagesController(context: context, peerId: peerId))
    }
    
    func openInviteLinks() {
        manageStep?(.openInviteLinks)
        pushViewController(InviteLinksController(context: context, peerId: peerId, isChannel: false, manager: linksManager))
    }
    func openRequests() {
        pushViewController(RequestJoinMemberListController(context: context, peerId: peerId, manager: requestManager, openInviteLinks: { [weak self] in
            self?.openInviteLinks()
        }))
    }
    func openReactions(allowedReactions: PeerAllowedReactions?, availableReactions: AvailableReactions?) {
        manageStep?(.openReactions)
        pushViewController(PeerInfoNavigationHooks.shared.makeGroupReactionsSettingsController(context, peerId, allowedReactions, availableReactions))
    }

    private func changeControllers(_ peer: Peer?) {
        guard let navigationController = self.pullNavigation() else {
            return
        }
        if let peer = peer {
            let peerId = peer.id
            var chatController: ChatController<Context>? = ChatController(context: context, chatLocation: .peer(peerId))
            
            navigationController.removeAll()
            
            chatController!.navigationController = navigationController
            chatController!.loadViewIfNeeded(navigationController.bounds)
            
            var signal = chatController!.ready.get() |> filter {$0} |> take(1) |> ignoreValues
            
            var controller: PeerInfoController<Context>? = PeerInfoController(context: context, peer: peer)
            
            
            controller!.navigationController = navigationController
            controller!.loadViewIfNeeded(navigationController.bounds)
            
            let mainSignal = controller!.ready.get() |> filter {$0} |> take(1) |> ignoreValues
            
            signal = combineLatest(queue: .mainQueue(), signal, mainSignal) |> ignoreValues
            
            _ = signal.start(completed: { [weak navigationController] in
                guard let navigationController = navigationController else { return }
                
                
                navigationController.stackInsert(navigationController.empty, at: 0)
                navigationController.stackInsert(chatController!, at: 1)
                navigationController.stackInsert(controller!, at: 2)
                navigationController.stackInsert(navigationController.controller, at: 3)
                navigationController.back()
                chatController = nil
                controller = nil
            })
        } else {
            navigationController.back()
        }
        
        
    }
    
    func report() -> Void {
        let context = self.context
        let peerId = self.peerId

        let report = reportReasonSelector(context: context) |> map { value -> (ChatController<Context>?, ReportReasonValue) in
            switch value.reason {
            case .fake:
                return (nil, value)
            default:
                return (ChatController(context: context, chatLocation: .peer(peerId), initialAction: .selectToReport(reason: value)), value)
            }
        } |> deliverOnMainQueue

        reportPeerDisposable.set(report.start(next: { [weak self] controller, value in
            if let controller = controller {
                self?.pullNavigation()?.push(controller)
            } else {
                showModal(with: ReportDetailsController(context: context, reason: value, updated: { value in
                    _ = showModalProgress(signal: context.engine.peers.reportPeer(peerId: peerId, reason: value.reason, message: value.comment), for: context.window).start(completed: {
                        showModalText(for: context.window, text: strings().peerInfoChannelReported)
                    })
                }), for: context.window)
               
            }
        }))
    }
    
    func preHistorySetup() {
        manageStep?(.toggleHistoryVisible)
        let context = self.context
        let setup = PreHistorySettingsController(context: context, peerId: peerId, onComplete: { [weak self] resultPeerId in
            let signal: Signal<Peer?, NoError>
            if let resultPeerId = resultPeerId {
                signal = context.account.postbox.loadedPeerWithId(resultPeerId) |> map(Optional.init)
            } else {
                signal = .single(nil)
            }
            _ = (signal |> deliverOnMainQueue).start(next: { [weak self] peer in
                self?.changeControllers(peer)
            })
        })
        pushViewController(setup)
    }
    func toggleForum(_ enabled: Bool, _ convert: Bool, _ limit: TopicsLimitedReason?) {
        
        
        let context = self.context
        if let limit = limit {
            let text: String
            switch limit {
            case let .participants(minimum):
                text = strings().peerInfoTopicsLimitedParticipantCountTextOther(minimum)
            case .discussion:
                text = strings().peerInfoTopicsLimitedDiscussionGroups
            }
            showModalText(for: context.window, text: text)
        } else {
            manageStep?(.toggleForum)
            if convert {
                let upgrade = upgradeToSupergroup()
                
                _ = showModalProgress(signal: context.engine.peers.convertGroupToSupergroup(peerId: peerId), for: context.window).start(next: { [weak self] peerId in
                    upgrade(peerId, {
                        self?.pushViewController(PeerInfoNavigationHooks.shared.makeForumSettingsController(context, peerId))
                    })
                }, error: { error in
                    switch error {
                    case .tooManyChannels:
                        showInactiveChannels(context: context, source: .upgrade)
                    case .generic:
                        alert(for: context.window, info: strings().unknownError)
                    }
                })
                
            } else {
                pushViewController(PeerInfoNavigationHooks.shared.makeForumSettingsController(context, peerId))
            }
        }
    }
    
    func blacklist() {
        manageStep?(.openPermissions)
        pushViewController(PeerInfoNavigationHooks.shared.makeChannelPermissionsController(context, peerId))
    }
    func admins() {
        manageStep?(.openAdmins)
        pushViewController(ChannelAdminsViewController(context, peerId: peerId))
    }
    func members() {
        manageStep?(.openMembers)
        pushViewController(PeerInfoNavigationHooks.shared.makeChannelMembersController(context, peerId))
    }
    func addToCommunity() {
        pushViewController(CommunitiesController(context, peerId: peerId))
    }

    func openCommunity(_ communityId: PeerId) {
        showCommunityView(context, communityId: communityId)
    }

    func removeFromCommunity(_ communityId: PeerId) {
        let context = self.context
        let peerId = self.peerId
        verifyAlert(for: context.window, header: strings().groupInfoRemoveGroupFromCommunity, information: strings().groupInfoRemoveGroupFromCommunityConfirm, ok: strings().groupInfoRemove, successHandler: { _ in
            _ = (context.engine.peers.toggleCommunityPeerLink(communityId: communityId, peerId: peerId, action: .unlink) |> deliverOnMainQueue).start(error: { _ in
                alert(for: context.window, info: strings().groupInfoSomethingWentWrong)
            }, completed: {
                context.account.viewTracker.forceUpdateCachedPeerData(peerId: peerId)
                context.account.viewTracker.forceUpdateCachedPeerData(peerId: communityId)
            })
        })
    }
    
    func invation() {
        pushViewController(InviteLinksController(context: context, peerId: peerId, isChannel: false, manager: linksManager))
    }
    
    func stats(_ datacenterId: Int32) {
        if self.peer?.isSupergroup == true {
            self.pushViewController(ChannelStatsSegmentController(context, peerId: peerId, isChannel: false, analyticsContext: captureAnalyticsContext()))
        } else {
            self.pushViewController(GroupStatsViewController(context, peerId: peerId, analyticsContext: captureAnalyticsContext()))
        }
    }
    
    func showMore() {
        let updateState:((GroupInfoState)->GroupInfoState)->Void = { [weak self] f in
            self?.updateState(f)
        }
        updateState {
            return $0.withUpdatedHasShowMoreButton(nil)
        }
    }
    
    func updatePhoto(_ path:String) -> Void {
        manageStep?(.changePhoto)
        
        let updateState:((GroupInfoState)->GroupInfoState)->Void = { [weak self] f in
            self?.updateState(f)
        }
        
        let cancel = { [weak self] in
            self?.updatePhotoDisposable.set(nil)
            updateState { state -> GroupInfoState in
                return state.withoutUpdatingPhotoState()
            }
        }
        
        let context = self.context
        let peerId = self.peerId
        
        let updateSignal = Signal<String, NoError>.single(path) |> map { path -> TelegramMediaResource in
            return LocalFileReferenceMediaResource(localFilePath: path, randomId: arc4random64())
            } |> beforeNext { resource in
                
                updateState { (state) -> GroupInfoState in
                    return state.withUpdatedUpdatingPhotoState { previous -> PeerInfoUpdatingPhotoState? in
                        return PeerInfoUpdatingPhotoState(progress: 0, image: NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil), cancel: cancel)
                    }
                }
                
            } |> castError(UploadPeerPhotoError.self) |> mapToSignal { resource -> Signal<UpdatePeerPhotoStatus, UploadPeerPhotoError> in
                return context.engine.peers.updatePeerPhoto(peerId: peerId, photo: context.engine.peers.uploadedPeerPhoto(resource: EngineMediaResource(resource)), mapResourceToAvatarSizes: { resource, representations in
                    return mapResourceToAvatarSizes(engine: context.engine, resource: resource, representations: representations)
                })
        }
        
        
        updatePhotoDisposable.set((updateSignal |> deliverOnMainQueue).start(next: { status in
            updateState { state -> GroupInfoState in
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
            updateState { (state) -> GroupInfoState in
                return state.withoutUpdatingPhotoState()
            }
        }, completed: {
            updateState { (state) -> GroupInfoState in
                return state.withoutUpdatingPhotoState()
            }
        }))
        
        
    }
    
    func updateVideo(_ signal:Signal<VideoAvatarGeneratorState, NoError>) -> Void {
        manageStep?(.changePhoto)
        
        let updateState:((GroupInfoState)->GroupInfoState)->Void = { [weak self] f in
            self?.updateState(f)
        }
        
        let cancel = { [weak self] in
            self?.updatePhotoDisposable.set(nil)
            updateState { state -> GroupInfoState in
                return state.withoutUpdatingPhotoState()
            }
        }
        
        let context = self.context
        let peerId = self.peerId
        
        
        let updateSignal: Signal<UpdatePeerPhotoStatus, UploadPeerPhotoError> = signal
            |> castError(UploadPeerPhotoError.self)
            |> mapToSignal { state in
                switch state {
                case .error:
                    return .fail(.generic)
                case let .start(path):
                    updateState { (state) -> GroupInfoState in
                        return state.withUpdatedUpdatingPhotoState { previous -> PeerInfoUpdatingPhotoState? in
                            return PeerInfoUpdatingPhotoState(progress: 0, image: NSImage(contentsOfFile: path)?._cgImage, cancel: cancel)
                        }
                    }
                    return .next(.progress(0))
                case let .progress(value):
                    return .next(.progress(value * 0.2))
                case let .complete(thumb, video, keyFrame):
                    let (thumbResource, videoResource) = (LocalFileReferenceMediaResource(localFilePath: thumb, randomId: arc4random64(), isUniquelyReferencedTemporaryFile: true),
                                                          LocalFileReferenceMediaResource(localFilePath: video, randomId: arc4random64(), isUniquelyReferencedTemporaryFile: true))
                                        
                    return context.engine.peers.updatePeerPhoto(peerId: peerId, photo: context.engine.peers.uploadedPeerPhoto(resource: EngineMediaResource(thumbResource)), video: context.engine.peers.uploadedPeerVideo(resource: EngineMediaResource(videoResource)) |> map(Optional.init), videoStartTimestamp: keyFrame, mapResourceToAvatarSizes: { resource, representations in
                        return mapResourceToAvatarSizes(engine: context.engine, resource: resource, representations: representations)
                    }) |> map { result in
                        switch result {
                        case let .progress(current):
                            return .progress(0.2 + (current * 0.8))
                        default:
                            return result
                        }
                    }
                }
        }

        updatePhotoDisposable.set((updateSignal |> deliverOnMainQueue).start(next: { status in
            updateState { state -> GroupInfoState in
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
            updateState { (state) -> GroupInfoState in
                return state.withoutUpdatingPhotoState()
            }
        }, completed: {
            updateState { (state) -> GroupInfoState in
                return state.withoutUpdatingPhotoState()
            }
        }))

        
    }
    
    private func upgradeToSupergroup(needChat: Bool = true) -> (PeerId, @escaping () -> Void) -> Void {
        return { [weak self] upgradedPeerId, f in
            guard let `self` = self, let navigationController = self.pullNavigation() else {
                return
            }
            let context = self.context
            
            let signal = context.account.postbox.loadedPeerWithId(upgradedPeerId) |> deliverOnMainQueue
            
            _ = signal.start(next: { [navigationController] peer in
                var chatController: ChatController<Context>? = ChatController(context: context, chatLocation: .peer(upgradedPeerId))
                
                chatController!.navigationController = navigationController
                chatController!.loadViewIfNeeded(navigationController.bounds)
                
                var signal = chatController!.ready.get() |> filter {$0} |> take(1) |> ignoreValues
                
                var controller: PeerInfoController<Context>? = PeerInfoController(context: context, peer: peer)
                
                controller!.navigationController = navigationController
                controller!.loadViewIfNeeded(navigationController.bounds)
                
                let mainSignal = combineLatest(controller!.ready.get(), controller!.ready.get()) |> map { $0 && $1 } |> filter {$0} |> take(1) |> ignoreValues
                
                signal = combineLatest(queue: .mainQueue(), signal, mainSignal) |> ignoreValues
                
                _ = signal.start(completed: { [weak navigationController] in
                    navigationController?.removeAll()
                    navigationController?.push(chatController!, false, style: ViewControllerStyle.none)
                    navigationController?.push(controller!, false, style: ViewControllerStyle.none)
                    
                    chatController = nil
                    controller = nil
                    f()
                })
            })
        }
    }
    
    func addMember(_ canInviteByLink: Bool) -> Void {
        
        let upgradeToSupergroup = self.upgradeToSupergroup()
        
        let context = self.context
        let peerId = self.peerId
        let updateState:((GroupInfoState)->GroupInfoState)->Void = { [weak self] f in
            self?.updateState(f)
        }
        let confirmationImpl:([PeerId])->Signal<Bool, NoError> = { peerIds in
            if let first = peerIds.first, peerIds.count == 1 {
                return context.account.postbox.loadedPeerWithId(first) |> deliverOnMainQueue |> mapToSignal { peer in
                    return verifyAlertSignal(for: context.window, information: strings().peerInfoConfirmAddMember(peer.displayTitle), ok: strings().peerInfoConfirmAdd) |> map { $0 == .basic }
                }
            }
            return verifyAlertSignal(for: context.window, information: strings().peerInfoConfirmAddMembers1Other(peerIds.count), ok: strings().peerInfoConfirmAdd) |> map { $0 == .basic }
        }

        
        
        let addMember = getCachedDataView(peerId: peerId, postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue |> mapToSignal{ [self] cachedData -> Signal<Result, NoError> in
            
            var excludePeerIds:[PeerId] = []
            if let cachedData = cachedData as? CachedChannelData {
                excludePeerIds = Array(cachedData.peerIds)
            } else if let cachedData = cachedData as? CachedGroupData {
                excludePeerIds = Array(cachedData.peerIds)
            }
            
            var linkInvation: ((Int)->Void)? = nil
            if canInviteByLink {
                linkInvation = { [weak self] _  in
                    self?.invation()
                }
            }
            
            
            return selectModalPeers(window: context.window, context: context, title: strings().peerInfoAddMember, settings: [.contacts, .remote], excludePeerIds:excludePeerIds, limit: peerId.namespace == Namespaces.Peer.CloudGroup ? 1 : 100, confirmation: confirmationImpl, linkInvation: linkInvation)
                |> deliverOnMainQueue
                |> mapToSignal { memberIds -> Signal<Result, NoError> in
                    return context.account.postbox.multiplePeersView(memberIds + [peerId])
                        |> take(1)
                        |> deliverOnMainQueue
                        |> mapToSignal { view -> Signal<Result, NoError> in
                            updateState { state in
                                var state = state
                                for (memberId, peer) in view.peers {
                                    var found = false
                                    for participant in state.temporaryParticipants {
                                        if participant.peer.id == memberId {
                                            found = true
                                            break
                                        }
                                    }
                                    if !found {
                                        let timestamp = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
                                        var temporaryParticipants = state.temporaryParticipants
                                        temporaryParticipants.append(TemporaryParticipant(peer: peer, presence: view.presences[memberId], timestamp: timestamp))
                                        state = state.withUpdatedTemporaryParticipants(temporaryParticipants)
                                    }
                                }
                                
                                return state
                                
                            }
                            
                            if let peer = view.peers[peerId] {
                                if peer.isGroup, let memberId = memberIds.first {
                                    return context.engine.peers.addGroupMember(peerId: peerId, memberId: memberId)
                                        |> deliverOnMainQueue
                                        |> map { _ in return .init(success: [memberId], failed: []) }
                                        |> `catch` { error -> Signal<Result, NoError> in
                                            return .single(.init(success: [], failed: [(memberId, error.channelError)]))
                                    }
                                    
                                } else if peer.isSupergroup {
                                    return context.peerChannelMemberCategoriesContextsManager.addMembersAllowPartial(peerId: peerId, memberIds: memberIds) |> map { failed in
                                        let success = memberIds.filter { memberId in
                                            return !failed.contains(where: { $0.0 == memberId })
                                        }
                                        return .init(success: success, failed: failed)
                                    } |> deliverOnMainQueue
                                }
                            }
                            
                            return .complete()
                    }
            }
        }
        
        addMemberDisposable.set(addMember.start(next: { result in
            updateState { state in
                var successfullyAddedParticipantIds = state.successfullyAddedParticipantIds

                for memberId in result.success {
                    successfullyAddedParticipantIds.insert(memberId)
                }
                return state.withUpdatedTemporaryParticipants([]).withUpdatedSuccessfullyAddedParticipantIds(successfullyAddedParticipantIds)
            }
            var forbidden: [TelegramForbiddenInvitePeer] = []
            
            for (_, failed) in result.failed {
                switch failed {
                case let .restricted(peer):
                    if let peer {
                        forbidden.append(peer)
                    }
                default:
                    break
                }
            }
            
            let failed = result.failed.filter {
                switch $0.1 {
                case .notMutualContact, .limitExceeded, .tooMuchJoined, .generic, .kicked, .restricted:
                    return true
                default:
                    return false
                }
            }
            let botFailed = result.failed.filter {
                switch $0.1 {
                case .bot:
                    return true
                default:
                    return false
                }
            }
            if !failed.isEmpty {
                showInvitePrivacyLimitedController(context: context, peerId: peerId, ids: failed.map { $0.0 }, forbidden: forbidden)
            } else if let first = botFailed.first {
                if case let .bot(memberId) = first.1 {
                    let _ = (context.account.postbox.transaction { transaction in
                        return transaction.getPeer(peerId)
                        }
                        |> deliverOnMainQueue).start(next: { peer in
                            guard let peer = peer as? TelegramChannel else {
                                alert(for: context.window, info: strings().unknownError)
                                return
                            }
                            if peer.hasPermission(.addAdmins) {
                                verifyAlert_button(for: context.window, information: strings().channelAddBotErrorHaveRights, ok: strings().channelAddBotAsAdmin, successHandler: { _ in
                                    showModal(with: ChannelAdminModalController(context, peerId: peerId, adminId: memberId, initialParticipant: nil, updated: { _ in }, upgradedToSupergroup: upgradeToSupergroup), for: context.window)
                                })
                            } else {
                                alert(for: context.window, info: strings().channelAddBotErrorHaveRights)
                            }
                        })
                }
            }
        }))
        
    }
    
    
    func restrict(_ participant: ChannelParticipant) -> Void {
        
        let context = self.context
        let peerId = self.peerId
        
        PeerInfoNavigationHooks.shared.showRestrictMember(context, peerId, participant.peerId, participant, { updatedRights in
            _ = context.peerChannelMemberCategoriesContextsManager.updateMemberBannedRights(peerId: peerId, memberId: participant.peerId, bannedRights: updatedRights).start()
        })
    }
    
    func promote(_ participant: ChannelParticipant) -> Void {
        showModal(with: ChannelAdminModalController(context, peerId: peerId, adminId: participant.peerId, initialParticipant: participant, updated: { _ in }, upgradedToSupergroup: self.upgradeToSupergroup()), for: context.window)
    }
    
    func removePeer(_ memberId:PeerId) -> Void {
        
        let context = self.context
        let peerId = self.peerId
        let updateState:((GroupInfoState)->GroupInfoState)->Void = { [weak self] f in
            self?.updateState(f)
        }
        
        
        
        
        let signal = context.account.postbox.loadedPeerWithId(memberId)
            |> deliverOnMainQueue
            |> mapToSignal { peer -> Signal<Bool, NoError> in
                let result = ValuePromise<Bool>()
                result.set(true)
                return result.get()
            }
            |> mapToSignal { value -> Signal<Void, NoError> in
                if value {
                    updateState { state in
                        var temporaryParticipants = state.temporaryParticipants
                        for i in 0 ..< state.temporaryParticipants.count {
                            if state.temporaryParticipants[i].peer.id == memberId {
                                temporaryParticipants.remove(at: i)
                                break
                            }
                        }
                        var successfullyAddedParticipantIds = state.successfullyAddedParticipantIds
                        successfullyAddedParticipantIds.remove(memberId)
                        
                        var removingParticipantIds = state.removingParticipantIds
                        removingParticipantIds.insert(memberId)
                        
                        return state.withUpdatedTemporaryParticipants(temporaryParticipants).withUpdatedSuccessfullyAddedParticipantIds(successfullyAddedParticipantIds).withUpdatedRemovingParticipantIds(removingParticipantIds)
                    }
                    
                    if peerId.namespace == Namespaces.Peer.CloudChannel {
                        return context.peerChannelMemberCategoriesContextsManager.updateMemberBannedRights(peerId: peerId, memberId: memberId, bannedRights: TelegramChatBannedRights(flags: [.banReadMessages], untilDate: Int32.max))
                            |> afterDisposed {
                                Queue.mainQueue().async {
                                    updateState { state in
                                        var removingParticipantIds = state.removingParticipantIds
                                        removingParticipantIds.remove(memberId)
                                        
                                        return state.withUpdatedRemovingParticipantIds(removingParticipantIds)
                                    }
                                }
                        }
                    }
                    
                    return context.engine.peers.removePeerMember(peerId: peerId, memberId: memberId)
                        |> deliverOnMainQueue
                        |> afterDisposed {
                            updateState { state in
                                var removingParticipantIds = state.removingParticipantIds
                                removingParticipantIds.remove(memberId)
                                
                                return state.withUpdatedRemovingParticipantIds(removingParticipantIds)
                            }
                    }
                } else {
                    return .complete()
                }
        }
        removeMemberDisposable.set(signal.start())
    }

    
    func setGroupStickerset() {
        manageStep?(.openStickers)
        pullNavigation()?.push(PeerInfoNavigationHooks.shared.makeGroupStickerSetController(context, peerId))
        
    }
    
    func updateGroupPhoto(_ custom: NSImage?, control: Control?) {
        let context = self.context
        let updatePhoto:(Signal<NSImage, NoError>) -> Void = { [weak self] image in
            let signal = image |> mapToSignal { image in
                return putToTemp(image: image, compress: true)
            } |> deliverOnMainQueue
            _ = signal.start(next: { [weak self] path in
                guard let controller = EditImageModalController(URL(fileURLWithPath: path), context: context, settings: .disableSizes(dimensions: .square, circle: true)) else { return }
                showModal(with: controller, for: context.window, animationType: .scaleCenter)
                _ = (controller.result |> take(1)).start(next: { [weak self] url, _ in
                    self?.updatePhoto(url.path)
                })
                controller.onClose = {
                    removeFile(at: path)
                }
            })
        }
        if let image = custom {
            updatePhoto(.single(image))
        } else {
            
            let context = self.context
            let updateVideo = self.updateVideo
                        
            let makeVideo:(MediaObjectToAvatar)->Void = { object in
                makeAvatarVideo(object, updatePhoto: updatePhoto, updateVideo: updateVideo)
            }

            
            var items:[ContextMenuItem] = []
            
            items.append(.init(strings().editAvatarPhotoOrVideo, handler: {
                filePanel(with: photoExts + videoExts, allowMultiple: false, canChooseDirectories: false, for: context.window, completion: { paths in
                    if let path = paths?.first, let image = NSImage(contentsOfFile: path) {
                        updatePhoto(.single(image))
                    } else if let path = paths?.first {
                        selectVideoAvatar(context: context, path: path, localize: strings().videoAvatarChooseDescGroup, signal: { signal in
                            updateVideo(signal)
                        })
                    }
                })
            }, itemImage: MenuAnimation.menu_shared_media.value))
            
            items.append(.init(strings().editAvatarCustomize, handler: {
                showModal(with: AvatarConstructorController(context, target: .avatar, videoSignal: makeVideo), for: context.window)
            }, itemImage: MenuAnimation.menu_view_sticker_set.value))
            
            if let control = control, let event = NSApp.currentEvent {
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
                        selectVideoAvatar(context: context, path: path, localize: strings().videoAvatarChooseDescGroup, signal: { signal in
                            updateVideo(signal)
                        })
                    }
                })
            }
        }
    }
    
    deinit {
        removeMemberDisposable.dispose()
        addMemberDisposable.dispose()
        updatePeerNameDisposable.dispose()
        updatePhotoDisposable.dispose()
        reportPeerDisposable.dispose()
        visibilitySetupDisposable.dispose()
    }
    
}

class GroupInfoState: PeerInfoState {
    
    let editingState: GroupInfoEditingState?
    let updatingName: String?
    let temporaryParticipants: [TemporaryParticipant]
    let successfullyAddedParticipantIds: Set<PeerId>
    let removingParticipantIds: Set<PeerId>
    let updatingPhotoState:PeerInfoUpdatingPhotoState?
    
    let savingData: Bool
    
    let hasShowMoreButton: Bool?
    
    init(editingState: GroupInfoEditingState?, updatingName:String?, temporaryParticipants:[TemporaryParticipant], successfullyAddedParticipantIds:Set<PeerId>, removingParticipantIds:Set<PeerId>, savingData: Bool, updatingPhotoState:PeerInfoUpdatingPhotoState?, hasShowMoreButton: Bool?) {
        self.editingState = editingState
        self.updatingName = updatingName
        self.temporaryParticipants = temporaryParticipants
        self.successfullyAddedParticipantIds = successfullyAddedParticipantIds
        self.removingParticipantIds = removingParticipantIds
        self.savingData = savingData
        self.updatingPhotoState = updatingPhotoState
        self.hasShowMoreButton = hasShowMoreButton
    }
    
    override init() {
        self.editingState = nil
        self.updatingName = nil
        self.temporaryParticipants = []
        self.successfullyAddedParticipantIds = Set()
        self.removingParticipantIds = Set()
        self.savingData = false
        self.updatingPhotoState = nil
        self.hasShowMoreButton = true
    }
    
    func isEqual(to: PeerInfoState) -> Bool {
        if let to = to as? GroupInfoState {
            return self == to
        }
        return false
    }
    
    func withUpdatedEditingState(_ editingState: GroupInfoEditingState?) -> GroupInfoState {
        return GroupInfoState(editingState: editingState, updatingName: self.updatingName, temporaryParticipants: self.temporaryParticipants, successfullyAddedParticipantIds: self.successfullyAddedParticipantIds, removingParticipantIds: self.removingParticipantIds, savingData: self.savingData, updatingPhotoState: self.updatingPhotoState, hasShowMoreButton: self.hasShowMoreButton)
    }
    
    
    func withUpdatedTemporaryParticipants(_ temporaryParticipants: [TemporaryParticipant]) -> GroupInfoState {
        return GroupInfoState(editingState: self.editingState, updatingName: self.updatingName, temporaryParticipants: temporaryParticipants, successfullyAddedParticipantIds: self.successfullyAddedParticipantIds, removingParticipantIds: self.removingParticipantIds, savingData: self.savingData, updatingPhotoState: self.updatingPhotoState, hasShowMoreButton: self.hasShowMoreButton)
    }
    
    func withUpdatedSuccessfullyAddedParticipantIds(_ successfullyAddedParticipantIds: Set<PeerId>) -> GroupInfoState {
        return GroupInfoState(editingState: self.editingState, updatingName: self.updatingName, temporaryParticipants: self.temporaryParticipants, successfullyAddedParticipantIds: successfullyAddedParticipantIds, removingParticipantIds: self.removingParticipantIds, savingData: self.savingData, updatingPhotoState: self.updatingPhotoState, hasShowMoreButton: self.hasShowMoreButton)
    }
    
    func withUpdatedRemovingParticipantIds(_ removingParticipantIds: Set<PeerId>) -> GroupInfoState {
        return GroupInfoState(editingState: self.editingState, updatingName: self.updatingName, temporaryParticipants: self.temporaryParticipants, successfullyAddedParticipantIds: self.successfullyAddedParticipantIds, removingParticipantIds: removingParticipantIds, savingData: self.savingData, updatingPhotoState: self.updatingPhotoState, hasShowMoreButton: self.hasShowMoreButton)
    }
    
    func withUpdatedSavingData(_ savingData: Bool) -> GroupInfoState {
        return GroupInfoState(editingState: self.editingState, updatingName: self.updatingName, temporaryParticipants: self.temporaryParticipants, successfullyAddedParticipantIds: self.successfullyAddedParticipantIds, removingParticipantIds: self.removingParticipantIds, savingData: savingData, updatingPhotoState: self.updatingPhotoState, hasShowMoreButton: self.hasShowMoreButton)
    }
    
    func withUpdatedUpdatingPhotoState(_ f: (PeerInfoUpdatingPhotoState?) -> PeerInfoUpdatingPhotoState?) -> GroupInfoState {
        return GroupInfoState(editingState: self.editingState, updatingName: self.updatingName, temporaryParticipants: self.temporaryParticipants, successfullyAddedParticipantIds: self.successfullyAddedParticipantIds, removingParticipantIds: self.removingParticipantIds, savingData: self.savingData, updatingPhotoState: f(self.updatingPhotoState), hasShowMoreButton: self.hasShowMoreButton)
    }
    func withoutUpdatingPhotoState() -> GroupInfoState {
        return GroupInfoState(editingState: self.editingState, updatingName: self.updatingName, temporaryParticipants: self.temporaryParticipants, successfullyAddedParticipantIds: self.successfullyAddedParticipantIds, removingParticipantIds: self.removingParticipantIds, savingData: self.savingData, updatingPhotoState: nil, hasShowMoreButton: self.hasShowMoreButton)
    }
    func withUpdatedHasShowMoreButton(_ hasShowMoreButton: Bool?) -> GroupInfoState {
        return GroupInfoState(editingState: self.editingState, updatingName: self.updatingName, temporaryParticipants: self.temporaryParticipants, successfullyAddedParticipantIds: self.successfullyAddedParticipantIds, removingParticipantIds: self.removingParticipantIds, savingData: self.savingData, updatingPhotoState: self.updatingPhotoState, hasShowMoreButton: hasShowMoreButton)
    }
    
}


enum GroupInfoMemberStatus : Equatable {
    case member
    case creator(rank: String)
    case admin(rank: String)
    case memberTag(rank: String)
}

private struct GroupPeerEntryStableId: PeerInfoEntryStableId {
    let peerId: PeerId
    
    func isEqual(to: PeerInfoEntryStableId) -> Bool {
        if let to = to as? GroupPeerEntryStableId, to.peerId == self.peerId {
            return true
        } else {
            return false
        }
    }
    
    var hashValue: Int {
        return self.peerId.hashValue
    }
}



enum GroupInfoEntry<Context: AccountContextProtocol>: PeerInfoEntry {
    case info(section:Int, view: PeerView, editingState: Bool, updatingPhotoState:PeerInfoUpdatingPhotoState?, viewType: GeneralViewType)
    case setTitle(section:Int, text: String, viewType: GeneralViewType)
    case scam(section:Int, title: String, text: String, viewType: GeneralViewType)
    case about(section:Int, text: String, viewType: GeneralViewType)
    case addressName(section:Int, name:[UserInfoAddress], viewType: GeneralViewType)
    case verifiedInfo(sectionId: Int, value: PeerVerification?, viewType: GeneralViewType)
    case peerId(section:Int, value: String, viewType: GeneralViewType)
    case sharedMedia(section:Int, viewType: GeneralViewType)
    case balance(section: Int, stars: String, canSeeStars: Bool, viewType: GeneralViewType)
    case notifications(section:Int, settings: PeerNotificationSettings?, viewType: GeneralViewType)
    case usersHeader(section:Int, count:Int, viewType: GeneralViewType)
    case addMember(section:Int, inviteViaLink: Bool, viewType: GeneralViewType)
    case groupTypeSetup(section:Int, isPublic: Bool, viewType: GeneralViewType)
    case autoDeleteMessages(section:Int, timer: CachedPeerAutoremoveTimeout?, viewType: GeneralViewType)
    case inviteLinks(section:Int, count: Int32, viewType: GeneralViewType)
    case requests(section:Int, count: Int32, viewType: GeneralViewType)
    case linkedChannel(section:Int, channel: Peer, subscribers: Int32?, viewType: GeneralViewType)
    case reactions(section:Int, text: String, allowedReactions: PeerAllowedReactions?, availableReactions: AvailableReactions?, viewType: GeneralViewType)
    case welcomeMessages(section: Int, enabled: Bool, viewType: GeneralViewType)
    case color(section: Int, peer: PeerEquatable, viewType: GeneralViewType)
    case groupDescriptionSetup(section:Int, text: String, viewType: GeneralViewType)
    case groupAboutDescription(section:Int, viewType: GeneralViewType)
    case groupStickerset(section:Int, packName: String, viewType: GeneralViewType)
    case preHistory(section:Int, enabled: Bool, viewType: GeneralViewType)
    case toggleForum(section:Int, enabled: Bool, convert: Bool, limit: TopicsLimitedReason?, viewType: GeneralViewType)
    case forumInfo(section:Int, text: String, viewType: GeneralViewType)
    case groupManagementInfoLabel(section:Int, text: String, viewType: GeneralViewType)
    case members(section:Int, count: Int32, viewType: GeneralViewType)
    case administrators(section:Int, count: String, viewType: GeneralViewType)
    case recentActions(section:Int, viewType: GeneralViewType)
    case permissions(section:Int, count: String, viewType: GeneralViewType)
    case blocked(section:Int, count:Int32?, viewType: GeneralViewType)
    case member(section:Int, index: Int, peerId: PeerId, peer: Peer?, presence: PeerPresence?, activity: PeerInputActivity?, stories: PeerStoryStats?, memberStatus: GroupInfoMemberStatus, editing: ShortPeerDeleting?, menuItems: [ContextMenuItem], enabled:Bool, viewType: GeneralViewType, badgeAction: ((NSView)->Void)? = nil)
    case showMore(section:Int, index: Int, viewType: GeneralViewType)
    case leave(section:Int, text: String, viewType: GeneralViewType)
    case media(section:Int, controller: PeerMediaController<Context>, isVisible: Bool, viewType: GeneralViewType)
    case addToCommunity(section: Int, viewType: GeneralViewType)
    case community(section: Int, communityId: PeerId, viewType: GeneralViewType)
    case removeFromCommunity(section: Int, communityId: PeerId, viewType: GeneralViewType)
    case section(Int)
    
    func withUpdatedViewType(_ viewType: GeneralViewType) -> GroupInfoEntry {
        switch self {
        case let .info(section, view, editingState, updatingPhotoState, _): return .info(section: section, view: view, editingState: editingState, updatingPhotoState: updatingPhotoState, viewType: viewType)
        case let .setTitle(section, text, _): return .setTitle(section: section, text: text, viewType: viewType)
        case let .scam(section, title, text, _): return .scam(section: section, title: title, text: text, viewType: viewType)
        case let .about(section, text, _): return .about(section: section, text: text, viewType: viewType)
        case let .addressName(section, name, _): return .addressName(section: section, name: name, viewType: viewType)
        case let .peerId(section, value, _): return .peerId(section: section, value: value, viewType: viewType)
        case let .sharedMedia(section, _): return .sharedMedia(section: section, viewType: viewType)
        case let .balance(section, stars, canSeeStars, _): return .balance(section: section, stars: stars, canSeeStars: canSeeStars, viewType: viewType)
        case let .notifications(section, settings, _): return .notifications(section: section, settings: settings, viewType: viewType)
        case let .usersHeader(section, count, _): return .usersHeader(section: section, count: count, viewType: viewType)
        case let .verifiedInfo(sectionId, verification, _): return .verifiedInfo(sectionId: sectionId, value: verification, viewType: viewType)
        case let .addMember(section, inviteViaLink, _): return .addMember(section: section, inviteViaLink: inviteViaLink, viewType: viewType)
        case let .groupTypeSetup(section, isPublic, _): return .groupTypeSetup(section: section, isPublic: isPublic, viewType: viewType)
        case let .autoDeleteMessages(section, timer, _): return .autoDeleteMessages(section: section, timer: timer, viewType: viewType)
        case let .inviteLinks(section, count, _): return .inviteLinks(section: section, count: count, viewType: viewType)
        case let .requests(section, count, _): return .requests(section: section, count: count, viewType: viewType)
        case let .reactions(section, text, allowedReactions, availableReactions, _): return .reactions(section: section, text: text, allowedReactions: allowedReactions, availableReactions: availableReactions, viewType: viewType)
        case let .welcomeMessages(section, enabled, _): return .welcomeMessages(section: section, enabled: enabled, viewType: viewType)
        case let .color(section, peer, _): return .color(section: section, peer: peer, viewType: viewType)
        case let .linkedChannel(section, channel, subscriber, _): return .linkedChannel(section: section, channel: channel, subscribers: subscriber, viewType: viewType)
        case let .groupDescriptionSetup(section, text, _): return .groupDescriptionSetup(section: section, text: text, viewType: viewType)
        case let .groupAboutDescription(section, _): return .groupAboutDescription(section: section, viewType: viewType)
        case let .groupStickerset(section, packName, _): return .groupStickerset(section: section, packName: packName, viewType: viewType)
        case let .preHistory(section, enabled, _): return .preHistory(section: section, enabled: enabled, viewType: viewType)
        case let .toggleForum(section, enabled, convert, limit, _): return .toggleForum(section: section, enabled: enabled, convert: convert, limit: limit, viewType: viewType)
        case let .forumInfo(section, text, _): return .forumInfo(section: section, text: text, viewType: viewType)
        case let .groupManagementInfoLabel(section, text, _): return .groupManagementInfoLabel(section: section, text: text, viewType: viewType)
        case let .members(section, count, _): return .members(section: section, count: count, viewType: viewType)
        case let .administrators(section, count, _): return .administrators(section: section, count: count, viewType: viewType)
        case let .recentActions(section, _): return .recentActions(section: section, viewType: viewType)
        case let .permissions(section, count, _): return .permissions(section: section, count: count, viewType: viewType)
        case let .blocked(section, count, _): return .blocked(section: section, count: count, viewType: viewType)
        case let .member(section, index, peerId, peer, presence, activity, stories, memberStatus, editing, menuItems, enabled, _, badgeAction): return .member(section: section, index: index, peerId: peerId, peer: peer, presence: presence, activity: activity, stories: stories, memberStatus: memberStatus, editing: editing, menuItems: menuItems, enabled: enabled, viewType: viewType, badgeAction: badgeAction)
        case let .showMore(section, index, _): return .showMore(section: section, index: index, viewType: viewType)
        case let .leave(section, text, _): return  .leave(section: section, text: text, viewType: viewType)
        case let .media(section, controller, isVisible, _): return  .media(section: section, controller: controller, isVisible: isVisible, viewType: viewType)
        case let .addToCommunity(section, _): return .addToCommunity(section: section, viewType: viewType)
        case let .community(section, communityId, _): return .community(section: section, communityId: communityId, viewType: viewType)
        case let .removeFromCommunity(section, communityId, _): return .removeFromCommunity(section: section, communityId: communityId, viewType: viewType)
        case .section: return self
        }
    }
    
    func isEqual(to: PeerInfoEntry) -> Bool {
        guard let entry = to as? GroupInfoEntry else {
            return false
        }
        
        switch self {
        case let .info(lhsSection, lhsPeerView, lhsEditingState, lhsUpdatingPhotoState, lhsViewType):
            switch entry {
            case let .info(rhsSection, rhsPeerView, rhsEditingState, rhsUpdatingPhotoState, rhsViewType):
                
                if lhsUpdatingPhotoState != rhsUpdatingPhotoState {
                    return false
                }
                if lhsSection != rhsSection {
                    return false
                }
                if lhsViewType != rhsViewType {
                    return false
                }
                
                if lhsEditingState != rhsEditingState {
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
                } else if (lhsPeer == nil) != (rhsPeer != nil) {
                    return false
                }
                
                if let lhsNotificationSettings = lhsNotificationSettings, let rhsNotificationSettings = rhsNotificationSettings {
                    if !lhsNotificationSettings.isEqual(to: rhsNotificationSettings) {
                        return false
                    }
                } else if (lhsNotificationSettings == nil) != (rhsNotificationSettings == nil) {
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
        case let .setTitle(section, text, viewType):
            if case .setTitle(section, text, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .addressName(section, addressName, viewType):
            if case .addressName(section, addressName, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .peerId(section, value, viewType):
            if case .peerId(section, value, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .scam(section, title, text, viewType):
            if case .scam(section, title, text, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .about(section, text, viewType):
            if case .about(section, text, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .verifiedInfo(sectionId, value, viewType):
            if case .verifiedInfo(sectionId, value, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .sharedMedia(sectionId, viewType):
            if case .sharedMedia(sectionId, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .balance(section, stars, canSeeStars, viewType):
            if case .balance(section, stars, canSeeStars, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .preHistory(sectionId, enabled, viewType):
            if case .preHistory(sectionId, enabled, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .toggleForum(sectionId, enabled, convert, limit, viewType):
            if case .toggleForum(sectionId, enabled, convert, limit, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .forumInfo(sectionId, text, viewType):
            if case .forumInfo(sectionId, text, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .members(section, count, viewType):
            if case .members(section, count, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .administrators(section, count, viewType):
            if case .administrators(section, count, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .recentActions(section, viewType):
            if case .recentActions(section, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .permissions(section, count, viewType):
            if case .permissions(section, count, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .blocked(section, count, viewType):
            if case .blocked(section, count, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .groupStickerset(sectionId, packName, viewType):
            if case .groupStickerset(sectionId, packName, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .notifications(section, lhsSettings, viewType):
            switch entry {
            case .notifications(section, let rhsSettings, viewType):
                
                if let lhsSettings = lhsSettings, let rhsSettings = rhsSettings {
                    return lhsSettings.isEqual(to: rhsSettings)
                } else if (lhsSettings != nil) != (rhsSettings != nil) {
                    return false
                }
                return true
            default:
                return false
            }
        case let .groupTypeSetup(sectionId, isPublic, viewType):
            if case .groupTypeSetup(sectionId, isPublic, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .autoDeleteMessages(sectionId, value, viewType):
            if case .autoDeleteMessages(sectionId, value, viewType) = entry {
                return true
            } else {
                return false
            }

        case let .inviteLinks(sectionId, count, viewType):
            if case .inviteLinks(sectionId, count, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .reactions(sectionId, text, allowedReactions, availableReactions, viewType):
            if case .reactions(sectionId, text, allowedReactions, availableReactions, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .welcomeMessages(sectionId, enabled, viewType):
            if case .welcomeMessages(sectionId, enabled, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .color(sectionId, peer, viewType):
            if case .color(sectionId, peer, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .requests(sectionId, count, viewType):
            if case .requests(sectionId, count, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .linkedChannel(sectionId, lhsChannel, subscribers, viewType):
            if case .linkedChannel(sectionId, let rhsChannel, subscribers, viewType) = entry {
                return lhsChannel.isEqual(rhsChannel)
            } else {
                return false
            }
        case let .groupDescriptionSetup(section, text, viewType):
            if case .groupDescriptionSetup(section, text, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .groupAboutDescription(section, viewType):
            if case .groupAboutDescription(section, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .groupManagementInfoLabel(section, text, viewType):
            if case .groupManagementInfoLabel(section, text, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .usersHeader(section, count, viewType):
            if case .usersHeader(section, count, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .addMember(section, inviteViaLink, viewType):
            if case .addMember(section, inviteViaLink, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .member(lhsSection, lhsIndex, lhsPeerId, lhsPeer, lhsPresence, lhsActivity, lhsStories, lhsMemberStatus, lhsEditing, lhsMenuItems, lhsEnabled, lhsViewType, _):
            if case let .member(rhsSection, rhsIndex, rhsPeerId, rhsPeer, rhsPresence, rhsActivity, rhsStories, rhsMemberStatus, rhsEditing, rhsMenuItems, rhsEnabled, rhsViewType, _) = entry {
                if lhsIndex != rhsIndex {
                    return false
                }
                if lhsSection != rhsSection {
                    return false
                }
                if lhsMemberStatus != rhsMemberStatus {
                    return false
                }
                if lhsPeerId != rhsPeerId {
                    return false
                }
                if lhsEnabled != rhsEnabled {
                    return false
                }
                if lhsViewType != rhsViewType {
                    return false
                }
                if lhsStories != rhsStories {
                    return false
                }
                if let lhsPeer = lhsPeer, let rhsPeer = rhsPeer {
                    if !lhsPeer.isEqual(rhsPeer) {
                        return false
                    }
                } else if (lhsPeer != nil) != (rhsPeer != nil) {
                    return false
                }
                if lhsActivity != rhsActivity {
                    return false
                }
                if let lhsPresence = lhsPresence, let rhsPresence = rhsPresence {
                    if !lhsPresence.isEqual(to: rhsPresence) {
                        return false
                    }
                } else if (lhsPresence != nil) != (rhsPresence != nil) {
                    return false
                }
                if lhsEditing != rhsEditing {
                    return false
                }
                if lhsMenuItems != rhsMenuItems {
                    return false
                }
                return true
            } else {
                return false
            }
        case let .showMore(sectionId, index, viewType):
            if case .showMore(sectionId, index, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .leave(sectionId, text, viewType):
            if case .leave(sectionId, text, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .media(sectionId, _, isVisible, viewType):
            if case .media(sectionId, _, isVisible, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .addToCommunity(section, viewType):
            if case .addToCommunity(section, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .community(section, communityId, viewType):
            if case .community(section, communityId, viewType) = entry {
                return true
            } else {
                return false
            }
        case let .removeFromCommunity(section, communityId, viewType):
            if case .removeFromCommunity(section, communityId, viewType) = entry {
                return true
            } else {
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
    
    var stableId: PeerInfoEntryStableId {
        switch self {
        case let .member(_, _, peerId, _, _, _, _, _, _, _, _, _, _):
            return GroupPeerEntryStableId(peerId: peerId)
        default:
            return IntPeerInfoEntryStableId(value: stableIndex)
        }
    }
    
    private var stableIndex: Int {
        switch self {
        case .info:
            return 0
        case .setTitle:
            return 1
        case .scam:
            return 2
        case .about:
            return 3
        case .addressName:
            return 4
        case .peerId:
            return 5
        case .groupDescriptionSetup:
            return 6
        case .groupAboutDescription:
            return 7
        case .notifications:
            return 8
        case .verifiedInfo:
            return 9
        case .sharedMedia:
            return 10
        case .balance:
            return 11
        case .groupTypeSetup:
            return 12
        case .members:
            return 13
        case .inviteLinks:
            return 14
        case .requests:
            return 15
        case .reactions:
            return 16
        case .color:
            return 17
        case .linkedChannel:
            return 19
        case .preHistory:
            return 20
        case .groupStickerset:
            return 21
        case .autoDeleteMessages:
            return 22
        case .groupManagementInfoLabel:
            return 23
        case .permissions:
            return 24
        case .blocked:
            return 25
        case .administrators:
            return 26
        case .recentActions:
            return 27
        case .toggleForum:
            return 28
        case .forumInfo:
            return 29
        case .usersHeader:
            return 30
        case .addMember:
            return 31
        case .member:
            fatalError("no stableIndex")
        case .showMore:
            return 32
        case .leave:
            return 33
        case .media:
            return 34
        case .addToCommunity:
            return 35
        case .community:
            return 36
        case .removeFromCommunity:
            return 37
        case .welcomeMessages:
            return 18
        case let .section(id):
            return (id + 1) * 100000 - id
        }
    }
    
    var sectionId: Int {
        switch self {
        case let .info(sectionId, _, _, _, _):
            return sectionId
        case let .scam(sectionId, _, _, _):
            return sectionId
        case let .about(sectionId, _, _):
            return sectionId
        case let .addressName(sectionId, _, _):
            return sectionId
        case let .peerId(sectionId, _, _):
            return sectionId
        case let .setTitle(sectionId, _, _):
            return sectionId
        case let .addMember(sectionId, _, _):
            return sectionId
        case let .notifications(sectionId, _, _):
            return sectionId
        case let .verifiedInfo(sectionId, _, _):
            return sectionId
        case let .sharedMedia(sectionId, _):
            return sectionId
        case let .balance(sectionId, _, _, _):
            return sectionId
        case let .groupTypeSetup(sectionId, _, _):
            return sectionId
        case let .autoDeleteMessages(sectionId, _, _):
            return sectionId
        case let .inviteLinks(sectionId, _, _):
            return sectionId
        case let .requests(sectionId, _, _):
            return sectionId
        case let .reactions(sectionId, _, _, _, _):
            return sectionId
        case let .welcomeMessages(sectionId, _, _):
            return sectionId
        case let .color(sectionId, _, _):
            return sectionId
        case let .linkedChannel(sectionId, _, _, _):
            return sectionId
        case let .preHistory(sectionId, _, _):
            return sectionId
        case let .toggleForum(sectionId, _, _, _, _):
            return sectionId
        case let .forumInfo(sectionId, _, _):
            return sectionId
        case let .groupStickerset(sectionId, _, _):
            return sectionId
        case let .administrators(sectionId, _, _):
            return sectionId
        case let .recentActions(sectionId, _):
            return sectionId
        case let .members(sectionId, _, _):
            return sectionId
        case let .permissions(sectionId, _, _):
            return sectionId
        case let .blocked(sectionId, _, _):
            return sectionId
        case let .groupDescriptionSetup(sectionId, _, _):
            return sectionId
        case let .groupAboutDescription(sectionId, _):
            return sectionId
        case let .groupManagementInfoLabel(sectionId, _, _):
            return sectionId
        case let .usersHeader(sectionId, _, _):
            return sectionId
        case let .member(sectionId, _, _, _, _, _, _, _, _, _, _, _, _):
            return sectionId
        case let .showMore(sectionId, _, _):
            return sectionId
        case let .leave(sectionId, _, _):
            return sectionId
        case let .media(sectionId, _, _, _):
            return sectionId
        case let .addToCommunity(sectionId, _):
            return sectionId
        case let .community(sectionId, _, _):
            return sectionId
        case let .removeFromCommunity(sectionId, _, _):
            return sectionId
        case let .section(sectionId):
            return sectionId
        }
    }

    var sortIndex: Int {
        switch self {
        case let .info(sectionId, _, _, _, _):
            return (sectionId * 100000) + stableIndex
        case let .scam(sectionId, _, _, _):
            return (sectionId * 100000) + stableIndex
        case let .about(sectionId, _, _):
            return (sectionId * 100000) + stableIndex
        case let .addressName(sectionId, _, _):
            return (sectionId * 100000) + stableIndex
        case let .peerId(sectionId, _, _):
            return (sectionId * 100000) + stableIndex
        case let .setTitle(sectionId, _, _):
            return (sectionId * 100000) + stableIndex
        case let .addMember(sectionId, _, _):
            return (sectionId * 100000) + stableIndex
        case let .notifications(sectionId, _, _):
            return (sectionId * 100000) + stableIndex
        case let .verifiedInfo(sectionId, _, _):
            return (sectionId * 100000) + stableIndex
        case let .sharedMedia(sectionId, _):
            return (sectionId * 100000) + stableIndex
        case let .balance(sectionId, _, _, _):
            return (sectionId * 100000) + stableIndex
        case let .groupTypeSetup(sectionId, _, _):
            return (sectionId * 100000) + stableIndex
        case let .autoDeleteMessages(sectionId, _, _):
            return (sectionId * 100000) + stableIndex
        case let .inviteLinks(sectionId, _, _):
            return (sectionId * 100000) + stableIndex
        case let .requests(sectionId, _, _):
            return (sectionId * 100000) + stableIndex
        case let .reactions(sectionId, _, _, _, _):
            return (sectionId * 100000) + stableIndex
        case let .welcomeMessages(sectionId, _, _):
            return (sectionId * 100000) + stableIndex
        case let .color(sectionId, _, _):
            return (sectionId * 100000) + stableIndex
        case let .linkedChannel(sectionId, _, _, _):
            return (sectionId * 100000) + stableIndex
        case let .preHistory(sectionId, _, _):
            return (sectionId * 100000) + stableIndex
        case let .toggleForum(sectionId, _, _, _, _):
            return (sectionId * 100000) + stableIndex
        case let .forumInfo(sectionId, _, _):
            return (sectionId * 100000) + stableIndex
        case let .groupStickerset(sectionId, _, _):
            return (sectionId * 100000) + stableIndex
        case let .members(sectionId, _, _):
            return (sectionId * 100000) + stableIndex
        case let .administrators(sectionId, _, _):
            return (sectionId * 100000) + stableIndex
        case let .recentActions(sectionId, _):
            return (sectionId * 100000) + stableIndex
        case let .permissions(sectionId, _, _):
            return (sectionId * 100000) + stableIndex
        case let .blocked(sectionId, _, _):
            return (sectionId * 100000) + stableIndex
        case let .groupDescriptionSetup(sectionId, _, _):
            return (sectionId * 100000) + stableIndex
        case let .groupAboutDescription(sectionId, _):
            return (sectionId * 100000) + stableIndex
        case let .groupManagementInfoLabel(sectionId, _, _):
            return (sectionId * 100000) + stableIndex
        case let .usersHeader(sectionId, _, _):
            return (sectionId * 100000) + stableIndex
        case let .member(sectionId, index, _, _, _, _, _, _, _, _, _, _, _):
            return (sectionId * 100000) + index + 200
        case let .showMore(sectionId, index, _):
            return (sectionId * 100000) + index + 200
        case let .leave(sectionId, _, _):
            return (sectionId * 100000) + stableIndex
        case let .media(sectionId, _, _, _):
            return (sectionId * 100000) + stableIndex
        case let .addToCommunity(sectionId, _):
            return (sectionId * 100000) + stableIndex
        case let .community(sectionId, _, _):
            return (sectionId * 100000) + stableIndex
        case let .removeFromCommunity(sectionId, _, _):
            return (sectionId * 100000) + stableIndex
        case let .section(sectionId):
            return (sectionId + 1) * 100000 - sectionId
        }
    }

    func isOrderedBefore(_ entry: PeerInfoEntry) -> Bool {
        guard let other = entry as? GroupInfoEntry else {
            return false
        }
        
        return self.sortIndex < other.sortIndex
    }
    
    func item<C: AccountContextProtocol>(initialSize:NSSize, arguments:PeerInfoArguments<C>) -> TableRowItem {
        let arguments = arguments as! GroupInfoArguments<Context>
        switch self {
        case let .info(_, peerView, editable, updatingPhotoState, viewType):
            return PeerInfoHeadItem(initialSize, stableId: stableId.hashValue, context: arguments.context, arguments: arguments, peerView: peerView, threadData: nil, threadId: nil, viewType: viewType, editing: editable, updatingPhotoState: updatingPhotoState, updatePhoto: arguments.updateGroupPhoto, giftsContext: arguments.getStarGiftsContext?())
        case let .scam(_, title, text, viewType):
            return TextAndLabelItem(initialSize, stableId:stableId.hashValue, label: title, copyMenuText: strings().textCopy, labelColor: theme.colors.redUI, text: text, context: arguments.context, viewType: viewType, detectLinks:false)
        case let .about(_, text, viewType):
            return TextAndLabelItem(initialSize, stableId: stableId.hashValue, label: strings().peerInfoInfo, copyMenuText: strings().textCopyLabelAbout, text: text, context: arguments.context, viewType: viewType, detectLinks: true, openInfo: { [weak arguments] peerId, toChat, postId, _ in
                if toChat {
                    arguments?.peerChat(peerId, postId: postId)
                } else {
                    arguments?.peerInfo(peerId)
                }
            }, hashtag: { hashtag in
                arguments.context.bindings.globalSearch(hashtag, arguments.peerId, nil)
            }, canTranslate: true)
        case let .addressName(_, value, viewType):
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
            
            return  TextAndLabelItem(initialSize, stableId: stableId.hashValue, label: strings().peerInfoSharelink, copyMenuText: strings().textCopyLabelShareLink, labelColor: theme.colors.text, text: text, context: arguments.context, viewType: viewType, detectLinks: true, isTextSelectable: value.count > 1, callback:{
                showModal(with: ShareModalController(ShareLinkObject(arguments.context, link: link)), for: arguments.context.window)
            }, selectFullWord: true, _copyToClipboard: {
                arguments.copy(link)
            }, linkInteractions: interactions, qrCode: { control in
                arguments.openQrStudio(from: control)
            })
        case let .peerId(_, value, viewType):
            return  TextAndLabelItem(initialSize, stableId: stableId.hashValue, label: "PEER ID", copyMenuText: strings().textCopyText, text: value, context: arguments.context, viewType: viewType, canCopy: true, _copyToClipboard: {
                arguments.copy(value)
            })
        case let .setTitle(_, text, viewType):
            return InputDataRowItem(initialSize, stableId: stableId.hashValue, mode: .plain, error: nil, viewType: viewType, currentText: text, placeholder: nil, inputPlaceholder: strings().peerInfoGroupTitlePleceholder, filter: { $0 }, updated: arguments.updateEditingName, limit: 255)
        case let .notifications(_, settings, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoNotifications, type: .switchable(!((settings as? TelegramPeerNotificationSettings)?.isMuted ?? true)), viewType: viewType, action: {})
        case let .verifiedInfo(_, value, viewType):
            let attr = NSMutableAttributedString()

            let text: String
            if let value {
                text = "\(clown) \(value.description)"
            } else {
                text = clown + " " + strings().peerInfoVerificationInfoGroup
            }
            
            attr.append(string: text, color: theme.colors.listGrayText, font: .normal(.text))
            if let value {
                InlineStickerItem.apply(to: attr, associatedMedia: [:], entities: [.init(range: 0..<2, type: .CustomEmoji(stickerPack: nil, fileId: value.iconFileId))], isPremium: true)
            } else {
                attr.insertEmbedded(.embedded(name: "Icon_Verified_Telegram", color: theme.colors.grayIcon, resize: false), for: clown)
            }
            ChatHistoryLink.detectLinks(attr, type: [.Links], color: theme.colors.listGrayText)

            return GeneralTextRowItem(initialSize, stableId: stableId.hashValue, text: .attributed(attr), viewType: viewType, context: arguments.context)
        case let .sharedMedia(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoSharedMedia, type: .next, viewType: viewType, action: arguments.sharedMedia)
        case let .balance(_, stars, canSeeStars, viewType):
            let icon = generateTonAndStarBalanceIcon(ton: nil, stars: stars)
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoBotEditBalance, icon: theme.icons.peerInfoBalance, type: .nextImage(icon), viewType: viewType, action: {
                arguments.openStats(canSeeTon: false, canSeeStars: canSeeStars)
            })
        case let .groupDescriptionSetup(section: _, text, viewType):
            return InputDataRowItem(initialSize, stableId: stableId.hashValue, mode: .plain, error: nil, viewType: viewType, currentText: text, placeholder: nil, inputPlaceholder: strings().peerInfoAboutPlaceholder, filter: { $0 }, updated: arguments.updateEditingDescriptionText, limit: 255)
        case let .preHistory(_, enabled, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoPreHistory, icon: theme.icons.profile_group_discussion, type: .context(enabled ? strings().peerInfoPreHistoryVisible : strings().peerInfoPreHistoryHidden), viewType: viewType, action: arguments.preHistorySetup)
        case let .toggleForum(_, enabled, convert, limit, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoForum, icon: theme.icons.profile_group_topics, type: .nextContext(""), viewType: viewType, action: {
                arguments.toggleForum(!enabled, convert, limit)
            }, enabled: limit == nil, autoswitch: false, disabledAction: {
                arguments.toggleForum(!enabled, convert, limit)
            })
        case let .forumInfo(_, text, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId.hashValue, text: text, viewType: viewType)
        case let .groupAboutDescription(_, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId.hashValue, text: strings().peerInfoSetAboutDescription, viewType: viewType)
        case let .groupTypeSetup(section: _, isPublic: isPublic, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoGroupType, icon: theme.icons.profile_group_type, type: .nextContext(isPublic ? strings().peerInfoGroupTypePublic : strings().peerInfoGroupTypePrivate), viewType: viewType, action: arguments.visibilitySetup)
        case let .autoDeleteMessages(section: _, timer, viewType):

            let text: String
            if let timer = timer {
                switch timer {
                case let .known(timer):
                    if let timer = timer?.effectiveValue {
                        text = autoremoveLocalized(Int(timer))
                    } else {
                        text = strings().peerInfoGroupTimerNever
                    }
                case .unknown:
                    text = ""
                }
            } else {
                text = ""
            }

            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoGroupAutoDeleteMessages, icon: theme.icons.profile_group_destruct, type: .nextContext(text), viewType: viewType, action: arguments.autoremoveController)
        case let .inviteLinks(_, count, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoInviteLinks, icon: theme.icons.profile_links, type: .nextContext(count > 0 ? "\(count)" : ""), viewType: viewType, action: arguments.openInviteLinks)
        case let .requests(_, count, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoMembersRequest, icon: theme.icons.profile_requests, type: .badge(count > 0 ? "\(count)" : "", theme.colors.redUI), viewType: viewType, action: arguments.openRequests)
        case let .reactions(_, text, allowedReactions, availableReactions, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoReactions, icon: theme.icons.profile_reactions, type: .nextContext(text), viewType: viewType, action: {
                arguments.openReactions(allowedReactions: allowedReactions, availableReactions: availableReactions)
            })
        case let .welcomeMessages(_, enabled, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().welcomeMessageTitle, icon: theme.icons.profile_group_welcome, type: .nextContext(enabled ? strings().peerInfoDirectMessagesOn : strings().peerInfoDirectMessagesOff), viewType: viewType, action: arguments.openWelcomeMessages)
        case let .linkedChannel(_, channel, _, viewType):
            let title: String
            if let address = channel.addressName {
                title = "@\(address)"
            } else {
                title = channel.displayTitle
            }
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoLinkedChannel, icon: theme.icons.profile_group_discussion, type: .nextContext(title), viewType: viewType, action: arguments.setupDiscussion)
        case let .color(_, peer, viewType):
            let level = (peer.peer as? TelegramChannel)?.approximateBoostLevel ?? 0
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoChannelAppearance, icon: theme.icons.profile_channel_color, type: .imageContext(PeerInfoNavigationHooks.shared.peerColorsLabelIcon(peer.peer, arguments.context), ""), viewType: viewType, action: {
                arguments.openNameColor(peer: peer.peer)
            }, afterNameImage: level == 0 ? generateDisclosureActionBoostLevelBadgeImage(text: strings().boostBadgeLevelPLus(1)) : nil)
        case let .groupStickerset(_, name, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoSetGroupStickersSet, icon: theme.icons.settingsStickers, type: .nextContext(name), viewType: viewType, action: arguments.setGroupStickerset)
        case let .permissions(section: _, count, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoPermissions, icon: theme.icons.peerInfoPermissions, type: .nextContext(count), viewType: viewType, action: arguments.blacklist)
        case let .blocked(section: _, count, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoBlackList, icon: theme.icons.peerInfoBanned, type: .nextContext(count != nil && count! > 0 ? "\(count!)" : ""), viewType: viewType, action: arguments.blocked)
        case let .members(_, count, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoMembers, icon: theme.icons.peerInfoMembers, type: .nextContext("\(count)"), viewType: viewType, action: arguments.members)
        case let .administrators(section: _, count, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoAdministrators, icon: theme.icons.peerInfoAdmins, type: .nextContext(count), viewType: viewType, action: arguments.admins)
        case let .recentActions(section: _, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoRecentActions, icon: theme.icons.peerInfoRecentActions, type: .next, viewType: viewType, action: arguments.eventLog)
        case let .usersHeader(section: _, count, viewType):
            var countValue = strings().peerInfoMembersHeaderOther(count)
            countValue = countValue.replacingOccurrences(of: "\(count)", with: count.separatedNumber)
            return GeneralTextRowItem(initialSize, stableId: stableId.hashValue, text: countValue, viewType: viewType)
        case let .addMember(_, inviteViaLink, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoAddMember, nameStyle: blueActionButton, type: .none, viewType: viewType, action: { [weak arguments] in
                arguments?.addMember(inviteViaLink)
            }, thumb: GeneralThumbAdditional(thumb: theme.icons.peerInfoAddMember, textInset: 52, thumbInset: 5))
        case let .member(_, _, _, peer, presence, inputActivity, stories, memberStatus, editing, menuItems, enabled, viewType, _):
            let label: String
            let badgeType: AdminBadgeType
            switch memberStatus {
            case let .creator(rank):
                label = rank
                badgeType = .owner
            case let .admin(rank):
                label = rank
                badgeType = .admin
            case let .memberTag(rank):
                label = rank
                badgeType = .none
            case .member:
                label = ""
                badgeType = .none
            }

            var string:String = strings().peerStatusRecently
            var color:NSColor = theme.colors.grayText

            if let peer = peer as? TelegramUser, let botInfo = peer.botInfo {
                string = botInfo.flags.contains(.hasAccessToChatHistory) ? strings().peerInfoBotStatusHasAccess : strings().peerInfoBotStatusHasNoAccess
            } else if let presence = presence as? TelegramUserPresence {
                let timestamp = CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970
                (string, _, color) = stringAndActivityForUserPresence(presence, timeDifference: arguments.context.timeDifference, relativeTo: Int32(timestamp))
            }

            let interactionType:ShortPeerItemInteractionType
            if let editing = editing {

                interactionType = .deletable(onRemove: { [weak arguments] memberId in
                    arguments?.removePeer(memberId)
                }, deletable: editing.editable)
            } else {
                interactionType = .plain
            }

            let generalType: GeneralInteractedType
            if badgeType != .none, !label.isEmpty {
                let badgeColor: NSColor = badgeType == .owner ? premiumGradient[1] : theme.colors.greenUI
                generalType = .contextColored(label, badgeColor)
            } else {
                generalType = .context(label)
            }

            return ShortPeerRowItem(initialSize, peer: peer!, account: arguments.context.account, context: arguments.context, stableId: stableId.hashValue, enabled: enabled, height: 50, photoSize: NSMakeSize(36, 36), titleStyle: ControlStyle(font: .medium(12.5), foregroundColor: theme.colors.text), statusStyle: ControlStyle(font: NSFont.normal(12.5), foregroundColor:color), status: string, inset: NSEdgeInsets(left: 20, right: 20), interactionType: interactionType, generalType: generalType, viewType: viewType, action: { [weak arguments] in
                arguments?.peerInfo(peer!.id)
            }, contextMenuItems: {
                return .single(menuItems)
            }, inputActivity: inputActivity, highlightVerified: true, story: stories?.subscriptionItem(peer!))
        case let .showMore(_, _, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().peerInfoShowMore, nameStyle: blueActionButton, type: .none, viewType: viewType, action: arguments.showMore, thumb: GeneralThumbAdditional(thumb: theme.icons.chatSearchUp, textInset: 52, thumbInset: 4))
        case let .leave(_, text, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: text, nameStyle: redActionButton, type: .none, viewType: viewType, action: {
                arguments.delete()
            })
        case let .media(_, controller, isVisible, viewType):
            return PeerMediaBlockRowItem(initialSize, stableId: stableId.hashValue, controller: controller, isVisible: isVisible, viewType: viewType)
        case let .addToCommunity(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().groupInfoAddGroupToCommunity, nameStyle: blueActionButton, type: .none, viewType: viewType, action: { [weak arguments] in
                arguments?.addToCommunity()
            })
        case let .community(_, communityId, viewType):
            return CommunityInfoRowItem(initialSize, stableId: stableId.hashValue, context: arguments.context, communityId: communityId, viewType: viewType, action: { [weak arguments] in
                arguments?.openCommunity(communityId)
            })
        case let .removeFromCommunity(_, communityId, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: strings().groupInfoRemoveGroupFromCommunity, nameStyle: redActionButton, type: .none, viewType: viewType, action: { [weak arguments] in
                arguments?.removeFromCommunity(communityId)
            })
        case .section:
            return GeneralRowItem(initialSize, height: 20, stableId: stableId.hashValue, viewType: .separator, backgroundColor: .clear)
        default:
            preconditionFailure()
        }
    }
}

enum GroupInfoSection : Int {
    case header = 1
    case info = 2
    case desc = 3
    case action = 4
    case addition = 5
    case type = 6
    case admin = 7
    case members = 8
    case destruct = 9
    case media = 10
}


func groupInfoEntries<Context: AccountContextProtocol>(view: PeerView, arguments: PeerInfoArguments<Context>, inputActivities: [PeerId: PeerInputActivity], channelMembers: [RenderedChannelParticipant] = [], mediaTabsData: PeerMediaTabsData, inviteLinksCount: Int32, joinRequestsCount: Int32, availableReactions: AvailableReactions?, revenueState: StarsRevenueStatsContextState?) -> [PeerInfoEntry] {
    var entries: [GroupInfoEntry<Context>] = []
    if let group = peerViewMainPeer(view), let arguments = arguments as? GroupInfoArguments<Context>, let state = arguments.state as? GroupInfoState {
        
        let access = group.groupAccess
        let canChangeInfo: Bool
        if let legacyGroup = group as? TelegramGroup {
            switch legacyGroup.role {
            case .creator:
                canChangeInfo = true
            case let .admin(rights, _):
                canChangeInfo = rights.rights.contains(.canChangeInfo)
            case .member:
                canChangeInfo = access.canEditGroupInfo
            }
        } else {
            canChangeInfo = access.canEditGroupInfo
        }
        
        
        var infoBlock: [GroupInfoEntry<Context>] = []
        func applyBlock(_ block:[GroupInfoEntry<Context>]) {
            var block = block.sorted { (p1, p2) -> Bool in
                return p1.isOrderedBefore(p2)
            }
            for (i, item) in block.enumerated() {
                block[i] = item.withUpdatedViewType(bestGeneralViewType(block, for: i))
            }
            entries.append(contentsOf: block)
        }
        
        entries.append(.info(section: GroupInfoSection.header.rawValue, view: view, editingState: state.editingState != nil, updatingPhotoState: state.updatingPhotoState, viewType: .singleItem))
        
        
        if let editingState = state.editingState {
            if canChangeInfo {
                infoBlock.append(GroupInfoEntry<Context>.setTitle(section: GroupInfoSection.header.rawValue, text: editingState.editingName ?? group.displayTitle, viewType: .singleItem))
                
                infoBlock.append(GroupInfoEntry<Context>.groupDescriptionSetup(section: GroupInfoSection.header.rawValue, text: editingState.editingDescriptionText, viewType: .singleItem))
                applyBlock(infoBlock)
               
                entries.append(GroupInfoEntry<Context>.groupAboutDescription(section:  GroupInfoSection.header.rawValue, viewType: .textBottomItem))

               
            } else {
                applyBlock(infoBlock)
            }
            
            
            if let group = view.peers[view.peerId] as? TelegramGroup {
                let hasAccess: Bool
                switch group.role {
                case .admin:
                    hasAccess = true
                case .creator:
                    hasAccess = true
                default:
                    hasAccess = false
                }
                if case .creator = group.role {

                }
                var actionBlock:[GroupInfoEntry<Context>] = []

                switch group.role {
                case .admin, .creator:
                    if case .creator = group.role {
                        actionBlock.append(.groupTypeSetup(section: GroupInfoSection.type.rawValue, isPublic: group.usernames.first(where: { $0.isActive }) != nil || group.username != nil, viewType: .singleItem))
                    }
                   
                    if case .creator = group.role {
                        actionBlock.append(.preHistory(section: GroupInfoSection.type.rawValue, enabled: false, viewType: .singleItem))
                    }
                    
                    let cachedGroupData = view.cachedData as? CachedGroupData
                                        
                    let text: String
                    if let allowed = cachedGroupData?.reactionSettings.knownValue?.allowedReactions, let availableReactions = availableReactions {
                        switch allowed {
                        case .all:
                            text = strings().peerInfoReactionsAll
                        case let .limited(count):
                            text = strings().peerInfoReactionsPart("\(count.count)", "\(availableReactions.enabled.count)")
                        case .empty:
                            text = strings().peerInfoReactionsDisabled
                        }
                    } else {
                        text = strings().peerInfoReactionsAll
                    }
                    
                    
                    if canChangeInfo {
                        actionBlock.append(.reactions(section: GroupInfoSection.type.rawValue, text: text, allowedReactions: cachedGroupData?.reactionSettings.knownValue?.allowedReactions, availableReactions: availableReactions, viewType: .singleItem))
                    }
                    if group.hasPermission(.manageWelcomeMessages) {
                        actionBlock.append(.welcomeMessages(section: GroupInfoSection.type.rawValue, enabled: cachedGroupData?.flags.contains(.hasWelcomeMessages) == true, viewType: .singleItem))
                    }
                    
                default:
                    break
                }

                if hasAccess {
                    let permissionList = internal_allPossibleGroupPermissionList
                    var activePermissionCount: Int?
                    if let defaultBannedRights = group.defaultBannedRights {
                        var count = 0
                        for (right, _) in permissionList {
                            if !defaultBannedRights.flags.contains(right) {
                                count += 1
                            }
                        }
                        activePermissionCount = count
                    }
                    
                    actionBlock.append(.inviteLinks(section: GroupInfoSection.type.rawValue, count: inviteLinksCount, viewType: .firstItem))
                    
                    
                    
                    if joinRequestsCount > 0 {
                        actionBlock.append(.requests(section: GroupInfoSection.type.rawValue, count: joinRequestsCount, viewType: .singleItem))
                    }

                    actionBlock.append(.permissions(section: GroupInfoSection.type.rawValue, count: activePermissionCount.flatMap({ "\($0 - 2)/\(permissionList.count - 2)" }) ?? "", viewType: .singleItem))
                    actionBlock.append(.administrators(section: GroupInfoSection.type.rawValue, count: "", viewType: .singleItem))
                    
                    
                    if access.isCreator, let cachedData = view.cachedData as? CachedGroupData {
                        
                        var minParticipants = 200
                        if let data = arguments.context.appConfiguration.data, let value = data["forum_upgrade_participants_min"] as? Double {
                            minParticipants = Int(value)
                        }
                        var topicsLimitedReason: TopicsLimitedReason?
                        let count = cachedData.participants?.participants.count ?? 0
                        if count < minParticipants {
                            topicsLimitedReason = .participants(minParticipants)
                        }
                        actionBlock.append(.toggleForum(section: GroupInfoSection.type.rawValue, enabled: false, convert: true, limit: topicsLimitedReason, viewType: .singleItem))
                    }
                    
                }
                
                applyBlock(actionBlock)
                
                if access.isCreator {
                    entries.append(.forumInfo(section: GroupInfoSection.type.rawValue, text: strings().peerInfoForumInfo, viewType: .textBottomItem))
                }

            } else if let channel = view.peers[view.peerId] as? TelegramChannel, let cachedChannelData = view.cachedData as? CachedChannelData {
                
                var actionBlock:[GroupInfoEntry<Context>] = []
                
                if access.isCreator {
                    actionBlock.append(.groupTypeSetup(section: GroupInfoSection.type.rawValue, isPublic: group.addressName != nil, viewType: .singleItem))
                }
                
                if access.canEditGroupInfo {
                                        
                    let text: String
                    if let allowed = cachedChannelData.reactionSettings.knownValue?.allowedReactions, let availableReactions = availableReactions {
                        switch allowed {
                        case .all:
                            text = strings().peerInfoReactionsAll
                        case let .limited(count):
                            text = strings().peerInfoReactionsPart("\(count.count)", "\(availableReactions.enabled.count)")
                        case .empty:
                            text = strings().peerInfoReactionsDisabled
                        }
                    } else {
                        text = strings().peerInfoReactionsAll
                    }
                    actionBlock.append(.color(section: GroupInfoSection.type.rawValue, peer: PeerEquatable(peer: channel), viewType: .singleItem))

                    actionBlock.append(.reactions(section: GroupInfoSection.type.rawValue, text: text, allowedReactions: cachedChannelData.reactionSettings.knownValue?.allowedReactions, availableReactions: availableReactions, viewType: .singleItem))
                }
                if channel.hasPermission(.manageWelcomeMessages) {
                    actionBlock.append(.welcomeMessages(section: GroupInfoSection.type.rawValue, enabled: cachedChannelData.flags.contains(.hasWelcomeMessages), viewType: .singleItem))
                }
                

                if (channel.adminRights != nil || channel.flags.contains(.isCreator)), let linkedDiscussionPeerId = cachedChannelData.linkedDiscussionPeerId.peerId, let peer = view.peers[linkedDiscussionPeerId] {
                    actionBlock.append(.linkedChannel(section: GroupInfoSection.type.rawValue, channel: peer, subscribers: cachedChannelData.participantsSummary.memberCount, viewType: .singleItem))
                } else if channel.hasPermission(.banMembers) {
                    if !access.isPublic {
                        actionBlock.append(.preHistory(section: GroupInfoSection.type.rawValue, enabled: cachedChannelData.flags.contains(.preHistoryEnabled), viewType: .singleItem))
                    }
                }

                if cachedChannelData.flags.contains(.canSetStickerSet) && access.canEditGroupInfo {
                    actionBlock.append(.groupStickerset(section: GroupInfoSection.type.rawValue, packName: cachedChannelData.stickerPack?.title ?? "", viewType: .singleItem))
                }
                var minParticipants = 200
                if let data = arguments.context.appConfiguration.data, let value = data["forum_upgrade_participants_min"] as? Double {
                    minParticipants = Int(value)
                }

                var canSetupTopics = false
                var topicsLimitedReason: TopicsLimitedReason?
                if channel.flags.contains(.isForum) {
                    canSetupTopics = true
                } else if case let .known(value) = cachedChannelData.linkedDiscussionPeerId, value != nil {
                    canSetupTopics = true
                    topicsLimitedReason = .discussion
                } else if let memberCount = cachedChannelData.participantsSummary.memberCount {
                    canSetupTopics = true
                    if Int(memberCount) < minParticipants {
                        topicsLimitedReason = .participants(minParticipants)
                    }
                }

                
                if access.isCreator, canSetupTopics {
                    actionBlock.append(.toggleForum(section: GroupInfoSection.type.rawValue, enabled: TelegramUtilsHooks.shared.peerIsForum(channel), convert: false, limit: topicsLimitedReason, viewType: .singleItem))
                }
                applyBlock(actionBlock)
                
                if access.isCreator, canSetupTopics {
                    entries.append(.forumInfo(section: GroupInfoSection.type.rawValue, text: strings().peerInfoForumInfo, viewType: .textBottomItem))
                }
                
                var canViewAdminsAndBanned = false
                if let channel = view.peers[view.peerId] as? TelegramChannel {
                    if let _ = channel.adminRights {
                        canViewAdminsAndBanned = true
                    } else if channel.flags.contains(.isCreator) {
                        canViewAdminsAndBanned = true
                    }
                }
                
                if canViewAdminsAndBanned {
                    var block: [GroupInfoEntry<Context>] = []
                    var activePermissionCount: Int?
                    
                    let permissionList = internal_allPossibleGroupPermissionList
                    if let defaultBannedRights = channel.defaultBannedRights {
                        var count = 0
                        for (right, _) in permissionList {
                            if !defaultBannedRights.flags.contains(right) {
                                count += 1
                            }
                        }
                        activePermissionCount = count
                    }
                    
                    if !channel.flags.contains(.isGigagroup) {
                        if access.canEditMembers {
                            block.append(.members(section: GroupInfoSection.admin.rawValue, count: cachedChannelData.participantsSummary.memberCount ?? 0, viewType: .singleItem))
                        }
                    }
                                        
                    if (access.isCreator || access.canCreateInviteLink) {
                        block.append(.inviteLinks(section: GroupInfoSection.admin.rawValue, count: inviteLinksCount, viewType: .singleItem))
                        if joinRequestsCount > 0 {
                            block.append(.requests(section: GroupInfoSection.admin.rawValue, count: joinRequestsCount, viewType: .singleItem))
                        }
                    }
                    

                    if !channel.flags.contains(.isGigagroup) {
                        if access.canEditMembers {
                            block.append(.permissions(section: GroupInfoSection.admin.rawValue, count: activePermissionCount.flatMap({ "\(max(0, $0 - 2))/\(permissionList.count - 2)" }) ?? "", viewType: .singleItem))
                        }
                    } else {
                        block.append(.blocked(section: GroupInfoSection.admin.rawValue, count: cachedChannelData.participantsSummary.kickedCount, viewType: .singleItem))
                    }
                    block.append(.administrators(section: GroupInfoSection.admin.rawValue, count: cachedChannelData.participantsSummary.adminCount.flatMap { "\($0)" } ?? "", viewType: .lastItem))
                    
                    block.append(.recentActions(section: GroupInfoSection.admin.rawValue, viewType: .singleItem))

                    
                    applyBlock(block)

                }

                if channel.linkedCommunityId == nil, (channel.adminRights != nil || channel.flags.contains(.isCreator)) {
                    entries.append(.addToCommunity(section: GroupInfoSection.members.rawValue, viewType: .singleItem))
                }
            }

        } else {
            
            applyBlock(infoBlock)
            
            
            
            var aboutBlock:[GroupInfoEntry<Context>] = []
            
            if group.isScam {
                aboutBlock.append(GroupInfoEntry<Context>.scam(section: GroupInfoSection.desc.rawValue, title: strings().peerInfoScam, text: strings().groupInfoScamWarning, viewType: .singleItem))
            } else if group.isFake {
                aboutBlock.append(GroupInfoEntry<Context>.scam(section: GroupInfoSection.desc.rawValue, title: strings().peerInfoFake, text: strings().groupInfoFakeWarning, viewType: .singleItem))
            }
            
            if let cachedChannelData = view.cachedData as? CachedChannelData {
                if let about = cachedChannelData.about, !about.isEmpty, !group.isScam && !group.isFake {
                    aboutBlock.append(GroupInfoEntry<Context>.about(section: GroupInfoSection.desc.rawValue, text: about, viewType: .singleItem))
                }
            }
            
            if let cachedGroupData = view.cachedData as? CachedGroupData {
                if let about = cachedGroupData.about, !about.isEmpty, !group.isScam {
                    aboutBlock.append(GroupInfoEntry<Context>.about(section: GroupInfoSection.desc.rawValue, text: about, viewType: .singleItem))
                }
            }
            var usernames:[UserInfoAddress] = group.usernames.filter { $0.isActive }.map {
                .init(username: $0.username, collectable: $0.flags.contains(.isEditable))
            }
            if usernames.isEmpty, let address = group.addressName {
                usernames.append(.init(username: address, collectable: false))
            }
            if !usernames.isEmpty {
                aboutBlock.append(GroupInfoEntry<Context>.addressName(section: GroupInfoSection.desc.rawValue, name: usernames, viewType: .singleItem))
            }
            if FastSettings.canViewPeerId {
                aboutBlock.append(GroupInfoEntry<Context>.peerId(section: GroupInfoSection.desc.rawValue, value: "\(group.id.id._internalGetInt64Value())", viewType: .singleItem))
            }

            applyBlock(aboutBlock)

            if let channel = peerViewMainPeer(view) as? TelegramChannel, let communityId = channel.linkedCommunityId {
                var communityBlock: [GroupInfoEntry<Context>] = []
                communityBlock.append(.community(section: GroupInfoSection.type.rawValue, communityId: communityId, viewType: .singleItem))
                if channel.adminRights != nil || channel.flags.contains(.isCreator) {
                    communityBlock.append(.removeFromCommunity(section: GroupInfoSection.type.rawValue, communityId: communityId, viewType: .singleItem))
                }
                applyBlock(communityBlock)
            }
            
            if group.isVerified || (view.cachedData as? CachedChannelData)?.verification != nil {
                entries.append(GroupInfoEntry<Context>.verifiedInfo(sectionId: GroupInfoSection.desc.rawValue, value: (view.cachedData as? CachedChannelData)?.verification, viewType: .textBottomItem))
            }
            
            if let cachedData = (view.cachedData as? CachedChannelData), cachedData.flags.contains(.canViewStarsRevenue) {
                if let stars = revenueState?.stats?.balances.availableBalance.fullyFormatted {
                    entries.append(.balance(section: GroupInfoSection.action.rawValue, stars: stars, canSeeStars: cachedData.flags.contains(.canViewStarsRevenue), viewType: .singleItem))
                }
            }
            


        }
                
        var destructBlock:[GroupInfoEntry<Context>] = []

        if let channel = peerViewMainPeer(view) as? TelegramChannel {
            if case .member = channel.participationStatus {
                if state.editingState != nil, access.isCreator {
                    destructBlock.append(GroupInfoEntry<Context>.leave(section: GroupInfoSection.destruct.rawValue, text: strings().peerInfoDeleteGroup, viewType: .singleItem))
                }
            }
        }

        applyBlock(destructBlock)

        if mediaTabsData.loaded && !mediaTabsData.collections.isEmpty, let controller = arguments.mediaController() {
            entries.append(.media(section: GroupInfoSection.media.rawValue, controller: controller, isVisible: state.editingState == nil, viewType: .singleItem))
        }
        
        var items:[GroupInfoEntry<Context>] = []
        var sectionId:Int = 0
        for (i, entry) in entries.enumerated() {
            if entry.sectionId != sectionId, i != 0 {
                if case .media(_, _, true, _) = entry {
                } else {
                    items.append(.section(sectionId))
                }
                sectionId = entry.sectionId
            }
            items.append(entry)
        }
        
        entries = items
        
    }
    
    
    return entries.sorted(by: { p1, p2 -> Bool in
        return p1.isOrderedBefore(p2)
    })
}
