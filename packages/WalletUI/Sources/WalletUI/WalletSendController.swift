import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows
import InputDataUI
import Localization
import Cocoa
import TGUIKit
import SwiftSignalKit
import Postbox
import TelegramCore
import WalletContext
import PasscodeCore
import AppAnalytics

struct WalletParsedRecipient {
    let address: String
    let amount: Int64?
    let comment: String?
}

func walletParseRecipient(_ value: String) -> WalletParsedRecipient {
    var address = value.trimmingCharacters(in: .whitespacesAndNewlines)
    var amount: Int64? = nil
    var comment: String? = nil
    if let components = URLComponents(string: address), components.scheme?.lowercased() == "ton" {
        if components.host?.lowercased() == "transfer" {
            address = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else if let host = components.host, !host.isEmpty {
            address = host
        }
        if let amountValue = components.queryItems?.first(where: { $0.name == "amount" })?.value, let parsedAmount = Int64(amountValue), parsedAmount > 0 {
            amount = parsedAmount
        }
        if let text = components.queryItems?.first(where: { $0.name == "text" })?.value, !text.isEmpty {
            comment = text
        }
    }
    return WalletParsedRecipient(address: address, amount: amount, comment: comment)
}

private final class Arguments {
    let context: any AccountContextProtocol
    let environment: WalletUIEnvironment
    let editComment: () -> Void
    let updateAmount: (Int64) -> Void
    let toggleMode: () -> Void
    let submit: () -> Void
    let showLinkedPeerInfo: (EnginePeer?, String) -> Void
    let copyAddress: (String) -> Void
    let openPeer: (EnginePeer) -> Void
    let clock = WalletSendMotionClock()
    let opening = WalletSendOpening()

    let deposit: ((() -> NSView?)?) -> Void
    init(context: any AccountContextProtocol, environment: WalletUIEnvironment, deposit: @escaping ((() -> NSView?)?) -> Void, editComment: @escaping () -> Void, updateAmount: @escaping (Int64) -> Void, toggleMode: @escaping () -> Void, submit: @escaping () -> Void, showLinkedPeerInfo: @escaping (EnginePeer?, String) -> Void, copyAddress: @escaping (String) -> Void, openPeer: @escaping (EnginePeer) -> Void) {
        self.context = context
        self.environment = environment
        self.deposit = deposit
        self.editComment = editComment
        self.updateAmount = updateAmount
        self.toggleMode = toggleMode
        self.submit = submit
        self.showLinkedPeerInfo = showLinkedPeerInfo
        self.copyAddress = copyAddress
        self.openPeer = openPeer
    }
}

enum WalletSendAmountSource: Equatable {
    case manual
    case transferLink
}

@available(macOS 10.15, *)
struct WalletSendState: Equatable {
    var amount: Int64 = 0
    var comment: String? = nil
    var isCommentPublic: Bool = false
    var isSending: Bool = false
    var mode: WalletSendInputMode = .gram
    var revision: Int = 0
    var balance: Int64? = nil
    var isLoading: Bool = true
    var isResolvingSigningAccess: Bool = false
    var gaslessInfo: WalletGaslessInfo? = nil
    var gaslessMinAmount: Int64 = 0
    var walletPhase: WalletContext.Phase? = nil
    var walletAddress: String? = nil
    var amountSource: WalletSendAmountSource = .manual
    var currency: WalletContext.FiatCurrency = .usd
    var rate: Double? = nil
    var selectedPeer: EnginePeer? = nil
    var isPeerMode: Bool {
        return selectedPeer != nil
    }
    var resolved: WalletContext.ResolvedTransferRecipient? = nil
    var recipientPublicKey: Data? = nil
    var isResolving: Bool = false
    var feeEstimate: WalletSendFeeEstimate? = nil
    var isEstimatingFee: Bool = false
    var linkedPeer: WalletSendLinkedPeer? = nil
}

struct WalletSendLinkedPeer: Equatable {
    let address: String
    let peer: EnginePeer
}

struct WalletSendRecipientPresentation: Equatable {
    let address: String
    let peer: EnginePeer?
    let isLoading: Bool
    let canOpenPeer: Bool
}

@available(macOS 10.15, *)
func walletSendRecipientAddress(_ value: String) -> String? {
    return WalletContext.transferAddress(from: value, preserveBounce: true)
}

@available(macOS 10.15, *)
func walletSendPeerPublicKey(address: String, peerAddress: String, publicKey: Data?) -> Data? {
    guard let account = WalletContext.transferAddress(from: address), account == WalletContext.transferAddress(from: peerAddress) else {
        return nil
    }
    return publicKey
}

@available(macOS 10.15, *)
func walletSendLinkedPeer(_ state: WalletSendState) -> EnginePeer? {
    guard !state.isPeerMode, !state.isResolving, let resolved = state.resolved, let linkedPeer = state.linkedPeer, linkedPeer.address == resolved.address else {
        return nil
    }
    return linkedPeer.peer
}

@available(macOS 10.15, *)
func walletSendCanOpenRecipientChat(_ state: WalletSendState) -> Bool {
    return !state.isSending && !state.isResolvingSigningAccess
}

@available(macOS 10.15, *)
func walletSendIsSelfTransfer(_ state: WalletSendState) -> Bool {
    guard let resolved = state.resolved else {
        return false
    }
    return WalletContext.isSelfTransfer(recipient: resolved.address, walletAddress: state.walletAddress)
}

@available(macOS 10.15, *)
func walletSendIsInsufficient(_ state: WalletSendState) -> Bool {
    if state.amount > 0, !state.isLoading, let balance = state.balance, state.amount > balance {
        return true
    }
    return false
}

@available(macOS 10.15, *)
func walletSendFeesAreCovered(_ state: WalletSendState, amount: Int64) -> Bool {
    guard !walletSendIsSelfTransfer(state) else {
        return false
    }
    return WalletContext.isGaslessEligible(amount: amount, gaslessInfo: state.gaslessInfo, minimumAmount: state.gaslessMinAmount)
}

@available(macOS 10.15, *)
func walletShouldSendAll(_ state: WalletSendState) -> Bool {
    guard state.amountSource == .manual, state.amount > 0, let balance = state.balance else {
        return false
    }
    return state.amount == balance && !walletSendFeesAreCovered(state, amount: state.amount)
}

@available(macOS 10.15, *)
struct WalletSendFeeRequest: Equatable {
    let walletAddress: String
    let walletPublicKey: String
    let address: String
    let comment: WalletContext.TransferFeeComment
}

@available(macOS 10.15, *)
struct WalletSendFeeEstimate: Equatable {
    let request: WalletSendFeeRequest
    let fee: Int64?
    var error: WalletContext.WalletError? = nil
}

@available(macOS 10.15, *)
enum WalletSendFeeReadiness: Equatable {
    case estimating
    case ready(Int64)
    case failed(WalletContext.WalletError)
    case changed
}

@available(macOS 10.15, *)
func walletSendFeeRequest(_ state: WalletSendState) -> WalletSendFeeRequest? {
    guard case let .wallet(info) = state.walletPhase, let resolved = state.resolved, !resolved.address.isEmpty else {
        return nil
    }
    let comment: WalletContext.TransferFeeComment
    if let text = walletTransactionComment(state.comment) {
        comment = state.isPeerMode && !state.isCommentPublic ? .encrypted : .plainText(byteCount: text.utf8.count)
    } else {
        comment = .none
    }
    return WalletSendFeeRequest(walletAddress: info.address, walletPublicKey: info.publicKey, address: resolved.address, comment: comment)
}

@available(macOS 10.15, *)
func walletSendShowsFee(_ state: WalletSendState) -> Bool {
    guard !state.isSending, state.amount > 0, state.resolved != nil else {
        return false
    }
    guard let balance = state.balance, state.amount <= balance else {
        return false
    }
    if !walletSendIsSelfTransfer(state) {
        guard let gaslessInfo = state.gaslessInfo else {
            return false
        }
        if !walletShouldSendAll(state), WalletContext.isGaslessEligible(amount: state.amount, gaslessInfo: gaslessInfo, minimumAmount: state.gaslessMinAmount) {
            return false
        }
    }
    return true
}

@available(macOS 10.15, *)
func walletSendFeeReadiness(_ state: WalletSendState, request: WalletSendFeeRequest) -> WalletSendFeeReadiness {
    guard walletSendFeeRequest(state) == request else {
        return .changed
    }
    guard let estimate = state.feeEstimate, estimate.request == request else {
        return .estimating
    }
    if let fee = estimate.fee {
        return .ready(fee)
    }
    return .failed(estimate.error ?? .previewFailed)
}

@available(macOS 10.15, *)
func walletSendInitialFee(_ state: WalletSendState) -> Int64? {
    guard let request = walletSendFeeRequest(state), let estimate = state.feeEstimate, estimate.request == request else {
        return nil
    }
    return estimate.fee
}

enum WalletSendFeeDisplay: Equatable {
    case loading
    case value(Int64)
    case unavailable
}

@available(macOS 10.15, *)
func walletSendRecipientIsLoading(_ state: WalletSendState) -> Bool {
    return state.isPeerMode && state.resolved == nil && state.isResolving
}

@available(macOS 10.15, *)
func walletSendFeeDisplay(_ state: WalletSendState) -> WalletSendFeeDisplay? {
    if state.resolved == nil {
        guard state.isPeerMode, state.amount > 0, let gaslessInfo = state.gaslessInfo else {
            return nil
        }
        if !walletShouldSendAll(state), WalletContext.isGaslessEligible(amount: state.amount, gaslessInfo: gaslessInfo, minimumAmount: state.gaslessMinAmount) {
            return nil
        }
        return state.isResolving && state.isLoading ? .loading : .unavailable
    }
    guard walletSendShowsFee(state) else {
        return nil
    }
    guard let request = walletSendFeeRequest(state) else {
        return state.isLoading ? .loading : .unavailable
    }
    guard let estimate = state.feeEstimate else {
        return .loading
    }
    if let fee = estimate.fee {
        return .value(fee)
    }
    return estimate.request == request ? .unavailable : .loading
}

@available(macOS 10.15, *)
func walletCanSend(_ state: WalletSendState) -> Bool {
    guard state.amount > 0, !state.isResolvingSigningAccess, !state.isSending else {
        return false
    }
    guard !state.isLoading, let balance = state.balance, state.amount <= balance else {
        return false
    }
    return state.resolved != nil
}

private let _id_amount = InputDataIdentifier("_id_amount")
private let _id_rate = InputDataIdentifier("_id_rate")
private let _id_insufficient = InputDataIdentifier("_id_insufficient")
private let _id_balance = InputDataIdentifier("_id_balance")
private let _id_deposit = InputDataIdentifier("_id_deposit")
private let _id_fees = InputDataIdentifier("_id_fees")
private let _id_comment_bubble = InputDataIdentifier("_id_comment_bubble")
private let _id_comment_text = InputDataIdentifier("_id_comment_text")
private let _id_comment_public = InputDataIdentifier("_id_comment_public")
private let _id_recipient = InputDataIdentifier("_id_recipient")
private let _id_linked_recipient = InputDataIdentifier("_id_linked_recipient")

private final class WalletSendFundsStatusRowItem: GeneralRowItem {
    let warningLayout: TextViewLayout
    let showsDeposit: Bool
    let morphAction: ((() -> NSView?)?) -> Void

    init(_ initialSize: NSSize, stableId: AnyHashable, isInsufficient: Bool, showsDeposit: Bool, height: CGFloat = 22, action: @escaping ((() -> NSView?)?) -> Void) {
        let warningText = isInsufficient ? strings().walletSendControllerInsufficientFunds : ""
        self.warningLayout = TextViewLayout(.initialize(string: warningText, color: theme.colors.redUI, font: .normal(.text)), maximumNumberOfLines: 1)
        self.warningLayout.measure(width: .greatestFiniteMagnitude)
        self.showsDeposit = showsDeposit
        self.morphAction = action
        super.init(initialSize, height: height, stableId: stableId, action: { action(nil) })
    }

    override func viewClass() -> AnyClass {
        return WalletSendFundsStatusRowView.self
    }

    override var accessibilityLabel: String? {
        let warning = warningLayout.attributedString.string
        if !warning.isEmpty {
            return warning
        }
        return showsDeposit ? strings().walletSendControllerDepositFundsLink : nil
    }

    override var accessibilityIsSpacer: Bool {
        return warningLayout.attributedString.string.isEmpty && !showsDeposit
    }
}

private final class WalletSendFundsStatusRowView: GeneralRowView {
    private let warningView = TextView()
    private let button = TextButton()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(warningView)
        warningView.userInteractionEnabled = false
        warningView.isSelectable = false
        warningView.isAccessibilityDecorative = true
        addSubview(button)
        button.autoSizeToFit = false
        button.scaleOnClick = true
        button.set(handler: { [weak self] _ in
            (self?.item as? WalletSendFundsStatusRowItem)?.morphAction({ [weak self] in self?.button })
        }, for: .Click)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? WalletSendFundsStatusRowItem else { return }
        warningView.update(item.warningLayout)
        button.set(text: strings().walletSendControllerDepositFundsLink, for: .Normal)
        button.set(font: .normal(.text), for: .Normal)
        button.set(color: walletClassicAccent, for: .Normal)
        button.set(background: .clear, for: .Normal)
        button.isHidden = !item.showsDeposit
        button.isEnabled = item.showsDeposit
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? WalletSendFundsStatusRowItem else { return }
        let warningWidth = item.warningLayout.layoutSize.width
        let buttonWidth = item.showsDeposit ? button.textSize.width : 0
        let spacing: CGFloat = warningWidth > 0 && item.showsDeposit ? 4 : 0
        let x = floorToScreenPixels(backingScaleFactor, (frame.width - warningWidth - spacing - buttonWidth) / 2)
        warningView.setFrameOrigin(NSMakePoint(x, floorToScreenPixels(backingScaleFactor, (frame.height - warningView.frame.height) / 2)))
        button.frame = NSMakeRect(x + warningWidth + spacing, 0, buttonWidth, frame.height)
    }
}

