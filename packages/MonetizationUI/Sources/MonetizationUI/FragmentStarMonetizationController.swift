import Foundation
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import CurrencyFormat
import InputView
import GraphCore
import Localization
import ColorPalette
import TelegramTheme
import TelegramIconsTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import AlertsUI
import LocalAnimations
import TelegramMedia
import InputTextView
import StatisticsUI
import StarsUI
import InlineStickerLayer


private func transactionSegments(_ list: [State.TransactionMode], transactionMode: State.TransactionMode) -> [ScrollableSegmentItem] {
    let theme = ScrollableSegmentTheme.standard(theme.colors)
    var items: [ScrollableSegmentItem] = []
    if list.contains(.all) {
        items.append(.init(title: strings().starListTransactionsAll, index: 0, uniqueId: 0, selected: transactionMode == .all, insets: NSEdgeInsets(left: 10, right: 10), icon: nil, theme: theme, equatable: UIEquatable(transactionMode)))
    }
    if list.contains(.incoming) {
        items.append(.init(title: strings().starListTransactionsIncoming, index: 1, uniqueId: 1, selected: transactionMode == .incoming, insets: NSEdgeInsets(left: 10, right: 10), icon: nil, theme: theme, equatable: UIEquatable(transactionMode)))
    }
    if list.contains(.outgoing) {
        items.append(.init(title: strings().starListTransactionsOutgoing, index: 2, uniqueId: 2, selected: transactionMode == .outgoing, insets: NSEdgeInsets(left: 10, right: 10), icon: nil, theme: theme, equatable: UIEquatable(transactionMode)))
    }
    return items
}

private final class Arguments {
    let context: any AccountContextProtocol
    let withdraw:()->Void
    let executeLink:(String)->Void
    let loadMore:()->Void
    let openTransaction:(Star_Transaction)->Void
    let loadDetailedGraph:(StatsGraph, Int64) -> Signal<StatsGraph?, NoError>
    let toggleFilterMode:(State.TransactionMode)->Void
    init(context: any AccountContextProtocol, withdraw:@escaping()->Void, executeLink:@escaping(String)->Void, loadMore:@escaping()->Void, openTransaction:@escaping(Star_Transaction)->Void, loadDetailedGraph:@escaping(StatsGraph, Int64) -> Signal<StatsGraph?, NoError>, toggleFilterMode:@escaping(State.TransactionMode)->Void) {
        self.context = context
        self.withdraw = withdraw
        self.executeLink = executeLink
        self.loadMore = loadMore
        self.openTransaction = openTransaction
        self.loadDetailedGraph = loadDetailedGraph
        self.toggleFilterMode = toggleFilterMode
    }
}



private struct State : Equatable {
    
    enum TransactionMode : Equatable {
        case all
        case incoming
        case outgoing
    }

    struct Balance : Equatable {
        var stars: StarsAmount
        var usdRate: Double
        
        var fractional: Double {
            return currencyToFractionalAmount(value: stars.totalValue, currency: XTR) ?? 0
        }
        
        var usd: String {
            return "$" + "\(self.fractional * self.usdRate)".prettyCurrencyNumberUsd
        }
    }
    struct Overview : Equatable {
        var balance: Balance
        var current: Balance
        var all: Balance
    }
    
    var ton: Bool = false
    
    var config_withdraw: Bool
        
    var nextWithdrawalTimestamp: Int32? = nil

    var overview: Overview = .init(balance: .init(stars: .init(value: 0, nanos: 0), usdRate: 0), current: .init(stars: .init(value: 0, nanos: 0), usdRate: 0), all: .init(stars: .init(value: 0, nanos: 0), usdRate: 0))
    var balance: Balance = .init(stars: .init(value: 0, nanos: 0), usdRate: 0)
    var allTransactions: [Star_Transaction] = []
    var incomingTransactions: [Star_Transaction] = []
    var outgoingTransactions: [Star_Transaction] = []

    var allTransactionsState: StarsTransactionsContext.State?
    var incomingTransactionsState: StarsTransactionsContext.State?
    var outgoingTransactionsState: StarsTransactionsContext.State?

    var adsUrl: String?
    var inputState: Updated_ChatTextInputState = .init()
    
    
    var withdrawError: RequestStarsRevenueWithdrawalError? = nil
    
    var peer: EnginePeer? = nil
    
    var canWithdraw: Bool {
        if let nextWithdrawalTimestamp {
            if nextWithdrawalTimestamp < Int32(Date().timeIntervalSince1970) {
                return config_withdraw
            }
        }
        return config_withdraw
    }
    
    var balanceAmount: CurrencyAmount {
        return .init(amount: balance.stars, currency: ton ? .ton : .stars)
    }
    
