import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import InAppSettings
import TelegramContext
import TelegramUtils
import TelegramTheme
import Localization
import Strings
import GeneralRows
import InputDataUI
import AlertsUI
import ChatHistoryModel
import ChatUI
import LocalAnimations

private let _id_tag_preview = InputDataIdentifier("_id_tag_preview")
private let _id_tag_header = InputDataIdentifier("_id_tag_header")
private let _id_tag_input = InputDataIdentifier("_id_tag_input")
private let _id_tag_info = InputDataIdentifier("_id_tag_info")
private let _id_permissions = InputDataIdentifier("_id_permissions")
private let _id_promote = InputDataIdentifier("_id_promote")
private let _id_remove = InputDataIdentifier("_id_remove")

private final class Arguments {
    let context: any AccountContextProtocol
    let peerId: PeerId
    let promote: (ChannelParticipant) -> Void
    let restrict: (ChannelParticipant) -> Void
    let remove: (ChannelParticipant) -> Void
    let updateTag: (String) -> Void
    let openPermissions: (ChannelParticipant) -> Void
    init(context: any AccountContextProtocol, peerId: PeerId, promote: @escaping(ChannelParticipant) -> Void, restrict: @escaping(ChannelParticipant) -> Void, remove: @escaping(ChannelParticipant) -> Void, updateTag: @escaping(String) -> Void, openPermissions: @escaping(ChannelParticipant) -> Void) {
        self.context = context
        self.peerId = peerId
        self.promote = promote
        self.restrict = restrict
        self.remove = remove
        self.updateTag = updateTag
        self.openPermissions = openPermissions
    }
}

private struct State : Equatable {
    var peer: PeerEquatable
    var presence: TelegramUserPresence?
    var participant: ChannelParticipant
    var channel: TelegramChannel?
    var tag: String
    var initialTag: String
    var defaultBannedRights: TelegramChatBannedRights?
}

// MARK: - Tag Preview

private final class TagPreviewRowItem: GeneralRowItem {
    fileprivate let chatItem: TableRowItem
    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, peer: Peer, tag: String, rankType: AdminBadgeType, viewType: GeneralViewType) {

        let groupPeerId = PeerId(namespace: Namespaces.Peer.CloudGroup, id: ._internalFromInt64Value(0))
        let groupPeer = TelegramGroup(id: groupPeerId, title: "", photo: [], participantCount: 0, role: .member, membership: .Member, flags: [], defaultBannedRights: nil, migrationReference: nil, creationDate: 0, version: 0)

        let chatInteraction = ChatInteraction(chatLocation: .peer(groupPeerId), context: context, isLogInteraction: true, disableSelectAbility: true)

        let fromUser = TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(peer.id.id._internalGetInt64Value() % 7 * 100)), accessHash: nil, firstName: peer.compactDisplayTitle, lastName: "", username: nil, phone: nil, photo: peer.profileImageRepresentations, botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: peer.emojiStatus, usernames: [], storiesHidden: nil, nameColor: peer.nameColor, backgroundEmojiId: peer.backgroundEmojiId, profileColor: peer.profileColor, profileBackgroundEmojiId: peer.profileBackgroundEmojiId, subscriberCount: nil, verificationIconFileId: nil)

        let rank = tag.isEmpty ? nil : tag

        let message = Message(stableId: 0, stableVersion: 0, id: MessageId(peerId: groupPeerId, namespace: 0, id: 0), globallyUniqueId: 0, groupingKey: 0, groupInfo: nil, threadId: nil, timestamp: 60 * 22 + 60 * 60 * 18, flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: fromUser, text: strings().channelParticipantPreviewMessage, attributes: [], media: [], peers: SimpleDictionary([fromUser.id: fromUser, groupPeerId: groupPeer]), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])

        let entry: ChatHistoryEntry = .MessageEntry(message, MessageIndex(message), true, theme.bubbled ? .bubble : .list, .Full(rank: rank, rankType: rank != nil ? rankType : .none, header: .normal), nil, ChatHistoryEntryData(nil, MessageEntryAdditionalData(), AutoplayMediaPreferences.defaultSettings))

        self.chatItem = ChatRowItem.item(initialSize, from: entry, interaction: chatInteraction, theme: theme)

        super.init(initialSize, stableId: stableId, viewType: viewType)

        chatInteraction.getGradientOffsetRect = { [weak self] in
            guard let self = self else { return .zero }
            return CGRect(origin: NSMakePoint(0, self.height), size: NSMakeSize(self.width, self.height))
        }

        _ = makeSize(initialSize.width, oldWidth: 0)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        _ = chatItem.makeSize(self.blockWidth + 40, oldWidth: 0)
        return true
    }

    override var instantlyResize: Bool {
        return true
    }

    override var height: CGFloat {
        return self.viewType.innerInset.top + chatItem.height + self.viewType.innerInset.bottom
    }

    override func viewClass() -> AnyClass {
        return TagPreviewRowView.self
    }

    override var accessibilityLabel: String? {
        return chatItem.accessibilityLabel ?? strings().channelParticipantPreviewMessage
    }
}

