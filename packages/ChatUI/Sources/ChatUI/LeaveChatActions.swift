import Cocoa
import TelegramCore
import Localization
import Postbox
import SwiftSignalKit
import TGUIKit
import InAppSettings
import ColorPalette
import ThemeSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import AlertsUI
import InputDataUI

public func removeChatInteractively<Context: AccountContextProtocol>(context: Context, peerId:PeerId, threadId: Int64? = nil, userId: PeerId? = nil, deleteGroup: Bool = false, forceRemoveGlobally: Bool = false, offerDeleteForAll: Bool = false) -> Signal<Bool, NoError> {
    return context.account.postbox.peerView(id: peerId)
        |> take(1)
        |> map { peerViewMainPeer($0) }
        |> filter { $0 != nil }
        |> map { $0! }
        |> deliverOnMainQueue
        |> mapToSignal { peer -> Signal<Bool, NoError> in

            if offerDeleteForAll, !deleteGroup, threadId == nil, canDeletePeerGloballyAsCreator(peer) {
                return showDeleteForAllDialog(context: context, peer: peer, peerId: peerId)
            }

            if let channel = peer as? TelegramChannel, case .group = channel.info, channel.flags.contains(.isCreator), !deleteGroup, threadId == nil {
                return leaveGroupAsOwner(context: context, channel: channel, fallback: {
                    return showStandardLeaveDialog(context: context, peer: peer, peerId: peerId, threadId: threadId, deleteGroup: deleteGroup, forceRemoveGlobally: forceRemoveGlobally)
                })
            }

            return showStandardLeaveDialog(context: context, peer: peer, peerId: peerId, threadId: threadId, deleteGroup: deleteGroup, forceRemoveGlobally: forceRemoveGlobally)
    }
}

private func canDeletePeerGloballyAsCreator(_ peer: Peer) -> Bool {
    if let channel = peer as? TelegramChannel {
        return !channel.isMonoForum && channel.flags.contains(.isCreator) && channel.addressName == nil
    } else if let group = peer as? TelegramGroup, case .creator = group.role {
        return true
    } else {
        return false
    }
}

private func leaveGroupAsOwner<Context: AccountContextProtocol>(context: Context, channel: TelegramChannel, fallback: @escaping () -> Signal<Bool, NoError>) -> Signal<Bool, NoError> {
    let peerId = channel.id
    let adminsSignal: Signal<[RenderedChannelParticipant], NoError> = Signal { subscriber in
        let (disposable, _) = context.peerChannelMemberCategoriesContextsManager.admins(peerId: peerId, updated: { state in
            subscriber.putNext(state.list)
            subscriber.putCompletion()
        })
        return disposable
    }

    return combineLatest(context.engine.peers.getFutureCreatorAfterLeave(peerId: peerId), adminsSignal |> take(1))
        |> deliverOnMainQueue
        |> mapToSignal { futureCreator, admins -> Signal<Bool, NoError> in
            if let futureCreator = futureCreator, let myPeer = context.myPeer {
                let otherAdmins = admins.filter { participant in
                    if participant.peer.id == context.peerId { return false }
                    if case .creator = participant.participant { return false }
                    return true
                }
                let hasOtherAdmins = !otherAdmins.isEmpty
                return showOwnerLeaveGroupModal(context: context, peer: channel, myPeer: myPeer, futureCreator: futureCreator._asPeer(), hasOtherAdmins: hasOtherAdmins)
            } else {
                return fallback()
            }
        }
}

private func showDeleteForAllDialog<Context: AccountContextProtocol>(context: Context, peer: Peer, peerId: PeerId) -> Signal<Bool, NoError> {
    let text: String
    let okTitle: String
    let option: String
    if let channel = peer as? TelegramChannel, case .broadcast = channel.info {
        text = strings().peerInfoConfirmLeaveChannel
        okTitle = strings().alertOK
        option = strings().leaveChatActionsDeleteForAllSubscribers
    } else if peer is TelegramChannel {
        text = strings().confirmLeaveGroup
        okTitle = strings().peerInfoConfirmLeave
        option = strings().deleteChatDeleteGroupForAll
    } else {
        text = strings().peerInfoConfirmDeleteChat(peer.displayTitle)
        okTitle = strings().confirmDelete
        option = strings().deleteChatDeleteGroupForAll
    }

    return verifyAlertSignal(for: context.window, information: text, ok: okTitle, option: option, optionIsSelected: false, completeWhenDismissed: true)
        |> mapToSignal { result -> Signal<Bool, NoError> in
            switch result {
            case .thrid:
                return removeConfirmedChat(context: context, peer: peer, peerId: peerId, deleteGloballyIfPossible: true)
            case .basic:
                if let channel = peer as? TelegramChannel, case .group = channel.info {
                    return leaveGroupAsOwner(context: context, channel: channel, fallback: {
                        return removeConfirmedChat(context: context, peer: peer, peerId: peerId, deleteGloballyIfPossible: false)
                    })
                }
                return removeConfirmedChat(context: context, peer: peer, peerId: peerId, deleteGloballyIfPossible: false)
            case .none:
                return .single(false)
            }
        }
}