    var revenueGraph: StatsGraph?
    var loaded: Bool = false
    
    var transactionMode: TransactionMode = .all
    
}


private func _id_overview(_ index: Int) -> InputDataIdentifier {
    return InputDataIdentifier("_id_overview_\(index)")
}
private func _id_transaction(_ id: String, type: Star_TransactionType) -> InputDataIdentifier {
    return InputDataIdentifier("_id_transaction\(id)_\(type)")
}

private let _id_balance = InputDataIdentifier("_id_balance")

private let _id_revenue_graph = InputDataIdentifier("_id_revenue_graph")

private let _id_loading = InputDataIdentifier("_id_loading")
private let _id_load_more = InputDataIdentifier("_id_load_more")
private let _id_transaction_mode = InputDataIdentifier("_id_transaction_mode")

private func entries(_ state: State, arguments: Arguments, detailedDisposable: DisposableDict<InputDataIdentifier>) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    if !state.loaded && statisticsChartStyle.usesGlass {
        entries.append(contentsOf: statisticsGraphSkeletonEntries([
            (_id_revenue_graph, strings().fragmentStarsRevenueTitle, 1)
        ], sectionId: &sectionId, index: &index))
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().fragmentStarsOvervew), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1
        for i in 0 ..< 2 {
            let viewType: GeneralViewType = i == 0 ? .firstItem : .lastItem
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_overview(i), equatable: InputDataEquatable("skeleton"), comparable: nil, item: { initialSize, stableId in
                return StatisticSkeletonListRowItem(initialSize, stableId: stableId, style: .amount, viewType: viewType)
            }))
            index += 1
        }
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().fragmentStarsBalanceTitle), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_balance, equatable: InputDataEquatable("skeleton"), comparable: nil, item: { initialSize, stableId in
            return StatisticSkeletonListRowItem(initialSize, stableId: stableId, style: .balance, viewType: .singleItem)
        }))
        index += 1
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().monetizationTransactionsTitle), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1
        entries.append(contentsOf: statisticsListSkeletonEntries(prefix: "transaction", count: 3, sectionId: sectionId, index: &index))
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        return entries
    }
    
    do {
        
        struct Graph {
            let graph: StatsGraph
            let title: String
            let identifier: InputDataIdentifier
            let type: ChartItemType
            let rate: Double
            let load:(InputDataIdentifier)->Void
        }
        
        var graphs: [Graph] = []
        if let graph = state.revenueGraph, !graph.isEmpty {
            graphs.append(Graph(graph: graph, title: strings().fragmentStarsRevenueTitle, identifier: _id_revenue_graph, type: .currency(XTR), rate: state.balance.usdRate, load: { identifier in
                
            }))
        }
        
        
        for graph in graphs {
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(graph.title), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
            index += 1
            
            switch graph.graph {
            case let .Loaded(_, string):
                ChartsDataManager.readChart(data: string.data(using: .utf8)!, sync: true, success: { collection in
                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: graph.identifier, equatable: InputDataEquatable(graph.graph), comparable: nil, item: { initialSize, stableId in
                        return StatisticRowItem(initialSize, stableId: stableId, context: arguments.context, collection: collection, viewType: .singleItem, type: graph.type, rate: graph.rate, title: graph.title, getDetailsData: { date, completion in
                            detailedDisposable.set(arguments.loadDetailedGraph(graph.graph, Int64(date.timeIntervalSince1970) * 1000).start(next: { graph in
                                if let graph = graph, case let .Loaded(_, data) = graph {
                                    completion(data)
                                }
                            }), forKey: graph.identifier)
                        })
                    }))
                }, failure: { error in
                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: graph.identifier, equatable: InputDataEquatable(graph.graph), comparable: nil, item: { initialSize, stableId in
                        return StatisticLoadingRowItem(initialSize, stableId: stableId, error: error.localizedDescription)
                    }))
                })
                                
                index += 1
            case .OnDemand:
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: graph.identifier, equatable: InputDataEquatable(graph.graph), comparable: nil, item: { initialSize, stableId in
                    return statisticsGraphPlaceholderItem(initialSize, stableId: stableId, seriesCount: 1)
                }))
                index += 1
            case let .Failed(error):
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: graph.identifier, equatable: InputDataEquatable(graph.graph), comparable: nil, item: { initialSize, stableId in
                    return StatisticLoadingRowItem(initialSize, stableId: stableId, error: error)
                }))
                index += 1
            case .Empty:
                break
            }
        }
        
    }
  
    do {
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        
        struct Tuple : Equatable {
            let overview: Fragment_OverviewRowItem.Overview
            let viewType: GeneralViewType
        }
        
        var tuples: [Tuple] = []
        
        tuples.append(.init(overview: .init(amount: state.overview.balance.stars.value, usdAmount: state.overview.balance.usd, info: strings().fragmentStarsAvailableBalance, stars: nil), viewType: .firstItem))
        
        tuples.append(.init(overview: .init(amount: state.overview.current.stars.value, usdAmount: state.overview.current.usd, info: strings().fragmentStarsTotalCurrent, stars: nil), viewType: .lastItem))

        
        //tuples.append(.init(overview: .init(amount: state.overview.all.stars, usdAmount: state.overview.all.usd, info: strings().fragmentStarsTotalLifetime, stars: nil), viewType: .lastItem))
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().fragmentStarsOvervew), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1
        
        for (i, tuple) in tuples.enumerated() {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_overview(i), equatable: .init(tuple), comparable: nil, item: { initialSize, stableId in
                return Fragment_OverviewRowItem(initialSize, stableId: stableId, context: arguments.context, overview: tuple.overview, currency: .xtr, viewType: tuple.viewType)
            }))
        }
    }
    
    do {
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
      
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().fragmentStarsBalanceTitle), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1
        
        let buyAds:()->Void = {
            if let url = state.adsUrl {
                arguments.executeLink(url)
            }
        }
        
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_balance, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            return Fragment_BalanceRowItem(initialSize, stableId: stableId, context: arguments.context, balance: .init(amount: state.balance.stars.totalValue, usd: state.balance.usd, currency: .xtr), canWithdraw: state.canWithdraw, buyAds: state.peer?.id == arguments.context.peerId ? nil : buyAds, nextWithdrawalTimestamp: state.nextWithdrawalTimestamp, viewType: .singleItem, transfer: arguments.withdraw)
        }))
        
        let text: String
        text = strings().fragmentStarsWithdrawInfo
        entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(text, linkHandler: { link in
            arguments.executeLink(link)
        }), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
        
    }