private let walletSendFeePlaceholderSize = NSMakeSize(92, 14)
private let walletSendFeeSpacing: CGFloat = 3

private func walletSendFeeTextLayout(_ text: String) -> TextViewLayout {
    let layout = TextViewLayout(.initialize(string: text, color: theme.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 1)
    layout.measure(width: .greatestFiniteMagnitude)
    return layout
}

private final class WalletSendFeesRowItem: GeneralRowItem {
    fileprivate let display: WalletSendFeeDisplay?
    fileprivate let titleLayout = walletSendFeeTextLayout(strings().walletSendControllerNetworkFee)
    fileprivate let valueLayout: TextViewLayout?
    fileprivate let valueWidth: CGFloat

    init(_ initialSize: NSSize, stableId: AnyHashable, display: WalletSendFeeDisplay?) {
        self.display = display
        switch display {
        case let .value(fee):
            let layout = walletSendFeeTextLayout(formatGramsText(fee, maxDecimalPositions: 5))
            self.valueLayout = layout
            self.valueWidth = layout.layoutSize.width
        case .unavailable:
            self.valueLayout = nil
            self.valueWidth = walletSendFeeTextLayout("0.00000 Grams").layoutSize.width
        case .loading, .none:
            self.valueLayout = nil
            self.valueWidth = walletSendFeePlaceholderSize.width
        }
        super.init(initialSize, height: display == nil ? 1 : 24, stableId: stableId)
    }

    override func viewClass() -> AnyClass {
        return WalletSendFeesRowView.self
    }

    override var accessibilityLabel: String? {
        return display == nil ? nil : titleLayout.attributedString.string
    }

    override var accessibilityValue: String? {
        if let valueLayout {
            return valueLayout.attributedString.string
        }
        return display == .loading ? strings().voiceOverCommonLoading : nil
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return .staticText
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }

    override var accessibilityIsSpacer: Bool {
        return display == nil
    }
}

private final class WalletSendFeesRowView: GeneralRowView {
    private let titleView = TextView()
    private let valueView = TextView()
    private var placeholderView: ShimmerEffectView?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for view in [titleView, valueView] {
            view.userInteractionEnabled = false
            view.isSelectable = false
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? WalletSendFeesRowItem else {
            return
        }
        titleView.update(item.titleLayout)
        titleView.isHidden = item.display == nil
        valueView.update(item.valueLayout)
        valueView.isHidden = item.valueLayout == nil
        if item.display == .loading {
            if placeholderView == nil {
                let view = ShimmerEffectView()
                view.isEventLess = true
                addSubview(view)
                placeholderView = view
            }
        } else if let placeholderView {
            placeholderView.removeFromSuperview()
            self.placeholderView = nil
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? WalletSendFeesRowItem else {
            return
        }
        let width = item.titleLayout.layoutSize.width + walletSendFeeSpacing + item.valueWidth
        let x = floorToScreenPixels(backingScaleFactor, (frame.width - width) / 2)
        titleView.setFrameOrigin(NSMakePoint(x, floorToScreenPixels(backingScaleFactor, (frame.height - titleView.frame.height) / 2)))
        let valueX = titleView.frame.maxX + walletSendFeeSpacing
        valueView.setFrameOrigin(NSMakePoint(valueX, floorToScreenPixels(backingScaleFactor, (frame.height - valueView.frame.height) / 2)))
        if let placeholderView {
            let size = walletSendFeePlaceholderSize
            placeholderView.frame = NSMakeRect(valueX, floorToScreenPixels(backingScaleFactor, (frame.height - size.height) / 2), size.width, size.height)
            placeholderView.updateAbsoluteRect(placeholderView.frame, within: frame.size)
            placeholderView.update(backgroundColor: theme.colors.background, foregroundColor: theme.colors.grayBackground, shimmeringColor: theme.colors.background.withAlphaComponent(0.6), shapes: [.roundedRect(rect: NSMakeRect(0, 0, size.width, size.height), cornerRadius: size.height / 2)], horizontal: true, size: size)
        }
    }
}

private final class WalletSendCommentRowItem: GeneralRowItem {
    fileprivate let textLayout: TextViewLayout

    init(_ initialSize: NSSize, stableId: AnyHashable, comment: String, action: @escaping () -> Void) {
        self.textLayout = TextViewLayout(.initialize(string: comment, color: theme.colors.grayText, font: .medium(.title)), maximumNumberOfLines: 1)
        super.init(initialSize, stableId: stableId, action: action)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        let result = super.makeSize(width, oldWidth: oldWidth)
        textLayout.measure(width: max(1, width - 120))
        return result
    }

    fileprivate var bubbleSize: NSSize {
        return NSMakeSize(textLayout.layoutSize.width + 34, max(34, textLayout.layoutSize.height + 14))
    }

    override var height: CGFloat {
        return bubbleSize.height
    }

    override func viewClass() -> AnyClass {
        return WalletSendCommentRowView.self
    }

    override var accessibilityLabel: String? {
        let text = textLayout.attributedString.string
        return text.isEmpty ? nil : text
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
}

private final class WalletSendCommentRowView: GeneralRowView {
    private let control = Control()
    private let bubbleView = WalletSendCommentBackgroundView(frame: .zero)
    private let textView = TextView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        textView.isEventLess = true
        control.addSubview(bubbleView)
        control.addSubview(textView)
        control.stretchReferenceView = control
        control.set(handler: { [weak self] _ in
            (self?.item as? WalletSendCommentRowItem)?.action()
        }, for: .Click)
        addSubview(control)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? WalletSendCommentRowItem else {
            return
        }
        textView.update(item.textLayout)
        control.setAccessibilityLabel(item.textLayout.attributedString.string)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? WalletSendCommentRowItem else {
            return
        }
        let size = item.bubbleSize
        control.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - size.width) / 2 + 3), 0, size.width, size.height)
        bubbleView.frame = control.bounds
        bubbleView.update(size: size)
        textView.setFrameOrigin(NSMakePoint(14, floorToScreenPixels(backingScaleFactor, (size.height - textView.frame.height) / 2)))
    }
}