private func removeConfirmedChat(context: any AccountContextProtocol, peer: Peer, peerId: PeerId, deleteGloballyIfPossible: Bool) -> Signal<Bool, NoError> {
    return context.globalPeerHandler.get()
        |> take(1)
        |> deliverOnMainQueue
        |> map { location -> Bool in
            scheduleChatRemoval(context: context, peer: peer, peerId: peerId, deleteGloballyIfPossible: deleteGloballyIfPossible)
            if location?.peerId == peerId {
                context.bindings.rootNavigation().close()
            }
            return true
        }
}

private func scheduleChatRemoval(context: any AccountContextProtocol, peer: Peer, peerId: PeerId, deleteGloballyIfPossible: Bool, blockBot: Bool = false) {
    let text = pendingChatRemovalText(peer: peer, peerId: peerId, deleteGloballyIfPossible: deleteGloballyIfPossible)
    PendingChatRemovals.get(context).schedule(peerId: peerId, text: text, commit: {
        if blockBot {
            _ = context.blockedPeersContext.add(peerId: peerId).start()
        }
        return context.engine.peers.removePeerChat(peerId: peerId, reportChatSpam: false, deleteGloballyIfPossible: deleteGloballyIfPossible) |> ignoreValues
    })
}

private func pendingChatRemovalText(peer: Peer, peerId: PeerId, deleteGloballyIfPossible: Bool) -> String {
    if let channel = peer as? TelegramChannel {
        if channel.isMonoForum {
            return strings().leaveChatActionsRemovedFromChatList
        }
        switch channel.info {
        case .broadcast:
            return deleteGloballyIfPossible ? strings().leaveChatActionsDeletedChannel : strings().leaveChatActionsLeftChannel
        case .group:
            return deleteGloballyIfPossible ? strings().leaveChatActionsDeletedGroup : strings().leaveChatActionsLeftGroup
        }
    } else if peer is TelegramGroup {
        return deleteGloballyIfPossible ? strings().leaveChatActionsDeletedGroup : strings().leaveChatActionsLeftGroup
    } else if peerId.namespace == Namespaces.Peer.SecretChat {
        return strings().leaveChatActionsSecretChatDeleted
    } else if deleteGloballyIfPossible && !peer.isBot {
        return strings().leaveChatActionsChatDeletedForBothSides
    } else {
        return strings().leaveChatActionsChatDeleted
    }
}

private func showOwnerLeaveGroupModal<Context: AccountContextProtocol>(context: Context, peer: TelegramChannel, myPeer: Peer, futureCreator: Peer, hasOtherAdmins: Bool) -> Signal<Bool, NoError> {
    let title = strings().groupLeaveTitle(peer.title)
    let info: String
    let optionTitle: String
    let selectTitle: String

    if hasOtherAdmins {
        info = strings().groupLeaveInfoOwner(futureCreator.displayTitle, peer.title)
        optionTitle = strings().groupAppointAnotherOwner
        selectTitle = strings().groupAppointAnotherOwner
    } else {
        info = strings().groupLeaveInfoAdmin(futureCreator.displayTitle, peer.title)
        optionTitle = strings().groupAppointAnotherAdmin
        selectTitle = strings().groupAppointAnotherAdmin
    }

    let header = ModalAlertData.Header(id: "avatar_header") { initialSize, stableId, _ in
        return ChangePeerRowItem(initialSize, stableId: stableId, context: context, fromPeer: .init(myPeer), toPeer: .init(futureCreator))
    }

    return verifyAlertSignal(for: context.window, header: title, information: info, ok: strings().groupLeaveButton, option: optionTitle, optionIsSelected: false, headerItem: header, completeWhenDismissed: true)
        |> mapToSignal { result -> Signal<Bool, NoError> in
            switch result {
            case .thrid:
                return ChatNavigationHooks.shared.selectChannelOwner(context, peer, selectTitle, peer.title)
                    |> deliverOnMainQueue
                    |> mapToSignal { selected -> Signal<Bool, NoError> in
                        guard let (selectedPeerId, participant) = selected else {
                            return .single(false)
                        }

                        if hasOtherAdmins {
                            return transferOwnership(context: context, peerId: peer.id, memberId: selectedPeerId, isGroup: true)
                        } else {
                            showModal(with: ChatUIHooks.shared.makeChannelAdminModal(context, peer.id, selectedPeerId, participant), for: context.window)
                            return .single(false)
                        }
                    }
            case .basic:
                scheduleChatRemoval(context: context, peer: peer, peerId: peer.id, deleteGloballyIfPossible: false)
                context.bindings.rootNavigation().close()
                return .single(true)
            case .none:
                return .single(false)
            }
        }
}