//
//
    
    
    if !state.allTransactions.isEmpty {
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
      
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().monetizationTransactionsTitle), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1
        
        var list: [State.TransactionMode] = [.all]
        if !state.incomingTransactions.isEmpty {
            list.append(.incoming)
        }
        if !state.outgoingTransactions.isEmpty {
            list.append(.outgoing)
        }
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_transaction_mode, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            return SegmentTypesRowItem(initialSize, stableId: stableId, items: transactionSegments(list, transactionMode: state.transactionMode), viewType: .firstItem, callback: { uniqueId in
                switch uniqueId {
                case 0:
                    arguments.toggleFilterMode(.all)
                case 1:
                    arguments.toggleFilterMode(.incoming)
                case 2:
                    arguments.toggleFilterMode(.outgoing)
                default:
                    break
                }
            })
        }))
        
        struct Tuple : Equatable {
            let transaction: Star_Transaction
            let viewType: GeneralViewType
        }
        
        let transactions: [Star_Transaction]
        var transactionState: StarsTransactionsContext.State?
        switch state.transactionMode {
        case .all:
            transactions = state.allTransactions
            transactionState = state.allTransactionsState
        case .incoming:
            transactions = state.incomingTransactions
            transactionState = state.incomingTransactionsState
        case .outgoing:
            transactions = state.outgoingTransactions
            transactionState = state.outgoingTransactionsState
        }
        
        if let transactionState {
            var tuples: [Tuple] = []
            for (i, transaction) in transactions.enumerated() {
                var viewType = bestGeneralViewTypeAfterFirst(transactions, for: i)
                if i == transactions.count - 1, transactionState.canLoadMore || transactionState.isLoading {
                    viewType = .innerItem
                }
                tuples.append(.init(transaction: transaction, viewType: viewType))
            }
            
            for tuple in tuples {
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_transaction(tuple.transaction.id, type: tuple.transaction.type), equatable: .init(tuple), comparable: nil, item: { initialSize, stableId in
                    return Star_TransactionItem(initialSize, stableId: stableId, context: arguments.context, viewType: tuple.viewType, transaction: tuple.transaction, callback: arguments.openTransaction)
                }))
            }
            
            if transactionState.isLoading {
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_loading, equatable: nil, comparable: nil, item: { initialSize, stableId in
                    return LoadingTableItem(initialSize, height: 40, stableId: stableId, viewType: .lastItem)
                }))
            } else if transactionState.canLoadMore {
                entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_load_more, data: .init(name: strings().fragmentStarsShowMore, color: theme.colors.accent, type: .none, viewType: .lastItem, action: arguments.loadMore)))
            }
        }
        
    }
    
    
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

