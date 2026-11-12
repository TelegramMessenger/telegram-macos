import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows
import InputDataUI
import Localization
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import WalletContext
import AppAnalytics


enum WalletMainTab: Equatable {
    case transactions
    case collectibles
}

@available(macOS 10.15, *)
private final class Arguments {
    let context: any AccountContextProtocol
    let gramTooltip: WalletGramTooltipPresenter
    let environment: WalletUIEnvironment
    let receive: ((() -> NSView?)?) -> Void
    let addFunds: ((() -> NSView?)?) -> Void
    let send: ((() -> NSView?)?) -> Void
    let openTransaction: (WalletContext.Transaction, (() -> NSView?)?) -> Void
    let openCollectible: (WalletContext.Collectible) -> Void
    let loadMore: () -> Void
    let showMoreTransactions: () -> Void
    let selectTab: (WalletMainTab) -> Void
    let openAccountProtection: () -> Void
    let openEarnings: () -> Void
    let openPreviousWallets: () -> Void
    let openWaltBalance: () -> Void
    let cardDidLayout: (WalletCardView) -> Void
    let intro = WalletHomeIntro.make()
    let collectables: WalletCollectablesStage

    @available(macOS 10.15, *)
    init(context: any AccountContextProtocol, environment: WalletUIEnvironment, receive: @escaping ((() -> NSView?)?) -> Void, addFunds: @escaping ((() -> NSView?)?) -> Void, send: @escaping ((() -> NSView?)?) -> Void, openTransaction: @escaping (WalletContext.Transaction, (() -> NSView?)?) -> Void, openCollectible: @escaping (WalletContext.Collectible) -> Void, loadMore: @escaping () -> Void, showMoreTransactions: @escaping () -> Void, selectTab: @escaping (WalletMainTab) -> Void, openAccountProtection: @escaping () -> Void, openEarnings: @escaping () -> Void, openPreviousWallets: @escaping () -> Void, openWaltBalance: @escaping () -> Void, cardDidLayout: @escaping (WalletCardView) -> Void, collectables: WalletCollectablesStage, walletContext: WalletContext) {
        self.cardDidLayout = cardDidLayout
        self.openEarnings = openEarnings
        self.openWaltBalance = openWaltBalance
        self.openPreviousWallets = openPreviousWallets
        self.gramTooltip = WalletGramTooltipPresenter(context: context)
        self.context = context
        self.environment = environment
        self.receive = receive
        self.addFunds = addFunds
        self.send = send
        self.openTransaction = openTransaction
        self.openCollectible = openCollectible
        self.collectables = collectables
        self.loadMore = loadMore
        self.showMoreTransactions = showMoreTransactions
        self.selectTab = selectTab
        self.openAccountProtection = openAccountProtection
    }
}

@available(macOS 10.15, *)
struct WalletHomeState: Equatable {
    var walletState: WalletContext.State?
    var accountName: String = ""
    var selectedTab: WalletMainTab = .transactions
    var hasTwoStepAuth: Bool? = nil
    var isResolvingSigningAccess: Bool = false
    var suppressedCollectibleAddresses: Set<String> = []
    var suppressedCollectiblesWalletAddress: String? = nil
    var hasConnectedApps: Bool = false
    var existingWaltBalance: WalletExistingBalance? = nil
    var availableEarnings: Int64? = nil
    var previousWalletsBalance: Int64 = 0
    var transferMinimumAmount: Int64 = 0
    var gaslessDailyTransfers: Int32 = WalletConfiguration.defaultValue.transferGaslessDailyLimit
    var continuousTransactionLoading = false
    var pendingTransferAnimations: [String: WalletPendingTransferAnimation] = [:]

    mutating func updateSuppressedCollectibles(previous: WalletContext.CollectiblesState?) {
        switch walletState?.phase {
        case let .wallet(info):
            if let currentAddress = suppressedCollectiblesWalletAddress, currentAddress != info.address {
                suppressedCollectibleAddresses.removeAll()
                continuousTransactionLoading = false
            }
            suppressedCollectiblesWalletAddress = info.address
            if let previous, let collectibles = walletState?.collectibles,
               previous.generation == collectibles.generation,
               previous.isRefreshing || previous.isLoadingMore,
               !collectibles.isRefreshing, !collectibles.isLoadingMore,
               collectibles.error == nil, collectibles.nextOffset == nil {
                suppressedCollectibleAddresses.formIntersection(collectibles.items.map(\.address))
            }
        case .restoring, .none:
            break
        case .creating, .empty, .failed:
            suppressedCollectibleAddresses.removeAll()
            suppressedCollectiblesWalletAddress = nil
            continuousTransactionLoading = false
        }
    }
}

private struct CardData: Equatable {
    var balance: Int64
    var fiatText: String?
    var name: String
    var address: String
}

struct WalletListEntry<Value: Equatable>: Equatable {
    let value: Value
    let viewType: GeneralViewType
}

@available(macOS 10.15, *)
private struct WalletTransactionListValue: Equatable {
    let entry: WalletListEntry<WalletContext.Transaction>
    let transferAnimation: WalletPendingTransferAnimation?
}

@available(macOS 10.15, *)
func walletShowsTransferAnimation(_ transaction: WalletContext.Transaction) -> Bool {
    return transaction.status == .pending && transaction.currency == .ton && transaction.direction == .outgoing
        && transaction.kind != .deployContract && transaction.kind != .keyChange
        && transaction.isVisibleInWalletHistory
}

enum WalletPendingTransferObservation: Equatable {
    case remove
    case keep(isPending: Bool)
}

@available(macOS 10.15, *)
func walletObservePendingTransfer(_ transaction: WalletContext.Transaction?, isFlying: Bool, isVisible: Bool) -> WalletPendingTransferObservation {
    guard let transaction, transaction.status != .failed else {
        return .remove
    }
    let isPending = transaction.status == .pending
    if !isPending && !isFlying && !isVisible {
        return .remove
    }
    return .keep(isPending: isPending)
}

@available(macOS 10.15, *)
func walletAcceptsTransferAnimation(_ transaction: WalletContext.Transaction?, sourceWindowMissing: Bool) -> Bool {
    guard let transaction, transaction.status != .failed, transaction.isVisibleInWalletHistory else {
        return false
    }
    return !sourceWindowMissing
}

/// `hasHeader` means a row already opened this block (the tabs switch), so the first value must not
/// round its top corners again.
func walletListEntries<Value: Equatable>(_ values: [Value], hasLoadMore: Bool, hasHeader: Bool = false) -> [WalletListEntry<Value>] {
    return values.enumerated().map { index, value in
        let isFirst = index == 0 && !hasHeader
        let isLast = index == values.count - 1 && !hasLoadMore
        let viewType: GeneralViewType
        if isFirst && isLast {
            viewType = .singleItem
        } else if isFirst {
            viewType = .firstItem
        } else if isLast {
            viewType = .lastItem
        } else {
            viewType = .innerItem
        }
        return WalletListEntry(value: value, viewType: viewType)
    }
}

private let walletTermsOfServiceUrl = "https://telegram.org/tos"
let walletTermsText = strings().walletControllerTermsAgreement(walletTermsOfServiceUrl)

private let _id_card = InputDataIdentifier("_id_card")
private let _id_walt_balance = InputDataIdentifier("_id_walt_balance")
private let _id_earnings_balance = InputDataIdentifier("_id_earnings_balance")
private let _id_previous_wallets_balance = InputDataIdentifier("_id_previous_wallets_balance")

enum WalletHomeBanner: String {
    case walt
    case earnings
    case previousWallets
}

@available(macOS 10.15, *)
func walletHomeBanners(_ state: WalletHomeState) -> [WalletHomeBanner] {
    var banners: [WalletHomeBanner] = []
    if state.existingWaltBalance?.hasBalance == true {
        banners.append(.walt)
    }
    if let earnings = state.availableEarnings, earnings >= 10_000_000_000 {
        banners.append(.earnings)
    }
    if state.previousWalletsBalance > 0 {
        banners.append(.previousWallets)
    }
    return banners
}
private let _id_actions = InputDataIdentifier("_id_actions")
private let _id_protect_account = InputDataIdentifier("_id_protect_account")
private let _id_tabs = InputDataIdentifier("_id_tabs")
private let _id_load_more = InputDataIdentifier("_id_load_more")
private let _id_collectibles_grid = InputDataIdentifier("_id_collectibles_grid")
private let _id_info_fast = InputDataIdentifier("_id_info_fast")
private let _id_info_cheap = InputDataIdentifier("_id_info_cheap")
private let _id_info_verified = InputDataIdentifier("_id_info_verified")
func walletHomeTransactionIdentifier(_ id: String) -> InputDataIdentifier {
    return InputDataIdentifier("_id_transaction_\(id)")
}
func walletHomeCollectibleIdentifier(_ address: String) -> InputDataIdentifier {
    return InputDataIdentifier("_id_collectible_\(address)")
}

@available(macOS 10.15, *)
func walletDisplayBalance(_ walletState: WalletContext.State) -> Int64? {
    guard let balance = walletState.balance.currentValue else {
        return nil
    }
    return balance.magnitude < 1_000_000 ? 0 : balance
}

@available(macOS 10.15, *)
func walletFiatText(_ walletState: WalletContext.State) -> String? {
    return walletFiatText(walletState, balance: walletState.balance.currentValue)
}

@available(macOS 10.15, *)
func walletFiatText(_ walletState: WalletContext.State, balance: Int64?) -> String? {
    guard let balance else {
        return nil
    }
    let maxDecimalPositions = balance == 0 ? 0 : 2
    if let rate = walletState.fiat.selectedRate {
        return formatTonFiatValue(balance, rate: rate.unitsPerGram, currencySymbol: walletState.fiat.selectedCurrency.symbol, maxDecimalPositions: maxDecimalPositions)
    }
    if let usdRate = walletState.fiat.rates.currentValue?[.usd] {
        return formatTonFiatValue(balance, rate: usdRate.unitsPerGram, currencySymbol: WalletContext.FiatCurrency.usd.symbol, maxDecimalPositions: maxDecimalPositions)
    }
    return nil
}

