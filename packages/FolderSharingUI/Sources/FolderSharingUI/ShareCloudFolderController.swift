import Cocoa
import TelegramContext
import TelegramTheme
import GeneralRows
import InputDataUI
import Localization
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import AppAnalytics



private final class Arguments {
    let context: any AccountContextProtocol
    let environment: FolderSharingUIEnvironment
    let select: FolderSharingPeerSelection
    let copy:(String)->Void
    let share:(String)->Void
    let delete:()->Void
    let cantSelect:(Peer)->Void
    let nameLink: ()->Void
    let merge:()->Void
    init(context: any AccountContextProtocol, environment: FolderSharingUIEnvironment, select: FolderSharingPeerSelection, copy:@escaping(String)->Void, share:@escaping(String)->Void, delete: @escaping()->Void, cantSelect:@escaping(Peer)->Void, nameLink: @escaping()->Void, merge:@escaping()->Void) {
        self.context = context
        self.environment = environment
        self.select = select
        self.copy = copy
        self.share = share
        self.delete = delete
        self.cantSelect = cantSelect
        self.nameLink = nameLink
        self.merge = merge
    }
}

public func peerCanBeSharedInFolder(_ peer: Peer, filter: ChatListFilter? = nil) -> Bool {
    if peer.isChannel || peer.isSupergroup || peer.isGigagroup || peer.isGroup {
        if let channel = peer as? TelegramChannel {
            if channel.flags.contains(.requestToJoin) {
                return false
            }
        }
        return peer.addressName != nil || peer.groupAccess.canCreateInviteLink
    }
    return false
}

struct FolderSharingLinkState : Equatable {
    var filter: ChatListFilter
    var link: ExportedChatFolderLink?
    var peers: [FolderSharingPeer] = []
    var selected: Set<PeerId> = Set()
    var membersCount: [EnginePeer.Id: Int] = [:]
    func needsDiscardConfirmation(original: ExportedChatFolderLink?, initialSelected: Set<PeerId>) -> Bool {
        return original != nil && (original != link || initialSelected != selected)
    }

    var isEmpty: Bool {
        return peers.filter {
            peerCanBeSharedInFolder($0.peer, filter: filter)
        }.isEmpty
    }
}

private let _id_header = InputDataIdentifier("_id_header")
private let _id_link = InputDataIdentifier("_id_link")
func folderSharingLinkPeerIdentifier(_ id: PeerId) -> InputDataIdentifier {
    return InputDataIdentifier("_id_peer_\(id.toInt64())")
}