public func FragmentStarMonetizationController(context: any AccountContextProtocol, peerId: PeerId, revenueContext: StarsRevenueStatsContext?) -> InputDataController {

    let actionsDisposable = DisposableSet()
    
    let detailedDisposable: DisposableDict<InputDataIdentifier> = DisposableDict()
    actionsDisposable.add(detailedDisposable)


    let initialState = State(config_withdraw: false)

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    
    let revenueContext = revenueContext ?? StarsRevenueStatsContext(account: context.account, peerId: peerId, ton: false)
    
    revenueContext.reload()
    
    class ContextObject {
        let revenue: StarsRevenueStatsContext
        let allTransactions: StarsTransactionsContext
        let incomingTransactions: StarsTransactionsContext
        let outgoingTransactions: StarsTransactionsContext
        init(revenue: StarsRevenueStatsContext, allTransactions: StarsTransactionsContext, incomingTransactions: StarsTransactionsContext, outgoingTransactions: StarsTransactionsContext) {
            self.revenue = revenue
            self.allTransactions = allTransactions
            self.incomingTransactions = incomingTransactions
            self.outgoingTransactions = outgoingTransactions
            
            allTransactions.loadMore()
            incomingTransactions.loadMore()
            outgoingTransactions.loadMore()
        }
    }
    
    
    let contextObject = ContextObject(revenue: revenueContext,
                                      allTransactions: context.engine.payments.peerStarsTransactionsContext(subject: .peer(peerId: peerId, ton: false), mode: .all),
                                      incomingTransactions: context.engine.payments.peerStarsTransactionsContext(subject: .peer(peerId: peerId, ton: false), mode: .incoming),
                                      outgoingTransactions: context.engine.payments.peerStarsTransactionsContext(subject: .peer(peerId: peerId, ton: false), mode: .outgoing))
    
    
    let adsUrl: Signal<String?, NoError> = .single(nil) |> then(context.engine.peers.requestStarsRevenueAdsAccountlUrl(peerId: peerId))
    
    actionsDisposable.add(combineLatest(contextObject.revenue.state, contextObject.allTransactions.state, contextObject.incomingTransactions.state, contextObject.outgoingTransactions.state, adsUrl, context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))).startStrict(next: { revenue, allTransactions, incomingTransactions, outgoingTransactions, adsUrl, peer in
        if let revenue = revenue.stats {
            updateState { current in
                var current = current
                current.peer = peer
                current.balance = .init(stars: revenue.balances.availableBalance.amount, usdRate: revenue.usdRate)
                current.overview.balance = .init(stars: revenue.balances.availableBalance.amount, usdRate: revenue.usdRate)
                current.overview.all = .init(stars: revenue.balances.overallRevenue.amount, usdRate: revenue.usdRate)
                current.overview.current = .init(stars: revenue.balances.currentBalance.amount, usdRate: revenue.usdRate)
                current.config_withdraw = revenue.balances.withdrawEnabled
                current.nextWithdrawalTimestamp = revenue.balances.nextWithdrawalTimestamp
                current.allTransactionsState = allTransactions
                current.incomingTransactionsState = incomingTransactions
                current.outgoingTransactionsState = outgoingTransactions

                current.adsUrl = adsUrl
                
                let map:(StarsContext.State.Transaction)->Star_Transaction = { value in
                    let type: Star_TransactionType
                    var botPeer: EnginePeer?
                    let incoming: Bool = value.count.amount.value > 0
                    let source: Star_TransactionType.Source
                    switch value.peer {
                    case let .peer(peer):
                        source = .peer
                        botPeer = peer
                    case .appStore:
                        source = .appstore
                    case .fragment:
                        source = .fragment
                    case .playMarket:
                        source = .playmarket
                    case .premiumBot:
                        source = .premiumbot
                    case .unsupported:
                        source = .unknown
                    case .ads:
                        source = .ads
                    case .apiLimitExtension:
                        source = .apiLimitExtension
                    }
                    if incoming {
                        type = .incoming(source)
                    } else {
                        type = .outgoing(source)
                    }
                    
                    return Star_Transaction(id: value.id, currency: value.count.currency, amount: value.count.amount, date: value.date, name: "", peer: botPeer, type: type, native: value)
                }
                
                current.revenueGraph = revenue.revenueGraph
                current.loaded = true
                current.allTransactions = allTransactions.transactions.map(map)
                current.incomingTransactions = incomingTransactions.transactions.map(map)
                current.outgoingTransactions = outgoingTransactions.transactions.map(map)

                return current
            }
        }
    }))

    let processWithdraw:(Int64)->Void = { amount in
        
        _ = showModalProgress(signal: context.engine.peers.checkStarsRevenueWithdrawalAvailability(), for: context.window).startStandalone(error: { error in
            switch error {
            case .authSessionTooFresh, .twoStepAuthTooFresh, .twoStepAuthMissing:
                alert(for: context.window, info: strings().monetizationWithdrawErrorText)
            case .requestPassword:
                showModal(with: InputPasswordController(context: context, title: strings().monetizationWithdrawEnterPasswordTitle, desc: strings().monetizationWithdrawEnterPasswordText, checker: { value in
                    return context.engine.peers.requestStarsRevenueWithdrawalUrl(peerId: peerId, ton: false, amount: amount, password: value)
                    |> deliverOnMainQueue
                    |> afterNext { url in
                        LinkHooks.shared.openExternalLink(url, false)
                    }
                    |> ignoreValues
                    |> mapError { error in
                        switch error {
                        case .invalidPassword:
                            return .wrong
                        case .limitExceeded:
                            return .custom(strings().loginFloodWait)
                        case .generic:
                            return .generic
                        default:
                            return .custom(strings().monetizationWithdrawErrorText)
                        }
                    }
                }), for: context.window)
            default:
                break
            }
        })
    }
    
    var getController: (()->InputDataController?)? = nil
    let arguments = Arguments(context: context, withdraw: {
        showModal(with: withdraw(context: context, state: stateValue.with { $0 }, stateValue: statePromise.get(), updateState: updateState, callback: processWithdraw), for: context.window)
    }, executeLink: { link in
        LinkHooks.shared.openExternalLink(link, false)
    }, loadMore: { [weak contextObject] in
        let current = stateValue.with { $0.transactionMode }
        switch current {
        case .all:
            contextObject?.allTransactions.loadMore()
        case .incoming:
            contextObject?.incomingTransactions.loadMore()
        case .outgoing:
            contextObject?.outgoingTransactions.loadMore()
        }
    }, openTransaction: { transaction in
        showModal(with: Star_TransactionScreen(context: context, fromPeerId: peerId, peer: transaction.peer, transaction: transaction.native), for: context.window, morphSource: {
            (getController?()?.tableView.item(stableId: InputDataEntryId.custom(_id_transaction(transaction.id, type: transaction.type)))?.view as? GeneralContainableRowView)?.containerView
        })
    }, loadDetailedGraph: { [weak contextObject] graph, x in
        return contextObject?.revenue.loadDetailedGraph(graph, x: x) ?? .complete()
    }, toggleFilterMode: { filter in
        updateState { current in
            var current = current
            current.transactionMode = filter
            return current
        }
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments, detailedDisposable: detailedDisposable))
    }
    
    let controller = InputDataController(dataSignal: signal, title: strings().fragmentStarsTitle, hasDone: false)
    getController = { [weak controller] in controller }
    
    controller.contextObject = contextObject
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    return controller
    
}