@available(macOS 10.15, *)
private func entries(_ state: WalletHomeState, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []

    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1

    let earnings = state.availableEarnings.flatMap { $0 > 0 ? $0 : nil }
    let previousWalletsBalance = state.previousWalletsBalance > 0 ? state.previousWalletsBalance : nil
    let banners = walletHomeBanners(state)
    let bannerKey = banners.map { $0.rawValue }.joined(separator: "-")
    for banner in banners {
        let viewType = bestGeneralViewType(banners, for: banner)
        switch banner {
        case .walt:
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_walt_balance, equatable: .init(bannerKey), comparable: nil, item: { initialSize, stableId in
                return WalletBalanceBannerRowItem(initialSize, stableId: stableId, prefix: strings().walletControllerWaltFundsBanner, amount: nil, suffix: "", viewType: viewType, action: arguments.openWaltBalance)
            }))
            index += 1
        case .earnings:
            guard let earnings else {
                continue
            }
            let amountText = formatTonAmountText(earnings, maxDecimalPositions: nil)
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_earnings_balance, equatable: .init("\(earnings):\(bannerKey)"), comparable: nil, item: { initialSize, stableId in
                return WalletBalanceBannerRowItem(initialSize, stableId: stableId, prefix: strings().walletControllerEarningsBannerPrefix, amount: amountText, suffix: strings().walletControllerEarningsBannerSuffix, viewType: viewType, action: arguments.openEarnings)
            }))
            index += 1
        case .previousWallets:
            guard let previousWalletsBalance else {
                continue
            }
            let amountText = formatTonAmountText(previousWalletsBalance, maxDecimalPositions: 2)
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_previous_wallets_balance, equatable: .init("\(previousWalletsBalance):\(bannerKey)"), comparable: nil, item: { initialSize, stableId in
                return WalletBalanceBannerRowItem(initialSize, stableId: stableId, prefix: strings().walletControllerPreviousWalletsBannerPrefix, amount: amountText, suffix: strings().walletControllerPreviousWalletsBannerSuffix, viewType: viewType, action: arguments.openPreviousWallets)
            }))
            index += 1
        }
    }
    if !banners.isEmpty {
        entries.append(.sectionId(sectionId, type: .customModern(10)))
    }
    sectionId += 1
    index = 0

    let address = state.walletState?.walletAddress ?? ""
    let displayBalance = state.walletState.flatMap(walletDisplayBalance)
    let fiatText = state.walletState.flatMap { walletFiatText($0, balance: displayBalance) }
    let cardData = CardData(
        balance: displayBalance ?? 0,
        fiatText: fiatText,
        name: state.accountName,
        address: address
    )

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_card, equatable: .init(cardData), comparable: nil, item: { initialSize, stableId in
        return WalletCardRowItem(
            initialSize,
            stableId: stableId,
            context: arguments.context,
            balance: cardData.balance,
            fiatText: cardData.fiatText,
            name: cardData.name,
            address: cardData.address,
            viewType: .singleItem,
            cardDidLayout: { cardView in
                arguments.gramTooltip.update(cardView: cardView, address: cardData.address)
                arguments.intro.attach(cardView)
                arguments.collectables.attach(card: cardView)
                arguments.cardDidLayout(cardView)
            },
            receiveAction: arguments.receive
        )
    }))
    index += 1

    entries.append(.sectionId(sectionId, type: .customModern(12)))
    sectionId += 1

    let addFundsTitle = strings().walletControllerAddFunds
    let sendTitle = strings().walletControllerSend
    let actionsEnabled = state.walletState?.walletAddress != nil
    let isResolvingSigningAccess = state.isResolvingSigningAccess
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_actions, equatable: .init("\(actionsEnabled):\(isResolvingSigningAccess)"), comparable: nil, item: { initialSize, stableId in
        return WalletActionsRowItem(
            initialSize,
            stableId: stableId,
            leftTitle: addFundsTitle,
            leftEnabled: actionsEnabled,
            rightEnabled: actionsEnabled && !isResolvingSigningAccess,
            rightTitle: sendTitle,
            viewType: .singleItem,
            intro: arguments.intro,
            leftAction: arguments.addFunds,
            rightAction: arguments.send
        )
    }))
    index += 1

    var transactions: [WalletContext.Transaction] = []
    var canLoadMore = false
    var isLoadingMore = false
    if let walletState = state.walletState {
        transactions = walletVisibleTransactions(walletState.transactions.items)
        canLoadMore = walletState.transactions.canLoadMore
        isLoadingMore = walletState.transactions.isLoadingMore
    }

    let showsAccountProtection = state.hasTwoStepAuth == false && !transactions.isEmpty
    if showsAccountProtection {
        entries.append(.sectionId(sectionId, type: .customModern(12)))
        sectionId += 1

        let protectTitle = strings().walletControllerProtectAccount
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_protect_account, equatable: .init(protectTitle), comparable: nil, item: { initialSize, stableId in
            return GeneralInteractedRowItem(
                initialSize,
                stableId: stableId,
                name: protectTitle,
                icon: NSImage(named: "Wallet_AccountProtection")?.precomposed(),
                nameStyle: ControlStyle(font: .normal(.title), foregroundColor: theme.colors.redUI),
                type: .next,
                viewType: .singleItem,
                action: arguments.openAccountProtection
            )
        }))
        index += 1
    }

    var showsSetupNotice = false
    if let walletState = state.walletState {
        switch walletState.phase {
        case .creating, .empty, .restoring:
            showsSetupNotice = true
            entries.append(.sectionId(sectionId, type: .customModern(12)))
            sectionId += 1
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().walletControllerSettingUp), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
            index += 1
        case .wallet, .failed:
            break
        }
    }

    var collectibles: [WalletContext.Collectible] = []
    if let walletState = state.walletState {
        collectibles = walletState.collectibles.items.filter { !state.suppressedCollectibleAddresses.contains($0.address) }
    }

    var selectedTab = state.selectedTab
    if collectibles.isEmpty {
        selectedTab = .transactions
    }

    let hasTabs = !collectibles.isEmpty

    if hasTabs {
        entries.append(.sectionId(sectionId, type: .customModern(12)))
        sectionId += 1

        let transactionsTitle = strings().walletControllerTransactions
        let collectiblesTitle = strings().walletControllerCollectibles
        let selectedIndex = selectedTab == .transactions ? 0 : 1
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_tabs, equatable: .init(selectedIndex), comparable: nil, item: { initialSize, stableId in
            return WalletTabsRowItem(initialSize, stableId: stableId, titles: [transactionsTitle, collectiblesTitle], selectedIndex: selectedIndex, viewType: .singleItem, callback: { tabIndex in
                arguments.selectTab(tabIndex == 0 ? .transactions : .collectibles)
            })
        }))
        index += 1
    }

    if selectedTab == .collectibles {
        entries.append(.sectionId(sectionId, type: .customModern(12)))
        sectionId += 1

        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_collectibles_grid, equatable: .init(collectibles), comparable: nil, item: { initialSize, stableId in
            return WalletCollectablesRowItem(initialSize, stableId: stableId, context: arguments.context, environment: arguments.environment, collectibles: collectibles, stage: arguments.collectables, viewType: .singleItem, open: arguments.openCollectible)
        }))
        index += 1
        if case .wallet? = state.walletState?.phase, collectibles.contains(where: { $0.kind == .gift }) {
            let footer = strings().walletControllerStickerGridFooter
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(footer), data: .init(color: theme.colors.grayText, viewType: .textBottomItem, fontSize: 13, centerViewAlignment: true, alignment: .center)))
            index += 1
        }
    } else if !transactions.isEmpty {
        entries.append(.sectionId(sectionId, type: .customModern(12)))
        sectionId += 1

        var transactionIdentifierCounts: [String: Int] = [:]
        for entry in walletListEntries(transactions, hasLoadMore: canLoadMore) {
            let occurrence = transactionIdentifierCounts[entry.value.presentationId, default: 0]
            transactionIdentifierCounts[entry.value.presentationId] = occurrence + 1
            let identifier = occurrence == 0 ? walletHomeTransactionIdentifier(entry.value.presentationId) : walletHomeTransactionIdentifier("\(entry.value.presentationId)#\(occurrence)")
            let transferAnimation = occurrence == 0 ? state.pendingTransferAnimations[entry.value.presentationId] : nil
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: identifier, equatable: .init(WalletTransactionListValue(entry: entry, transferAnimation: transferAnimation)), comparable: nil, item: { initialSize, stableId in
                return WalletTransactionRowItem(
                    initialSize,
                    stableId: stableId,
                    context: arguments.context, environment: arguments.environment,
                    transaction: entry.value,
                    walletAddress: cardData.address,
                    transferAnimation: transferAnimation,
                    viewType: entry.viewType,
                    callback: arguments.openTransaction
                )
            }))
            index += 1
        }

        if canLoadMore {
            let mode: WalletLoadMoreMode = state.continuousTransactionLoading || isLoadingMore ? .loading : .showMore
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_load_more, equatable: .init(mode), comparable: nil, item: { initialSize, stableId in
                return WalletLoadMoreRowItem(initialSize, stableId: stableId, mode: mode, viewType: .lastItem, action: arguments.showMoreTransactions)
            }))
            index += 1
        }

        let footerText = strings().walletControllerSmallTransactionsHidden(formatGramsText(state.transferMinimumAmount, maxDecimalPositions: 9))
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(footerText), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem, inset: .init(left: 20, right: 20, top: 3 - .borderSize, bottom: 0))))
        index += 1
    } else {
        entries.append(.sectionId(sectionId, type: .customModern(showsSetupNotice ? 8 : 26)))
        sectionId += 1

        let instantTransfersTitle = strings().walletControllerInstantTransfers
        let instantTransfersText = strings().walletControllerInstantTransfersInfo
        let zeroFeesTitle = strings().walletControllerZeroFees
        let zeroFeesText = strings().walletControllerZeroFeesInfoOther(Int(state.gaslessDailyTransfers))
        let blockchainVerifiedTitle = strings().walletControllerBlockchainVerified
        let blockchainVerifiedText = strings().walletControllerBlockchainVerifiedInfo

        let paragraphs: [(InputDataIdentifier, String, String, String)] = [
            (_id_info_fast, "Wallet_InfoFast", instantTransfersTitle, instantTransfersText),
            (_id_info_cheap, "Wallet_InfoCheap", zeroFeesTitle, zeroFeesText),
            (_id_info_verified, "Wallet_InfoVerified", blockchainVerifiedTitle, blockchainVerifiedText)
        ]

        for (identifier, iconName, title, text) in paragraphs {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: identifier, equatable: .init(0 as Int32), comparable: nil, item: { initialSize, stableId in
                return WalletInfoParagraphRowItem(
                    initialSize,
                    stableId: stableId,
                    icon: NSImage(named: iconName)?.precomposed(walletClassicAccent),
                    title: title,
                    text: text,
                    viewType: .singleItem
                )
            }))
            index += 1
        }

        entries.append(.sectionId(sectionId, type: .customModern(9)))
        sectionId += 1

        entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(walletTermsText, linkHandler: { link in
            arguments.environment.openExternalURL(link)
        }), data: .init(color: theme.colors.listGrayText, detectBold: false, viewType: .textBottomItem, fontSize: .text, inset: .init(left: 20, right: 20), centerViewAlignment: true, alignment: .center, linkColor: walletClassicAccent)))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .customModern(24)))
    sectionId += 1

    return entries
}