private func transferOwnership<Context: AccountContextProtocol>(context: Context, peerId: PeerId, memberId: PeerId, isGroup: Bool) -> Signal<Bool, NoError> {
    return combineLatest(context.account.postbox.loadedPeerWithId(peerId), context.account.postbox.loadedPeerWithId(memberId))
        |> take(1)
        |> deliverOnMainQueue
        |> mapToSignal { peer, member -> Signal<Bool, NoError> in
            let header: String
            let text: String
            if peer.isChannel {
                header = strings().channelAdminTransferOwnershipConfirmChannelTitle
                text = strings().channelAdminTransferOwnershipConfirmChannelText(peer.displayTitle, member.displayTitle)
            } else {
                header = strings().channelAdminTransferOwnershipConfirmGroupTitle
                text = strings().channelAdminTransferOwnershipConfirmGroupText(peer.displayTitle, member.displayTitle)
            }

            return Signal { subscriber in
                verifyAlert_button(for: context.window, header: header, information: text, ok: strings().channelAdminTransferOwnershipConfirmOK, successHandler: { _ in
                    _ = showModalProgress(signal: context.engine.peers.checkOwnershipTranfserAvailability(memberId: memberId), for: context.window).start(error: { error in
                        let errorText = getOwnershipTransferErrorText(error, isGroup: isGroup)
                        var install2Fa = false
                        if case .twoStepAuthMissing = error {
                            install2Fa = true
                        }

                        if let errorText = errorText {
                            verifyAlert_button(for: context.window, header: strings().channelTransferOwnerErrorTitle, information: errorText, ok: strings().modalOK, cancel: strings().modalCancel, option: install2Fa ? strings().channelTransferOwnerErrorEnable2FA : nil, successHandler: { result in
                                if case .thrid = result {
                                    context.bindings.rootNavigation().removeUntil(ChatHistoryUIHooks.shared.emptyChatControllerType())
                                    ChatNavigationHooks.shared.pushTwoStepVerificationUnlock(context, { (controller, isRoot, animated) in
                                        let navigation = context.bindings.rootNavigation()
                                        if isRoot {
                                            navigation.removeUntil(ChatHistoryUIHooks.shared.emptyChatControllerType())
                                        }
                                        if !animated {
                                            navigation.stackInsert(controller, at: navigation.stackCount)
                                        } else {
                                            navigation.push(controller)
                                        }
                                    })
                                }
                            })
                        } else {
                            showModal(with: InputPasswordController(context: context, title: strings().channelAdminTransferOwnershipPasswordTitle, desc: strings().channelAdminTransferOwnershipPasswordDesc, checker: { pwd in
                                return context.peerChannelMemberCategoriesContextsManager.transferOwnership(peerId: peerId, memberId: memberId, password: pwd)
                                    |> deliverOnMainQueue
                                    |> ignoreValues
                                    |> `catch` { error -> Signal<Never, InputPasswordValueError> in
                                        let errorText = getOwnershipTransferErrorText(error, isGroup: isGroup)
                                        switch error {
                                        case .invalidPassword:
                                            return .fail(.wrong)
                                        default:
                                            if let errorText = errorText {
                                                return .fail(.custom(errorText))
                                            } else {
                                                return .fail(.generic)
                                            }
                                        }
                                    } |> afterCompleted {
                                        _ = showModalSuccess(for: context.window, icon: theme.icons.successModalProgress, delay: 2.0)
                                        subscriber.putNext(true)
                                        subscriber.putCompletion()
                                    }
                            }), for: context.window)
                        }
                        subscriber.putNext(false)
                        subscriber.putCompletion()
                    })
                }, cancelHandler: {
                    subscriber.putNext(false)
                    subscriber.putCompletion()
                })

                return EmptyDisposable
            }
        }
}