private final class TagPreviewRowView: GeneralContainableRowView {
    private let backgroundView: BackgroundView
    private let itemsView = View()

    required init(frame frameRect: NSRect) {
        backgroundView = BackgroundView(frame: NSMakeRect(0, 0, frameRect.width, frameRect.height))
        backgroundView.useSharedAnimationPhase = false
        super.init(frame: frameRect)
        containerView.addSubview(backgroundView, positioned: .below, relativeTo: nil)
        if let backgroundLayer = backgroundView.layer {
            containerView.layer?.insertSublayer(borderView, above: backgroundLayer)
        }
        backgroundView.addSubview(itemsView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? TagPreviewRowItem else { return }

        self.itemsView.removeAllSubviews()

        let y: CGFloat = item.viewType.innerInset.top
        let vz = item.chatItem.viewClass() as! TableRowView.Type
        let view = vz.init(frame: NSMakeRect(0, y, self.backgroundView.frame.width, item.chatItem.height))
        view.set(item: item.chatItem, animated: false)
        self.itemsView.addSubview(view)

        if let view = view as? ChatRowView {
            view.updateBackground(animated: false, item: view.item, rotated: true)
        }
    }

    override func updateColors() {
        super.updateColors()
        self.backgroundView.backgroundMode = theme.bubbled ? theme.backgroundMode : .color(color: theme.colors.chatBackground)
    }

    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        self.backgroundView.frame = containerView.bounds
        itemsView.frame = backgroundView.bounds
    }
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []

    var sectionId:Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1

    let peer = state.peer.peer

    guard let channel = state.channel else {
        return entries
    }