/// Drives the card's scroll collapse from the table offset: the card leans back and shrinks over the
/// distance it takes to leave the viewport, mirroring the pager collapse on iOS.
@available(macOS 10.15, *)
private final class WalletCardScrollCollapse {
    weak var cardView: WalletCardView?
    weak var tableView: TableView?
    var onCollapsedChanged: ((Bool) -> Void)?
    private(set) var isCollapsed = false

    func apply() {
        guard let cardView, let tableView else {
            return
        }
        let distance = cardView.frame.height + 12.0
        guard distance > 0 else {
            return
        }
        let fraction = tableView.documentOffset.y / distance
        cardView.updateScrollCollapse(fraction: fraction)
        let collapsed = isCollapsed ? fraction > 0.5 : fraction >= 0.6
        if collapsed != isCollapsed {
            isCollapsed = collapsed
            onCollapsedChanged?(collapsed)
        }
    }
}

@available(macOS 10.15, *)
private func walletHeaderBalanceText(_ walletState: WalletContext.State?) -> (title: String, subtitle: String?)? {
    guard let walletState, case .wallet = walletState.phase, let balance = walletDisplayBalance(walletState) else {
        return nil
    }
    return (formatTonAmountText(balance, maxDecimalPositions: 2) + " GRAM", walletFiatText(walletState, balance: balance))
}

@available(macOS 10.15, *)
public func showWallet(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext?, for window: Window, morphSource: (() -> NSView?)? = nil, opensCollectibles: Bool = false) {
    presentWallet(context: context, environment: environment, walletContext: walletContext, for: window, morphSource: morphSource, analyticsContext: nil, opensCollectibles: opensCollectibles)
}

@available(macOS 10.15, *)
public func showWallet(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext?, for window: Window, morphSource: (() -> NSView?)? = nil, analyticsContext: AnalyticsContext, opensCollectibles: Bool = false) {
    presentWallet(context: context, environment: environment, walletContext: walletContext, for: window, morphSource: morphSource, analyticsContext: analyticsContext, opensCollectibles: opensCollectibles)
}

@available(macOS 10.15, *)
private func presentWallet(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext?, for window: Window, morphSource: (() -> NSView?)?, analyticsContext: AnalyticsContext?, opensCollectibles: Bool) {
    guard let walletContext = walletContext else {
        return
    }

    let presentation = analyticsContext?.beginPresentation()
    let prepare: (InputDataModalController) -> InputDataModalController = { controller in
        if let analyticsContext {
            controller.analyticsContext = analyticsContext
            controller.current.analyticsContext = analyticsContext
            let onDeinit = controller.onDeinit
            controller.onDeinit = {
                onDeinit?()
                presentation?.end()
            }
        }
        return controller
    }

    switch walletContext.stateValue.phase {
    case .restoring, .empty, .creating, .wallet:
        showModal(with: prepare(WalletController(context: context, environment: environment, walletContext: walletContext, opensCollectibles: opensCollectibles)), for: window, morphSource: morphSource)
    case let .failed(error):
        let errorText: String
        switch error {
        case .identityMismatch:
            errorText = strings().walletControllerErrorDataMismatch
        case .corrupted, .unsupportedVersion:
            errorText = strings().walletControllerErrorDataUnreadable
        case .keychainStatus:
            errorText = strings().walletControllerErrorStorageUnavailable
        }
        showModal(with: prepare(WalletSettingsController(context: context, environment: environment, walletContext: walletContext)), for: window)
        environment.alert(for: window, info: errorText)
    }
}