private func entries(_ state: FolderSharingLinkState, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []

    var sectionId:Int32 = 0
    var index: Int32 = 0


    let name: String = state.filter.title

    let titleText: String
    if !state.isEmpty {
        titleText = strings().shareFolderTitleTextOther(name, state.selected.count)
    } else {
        titleText = strings().shareFolderTitleTextEmpty
    }

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        let attr: NSMutableAttributedString = .init()
        attr.append(string: titleText, color: theme.colors.listGrayText, font: .normal(.text))
        attr.detectBoldColorInString(with: .medium(.text))
        return arguments.environment.makeAnimatedHeader(initialSize, stableId: stableId, text: attr)
    }))
    index += 1

    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1

    if let link = state.link {
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().shareFolderInviteLinkTitle), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1


        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_link, equatable: .init(link), comparable: nil, item: { initialSize, stableId in
            return arguments.environment.makeInvitationRow(initialSize, stableId: stableId, link: link, menuItems: {

                var items:[ContextMenuItem] = []

                if let link = state.link {
                    items.append(ContextMenuItem(strings().contextCopy, handler: {
                        arguments.copy(link.link)
                    }, itemImage: arguments.environment.menuImage(.copy)))

                    items.append(ContextMenuItem(strings().shareFolderContextNameLink, handler: {
                        arguments.nameLink()
                    }, itemImage: arguments.environment.menuImage(.edit)))

                    items.append(ContextSeparatorItem())

                    items.append(ContextMenuItem(strings().shareFolderContextDelete, handler: arguments.delete, itemMode: .destruct, itemImage: arguments.environment.menuImage(.delete)))

                }

                return .single(items)
            }, share: arguments.share, copyLink: arguments.copy)
        }))
        index += 1

        entries.append(.sectionId(sectionId, type: .customModern(20)))
        sectionId += 1
    }

    struct Tuple : Equatable {
        let peer: FolderSharingPeer
        let selected: Bool
        let viewType: GeneralViewType
        let selectable: Bool
        let enabled: Bool
    }

    var items: [Tuple] = []

    for (i, peer) in state.peers.enumerated() {
        items.append(.init(peer: peer, selected: state.selected.contains(peer.peer.id), viewType: bestGeneralViewType(state.peers, for: i), selectable: true, enabled: peerCanBeSharedInFolder(peer.peer, filter: state.filter)))
    }

    var rightItem = InputDataGeneralTextRightData(isLoading: false, text: nil)

    if items.count > 1, !state.isEmpty {
        let allSelected = items.filter {
            $0.selected && $0.enabled
        }.count == items.filter({ $0.enabled }).count

        rightItem = .init(isLoading: false, text: .initialize(string: allSelected ? strings().shareFolderDeselectAll : strings().shareFolderSelectAll, color: theme.colors.accent, font: .normal(.short)), action: {
            folderSharingToggleAll(items.filter { $0.enabled }.map { $0.peer.peer }, selected: state.selected, selection: arguments.select)
            arguments.merge()
        }, update: arc4random())
    }


    let headerText: String
    let infoText: String
    if state.isEmpty {
        headerText = strings().shareFolderHeaderEmptyTitle
        infoText = strings().shareFolderHeaderEmptyInfo
    } else {
        headerText = strings().shareFolderHeaderTitleOther(state.selected.count)
        infoText = strings().shareFolderHeaderInfo
    }

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(headerText), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem, rightItem: rightItem)))
    index += 1

    for item in items {

        let interactionType: FolderSharingPeerSelection?
        if item.selectable {
            interactionType = arguments.select
        } else {
            interactionType = nil
        }

        let text: String
        if item.enabled {
            text = strings().shareFolderStatusAllowed
        } else {
            if let data = state.filter.data, !data.includePeers.peers.contains(item.peer.peer.id) {
                text = strings().shareFolderStatusDisallowedNoLonger
            } else if item.peer.peer.isBot {
                text = strings().shareFolderStatusDisallowedBot
            } else if item.peer.peer.isUser {
                text = strings().shareFolderStatusDisallowedPrivateChats
            } else {
                text = strings().shareFolderStatusDisallowedOthers
            }
        }

        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: folderSharingLinkPeerIdentifier(item.peer.peer.id), equatable: .init(item), comparable: nil, item: { initialSize, stableId in
            return arguments.environment.makePeerRow(initialSize, peer: item.peer.peer, enabled: item.enabled, status: text, selection: interactionType, viewType: item.viewType, disabledAction: {
                arguments.cantSelect(item.peer.peer)
            })
        }))
        index += 1
    }

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(infoText), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1



    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1


    return entries
}