private func walletSendStatusRow(_ initialSize: NSSize, stableId: AnyHashable, text: String, color: NSColor, height: CGFloat) -> GeneralTextRowItem {
    let attributedText = NSAttributedString.initialize(string: text, color: color, font: .normal(.text))
    let layout = TextViewLayout(attributedText, maximumNumberOfLines: 1)
    layout.measure(width: max(1, initialSize.width - 68))
    let verticalInset = max(0, (height - layout.layoutSize.height) / 2)
    return GeneralTextRowItem(initialSize, stableId: stableId, text: attributedText, alignment: .center, inset: NSEdgeInsets(left: 20, right: 20), centerViewAlignment: true, viewType: .textTopItem.withUpdatedInsets(NSEdgeInsets(top: verticalInset, left: 14, bottom: verticalInset, right: 0)))
}

@available(macOS 10.15, *)
private func entries(_ state: WalletSendState, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .customModern(14)))
    sectionId += 1

    let recipientPeer = state.isPeerMode ? state.selectedPeer : walletSendLinkedPeer(state)
    let recipientAddress = state.resolved?.address ?? ""
    if state.isPeerMode, state.selectedPeer == nil, state.isResolving {
        let resolvingText = strings().walletSendControllerResolving
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_recipient, equatable: .init(resolvingText), comparable: nil, item: { initialSize, stableId in
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: resolvingText, type: .loading, viewType: .singleItem)
        }))
        index += 1
    } else if recipientPeer != nil || !recipientAddress.isEmpty {
        var openPeer: (() -> Void)? = nil
        if let recipientPeer, walletSendCanOpenRecipientChat(state) {
            openPeer = {
                arguments.openPeer(recipientPeer)
            }
        }
        let presentation = WalletSendRecipientPresentation(address: recipientAddress, peer: recipientPeer, isLoading: walletSendRecipientIsLoading(state), canOpenPeer: openPeer != nil)
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_linked_recipient, equatable: .init(presentation), comparable: nil, item: { initialSize, stableId in
            return WalletLinkedRecipientRowItem(initialSize, stableId: stableId, environment: arguments.environment, peer: recipientPeer, address: recipientAddress.isEmpty ? nil : recipientAddress, isLoading: presentation.isLoading, action: {
                arguments.showLinkedPeerInfo(recipientPeer, recipientAddress)
            }, copyAddress: {
                arguments.copyAddress(recipientAddress)
            }, openPeer: openPeer, openingTime: {
                arguments.opening.recipientTime
            })
        }))
        index += 1
    }

    sectionId = 10
    index = 100
    if state.resolved != nil || state.isPeerMode {
        entries.append(.sectionId(sectionId, type: .customModern(36)))
        sectionId += 1

        @available(macOS 10.15, *)
        struct AmountTuple: Equatable {
            let amount: Int64
            let mode: WalletSendInputMode
            let rate: Double?
            let currency: WalletContext.FiatCurrency
            let revision: Int
        }
        let amountTuple = AmountTuple(amount: state.amount, mode: state.mode, rate: state.rate, currency: state.currency, revision: state.revision)
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_amount, equatable: .init(amountTuple), comparable: nil, item: { initialSize, stableId in
            return WalletAmountRowItem(initialSize, stableId: stableId, amount: amountTuple.amount, mode: amountTuple.mode, rate: amountTuple.rate, currency: amountTuple.currency, revision: amountTuple.revision, clock: arguments.clock, opening: arguments.opening, viewType: .singleItem, updated: arguments.updateAmount, onReturn: arguments.submit)
        }))
        index += 1

        let ratePill: WalletSendRatePill?
        if state.amount > 0, let rate = state.rate {
            switch state.mode {
            case .gram:
                ratePill = WalletSendRatePill(text: "~" + formatTonFiatValue(state.amount, rate: rate, currencySymbol: "") + " " + state.currency.code, mode: .gram)
            case .fiat:
                ratePill = WalletSendRatePill(text: formatTonAmountText(state.amount, maxDecimalPositions: 2), mode: .fiat)
            }
        } else {
            ratePill = nil
        }
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_rate, equatable: .init(ratePill), comparable: nil, item: { initialSize, stableId in
            return WalletSendRatePillRowItem(initialSize, stableId: stableId, pill: ratePill, clock: arguments.clock, toggle: arguments.toggleMode)
        }))
        index += 1

        let isInsufficient = walletSendIsInsufficient(state)
        let showsBalance = state.balance != 0 && (state.amount > 0 || state.balance.map { $0 > 0 } == true)
        let showsInlineDeposit = isInsufficient && showsBalance
        let comment = state.isPeerMode ? walletTransactionComment(state.comment) : nil
        if comment == nil || isInsufficient {
            entries.append(.sectionId(sectionId, type: .customModern(10)))
            sectionId += 1
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_insufficient, equatable: .init([isInsufficient, showsInlineDeposit]), comparable: nil, item: { initialSize, stableId in
                return WalletSendFundsStatusRowItem(initialSize, stableId: stableId, isInsufficient: isInsufficient, showsDeposit: showsInlineDeposit, action: arguments.deposit)
            }))
            index += 1
        }

        if let comment {
            entries.append(.sectionId(sectionId, type: .customModern(isInsufficient ? 8 : 15)))
            sectionId += 1
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_comment_bubble, equatable: .init(comment), comparable: nil, item: { initialSize, stableId in
                return WalletSendCommentRowItem(initialSize, stableId: stableId, comment: comment, action: arguments.editComment)
            }))
            index += 1
            entries.append(.sectionId(sectionId, type: .customModern(12)))
            sectionId += 1
        }

        if showsBalance {
            let balanceText = strings().walletSendControllerBalance(state.balance.map { walletGramsUnitText(formatTonAmountText($0, maxDecimalPositions: 2)) } ?? "–")
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_balance, equatable: .init(balanceText), comparable: nil, item: { initialSize, stableId in
                return walletSendStatusRow(initialSize, stableId: stableId, text: balanceText, color: theme.colors.grayText, height: 24)
            }))
        } else {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_deposit, equatable: nil, comparable: nil, item: { initialSize, stableId in
                return WalletSendFundsStatusRowItem(initialSize, stableId: stableId, isInsufficient: false, showsDeposit: true, height: 24, action: arguments.deposit)
            }))
        }
        index += 1

        let feeDisplay = walletSendFeeDisplay(state)
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_fees, equatable: .init(feeDisplay), comparable: nil, item: { initialSize, stableId in
            return WalletSendFeesRowItem(initialSize, stableId: stableId, display: feeDisplay)
        }))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .customModern(18)))
    sectionId += 1

    return entries
}

@available(macOS 10.15, *)
public func WalletSendController(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, initialAddress: String? = nil, initialAmount: Int64? = nil, transferAnimation: WalletSendTransferAnimation? = nil) -> InputDataModalController {
    if let initialAddress, WalletContext.transferAddress(from: walletParseRecipient(initialAddress).address) != nil {
        return makeWalletSendModal(context: context, environment: environment, walletContext: walletContext, initialAddress: initialAddress, peer: nil, initialAmount: initialAmount, transferAnimation: transferAnimation)
    }
    return makeWalletRecipientController(context: context, environment: environment, walletContext: walletContext, initialQuery: initialAddress, initialAmount: initialAmount, transferAnimation: transferAnimation)
}

@available(macOS 10.15, *)
public func WalletSendController(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, peer: Peer, initialAmount: Int64? = nil, transferAnimation: WalletSendTransferAnimation? = nil, transferAnimationWillStart: ((String) -> Void)? = nil, completed: (() -> Void)? = nil) -> InputDataModalController {
    return makeWalletSendModal(context: context, environment: environment, walletContext: walletContext, initialAddress: nil, peer: peer, initialAmount: initialAmount, transferAnimation: transferAnimation, transferAnimationWillStart: transferAnimationWillStart, completed: completed)
}

