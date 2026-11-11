import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows
import InputDataUI
import Cocoa
import TGUIKit
import SwiftSignalKit
import Postbox
import TelegramCore
import WalletContext
import Localization
import AppAnalytics

private let walletCollapsedPeersLimit = 5
private let walletExpandedPeersLimit = 30

func walletRecipientIsEligiblePeer(_ peer: EnginePeer, accountPeerId: PeerId) -> Bool {
    guard case let .user(user) = peer else {
        return false
    }
    return user.canBeDirectRecipient(accountPeerId: accountPeerId)
}

func walletRecipientSearchPeers(local: [EnginePeer], remote: [EnginePeer]) -> [EnginePeer] {
    var seen = Set<PeerId>()
    return (local + remote).filter { seen.insert($0.id).inserted }
}

func walletSendIsTonDomainCandidate(_ value: String) -> Bool {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return (value.hasSuffix(".ton") || value.hasSuffix(".t.me")) && value.count > 4 && !value.contains(" ")
}

@available(macOS 10.15, *)
func walletNeedsRecipientResolution(_ value: String) -> Bool {
    return WalletContext.transferAddress(from: value) != nil || walletSendIsTonDomainCandidate(value)
}

@available(macOS 10.15, *)
enum WalletRecipientMode: Equatable {
    case transfer
    case collectible(WalletContext.Collectible)
}

@available(macOS 10.15, *)
enum WalletRecipientDestination: Equatable {
    case send(address: String, publicKey: Data?)
    case collectiblePreview(address: String, collectible: WalletContext.Collectible)
}

@available(macOS 10.15, *)
func walletRecipientDestination(mode: WalletRecipientMode, address: String, publicKey: Data?) -> WalletRecipientDestination {
    switch mode {
    case .transfer:
        return .send(address: address, publicKey: publicKey)
    case let .collectible(collectible):
        return .collectiblePreview(address: address, collectible: collectible)
    }
}

func walletRecipientPeerAddress(_ addresses: [WalletUserAddress], peerId: PeerId) -> String? {
    guard let entry = addresses.first(where: { $0.userId == peerId }) else {
        return nil
    }
    let address = entry.address.trimmingCharacters(in: .whitespacesAndNewlines)
    return address.isEmpty ? nil : address
}

@available(macOS 10.15, *)
struct WalletRecipientState: Equatable {
    var address: String = ""
    var resolved: WalletContext.ResolvedTransferRecipient? = nil
    var owner: WalletAddressOwner? = nil
    var isResolving: Bool = false
    var resolveFailed: Bool = false
    var resolveRevision: Int = 0
    var recentPeers: [EnginePeer]? = nil
    var isSearchingLocalPeers: Bool = false
    var isSearchingRemotePeers: Bool = false
    var localSearchResults: [EnginePeer] = []
    var remoteSearchResults: [EnginePeer] = []
    var peerAddresses: [PeerId: String] = [:]
    var showsAllPeers: Bool = false
    var resolvingPeerId: PeerId? = nil
    var transferAmount: Int64? = nil
    var transferComment: String? = nil

    var isSearching: Bool {
        return isSearchingLocalPeers || isSearchingRemotePeers
    }

    mutating func beginSearch(_ query: String) -> Bool {
        let searches = !query.isEmpty && WalletContext.transferAddress(from: query) == nil && !walletSendIsTonDomainCandidate(query)
        if !searches || recipientQuery(self).isEmpty {
            localSearchResults = []
            remoteSearchResults = []
        }
        isSearchingLocalPeers = searches
        isSearchingRemotePeers = searches
        return searches
    }

    mutating func finishLocalSearch(_ peers: [EnginePeer]) {
        localSearchResults = peers
        isSearchingLocalPeers = false
    }

    mutating func finishRemoteSearch(_ peers: [EnginePeer]) {
        remoteSearchResults = peers
        isSearchingRemotePeers = false
    }
}

