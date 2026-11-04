import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramContext
import TelegramTheme
import TelegramUtils
import Localization
import GeneralRows
import InputDataUI
import ShortPeerRow
import AlertsUI

private let frequentContactsLimit = 15

private struct BlockchainRow: Equatable {
    let title: String
    let subtitle: String?
    let icon: NSImage
}

private final class GiftTransferDestinationRowItem: GeneralRowItem {
    let titleLayout: TextViewLayout
    let subtitleLayout: TextViewLayout?
    let icon: CGImage
    let textSpacing: CGFloat = 2
    let iconSize = NSMakeSize(32, 32)
    let iconInset: CGFloat = 18
    let textInset: CGFloat = 60

    init(_ initialSize: NSSize, stableId: AnyHashable, destination: BlockchainRow, action: @escaping () -> Void) {
        self.titleLayout = TextViewLayout(.initialize(string: destination.title, color: theme.colors.text, font: .medium(.title)), maximumNumberOfLines: 1)
        self.subtitleLayout = destination.subtitle.map { TextViewLayout(.initialize(string: $0, color: theme.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 1) }
        self.icon = destination.icon.precomposed()
        super.init(initialSize, stableId: stableId, viewType: .singleItem, action: action)
    }

    override var height: CGFloat {
        let textHeight = titleLayout.layoutSize.height + (subtitleLayout.map { textSpacing + $0.layoutSize.height } ?? 0)
        return max(50, textHeight + 12)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        let result = super.makeSize(width, oldWidth: oldWidth)
        let textWidth = max(0, blockWidth - textInset - viewType.innerInset.right)
        titleLayout.measure(width: textWidth)
        subtitleLayout?.measure(width: textWidth)
        return result
    }

    override var accessibilityLabel: String? {
        return titleLayout.attributedString.string
    }

    override var accessibilityValue: String? {
        return subtitleLayout?.attributedString.string
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }

    override func accessibilityPerformPress() -> Bool {
        action()
        return true
    }

    override func viewClass() -> AnyClass {
        return GiftTransferDestinationRowView.self
    }
}

private final class GiftTransferDestinationRowView: GeneralContainableRowView {
    private let iconView = ImageView()
    private let titleView = TextView()
    private let subtitleView = TextView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        iconView.isEventLess = true
        iconView.isAccessibilityDecorative = true
        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        subtitleView.userInteractionEnabled = false
        subtitleView.isSelectable = false
        addSubview(iconView)
        addSubview(titleView)
        addSubview(subtitleView)
        containerView.setStateChangeHandler { [weak self] in
            self?.updateColors()
        }
        containerView.set(handler: { [weak self] _ in
            (self?.item as? GiftTransferDestinationRowItem)?.action()
        }, for: .Click)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return containerView.controlState == .Highlight ? theme.colors.grayHighlight : theme.colors.background
    }

    override func updateColors() {
        super.updateColors()
        titleView.backgroundColor = backdorColor
        subtitleView.backgroundColor = backdorColor
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? GiftTransferDestinationRowItem else {
            return
        }
        iconView.image = item.icon
        iconView.setFrameSize(item.iconSize)
        titleView.update(item.titleLayout)
        subtitleView.update(item.subtitleLayout)
        subtitleView.isHidden = item.subtitleLayout == nil
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? GiftTransferDestinationRowItem else {
            return
        }
        let textHeight = titleView.frame.height + (item.subtitleLayout != nil ? item.textSpacing + subtitleView.frame.height : 0)
        let textY = floorToScreenPixels(backingScaleFactor, (containerView.frame.height - textHeight) / 2)
        titleView.setFrameOrigin(NSMakePoint(item.textInset, textY))
        subtitleView.setFrameOrigin(NSMakePoint(item.textInset, titleView.frame.maxY + item.textSpacing))
        iconView.centerY(x: item.iconInset)
    }
}

private final class Arguments {
    let context: any AccountContextProtocol
    let blockchain: BlockchainRow?
    let searchInteractions: SearchInteractions
    let openBlockchain: () -> Void
    let select: (EnginePeer) -> Void