@available(macOS 10.15, *)
public func WalletController(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, opensCollectibles: Bool = false) -> InputDataModalController {
    let actionsDisposable = DisposableSet()
    let waltBalanceDisposable = MetaDisposable()
    actionsDisposable.add(waltBalanceDisposable)
    var loadMoreImpl: (() -> Void)?
    var isAwaitingWaltBalanceUrl = false
    var openPendingWaltBalanceUrl: ((String) -> Void)? = nil
    var loadMoreIfNeeded: (() -> Void)?
    weak var loadMoreTableView: TableView?
    var updateHeaderImpl: (() -> Void)?
    var refreshPreviousWalletsBalanceImpl: (() -> Void)?
    actionsDisposable.add(walletContext.beginWalletScreenUpdates())
    let loadMoreDisposable = MetaDisposable()
    actionsDisposable.add(loadMoreDisposable)
    let twoStepAuthDisposable = MetaDisposable()
    actionsDisposable.add(twoStepAuthDisposable)

    let walletConfiguration = WalletConfiguration.with(appConfiguration: context.appConfiguration)
    var initialState = WalletHomeState()
    initialState.transferMinimumAmount = walletConfiguration.transferMinAmount
    initialState.gaslessDailyTransfers = walletConfiguration.transferGaslessDailyLimit
    initialState.selectedTab = opensCollectibles ? .collectibles : .transactions
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((WalletHomeState) -> WalletHomeState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    var isAwaitingAccountProtection = false
    let refreshTwoStepAuth: () -> Void = {
        twoStepAuthDisposable.set((context.engine.auth.twoStepAuthData()
        |> map(Optional.init)
        |> `catch` { _ in Signal<TwoStepAuthData?, NoError>.single(nil) }
        |> deliverOnMainQueue).start(next: { data in
            if isAwaitingAccountProtection, data?.currentPasswordDerivation != nil {
                isAwaitingAccountProtection = false
                delay(0.4, closure: {
                    environment.showModalText(for: context.window, text: strings().walletControllerAccountProtected, title: strings().walletControllerPasswordSet)
                })
            }
            updateState { current in
                var current = current
                current.hasTwoStepAuth = data.map { $0.currentPasswordDerivation != nil || $0.unconfirmedEmailPattern != nil }
                return current
            }
        }))
    }
    refreshTwoStepAuth()

    let restoreAuthorization = WalletFlowAuthorization(walletContext: walletContext, reason: walletRestoreFlowReason)
    let signingAccessDisposable = MetaDisposable()
    actionsDisposable.add(signingAccessDisposable)
    let cardScrollCollapse = WalletCardScrollCollapse()
    let setResolving: (Bool) -> Void = { value in
        updateState { current in
            var current = current
            current.isResolvingSigningAccess = value
            return current
        }
    }
    let abandonRestoration: () -> Void = {
        signingAccessDisposable.set(nil)
        restoreAuthorization.end()
        setResolving(false)
    }
    var revealsSentTransfer = false
    var transferToReveal: String?
    var revealsLatestTransactions = false
    var revealLatestTransactionsImpl: (() -> Void)?
    let showTransactions: () -> Void = {
        transferToReveal = nil
        revealsLatestTransactions = true
        if stateValue.with({ $0.selectedTab == .transactions }) {
            revealLatestTransactionsImpl?()
        } else {
            updateState { current in
                var current = current
                current.selectedTab = .transactions
                return current
            }
        }
    }
    let openReceive: ((() -> NSView?)?) -> Void = { morphSource in
        guard let address = walletContext.stateValue.walletAddress else {
            return
        }
        showModal(with: WalletReceiveController(context: context, environment: environment, walletContext: walletContext, address: address, appeared: {
            guard walletContext.stateValue.walletAddress == address else {
                return
            }
            showTransactions()
        }), for: context.window, morphSource: morphSource)
    }
    var receiveTransferAnimationImpl: WalletSendTransferAnimation?
    let transferAnimation: WalletSendTransferAnimation = { id, source in
        return receiveTransferAnimationImpl?(id, source) ?? false
    }
    var openSend: (((() -> NSView?)?) -> Void)?
    openSend = { morphSource in
        switch walletContext.stateValue.phase {
        case let .wallet(info) where info.canSign:
            abandonRestoration()
            showModal(with: WalletSendController(context: context, environment: environment, walletContext: walletContext, transferAnimation: transferAnimation), for: context.window, morphSource: morphSource)
        case let .wallet(info) where info.canExportPhrase:
            setResolving(true)
            signingAccessDisposable.set(walletRestoreSigningAccess(context: context, environment: environment, window: context.window, walletContext: walletContext, authorization: restoreAuthorization, retry: {
                openSend?(morphSource)
            }, next: {
                setResolving(false)
                showModal(with: WalletSendController(context: context, environment: environment, walletContext: walletContext, transferAnimation: transferAnimation), for: context.window, morphSource: morphSource)
            }, failed: {
                setResolving(false)
            }))
        case .wallet:
            environment.verifyAlert(for: context.window, header: strings().walletControllerSecretPhraseRequired, information: strings().walletControllerSecretPhraseRequiredToSend, ok: strings().walletControllerProceed, cancel: strings().walletControllerCancel, successHandler: { _ in
                showModal(with: WalletImportController(context: context, environment: environment, walletContext: walletContext, mode: .enterRecoveryPhrase, onImported: {
                    environment.showModalText(for: context.window, text: strings().walletControllerWalletImportedInfo, title: strings().walletControllerWalletImported)
                    showModal(with: WalletSendController(context: context, environment: environment, walletContext: walletContext, transferAnimation: transferAnimation), for: context.window, morphSource: morphSource)
                }), for: context.window)
            })
        case .restoring where walletContext.stateValue.walletAddress != nil:
            abandonRestoration()
            showModal(with: WalletSendController(context: context, environment: environment, walletContext: walletContext, transferAnimation: transferAnimation), for: context.window, morphSource: morphSource)
        default:
            environment.showModalText(for: context.window, text: strings().walletControllerStillSyncing)
        }
    }

    let collectables = WalletCollectablesStage(context: context, environment: environment, walletContext: walletContext)
    let arguments = Arguments(context: context, environment: environment, receive: { morphSource in
        openReceive(morphSource)
    }, addFunds: { morphSource in
        openReceive(morphSource)
    }, send: { morphSource in
        guard !stateValue.with({ $0.isResolvingSigningAccess }) else {
            return
        }
        revealsSentTransfer = true
        openSend?(morphSource)
    }, openTransaction: { transaction, morphSource in
        revealsSentTransfer = true
        showModal(with: WalletTransactionController(context: context, environment: environment, walletContext: walletContext, subject: .transaction(transaction), transferAnimation: transferAnimation), for: context.window, morphSource: morphSource)
    }, openCollectible: { collectible in
        showModal(with: WalletCollectibleDetailsController(context: context, environment: environment, walletContext: walletContext, collectible: collectible, cardStage: collectables, collectibleSent: { address in
            updateState { current in
                var current = current
                current.suppressedCollectibleAddresses.insert(address)
                return current
            }
            showTransactions()
        }), for: context.window)
    }, loadMore: {
        loadMoreImpl?()
    }, showMoreTransactions: {
        updateState { current in
            var current = current
            current.continuousTransactionLoading = true
            return current
        }
        loadMoreImpl?()
    }, selectTab: { tab in
        updateState { current in
            var current = current
            current.selectedTab = tab
            return current
        }
    }, openAccountProtection: {
        isAwaitingAccountProtection = true
        environment.openAccountProtection()
    }, openEarnings: {
        WalletUIHooks.shared.openTonEarnings(context)
    }, openPreviousWallets: {
        showModal(with: WalletSettingsController(context: context, environment: environment, walletContext: walletContext), for: context.window)
    }, openWaltBalance: {
        guard case let .wallet(info) = walletContext.stateValue.phase else {
            return
        }
        let window = context.window
        if let url = stateValue.with({ $0.existingWaltBalance?.url }) {
            if let navigate = environment.prepareOnrampNavigation(url) {
                navigate()
            } else {
                environment.alert(for: window, info: strings().unknownError)
            }
            return
        }
        isAwaitingWaltBalanceUrl = true
        waltBalanceDisposable.set((showModalProgress(signal: context.engine.payments.createOnrampSession(provider: "wallet", cryptoCurrency: "gram", address: info.address, paymentMethod: "balance"), for: window)
        |> deliverOnMainQueue).start(next: { session in
            guard let navigate = environment.prepareOnrampNavigation(session.url) else {
                environment.alert(for: window, info: strings().unknownError)
                return
            }
            navigate()
        }, error: { _ in
            environment.alert(for: window, info: strings().unknownError)
        }))
    }, cardDidLayout: { cardView in
        cardScrollCollapse.cardView = cardView
        cardScrollCollapse.apply()
    }, collectables: collectables, walletContext: walletContext)

    arguments.collectables.limitReached = {
        environment.showModalText(for: context.window, text: strings().walletControllerSaveCardFailed)
    }

    openPendingWaltBalanceUrl = { url in
        guard isAwaitingWaltBalanceUrl else {
            return
        }
        isAwaitingWaltBalanceUrl = false
        if let navigate = environment.prepareOnrampNavigation(url) {
            navigate()
        }
    }

    loadMoreImpl = {
        let walletState = walletContext.stateValue
        guard walletState.activeOperation == nil else {
            return
        }
        let (selectedTab, suppressedCollectibleAddresses) = stateValue.with { ($0.selectedTab, $0.suppressedCollectibleAddresses) }
        let hasCollectibles = walletState.collectibles.items.contains { !suppressedCollectibleAddresses.contains($0.address) }
        if selectedTab == .collectibles && hasCollectibles {
            guard walletState.collectibles.canLoadMore, !walletState.collectibles.isRefreshing, !walletState.collectibles.isLoadingMore else {
                return
            }
            loadMoreDisposable.set(walletContext.loadMoreCollectibles().start())
        } else {
            let continuousLoading = stateValue.with { $0.continuousTransactionLoading }
            guard walletState.transactions.canLoadMore, !walletState.transactions.isLoadingMore,
                  continuousLoading || walletVisibleTransactions(walletState.transactions.items).isEmpty else {
                return
            }
            loadMoreDisposable.set(walletContext.loadMoreTransactions().start())
        }
    }
    loadMoreIfNeeded = {
        let walletState = walletContext.stateValue
        guard walletState.transactions.error == nil, walletState.collectibles.error == nil,
              let tableView = loadMoreTableView,
              tableView.documentOffset.y + tableView.frame.height > tableView.documentSize.height - 240 else {
            return
        }
        loadMoreImpl?()
    }

    actionsDisposable.add((context.engine.data.subscribe(TelegramEngine.EngineData.Item.Configuration.App())
    |> map { WalletConfiguration.with(appConfiguration: $0) }
    |> deliverOnMainQueue).start(next: { configuration in
        collectables.updateConfiguration(configuration)
        updateState { current in
            var current = current
            current.transferMinimumAmount = configuration.transferMinAmount
            current.gaslessDailyTransfers = configuration.transferGaslessDailyLimit
            return current
        }
    }))

    let finishPendingTransfer: (String) -> Void = { id in
        updateState { current in
            var current = current
            current.pendingTransferAnimations.removeValue(forKey: id)
            return current
        }
    }
    let makePendingTransferAnimation: (WalletContext.Transaction) -> WalletPendingTransferAnimation = { transaction in
        let id = transaction.presentationId
        let animation = WalletPendingTransferAnimation(id: id, isCollectible: transaction.collectible != nil)
        animation.onFinished = {
            finishPendingTransfer(id)
        }
        return animation
    }
    receiveTransferAnimationImpl = { id, source in
        let transaction = walletContext.stateValue.transactions.items.first(where: { $0.presentationId == id })
        guard walletAcceptsTransferAnimation(transaction, sourceWindowMissing: source.map { $0.window == nil } ?? false), let transaction else {
            return false
        }
        let animation = stateValue.with { $0.pendingTransferAnimations[id] } ?? makePendingTransferAnimation(transaction)
        animation.isPending = transaction.status == .pending
        revealsSentTransfer = false
        transferToReveal = id
        revealsLatestTransactions = false
        updateState { current in
            var current = current
            current.pendingTransferAnimations[id] = animation
            current.selectedTab = .transactions
            return current
        }
        if let source {
            animation.launch(source, at: CACurrentMediaTime())
        }
        return true
    }
    let observePendingTransfers: (WalletContext.State) -> [String: WalletPendingTransferAnimation] = { walletState in
        var animations = stateValue.with { $0.pendingTransferAnimations }
        let transactions = Dictionary(walletState.transactions.items.map { ($0.presentationId, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, animation) in animations {
            switch walletObservePendingTransfer(transactions[id], isFlying: animation.isFlying, isVisible: animation.isVisible) {
            case let .keep(isPending):
                animation.isPending = isPending
            case .remove:
                animation.onFinished = nil
                animation.suspend()
                animations.removeValue(forKey: id)
            }
        }
        for transaction in walletState.transactions.items where walletShowsTransferAnimation(transaction) && animations[transaction.presentationId] == nil {
            animations[transaction.presentationId] = makePendingTransferAnimation(transaction)
        }
        return animations.filter { !$0.value.finished }
    }

    actionsDisposable.add((walletContext.state
    |> deliverOnMainQueue).start(next: { walletState in
        let pendingTransferAnimations = observePendingTransfers(walletState)
        let previousWalletState = stateValue.with { $0.walletState }
        if let error = walletState.cardStickerSaveError, error != previousWalletState?.cardStickerSaveError {
            walletShowCardSaveError(error, context: context, environment: environment)
        }
        let walletAddressChanged = previousWalletState != nil && previousWalletState?.walletAddress != walletState.walletAddress
        let reloadsPreviousWallets = walletAddressChanged || (previousWalletState != nil && previousWalletState?.phase != walletState.phase)
        if case let .wallet(previousInfo) = previousWalletState?.phase {
            switch walletState.phase {
            case let .wallet(info) where previousInfo.address == info.address && previousInfo.publicKey == info.publicKey:
                break
            default:
                abandonRestoration()
                revealsLatestTransactions = false
            }
        }
        var revealsTransfer = false
        if revealsSentTransfer, let previousTransactions = stateValue.with({ $0.walletState?.transactions.items }) {
            let previousIds = Set(previousTransactions.map(\.presentationId))
            if let sent = walletState.transactions.items.first(where: { !previousIds.contains($0.presentationId) && walletShowsTransferAnimation($0) }) {
                revealsSentTransfer = false
                transferToReveal = sent.presentationId
                revealsLatestTransactions = false
                revealsTransfer = true
            }
        }
        updateState { current in
            var current = current
            let previousCollectibles = current.walletState?.collectibles
            current.walletState = walletState
            current.pendingTransferAnimations = pendingTransferAnimations
            current.updateSuppressedCollectibles(previous: previousCollectibles)
            if revealsTransfer {
                current.selectedTab = .transactions
            }
            if walletAddressChanged {
                current.previousWalletsBalance = 0
            }
            return current
        }
        arguments.collectables.update(state: walletState, suppressed: stateValue.with { $0.suppressedCollectibleAddresses })
        if reloadsPreviousWallets {
            refreshPreviousWalletsBalanceImpl?()
        }
    }))

    actionsDisposable.add((walletContext.tonConnectState
    |> map { state -> Bool in
        return !walletConnectedAppSessions(state.sessions).isEmpty
    }
    |> distinctUntilChanged
    |> deliverOnMainQueue).start(next: { hasConnectedApps in
        updateState { current in
            var current = current
            current.hasConnectedApps = hasConnectedApps
            return current
        }
    }))

    let existingWaltBalanceDisposable = MetaDisposable()
    actionsDisposable.add(existingWaltBalanceDisposable)
    let refreshExistingWaltBalance: () -> Void = {
        existingWaltBalanceDisposable.set((context.engine.wallet.getExistingWaltBalance()
        |> deliverOnMainQueue).start(next: { balance in
            updateState { current in
                var current = current
                current.existingWaltBalance = balance
                return current
            }
            if let balance, balance.hasBalance, let url = balance.url {
                openPendingWaltBalanceUrl?(url)
            }
        }))
    }
    refreshExistingWaltBalance()

    let earningsContext = context.engine.payments.peerStarsRevenueContext(peerId: context.peerId, ton: true)
    actionsDisposable.add((earningsContext.state
    |> deliverOnMainQueue).start(next: { revenueState in
        guard let availableBalance = revenueState.stats?.balances.availableBalance, availableBalance.currency == .ton else {
            return
        }
        updateState { current in
            var current = current
            current.availableEarnings = availableBalance.amount.value
            return current
        }
    }))
    let previousWalletsDisposable = MetaDisposable()
    actionsDisposable.add(previousWalletsDisposable)
    let refreshPreviousWalletsBalance: () -> Void = {
        previousWalletsDisposable.set((walletContext.previousWallets(refreshBalances: true)
        |> deliverOnMainQueue).start(next: { wallets in
            let balance = walletUniquePreviousWallets(wallets).reduce(Int64(0)) { $0 + ($1.balance ?? 0) }
            updateState { current in
                var current = current
                current.previousWalletsBalance = balance
                return current
            }
        }, error: { _ in
            updateState { current in
                var current = current
                current.previousWalletsBalance = 0
                return current
            }
        }))
    }
    refreshPreviousWalletsBalanceImpl = refreshPreviousWalletsBalance
    refreshPreviousWalletsBalance()

    let refreshAdditionalBalances: () -> Void = {
        refreshExistingWaltBalance()
        refreshPreviousWalletsBalance()
        earningsContext.reload()
    }

    actionsDisposable.add(walletUIPeerView(peerId: context.peerId, postbox: context.account.postbox).start(next: { peer in
        updateState { current in
            var current = current
            current.accountName = peer.map { environment.peerTitle($0, compact: false).uppercased() } ?? ""
            return current
        }
    }))

    let signal = statePromise.get()
    |> deliverOnPrepareQueue
    |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments), animated: true)
    }

    let title = strings().walletControllerMoney
    let controller = InputDataController(dataSignal: signal, title: title, hasDone: false)
    controller.analyticsScreen = .wallet

    controller.onDeinit = {
        actionsDisposable.dispose()
        arguments.collectables.invalidate()
        openSend = nil
        for animation in stateValue.with({ $0.pendingTransferAnimations.values }) {
            animation.onFinished = nil
        }
    }

    // Page in the next batch as the list reaches the bottom, so the spinner row at the end is a
    // progress indicator rather than a button. `loadMore` is already idempotent — it no-ops unless the
    // active tab has more to fetch and isn't mid-request — so repeated scroll events are harmless.
    var headerShowsBalance = false
    var displayedHeaderTitle: String? = nil
    updateHeaderImpl = { [weak controller] in
        guard let controller else {
            return
        }
        let balance = headerShowsBalance ? walletHeaderBalanceText(stateValue.with { $0.walletState }) : nil
        let title = balance?.title
        guard title != displayedHeaderTitle else {
            return
        }
        let animated = (displayedHeaderTitle == nil) != (title == nil)
        displayedHeaderTitle = title
        controller.centerModalHeader = balance.map { ModalHeaderData(title: $0.title, subtitle: $0.subtitle) }
        controller.modal?.updateHeader(animated: animated)
    }
    cardScrollCollapse.onCollapsedChanged = { collapsed in
        headerShowsBalance = collapsed
        updateHeaderImpl?()
    }

    controller.didLoad = { controller, _ in
        loadMoreTableView = controller.tableView
        controller.tableView.setScrollHandler { position in
            switch position.direction {
            case .bottom:
                arguments.loadMore()
            default:
                break
            }
        }
        cardScrollCollapse.tableView = controller.tableView
        controller.tableView.addScroll(listener: TableScrollListener(dispatchWhenVisibleRangeUpdated: false, { _ in
            cardScrollCollapse.apply()
            loadMoreIfNeeded?()
        }))
    }

    controller.afterTransaction = { controller in
        loadMoreIfNeeded?()
        if headerShowsBalance {
            updateHeaderImpl?()
        }
        if let id = transferToReveal, stateValue.with({ $0.selectedTab == .transactions }),
           let item = controller.tableView.item(stableId: InputDataEntryId.custom(walletHomeTransactionIdentifier(id))) {
            transferToReveal = nil
            controller.tableView.scroll(to: .top(id: item.stableId, innerId: nil, animated: false, focus: .init(focus: false), inset: -16), toVisible: true)
        }
        revealLatestTransactionsImpl?()
    }

    revealLatestTransactionsImpl = { [weak controller] in
        guard revealsLatestTransactions, let controller, stateValue.with({ $0.selectedTab == .transactions }) else {
            return
        }
        revealsLatestTransactions = false
        let id = stateValue.with { $0.walletState.flatMap { walletVisibleTransactions($0.transactions.items).first?.presentationId } }
        if let id, let item = controller.tableView.item(stableId: InputDataEntryId.custom(walletHomeTransactionIdentifier(id))) {
            controller.tableView.scroll(to: .top(id: item.stableId, innerId: nil, animated: false, focus: .init(focus: false), inset: -16), toVisible: true)
        } else {
            controller.tableView.scroll(to: .up(false))
        }
    }

    controller.didDisappear = { _ in
        arguments.gramTooltip.setVisible(false)
    }

    controller.willAppear = { controller in
        arguments.intro.begin(with: controller.view, isReady: {
            return stateValue.with { state -> Bool in
                guard let walletState = state.walletState, case .wallet = walletState.phase else {
                    return false
                }
                return walletDisplayBalance(walletState) != nil
            }
        })
    }

    var didAppear = false
    controller.didAppear = { controller in
        delay(max(0.35, (arguments.intro.endTime ?? 0) - CACurrentMediaTime()), closure: {
            arguments.gramTooltip.setVisible(true)
        })
        refreshTwoStepAuth()
        if didAppear {
            refreshAdditionalBalances()
        }
        didAppear = true
    }

    let modalController = WalletModalController(controller, size: NSMakeSize(400, 0))

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })

    controller.rightModalHeader = ModalHeaderData(image: theme.icons.chatActionsActive, contextMenu: {
        let keysAndBackupTitle = strings().walletControllerKeysAndBackup
        let passcodeTitle = strings().walletControllerPasscodeAndTouchId
        let howItWorksTitle = strings().walletControllerHowItWorks

        var items: [ContextMenuItem] = []
        if case .wallet = walletContext.stateValue.phase {
            let currencyTitle = strings().walletControllerCurrency
            let selectedCurrency = walletContext.stateValue.fiat.selectedCurrency
            let topCurrencies: [WalletContext.FiatCurrency] = [.usd, .eur, .rub, .cny, .aed]
            var orderedCurrencies = topCurrencies
            if !topCurrencies.contains(selectedCurrency) {
                orderedCurrencies.insert(selectedCurrency, at: 0)
            }
            let otherCurrencies = WalletContext.FiatCurrency.allCases
                .filter { !orderedCurrencies.contains($0) }
                .sorted { walletCurrencyName($0) < walletCurrencyName($1) }
            let currencyMenu = ContextMenu(betterInside: true)
            for (index, currency) in (orderedCurrencies + otherCurrencies).enumerated() {
                if index == orderedCurrencies.count {
                    currencyMenu.addItem(ContextSeparatorItem())
                }
                currencyMenu.addItem(ContextMenuItem("\(walletCurrencyName(currency)) (\(currency.code))", handler: {
                    walletContext.setFiatCurrency(currency)
                }, state: currency == selectedCurrency ? .on : nil))
            }
            let currencyItem = ContextMenuItem("\(currencyTitle): \(selectedCurrency.code)", itemImage: environment.menuImage(.menu_globe))
            currencyItem.submenu = currencyMenu
            items.append(currencyItem)
        }
        items.append(ContextMenuItem(passcodeTitle, handler: {
            environment.openPasscodeSettings()
        }, itemImage: environment.menuImage(.menu_lock)))
        items.append(ContextMenuItem(keysAndBackupTitle, handler: {
            showModal(with: WalletSettingsController(context: context, environment: environment, walletContext: walletContext), for: context.window)
        }, itemImage: environment.menuImage(.menu_cloud)))
        if stateValue.with({ $0.hasConnectedApps }) {
            let connectedAppsTitle = strings().walletControllerConnectedApps
            items.append(ContextMenuItem(connectedAppsTitle, handler: {
                showModal(with: WalletConnectedAppsController(context: context, environment: environment, walletContext: walletContext), for: context.window)
            }, itemImage: environment.menuImage(.menu_apps)))
        }
        items.append(ContextSeparatorItem())
        items.append(ContextMenuItem(howItWorksTitle, handler: {
            showModal(with: WalletInfoController(context: context, environment: environment, walletContext: walletContext, mode: .wallet), for: context.window)
        }, itemImage: environment.menuImage(.menu_show_info)))
        return items
    })

    return modalController
}