private func walletPeerStatus(_ peer: EnginePeer, addresses: [PeerId: String]) -> String? {
    if let username = peer.addressName, !username.isEmpty {
        return "@\(username)"
    }
    if let address = addresses[peer.id] {
        return formatTonAddress(address)
    }
    return nil
}

@available(macOS 10.15, *)
private func recipientQuery(_ state: WalletRecipientState) -> String {
    return state.address.trimmingCharacters(in: .whitespacesAndNewlines)
}

@available(macOS 10.15, *)
func walletMatchingPeers(_ state: WalletRecipientState) -> [EnginePeer] {
    guard state.resolved == nil else {
        return []
    }
    let peers = recipientQuery(state).isEmpty ? state.recentPeers ?? [] : walletRecipientSearchPeers(local: state.localSearchResults, remote: state.remoteSearchResults)
    var seen = Set<PeerId>()
    return Array(peers.filter { seen.insert($0.id).inserted }.prefix(walletExpandedPeersLimit))
}

@available(macOS 10.15, *)
func walletShowsNoRecipientResults(_ state: WalletRecipientState) -> Bool {
    guard state.resolved == nil, !state.isResolving, state.resolveFailed, !state.isSearching else {
        return false
    }
    guard !recipientQuery(state).isEmpty else {
        return false
    }
    return walletMatchingPeers(state).isEmpty
}

@available(macOS 10.15, *)
func walletRecipientAddressLooksInvalid(_ state: WalletRecipientState) -> Bool {
    guard state.address.count >= walletAddressLength, isValidTonAddress(state.address) else {
        return false
    }
    if walletSendIsTonDomainCandidate(state.address) {
        return false
    }
    return WalletContext.transferAddress(from: state.address) == nil
}

@available(macOS 10.15, *)
private final class Arguments {
    let environment: WalletUIEnvironment
    let filterRecipient: (String) -> String
    let openRecipient: (WalletContext.ResolvedTransferRecipient, WalletAddressOwner?) -> Void
    let selectPeer: (EnginePeer) -> Void
    let showMorePeers: () -> Void
    var moveToGifts: (() -> Void)?

    init(environment: WalletUIEnvironment, filterRecipient: @escaping (String) -> String, openRecipient: @escaping (WalletContext.ResolvedTransferRecipient, WalletAddressOwner?) -> Void, selectPeer: @escaping (EnginePeer) -> Void, showMorePeers: @escaping () -> Void) {
        self.environment = environment
        self.filterRecipient = filterRecipient
        self.openRecipient = openRecipient
        self.selectPeer = selectPeer
        self.showMorePeers = showMorePeers
    }
}

private let _id_address = InputDataIdentifier("_id_address")
private let _id_resolving = InputDataIdentifier("_id_resolving")
private let _id_recipient = InputDataIdentifier("_id_recipient")
private let _id_no_results = InputDataIdentifier("_id_no_results")
private let _id_show_more_peers = InputDataIdentifier("_id_show_more_peers")
private let _id_move_to_gifts = InputDataIdentifier("_id_move_to_gifts")
private func _id_recent_peer(_ peerId: PeerId) -> InputDataIdentifier {
    return InputDataIdentifier("_id_recent_peer_\(peerId.toInt64())")
}