public func ShareCloudFolderController(context: any AccountContextProtocol, environment: FolderSharingUIEnvironment, filter: ChatListFilter, link: ExportedChatFolderLink?, updated:@escaping(ExportedChatFolderLink, ExportedChatFolderLink?)->Void) -> InputDataModalController {

    let actionsDisposable = DisposableSet()
    var close:(()->Void)? = nil

    let initialState = FolderSharingLinkState(filter: filter, link: link, peers: [], selected: [])
    let selected = environment.makeSelection()
    let statePromise = ValuePromise<FolderSharingLinkState>(ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((FolderSharingLinkState) -> FolderSharingLinkState) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }

    var initialSelected: Set<PeerId> = Set()

    if let data = filter.data {

        let peerIds = ((link?.peerIds ?? []) + data.includePeers.peers).uniqueElements

        let peers = combineLatest(peerIds.map {  folderSharingPeerView(peerId: $0, postbox: context.account.postbox) }) |> map {
            return $0.compactMap(FolderSharingPeer.init).filter { peer in
                if let peer = peer.peer as? TelegramGroup {
                    return peer.migrationReference == nil
                } else {
                    return true
                }
            }
        } |> deliverOnMainQueue

        let participantCount = context.engine.data.get(EngineDataMap(peerIds.map(TelegramEngine.EngineData.Item.Peer.ParticipantCount.init(id:))))



        actionsDisposable.add(combineLatest(peers, participantCount).start(next: { [weak selected] peers, participantCount in

            let access = peers.filter {
                peerCanBeSharedInFolder($0.peer, filter: filter)
            }
            let cantInvite = peers.filter {
                !peerCanBeSharedInFolder($0.peer, filter: filter)
            }

            var memberCounts: [EnginePeer.Id: Int] = [:]
            for (id, count) in participantCount {
                if let count = count {
                    memberCounts[id] = count
                }
            }


            let peers = access + cantInvite

            folderSharingInitializeSelection(access.map { $0.peer }, selectedIds: link.map { Set($0.peerIds) }, selection: selected)

            initialSelected = selected?.selectedPeerIds ?? []

            updateState { current in
                var current = current
                current.peers = peers
                current.selected = initialSelected
                current.membersCount = memberCounts
                return current
            }

        }))
    }



    selected.action = { [weak selected] peerId, _ in
        guard let selected = selected else {
            return
        }
        let peer = stateValue.with { $0.peers.first(where: { $0.peer.id == peerId }) }?.peer
        if let peer = peer {
            selected.toggleFromRow(peer)
        }
        updateState { current in
            var current = current
            current.selected = selected.selectedPeerIds
            return current
        }
    }


    let arguments = Arguments(context: context, environment: environment, select: selected, copy: { link in
        environment.notify( strings().shareLinkCopied)
        environment.copyToClipboard(link)
    }, share: { link in
        environment.shareLink(link)
    }, delete: {
        if let link = stateValue.with ({ $0.link }) {
            environment.confirmAction( information: strings().chatListFilterInviteLinkDeleteConfirm, ok: strings().chatListFilterInviteLinkDelete, successHandler: {
                let signal = context.engine.peers.deleteChatFolderLink(filterId: filter.folderSharingId, link: link)
                _ = showModalProgress(signal: signal, for: context.window).start()
                folderSharingDeletedLink(link, updated: updated, close: { close?() })
            })
        }
    }, cantSelect: { peer in
        let text: String
        if let data = filter.data, !data.includePeers.peers.contains(peer.id) {
            text = strings().shareFolderStatusDisallowedAlertNoLonger
        } else if peer.isUser {
            text = strings().shareFolderStatusDisallowedAlertPrivateChats
        } else if peer.isBot {
            text = strings().shareFolderStatusDisallowedAlertBot
        } else if peer.isChannel {
            text = strings().shareFolderStatusDisallowedAlertChannel
        } else {
            text = strings().shareFolderStatusDisallowedAlertGroup
        }
        environment.notify( text)
    }, nameLink: {
        environment.promptLinkName(initialText: stateValue.with { $0.link?.title ?? "" }, callback: { name in
            updateState { current in
                var current = current
                current.link?.title = name
                return current
            }
        })
    }, merge: {
        updateState { current in
            var current = current
            current.selected = selected.selectedPeerIds
            return current
        }
    })


    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    let title: String
    if let linkTitle = link?.title, !linkTitle.isEmpty {
        title = linkTitle
    } else {
        title = strings().shareFolderTitle
    }

    let controller = InputDataController(dataSignal: signal, title: title)
    controller.analyticsScreen = .settingsFoldersSharing

    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().modalDone, accept: { [weak controller] in
        controller?.validateInputValues()
    }, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: link != nil ? modalInteractions : nil, closeHandler: { f in
        if let link = link {
            let state = stateValue.with { $0 }
            if state.needsDiscardConfirmation(original: link, initialSelected: initialSelected) {
                environment.confirmAction( information: strings().shareFolderDiscardText, ok: strings().shareFolderDiscardOk, successHandler: {
                    f()
                })
            } else {
                f()
            }
        } else {
            f()
        }
    })


    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })

    controller.validateData = { data in
        let state = stateValue.with { $0 }
        folderSharingSaveLink(state: state, original: link, edit: { current, selected, success, failure in
            _ = showModalProgress(signal: context.engine.peers.editChatFolderLink(filterId: state.filter.folderSharingId, link: current, title: current.title, peerIds: Array(selected), revoke: false), for: context.window).start(next: success, error: { _ in failure() })
        }, updated: updated, success: environment.showSuccess, failure: {
            environment.alert(strings().unknownError)
        }, delete: arguments.delete, close: { close?() })
        return .none

    }


    close = { [weak modalController] in
        modalController?.modal?.close()
    }


    controller.afterTransaction = { [weak modalInteractions, weak modalController] controller in
        modalInteractions?.updateDone { title in
            title.set(background: stateValue.with { $0.selected.isEmpty } ? theme.colors.redUI : theme.colors.accent, for: .Normal)
            title.set(text: stateValue.with { $0.selected.isEmpty } ? strings().shareFolderDoneDelete : strings().shareFolderDoneDone, for: .Normal)
        }
        if let title = stateValue.with({ $0.link?.title }), !title.isEmpty {
            controller.centerModalHeader = .init(title: title)
            modalController?.updateLocalizationAndTheme(theme: theme)
        }
    }


    return modalController
}