@discardableResult
@available(macOS 10.15, *)
private func walletProcessConnectValue(_ value: String, context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext) -> Bool {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else {
        return false
    }
    if WalletContext.isTonConnectUrl(value) {
        walletEnsureSigningAccess(context: context, environment: environment, walletContext: walletContext, window: context.window, next: {
            walletContext.processTonConnectUrl(value)
        })
        return true
    }
    if let address = WalletContext.transferAddress(from: value) {
        let recipient = context.engine.wallet.getUserAddresses(addresses: [address], force: false)
        |> `catch` { _ in Signal<[WalletUserAddress], NoError>.single([]) }
        |> mapToSignal { entries -> Signal<(EnginePeer, WalletUserAddress)?, NoError> in
            guard let entry = entries.first, !entry.address.isEmpty, let userId = entry.userId as PeerId? else {
                return .single(nil)
            }
            return context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: userId))
            |> map { peer in peer.flatMap { ($0, entry) } }
        }
        |> deliverOnMainQueue
        _ = showModalProgress(signal: recipient, for: context.window).start(next: { resolved in
            if let (peer, entry) = resolved {
                showModal(with: WalletSendController(context: context, environment: environment, walletContext: walletContext, peer: peer._asPeer(), address: value, publicKey: entry.publicKey, completed: walletOpenRecipientChat(environment: environment, window: context.window, peerId: peer.id)), for: context.window)
            } else {
                showModal(with: WalletSendController(context: context, environment: environment, walletContext: walletContext, initialAddress: value), for: context.window)
            }
        })
        return true
    }
    return false
}