@available(macOS 10.15, *)
private func entries(_ state: WalletRecipientState, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .customModern(16)))
    sectionId += 1

    let addressPlaceholder = strings().walletRecipientControllerAddressPlaceholder
    let addressError: InputDataValueError?
    if walletRecipientAddressLooksInvalid(state) {
        addressError = InputDataValueError(description: strings().walletRecipientControllerInvalidAddress, target: .data)
    } else {
        addressError = nil
    }
    entries.append(.input(sectionId: sectionId, index: index, value: .string(state.address), error: addressError, identifier: _id_address, mode: .plain, data: .init(viewType: .singleItem), placeholder: nil, inputPlaceholder: addressPlaceholder, filter: arguments.filterRecipient, limit: 512))
    index += 1

    if state.address.isEmpty, state.resolved == nil, state.owner == nil, let moveToGifts = arguments.moveToGifts {
        entries.append(.sectionId(10, type: .customModern(12)))
        entries.append(.custom(sectionId: 11, index: 100, value: .none, identifier: _id_move_to_gifts, equatable: nil, comparable: nil, item: { initialSize, stableId in
            let thumb = walletMoveActionIcon("Wallet_MoveToGifts", diameter: 30).map { GeneralThumbAdditional(thumb: $0, textInset: 40) }
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().giftTransferMoveToGifts, nameStyle: ControlStyle(font: .medium(.title), foregroundColor: theme.colors.text), type: .none, viewType: .singleItem, action: moveToGifts, thumb: thumb)
        }))
    }

    if walletShowsNoRecipientResults(state) {
        let query = recipientQuery(state)
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_no_results, equatable: .init(query), comparable: nil, item: { initialSize, stableId in
            return WalletRecipientNoResultsItem(initialSize, stableId: stableId, query: query)
        }))
        return entries
    }

    if state.isResolving {
        entries.append(.sectionId(sectionId, type: .customModern(8)))
        sectionId += 1

        let resolvingText = strings().walletRecipientControllerResolving
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_resolving, equatable: .init(resolvingText), comparable: nil, item: { initialSize, stableId in
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: resolvingText, type: .loading, viewType: .singleItem)
        }))
        index += 1
    } else if let resolved = state.resolved {
        entries.append(.sectionId(sectionId, type: .customModern(12)))
        sectionId += 1

        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().walletRecipientControllerRecipientHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1

        if let owner = state.owner {
            let status = walletPeerStatus(owner.peer, addresses: [owner.peer.id: resolved.address])
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_recipient, equatable: .init(WalletSendLinkedPeer(address: resolved.address, peer: owner.peer)), comparable: nil, item: { initialSize, stableId in
                return arguments.environment.makePeerRow(initialSize, stableId: stableId, peer: owner.peer._asPeer(), status: status, isResolving: false, viewType: .singleItem, action: { arguments.openRecipient(resolved, owner) }, deselect: nil)
            }))
        } else {
            let name = resolved.displayName ?? formatTonAddress(resolved.address)
            let description = resolved.displayName != nil ? formatTonAddress(resolved.address) : nil
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_recipient, equatable: .init(resolved), comparable: nil, item: { initialSize, stableId in
                return GeneralInteractedRowItem(initialSize, stableId: stableId, name: name, icon: NSImage(named: "Wallet_Ton")?.precomposed(), description: description, type: .next, viewType: .singleItem, action: {
                    arguments.openRecipient(resolved, nil)
                })
            }))
        }
        index += 1
    }

    sectionId = 20
    index = 200
    let allPeers = walletMatchingPeers(state)
    let hasMorePeers = !state.showsAllPeers && allPeers.count > walletCollapsedPeersLimit
    let recentPeers = hasMorePeers ? Array(allPeers.prefix(walletCollapsedPeersLimit)) : allPeers
    if !recentPeers.isEmpty {
        entries.append(.sectionId(sectionId, type: .customModern(12)))
        sectionId += 1

        let recentTitle = recipientQuery(state).isEmpty ? strings().walletRecipientControllerRecentHeader : strings().walletRecipientControllerPeopleHeader
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(recentTitle), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1

        struct RecentPeerTuple: Equatable {
            let peer: EnginePeer
            let status: String?
            let isResolving: Bool
            let viewType: GeneralViewType
        }
        for (position, peer) in recentPeers.enumerated() {
            let viewType: GeneralViewType
            let isLast = position == recentPeers.count - 1 && !hasMorePeers
            if position == 0 && isLast {
                viewType = .singleItem
            } else if position == 0 {
                viewType = .firstItem
            } else if isLast {
                viewType = .lastItem
            } else {
                viewType = .innerItem
            }
            let tuple = RecentPeerTuple(peer: peer, status: walletPeerStatus(peer, addresses: state.peerAddresses), isResolving: state.resolvingPeerId == peer.id, viewType: viewType)
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_recent_peer(peer.id), equatable: .init(tuple), comparable: nil, item: { initialSize, stableId in
                return arguments.environment.makePeerRow(initialSize, stableId: stableId, peer: tuple.peer._asPeer(), status: tuple.status, isResolving: tuple.isResolving, viewType: tuple.viewType, action: { arguments.selectPeer(tuple.peer) }, deselect: nil)
            }))
            index += 1
        }
        if hasMorePeers {
            let showMoreText = strings().walletRecipientControllerShowMore
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_show_more_peers, equatable: .init(showMoreText), comparable: nil, item: { initialSize, stableId in
                return GeneralInteractedRowItem(initialSize, stableId: stableId, name: showMoreText, nameStyle: ControlStyle(font: .normal(.title), foregroundColor: walletClassicAccent), type: .none, viewType: .lastItem, action: arguments.showMorePeers, thumb: GeneralThumbAdditional(thumb: theme.icons.chatSearchUp.highlight(color: walletClassicAccent), textInset: 52, thumbInset: 4))
            }))
            index += 1
        }
    }

    entries.append(.sectionId(sectionId, type: .customModern(18)))
    sectionId += 1

    return entries
}