    let isCreatorParticipant: Bool
    if case .creator = state.participant {
        isCreatorParticipant = true
    } else {
        isCreatorParticipant = false
    }
    let rankType: AdminBadgeType = isCreatorParticipant ? .owner : (state.participant.adminInfo != nil ? .admin : .none)

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_tag_preview, equatable: InputDataEquatable(state.tag), comparable: nil, item: { initialSize, stableId in
        return TagPreviewRowItem(initialSize, stableId: stableId, context: arguments.context, peer: peer, tag: state.tag, rankType: rankType, viewType: .firstItem)
    }))
    index += 1

    entries.append(.input(sectionId: sectionId, index: index, value: .string(state.tag), error: nil, identifier: _id_tag_input, mode: .plain, data: InputDataRowData(viewType: .lastItem), placeholder: nil, inputPlaceholder: strings().channelParticipantAddTag, filter: { text in
        return String(text.prefix(16)).filter { !String($0).containsOnlyEmoji }
    }, limit: 16))
    index += 1

    let tagDesc = peer.id == arguments.context.peerId ? strings().channelParticipantTagDescSelf : strings().channelParticipantTagDescOther(peer.compactDisplayTitle)
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(tagDesc), data: InputDataGeneralTextData(viewType: .textBottomItem)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    let isAdmin = state.participant.adminInfo != nil
    let isCreator = isCreatorParticipant

    let canBanMembers = channel.hasPermission(.banMembers)
    let canAddAdmins = channel.hasPermission(.addAdmins)

    let canRemoveAdmin: Bool
    if let adminInfo = state.participant.adminInfo {
        canRemoveAdmin = adminInfo.promotedBy == arguments.context.peerId || channel.flags.contains(.isCreator)
    } else {
        canRemoveAdmin = true
    }

    let canRestrict = canBanMembers && !isCreator && canRemoveAdmin
    let canPromote = canAddAdmins && !isAdmin && !isCreator
    let canRemove = canBanMembers && !isCreator && canRemoveAdmin

    if !isCreator, canRestrict || canPromote || canRemove, false {
        if canRestrict {
            let permissionList = allGroupPermissionList(peer: channel)
            let subList = banSendMediaSubList()
            let totalCount = permissionList.count + subList.count

            var enabledCount = totalCount
            if let bannedRights = state.participant.banInfo?.rights {
                for (flag, _) in permissionList {
                    if bannedRights.flags.contains(flag) {
                        enabledCount -= 1
                    }
                }
                for (flag, _) in subList {
                    if bannedRights.flags.contains(flag) {
                        enabledCount -= 1
                    }
                }
            } else if let defaultBannedRights = state.defaultBannedRights {
                for (flag, _) in permissionList {
                    if defaultBannedRights.flags.contains(flag) {
                        enabledCount -= 1
                    }
                }
                for (flag, _) in subList {
                    if defaultBannedRights.flags.contains(flag) {
                        enabledCount -= 1
                    }
                }
            }
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_permissions, data: InputDataGeneralData(name: strings().channelParticipantPermissions, color: theme.colors.text, type: .nextContext("\(enabledCount)/\(totalCount)"), viewType: .singleItem, action: {
                arguments.openPermissions(state.participant)
            })))
            index += 1

            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1
        }

        let hasPromote = canPromote
        let hasRemove = canRemove
        let hasBoth = hasPromote && hasRemove

        if canPromote {
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_promote, data: InputDataGeneralData(name: strings().channelParticipantPromoteToAdmin, color: theme.colors.accent, type: .none, viewType: hasBoth ? .firstItem : .singleItem, action: {
                arguments.promote(state.participant)
            })))
            index += 1
        }

        if canRemove {
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_remove, data: InputDataGeneralData(name: strings().channelParticipantRemoveMember, color: theme.colors.redUI, type: .none, viewType: hasBoth ? .lastItem : .singleItem, action: {
                arguments.remove(state.participant)
            })))
            index += 1
        }

        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    }

    return entries
}