private let _id_connect_link = InputDataIdentifier("_id_connect_link")

private struct WalletConnectLinkState: Equatable {
    var value: String = ""
    var error: InputDataValueError? = nil
}

private func walletConnectLinkEntries(_ state: WalletConnectLinkState) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1

    entries.append(.input(sectionId: sectionId, index: index, value: .string(state.value), error: state.error, identifier: _id_connect_link, mode: .plain, data: InputDataRowData(viewType: .singleItem), placeholder: nil, inputPlaceholder: strings().walletControllerConnectLinkPlaceholder, filter: { $0 }, limit: 2048))
    index += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().walletControllerConnectLinkInfo), data: .init(color: theme.colors.listGrayText, detectBold: false, viewType: .textBottomItem)))
    index += 1

    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1

    return entries
}

@available(macOS 10.15, *)
public func WalletConnectLinkController(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext) -> InputDataModalController {
    let initialState = WalletConnectLinkState()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((WalletConnectLinkState) -> WalletConnectLinkState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    let signal = statePromise.get()
    |> map { state in
        return InputDataSignalValue(entries: walletConnectLinkEntries(state))
    }

    var close: (() -> Void)? = nil

    let controller = InputDataController(dataSignal: signal, title: strings().walletControllerConnectApp, validateData: { data in
        let value = data[_id_connect_link]?.stringValue ?? ""
        if walletProcessConnectValue(value, context: context, environment: environment, walletContext: walletContext) {
            close?()
            return .none
        }
        updateState { current in
            var current = current
            current.error = InputDataValueError(description: strings().walletControllerConnectLinkInvalid, target: .data)
            return current
        }
        return .fail(.fields([_id_connect_link: .shake]))
    }, updateDatas: { data in
        updateState { current in
            var current = current
            current.value = data[_id_connect_link]?.stringValue ?? ""
            current.error = nil
            return current
        }
        return .fail(.none)
    }, hasDone: true)

    controller.autoInputAction = true

    let interactions = ModalInteractions(acceptTitle: strings().walletControllerConnect, accept: { [weak controller] in
        controller?.validateInputValues()
    }, singleButton: true, customTheme: { walletModalTheme })

    let modalController = WalletModalController(controller, modalInteractions: interactions, size: NSMakeSize(340, 300))
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    close = { [weak modalController] in
        modalController?.close()
    }
    return modalController
}

@available(macOS 10.15, *)
public enum WalletTonConnectSubject: Equatable {
    case connection(WalletContext.TonConnectRequest)
    case operation(WalletContext.TonConnectOperationRequest)

    var id: String {
        switch self {
        case let .connection(request): return request.id
        case let .operation(request): return request.id
        }
    }

    var applicationName: String {
        switch self {
        case let .connection(request): return request.applicationName
        case let .operation(request): return request.applicationName
        }
    }

    var domain: String {
        switch self {
        case let .connection(request): return request.domain
        case let .operation(request): return request.domain
        }
    }

    var icon: WalletTonConnectIcon? {
        switch self {
        case let .connection(request): return request.icon
        case let .operation(request): return request.icon
        }
    }
}

enum WalletTransferPreviewIconKind {
    case transfer
    case incoming
    case outgoing
    case contract
}

@available(macOS 10.15, *)
private func walletTransferPreviewIcon(_ kind: WalletTransferPreviewIconKind) -> CGImage? {
    let size = NSMakeSize(40, 40)
    let colors: [NSColor]
    let symbol: CGImage?
    let symbolInset: CGFloat
    switch kind {
    case .incoming:
        return walletTransactionAvatarImage(direction: .incoming)
    case .outgoing:
        return walletTransactionAvatarImage(direction: .outgoing)
    case .transfer:
        colors = [NSColor(rgb: 0x2a9ef1), NSColor(rgb: 0x72d5fd)]
        symbolInset = 3
        symbol = walletGramIcon(size.width - symbolInset * 2)
    case .contract:
        colors = [NSColor(rgb: 0x9aa0ac), NSColor(rgb: 0xb8bdc7)]
        symbol = NSImage(named: "Wallet_TransactionContract")?.precomposed(.white)
        symbolInset = 7
    }
    return generateImage(size, contextGenerator: { size, ctx in
        ctx.clear(size.bounds)
        ctx.saveGState()
        ctx.addEllipse(in: size.bounds)
        ctx.clip()
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(gradient, start: .zero, end: NSMakePoint(0, size.height), options: [])
        }
        if let symbol {
            let symbolSize = symbol.systemSize.aspectFitted(size.bounds.insetBy(dx: symbolInset, dy: symbolInset).size)
            ctx.draw(symbol, in: size.bounds.focus(symbolSize))
        }
        ctx.restoreGState()
    })
}

@available(macOS 10.15, *)
func walletTransferPreviewRowContent(_ item: WalletTransferPresentation.PreviewItem, fallbackDestination: String? = nil) -> (title: String, subtitle: String?, icon: WalletTransferPreviewIconKind) {
    var title: String
    var subtitle: String?
    let icon: WalletTransferPreviewIconKind
    let shortAddress = item.address.map(walletTransferShortAddress)
    switch item.kind {
    case .transfer:
        switch item.direction {
        case .outgoing:
            title = shortAddress ?? walletTransferShortAddress(fallbackDestination ?? "")
            subtitle = strings().walletControllerWithdrawal
            icon = .outgoing
        case .incoming:
            title = shortAddress ?? strings().walletControllerTransfer
            subtitle = strings().walletControllerDeposit
            icon = .incoming
        case .none:
            title = strings().walletControllerTransfer
            subtitle = shortAddress
            icon = .transfer
        }
    case .callContract:
        title = strings().walletControllerCallContract
        icon = .contract
    case .deployContract:
        title = strings().walletControllerDeployContract
        icon = .contract
    case .excess:
        title = strings().walletControllerExcess
        icon = .incoming
    case .unknown:
        title = strings().walletControllerUnknownOperation
        icon = .contract
    }
    if !item.succeeded {
        subtitle = subtitle.map { strings().walletControllerFailedSuffix($0) } ?? strings().walletControllerFailed
    }
    return (title, subtitle, icon)
}

func walletTonConnectViewType(index: Int, count: Int) -> GeneralViewType {
    if count <= 1 {
        return .singleItem
    }
    if index == 0 {
        return .firstItem
    }
    if index == count - 1 {
        return .lastItem
    }
    return .innerItem
}

@available(macOS 10.15, *)
private struct WalletTonConnectState: Equatable {
    var walletState: WalletContext.State
    var accountName: String = ""
    var iconData: Data?
    var processing = false
}