@available(macOS 10.15, *)
public func WalletSendController(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, peer: Peer, address: String, publicKey: Data? = nil, initialAmount: Int64? = nil, transferAnimation: WalletSendTransferAnimation? = nil, completed: (() -> Void)? = nil) -> InputDataModalController {
    return makeWalletSendModal(context: context, environment: environment, walletContext: walletContext, initialAddress: address, initialRecipientPublicKey: publicKey, peer: peer, initialAmount: initialAmount, transferAnimation: transferAnimation, completed: completed)
}

@available(macOS 10.15, *)
func walletOpenRecipientChat(environment: WalletUIEnvironment, window: Window, peerId: PeerId) -> () -> Void {
    return {
        closeAllModals(window: window)
        environment.openChat(peerId)
    }
}

@available(macOS 10.15, *)
struct WalletSendStep {
    let controller: InputDataController
    let acceptTitle: () -> String
    let submit: () -> Void
    let updateButton: () -> Void
    let requestDismiss: (@escaping () -> Void) -> Void
}

@available(macOS 10.15, *)
private func makeWalletSendModal(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, initialAddress: String?, initialRecipientPublicKey: Data? = nil, peer: Peer?, initialAmount: Int64? = nil, transferAnimation: WalletSendTransferAnimation? = nil, transferAnimationWillStart: ((String) -> Void)? = nil, completed: (() -> Void)? = nil) -> InputDataModalController {
    var getModal: (() -> InputDataModalController?)?
    let step = makeWalletSendController(context: context, environment: environment, walletContext: walletContext, initialAddress: initialAddress, initialRecipientPublicKey: initialRecipientPublicKey, peer: peer, initialAmount: initialAmount, transferAnimation: transferAnimation, transferAnimationWillStart: transferAnimationWillStart, completed: completed, getModal: {
        return getModal?()
    }, onBack: nil)
    let modalInteractions = ModalInteractions(acceptTitle: step.acceptTitle(), accept: {
        step.submit()
    }, singleButton: true, customTheme: { walletModalTheme })
    let modalController = WalletModalController(step.controller, modalInteractions: modalInteractions, closeHandler: { close in
        step.requestDismiss(close)
    }, size: NSMakeSize(360, 0))
    getModal = { [weak modalController] in
        return modalController
    }
    return modalController
}

public struct WalletPeerSendTarget: Equatable {
    public let address: String
    public let publicKey: Data?

    public init(address: String, publicKey: Data?) {
        self.address = address
        self.publicKey = publicKey
    }
}

@available(macOS 10.15, *)
public func walletPeerSendAddress(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, peerId: PeerId) -> Signal<WalletPeerSendTarget?, NoError> {
    return context.engine.wallet.getUserAddresses(userIds: [peerId], force: true)
    |> map { addresses -> WalletPeerSendTarget? in
        guard let entry = addresses.first(where: { $0.userId == peerId }) else {
            return nil
        }
        let address = entry.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else {
            return nil
        }
        return WalletPeerSendTarget(address: address, publicKey: entry.publicKey.isEmpty ? nil : entry.publicKey)
    }
    |> `catch` { _ in Signal<WalletPeerSendTarget?, NoError>.single(nil) }
}

@available(macOS 10.15, *)
public func showWalletSendMoney(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, peer: Peer) {
    showWalletSendMoney(context: context, environment: environment, walletContext: walletContext, peer: peer, analyticsContext: Analytics.shared.unresolvedContext())
}

@available(macOS 10.15, *)
public func showWalletSendMoney(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, peer: Peer, analyticsContext: AnalyticsContext) {
    let analyticsContext = Analytics.shared.captureContext(engine: context.engine, peerId: peer.id, inherited: analyticsContext)
    let presentation = analyticsContext.beginPresentation()
    let completed = walletOpenRecipientChat(environment: environment, window: context.window, peerId: peer.id)
    let controller = WalletSendController(context: context, environment: environment, walletContext: walletContext, peer: peer, completed: {
        let presentation = analyticsContext.beginPresentation()
        withExtendedLifetime(presentation) { completed() }
    })
    controller.analyticsContext = analyticsContext
    controller.current.analyticsContext = analyticsContext
    let onDeinit = controller.onDeinit
    controller.onDeinit = {
        onDeinit?()
        presentation.end()
    }
    showModal(with: controller, for: context.window)
}

let walletSendTransferFiatSwitchDelay: Double = 0.54
let walletSendTransferSpinLead: Double = 0.18
let walletSendTransferSpin: (velocity: Float, decay: Float) = (-10.0, 0.9)

func walletTransferSuccessText(isCollectible: Bool, recipient: String) -> String? {
    guard isCollectible else {
        return nil
    }
    return strings().walletSendControllerCollectibleSent(recipient)
}

private var walletDetachedSubmissions: [String: Disposable] = [:]

@available(macOS 10.15, *)
public func submitWalletTransferDetached(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, prepared: WalletContext.PreparedTransfer, window: Window, recipientName: String?, recipientPeerId: PeerId? = nil, session: PasscodeSession? = nil, submitted: @escaping () -> Void = {}, failed: @escaping () -> Void = {}) {
    submitWalletTransferDetached(context: context, environment: environment, walletContext: walletContext, prepared: prepared, window: window, recipientName: recipientName, recipientPeerId: recipientPeerId, session: session, submitted: submitted, failed: failed, analyticsContext: Analytics.shared.unresolvedContext())
}

@available(macOS 10.15, *)
public func submitWalletTransferDetached(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, prepared: WalletContext.PreparedTransfer, window: Window, recipientName: String?, recipientPeerId: PeerId? = nil, session: PasscodeSession? = nil, submitted: @escaping () -> Void = {}, failed: @escaping () -> Void = {}, analyticsContext: AnalyticsContext) {
    let analyticsContext = Analytics.shared.captureContext(engine: context.engine, peerId: recipientPeerId ?? context.peerId, inherited: analyticsContext)
    let presentation = analyticsContext.beginPresentation()
    defer { withExtendedLifetime(presentation) {} }
    runWalletTransferDetached(environment: environment, analyticsContext: analyticsContext, walletContext: walletContext, transferId: prepared.id, recipientAddress: prepared.recipient, isCollectible: prepared.collectible != nil, window: window, recipientName: recipientName, recipientPeerId: recipientPeerId, hasObservedTransfer: false, submission: walletContext.submitTransfer(prepared, recipientPeerId: recipientPeerId, session: session), submitted: submitted, failed: { error in
        session?.invalidate()
        presentWalletAuthorizationError(environment: environment, error, window: window, fallbackTitle: strings().walletSendControllerTransferFailedTitle, fallbackText: strings().walletSendControllerSendFailedInfo)
        failed()
    }, completed: {
        session?.invalidate()
    })
}

@available(macOS 10.15, *)
struct WalletPeerTransferRequest {
    let walletAddress: String
    let walletPublicKey: String
    let address: String
    let amount: Int64
    let sendAll: Bool
    let estimatedFee: Int64?
    let comment: String?
    let commentEncrypted: Bool
    let recipientPublicKey: Data?
}

@available(macOS 10.15, *)
func submitWalletPeerTransferDetached(environment: WalletUIEnvironment, walletContext: WalletContext, request: WalletPeerTransferRequest, registration: WalletContext.PendingTransferRegistration, session: PasscodeSession, window: Window, recipientName: String?, recipientPeerId: PeerId, analyticsContext: AnalyticsContext) {
    var preparedTransfer: WalletContext.PreparedTransfer?
    let submission: Signal<WalletContext.PendingTransfer, WalletContext.WalletError> = walletContext.state
    |> filter { $0.activeOperation == nil }
    |> take(1)
    |> castError(WalletContext.WalletError.self)
    |> mapToSignal { state -> Signal<WalletContext.PreparedTransfer, WalletContext.WalletError> in
        guard case let .wallet(info) = state.phase, info.address == request.walletAddress, info.publicKey == request.walletPublicKey else {
            return .fail(.authorizationCancelled)
        }
        guard let balance = state.balance.currentValue, request.amount <= balance else {
            return .fail(.insufficientBalance(required: request.amount))
        }
        if request.sendAll && balance != request.amount {
            return .fail(.previewFailed)
        }
        return walletContext.prepareTransfer(address: request.address, amount: request.amount, sendAll: request.sendAll, comment: request.comment, commentEncrypted: request.commentEncrypted, recipientPublicKey: request.recipientPublicKey, session: session, pendingRegistration: registration, estimatedFee: request.estimatedFee)
    }
    |> deliverOnMainQueue
    |> mapToSignal { prepared -> Signal<WalletContext.PendingTransfer, WalletContext.WalletError> in
        preparedTransfer = prepared
        return walletContext.submitTransfer(prepared, recipientPeerId: recipientPeerId, session: session, stageUpdated: { stage in
            if stage == .submitted {
                session.invalidate()
            }
        })
    }
    runWalletTransferDetached(environment: environment, analyticsContext: analyticsContext, walletContext: walletContext, transferId: registration.id, recipientAddress: request.address, isCollectible: false, window: window, recipientName: recipientName, recipientPeerId: recipientPeerId, hasObservedTransfer: true, submission: submission, submitted: {}, failed: { error in
        session.invalidate()
        _ = walletContext.discardPendingTransferRegistration(registration).startStandalone()
        if let preparedTransfer {
            _ = walletContext.discardPreparedTransfer(preparedTransfer).startStandalone()
        }
        presentWalletSendError(environment: environment, error, window: window)
    }, completed: {
        session.invalidate()
    })
}