    init(context: any AccountContextProtocol, blockchain: BlockchainRow?, searchInteractions: SearchInteractions, openBlockchain: @escaping () -> Void, select: @escaping (EnginePeer) -> Void) {
        self.context = context
        self.blockchain = blockchain
        self.searchInteractions = searchInteractions
        self.openBlockchain = openBlockchain
        self.select = select
    }
}

private struct State: Equatable {
    var isLoaded: Bool = false
    var birthdays: [EnginePeer] = []
    var frequent: [EnginePeer] = []
    var contacts: [EnginePeer] = []
    var presences: [PeerId: EnginePeer.Presence] = [:]
    var query: String = ""
    var searchResults: [EnginePeer] = []
    var isSearching: Bool = false
}

private struct PeerRow: Equatable {
    let peer: EnginePeer
    let status: String?
    let statusColor: NSColor
    let viewType: GeneralViewType
}

private func giftTransferCanReceive(_ peer: EnginePeer, accountPeerId: PeerId) -> Bool {
    guard peer.id != accountPeerId, !peer.isDeleted else {
        return false
    }
    switch peer {
    case let .user(user):
        return user.botInfo == nil
    case let .channel(channel):
        if case .broadcast = channel.info {
            return true
        }
        return false
    default:
        return false
    }
}

private func giftTransferUnlockDays(_ canExportDate: Int32) -> Int32? {
    let currentTime = Int32(CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970)
    guard currentTime <= canExportDate else {
        return nil
    }
    return Int32(ceil(Float(canExportDate - currentTime) / 86400.0))
}

private func giftTransferSortedContacts(_ peers: [EnginePeer]) -> [EnginePeer] {
    return peers.sorted { lhs, rhs in
        return lhs._asPeer().displayTitle.localizedStandardCompare(rhs._asPeer().displayTitle) == .orderedAscending
    }
}

private func giftTransferContactSections(_ contacts: [EnginePeer]) -> [(letter: String, peers: [EnginePeer])] {
    var letters: [String] = []
    var byLetter: [String: [EnginePeer]] = [:]
    var other: [EnginePeer] = []
    for peer in contacts {
        if let first = peer._asPeer().displayTitle.first, first.isLetter {
            let letter = String(first).uppercased()
            if byLetter[letter] == nil {
                letters.append(letter)
            }
            byLetter[letter, default: []].append(peer)
        } else {
            other.append(peer)
        }
    }
    var sections = letters.map { (letter: $0, peers: byLetter[$0] ?? []) }
    if !other.isEmpty {
        sections.append((letter: "#", peers: other))
    }
    return sections
}

private func peerStatus(_ peer: EnginePeer, presence: EnginePeer.Presence?, context: any AccountContextProtocol) -> (text: String?, color: NSColor) {
    if case .user = peer, let presence {
        let (text, _, color) = userPresenceText(presence._asPresence(), timeDifference: context.timeDifference, relativeTo: Int32(Date().timeIntervalSince1970))
        return (text, color)
    }
    if let username = peer.addressName, !username.isEmpty {
        return ("@\(username)", theme.colors.grayText)
    }
    return (nil, theme.colors.grayText)
}

private let _id_search = InputDataIdentifier("_id_search")
private let _id_blockchain = InputDataIdentifier("_id_blockchain")
private let _id_empty = InputDataIdentifier("_id_empty")

private func appendPeers(_ peers: [EnginePeer], block: String, sectionId: Int32, index: inout Int32, state: State, arguments: Arguments, entries: inout [InputDataEntry]) {
    for (i, peer) in peers.enumerated() {
        let status = peerStatus(peer, presence: state.presences[peer.id], context: arguments.context)
        let row = PeerRow(peer: peer, status: status.text, statusColor: status.color, viewType: bestGeneralViewType(peers, for: i))
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: InputDataIdentifier("_id_\(block)_\(peer.id.toInt64())"), equatable: .init(row), comparable: nil, item: { initialSize, stableId in
            return ShortPeerRowItem(initialSize, peer: row.peer._asPeer(), account: arguments.context.account, context: arguments.context, stableId: stableId, height: 44, photoSize: NSMakeSize(30, 30), statusStyle: ControlStyle(font: .normal(.text), foregroundColor: row.statusColor, highlightColor: .white), status: row.status, inset: NSEdgeInsets(left: 20, right: 20), viewType: row.viewType, action: {
                arguments.select(row.peer)
            })
        }))
        index += 1
    }
}