@available(macOS 10.15, *)
func walletRecipientSendOpensChat(hasPeer: Bool, address: String?) -> Bool {
    return hasPeer && address != nil
}

@available(macOS 10.15, *)
func makeWalletRecipientController(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, initialQuery: String?, initialAmount: Int64?, mode: WalletRecipientMode = .transfer, transferAnimation: WalletSendTransferAnimation? = nil, onSuccess: (() -> Void)? = nil) -> InputDataModalController {
    let actionsDisposable = DisposableSet()
    let resolveDisposable = MetaDisposable()
    actionsDisposable.add(resolveDisposable)
    let searchDisposable = MetaDisposable()
    actionsDisposable.add(searchDisposable)
    let remoteSearchDisposable = MetaDisposable()
    actionsDisposable.add(remoteSearchDisposable)
    let peerAddressDisposable = MetaDisposable()
    actionsDisposable.add(peerAddressDisposable)

    let initialState = WalletRecipientState()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((WalletRecipientState) -> WalletRecipientState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    var getController: (() -> InputDataController?)? = nil
    var getModal: (() -> InputDataModalController?)? = nil
    var sendStep: WalletSendStep? = nil
    var openedCollectiblePreview = false
    var pinnedHeight: CGFloat = 0

    var window: Window {
        return walletUIWindow(context, getController?())
    }

    var searchRevision = 0

    let walletUsers: ([EnginePeer]) -> Signal<([EnginePeer], [PeerId: String]), NoError> = { peers in
        let candidates = Array(peers.prefix(100))
        guard !candidates.isEmpty else {
            return .single(([], [:]))
        }
        return context.engine.wallet.getUserAddresses(userIds: candidates.map { $0.id }, force: false)
        |> map { addresses -> ([EnginePeer], [PeerId: String]) in
            var addressByPeer: [PeerId: String] = [:]
            for entry in addresses {
                let address = entry.address.trimmingCharacters(in: .whitespacesAndNewlines)
                if !address.isEmpty, let userId = entry.userId as PeerId? {
                    addressByPeer[userId] = address
                }
            }
            return (candidates.filter { addressByPeer[$0.id] != nil }, addressByPeer)
        }
        |> `catch` { _ in Signal<([EnginePeer], [PeerId: String]), NoError>.single((candidates, [:])) }
    }

    let updateSearch: (String) -> Void = { query in
        searchRevision += 1
        let revision = searchRevision
        searchDisposable.set(nil)
        remoteSearchDisposable.set(nil)
        var searches = false
        updateState { current in
            var current = current
            searches = current.beginSearch(query)
            return current
        }
        guard searches else {
            return
        }
        searchDisposable.set((context.engine.contacts.searchLocalPeers(query: query.lowercased())
        |> map { results -> [EnginePeer] in
            return results.compactMap { $0.chatMainPeer }.filter { walletRecipientIsEligiblePeer($0, accountPeerId: context.peerId) }
        }
        |> mapToSignal(walletUsers)
        |> deliverOnMainQueue).start(next: { peers, addresses in
            guard searchRevision == revision else {
                return
            }
            updateState { current in
                var current = current
                current.finishLocalSearch(peers)
                current.peerAddresses.merge(addresses, uniquingKeysWith: { $1 })
                return current
            }
        }))
        remoteSearchDisposable.set((Signal<Void, NoError>.single(Void())
        |> delay(0.4, queue: .mainQueue())
        |> mapToSignal { _ in
            return context.engine.contacts.searchRemotePeers(query: query)
        }
        |> map { local, global -> [EnginePeer] in
            return (local + global).map(\.peer).filter { walletRecipientIsEligiblePeer($0, accountPeerId: context.peerId) }
        }
        |> mapToSignal(walletUsers)
        |> deliverOnMainQueue).start(next: { peers, addresses in
            guard searchRevision == revision else {
                return
            }
            updateState { current in
                var current = current
                current.finishRemoteSearch(peers)
                current.peerAddresses.merge(addresses, uniquingKeysWith: { $1 })
                return current
            }
        }))
    }

    let updateAddress: (String) -> Void = { value in
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard stateValue.with({ $0.address }) != value else {
            return
        }
        resolveDisposable.set(nil)
        updateSearch(value)
        var revision = 0
        updateState { current in
            var current = current
            current.address = value
            current.showsAllPeers = false
            current.resolved = nil
            current.owner = nil
            current.resolveFailed = false
            current.isResolving = !value.isEmpty
            current.resolveRevision += 1
            revision = current.resolveRevision
            return current
        }
        guard !value.isEmpty else {
            return
        }
        let recipient: Signal<WalletContext.ResolvedTransferRecipient?, WalletContext.WalletError>
        if let address = walletSendRecipientAddress(value) {
            recipient = .single(WalletContext.ResolvedTransferRecipient(address: address, displayName: nil))
        } else {
            recipient = Signal<Void, WalletContext.WalletError>.single(Void())
            |> delay(0.4, queue: .mainQueue())
            |> mapToSignal { _ in
                return walletContext.resolveTransferRecipient(value)
            }
        }
        resolveDisposable.set((recipient
        |> mapToSignal { recipient -> Signal<(WalletContext.ResolvedTransferRecipient?, WalletAddressOwner?), WalletContext.WalletError> in
            guard let recipient else {
                return .single((nil, nil))
            }
            return walletAddressOwner(context: context, address: recipient.address)
            |> timeout(5.0, queue: .mainQueue(), alternate: .single(nil))
            |> map { owner -> (WalletContext.ResolvedTransferRecipient?, WalletAddressOwner?) in
                guard let owner, walletRecipientIsEligiblePeer(owner.peer, accountPeerId: context.peerId) else {
                    return (recipient, nil)
                }
                return (recipient, owner)
            }
            |> castError(WalletContext.WalletError.self)
        }
        |> deliverOnMainQueue).start(next: { recipient, owner in
            guard stateValue.with({ $0.resolveRevision }) == revision else {
                return
            }
            updateState { current in
                var current = current
                current.isResolving = false
                current.resolved = recipient
                current.owner = owner
                current.resolveFailed = recipient == nil
                return current
            }
        }, error: { _ in
            guard stateValue.with({ $0.resolveRevision }) == revision else {
                return
            }
            updateState { current in
                var current = current
                current.isResolving = false
                current.resolveFailed = true
                return current
            }
        }))
    }

    let openSendStep: (String?, Data?, Peer?, Bool) -> Void = { address, publicKey, peer, isTypedRecipient in
        guard sendStep == nil, let modalController = getModal?() else {
            return
        }
        let state = stateValue.with { $0 }
        let opensRecipientChat = walletRecipientSendOpensChat(hasPeer: peer != nil, address: address)
        let step = makeWalletSendController(context: context, environment: environment, walletContext: walletContext, initialAddress: address, initialRecipientPublicKey: publicKey, peer: peer, initialAmount: isTypedRecipient ? state.transferAmount ?? initialAmount : nil, initialComment: isTypedRecipient ? state.transferComment : nil, transferAnimation: opensRecipientChat ? nil : transferAnimation, completed: opensRecipientChat ? peer.map { walletOpenRecipientChat(environment: environment, window: window, peerId: $0.id) } : nil, getModal: {
            return getModal?()
        }, onBack: {
            getModal?()?.pop(animated: true)
        })
        step.controller._frameRect = modalController.frame.size.bounds
        sendStep = step
        modalController.fixedHeight = nil
        modalController.push(step.controller, animated: true)
        step.updateButton()
    }

    let openCollectiblePreview: (String, EnginePeer?, WalletContext.Collectible) -> Void = { address, recipientPeer, collectible in
        guard !openedCollectiblePreview, let modalController = getModal?() else {
            return
        }
        openedCollectiblePreview = true
        let targetWindow = window
        modalController.close()
        showModal(with: WalletTransactionController(context: context, environment: environment, walletContext: walletContext, subject: .collectiblePreview(address: address, recipientPeer: recipientPeer, collectible: collectible), onSuccess: onSuccess), for: targetWindow)
    }

    let openRecipient: (WalletContext.ResolvedTransferRecipient, WalletAddressOwner?) -> Void = { recipient, owner in
        switch walletRecipientDestination(mode: mode, address: recipient.address, publicKey: owner?.publicKey) {
        case let .send(address, publicKey):
            openSendStep(address, publicKey, owner?.peer._asPeer(), true)
        case let .collectiblePreview(address, collectible):
            openCollectiblePreview(address, owner?.peer, collectible)
        }
    }

    let arguments = Arguments(environment: environment, filterRecipient: { value in
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("ton:") else {
            let filtered = walletFilteredRecipientInput(trimmed)
            if filtered == trimmed {
                return filtered
            }
            return trimmed.components(separatedBy: .newlines).joined(separator: " ")
        }
        let parsed = walletParseRecipient(trimmed)
        updateState { current in
            var current = current
            current.transferAmount = parsed.amount
            current.transferComment = parsed.comment
            return current
        }
        updateAddress(parsed.address)
        return walletFilteredRecipientInput(parsed.address)
    }, openRecipient: openRecipient, selectPeer: { selectedPeer in
        guard stateValue.with({ $0.resolvingPeerId == nil }) else {
            return
        }
        guard case let .collectible(collectible) = mode else {
            openSendStep(nil, nil, selectedPeer._asPeer(), false)
            return
        }
        updateState { current in
            var current = current
            current.resolvingPeerId = selectedPeer.id
            return current
        }
        peerAddressDisposable.set((context.engine.wallet.getUserAddresses(userIds: [selectedPeer.id], force: true)
        |> map { addresses in
            walletRecipientPeerAddress(addresses, peerId: selectedPeer.id)
        }
        |> `catch` { _ in Signal<String?, NoError>.single(nil) }
        |> deliverOnMainQueue).start(next: { address in
            guard stateValue.with({ $0.resolvingPeerId == selectedPeer.id }) else {
                return
            }
            updateState { current in
                var current = current
                current.resolvingPeerId = nil
                return current
            }
            if let address {
                openCollectiblePreview(address, selectedPeer, collectible)
            } else {
                environment.showModalText(for: window, text: strings().walletRecipientControllerUnknownError)
            }
        }))
    }, showMorePeers: {
        updateState { current in
            var current = current
            current.showsAllPeers = true
            return current
        }
    })

    actionsDisposable.add((context.engine.messages.chatList(group: .root, count: 100)
    |> take(1)
    |> map { chatList -> [EnginePeer] in
        var seen = Set<PeerId>()
        var peers: [EnginePeer] = []
        for item in chatList.items.reversed() {
            guard case let .user(user) = item.renderedPeer.chatMainPeer else {
                continue
            }
            guard user.canBeDirectRecipient(accountPeerId: context.peerId), seen.insert(user.id).inserted else {
                continue
            }
            peers.append(.user(user))
        }
        return peers
    }
    |> mapToSignal(walletUsers)
    |> deliverOnMainQueue).start(next: { peers, addresses in
        updateState { current in
            var current = current
            current.recentPeers = peers
            current.peerAddresses.merge(addresses, uniquingKeysWith: { $1 })
            return current
        }
    }))

    let continueAction: () -> Void = {
        if let sendStep, getModal?()?.current === sendStep.controller {
            sendStep.submit()
            return
        }
        let state = stateValue.with { $0 }
        if let resolved = state.resolved, !state.isResolving {
            openRecipient(resolved, state.owner)
        } else if !recipientQuery(state).isEmpty {
            getController?()?.proccessValidation(.fail(.fields([_id_address: .shake])))
        }
    }

    let signal = statePromise.get()
    |> deliverOnPrepareQueue
    |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    if case let .collectible(collectible) = mode, collectible.kind == .gift, let slug = collectible.giftSlug {
        arguments.moveToGifts = {
            walletMoveCollectibleToGifts(context: context, environment: environment, walletContext: walletContext, collectible: collectible, slug: slug, name: collectible.name, window: context.window)
        }
    }

    let controller = InputDataController(dataSignal: signal, title: strings().walletRecipientControllerTitle, hasDone: false, identifier: "wallet-recipient")
    switch mode {
    case .transfer:
        controller.analyticsScreen = AnalyticsScreen.walletTransferRecipient
    case .collectible:
        controller.analyticsScreen = AnalyticsScreen.walletCollectibleRecipient
    }

    getController = { [weak controller] in
        return controller
    }

    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    controller.updateDatas = { data in
        updateAddress(data[_id_address]?.stringValue ?? "")
        return .none
    }

    controller.validateData = { _ in
        return .success(.custom {
            continueAction()
        })
    }

    controller.returnKeyInvocation = { identifier, _ in
        if identifier == _id_address {
            continueAction()
            return .nothing
        }
        return .default
    }

    let continueTitle = strings().walletRecipientControllerContinue
    let modalInteractions = ModalInteractions(acceptTitle: continueTitle, accept: {
        continueAction()
    }, singleButton: true, customTheme: { walletModalTheme })

    let modalController = WalletModalController(controller, modalInteractions: modalInteractions, closeHandler: { close in
        if let sendStep, getModal?()?.current === sendStep.controller {
            sendStep.requestDismiss(close)
        } else {
            close()
        }
    }, size: NSMakeSize(360, 0))

    getModal = { [weak modalController] in
        return modalController
    }

    let updateButton: () -> Void = { [weak modalInteractions] in
        guard getModal?()?.current === getController?() else {
            return
        }
        modalInteractions?.updateDone { button in
            WalletSendButtonContentView.remove(from: button)
            button.isEnabled = stateValue.with { $0.resolved != nil && !$0.isResolving }
            button.set(text: continueTitle, for: .Normal)
            button.set(subtext: nil, for: .Normal)
        }
        modalInteractions?.acceptTitle = continueTitle
    }

    controller.afterTransaction = { [weak modalController] controller in
        updateButton()
        guard let modalController, modalController.current === controller, pinnedHeight == 0 else {
            return
        }
        let table = controller.tableView
        guard table.count >= 2, table.frame.width > 0 else {
            return
        }
        var headerHeight: CGFloat = 0
        for index in 0 ..< 2 {
            headerHeight += table.item(at: index).height
        }
        let probe = WalletRecipientNoResultsItem(NSMakeSize(table.frame.width, 0), stableId: _id_no_results, query: "")
        _ = probe.makeSize(table.frame.width, oldWidth: 0)
        pinnedHeight = headerHeight + probe.height
        modalController.fixedHeight = pinnedHeight
    }

    modalController.didPopController = { [weak modalController] _ in
        sendStep = nil
        updateButton()
        modalController?.fixedHeight = pinnedHeight
    }

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })

    controller.rightModalHeader = ModalHeaderData(image: theme.icons.chatActionsActive, contextMenu: {
        if let sendStep, getModal?()?.current === sendStep.controller {
            return sendStep.controller.rightModalHeader?.contextMenu?() ?? []
        }
        guard case let .wallet(info) = walletContext.stateValue.phase else {
            return []
        }
        let targetWindow = window
        return [ContextMenuItem(strings().walletRecipientControllerDepositFunds, handler: {
            showModal(with: WalletReceiveController(context: context, environment: environment, walletContext: walletContext, address: info.address), for: targetWindow)
        }, itemImage: environment.menuImage(.menu_plus))]
    })

    if let initialQuery, !initialQuery.isEmpty {
        let parsed = walletParseRecipient(initialQuery)
        updateState { current in
            var current = current
            current.transferAmount = parsed.amount
            current.transferComment = parsed.comment
            return current
        }
        updateAddress(parsed.address)
    }

    return modalController
}