private final class WithdrawInputItem : GeneralRowItem {
    let inputState: Updated_ChatTextInputState
    let arguments: WithdrawArguments
    let interactions: TextView_Interactions
    let balance: CurrencyAmount
    init(_ initialSize: NSSize, stableId: AnyHashable, balance: CurrencyAmount, inputState: Updated_ChatTextInputState, arguments: WithdrawArguments) {
        self.inputState = inputState
        self.arguments = arguments
        self.balance = balance
        self.interactions = arguments.interactions
        super.init(initialSize, stableId: stableId)
    }
    
    override var height: CGFloat {
        return 40 + 20 + 40
    }
    
    override func viewClass() -> AnyClass {
        return WithdrawInputView.self
    }

    override var accessibilityLabel: String? {
        return strings().fragmentStarAmountPlaceholder
    }

    override var accessibilityValue: String? {
        return inputState.inputText.string
    }
}


private final class WithdrawInputView : GeneralRowView {
    
    
    private final class AcceptView : Control {
        private let textView = InteractiveTextView()
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(textView)
            layer?.cornerRadius = 20
            scaleOnClick = true
            self.set(background: theme.colors.accent, for: .Normal)
            
            textView.userInteractionEnabled = false
        }
        
        func update(_ item: WithdrawInputItem, animated: Bool) {
            let attr = NSMutableAttributedString()
            
            attr.append(string: strings().fragmentStarWithdrawInput("\(clown + TINY_SPACE)\(item.inputState.inputText.string)") , color: theme.colors.underSelectedColor, font: .medium(.text))
            
            switch item.balance.currency {
            case .stars:
                attr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.star_currency_new.file), for: clown)
            case .ton:
                attr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.ton_logo.file, color: theme.colors.underSelectedColor), for: clown)
            }
            
            let layout = TextViewLayout(attr)
            layout.measure(width: item.width - 60)
            
            textView.set(text: layout, context: item.arguments.context)
            
            needsLayout = true
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func layout() {
            super.layout()
            textView.center()
        }
    }
    
    private final class LimitView : Control {
        private let iconView = InteractiveTextView()
        private let textView = InteractiveTextView()
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(iconView)
            addSubview(textView)
            layer?.cornerRadius = 10
            scaleOnClick = true
            self.set(background: theme.colors.background, for: .Normal)
            
            textView.userInteractionEnabled = false
            iconView.userInteractionEnabled = false

        }
        
        func update(_ item: WithdrawInputItem, value: CurrencyAmount, animated: Bool) {
            let attr = NSMutableAttributedString()
                        
            let min_withdraw: Int64
            let max_withdraw: Int64
            
            switch value.currency {
            case .stars:
                min_withdraw = item.arguments.context.appConfiguration.getGeneralValue64("stars_revenue_withdrawal_min", orElse: 1000)
                max_withdraw = item.arguments.context.appConfiguration.getGeneralValue64("stars_revenue_withdrawal_max", orElse: 10_000_000)
            case .ton:
                min_withdraw = item.arguments.context.appConfiguration.getGeneralValue64("ton_revenue_withdrawal_min", orElse: 1 * 1_000_000_000)
                max_withdraw = item.arguments.context.appConfiguration.getGeneralValue64("ton_revenue_withdrawal_max", orElse: 100000 * 1_000_000_000)
            }
            
            

            switch value.currency {
            case .stars:
                if value.amount.value < min_withdraw {
                    attr.append(string: strings().fragmentStarsMinWithdraw(Int(min_withdraw)), color: theme.colors.text, font: .medium(.text))
                } else {
                    attr.append(string: strings().fragmentStarsMaxWithdraw(Int(max_withdraw)), color: theme.colors.text, font: .medium(.text))
                }
            case .ton:
                if value.amount.value < min_withdraw {
                    attr.append(string: strings().fragmentTonMinWithdraw(Int(Double(min_withdraw) / 1_000_000_000)), color: theme.colors.text, font: .medium(.text))
                } else {
                    attr.append(string: strings().fragmentTonMaxWithdraw(Int(Double(max_withdraw) / 1_000_000_000)), color: theme.colors.text, font: .medium(.text))
                }
            }
            
            let layout = TextViewLayout(attr)
            layout.measure(width: frame.width - 70)
            
            textView.set(text: layout, context: item.arguments.context)

            
            let iconAttr = NSMutableAttributedString()
            iconAttr.append(string: clown, color: theme.colors.text, font: .medium(.text))
            switch value.currency {
            case .stars:
                iconAttr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.star_currency_new.file), for: clown)
            case .ton:
                iconAttr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.ton_logo.file, color: theme.colors.accent), for: clown)
            }
            
            let iconLayout = TextViewLayout(iconAttr)
            iconLayout.measure(width: frame.width - 70)

            iconView.set(text: iconLayout, context: item.arguments.context)

            
            needsLayout = true
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func layout() {
            super.layout()
            iconView.centerY(x: 10)
            textView.centerY(x: iconView.frame.maxX + 10)
        }
    }
    
    private final class WithdrawInput : View {
        
        private weak var item: WithdrawInputItem?
        let inputView: UITextView = UITextView(frame: NSMakeRect(0, 0, 100, 40))
        private let starView = InteractiveTextView()
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(starView)
            addSubview(inputView)
                        

            layer?.cornerRadius = 10
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func update(item: WithdrawInputItem, animated: Bool) {
            self.item = item
            self.backgroundColor = theme.colors.background
            
            let attr = NSMutableAttributedString()
            attr.append(string: clown)
            switch item.balance.currency {
            case .stars:
                attr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.star_currency_new.file), for: clown)
            case .ton:
                attr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.ton_logo.file, color: theme.colors.accent), for: clown)
            }
            
            let layout = TextViewLayout(attr)
            layout.measure(width: .greatestFiniteMagnitude)
            
            self.starView.set(text: layout, context: item.arguments.context)

            
            inputView.placeholder = strings().fragmentStarAmountPlaceholder
            
            inputView.context = item.arguments.context
            inputView.interactions.max_height = 500
            inputView.interactions.min_height = 13
            inputView.interactions.emojiPlayPolicy = .onceEnd
            inputView.interactions.canTransform = false
            
            item.interactions.min_height = 13
            item.interactions.max_height = 500
            item.interactions.emojiPlayPolicy = .onceEnd
            item.interactions.canTransform = false
            
            let value: Int64
            switch item.balance.currency {
            case .stars:
                value = Int64(item.inputState.string) ?? 0
            case .ton:
                value = (Int64(item.inputState.string) ?? 0) * 1_000_000_000
            }
            
            let min_withdraw: Int64
            let max_withdraw: Int64
            
            switch item.balance.currency {
            case .stars:
                min_withdraw = item.arguments.context.appConfiguration.getGeneralValue64("stars_revenue_withdrawal_min", orElse: 1000)
                max_withdraw = item.arguments.context.appConfiguration.getGeneralValue64("stars_revenue_withdrawal_max", orElse: 10_000_000)
            case .ton:
                min_withdraw = item.arguments.context.appConfiguration.getGeneralValue64("ton_revenue_withdrawal_min", orElse: 1 * 1_000_000_000)
                max_withdraw = item.arguments.context.appConfiguration.getGeneralValue64("ton_revenue_withdrawal_max", orElse: 100000 * 1_000_000_000)
            }
            
            inputView.inputTheme = inputView.inputTheme.withUpdatedTextColor(value < min_withdraw || value > max_withdraw || value > item.balance.amount.value ? theme.colors.redUI : theme.colors.text)
            
            
            item.interactions.filterEvent = digitsOnlyFilterEvent

            self.inputView.set(item.interactions.presentation.textInputState())

            self.inputView.interactions = item.interactions
            
            item.interactions.inputDidUpdate = { [weak self] state in
                guard let `self` = self else {
                    return
                }
                self.set(state)
                self.inputDidUpdateLayout(animated: true)
            }
            
        }
        
        
        var textWidth: CGFloat {
            return frame.width - 20
        }
        
        func textViewSize() -> (NSSize, CGFloat) {
            return inputTextViewSize(inputView, width: textWidth)
        }
        
        private func inputDidUpdateLayout(animated: Bool) {
            self.updateLayout(size: frame.size, transition: animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate)
        }
        
        func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
            let (textSize, textHeight) = textViewSize()
            
            transition.updateFrame(view: starView, frame: starView.centerFrameY(x: 10))
            
            transition.updateFrame(view: inputView, frame: CGRect(origin: CGPoint(x: starView.frame.maxX + 10, y: 7), size: textSize))
            inputView.updateLayout(size: textSize, textHeight: textHeight, transition: transition)
        }
        
        private func set(_ state: Updated_ChatTextInputState) {
            guard let item else {
                return
            }
            item.arguments.updateState(state)
            
            item.redraw(animated: true)
        }
    }
    
    private let inputView = WithdrawInput(frame: NSMakeRect(0, 0, 40, 40))
    private var acceptView: AcceptView?
    private var limitView : LimitView?
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(inputView)
    }
    override var backdorColor: NSColor {
        return theme.colors.listBackground
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? WithdrawInputItem else {
            return
        }
        
        self.inputView.update(item: item, animated: animated)
        
        let min_withdraw: Int64
        let max_withdraw: Int64
        
        switch item.balance.currency {
        case .stars:
            min_withdraw = item.arguments.context.appConfiguration.getGeneralValue64("stars_revenue_withdrawal_min", orElse: 1000)
            max_withdraw = item.arguments.context.appConfiguration.getGeneralValue64("stars_revenue_withdrawal_max", orElse: 10_000_000)
        case .ton:
            min_withdraw = item.arguments.context.appConfiguration.getGeneralValue64("ton_revenue_withdrawal_min", orElse: 1 * 1_000_000_000)
            max_withdraw = item.arguments.context.appConfiguration.getGeneralValue64("ton_revenue_withdrawal_max", orElse: 100000 * 1_000_000_000)
        }
        
        let value: Int64
        switch item.balance.currency {
        case .stars:
            value = Int64(item.inputState.string) ?? 0
        case .ton:
            value = (Int64(item.inputState.string) ?? 0) * 1_000_000_000
        }
                
        if value < min_withdraw || value > max_withdraw {
            if let acceptView {
                performSubviewRemoval(acceptView, animated: animated)
                self.acceptView = nil
            }
            
            let current: LimitView
            if let view = self.limitView {
                current = view
            } else {
                current = LimitView(frame: NSMakeRect(20, inputView.frame.maxY + 20, frame.width - 40, 40))
                self.limitView = current
                addSubview(current)
                
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
            current.update(item, value: .init(amount: .init(value: value, nanos: 0), currency: item.balance.currency), animated: animated)
        } else {
            if let limitView {
                performSubviewRemoval(limitView, animated: animated)
                self.limitView = nil
            }
            let current: AcceptView
            if let view = self.acceptView {
                current = view
            } else {
                current = AcceptView(frame: NSMakeRect(20, inputView.frame.maxY + 20, frame.width - 40, 40))
                self.acceptView = current
                addSubview(current)
                
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
                
                current.set(handler: { [weak self] _ in
                    if let item = self?.item as? WithdrawInputItem {
                        item.arguments.withdraw()
                    }
                }, for: .Click)
            }
            current.update(item, animated: animated)
        }
        
        
        self.inputView.updateLayout(size: self.frame.size, transition: animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate)
    }
    
    override func shakeView() {
        inputView.shake(beep: true)
    }
    
    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        
        transition.updateFrame(view: inputView, frame: NSMakeRect(20, 0, size.width - 40,40))
        inputView.updateLayout(size: inputView.frame.size, transition: transition)
        
        if let acceptView {
            transition.updateFrame(view: acceptView, frame: NSMakeRect(20, inputView.frame.maxY + 20, frame.width - 40, 40))
        }
        if let limitView {
            transition.updateFrame(view: limitView, frame: NSMakeRect(20, inputView.frame.maxY + 20, frame.width - 40, 40))
        }
    }
    override var firstResponder: NSResponder? {
        return inputView.inputView.inputView
    }
}