private func appendHeader(_ text: String, sectionId: Int32, index: inout Int32, entries: inout [InputDataEntry]) {
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(text), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []

    entries.append(.sectionId(0, type: .customModern(10)))
    entries.append(.custom(sectionId: 0, index: 0, value: .none, identifier: _id_search, equatable: nil, comparable: nil, item: { initialSize, stableId in
        return SearchRowItem(initialSize, stableId: stableId, searchInteractions: arguments.searchInteractions, viewType: .singleItem)
    }))

    if !state.query.isEmpty {
        var index: Int32 = 3000
        if !state.searchResults.isEmpty {
            entries.append(.sectionId(40, type: .customModern(12)))
            appendPeers(state.searchResults, block: "search", sectionId: 40, index: &index, state: state, arguments: arguments, entries: &entries)
        } else if !state.isSearching {
            entries.append(.sectionId(40, type: .customModern(12)))
            entries.append(.custom(sectionId: 40, index: index, value: .none, identifier: _id_empty, equatable: .init(state.query), comparable: nil, item: { initialSize, stableId in
                return SearchEmptyRowItem(initialSize, stableId: stableId, viewType: .singleItem)
            }))
        }
        entries.append(.sectionId(1000, type: .customModern(20)))
        return entries
    }

    if let blockchain = arguments.blockchain {
        entries.append(.sectionId(10, type: .customModern(12)))
        entries.append(.custom(sectionId: 10, index: 10, value: .none, identifier: _id_blockchain, equatable: .init(blockchain), comparable: nil, item: { initialSize, stableId in
            return GiftTransferDestinationRowItem(initialSize, stableId: stableId, destination: blockchain, action: arguments.openBlockchain)
        }))
    }

    if !state.birthdays.isEmpty {
        var index: Int32 = 1000
        entries.append(.sectionId(20, type: .customModern(12)))
        appendHeader(strings().birthdaySeparatorToday, sectionId: 20, index: &index, entries: &entries)
        appendPeers(state.birthdays, block: "birthday", sectionId: 20, index: &index, state: state, arguments: arguments, entries: &entries)
    }

    if !state.frequent.isEmpty {
        var index: Int32 = 2000
        entries.append(.sectionId(30, type: .customModern(12)))
        appendHeader(strings().giftTransferControllerFrequentContacts, sectionId: 30, index: &index, entries: &entries)
        appendPeers(state.frequent, block: "frequent", sectionId: 30, index: &index, state: state, arguments: arguments, entries: &entries)
    }

    let frequentIds = Set(state.frequent.map(\.id))
    var index: Int32 = 10000
    for (i, section) in giftTransferContactSections(state.contacts.filter { !frequentIds.contains($0.id) }).enumerated() {
        let sectionId = Int32(100 + i)
        entries.append(.sectionId(sectionId, type: .customModern(12)))
        appendHeader(section.letter, sectionId: sectionId, index: &index, entries: &entries)
        appendPeers(section.peers, block: "contact", sectionId: sectionId, index: &index, state: state, arguments: arguments, entries: &entries)
    }

    entries.append(.sectionId(1000, type: .customModern(20)))

    return entries
}