@available(macOS 10.15, *)
private func runWalletTransferDetached(environment: WalletUIEnvironment, analyticsContext: AnalyticsContext, walletContext: WalletContext, transferId: String, recipientAddress: String, isCollectible: Bool, window: Window, recipientName: String?, recipientPeerId: PeerId?, hasObservedTransfer: Bool, submission submissionSignal: Signal<WalletContext.PendingTransfer, WalletContext.WalletError>, submitted: @escaping () -> Void, failed: @escaping (WalletContext.WalletError) -> Void, completed: @escaping () -> Void) {
    let presentation = analyticsContext.beginPresentation()
    defer { withExtendedLifetime(presentation) {} }
    let key = transferId
    let disposables = DisposableSet()
    let observationDisposable = MetaDisposable()
    disposables.add(observationDisposable)
    var submission = WalletDetachedSubmissionState()
    submission.hasObservedTransfer = hasObservedTransfer
    let walletAddress: String?
    if case let .wallet(info) = walletContext.stateValue.phase {
        walletAddress = WalletContext.transferAddress(from: info.address) ?? info.address
    } else {
        walletAddress = nil
    }
    let recipient = walletCollectibleSuccessRecipient(peerName: recipientName, address: recipientAddress)
    let cleanupIfNeeded: () -> Void = {
        if submission.shouldCleanUp {
            walletDetachedSubmissions.removeValue(forKey: key)?.dispose()
        }
    }
    let stopObserving: () -> Void = {
        guard !submission.observationStopped else {
            return
        }
        submission.observationStopped = true
        observationDisposable.set(nil)
        cleanupIfNeeded()
    }
    var dismissPendingAlert: (() -> Void)?
    let dismissSubmissionUnknown: () -> Void = {
        dismissPendingAlert?()
        dismissPendingAlert = nil
    }
    let presentSuccess: () -> Void = {
        guard submission.beginPresentingSuccess() else {
            return
        }
        dismissSubmissionUnknown()
        guard let text = walletTransferSuccessText(isCollectible: isCollectible, recipient: recipient) else {
            return
        }
        if let recipientPeerId {
            let feedbackPresentation = analyticsContext.beginPresentation()
            environment.showModalText(for: window, text: text, button: strings().walletSendControllerOpenChat, callback: { _ in
                withExtendedLifetime(feedbackPresentation) {
                    closeAllModals(window: window)
                    environment.openChat(recipientPeerId)
                }
            })
        } else {
            environment.showModalText(for: window, text: text)
        }
    }
    let presentationId = "pending:\(transferId)"
    observationDisposable.set(analyticsContext.preservingPresentation(walletContext.state
    |> deliverOnMainQueue).start(next: { state in
        guard !submission.observationStopped else {
            return
        }
        let matchesWallet: Bool
        if let walletAddress, case let .wallet(info) = state.phase {
            matchesWallet = (WalletContext.transferAddress(from: info.address) ?? info.address) == walletAddress
        } else {
            matchesWallet = false
        }
        let transaction = state.transactions.items.first { $0.presentationId == presentationId }
        let hasTransfer = transaction != nil || state.pendingTransfers.contains { $0.id == transferId }
        switch submission.observe(matchesWallet: matchesWallet, status: transaction?.status, hasTransfer: hasTransfer) {
        case .completed:
            stopObserving()
            presentSuccess()
        case .stop:
            if !matchesWallet {
                dismissSubmissionUnknown()
            }
            stopObserving()
        case .none:
            break
        }
    }))
    var didReportSubmission = false
    disposables.add(analyticsContext.preservingPresentation(submissionSignal
    |> deliverOnMainQueue).start(next: { pendingTransfer in
        if !didReportSubmission {
            didReportSubmission = true
            submitted()
        }
        if pendingTransfer.status == .submissionUnknown, !submission.observationStopped {
            dismissSubmissionUnknown()
            dismissPendingAlert = environment.dismissableAlert(for: window, header: strings().walletSendControllerTransferPendingTitle, info: strings().walletSendControllerTransferPendingInfo)
        }
    }, error: { error in
        stopObserving()
        submission.submitCompleted = true
        failed(error)
        cleanupIfNeeded()
    }, completed: {
        completed()
        submission.submitCompleted = true
        cleanupIfNeeded()
    }))
    if !(submission.shouldCleanUp) {
        walletDetachedSubmissions[key] = disposables
    }
}

@available(macOS 10.15, *)
private func presentWalletSendError(environment: WalletUIEnvironment, _ error: WalletContext.WalletError, window: Window) {
    switch error {
    case .authorizationCancelled:
        break
    case .commentTooLong, .commentEncryptionRecipientUnavailable, .commentEncryptionFailed:
        let message = walletAuthorizationErrorMessage(error)
        environment.alert(for: window, header: message?.title ?? strings().walletSendControllerTransferFailedTitle, info: message?.text ?? strings().walletSendControllerTransferFailedInfo)
    case let .insufficientBalance(required):
        environment.alert(for: window, header: strings().walletSendControllerInsufficientFundsTitle, info: strings().walletSendControllerInsufficientFundsInfo(formatGramsText(required, maxDecimalPositions: 9)))
    default:
        presentWalletAuthorizationError(environment: environment, error, window: window, fallbackTitle: strings().walletSendControllerTransferFailedTitle, fallbackText: strings().walletSendControllerTransferFailedDetailedInfo)
    }
}