public func ChannelParticipantController<Context: AccountContextProtocol>(context: Context, peerId: PeerId, participant: RenderedChannelParticipant) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    let initialTag = participant.participant.rank ?? ""
    let initialState = State(
        peer: PeerEquatable(participant.peer._asPeer()),
        presence: participant.presences[participant.peer.id] as? TelegramUserPresence,
        participant: participant.participant,
        channel: nil,
        tag: initialTag,
        initialTag: initialTag
    )

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }

    let peerView = context.account.viewTracker.peerView(peerId)
    actionsDisposable.add(peerView.start(next: { view in
        if let channel = peerViewMainPeer(view) as? TelegramChannel {
            updateState { state in
                var state = state
                state.channel = channel
                state.defaultBannedRights = channel.defaultBannedRights
                return state
            }
        }
    }))

    var getController:(()->ViewController?)? = nil
    var close:(()->Void)? = nil

    var window:Window {
        get {
            return bestWindow(context, getController?())
        }
    }

    let openRestrictions: (ChannelParticipant) -> Void = { participant in
        close?()
        showModal(with: RestrictedModalController(context, peerId: peerId, memberId: participant.peerId, initialParticipant: participant, updated: { updatedRights in
            let signal = context.peerChannelMemberCategoriesContextsManager.updateMemberBannedRights(peerId: peerId, memberId: participant.peerId, bannedRights: updatedRights)
            _ = (signal).start()
        }), for: context.window)
    }

    let arguments = Arguments(context: context, peerId: peerId, promote: { participant in
        close?()
        if let controller = FeatureNavigationHooks.shared.makeChannelAdminControllerObserved(context, peerId, participant.peerId, participant, { _ in }, { _, _ in }) { showModal(with: controller, for: context.window) }
    }, restrict: { participant in
        openRestrictions(participant)
    }, remove: { channelParticipant in
        verifyAlert_button(for: context.window, information: strings().peerInfoConfirmRemovePeer(participant.peer._asPeer().compactDisplayTitle), ok: strings().modalRemove, successHandler: { _ in
            let signal = context.peerChannelMemberCategoriesContextsManager.updateMemberBannedRights(peerId: peerId, memberId: channelParticipant.peerId, bannedRights: TelegramChatBannedRights(flags: [.banReadMessages], untilDate: 0))
            actionsDisposable.add((signal).start())
            close?()
        })
    }, updateTag: { tag in
        updateState { state in
            var state = state
            state.tag = tag
            return state
        }
    }, openPermissions: { participant in
        openRestrictions(participant)
    })

    let signal = statePromise.get() |> filter { $0.channel != nil } |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: strings().channelParticipantMember)

    controller.updateDatas = { data in
        updateState { state in
            var state = state
            if let tag = data[_id_tag_input]?.stringValue {
                state.tag = tag
            }
            return state
        }
        return .none
    }

    controller.validateData = { _ in
        let state = stateValue.with { $0 }
        let tag = state.tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if tag != state.initialTag {
            let signal = showModalProgress(signal: context.peerChannelMemberCategoriesContextsManager.updateChatRank(peerId: peerId, memberId: participant.peer.id, rank: tag.isEmpty ? nil : tag, participant: participant), for: context.window) |> deliverOnMainQueue
            actionsDisposable.add((signal).start(error: { _ in
                showModalText(for: context.window, text: strings().channelParticipantTagUpdateError)
            }, completed: {
                close?()
                showModalText(for: context.window, text: strings().channelParticipantTagUpdated)
            }))
            return .fail(.none)
        }
        close?()
        return .fail(.none)
    }

    getController = { [weak controller] in
        return controller
    }

    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().channelParticipantSaveChanges, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true)

    controller.afterTransaction = { [weak modalInteractions] _ in
        let state = stateValue.with { $0 }
        let tag = state.tag.trimmingCharacters(in: .whitespacesAndNewlines)
        modalInteractions?.updateDone { button in
            if !state.initialTag.isEmpty && tag.isEmpty {
                button.set(text: strings().channelParticipantRemoveTag, for: .Normal)
            } else {
                button.set(text: strings().channelParticipantEditTag, for: .Normal)
            }
        }
    }

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(350, 350))

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })

    controller.centerModalHeader = ModalHeaderData(title: strings().channelParticipantMember)

    close = { [weak modalController] in
        modalController?.modal?.close()
    }

    return modalController
}

private func canModerateChannelParticipant(channel: TelegramChannel, accountPeerId: PeerId, member: Peer, participant: ChannelParticipant?) -> Bool {
    guard !channel.isChannel, channel.hasPermission(.banMembers), member.id != accountPeerId, member.isUser || member.isBot,
          let participant = participant, participant.peerId == member.id else {
        return false
    }
    switch participant {
    case .creator:
        return false
    case let .member(_, _, adminInfo, _, _, _):
        if let adminInfo = adminInfo {
            return channel.flags.contains(.isCreator) || adminInfo.canBeEditedByAccountPeer || adminInfo.promotedBy == accountPeerId
        }
        return true
    }
}

private func channelParticipantHasBannedRights(_ participant: ChannelParticipant?, rights: TelegramChatBannedRights) -> Bool {
    guard case let .member(_, _, _, banInfo, _, _)? = participant else {
        return false
    }
    var expectedFlags = rights.flags
    expectedFlags.remove(.banSendMedia)
    expectedFlags.remove(TelegramChatBannedRightsFlags(rawValue: 1 << 1))
    guard let banInfo = banInfo else {
        return expectedFlags.isEmpty
    }
    let expectedUntilDate = rights.untilDate == 0 ? Int32.max : rights.untilDate
    let actualUntilDate = banInfo.rights.untilDate == 0 ? Int32.max : banInfo.rights.untilDate
    if rights.flags.contains(.banReadMessages) {
        return banInfo.rights.flags.contains(.banReadMessages) && actualUntilDate == expectedUntilDate
    }
    return banInfo.rights.flags == expectedFlags && (expectedFlags.isEmpty || actualUntilDate == expectedUntilDate)
}