private let walletTonConnectAppId = InputDataIdentifier("wallet_ton_connect_app")
private let walletTonConnectCardId = InputDataIdentifier("wallet_ton_connect_card")
private let walletTonConnectPermissionId = InputDataIdentifier("wallet_ton_connect_permission")
private let walletTonConnectNoticeId = InputDataIdentifier("wallet_ton_connect_notice")
private let walletTonConnectSignDataId = InputDataIdentifier("wallet_ton_connect_sign_data")
private func walletTonConnectMessageId(_ index: Int) -> InputDataIdentifier {
    return InputDataIdentifier("wallet_ton_connect_message_\(index)")
}
private func walletTonConnectPreviewId(_ id: String) -> InputDataIdentifier {
    return InputDataIdentifier("wallet_ton_connect_preview_\(id)")
}

@available(macOS 10.15, *)
private func walletTonConnectEntries(_ state: WalletTonConnectState, context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, subject: WalletTonConnectSubject, openPreview: @escaping () -> Void) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    if case let .operation(request) = subject {
        let presentation = WalletTransferPresentation(request: request, walletState: state.walletState)
        if let signingContent = presentation.signingContent {
            entries.append(.sectionId(sectionId, type: .customModern(10)))
            sectionId += 1

            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: walletTonConnectSignDataId, equatable: .init(signingContent), comparable: nil, item: { initialSize, stableId in
                return WalletTonConnectSigningRowItem(initialSize, stableId: stableId, title: strings().walletControllerSigningData, content: signingContent)
            }))
            index += 1

            let footer = [signingContent.explanation, presentation.submissionText, presentation.feeText]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            if !footer.isEmpty {
                entries.append(.desc(sectionId: sectionId, index: index, text: .plain(footer), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
                index += 1
            }

            entries.append(.sectionId(sectionId, type: .customModern(16)))
            return entries
        }
    }

    entries.append(.sectionId(sectionId, type: .customModern(4)))
    sectionId += 1

    let appIcon = state.iconData.flatMap { NSImage(data: $0)?.precomposed() } ?? walletFallbackAppIcon(subject.applicationName)
    let applicationTitle: String
    switch subject {
    case .connection:
        applicationTitle = strings().walletControllerConnectTo(subject.applicationName)
    case .operation:
        applicationTitle = strings().walletControllerConfirmAction
    }
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: walletTonConnectAppId, equatable: .init(state.iconData), comparable: nil, item: { initialSize, stableId in
        return WalletInfoParagraphRowItem(
            initialSize,
            stableId: stableId,
            icon: appIcon,
            title: applicationTitle,
            text: subject.domain,
            viewType: .singleItem,
            centered: true,
            titleFont: .bold(.huge),
            textFont: .semibold(.text),
            textColor: walletClassicAccent
        )
    }))
    index += 1

    switch subject {
    case let .connection(request):
        entries.append(.sectionId(sectionId, type: .customModern(9)))
        sectionId += 1

        var permissionTexts: [String] = []
        permissionTexts.append(strings().walletControllerPermissionViewWallet)
        for permission in request.permissions {
            if case let .proof(domain) = permission {
                permissionTexts.append(strings().walletControllerPermissionProof(domain))
            }
        }
        let permission = permissionTexts.joined(separator: "\n\n")
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: walletTonConnectPermissionId, equatable: .init(permission), comparable: nil, item: { initialSize, stableId in
            return WalletBalancedTextRowItem(initialSize, stableId: stableId, text: .initialize(string: permission, color: theme.colors.text, font: .normal(.text)))
        }))
        index += 1

        entries.append(.sectionId(sectionId, type: .customModern(18)))
        sectionId += 1

        var address = ""
        if case let .wallet(info) = state.walletState.phase {
            address = info.address
        }
        let fiatText = walletFiatText(state.walletState)
        let cardValue = "\(state.walletState.balance.currentValue ?? 0):\(fiatText ?? ""):\(state.accountName):\(address)"
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: walletTonConnectCardId, equatable: .init(cardValue), comparable: nil, item: { initialSize, stableId in
            return WalletCardRowItem(
                initialSize,
                stableId: stableId,
                context: context,
                balance: state.walletState.balance.currentValue ?? 0,
                fiatText: fiatText,
                name: state.accountName,
                address: address,
                viewType: .singleItem,
                receiveAction: { morphSource in
                    showModal(with: WalletReceiveController(context: context, environment: environment, walletContext: walletContext, address: address), for: context.window, morphSource: morphSource)
                }
            )
        }))
        index += 1

        entries.append(.sectionId(sectionId, type: .customModern(20)))
        sectionId += 1
        let notice = strings().walletControllerNoFundsWithoutPermission(request.applicationName)
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: walletTonConnectNoticeId, equatable: .init(notice), comparable: nil, item: { initialSize, stableId in
            return WalletBalancedTextRowItem(initialSize, stableId: stableId, text: .initialize(string: notice, color: theme.colors.grayText, font: .normal(.short)))
        }))
        index += 1

    case let .operation(request):
        let presentation = WalletTransferPresentation(request: request, walletState: state.walletState)
        entries.append(.sectionId(sectionId, type: .customModern(15)))
        sectionId += 1

        let amountNanograms = presentation.amountNanograms
        let amount = amountNanograms.flatMap { Int64($0) }
        let amountText = amount == nil ? formatTonConnectNanograms(amountNanograms ?? "") : nil
        let fiatText: String?
        if let amount, let rate = state.walletState.fiat.selectedRate {
            fiatText = formatTonFiatValue(amount, rate: rate.unitsPerGram, currencySymbol: state.walletState.fiat.selectedCurrency.symbol, maxDecimalPositions: amount == 0 ? 0 : 2)
        } else {
            fiatText = nil
        }
        let recipient = presentation.recipient
        let recipientTitle = presentation.recipientTitle
        let cardValue = "\(amount ?? 0):\(amountText ?? ""):\(fiatText ?? ""):\(recipient):\(recipientTitle ?? "")"
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: walletTonConnectCardId, equatable: .init(cardValue), comparable: nil, item: { initialSize, stableId in
            return WalletTransferCardRowItem(initialSize, stableId: stableId, amount: amount ?? 0, amountText: amountText, fiatText: fiatText, recipient: recipient, recipientTitle: recipientTitle, infoAction: openPreview)
        }))
        index += 1

        let feeText = presentation.feeText
        if !feeText.isEmpty {
            entries.append(.sectionId(sectionId, type: .customModern(18)))
            sectionId += 1
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: walletTonConnectNoticeId, equatable: .init(feeText), comparable: nil, item: { initialSize, stableId in
                return WalletBalancedTextRowItem(initialSize, stableId: stableId, text: .initialize(string: feeText, color: theme.colors.grayText, font: .normal(.short)))
            }))
            index += 1
        }
    }

    entries.append(.sectionId(sectionId, type: .customModern(16)))
    return entries
}

@available(macOS 10.15, *)
private func walletTonConnectPreviewEntries(_ state: WalletTonConnectState, request: WalletContext.TonConnectOperationRequest) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    let presentation = WalletTransferPresentation(request: request, walletState: state.walletState)
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    let transfersTitle = request.messages.count == 1 ? strings().walletControllerTransferHeader : strings().walletControllerTransfersHeader
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(transfersTitle), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1
    for (messageIndex, message) in request.messages.enumerated() {
        let destination = WalletContext.transferAddress(from: message.destination) ?? message.destination
        let title = formatTonConnectGrams(message.amountNanograms)
        let subtitle = strings().walletControllerToAddress(walletTransferShortAddress(destination))
        let viewType = walletTonConnectViewType(index: messageIndex, count: request.messages.count)
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: walletTonConnectMessageId(messageIndex), equatable: .init("\(message.id):\(title):\(subtitle):\(viewType)"), comparable: nil, item: { initialSize, stableId in
            return WalletTonConnectPreviewRowItem(initialSize, stableId: stableId, avatar: walletTransferPreviewIcon(.transfer), title: title, subtitle: subtitle, viewType: viewType)
        }))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .customModern(12)))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().walletControllerPreviewHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1
    let previewItems = presentation.previewItems
    for (previewIndex, item) in previewItems.enumerated() {
        let content = walletTransferPreviewRowContent(item, fallbackDestination: request.messages.first?.destination)
        let viewType = walletTonConnectViewType(index: previewIndex, count: previewItems.count)
        let amountText: String?
        let amountColor: NSColor
        if let amount = item.amount, let direction = item.direction {
            amountText = (direction == .incoming ? "+" : "−") + formatTonConnectNanograms(amount)
            amountColor = direction == .incoming ? theme.colors.greenUI : theme.colors.text
        } else {
            amountText = nil
            amountColor = theme.colors.text
        }
        let trimmedComment = item.comment?.trimmingCharacters(in: .whitespacesAndNewlines)
        let comment = trimmedComment?.isEmpty == false ? trimmedComment : nil
        let equatable = "\(item.id):\(content.title):\(content.subtitle ?? ""):\(item.succeeded):\(amountText ?? ""):\(comment ?? ""):\(viewType)"
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: walletTonConnectPreviewId(item.id), equatable: .init(equatable), comparable: nil, item: { initialSize, stableId in
            return WalletTonConnectPreviewRowItem(initialSize, stableId: stableId, avatar: walletTransferPreviewIcon(content.icon), title: content.title, subtitle: content.subtitle, subtitleColor: item.succeeded ? theme.colors.text : theme.colors.redUI, amount: amountText, amountColor: amountColor, comment: comment, viewType: viewType)
        }))
        index += 1
    }

    let footer = [presentation.submissionText, presentation.feeText]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    if !footer.isEmpty {
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(footer), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal))
    return entries
}