@available(macOS 10.15, *)
func makeWalletSendController(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, initialAddress: String?, initialRecipientPublicKey: Data? = nil, peer: Peer?, initialAmount: Int64? = nil, initialComment: String? = nil, transferAnimation: WalletSendTransferAnimation? = nil, transferAnimationWillStart: ((String) -> Void)? = nil, completed: (() -> Void)? = nil, getModal: @escaping () -> InputDataModalController?, onBack: (() -> Void)?) -> WalletSendStep {
    let actionsDisposable = DisposableSet()
    actionsDisposable.add(walletContext.refreshBalance())
    actionsDisposable.add(walletContext.beginGaslessInfoUpdates())
    let signingAccessDisposable = MetaDisposable()
    actionsDisposable.add(signingAccessDisposable)
    let restoreAuthorization = WalletFlowAuthorization(walletContext: walletContext, reason: walletRestoreFlowReason)
    var abandonRestoration: (() -> Void)?

    var initialState = WalletSendState()
    initialState.selectedPeer = peer.map(EnginePeer.init)
    if let initialAmount, initialAmount > 0 {
        initialState.amount = initialAmount
        initialState.amountSource = .transferLink
    }
    if let initialAddress, !initialAddress.isEmpty {
        let parsed = walletParseRecipient(initialAddress)
        if let amount = parsed.amount {
            initialState.amount = amount
            initialState.amountSource = .transferLink
        }
        initialState.comment = parsed.comment ?? initialComment
        if let address = walletSendRecipientAddress(parsed.address) {
            initialState.resolved = WalletContext.ResolvedTransferRecipient(address: address, displayName: peer.map { environment.peerTitle($0, compact: true) })
            if let initialRecipientPublicKey, !initialRecipientPublicKey.isEmpty {
                initialState.recipientPublicKey = initialRecipientPublicKey
            }
        }
    }
    initialState.isResolving = peer != nil && initialState.resolved == nil

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((WalletSendState) -> WalletSendState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    var getController: (() -> InputDataController?)? = nil
    let getAnalyticsContext: () -> AnalyticsContext = {
        return getController?()?.analyticsContext ?? Analytics.shared.unresolvedContext()
    }
    let presentChild: (AnalyticsContext, () -> InputDataModalController, Window, (() -> NSView?)?) -> Void = { analyticsContext, makeController, window, morphSource in
        let presentation = analyticsContext.beginPresentation()
        let controller = makeController()
        controller.analyticsContext = analyticsContext
        controller.current.analyticsContext = analyticsContext
        let onDeinit = controller.onDeinit
        controller.onDeinit = {
            onDeinit?()
            presentation.end()
        }
        showModal(with: controller, for: window, morphSource: morphSource)
    }
    let amountRowView: () -> WalletAmountRowView? = {
        return getController?()?.tableView.item(stableId: InputDataEntryId.custom(_id_amount))?.view as? WalletAmountRowView
    }
    var close: (() -> Void)? = nil
    var submitImpl: (() -> Void)? = nil
    var closesWithoutConfirmation = false

    var window: Window {
        return walletUIWindow(context, getController?())
    }

    var lockedPeerPublicKey: (address: String, publicKey: Data)? = nil
    if let address = initialState.resolved?.address, let initialRecipientPublicKey, !initialRecipientPublicKey.isEmpty {
        lockedPeerPublicKey = (address, initialRecipientPublicKey)
    }
    let applyResolvedAddress: (String, String?) -> Void = { address, displayName in
        updateState { current in
            var current = current
            current.resolved = WalletContext.ResolvedTransferRecipient(address: address, displayName: displayName)
            if let lockedPeerPublicKey, lockedPeerPublicKey.address == address {
                current.recipientPublicKey = lockedPeerPublicKey.publicKey
            }
            current.isResolving = false
            return current
        }
    }

    let openLinkedPeer: (EnginePeer) -> Void = { linkedPeer in
        closeAllModals(window: window)
        environment.openChat(linkedPeer.id)
    }

    let clampedTransferAmount: (Int64) -> (amount: Int64, clamped: Bool) = { amount in
        let minimum = WalletConfiguration.with(appConfiguration: context.appConfiguration).transferMinAmount
        if amount > 0, amount < minimum {
            return (minimum, true)
        }
        return (amount, false)
    }

    let editComment: () -> Void = {
        let current = stateValue.with { $0 }
        presentChild(getAnalyticsContext(), { walletCommentInputController(comment: walletTransactionComment(current.comment), isPublic: current.isCommentPublic, completion: { comment, isPublic in
            updateState { current in
                var current = current
                current.comment = comment
                current.isCommentPublic = isPublic
                return current
            }
        }) }, window, nil)
    }

    let arguments = Arguments(context: context, environment: environment, deposit: { morphSource in
        guard case let .wallet(info) = walletContext.stateValue.phase else {
            return
        }
        presentChild(getAnalyticsContext(), { WalletReceiveController(context: context, environment: environment, walletContext: walletContext, address: info.address) }, window, morphSource)
    }, editComment: editComment, updateAmount: { amount in
        let resolved = clampedTransferAmount(amount)
        updateState { current in
            var current = current
            current.amount = resolved.amount
            current.amountSource = .manual
            if resolved.clamped {
                current.revision += 1
            }
            return current
        }
        if resolved.clamped {
            getController?()?.proccessValidation(.fail(.fields([_id_amount: .shake])))
        }
    }, toggleMode: {
        updateState { current in
            var current = current
            guard let rate = current.rate, rate.isFinite, rate > 0 else {
                return current
            }
            if current.mode == .fiat {
                current.amount = walletMilligramTruncated(current.amount)
            }
            current.mode = current.mode == .gram ? .fiat : .gram
            current.revision += 1
            return current
        }
    }, submit: {
        submitImpl?()
    }, showLinkedPeerInfo: { linkedPeer, address in
        let canOpenPeer = stateValue.with { walletSendCanOpenRecipientChat($0) }
        showWalletLinkedRecipientInfo(environment: environment, window: window, peer: linkedPeer, address: address, openPeer: canOpenPeer ? linkedPeer.map { peer in
            { openLinkedPeer(peer) }
        } : nil)
    }, copyAddress: { address in
        walletCopyAddress(address, environment: environment, window: window)
    }, openPeer: openLinkedPeer)

    let linkedPeerDisposable = MetaDisposable()
    actionsDisposable.add(linkedPeerDisposable)
    actionsDisposable.add((statePromise.get()
    |> map { state -> String? in
        guard !state.isPeerMode, !state.isResolving else {
            return nil
        }
        return state.resolved?.address
    }
    |> distinctUntilChanged
    |> deliverOnMainQueue).start(next: { address in
        guard let address else {
            linkedPeerDisposable.set(nil)
            return
        }
        linkedPeerDisposable.set((walletAddressOwner(context: context, address: address)
        |> deliverOnMainQueue).start(next: { owner in
            guard let linkedPeer = owner?.peer else {
                return
            }
            walletContext.rememberPresentedWalletPeer(linkedPeer, address: address)
            updateState { current in
                var current = current
                current.linkedPeer = WalletSendLinkedPeer(address: address, peer: linkedPeer)
                return current
            }
        }))
    }))

    let feeEstimateDisposable = MetaDisposable()
    actionsDisposable.add(feeEstimateDisposable)
    let startFeeEstimate: (WalletSendFeeRequest) -> Void = { request in
        updateState { current in
            var current = current
            current.isEstimatingFee = true
            if current.feeEstimate?.request == request {
                current.feeEstimate = nil
            }
            return current
        }
        let estimate: Signal<WalletSendFeeEstimate, NoError> = walletContext.state
        |> filter { $0.activeOperation == nil }
        |> take(1)
        |> castError(WalletContext.WalletError.self)
        |> mapToSignal { _ in
            walletContext.estimateTransferFee(address: request.address, comment: request.comment)
        }
        |> map { estimate -> WalletSendFeeEstimate in
            return WalletSendFeeEstimate(request: request, fee: estimate.fee)
        }
        |> `catch` { error in
            Signal<WalletSendFeeEstimate, NoError>.single(WalletSendFeeEstimate(request: request, fee: nil, error: error))
        }
        feeEstimateDisposable.set((Signal<WalletSendFeeEstimate, NoError>.complete()
        |> delay(0.4, queue: .mainQueue())
        |> then(estimate)
        |> deliverOnMainQueue).start(next: { estimate in
            updateState { current in
                var current = current
                current.feeEstimate = estimate
                current.isEstimatingFee = false
                return current
            }
        }))
    }
    actionsDisposable.add((statePromise.get()
    |> map { walletSendFeeRequest($0) }
    |> distinctUntilChanged
    |> deliverOnMainQueue).start(next: { request in
        guard let request else {
            feeEstimateDisposable.set(nil)
            updateState { current in
                var current = current
                current.isEstimatingFee = false
                return current
            }
            return
        }
        guard stateValue.with({ $0.feeEstimate?.request }) != request else {
            return
        }
        startFeeEstimate(request)
    }))

    actionsDisposable.add((walletContext.state
    |> deliverOnMainQueue).start(next: { walletState in
        if case .idle = walletState.gaslessInfo {
            walletContext.ensureGaslessInfo()
        }
        let gaslessMinAmount = WalletConfiguration.with(appConfiguration: context.appConfiguration).transferGaslessMinAmount
        if case let .wallet(previousInfo) = stateValue.with({ $0.walletPhase }) {
            switch walletState.phase {
            case let .wallet(info) where previousInfo.address == info.address && previousInfo.publicKey == info.publicKey:
                break
            default:
                abandonRestoration?()
            }
        }
        updateState { current in
            var current = current
            current.walletPhase = walletState.phase
            current.walletAddress = walletState.walletAddress
            current.balance = walletState.balance.currentValue
            if case .stale = walletState.gaslessInfo {
                current.gaslessInfo = nil
            } else {
                current.gaslessInfo = walletState.gaslessInfo.currentValue
            }
            current.gaslessMinAmount = gaslessMinAmount
            let ownPreparation = current.isEstimatingFee && walletState.activeOperation == .preparingTransfer
            let hasWallet: Bool
            if case .wallet = walletState.phase {
                hasWallet = true
            } else {
                hasWallet = false
            }
            switch walletState.balance {
            case .loading:
                current.isLoading = !hasWallet || walletState.balance.currentValue == nil || (walletState.activeOperation != nil && !ownPreparation)
            default:
                current.isLoading = !hasWallet || (walletState.activeOperation != nil && !ownPreparation)
            }
            current.currency = walletState.fiat.selectedCurrency
            if let rate = walletState.fiat.selectedRate, rate.unitsPerGram.isFinite, rate.unitsPerGram > 0 {
                current.rate = rate.unitsPerGram
            } else {
                current.rate = nil
                if current.mode == .fiat {
                    current.mode = .gram
                    current.revision += 1
                }
            }
            return current
        }
    }))

    if let peer, let resolved = initialState.resolved, lockedPeerPublicKey != nil {
        walletContext.rememberPresentedWalletPeer(EnginePeer(peer), address: resolved.address)
    }

    if let peer, initialState.resolved != nil, lockedPeerPublicKey == nil {
        actionsDisposable.add((walletPeerSendAddress(context: context, environment: environment, walletContext: walletContext, peerId: peer.id)
        |> take(1)
        |> deliverOnMainQueue).start(next: { target in
            if let target {
                walletContext.rememberPresentedWalletPeer(EnginePeer(peer), address: target.address)
            }
            updateState { current in
                var current = current
                guard current.isPeerMode, let resolved = current.resolved else {
                    return current
                }
                if let target {
                    if let publicKey = walletSendPeerPublicKey(address: resolved.address, peerAddress: target.address, publicKey: target.publicKey) {
                        current.recipientPublicKey = publicKey
                    }
                } else {
                    current.resolved = nil
                }
                return current
            }
        }))
    }

    if let peer, initialState.resolved == nil {
        actionsDisposable.add((walletPeerSendAddress(context: context, environment: environment, walletContext: walletContext, peerId: peer.id)
        |> take(1)
        |> deliverOnMainQueue).start(next: { target in
            if let target, let address = walletSendRecipientAddress(target.address) {
                walletContext.rememberPresentedWalletPeer(EnginePeer(peer), address: address)
                if let publicKey = target.publicKey, !publicKey.isEmpty {
                    lockedPeerPublicKey = (address, publicKey)
                }
                applyResolvedAddress(address, environment.peerTitle(peer, compact: true))
            } else {
                updateState { current in
                    var current = current
                    current.isResolving = false
                    return current
                }
            }
        }))
    }

    let closeAfterTransferRegistration: (String) -> Void = { transferId in
        let finish: () -> Void = {
            updateState { current in
                var current = current
                current.isSending = false
                return current
            }
            closesWithoutConfirmation = true
            getModal()?.close(animationType: .noMorph)
            completed?()
        }
        guard let transferAnimation else {
            finish()
            return
        }
        let isFormVisible: () -> Bool = {
            guard let controller = getController?(), controller.isLoaded() else {
                return false
            }
            return controller.view.window != nil
        }
        let launch: () -> Void = {
            guard isFormVisible() else {
                return
            }
            let presentationId = "pending:\(transferId)"
            if walletContext.stateValue.transactions.items.contains(where: { $0.presentationId == presentationId && $0.status != .failed }) {
                #if arch(arm64)
                let source = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : amountRowView()?.takeTransferDiamond()
                #else
                let source: WalletSendTransferAnimationSource? = nil
                #endif
                if !transferAnimation(presentationId, source) {
                    source?.diamond.isRenderingEnabled = false
                    source?.diamond.removeFromSuperview()
                }
            }
            finish()
        }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            launch()
            return
        }
        #if arch(arm64)
        transferAnimationWillStart?("pending:\(transferId)")
        #endif
        let switchedFromFiat = stateValue.with { $0.mode == .fiat }
        if switchedFromFiat {
            updateState { current in
                var current = current
                current.mode = .gram
                current.revision += 1
                return current
            }
        }
        delay(switchedFromFiat ? walletSendTransferFiatSwitchDelay : 0.0, closure: {
            guard isFormVisible() else {
                return
            }
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
                launch()
                return
            }
            #if arch(arm64)
            amountRowView()?.spinForTransfer()
            #endif
            delay(walletSendTransferSpinLead, closure: launch)
        })
    }

    let sendDisposable = MetaDisposable()
    actionsDisposable.add(sendDisposable)
    let sendDirectly: (WalletContext.ResolvedTransferRecipient) -> Void = { resolved in
        let analyticsContext = getController?()?.analyticsContext ?? Analytics.shared.unresolvedContext()
        let presentation = analyticsContext.beginPresentation()
        defer { withExtendedLifetime(presentation) {} }
        let targetWindow = window
        let state = stateValue.with { $0 }
        let comment = walletTransactionComment(state.comment)
        let finish: (WalletContext.WalletError?) -> Void = { error in
            updateState { current in
                var current = current
                current.isSending = false
                return current
            }
            guard let error else {
                return
            }
            presentWalletSendError(environment: environment, error, window: targetWindow)
        }
        guard let recipientPeerId = state.selectedPeer?.id, case let .wallet(info) = walletContext.stateValue.phase, let feeRequest = walletSendFeeRequest(state) else {
            finish(.unavailable)
            return
        }
        if case .failed = walletSendFeeReadiness(state, request: feeRequest) {
            startFeeEstimate(feeRequest)
        }
        updateState { current in
            var current = current
            current.isSending = true
            return current
        }
        sendDisposable.set(analyticsContext.preservingPresentation(statePromise.get()
        |> map { walletSendFeeReadiness($0, request: feeRequest) }
        |> filter { $0 != .estimating }
        |> take(1)
        |> castError(WalletContext.WalletError.self)
        |> mapToSignal { readiness -> Signal<WalletPeerTransferRequest, WalletContext.WalletError> in
            switch readiness {
            case let .ready(fee):
                return .single(WalletPeerTransferRequest(
                    walletAddress: info.address,
                    walletPublicKey: info.publicKey,
                    address: resolved.address,
                    amount: state.amount,
                    sendAll: walletShouldSendAll(state),
                    estimatedFee: fee,
                    comment: comment,
                    commentEncrypted: comment != nil && !state.isCommentPublic,
                    recipientPublicKey: state.recipientPublicKey
                ))
            case let .failed(error):
                return .fail(error)
            case .estimating, .changed:
                return .fail(.authorizationCancelled)
            }
        }
        |> mapToSignal { request -> Signal<(WalletPeerTransferRequest, WalletContext.PendingTransferRegistration, PasscodeSession), WalletContext.WalletError> in
            return walletContext.state
            |> filter { $0.activeOperation == nil }
            |> take(1)
            |> castError(WalletContext.WalletError.self)
            |> mapToSignal { _ in
                walletContext.beginWalletFlow(reason: "Send Grams")
            }
            |> mapToSignal { session -> Signal<(WalletPeerTransferRequest, WalletContext.PendingTransferRegistration, PasscodeSession), WalletContext.WalletError> in
                return walletContext.registerPendingTransfer(walletAddress: request.walletAddress, walletPublicKey: request.walletPublicKey, peerId: recipientPeerId, address: request.address, amount: request.amount, sendAll: request.sendAll, estimatedFee: request.estimatedFee, comment: request.comment, commentEncrypted: request.commentEncrypted, session: session)
                |> map { (request, $0, session) }
                |> `catch` { error -> Signal<(WalletPeerTransferRequest, WalletContext.PendingTransferRegistration, PasscodeSession), WalletContext.WalletError> in
                    session.invalidate()
                    return .fail(error)
                }
            }
        }
        |> deliverOnMainQueue).start(next: { request, registration, session in
            let recipientName = walletContext.walletPeerDisplayName(forAddress: resolved.address, environment: environment) ?? resolved.displayName
            submitWalletPeerTransferDetached(environment: environment, walletContext: walletContext, request: request, registration: registration, session: session, window: targetWindow, recipientName: recipientName, recipientPeerId: recipientPeerId, analyticsContext: analyticsContext.restricting(peerId: recipientPeerId))
            closeAfterTransferRegistration(registration.id)
        }, error: { error in
            finish(error)
        }))
    }

    abandonRestoration = {
        signingAccessDisposable.set(nil)
        restoreAuthorization.end()
        updateState { current in
            var current = current
            current.isResolvingSigningAccess = false
            return current
        }
    }

    submitImpl = {
        let analyticsContext = getAnalyticsContext()
        let presentation = analyticsContext.beginPresentation()
        defer { withExtendedLifetime(presentation) {} }
        let state = stateValue.with { $0 }
        guard !state.isResolvingSigningAccess else {
            return
        }
        let resolvedAmount = clampedTransferAmount(state.amount)
        if resolvedAmount.clamped {
            updateState { current in
                var current = current
                current.amount = resolvedAmount.amount
                current.revision += 1
                return current
            }
            getController?()?.proccessValidation(.fail(.fields([_id_amount: .shake])))
            return
        }
        guard walletCanSend(state) else {
            return
        }
        arguments.opening.finish(animated: true)
        guard let resolved = state.resolved else {
            return
        }
        let targetWindow = window
        let openPreview: () -> Void = {
            let presentation = analyticsContext.beginPresentation()
            defer { withExtendedLifetime(presentation) {} }
            let current = stateValue.with { $0 }
            guard !current.isPeerMode else {
                sendDirectly(resolved)
                return
            }
            close?()
            presentChild(analyticsContext, { WalletTransactionController(context: context, environment: environment, walletContext: walletContext, subject: .preview(address: resolved.address, amount: current.amount, sendAll: walletShouldSendAll(current), comment: current.comment, initialFee: walletSendInitialFee(current)), transferAnimation: transferAnimation) }, targetWindow, nil)
        }
        let setResolvingSigningAccess: (Bool) -> Void = { value in
            updateState { current in
                var current = current
                current.isResolvingSigningAccess = value
                return current
            }
        }
        switch walletContext.stateValue.phase {
        case let .wallet(info) where info.canSign:
            abandonRestoration?()
            openPreview()
        case let .wallet(info) where info.canExportPhrase:
            setResolvingSigningAccess(true)
            let restorationPresentation = analyticsContext.beginPresentation()
            let restoration = walletRestoreSigningAccess(context: context, environment: environment, window: targetWindow, walletContext: walletContext, authorization: restoreAuthorization, retry: {
                let delivery = analyticsContext.beginPresentation()
                withExtendedLifetime(delivery) { submitImpl?() }
            }, next: {
                let delivery = analyticsContext.beginPresentation()
                withExtendedLifetime(delivery) {
                    setResolvingSigningAccess(false)
                    openPreview()
                }
            }, failed: {
                let delivery = analyticsContext.beginPresentation()
                withExtendedLifetime(delivery) { setResolvingSigningAccess(false) }
            })
            signingAccessDisposable.set(ActionDisposable {
                restoration.dispose()
                restorationPresentation.end()
            })
        case .wallet:
            presentChild(analyticsContext, { WalletImportController(context: context, environment: environment, walletContext: walletContext, mode: .enterRecoveryPhrase, onImported: {
                openPreview()
            }) }, targetWindow, nil)
        default:
            environment.showModalText(for: targetWindow, text: strings().walletSendControllerStillSyncing)
        }
    }

    let signal = statePromise.get()
    |> deliverOnPrepareQueue
    |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let titleForState: () -> String = {
        return strings().walletSendControllerTitle
    }
    let recipientModalHeader: () -> ModalHeaderData? = {
        return ModalHeaderData(title: titleForState())
    }
    let controller = InputDataController(dataSignal: signal, title: titleForState(), hasDone: false, identifier: "wallet-send", getBackgroundColor: {
        theme.colors.background
    })
    controller.analyticsScreen = .walletTransfer
    controller.getTitle = titleForState
    controller.centerModalHeader = recipientModalHeader()

    getController = { [weak controller] in
        return controller
    }

    arguments.opening.isReady = {
        guard let view = amountRowView() else {
            return false
        }
        return view.window != nil && !view.bounds.isEmpty
    }
    arguments.opening.updateAmount = { value in
        amountRowView()?.updateOpening(value)
    }
    arguments.opening.updateRecipient = { time in
        (getController?()?.tableView.item(stableId: InputDataEntryId.custom(_id_linked_recipient))?.view as? WalletLinkedRecipientRowView)?.updateOpening(time: time)
    }
    controller.didAppear = { _ in
        arguments.opening.update()
    }
    controller.willDisappear = { _ in
        arguments.opening.finish(animated: false)
    }

    controller.onDeinit = {
        actionsDisposable.dispose()
        submitImpl = nil
    }

    controller.validateData = { _ in
        return .success(.custom {
            submitImpl?()
        })
    }

    let acceptTitlePrefixForState: () -> String? = {
        let state = stateValue.with { $0 }
        guard state.isPeerMode, !state.isSending else {
            return nil
        }
        return strings().walletSendControllerSendPrefix
    }
    let acceptTitleForState: () -> String = {
        let state = stateValue.with { $0 }
        guard state.isPeerMode else {
            return strings().walletSendControllerContinue
        }
        if state.isSending {
            return strings().walletSendControllerSending
        }
        let amountTitle = state.amount > 0 ? formatGramsText(state.amount, maxDecimalPositions: state.mode == .fiat ? 2 : 9) : strings().walletSendControllerGrams
        return (acceptTitlePrefixForState() ?? "") + amountTitle
    }
    let acceptSubtitleForState: () -> String? = {
        let state = stateValue.with { $0 }
        guard state.isPeerMode, !state.isSending, state.amount > 0, state.mode == .fiat, let rate = state.rate, rate.isFinite, rate > 0 else {
            return nil
        }
        return "~" + walletAmountGrouped(walletSendInputText(amount: state.amount, mode: .fiat, rate: rate, fiatFractionDigits: walletFiatFractionDigits(state.currency))) + " " + state.currency.code
    }
    weak var sendButtonView: NSView?
    let updateButton: () -> Void = {
        guard let modalController = getModal(), let controller = getController?(), modalController.current === controller else {
            return
        }
        let acceptTitle = acceptTitleForState()
        let acceptSubtitle = acceptSubtitleForState()
        let state = stateValue.with { $0 }
        modalController.modalInteractions?.updateDone { button in
            sendButtonView = button
            button.isEnabled = walletCanSend(state)
            button.set(text: "", for: .Normal)
            button.set(subtext: nil, for: .Normal)
            let content = WalletSendButtonContentView.install(in: button)
            content.alphaValue = button.isEnabled ? 1.0 : 0.5
            content.update(WalletSendButtonContentView.Content(title: acceptTitle, titlePrefix: acceptTitlePrefixForState(), subtitle: acceptSubtitle, color: walletClassicAccent.lightness > 0.8 ? .black : .white, isVisible: true, mode: state.mode, timing: arguments.clock.timing))
        }
        modalController.modalInteractions?.acceptTitle = acceptTitle
    }

    arguments.opening.risingViews = {
        let rows = [_id_balance, _id_deposit].compactMap { getController?()?.tableView.item(stableId: InputDataEntryId.custom($0))?.view }
        return rows + [sendButtonView].compactMap { $0 }
    }

    var appliedTitle = titleForState()
    var appliedLinkedPeer = stateValue.with { walletSendLinkedPeer($0) }
    controller.afterTransaction = { controller in
        defer {
            arguments.opening.update()
        }
        guard let modalController = getModal(), modalController.current === controller else {
            return
        }
        updateButton()
        let title = titleForState()
        let linkedPeer = stateValue.with { walletSendLinkedPeer($0) }
        if title != appliedTitle || linkedPeer != appliedLinkedPeer {
            appliedTitle = title
            appliedLinkedPeer = linkedPeer
            controller.centerModalHeader = recipientModalHeader()
            modalController.updateLocalizationAndTheme(theme: theme)
        }
    }

    controller.rightModalHeader = ModalHeaderData(image: theme.icons.chatActionsActive, contextMenu: {
        let state = stateValue.with { $0 }
        let targetWindow = window
        var items: [ContextMenuItem] = []
        if case let .wallet(info) = walletContext.stateValue.phase {
            items.append(ContextMenuItem(strings().walletSendControllerDepositFunds, handler: {
                presentChild(getAnalyticsContext(), { WalletReceiveController(context: context, environment: environment, walletContext: walletContext, address: info.address) }, targetWindow, nil)
            }, itemImage: environment.menuImage(.menu_plus)))
        }
        if state.isPeerMode {
            let hasComment = walletTransactionComment(state.comment) != nil
            items.append(ContextMenuItem(hasComment ? strings().walletSendControllerEditComment : strings().walletSendControllerAddComment, handler: editComment, itemImage: environment.menuImage(.menu_message)))
        }
        return items
    })

    if let onBack {
        controller.leftModalHeader = ModalHeaderData(image: theme.icons.chatNavigationBack, handler: onBack, isCloseButton: false)
    } else {
        controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: {
            getModal()?.close()
        })
    }

    close = {
        closesWithoutConfirmation = true
        getModal()?.close()
    }

    let requestDismiss: (@escaping () -> Void) -> Void = { completion in
        let state = stateValue.with { $0 }
        guard !closesWithoutConfirmation, state.amount > 0 || amountRowView()?.hasInputText == true || state.comment?.isEmpty == false else {
            completion()
            return
        }
        let targetWindow = window
        let restoresFocus = amountRowView().map { targetWindow.firstResponder === $0.firstResponder } ?? false
        environment.verifyAlert_button(for: targetWindow, header: appName, information: strings().walletSendControllerDiscardTransfer, ok: strings().alertYes, cancel: strings().alertNO, successHandler: { _ in
            completion()
        }, cancelHandler: {
            let state = stateValue.with { $0 }
            guard restoresFocus, !state.isSending, !state.isResolvingSigningAccess, let controller = getController?(), getModal()?.current === controller, let responder = amountRowView()?.firstResponder else {
                return
            }
            _ = targetWindow.makeFirstResponder(responder)
        })
    }

    return WalletSendStep(controller: controller, acceptTitle: acceptTitleForState, submit: {
        submitImpl?()
    }, updateButton: updateButton, requestDismiss: requestDismiss)
}