private func giftTransferConfirmController(context: any AccountContextProtocol, gift: StarGift.UniqueGift, peer: EnginePeer, transferStars: Int64?, transfer: @escaping () -> Void) -> InputDataController {
    let info: String
    let ok: String
    if let stars = transferStars, stars > 0 {
        info = strings().giftTransferConfirmationText("\(gift.title) #\(gift.number)", peer._asPeer().displayTitle, strings().starListItemCountOther(Int(stars)))
        ok = strings().giftTransferConfirmationTransfer + " " + strings().starListItemCountOther(Int(stars))
    } else {
        info = strings().giftTransferConfirmationTextFree("\(gift.title) #\(gift.number)", peer._asPeer().displayTitle)
        ok = strings().giftTransferConfirmationTransferFree
    }

    var entries: [InputDataEntry] = []
    entries.append(.sectionId(0, type: .customModern(10)))
    entries.append(.custom(sectionId: 0, index: 0, value: .none, identifier: InputDataIdentifier("_id_header"), equatable: nil, comparable: nil, item: { initialSize, stableId in
        return TransferUniqueGiftHeaderItem(initialSize, stableId: stableId, gift: gift, toPeer: peer, context: context)
    }))
    entries.append(.desc(sectionId: 0, index: 1, text: .markdown(info, linkHandler: { _ in }), data: .init(color: theme.colors.text, viewType: .singleItem, fontSize: 14, centerViewAlignment: true, alignment: .center)))
    entries.append(.sectionId(1, type: .customModern(16)))
    entries.append(.custom(sectionId: 1, index: 2, value: .none, identifier: InputDataIdentifier("_id_attributes"), equatable: nil, comparable: nil, item: { initialSize, stableId in
        return InputDataTableBasedItem(initialSize, stableId: stableId, viewType: .singleItem, rows: getTransferAttributesRows(gift: gift), context: context)
    }))
    entries.append(.sectionId(2, type: .customModern(20)))
    entries.append(.custom(sectionId: 2, index: 3, value: .none, identifier: InputDataIdentifier("_id_transfer"), equatable: nil, comparable: nil, item: { initialSize, stableId in
        return GeneralActionButtonRowItem(initialSize, stableId: stableId, text: ok, viewType: .legacy, action: transfer)
    }))
    entries.append(.sectionId(3, type: .customModern(20)))

    let controller = InputDataController(dataSignal: .single(InputDataSignalValue(entries: entries)), title: strings().giftTransferConfirmationTitle, hasDone: false)
    controller.centerModalHeader = ModalHeaderData(title: nil)
    controller.validateData = { _ in
        transfer()
        return .none
    }
    return controller
}