private let _id_input = InputDataIdentifier("_id_input")

private func withdrawBalanceText(_ balance: CurrencyAmount) -> NSAttributedString {
    let attr = NSMutableAttributedString()
    attr.append(string: strings().starPurchaseBalance("\(clown + TINY_SPACE)\(balance.formatted)"), color: theme.colors.text, font: .normal(.text))
    if balance.currency == .ton {
        attr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.ton_logo.file, color: theme.colors.accent), for: clown)
    } else {
        attr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.star_currency_new.file), for: clown)
    }
    return attr
}

private func withdrawEntries(_ state: State, arguments: WithdrawArguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("header"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return WithdrawHeaderItem(initialSize, stableId: stableId, balance: withdrawBalanceText(state.balanceAmount), arguments: arguments)
    }))
    
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().fragmentStarWithdrawPlaceholder), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_input, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return WithdrawInputItem(initialSize, stableId: stableId, balance: state.balanceAmount, inputState: state.inputState, arguments: arguments)
    }))
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    
    return entries
}

private func withdraw(context: any AccountContextProtocol, state: State, stateValue: Signal<State, NoError>, updateState:@escaping((State)->State)->Void, callback:@escaping(Int64)->Void) -> InputDataModalController {

    let actionsDisposable = DisposableSet()
    
    var close:(()->Void)? = nil
    var getController:(()->InputDataController?)? = nil
    
    let initialState: Updated_ChatTextInputState = .init(inputText: .initialize(string: "\(state.balanceAmount.formatted)"))
    
    let interactions = TextView_Interactions(presentation: initialState)
    
    updateState { current in
        var current = current
        current.inputState = initialState
        return current
    }
        
    let arguments = WithdrawArguments(context: context, interactions: interactions, updateState: { [weak interactions] value in
        
        let number = Int64(value.string) ?? 0
        
        var value = value
        if number > state.balance.stars.value {
            let string = state.balance.stars.stringValue
            value = .init(inputText: .initialize(string: string), selectionRange: string.length..<string.length)
            getController?()?.proccessValidation(.fail(.fields([_id_input : .shake])))
        }
        
        interactions?.update { _ in
            return value
        }
        updateState { current in
            var current = current
            current.inputState = value
            return current
        }
    }, withdraw: {
        _ = getController?()?.returnKeyAction()
    }, close: {
        close?()
    })
    
    let signal = stateValue |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: withdrawEntries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: "")
    
    controller.validateData = { _ in
        
        if var value = Int64(interactions.presentation.string) {
            if state.ton {
                value = value * 1_000_000_000
            }
            if state.balance.stars.value < value {
                return .fail(.fields([_id_input : .shake]))
            }
            callback(value)
        }
        close?()
        return .none
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    
    let modalController = InputDataModalController(controller)
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    close = { [weak modalController] in
        modalController?.close()
    }
    getController = { [weak controller] in
        return controller
    }
    
    
    return modalController
}



public func withdrawStarBalance(context: any AccountContextProtocol, stars: StarsContext, state: StarsContext.State, ton: Bool = false, callback:@escaping(Int64)->Void = { _ in }) -> InputDataModalController {
    let initialState = State(ton: ton, config_withdraw: context.appConfiguration.getBoolValue("bot_revenue_withdrawal_enabled", orElse: true), balance: .init(stars: state.balance, usdRate: state.usdRate))

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }

    return withdraw(context: context, state: initialState, stateValue: statePromise.get(), updateState: updateState, callback: callback)
    
}


public func withdrawStarBalance(context: any AccountContextProtocol, balance: StarsRevenueStats, callback:@escaping(Int64)->Void) -> InputDataModalController {
    let initialState = State(config_withdraw: context.appConfiguration.getBoolValue("bot_revenue_withdrawal_enabled", orElse: true), balance: .init(stars: balance.balances.availableBalance.amount, usdRate: balance.usdRate))

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }

    return withdraw(context: context, state: initialState, stateValue: statePromise.get(), updateState: updateState, callback: callback)
    
}