private func getOwnershipTransferErrorText(_ error: ChatOwnershipTransferError, isGroup: Bool) -> String? {
    switch error {
    case .generic:
        return strings().unknownError
    case .tooMuchJoined:
        return strings().inviteChannelsTooMuch
    case .authSessionTooFresh, .twoStepAuthMissing, .twoStepAuthTooFresh:
        return strings().channelTransferOwnerErrorText
    case .invalidPassword, .requestPassword:
        return nil
    case .restricted, .userBlocked:
        return isGroup ? strings().groupTransferOwnerErrorPrivacyRestricted : strings().channelTransferOwnerErrorPrivacyRestricted
    case .adminsTooMuch:
        return isGroup ? strings().groupTransferOwnerErrorAdminsTooMuch : strings().channelTransferOwnerErrorAdminsTooMuch
    case .userPublicChannelsTooMuch:
        return strings().channelTransferOwnerErrorPublicChannelsTooMuch
    case .limitExceeded:
        return strings().loginFloodWait
    case .userLocatedGroupsTooMuch:
        return strings().groupOwnershipTransferErrorLocatedGroupsTooMuch
    }
}

private func showStandardLeaveDialog(context: any AccountContextProtocol, peer: Peer, peerId: PeerId, threadId: Int64?, deleteGroup: Bool, forceRemoveGlobally: Bool) -> Signal<Bool, NoError> {

            let text:String
            var okTitle: String? = nil
            var thridTitle: String? = nil
            var canRemoveGlobally: Bool = false

            if let _ = threadId {
                okTitle = strings().confirmDelete
                if context.peerId == peerId {
                    text = strings().chatContextDeleteSaved
                } else {
                    text = strings().chatContextDeleteTopic
                }
            } else {
                if let peer = peer as? TelegramChannel {
                    switch peer.info {
                    case .broadcast:
                        if peer.flags.contains(.isCreator) && deleteGroup {
                            text = strings().confirmDeleteAdminedChannel
                            okTitle = strings().confirmDelete
                        } else {
                            text = strings().peerInfoConfirmLeaveChannel
                        }
                    case .group:
                        if deleteGroup && peer.flags.contains(.isCreator) {
                            text = strings().peerInfoConfirmDeleteGroupConfirmation
                            okTitle = strings().confirmDelete
                        } else {
                            text = strings().confirmLeaveGroup
                            okTitle = strings().peerInfoConfirmLeave
                        }
                    }
                } else if let peer = peer as? TelegramGroup {
                    if deleteGroup && peer.groupAccess.isCreator {
                        text = strings().peerInfoConfirmDeleteGroupConfirmation
                    } else {
                        text = strings().peerInfoConfirmDeleteChat(peer.title)
                    }
                    okTitle = strings().confirmDelete
                } else {
                    text = strings().peerInfoConfirmDeleteUserChat
                    okTitle = strings().confirmDelete
                }

                if peerId.namespace == Namespaces.Peer.CloudUser && peerId != context.account.peerId && !peer.isBot {
                    if context.limitConfiguration.maxMessageRevokeIntervalInPrivateChats == LimitsConfiguration.timeIntervalForever {
                        canRemoveGlobally = true
                    }
                }
                if peerId.namespace == Namespaces.Peer.SecretChat {
                    canRemoveGlobally = false
                }

                if canRemoveGlobally {
                    thridTitle = strings().chatMessageDeleteForMeAndPerson(peer.displayTitle)
                } else if peer.isBot {
                    thridTitle = strings().peerInfoStopBot
                }

                if peer.groupAccess.isCreator, deleteGroup {
                    canRemoveGlobally = true
                    thridTitle = strings().deleteChatDeleteGroupForAll
                }
            }

            if forceRemoveGlobally {
                canRemoveGlobally = false
                thridTitle = nil
            }


            let verify = verifyAlertSignal(for: context.window, information: text, ok: okTitle ?? strings().alertOK, option: thridTitle, optionIsSelected: false, completeWhenDismissed: true) |> filter { $0 != nil }

            return combineLatest(verify, context.globalPeerHandler.get() |> take(1)) |> deliverOnMainQueue |> map { result, location -> Bool in

                if let threadId = threadId {
                    _ = context.engine.peers.removeForumChannelThread(id: peerId, threadId: threadId).start()
                } else {
                    scheduleChatRemoval(context: context, peer: peer, peerId: peerId, deleteGloballyIfPossible: result == .thrid || forceRemoveGlobally, blockBot: peer.isBot && result == .thrid)
                }

                if let threadId = threadId, peerId == context.peerId {
                    SavedChatControllerRegistry.shared.remove(accountId: context.account.id, peerId: peerId, threadId: threadId)
                    return true
                }

                switch location {
                case let .peer(id):
                    if id == peerId {
                        if threadId == nil {
                            context.bindings.rootNavigation().close()
                        }
                    }
                case let .thread(data):
                    if threadId == nil {
                        if data.peerId == peerId {
                            context.bindings.rootNavigation().close()
                        }
                    } else {
                        if data.threadId == threadId {
                            context.bindings.rootNavigation().close()
                        }
                    }
                case .none:
                    break
                }

                return true
            }
}