private func walletCommentInputController(comment: String?, isPublic: Bool, completion: @escaping (String?, Bool) -> Void) -> InputDataModalController {
    struct CommentInputState: Equatable {
        var text: String
        var isPublic: Bool
    }
    let initialState = CommentInputState(text: comment ?? "", isPublic: isPublic)
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((CommentInputState) -> CommentInputState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    let entries: (CommentInputState) -> [InputDataEntry] = { state in
        var entries: [InputDataEntry] = []
        var sectionId: Int32 = 0
        var index: Int32 = 0

        entries.append(.sectionId(sectionId, type: .customModern(10)))
        sectionId += 1

        entries.append(.input(sectionId: sectionId, index: index, value: .string(state.text), error: nil, identifier: _id_comment_text, mode: .plain, data: .init(viewType: .singleItem), placeholder: nil, inputPlaceholder: strings().walletSendControllerCommentPlaceholder, filter: walletCommentInputFilter, limit: Int32(walletCommentMaximumBytes)))
        index += 1

        entries.append(.sectionId(sectionId, type: .customModern(16)))
        sectionId += 1

        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_comment_public, data: .init(name: strings().walletSendControllerMakeCommentPublic, color: theme.colors.text, type: .switchable(state.isPublic), viewType: .singleItem, action: {
            updateState { current in
                var current = current
                current.isPublic.toggle()
                return current
            }
        }, theme: walletRowTheme)))
        index += 1

        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().walletSendControllerPublicCommentInfo), data: .init(color: theme.colors.listGrayText, detectBold: false, viewType: .textBottomItem)))
        index += 1

        entries.append(.sectionId(sectionId, type: .customModern(20)))
        sectionId += 1

        return entries
    }

    let dataSignal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state))
    }

    var close: (() -> Void)?
    let isEditing = comment?.isEmpty == false
    let controller = InputDataController(dataSignal: dataSignal, title: isEditing ? strings().walletSendControllerEditComment : strings().walletSendControllerAddComment, validateData: { data in
        return .fail(.doSomething { _ in
            let text = (data[_id_comment_text]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            completion(text.isEmpty ? nil : text, stateValue.with { $0.isPublic })
            close?()
        })
    }, updateDatas: { data in
        updateState { current in
            var current = current
            current.text = data[_id_comment_text]?.stringValue ?? ""
            return current
        }
        return .fail(.none)
    }, hasDone: false)
    controller.analyticsScreen = .walletTransferComment
    controller.autoInputAction = true

    let interactions = ModalInteractions(acceptTitle: isEditing ? strings().walletSendControllerSave : strings().walletSendControllerAdd, accept: { [weak controller] in
        controller?.validateInputValues()
    }, singleButton: true, customTheme: { walletModalTheme })

    let modalController = WalletModalController(controller, modalInteractions: interactions, size: NSMakeSize(320, 0))
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    close = { [weak modalController] in
        modalController?.close()
    }
    return modalController
}