func showGiftTransfer(context: any AccountContextProtocol, window: Window, gift: StarGift.UniqueGift, reference: StarGiftReference, giftsContext: ProfileGiftsContext, canExportDate: Int32?, transferStars: Int64?, transfer: @escaping (EnginePeer, @escaping () -> Void) -> Void) {
    let actionsDisposable = DisposableSet()
    let searchDisposable = MetaDisposable()
    actionsDisposable.add(searchDisposable)

    let initialState = State()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    var getController: (() -> InputDataController?)? = nil
    var getModal: (() -> InputDataModalController?)? = nil
    var pinnedHeight: CGFloat? = nil

    let accountPeerId = context.peerId

    let blockchainOption = canExportDate != nil ? StarsHooks.shared.giftTransferBlockchainOptionObserved(context, window, gift, reference, giftsContext) : nil
    let blockchain = blockchainOption.map { option in
        return BlockchainRow(title: option.title, subtitle: canExportDate.flatMap(giftTransferUnlockDays).map { strings().giftTransferSendUnlocks(strings().timerDaysOther(Int($0))) }, icon: option.icon)
    }

    let updateSearch: (SearchState) -> Void = { searchState in
        let query = searchState.request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard stateValue.with({ $0.query }) != query else {
            return
        }
        updateState { current in
            var current = current
            current.query = query
            current.searchResults = []
            current.isSearching = !query.isEmpty
            return current
        }
        guard !query.isEmpty else {
            searchDisposable.set(nil)
            return
        }
        let local: Signal<[EnginePeer], NoError> = context.engine.contacts.searchLocalPeers(query: query.lowercased())
        |> map { peers in
            return peers.compactMap { $0.chatMainPeer }
        }
        let remote: Signal<([EnginePeer], Bool), NoError> = Signal<([EnginePeer], Bool), NoError>.single(([], false))
        |> then(Signal<Void, NoError>.single(Void())
            |> delay(0.4, queue: .mainQueue())
            |> mapToSignal { _ in
                return context.engine.contacts.searchRemotePeers(query: query)
            }
            |> map { localPeers, globalPeers -> ([EnginePeer], Bool) in
                return ((localPeers + globalPeers).map(\.peer), true)
            })
        searchDisposable.set((combineLatest(local, remote) |> deliverOnMainQueue).start(next: { localPeers, remoteResult in
            var seen = Set<PeerId>()
            let peers = (localPeers + remoteResult.0).filter { giftTransferCanReceive($0, accountPeerId: accountPeerId) && seen.insert($0.id).inserted }
            updateState { current in
                var current = current
                if current.query == query {
                    current.searchResults = peers
                    current.isSearching = !remoteResult.1
                }
                return current
            }
        }))
    }

    let openBlockchain: () -> Void = {
        guard let canExportDate, let blockchainOption else {
            return
        }
        if let days = giftTransferUnlockDays(canExportDate) {
            alert(for: window, header: strings().giftTransferUnlockPendingTitle, info: strings().giftTransferUnlockPendingText(strings().timerDaysOther(Int(days))))
        } else {
            blockchainOption.action()
        }
    }

    let select: (EnginePeer) -> Void = { peer in
        guard let modal = getModal?(), modal.current === getController?() else {
            return
        }
        let confirm = giftTransferConfirmController(context: context, gift: gift, peer: peer, transferStars: transferStars, transfer: {
            transfer(peer, {
                getModal?()?.close()
            })
        })
        confirm.onDeinit = { }
        confirm.leftModalHeader = ModalHeaderData(image: theme.icons.chatNavigationBack, handler: {
            getModal?()?.pop(animated: true)
        }, isCloseButton: false)
        confirm._frameRect = modal.frame.size.bounds
        modal.fixedHeight = nil
        modal.window?.makeFirstResponder(nil)
        modal.push(confirm, animated: true)
    }

    let searchInteractions = SearchInteractions({ state, _ in
        updateSearch(state)
    }, { state in
        updateSearch(state)
    })

    let arguments = Arguments(context: context, blockchain: blockchain, searchInteractions: searchInteractions, openBlockchain: openBlockchain, select: select)

    let frequent: Signal<([EnginePeer], [PeerId: EnginePeer.Presence]), NoError> = context.engine.peers.recentPeers()
    |> map { recent -> [EnginePeer] in
        switch recent {
        case let .peers(peers):
            let users = peers.map(EnginePeer.init).filter { peer in
                guard case .user = peer else {
                    return false
                }
                return giftTransferCanReceive(peer, accountPeerId: accountPeerId)
            }
            return Array(users.prefix(frequentContactsLimit))
        case .disabled:
            return []
        }
    }
    |> mapToSignal { peers in
        return context.engine.data.subscribe(EngineDataMap(peers.map { TelegramEngine.EngineData.Item.Peer.Presence(id: $0.id) }))
        |> map { presences in
            return (peers, presences.compactMapValues { $0 })
        }
    }

    let birthdays: Signal<Set<PeerId>, NoError> = context.account.stateManager.contactBirthdays
    |> map { birthdays in
        return Set(birthdays.filter { $0.value.isToday }.keys)
    }

    let contacts = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Contacts.List(includePresences: true))

    actionsDisposable.add(combineLatest(queue: .mainQueue(), contacts, birthdays, frequent).start(next: { contacts, birthdays, frequent in
        let sorted = giftTransferSortedContacts(contacts.peers.filter { giftTransferCanReceive($0, accountPeerId: accountPeerId) })
        updateState { current in
            var current = current
            current.contacts = sorted
            current.birthdays = sorted.filter { birthdays.contains($0.id) }
            current.frequent = frequent.0
            current.presences = contacts.presences.merging(frequent.1, uniquingKeysWith: { lhs, _ in lhs })
            current.isLoaded = true
            return current
        }
    }))

    let signal = statePromise.get()
    |> filter { $0.isLoaded }
    |> deliverOnPrepareQueue
    |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: strings().giftTransferControllerTitle, hasDone: false)

    getController = { [weak controller] in
        return controller
    }

    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    let modalController = InputDataModalController(controller, size: NSMakeSize(360, 0))

    getModal = { [weak modalController] in
        return modalController
    }

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: {
        getModal?()?.close()
    })

    controller.afterTransaction = { controller in
        guard pinnedHeight == nil, let modal = getModal?(), modal.current === controller else {
            return
        }
        pinnedHeight = controller.tableView.listHeight
        modal.fixedHeight = pinnedHeight
    }

    modalController.didPopController = { _ in
        getModal?()?.fixedHeight = pinnedHeight
    }

    showModal(with: modalController, for: window)
}