@available(macOS 10.15, *)
public func WalletTonConnectController(
    context: any AccountContextProtocol, environment: WalletUIEnvironment,
    walletContext: WalletContext,
    subject: WalletTonConnectSubject,
    showConnectionSuccess: Bool = true,
    requestingBot: Peer? = nil,
    inputDelay: TimeInterval = 0,
    approve: @escaping (@escaping (Result<Void, WalletContext.WalletError>) -> Void) -> Void,
    cancelled: @escaping () -> Void,
    closed: @escaping () -> Void
) -> (InputDataModalController, () -> Void) {
    let disposables = DisposableSet()
    let operationDisposable = MetaDisposable()
    disposables.add(operationDisposable)

    let initialState = WalletTonConnectState(walletState: walletContext.stateValue)
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((WalletTonConnectState) -> WalletTonConnectState) -> Void = { transform in
        statePromise.set(stateValue.modify(transform))
    }

    var openPreview: (() -> Void)?
    let signal = statePromise.get()
    |> deliverOnPrepareQueue
    |> map { state in
        return InputDataSignalValue(entries: walletTonConnectEntries(state, context: context, environment: environment, walletContext: walletContext, subject: subject, openPreview: {
            openPreview?()
        }))
    }
    let isSigning: Bool
    switch subject {
    case .connection: isSigning = false
    case let .operation(request): isSigning = WalletTransferPresentation(request: request, walletState: nil).isSigning
    }
    let title: String
    switch subject {
    case .connection: title = strings().walletControllerConnectTo(subject.applicationName)
    case .operation: title = isSigning ? strings().walletControllerSignData : strings().walletControllerConfirmAction
    }
    let controller = InputDataController(dataSignal: signal, title: title, hasDone: false, getBackgroundColor: {
        isSigning ? theme.colors.listBackground : theme.colors.background
    })
    switch subject {
    case .connection:
        controller.analyticsScreen = AnalyticsScreen.walletTonConnectConnect
    case .operation:
        controller.analyticsScreen = isSigning ? AnalyticsScreen.walletTonConnectSignData : AnalyticsScreen.walletTonConnectOperation
    }

    weak var modalController: InputDataModalController?
    let completion = WalletTonConnectCompletion()
    var closeWithoutReject: (() -> Void)?
    let finish: () -> Void = completion.finish
    let rejectAndClose: (@escaping () -> Void) -> Void = { close in
        completion.rejectAndClose(cancelled: cancelled, close: close)
    }

    var inputGate = WalletTonConnectInputGate()
    inputGate.appear(now: ProcessInfo.processInfo.systemUptime, delay: inputDelay)
    let submit: () -> Void = {
        guard inputGate.allowsInput(now: ProcessInfo.processInfo.systemUptime) else { return }
        let requiresAuthorization: Bool
        switch subject {
        case .connection: requiresAuthorization = false
        case .operation: requiresAuthorization = true
        }
        walletBeginTonConnectApproval(isProcessing: stateValue.with { $0.processing }, requiresAuthorization: requiresAuthorization, setProcessing: { processing in
            updateState { state in
                var state = state
                state.processing = processing
                return state
            }
        }, approve: approve, finish: finish, close: { closeWithoutReject?() }, connectionSucceeded: {
            if showConnectionSuccess, case let .connection(request) = subject {
                Queue.mainQueue().after(0.25) {
                    let title = strings().walletControllerConnectionSuccessful
                    let text = strings().walletControllerConnectedTo(request.applicationName)
                    environment.showModalText(for: context.window, text: text, title: title)
                }
            }
        }, failure: {
            let errorText: String
            switch subject {
            case .connection: errorText = strings().walletControllerConnectFailed
            case .operation: errorText = strings().walletControllerRequestFailed
            }
            environment.alert(for: context.window, info: errorText)
        })
    }

    let acceptTitle: String
    switch subject {
    case .connection: acceptTitle = strings().walletControllerConnect
    case .operation: acceptTitle = isSigning ? strings().walletControllerSign : strings().walletControllerConfirm
    }
    let interactions = ModalInteractions(
        acceptTitle: acceptTitle,
        accept: submit,
        cancelTitle: strings().walletControllerCancel,
        cancel: { modalController?.close() },
        height: 80, customTheme: { walletModalTheme }
    )
    interactions.glassButtons = true
    interactions.cancelButtonStyle = .filled
    let modal = WalletModalController(controller, modalInteractions: interactions, closeHandler: { close in
        rejectAndClose(close)
    }, size: NSMakeSize(400, 0))
    modalController = modal
    closeWithoutReject = { [weak modal] in
        modal?.close()
    }
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modal] in
        modal?.close()
    })
    let headerAppIcon: () -> CGImage? = {
        return walletAppIconImage(data: stateValue.with { $0.iconData }, applicationName: subject.applicationName, size: 36, cornerRadius: 18)
    }
    if isSigning || requestingBot != nil {
        controller.centerModalHeader = ModalHeaderData(title: requestingBot.map { environment.peerTitle($0, compact: false) } ?? title, subtitle: subject.domain)
        controller.rightModalHeader = ModalHeaderData(image: headerAppIcon(), isCloseButton: false)
    } else {
        controller.centerModalHeader = ModalHeaderData(title: nil)
    }
    weak var previewController: InputDataController?
    openPreview = { [weak modal] in
        guard let modal, previewController == nil, case let .operation(request) = subject else {
            return
        }
        let previewSignal = statePromise.get()
        |> deliverOnPrepareQueue
        |> map { state in
            return InputDataSignalValue(entries: walletTonConnectPreviewEntries(state, request: request))
        }
        let preview = InputDataController(dataSignal: previewSignal, title: strings().walletControllerConfirmAction, hasDone: false)
        preview.analyticsScreen = .walletTonConnectConfirmation
        preview.leftModalHeader = ModalHeaderData(image: theme.icons.chatNavigationBack, handler: { [weak modal] in
            modal?.pop(animated: true)
        }, isCloseButton: false)
        preview.centerModalHeader = ModalHeaderData(title: strings().walletControllerConfirmAction, subtitle: subject.domain)
        preview.rightModalHeader = ModalHeaderData(image: headerAppIcon(), isCloseButton: false)
        preview.validateData = { _ in
            submit()
            return .none
        }
        preview._frameRect = modal.frame.size.bounds
        previewController = preview
        modal.push(preview, animated: true)
    }
    controller.afterTransaction = { [weak interactions] _ in
        interactions?.updateEnables(inputGate.allowsInput(now: ProcessInfo.processInfo.systemUptime) && !stateValue.with({ $0.processing }))
    }
    controller.didAppear = { [weak interactions] _ in
        inputGate.appear(now: ProcessInfo.processInfo.systemUptime, delay: inputDelay)
        interactions?.updateEnables(inputDelay <= 0 && !stateValue.with { $0.processing })
        Queue.mainQueue().after(inputDelay) { [weak interactions] in
            interactions?.updateEnables(!stateValue.with { $0.processing })
        }
    }
    controller.validateData = { _ in
        submit()
        return .none
    }
    let inputGateOwner = NSObject()
    if inputDelay > 0 {
        for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp] {
            context.window.set(mouseHandler: { _ in
                inputGate.allowsInput(now: ProcessInfo.processInfo.systemUptime) ? .invokeNext : .invoked
            }, with: inputGateOwner, for: type, priority: .supreme)
        }
    }
    controller.onDeinit = {
        context.window.removeAllHandlers(for: inputGateOwner)
        disposables.dispose()
        closed()
    }

    disposables.add((walletContext.state
    |> deliverOnMainQueue).start(next: { state in
        updateState { current in
            var current = current
            current.walletState = state
            return current
        }
    }))
    disposables.add(walletUIPeerView(peerId: context.peerId, postbox: context.account.postbox).start(next: { peer in
        updateState { current in
            var current = current
            current.accountName = peer.map { environment.peerTitle($0, compact: false).uppercased() } ?? ""
            return current
        }
    }))

    let iconSignal: Signal<Data?, NoError>
    if let requestingBot {
        iconSignal = environment.ownerAvatar(requestingBot, size: NSMakeSize(88, 88), font: .medium(40)) |> map { image in
            guard let image else { return nil }
            return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        }
    } else {
        iconSignal = walletFetchAppIcon(context: context, icon: subject.icon)
    }
    disposables.add((iconSignal |> deliverOnMainQueue).start(next: { [weak controller] data in
        guard let data else {
            return
        }
        updateState { current in
            var current = current
            current.iconData = data
            return current
        }
        if isSigning || requestingBot != nil {
            controller?.rightModalHeader = ModalHeaderData(image: headerAppIcon(), isCloseButton: false)
        }
        previewController?.rightModalHeader = ModalHeaderData(image: headerAppIcon(), isCloseButton: false)
        modalController?.modal?.updateHeader(animated: false)
    }))

    let dismiss: () -> Void = { [weak modal] in
        completion.dismiss { modal?.close() }
    }
    return (modal, dismiss)
}

@available(macOS 10.15, *)
private func walletShowCardSaveError(_ error: WalletCardUpdateError, context: any AccountContextProtocol, environment: WalletUIEnvironment) {
    let title = strings().walletControllerStickerSaveErrorTitle
    let text: String?
    switch error {
    case .limitExceeded, .floodWait:
        text = nil
    case .backgroundNotAllowed:
        text = strings().walletControllerStickerBackgroundNotAllowedError
    case .savedInProfile:
        text = strings().walletControllerStickerProfileError
    case .invalidSticker, .notOwned, .duplicate, .invalidAddress, .invalidNft:
        text = strings().walletControllerStickerInvalidError
    case .unavailable, .generic:
        text = strings().unknownError
    }
    if let text {
        environment.showModalText(for: context.window, text: text, title: title)
    } else {
        environment.showModalText(for: context.window, text: title)
    }
}