private enum ChannelParticipantModerationResult {
    case unauthorized
    case verified
    case unverified
}

public func channelParticipantModerationMenuItems(context: any AccountContextProtocol, channel: TelegramChannel, member: Peer, participant: ChannelParticipant? = nil) -> [ContextMenuItem] {
    guard !channel.isChannel, channel.hasPermission(.banMembers), member.id != context.peerId, member.isUser || member.isBot else {
        return []
    }
    if let participant = participant, !canModerateChannelParticipant(channel: channel, accountPeerId: context.peerId, member: member, participant: participant) {
        return []
    }
    let peerId = channel.id
    let authorizedParticipant = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
    |> mapToSignal { peer -> Signal<ChannelParticipant?, NoError> in
        guard let channel = peer?._asPeer() as? TelegramChannel, !channel.isChannel, channel.hasPermission(.banMembers) else {
            return .single(nil)
        }
        return context.engine.peers.fetchChannelParticipant(peerId: peerId, participantId: member.id)
        |> map { participant in
            return canModerateChannelParticipant(channel: channel, accountPeerId: context.peerId, member: member, participant: participant) ? participant : nil
        }
    }
    |> take(1)
    |> timeout(10.0, queue: .mainQueue(), alternate: .single(nil))
    |> deliverOnMainQueue

    let updateRights: (TelegramChatBannedRights) -> Void = { rights in
        let update = authorizedParticipant |> mapToSignal { participant -> Signal<ChannelParticipantModerationResult, NoError> in
            guard participant != nil else {
                return .single(.unauthorized)
            }
            return Signal { subscriber in
                let update = context.peerChannelMemberCategoriesContextsManager.updateMemberBannedRights(peerId: peerId, memberId: member.id, bannedRights: rights)
                |> then(.single(()))
                |> mapToSignal { _ in
                    return context.engine.peers.fetchChannelParticipant(peerId: peerId, participantId: member.id)
                    |> take(1)
                    |> timeout(10.0, queue: .mainQueue(), alternate: .single(nil))
                    |> map { participant -> ChannelParticipantModerationResult in
                        return channelParticipantHasBannedRights(participant, rights: rights) ? .verified : .unverified
                    }
                }
                _ = update.startStandalone(next: { success in
                    subscriber.putNext(success)
                }, completed: {
                    subscriber.putCompletion()
                })
                return EmptyDisposable
            }
        }
        |> deliverOnMainQueue

        _ = showModalProgress(signal: update, for: context.window).startStandalone(next: { result in
            switch result {
            case .verified:
                _ = showModalSuccess(for: context.window, icon: theme.icons.successModalProgress, delay: 3.0).startStandalone()
            case .unauthorized:
                alert(for: context.window, info: strings().unknownError)
            case .unverified:
                //TODOLANG
                alert(for: context.window, info: "Could not confirm the updated permissions. Check the member’s permissions before trying again.")
            }
        })
    }

    return [ContextMenuItem(strings().chatContextRestrict, handler: {
        _ = showModalProgress(signal: authorizedParticipant, for: context.window).startStandalone(next: { participant in
            guard let participant = participant else {
                alert(for: context.window, info: strings().unknownError)
                return
            }
            showModal(with: RestrictedModalController(context, peerId: peerId, memberId: member.id, initialParticipant: participant, updated: updateRights), for: context.window)
        })
    }, itemImage: MenuAnimation.menu_restrict.value), ContextMenuItem(strings().chatContextBan, handler: {
        updateRights(TelegramChatBannedRights(flags: [.banReadMessages], untilDate: Int32.max))
    }, itemMode: .destruct, itemImage: MenuAnimation.menu_ban.value)]
}