@available(macOS 10.15, *)
public func walletMoveCollectibleToGifts(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, collectible: WalletContext.Collectible?, slug: String, name: String, window: Window) {
    let title = strings().giftMoveToGiftsTitle
    let move = strings().giftMoveToWalletMove
    let networkFee: Signal<Int64?, NoError>
    if let address = collectible?.address ?? walletContext.stateValue.collectibles.items.first(where: { $0.giftSlug == slug })?.address {
        networkFee = walletContext.estimateTransferFee(address: address, comment: .none)
        |> map { Optional($0.fee) }
        |> `catch` { _ -> Signal<Int64?, NoError> in .single(nil) }
    } else {
        networkFee = .single(nil)
    }
    environment.presentConfirmation(window: window, header: title, ok: move, cancel: strings().modalCancel, content: { size, stableId, updateSize in
        WalletGiftDepositConfirmationRowItem(size, stableId: stableId, context: context, environment: environment, networkFee: networkFee, updateSize: updateSize)
    }, confirmed: {
        _ = showModalProgress(signal: context.engine.payments.depositStarGift(peerId: context.peerId, slug: slug, hideSender: false), for: window).start(next: { payload in
            let collectible = collectible ?? walletContext.stateValue.collectibles.items.first(where: { $0.giftSlug == slug }) ?? WalletContext.Collectible(address: payload.nftAddress, name: name, kind: .gift, giftSlug: slug)
            _ = showModalProgress(signal: walletContext.prepareCollectibleDeposit(collectible: collectible, address: payload.nftAddress, payload: payload.payload, amount: payload.amount), for: window).start(next: { prepared in
                submitWalletTransferDetached(context: context, environment: environment, walletContext: walletContext, prepared: prepared, window: window, recipientName: nil, submitted: {
                    closeAllModals(window: window)
                    environment.showModalText(for: window, text: strings().giftMoveToGiftsSuccess, button: strings().alertView, callback: { _ in
                        _ = showModalProgress(signal: context.engine.payments.getUniqueStarGift(slug: slug), for: window).start(next: { gift in
                            environment.openGift(gift)
                        })
                    })
                })
            }, error: { error in
                presentWalletAuthorizationError(environment: environment, error, window: window, fallbackTitle: strings().walletSendControllerTransferFailedTitle, fallbackText: strings().walletSendControllerSendFailedInfo)
            })
        }, error: { _ in
            environment.alert(for: window, info: strings().unknownError)
        })
    })
}
