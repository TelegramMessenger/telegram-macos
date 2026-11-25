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
import WalletContext
import TelegramCore
import PasscodeCore
import AppAnalytics

@available(macOS 10.15, *)
public enum WalletTransactionSubject {
    case transaction(WalletContext.Transaction)
    case preview(address: String, amount: Int64, sendAll: Bool, comment: String?, initialFee: Int64?)
    case collectiblePreview(address: String, recipientPeer: EnginePeer? = nil, collectible: WalletContext.Collectible)
}

public enum WalletTransactionOrigin {
    case wallet
    case chat
}

struct WalletTransactionOpenActions: Equatable {
    let decryptComment: Bool
    let checkFirstIncomingTransfer: Bool
}

@available(macOS 10.15, *)
func walletTransactionOpenActions(subject: WalletTransactionSubject, decryptCommentOnOpen: Bool) -> WalletTransactionOpenActions {
    guard case let .transaction(transaction) = subject else {
        return WalletTransactionOpenActions(decryptComment: false, checkFirstIncomingTransfer: false)
    }
    return WalletTransactionOpenActions(
        decryptComment: decryptCommentOnOpen && transaction.commentEncrypted && transaction.comment?.isEmpty == false,
        checkFirstIncomingTransfer: !decryptCommentOnOpen && transaction.direction == .incoming && transaction.currency == .ton && transaction.collectible == nil
    )
}

public func walletTransactionComment(_ value: String?) -> String? {
    guard var value = value else {
        return nil
    }
    value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
}

@available(macOS 10.15, *)
private func walletTransactionAddressesEqual(_ lhs: String, _ rhs: String) -> Bool {
    guard let lhs = WalletContext.transferAddress(from: lhs),
          let rhs = WalletContext.transferAddress(from: rhs) else {
        return false
    }
    return lhs == rhs
}

/// Only a pair that both canonicalize and differ is a real mismatch. Testnet addresses canonicalize to
/// nil, so treating "cannot compare" as a mismatch would reject every confirmation on a test network.
@available(macOS 10.15, *)
private func walletTransactionAddressesConflict(_ lhs: String, _ rhs: String) -> Bool {
    guard let lhs = WalletContext.transferAddress(from: lhs),
          let rhs = WalletContext.transferAddress(from: rhs) else {
        return false
    }
    return lhs != rhs
}

private func walletTransactionHashesEqual(_ lhs: String?, _ rhs: String?) -> Bool {
    return walletTransactionHashMatches(lhs, rhs)
}

func walletTransactionShortAddress(_ address: String) -> String {
    var address = address
    if #available(macOS 10.15, *) {
        address = WalletContext.transferAddress(from: address, preserveBounce: true) ?? address
    }
    guard address.count > 8 else {
        return address
    }
    return "\(address.prefix(4))…\(address.suffix(4))"
}

func walletCollectibleSuccessRecipient(peerName: String?, address: String) -> String {
    return peerName ?? walletTransactionShortAddress(address)
}

@available(macOS 10.15, *)
func walletPreviewTransactionPeer(recipient: String, recipientPeer: EnginePeer?) -> WalletContext.Transaction.Peer {
    return recipientPeer.map { .user($0, address: recipient, domain: nil) } ?? .address(recipient, domain: nil)
}

@available(macOS 10.15, *)
func walletTransactionCounterpartyTitle(isUnfinishedPreview: Bool, peer: WalletContext.Transaction.Peer, direction: WalletContext.Transaction.Direction) -> String {
    if isUnfinishedPreview, case .address = peer {
        return strings().walletTransactionControllerAddress
    }
    switch direction {
    case .incoming:
        return strings().walletTransactionControllerSender
    case .outgoing:
        return strings().walletTransactionControllerRecipient
    case .unknown:
        return strings().walletTransactionControllerAddress
    }
}

private func walletTransactionExplorerHash(_ value: String) -> String? {
    return walletNormalizedTransactionHash(value)
}

func walletTransactionExplorerUrl(explorerUrl: String, hash: String) -> String? {
    guard let hash = walletTransactionExplorerHash(hash) else {
        return nil
    }
    let baseUrl = explorerUrl.hasSuffix("/") ? explorerUrl : explorerUrl + "/"
    return "\(baseUrl)transaction/\(hash)"
}

@available(macOS 10.15, *)
private func walletExplorerUrl(context: any AccountContextProtocol, environment: WalletUIEnvironment, hash: String) -> String? {
    return walletTransactionExplorerUrl(explorerUrl: WalletConfiguration.with(appConfiguration: context.appConfiguration).explorerUrl, hash: hash)
}

@available(macOS 10.15, *)
private func walletTransactionExplorerUrl(context: any AccountContextProtocol, environment: WalletUIEnvironment, transaction: WalletContext.Transaction) -> String? {
    for candidate in [transaction.transactionHash, transaction.id, transaction.externalMessageHash] {
        if let candidate, let url = walletExplorerUrl(context: context, environment: environment, hash: candidate) {
            return url
        }
    }
    return nil
}

@available(macOS 10.15, *)
private final class Arguments {
    let context: any AccountContextProtocol
    let environment: WalletUIEnvironment
    let subject: WalletTransactionSubject
    let previewTimestamp: Int32
    let transferGaslessMinAmount: Int64
    let sendToCounterparty: (Int64?, String?) -> Void
    let decryptComment: () -> Void
    let toggleEncryptComment: () -> Void
    let toggleCommentExpansion: () -> Void
    let copyAddress: (String) -> Void
    let commentUpdated: (String) -> Void
    let showFeeInfo: () -> Void
    let showWhatsGram: ((() -> NSView?)?) -> Void
    let intro: WalletOpenIntro?
    var updateHeader: (Bool, NSColor?) -> Void = { _, _ in }
    var close: () -> Void = {}

    @available(macOS 10.15, *)
    init(context: any AccountContextProtocol, environment: WalletUIEnvironment, subject: WalletTransactionSubject, previewTimestamp: Int32, transferGaslessMinAmount: Int64, sendToCounterparty: @escaping (Int64?, String?) -> Void, decryptComment: @escaping () -> Void, toggleEncryptComment: @escaping () -> Void, toggleCommentExpansion: @escaping () -> Void, copyAddress: @escaping (String) -> Void, commentUpdated: @escaping (String) -> Void, showFeeInfo: @escaping () -> Void, showWhatsGram: @escaping ((() -> NSView?)?) -> Void) {
        self.commentUpdated = commentUpdated
        self.showFeeInfo = showFeeInfo
        self.showWhatsGram = showWhatsGram
        self.context = context
        self.environment = environment
        self.subject = subject
        self.previewTimestamp = previewTimestamp
        self.transferGaslessMinAmount = transferGaslessMinAmount
        self.sendToCounterparty = sendToCounterparty
        self.decryptComment = decryptComment
        self.toggleEncryptComment = toggleEncryptComment
        self.toggleCommentExpansion = toggleCommentExpansion
        self.copyAddress = copyAddress
        if case .transaction = subject {
            self.intro = WalletOpenIntro(rollDuration: WalletTransactionIntro.rollDuration, minimumRollDuration: WalletTransactionIntro.minimumRollDuration, duration: WalletTransactionIntro.duration)
        } else {
            self.intro = nil
        }
    }

    var isPreview: Bool {
        switch subject {
        case .preview, .collectiblePreview:
            return true
        case .transaction:
            return false
        }
    }

    var usesCollectibleModalHeader: Bool {
        if case let .transaction(transaction) = subject {
            return transaction.kind != .keyChange && transaction.collectible != nil
        }
        return false
    }
}

private enum PreviewOperation: Equatable {
    case ready
    case preparing
    case submitting
    case pending
    case submissionUnknown
    case confirmed

    var isTerminal: Bool {
        switch self {
        case .submissionUnknown, .confirmed:
            return true
        default:
            return false
        }
    }
}

@available(macOS 10.15, *)
private struct State: Equatable {
    var walletState: WalletContext.State?
    var transaction: WalletContext.Transaction?
    var preparedTransfer: WalletContext.PreparedTransfer?
    var displayedFee: Int64?
    var previewOperation: PreviewOperation = .ready
    var comment: String = ""
    var decryptedComment: String? = nil
    var isDecryptingComment: Bool = false
    var encryptComment: Bool = false
    var isAuthorizingComment: Bool = false
    var isCommentExpanded: Bool = false
    var accountAvatar: CGImage? = nil
}

func walletCommentPrivacyDescription(encrypted: Bool) -> String {
    return encrypted ? strings().walletTransactionControllerCommentEncryptedPrivacy : strings().walletTransactionControllerCommentPublicPrivacy
}

@available(macOS 10.15, *)
private func walletTransactionDisplayCollectible(_ collectible: WalletContext.Transaction.CollectibleTransfer) -> WalletContext.Collectible {
    let kind: WalletContext.Collectible.Kind
    let subtitle: String
    switch collectible.kind {
    case .gift:
        kind = .gift
        subtitle = strings().walletTransactionControllerCollectibleGift
    case .username:
        kind = .username
        subtitle = strings().walletTransactionControllerUsername
    case .anonymousNumber:
        kind = .anonymousNumber
        subtitle = strings().walletTransactionControllerAnonymousNumber
    case .other:
        kind = .other
        subtitle = strings().walletTransactionControllerNft
    }
    return WalletContext.Collectible(
        address: collectible.address,
        name: collectible.name,
        subtitle: subtitle,
        kind: kind,
        collectionName: collectible.collectionName,
        collectionUrl: collectible.collectionUrl,
        giftSlug: collectible.nft?.gift?.slug ?? (kind == .gift ? walletCollectibleGiftSlug(name: collectible.name) : nil),
        nft: collectible.nft
    )
}

@available(macOS 10.15, *)
private func walletTransactionHeroCollectible(_ state: State, arguments: Arguments, transaction: WalletContext.Transaction) -> WalletContext.Collectible? {
    switch arguments.subject {
    case let .collectiblePreview(_, _, collectible):
        return state.preparedTransfer?.collectible ?? collectible
    case .transaction:
        return transaction.collectible.map(walletTransactionDisplayCollectible)
    case .preview:
        return nil
    }
}

func walletPreviewAmount(preparedAmount: Int64?, amount: Int64, sendAll: Bool, displayedFee: Int64?) -> Int64 {
    return preparedAmount ?? (sendAll ? max(0, amount - (displayedFee ?? 0)) : amount)
}

@available(macOS 10.15, *)
func walletPreviewGasless(isSelfTransfer: Bool, isSendAll: Bool, isPrepared: Bool, displayedFee: Int64?, amount: Int64, gaslessInfo: WalletGaslessInfo?, minimumAmount: Int64) -> Bool {
    guard !isSelfTransfer, !isSendAll || isPrepared || displayedFee != nil else {
        return false
    }
    return WalletContext.isGaslessEligible(amount: amount, gaslessInfo: gaslessInfo, minimumAmount: minimumAmount)
}

@available(macOS 10.15, *)
func walletPreviewEstimatedFee(subject: WalletTransactionSubject, sendAll: Bool, hasPreparedTransfer: Bool, needsRefresh: Bool, previewAge: TimeInterval, comment: String?, encryptComment: Bool) -> Int64? {
    guard case let .preview(_, _, _, subjectComment, initialFee) = subject, !sendAll, !hasPreparedTransfer,
          !needsRefresh, previewAge >= 0, previewAge < 300,
          comment == walletTransactionComment(subjectComment), !encryptComment else {
        return nil
    }
    return initialFee
}

@available(macOS 10.15, *)
func walletPreviewBalanceError(balance: Int64?, requestedAmount: Int64, sendAll: Bool) -> WalletContext.WalletError? {
    guard let balance, requestedAmount <= balance else {
        return .insufficientBalance(required: requestedAmount)
    }
    if sendAll && balance != requestedAmount {
        return .previewFailed
    }
    return nil
}

enum WalletTransactionFeeDisplay: Equatable {
    case none
    case placeholder
    case fee(Int64)
    case free
}

func walletTransactionFeeDisplay(isPreview: Bool, displayedFee: Int64?, transactionFee: Int64, isSelfTransfer: Bool, isOutgoing: Bool, gasless: Bool) -> WalletTransactionFeeDisplay {
    let fee: Int64? = isPreview ? displayedFee : transactionFee
    if isSelfTransfer || (isOutgoing && !gasless) {
        guard let fee else {
            return .placeholder
        }
        return fee > 0 ? .fee(fee) : .none
    }
    if !isPreview, gasless, isOutgoing {
        return .free
    }
    return .none
}

@available(macOS 10.15, *)
private func displayTransaction(_ state: State, arguments: Arguments) -> WalletContext.Transaction {
    if let transaction = state.transaction {
        return transaction
    }
    switch arguments.subject {
    case let .transaction(transaction):
        return transaction
    case let .preview(address, amount, sendAll, comment, _):
        let previewAmount = walletPreviewAmount(preparedAmount: state.preparedTransfer?.amount, amount: amount, sendAll: sendAll, displayedFee: state.displayedFee)
        let recipient = state.preparedTransfer?.recipient ?? address
        let gasless: Bool
        if case let .wallet(info) = state.walletState?.phase {
            gasless = walletPreviewGasless(
                isSelfTransfer: WalletContext.isSelfTransfer(recipient: recipient, walletAddress: info.address),
                isSendAll: state.preparedTransfer?.isSendAll ?? sendAll,
                isPrepared: state.preparedTransfer != nil,
                displayedFee: state.displayedFee,
                amount: previewAmount,
                gaslessInfo: state.walletState?.gaslessInfo.currentValue,
                minimumAmount: arguments.transferGaslessMinAmount
            )
        } else {
            gasless = false
        }
        return WalletContext.Transaction(
            id: "",
            logicalTime: "",
            timestamp: arguments.previewTimestamp,
            direction: .outgoing,
            amount: previewAmount,
            fee: state.displayedFee ?? 0,
            gasless: gasless,
            peer: .address(recipient, domain: nil),
            comment: walletTransactionComment(state.comment) ?? comment
        )
    case let .collectiblePreview(address, recipientPeer, collectible):
        let recipient = state.preparedTransfer?.recipient ?? address
        return WalletContext.Transaction(
            id: "",
            logicalTime: "",
            timestamp: arguments.previewTimestamp,
            direction: .outgoing,
            amount: 0,
            fee: state.displayedFee ?? 0,
            peer: walletPreviewTransactionPeer(recipient: recipient, recipientPeer: recipientPeer),
            comment: walletTransactionComment(state.comment),
            collectible: WalletContext.Transaction.CollectibleTransfer(collectible: collectible)
        )
    }
}

@available(macOS 10.15, *)
private func updatedWalletTransaction(_ transaction: WalletContext.Transaction, in transactions: [WalletContext.Transaction]) -> WalletContext.Transaction? {
    if let exact = transactions.first(where: { $0.id == transaction.id }) {
        return exact
    }
    if let presented = transactions.first(where: { $0.presentationId == transaction.presentationId }) {
        return presented
    }
    if let matched = transactions.first(where: { $0.matchesHistoryTransaction(transaction) }) {
        return matched
    }
    guard let externalMessageHash = transaction.externalMessageHash else {
        return nil
    }
    return transactions.first(where: { candidate in
        guard walletTransactionHashesEqual(candidate.externalMessageHash, externalMessageHash),
              candidate.direction == transaction.direction,
              candidate.currency == transaction.currency,
              candidate.amount == transaction.amount else {
            return false
        }
        if let candidateAddress = candidate.peer.address, let transactionAddress = transaction.peer.address {
            return walletTransactionAddressesEqual(candidateAddress, transactionAddress)
        }
        return true
    })
}

func walletCommentBubblePath(_ size: NSSize, incoming: Bool) -> CGPath {
    let rect = NSRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
    let scale = min(rect.height, 35) / 35
    let radius = 17.5 * scale
    let right = rect.maxX - 6 * scale
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        return CGPoint(x: right + x * scale, y: rect.maxY - (35 - y) * scale)
    }
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
    path.addArc(tangent1End: CGPoint(x: right, y: rect.minY), tangent2End: CGPoint(x: right, y: rect.minY + radius), radius: radius)
    path.addLine(to: point(0, 26.86))
    path.addCurve(to: point(6, 35), control1: point(0, 26.86), control2: point(0.03, 31.55))
    path.addCurve(to: point(-6.42, 31.05), control1: point(6, 35), control2: point(-3.06, 34.99))
    path.addCurve(to: point(-17.5, 35), control1: point(-9.44, 33.52), control2: point(-13.29, 35))
    path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: radius)
    path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: right, y: rect.minY), radius: radius)
    path.closeSubpath()
    guard incoming else {
        return path
    }
    var mirror = CGAffineTransform(translationX: size.width, y: 0).scaledBy(x: -1, y: 1)
    return path.copy(using: &mirror) ?? path
}

private let walletTransactionCommentToggleSpacing: CGFloat = 12
private let walletTransactionCommentMinimumTextWidth: CGFloat = 40

final class WalletTransactionCommentRowItem: GeneralRowItem {
    static let collapsedLineCount: Int32 = 3

    fileprivate private(set) var textLayout: TextViewLayout
    fileprivate let fullLayout: TextViewLayout
    fileprivate let collapsedLayout: TextViewLayout
    fileprivate let toggleLayout: TextViewLayout
    fileprivate let isSpoiler: Bool
    fileprivate let isDecrypting: Bool
    fileprivate let isExpanded: Bool
    fileprivate private(set) var isCollapsible: Bool = false
    fileprivate private(set) var showsToggle: Bool = false
    fileprivate let incoming: Bool
    fileprivate let onReveal: (() -> Void)?
    fileprivate let onToggleExpansion: (() -> Void)?

    init(_ initialSize: NSSize, stableId: AnyHashable, comment: String, incoming: Bool, isSpoiler: Bool = false, isRevealed: Bool = false, isDecrypting: Bool = false, isExpanded: Bool = false, onReveal: (() -> Void)? = nil, onToggleExpansion: (() -> Void)? = nil) {
        let attributed = NSMutableAttributedString()
        attributed.append(string: comment, color: theme.colors.text, font: .normal(.text))
        if isSpoiler || isRevealed {
            attributed.addAttribute(TextInputAttributes.spoiler, value: true as NSNumber, range: attributed.range)
        }
        self.fullLayout = TextViewLayout(attributed, spoilerColor: theme.colors.text, isSpoilerRevealed: isRevealed)
        self.collapsedLayout = TextViewLayout(attributed, maximumNumberOfLines: WalletTransactionCommentRowItem.collapsedLineCount, truncationType: .end, spoilerColor: theme.colors.text, isSpoilerRevealed: isRevealed)
        self.textLayout = self.fullLayout
        let toggleTitle = strings().walletTransactionControllerShowMore
        self.toggleLayout = TextViewLayout(.initialize(string: toggleTitle, color: walletClassicAccent, font: .medium(.text)), maximumNumberOfLines: 1)
        self.isSpoiler = isSpoiler
        self.isDecrypting = isDecrypting
        self.isExpanded = isExpanded
        self.incoming = incoming
        self.onReveal = onReveal
        self.onToggleExpansion = onToggleExpansion
        super.init(initialSize, stableId: stableId, viewType: .singleItem)
    }

    fileprivate var toggleSize: NSSize {
        return NSMakeSize(toggleLayout.layoutSize.width + walletTransactionCommentToggleSpacing, toggleLayout.layoutSize.height)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        let textWidth = min(280, blockWidth - 80)
        toggleLayout.measure(width: textWidth)
        fullLayout.measure(width: textWidth)
        isCollapsible = !isExpanded && fullLayout.lines.count > Int(WalletTransactionCommentRowItem.collapsedLineCount)
        showsToggle = isCollapsible && !isSpoiler
        if isCollapsible {
            if showsToggle {
                let visibleWidth = fullLayout.lines.prefix(Int(WalletTransactionCommentRowItem.collapsedLineCount)).map { $0.frame.maxX }.max() ?? textWidth
                collapsedLayout.cutout = TextViewCutout(bottomRight: toggleSize)
                collapsedLayout.measure(width: min(textWidth, max(visibleWidth, toggleSize.width + walletTransactionCommentMinimumTextWidth)))
            } else {
                collapsedLayout.cutout = nil
                collapsedLayout.measure(width: textWidth)
            }
            textLayout = collapsedLayout
        } else {
            textLayout = fullLayout
        }
        return true
    }

    override var height: CGFloat {
        return max(34, textLayout.layoutSize.height + 14)
    }

    override func viewClass() -> AnyClass {
        return WalletTransactionCommentRowView.self
    }

    override var accessibilityLabel: String? {
        if isSpoiler {
            return strings().walletTransactionControllerEncryptedComment
        }
        let text = fullLayout.attributedString.string
        return text.isEmpty ? nil : text
    }

    override var accessibilityValue: String? {
        return isDecrypting ? strings().voiceOverCommonLoading : nil
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return isSpoiler || isCollapsible ? .button : .staticText
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }

    override func accessibilityPerformPress() -> Bool {
        if isSpoiler {
            onReveal?()
            return true
        }
        if isCollapsible {
            onToggleExpansion?()
            return true
        }
        return false
    }
}

private let walletCommentRevealTransition: ContainedViewLayoutTransition = .animated(duration: 0.2, curve: .easeOut)
private let walletCommentReplaceScale: CGFloat = 0.85
private let walletCommentReplaceBlur: CGFloat = 5

private func walletCommentReplace(_ view: NSView, appearing: Bool, completion: (() -> Void)? = nil) {
    guard let layer = view.layer, case let .animated(duration, curve) = walletCommentRevealTransition else {
        completion?()
        return
    }
    let opacityFrom: CGFloat = appearing ? 0 : CGFloat(layer.presentation()?.opacity ?? layer.opacity)
    let opacityTo: CGFloat = appearing ? 1 : 0
    let blurFrom: CGFloat = appearing ? walletCommentReplaceBlur : 0
    let blurTo: CGFloat = appearing ? 0 : walletCommentReplaceBlur

    layer.opacity = Float(opacityTo)
    layer.animateAlpha(from: opacityFrom, to: opacityTo, duration: duration, timingFunction: curve.timingFunction, completion: { _ in
        completion?()
    })
    layer.animateScaleCenter(from: appearing ? walletCommentReplaceScale : 1, to: appearing ? 1 : walletCommentReplaceScale, duration: duration, removeOnCompletion: appearing, timingFunction: curve.timingFunction)
    if let blur = ee2_makeBlurFilter() {
        blur.setValue(blurTo as NSNumber, forKey: "inputRadius")
        layer.filters = [blur]
        layer.animate(from: blurFrom as NSNumber, to: blurTo as NSNumber, keyPath: "filters.gaussianBlur.inputRadius", timingFunction: curve.timingFunction, duration: duration, completion: { [weak layer] _ in
            if appearing {
                layer?.filters = nil
            }
        })
    }
}

final class WalletTransactionCommentRowView: GeneralRowView {
    private let bubbleView = WalletSendCommentBackgroundView(frame: .zero)
    private var textView = TextView()
    private var dustView: TextView?
    private let toggleView = TextView()
    private let revealControl = Control()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        textView.userInteractionEnabled = false
        textView.isSelectable = false
        toggleView.userInteractionEnabled = false
        toggleView.isSelectable = false

        addSubview(bubbleView)
        addSubview(textView)
        addSubview(toggleView)
        addSubview(revealControl)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        let previous = self.item as? WalletTransactionCommentRowItem
        super.set(item: item, animated: animated)

        guard let item = item as? WalletTransactionCommentRowItem else {
            return
        }

        let transition: ContainedViewLayoutTransition = animated ? walletCommentRevealTransition : .immediate
        if animated, let previous, previous.stableId == item.stableId, previous.isSpoiler, !item.isSpoiler {
            let dustView = textView
            let revealedView = TextView()
            revealedView.userInteractionEnabled = false
            revealedView.isSelectable = false
            revealedView.update(item.textLayout)
            revealedView.setFrameOrigin(NSMakePoint(floorToScreenPixels(backingScaleFactor, dustView.frame.midX - revealedView.frame.width / 2), floorToScreenPixels(backingScaleFactor, dustView.frame.midY - revealedView.frame.height / 2)))
            addSubview(revealedView, positioned: .above, relativeTo: dustView)
            textView = revealedView
            self.dustView = dustView
            walletCommentReplace(revealedView, appearing: true)
            walletCommentReplace(dustView, appearing: false, completion: { [weak self, weak dustView] in
                dustView?.removeFromSuperview()
                if let self, self.dustView === dustView {
                    self.dustView = nil
                }
            })
        } else {
            textView.update(item.textLayout)
        }
        let dustAlpha: CGFloat = item.isSpoiler && item.isDecrypting ? 0.25 : 1.0
        if CGFloat(textView.layer?.opacity ?? 1.0) != dustAlpha {
            transition.updateAlpha(view: textView, alpha: dustAlpha)
        }

        toggleView.update(item.toggleLayout)
        toggleView.isHidden = !item.showsToggle
        let isInteractive = item.isSpoiler || item.isCollapsible
        revealControl.setAccessibilityLabel(item.isSpoiler ? strings().walletTransactionControllerEncryptedComment : strings().walletTransactionControllerShowMore)
        revealControl.isEventLess = !isInteractive
        revealControl.userInteractionEnabled = isInteractive
        revealControl.removeAllHandlers()
        revealControl.set(handler: { [weak item] _ in
            guard let item else {
                return
            }
            if item.isSpoiler {
                item.onReveal?()
            } else if item.isCollapsible {
                item.onToggleExpansion?()
            }
        }, for: .Click)
        updateLayout(size: frame.size, transition: transition)
    }

    override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }

    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)

        guard let item = item as? WalletTransactionCommentRowItem else {
            return
        }

        let lastLineEdge = item.textLayout.lines.last?.frame.maxX ?? 0
        let textWidth = item.showsToggle ? max(item.textLayout.layoutSize.width, lastLineEdge + item.toggleSize.width) : item.textLayout.layoutSize.width
        let bubbleWidth = textWidth + 34
        let bubbleFrame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (size.width - bubbleWidth) / 2 + (item.incoming ? -3 : 3)), 0, bubbleWidth, item.height)
        bubbleView.update(size: bubbleFrame.size, incoming: item.incoming)
        transition.updateFrame(view: bubbleView, frame: bubbleFrame)
        let textY = floorToScreenPixels(backingScaleFactor, (item.height - item.textLayout.layoutSize.height) / 2)
        let textFrame = CGRect(origin: NSMakePoint(floorToScreenPixels(backingScaleFactor, (size.width - textWidth) / 2), textY), size: textView.frame.size)
        transition.updateFrame(view: textView, frame: textFrame)
        if let dustView {
            let dustSize = dustView.frame.size
            transition.updateFrame(view: dustView, frame: CGRect(origin: NSMakePoint(floorToScreenPixels(backingScaleFactor, textFrame.midX - dustSize.width / 2), floorToScreenPixels(backingScaleFactor, textFrame.midY - dustSize.height / 2)), size: dustSize))
        }
        transition.updateFrame(view: toggleView, frame: CGRect(origin: NSMakePoint(textFrame.minX + lastLineEdge + walletTransactionCommentToggleSpacing, textY + item.textLayout.layoutSize.height - item.toggleLayout.layoutSize.height), size: toggleView.frame.size))
        revealControl.frame = bubbleFrame
    }
}

private let walletTransactionLinkVerticalInset: CGFloat = 8

private final class WalletTransactionLinkRowItem: GeneralRowItem {
    fileprivate let titleLayout: TextViewLayout
    fileprivate let morphAction: ((() -> NSView?)?) -> Void

    init(_ initialSize: NSSize, stableId: AnyHashable, title: String, action: @escaping ((() -> NSView?)?) -> Void) {
        self.titleLayout = TextViewLayout(.initialize(string: title, color: walletClassicAccent, font: .normal(.short)), maximumNumberOfLines: 1)
        self.morphAction = action
        super.init(initialSize, stableId: stableId, action: { action(nil) }, drawCustomSeparator: false)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        titleLayout.measure(width: max(60, width - 40))
        return true
    }

    override var height: CGFloat {
        return titleLayout.layoutSize.height + walletTransactionLinkVerticalInset * 2
    }

    override func viewClass() -> AnyClass {
        return WalletTransactionLinkRowView.self
    }

    override var accessibilityLabel: String? {
        let title = titleLayout.attributedString.string
        return title.isEmpty ? nil : title
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

private final class WalletTransactionLinkRowView: GeneralRowView {
    private let control = Control()
    private let titleView = TextView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        control.scaleOnClick = true
        control.addSubview(titleView)
        control.set(handler: { [weak self] _ in
            guard let item = self?.item as? WalletTransactionLinkRowItem else {
                return
            }
            item.morphAction({ [weak self] in self?.control })
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
        guard let item = item as? WalletTransactionLinkRowItem else {
            return
        }
        titleView.update(item.titleLayout)
        control.setAccessibilityLabel(item.titleLayout.attributedString.string)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? WalletTransactionLinkRowItem else {
            return
        }
        control.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - item.titleLayout.layoutSize.width - 20) / 2), 0, item.titleLayout.layoutSize.width + 20, frame.height)
        titleView.center()
    }
}

@available(macOS 10.15, *)
private struct AmountData: Equatable {
    let amount: Int64
    let direction: WalletContext.Transaction.Direction
    let currency: WalletContext.Transaction.Currency
    let fiatText: String?
    let isPending: Bool
    let isFailed: Bool
}

private struct DetailsData: Equatable {
    let counterpartyTitle: String
    let counterpartyValue: String?
    let counterpartyPeerId: Int64?
    let counterpartyAddress: String?
    let counterpartyAvatar: CGImage?
    let canSend: Bool
    let feeText: String?
    let feeFiat: String?
    let feeIsFree: Bool
    let feeIsLoading: Bool
    let dateText: String
}

private let _id_amount = InputDataIdentifier("_id_amount")
private let _id_collectible_hero = InputDataIdentifier("_id_collectible_hero")
private let _id_key_update_header = InputDataIdentifier("_id_key_update_header")
private let _id_comment_bubble = InputDataIdentifier("_id_comment_bubble")
private let _id_details = InputDataIdentifier("_id_details")
private let _id_comment_input = InputDataIdentifier("_id_comment_input")
private let _id_encrypt_comment = InputDataIdentifier("_id_encrypt_comment")
private let _id_whats_gram = InputDataIdentifier("_id_whats_gram")

@available(macOS 10.15, *)
private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []

    var sectionId: Int32 = 0
    var index: Int32 = 0

    let transaction = displayTransaction(state, arguments: arguments)
    let heroCollectible = walletTransactionHeroCollectible(state, arguments: arguments, transaction: transaction)
    let showsAmountHero = transaction.kind != .keyChange && heroCollectible == nil

    if !arguments.usesCollectibleModalHeader {
        entries.append(.sectionId(sectionId, type: .customModern(showsAmountHero ? 8 : 20)))
        sectionId += 1
    }

    let isPreview = arguments.isPreview
    let showsTransactionDetails = !isPreview || state.previewOperation.isTerminal

    let walletAddress: String?
    if case let .wallet(info) = state.walletState?.phase {
        walletAddress = info.address
    } else {
        walletAddress = nil
    }
    let isSelfTransfer = transaction.isSelfTransfer(walletAddress: walletAddress)
    let displayedDirection: WalletContext.Transaction.Direction = isSelfTransfer && showsTransactionDetails ? .incoming : transaction.direction

    let fiatCurrency = state.walletState?.fiat.selectedCurrency ?? .usd
    let fiatRate = state.walletState?.fiat.selectedRate

    var fiatText: String? = nil
    if let fiatRate = fiatRate {
        switch transaction.currency {
        case .ton:
            fiatText = formatTonFiatValue(abs(transaction.amount), rate: fiatRate.unitsPerGram, currencySymbol: fiatCurrency.symbol)
        case .usdt:
            fiatText = formatFiatValue(Double(abs(transaction.amount)) / 1_000_000 * fiatRate.unitsPerUsd, currencySymbol: fiatCurrency.symbol)
        }
    }

    if transaction.kind == .keyChange {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_key_update_header, equatable: nil, comparable: nil, item: { initialSize, stableId in
            return WalletTransactionKeyUpdateRowItem(initialSize, stableId: stableId)
        }))
    } else if let collectible = heroCollectible {
        let media = transaction.collectible
        var subtitle: String? = collectible.kind == .other ? collectible.collectionName : nil
        if case .telegramGift(true) = transaction.peer {
            subtitle = displayedDirection == .incoming ? strings().walletTransactionRowItemMovedFromProfile : strings().walletTransactionRowItemMovedToProfile
        }
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_collectible_hero, equatable: .init(collectible), comparable: nil, item: { initialSize, stableId in
            let item = WalletCollectibleHeroRowItem(initialSize, stableId: stableId, context: arguments.context, environment: arguments.environment, collectible: collectible, displaysGift: collectible.nft?.gift != nil || collectible.giftSlug != nil, subtitle: subtitle, image: media?.image, lottie: media?.lottie, collectionAction: collectible.collectionUrl.map { url in
                { arguments.environment.openExternalURL(url) }
            })
            if arguments.usesCollectibleModalHeader {
                item.updateHeader = { arguments.updateHeader($0, $1) }
                item.close = { arguments.close() }
            }
            return item
        }))
    } else {
        let amountData = AmountData(
            amount: transaction.amount,
            direction: displayedDirection,
            currency: transaction.currency,
            fiatText: fiatText,
            isPending: !isPreview && transaction.status == .pending && transaction.collectible == nil,
            isFailed: !isPreview && transaction.status == .failed
        )
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_amount, equatable: .init(amountData), comparable: nil, item: { initialSize, stableId in
            let item = WalletTransactionAmountRowItem(
                initialSize,
                stableId: stableId,
                amount: amountData.amount,
                direction: amountData.direction,
                currency: amountData.currency,
                fiatText: amountData.fiatText,
                isPending: amountData.isPending,
                isFailed: amountData.isFailed,
                viewType: .singleItem
            )
            item.intro = arguments.intro
            return item
        }))
    }
    index += 1

    struct CommentTuple: Equatable {
        let text: String
        let incoming: Bool
        let isSpoiler: Bool
        let isRevealed: Bool
        let isDecrypting: Bool
        let isExpanded: Bool
    }
    let isCommentEncrypted = transaction.commentEncrypted && transaction.comment?.isEmpty == false
    let displayedComment = isCommentEncrypted ? state.decryptedComment : walletTransactionComment(transaction.comment)
    let hasEncryptedComment = isCommentEncrypted && state.decryptedComment == nil
    let isTelegramGift: Bool
    if case .telegramGift = transaction.peer {
        isTelegramGift = true
    } else {
        isTelegramGift = false
    }
    if showsTransactionDetails, !isTelegramGift, displayedComment != nil || hasEncryptedComment {
        entries.append(.sectionId(sectionId, type: .customModern(16)))
        sectionId += 1

        let tuple = CommentTuple(
            text: displayedComment ?? strings().walletTransactionControllerEncryptedComment,
            incoming: displayedDirection == .incoming,
            isSpoiler: displayedComment == nil,
            isRevealed: isCommentEncrypted && state.decryptedComment != nil,
            isDecrypting: state.isDecryptingComment,
            isExpanded: state.isCommentExpanded
        )
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_comment_bubble, equatable: .init(tuple), comparable: nil, item: { initialSize, stableId in
            return WalletTransactionCommentRowItem(initialSize, stableId: stableId, comment: tuple.text, incoming: tuple.incoming, isSpoiler: tuple.isSpoiler, isRevealed: tuple.isRevealed, isDecrypting: tuple.isDecrypting, isExpanded: tuple.isExpanded, onReveal: arguments.decryptComment, onToggleExpansion: arguments.toggleCommentExpansion)
        }))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .customModern(16)))
    sectionId += 1

    let counterpartyTitle = walletTransactionCounterpartyTitle(isUnfinishedPreview: isPreview && !state.previewOperation.isTerminal, peer: transaction.peer, direction: displayedDirection)

    var feeText: String? = nil
    var feeFiat: String? = nil
    var feeIsFree = false
    var feeIsLoading = false
    switch walletTransactionFeeDisplay(isPreview: isPreview, displayedFee: state.displayedFee, transactionFee: transaction.fee, isSelfTransfer: isSelfTransfer, isOutgoing: transaction.direction == .outgoing, gasless: transaction.gasless) {
    case let .fee(fee):
        feeText = formatTonAmountText(fee, maxDecimalPositions: 5)
        if let fiatRate = fiatRate {
            feeFiat = "~ " + formatTonFiatValuePrecise(fee, rate: fiatRate.unitsPerGram, currencySymbol: fiatCurrency.symbol)
        }
    case .free:
        feeIsFree = true
    case .placeholder:
        feeIsLoading = true
    case .none:
        break
    }

    let counterpartyValue: String?
    var counterpartyPeerId: Int64? = nil
    var counterpartyAddress: String? = nil
    switch transaction.peer {
    case let .user(peer, address, _), let .channel(peer, address, _):
        counterpartyValue = arguments.environment.peerTitle(peer._asPeer(), compact: false)
        counterpartyPeerId = peer.id.toInt64()
        counterpartyAddress = address.isEmpty ? nil : address
    case let .address(address, _):
        counterpartyValue = transaction.peer.domain
        counterpartyAddress = address
    case let .onramp(address, _, providerName):
        counterpartyValue = providerName
        counterpartyAddress = address
    case let .telegramGift(ownProfile):
        counterpartyValue = ownProfile ? arguments.context.myPeer.map { arguments.environment.peerTitle($0, compact: false) } ?? strings().walletTransactionRowItemTelegram : strings().walletTransactionRowItemTelegram
        counterpartyPeerId = ownProfile ? arguments.context.peerId.toInt64() : nil
    case .unsupported:
        counterpartyValue = nil
    }
    let canSendToPeer: Bool
    switch transaction.peer {
    case .user:
        canSendToPeer = true
    case .address:
        canSendToPeer = transaction.peer.address != nil
    case .channel, .onramp, .telegramGift, .unsupported:
        canSendToPeer = false
    }
    let detailsData = DetailsData(
        counterpartyTitle: counterpartyTitle,
        counterpartyValue: counterpartyValue,
        counterpartyPeerId: counterpartyPeerId,
        counterpartyAddress: counterpartyAddress,
        counterpartyAvatar: {
            if case .telegramGift(true) = transaction.peer { return state.accountAvatar }
            return nil
        }(),
        canSend: !isPreview && transaction.kind != .keyChange && canSendToPeer && displayedDirection != .unknown,
        feeText: feeText,
        feeFiat: feeFiat,
        feeIsFree: feeIsFree,
        feeIsLoading: feeIsLoading,
        dateText: walletTransactionDateText(transaction.timestamp, environment: arguments.environment)
    )
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_details, equatable: .init(detailsData), comparable: nil, item: { initialSize, stableId in
        var rows: [WalletDetailsTableRowItem.Row] = []
        let sendAction: (title: String, handler: () -> Void)?
        if detailsData.canSend, detailsData.counterpartyPeerId != nil || detailsData.counterpartyAddress != nil {
            let peerId = detailsData.counterpartyPeerId
            let sendAddress = detailsData.counterpartyAddress
            sendAction = (title: strings().walletTransactionControllerSend, handler: { arguments.sendToCounterparty(peerId, sendAddress) })
        } else {
            sendAction = nil
        }
        let addressTitle = strings().walletTransactionControllerAddress
        let addressRow: (String, (title: String, handler: () -> Void)?) -> WalletDetailsTableRowItem.Row? = { label, action in
            guard let address = detailsData.counterpartyAddress else {
                return nil
            }
            return WalletDetailsTableRowItem.Row(
                label: label,
                value: address,
                isAddress: true,
                onClick: {
                    arguments.copyAddress(address)
                },
                action: action
            )
        }
        if let counterpartyValue = detailsData.counterpartyValue {
            if let peerId = detailsData.counterpartyPeerId {
                let context = arguments.context
                rows.append(WalletDetailsTableRowItem.Row(
                    label: detailsData.counterpartyTitle,
                    value: counterpartyValue,
                    icon: detailsData.counterpartyAvatar,
                    valueColor: walletClassicAccent,
                    onClick: {
                        closeAllModals(window: context.window)
                        arguments.environment.openChat(PeerId(peerId))
                    },
                    action: sendAction
                ))
            } else {
                rows.append(WalletDetailsTableRowItem.Row(label: detailsData.counterpartyTitle, value: counterpartyValue, action: sendAction))
            }
            if let row = addressRow(addressTitle, nil) {
                rows.append(row)
            }
        } else if let row = addressRow(detailsData.counterpartyTitle, sendAction) {
            rows.append(row)
        } else {
            let unknownAddress = strings().walletTransactionControllerUnknownAddress
            rows.append(WalletDetailsTableRowItem.Row(label: detailsData.counterpartyTitle, value: unknownAddress))
        }
        let feeTitle = strings().walletTransactionControllerFee
        if detailsData.feeIsLoading {
            rows.append(WalletDetailsTableRowItem.Row(label: feeTitle, value: "", isLoading: true))
        } else if detailsData.feeIsFree || detailsData.feeText != nil {
            let freeText = strings().walletTransactionControllerFeeFree
            rows.append(WalletDetailsTableRowItem.Row(
                label: feeTitle,
                value: detailsData.feeText ?? freeText,
                icon: NSImage(named: "Wallet_TransactionGram")?.precomposed(),
                secondaryValue: detailsData.feeFiat,
                action: detailsData.feeIsFree ? (title: "?", handler: arguments.showFeeInfo) : nil
            ))
        }
        let dateTitle = strings().walletTransactionControllerDate
        rows.append(WalletDetailsTableRowItem.Row(label: dateTitle, value: detailsData.dateText))
        let item = WalletDetailsTableRowItem(initialSize, stableId: stableId, rows: rows, viewType: .singleItem)
        item.intro = arguments.intro
        return item
    }))
    index += 1

    if isPreview && !state.previewOperation.isTerminal {
        entries.append(.sectionId(sectionId, type: .customModern(16)))
        sectionId += 1

        let commentPlaceholder = strings().walletTransactionControllerCommentPlaceholder
        if transaction.collectible == nil {
            struct CommentInputTuple: Equatable {
                let comment: String
                let encrypted: Bool
                let lockEnabled: Bool
            }
            let canEdit = state.previewOperation == .ready || state.previewOperation == .preparing
            let tuple = CommentInputTuple(comment: state.comment, encrypted: state.encryptComment, lockEnabled: canEdit && !state.isAuthorizingComment)
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_comment_input, equatable: .init(tuple), comparable: nil, item: { initialSize, stableId in
                return WalletCommentInputRowItem(initialSize, stableId: stableId, viewType: .singleItem, currentText: tuple.comment, inputPlaceholder: commentPlaceholder, commentEncrypted: tuple.encrypted, lockEnabled: tuple.lockEnabled, lockDescription: walletCommentPrivacyDescription(encrypted: tuple.encrypted), limit: Int32(walletCommentMaximumBytes), updated: { text in
                    arguments.commentUpdated(text)
                }, toggleEncryption: arguments.toggleEncryptComment)
            }))
        } else {
            entries.append(.input(sectionId: sectionId, index: index, value: .string(state.comment), error: nil, identifier: _id_comment_input, mode: .plain, data: .init(viewType: .singleItem, customTheme: GeneralRowItem.Theme(backgroundColor: theme.colors.grayBackground)), placeholder: nil, inputPlaceholder: commentPlaceholder, filter: walletCommentInputFilter, limit: Int32(walletCommentMaximumBytes)))
        }
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .customModern(3)))
    sectionId += 1

    let whatsGramTitle = strings().walletTransactionControllerWhatsGram
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_whats_gram, equatable: nil, comparable: nil, item: { initialSize, stableId in
        return WalletTransactionLinkRowItem(initialSize, stableId: stableId, title: whatsGramTitle, action: arguments.showWhatsGram)
    }))
    index += 1

    entries.append(.sectionId(sectionId, type: .customModern(3)))
    sectionId += 1

    return entries
}

@available(macOS 10.15, *)
public func WalletTransactionController(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, subject: WalletTransactionSubject, origin: WalletTransactionOrigin = .wallet, decryptCommentOnOpen: Bool = false, transferAnimation: WalletSendTransferAnimation? = nil, onSuccess: (() -> Void)? = nil) -> InputDataModalController {
    let actionsDisposable = DisposableSet()
    let transferDisposable = MetaDisposable()
    let returnToWalletDisposable = MetaDisposable()
    actionsDisposable.add(returnToWalletDisposable)
    actionsDisposable.add(transferDisposable)
    let discardDisposables = DisposableSet()
    actionsDisposable.add(discardDisposables)
    if case .transaction = subject {
        actionsDisposable.add(walletContext.beginWalletScreenUpdates())
    } else if case .preview = subject {
        actionsDisposable.add(walletContext.beginGaslessInfoUpdates())
    }

    let isPreview: Bool
    let subjectAddress: String
    let subjectAmount: Int64
    let subjectSendAll: Bool
    let initialComment: String?
    let subjectCollectible: WalletContext.Collectible?
    var subjectRecipientName: String? = nil
    switch subject {
    case let .transaction(transaction):
        isPreview = false
        subjectAddress = transaction.peer.address ?? ""
        subjectAmount = transaction.amount
        subjectSendAll = false
        initialComment = nil
        subjectCollectible = nil
    case let .preview(address, amount, sendAll, comment, _):
        isPreview = true
        subjectAddress = address
        subjectAmount = amount
        subjectSendAll = sendAll
        initialComment = comment
        subjectCollectible = nil
    case let .collectiblePreview(address, recipientPeer, collectible):
        isPreview = true
        subjectAddress = address
        subjectAmount = 0
        subjectSendAll = false
        initialComment = nil
        subjectCollectible = collectible
        subjectRecipientName = recipientPeer.map { environment.peerTitle($0._asPeer(), compact: false) }
    }

    let previewTimestamp = Int32(Date().timeIntervalSince1970)

    var initialState = State()
    initialState.walletState = walletContext.stateValue
    initialState.comment = initialComment ?? ""
    if case let .transaction(transaction) = subject {
        initialState.transaction = transaction
    } else if case let .preview(_, _, _, _, initialFee) = subject {
        initialState.displayedFee = initialFee
    }

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    if let transaction = initialState.transaction, case .telegramGift(true) = transaction.peer, let peer = context.myPeer {
        actionsDisposable.add((environment.ownerAvatar(peer, size: NSMakeSize(WalletDetailsTableRowItem.iconSize * System.backingScale, WalletDetailsTableRowItem.iconSize * System.backingScale), font: .avatar(8))
        |> deliverOnMainQueue).start(next: { avatar in
            updateState { current in
                var current = current
                current.accountAvatar = avatar
                return current
            }
        }))
    }

    var close: (() -> Void)? = nil
    var getController: (() -> InputDataController?)? = nil

    let decryptCommentDisposable = MetaDisposable()
    actionsDisposable.add(decryptCommentDisposable)
    let restoreAuthorization = WalletFlowAuthorization(walletContext: walletContext, reason: walletRestoreFlowReason)

    let commentSessionDisposable = MetaDisposable()
    actionsDisposable.add(commentSessionDisposable)
    var commentSession: PasscodeSession? = nil
    var commentSessionGeneration: UInt64 = 0
    var commentSessionHandedOff = false

    var decryptComment: (() -> Void)?
    let runDecryptComment: () -> Void = {
        let state = stateValue.with { $0 }
        guard !state.isDecryptingComment, state.decryptedComment == nil,
              let transaction = state.transaction,
              transaction.commentEncrypted, transaction.comment?.isEmpty == false else {
            return
        }
        let targetWindow = context.window
        let finish: (WalletContext.WalletError?) -> Void = { error in
            updateState { current in
                var current = current
                current.isDecryptingComment = false
                return current
            }
            guard let error, error != .authorizationCancelled else {
                return
            }
            let message = walletAuthorizationErrorMessage(error)
            environment.alert(for: targetWindow, header: message?.title ?? strings().walletTransactionControllerDecryptFailedTitle, info: message?.text ?? strings().walletTransactionControllerDecryptFailedInfo)
        }
        guard case let .wallet(info) = walletContext.stateValue.phase else {
            finish(.unavailable)
            return
        }
        let walletIdentity = (address: info.address, publicKey: info.publicKey)
        let matchesWalletIdentity: (WalletContext.State) -> Bool = { state in
            guard case let .wallet(info) = state.phase else { return false }
            return info.address == walletIdentity.address && info.publicKey == walletIdentity.publicKey
        }
        let runDecryption: () -> Void = {
            if case .wallet = walletContext.stateValue.phase, !matchesWalletIdentity(walletContext.stateValue) {
                finish(.unavailable)
                return
            }
            decryptCommentDisposable.set((walletContext.state
            |> filter { state in
                guard case let .wallet(info) = state.phase else { return false }
                return info.canSign && state.activeOperation == nil && matchesWalletIdentity(state)
            }
            |> take(1)
            |> castError(WalletContext.WalletError.self)
            |> mapToSignal { _ in
                walletContext.decryptTransactionComment(transaction)
            }
            |> deliverOnMainQueue).start(next: { comment in
                guard matchesWalletIdentity(walletContext.stateValue) else {
                    return
                }
                updateState { current in
                    var current = current
                    current.isDecryptingComment = false
                    current.decryptedComment = comment
                    return current
                }
            }, error: { error in
                finish(error)
            }))
        }
        updateState { current in
            var current = current
            current.isDecryptingComment = true
            return current
        }
        if info.canSign {
            restoreAuthorization.end()
            runDecryption()
        } else if info.canExportPhrase {
            decryptCommentDisposable.set(walletRestoreSigningAccess(context: context, environment: environment, window: targetWindow, walletContext: walletContext, authorization: restoreAuthorization, retry: {
                updateState { current in
                    var current = current
                    current.isDecryptingComment = false
                    return current
                }
                decryptComment?()
            }, next: {
                runDecryption()
            }, failed: {
                finish(nil)
            }))
        } else {
            environment.verifyAlert(for: targetWindow, header: strings().walletTransactionControllerSecretPhraseRequiredTitle, information: strings().walletTransactionControllerSecretPhraseRequiredInfo, ok: strings().walletTransactionControllerProceed, cancel: strings().walletTransactionControllerCancel, successHandler: { _ in
                showModal(with: WalletImportController(context: context, environment: environment, walletContext: walletContext, mode: .enterRecoveryPhrase, onImported: {
                    runDecryption()
                }), for: targetWindow)
            }, cancelHandler: {
                finish(nil)
            })
        }
    }
    decryptComment = runDecryptComment

    var commentRevision = 0
    var preparingForSend = false
    var preparedTransferNeedsRefresh = false
    var submittedTransfer: WalletContext.PendingTransfer? = nil
    let baselineTransactionIds = Set<String>()
    var didShowSuccess = false

    var prepareCurrentComment: ((Int?, Bool) -> Void)? = nil
    var submitPrepared: ((WalletContext.PreparedTransfer) -> Void)? = nil
    var performSubmit: ((WalletContext.PreparedTransfer) -> Void)? = nil
    var checkForConfirmation: (() -> Void)? = nil
    var requestCommentSession: ((Bool) -> Void)? = nil
    var previewCommentUpdated: (() -> Void)? = nil

    let presentTransferError: (WalletContext.WalletError?) -> Void = { error in
        let title: String
        let text: String
        switch error {
        case .authorizationCancelled:
            return
        case .insufficientBalance where subjectCollectible != nil:
            environment.verifyAlert(for: context.window, header: strings().walletTransactionControllerNotEnoughGramsTitle, information: strings().walletTransactionControllerCollectibleTopUpInfo, ok: strings().walletTransactionControllerTopUp, cancel: strings().walletTransactionControllerCancel, successHandler: { _ in
                guard case let .wallet(info) = walletContext.stateValue.phase else {
                    return
                }
                showModal(with: WalletReceiveController(context: context, environment: environment, walletContext: walletContext, address: info.address), for: context.window)
            })
            return
        case .commentTooLong:
            title = strings().walletTransactionControllerCommentTooLongTitle
            text = strings().walletTransactionControllerCommentTooLongInfo
        case .commentEncryptionRecipientUnavailable:
            title = strings().walletTransactionControllerEncryptFailedTitle
            text = strings().walletTransactionControllerEncryptRecipientUnavailableInfo
        case .commentEncryptionFailed:
            title = strings().walletTransactionControllerEncryptFailedTitle
            text = strings().walletTransactionControllerEncryptFailedInfo
        default:
            title = strings().walletTransactionControllerTransferFailedTitle
            text = strings().walletTransactionControllerTransferFailedInfo
        }
        environment.alert(for: context.window, header: title, info: text)
    }

    let discardCurrentPreparedTransfer: () -> Void = {
        let previous = stateValue.with { $0.preparedTransfer }
        guard let previous, subjectCollectible == nil else {
            return
        }
        discardDisposables.add(walletContext.discardPreparedTransfer(previous).start())
        updateState { current in
            var current = current
            current.preparedTransfer = nil
            return current
        }
    }

    let invalidateCommentSession: () -> Void = {
        commentSessionGeneration &+= 1
        if !commentSessionHandedOff {
            commentSession?.invalidate()
        }
        commentSession = nil
        commentSessionDisposable.set(nil)
        let wasAuthorizing = stateValue.with { $0.isAuthorizingComment }
        if wasAuthorizing {
            updateState { current in
                var current = current
                current.isAuthorizingComment = false
                return current
            }
        }
        let operation = stateValue.with { $0.previewOperation }
        if operation != .submitting && !operation.isTerminal {
            preparingForSend = false
            if stateValue.with({ $0.encryptComment }) {
                commentRevision += 1
                transferDisposable.set(nil)
                discardCurrentPreparedTransfer()
                updateState { current in
                    var current = current
                    current.previewOperation = .ready
                    return current
                }
            }
        }
    }

    let installCommentSession: (PasscodeSession) -> Void = { session in
        if commentSession !== session {
            commentSession?.invalidate()
        }
        commentSession = session
        commentSessionHandedOff = false
        guard let expiresAt = session.expiresAt else {
            return
        }
        let interval = max(0.0, expiresAt - ProcessInfo.processInfo.systemUptime)
        delay(interval, closure: { [weak session] in
            guard let session, commentSession === session else {
                return
            }
            invalidateCommentSession()
        })
    }

    let showCommentPrivacyNotice: () -> Void = {
        let encrypted = stateValue.with { $0.encryptComment }
        environment.showModalText(for: context.window, text: walletCommentPrivacyDescription(encrypted: encrypted))
    }

    requestCommentSession = { forSend in
        guard !stateValue.with({ $0.isAuthorizingComment }), isPreview, subjectCollectible == nil else {
            return
        }
        invalidateCommentSession()
        commentRevision += 1
        transferDisposable.set(nil)
        discardCurrentPreparedTransfer()
        let generation = commentSessionGeneration
        preparingForSend = forSend
        updateState { current in
            var current = current
            current.isAuthorizingComment = true
            current.previewOperation = .ready
            return current
        }
        commentSessionDisposable.set((walletContext.beginCommentEncryptionSession()
        |> deliverOnMainQueue).start(next: { session in
            guard commentSessionGeneration == generation else {
                session.invalidate()
                return
            }
            installCommentSession(session)
            updateState { current in
                var current = current
                current.isAuthorizingComment = false
                current.encryptComment = true
                return current
            }
            if forSend {
                commentRevision += 1
                transferDisposable.set(nil)
                prepareCurrentComment?(commentRevision, true)
            } else {
                previewCommentUpdated?()
                showCommentPrivacyNotice()
            }
        }, error: { error in
            guard commentSessionGeneration == generation else {
                return
            }
            preparingForSend = false
            updateState { current in
                var current = current
                current.isAuthorizingComment = false
                current.previewOperation = .ready
                return current
            }
            presentTransferError(error)
        }))
    }

    previewCommentUpdated = {
        commentRevision += 1
        let revision = commentRevision
        transferDisposable.set(nil)
        preparingForSend = false
        let state = stateValue.with { $0 }
        updateState { current in
            var current = current
            current.previewOperation = .ready
            return current
        }
        if state.isAuthorizingComment {
            return
        }
        if state.encryptComment && commentSession?.isValid != true {
            discardCurrentPreparedTransfer()
            return
        }
        let comment = walletTransactionComment(state.comment)
        let wantsEncryption = state.encryptComment && comment != nil
        if let preparedTransfer = state.preparedTransfer,
           !preparedTransferNeedsRefresh,
           preparedTransfer.comment == comment,
           preparedTransfer.commentEncrypted == wantsEncryption,
           TimeInterval(preparedTransfer.expiresAt) > Date().timeIntervalSince1970 {
            return
        }
        updateState { current in
            var current = current
            current.previewOperation = .preparing
            return current
        }
        delay(0.35, closure: {
            guard commentRevision == revision else {
                return
            }
            prepareCurrentComment?(revision, false)
        })
    }

    let showSuccessIfNeeded: (String) -> Void = { address in
        guard !didShowSuccess else {
            return
        }
        didShowSuccess = true
        let recipient = walletCollectibleSuccessRecipient(peerName: subjectRecipientName, address: address)
        if let text = walletTransferSuccessText(isCollectible: subjectCollectible != nil, recipient: recipient) {
            environment.showModalText(for: context.window, text: text)
        }
        onSuccess?()
        close?()
    }

    prepareCurrentComment = { revision, submitAfterPreparation in
        guard isPreview, !stateValue.with({ $0.isAuthorizingComment }) else {
            return
        }
        if let revision = revision, revision != commentRevision {
            return
        }
        let encryptComment = stateValue.with { $0.encryptComment } && subjectCollectible == nil
        if encryptComment && commentSession?.isValid != true {
            invalidateCommentSession()
            if submitAfterPreparation {
                requestCommentSession?(true)
            }
            return
        }
        let comment = walletTransactionComment(stateValue.with { $0.comment })
        let address = stateValue.with { $0.preparedTransfer?.recipient } ?? subjectAddress
        preparingForSend = submitAfterPreparation
        updateState { current in
            var current = current
            current.previewOperation = .preparing
            return current
        }
        let current = stateValue.with { $0.preparedTransfer }
        let requestedAmount = current?.requestedAmount ?? subjectAmount
        let sendAll = current?.isSendAll ?? subjectSendAll
        let preparation: Signal<WalletContext.PreparedTransfer, WalletContext.WalletError>
        if let collectible = subjectCollectible {
            preparation = walletContext.prepareCollectibleTransfer(address: address, collectible: collectible, comment: comment)
        } else {
            let commentEncrypted = encryptComment && comment != nil
            let estimatedFee = walletPreviewEstimatedFee(subject: subject, sendAll: sendAll, hasPreparedTransfer: current != nil, needsRefresh: preparedTransferNeedsRefresh, previewAge: Date().timeIntervalSince1970 - TimeInterval(previewTimestamp), comment: comment, encryptComment: encryptComment)
            preparation = walletContext.prepareTransfer(address: address, amount: requestedAmount, sendAll: sendAll, comment: comment, commentEncrypted: commentEncrypted, session: commentEncrypted ? commentSession : nil, estimatedFee: estimatedFee)
        }
        transferDisposable.set((walletContext.state
        |> filter { $0.activeOperation == nil }
        |> take(1)
        |> castError(WalletContext.WalletError.self)
        |> mapToSignal { state -> Signal<WalletContext.PreparedTransfer, WalletContext.WalletError> in
            if subjectCollectible == nil, let error = walletPreviewBalanceError(balance: state.balance.currentValue, requestedAmount: requestedAmount, sendAll: sendAll) {
                return .fail(error)
            }
            return preparation
        }
        |> deliverOnMainQueue).start(next: { updatedTransfer in
            if let revision = revision, revision != commentRevision {
                discardDisposables.add(walletContext.discardPreparedTransfer(updatedTransfer).start())
                return
            }
            let shouldSubmit = submitAfterPreparation || preparingForSend
            preparingForSend = false
            preparedTransferNeedsRefresh = false
            if let previous = stateValue.with({ $0.preparedTransfer }), previous.id != updatedTransfer.id {
                discardDisposables.add(walletContext.discardPreparedTransfer(previous).start())
            }
            updateState { current in
                var current = current
                current.preparedTransfer = updatedTransfer
                current.displayedFee = updatedTransfer.fee
                return current
            }
            if shouldSubmit {
                submitPrepared?(updatedTransfer)
            } else {
                updateState { current in
                    var current = current
                    current.previewOperation = .ready
                    return current
                }
            }
        }, error: { error in
            if let revision = revision, revision != commentRevision {
                return
            }
            preparingForSend = false
            updateState { current in
                var current = current
                current.previewOperation = .ready
                return current
            }
            presentTransferError(error)
        }))
    }

    submitPrepared = { preparedTransfer in
        updateState { current in
            var current = current
            current.previewOperation = .submitting
            return current
        }
        performSubmit?(preparedTransfer)
    }

    performSubmit = { preparedTransfer in
        let analyticsContext = getController?()?.analyticsContext ?? Analytics.shared.unresolvedContext()
        let presentation = analyticsContext.beginPresentation()
        defer { withExtendedLifetime(presentation) {} }
        preparedTransferNeedsRefresh = false
        let recipientName = subjectRecipientName
        var session: PasscodeSession? = nil
        if preparedTransfer.commentEncrypted, let current = commentSession, current.isValid {
            session = current
            commentSessionHandedOff = true
        }
        guard let transferAnimation, subjectCollectible == nil else {
            updateState { current in
                var current = current
                current.previewOperation = .confirmed
                return current
            }
            close?()
            submitWalletTransferDetached(context: context, environment: environment, walletContext: walletContext, prepared: preparedTransfer, window: context.window, recipientName: recipientName, session: session, submitted: {
                onSuccess?()
            }, analyticsContext: analyticsContext)
            return
        }
        var returnedToWallet = false
        let returnToWallet: () -> Void = {
            guard !returnedToWallet else {
                return
            }
            returnedToWallet = true
            returnToWalletDisposable.set(nil)
            let presentationId = "pending:\(preparedTransfer.id)"
            guard walletContext.stateValue.transactions.items.contains(where: { $0.presentationId == presentationId && $0.status != .failed }) else {
                updateState { current in
                    var current = current
                    current.previewOperation = .confirmed
                    return current
                }
                close?()
                return
            }
            #if arch(arm64)
            let amountRowView = getController?()?.tableView.item(stableId: InputDataEntryId.custom(_id_amount))?.view as? WalletTransactionAmountRowView
            let source = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : amountRowView?.takeTransferDiamond()
            #else
            let source: WalletSendTransferAnimationSource? = nil
            #endif
            if !transferAnimation(presentationId, source) {
                source?.diamond.isRenderingEnabled = false
                source?.diamond.removeFromSuperview()
            }
            close?()
        }
        submitWalletTransferDetached(context: context, environment: environment, walletContext: walletContext, prepared: preparedTransfer, window: context.window, recipientName: recipientName, session: session, submitted: {
            returnToWallet()
            onSuccess?()
        }, failed: {
            returnToWalletDisposable.set(nil)
            close?()
        }, analyticsContext: analyticsContext)
        returnToWalletDisposable.set(analyticsContext.preservingPresentation(walletContext.state
        |> filter { state in
            return state.pendingTransfers.contains(where: { $0.id == preparedTransfer.id }) && state.transactions.items.contains(where: { $0.presentationId == "pending:\(preparedTransfer.id)" && $0.status != .failed })
        }
        |> take(1)
        |> deliverOnMainQueue).start(next: { _ in
            returnToWallet()
        }))
    }

    checkForConfirmation = {
        let state = stateValue.with { $0 }
        guard isPreview,
              state.previewOperation == .pending || state.previewOperation == .submissionUnknown || state.previewOperation == .confirmed,
              let transfer = submittedTransfer,
              let walletState = state.walletState else {
            return
        }
        let pendingTransfer = transfer
        let trackedTransfer = walletState.pendingTransfers.first(where: { $0.id == pendingTransfer.id })
        let transaction = walletState.transactions.items.first(where: { transaction in
            guard !baselineTransactionIds.contains("\(transaction.id):\(transaction.logicalTime)"),
                  transaction.status == .completed,
                  transaction.direction == .outgoing else {
                return false
            }

            if let normalizedHash = pendingTransfer.normalizedHash {
                guard walletTransactionHashesEqual(transaction.externalMessageHash, normalizedHash) else {
                    return false
                }
                if let counterparty = transaction.peer.address,
                   walletTransactionAddressesConflict(counterparty, pendingTransfer.recipient) {
                    return false
                }
            } else {
                guard let counterparty = transaction.peer.address,
                      walletTransactionAddressesEqual(counterparty, pendingTransfer.recipient),
                      walletTransactionComment(transaction.comment) == walletTransactionComment(pendingTransfer.comment),
                      transaction.timestamp >= pendingTransfer.createdAt - 60 else {
                    return false
                }
            }

            if let collectibleAddress = pendingTransfer.collectibleAddress {
                if let transactionCollectible = transaction.collectible {
                    return walletTransactionAddressesEqual(transactionCollectible.address, collectibleAddress)
                }
                if let itemAddress = serverTransactionNftItemAddress(id: transaction.id) {
                    return walletTransactionAddressesEqual(itemAddress, collectibleAddress)
                }
                return true
            }
            return transaction.collectible == nil && transaction.amount == pendingTransfer.amount
        })
        if state.previewOperation == .confirmed {
            if state.transaction == nil, let transaction {
                updateState { current in
                    var current = current
                    current.transaction = transaction
                    return current
                }
            }
            return
        }
        if let trackedTransfer, trackedTransfer.status != .confirmed {
            return
        }
        if trackedTransfer == nil, transaction == nil {
            if state.previewOperation == .submissionUnknown || state.previewOperation == .confirmed {
                return
            }
            submittedTransfer = nil
            preparedTransferNeedsRefresh = true
            updateState { current in
                var current = current
                current.previewOperation = .ready
                return current
            }
            presentTransferError(nil)
            return
        }
        updateState { current in
            var current = current
            current.transaction = transaction ?? current.transaction
            current.previewOperation = .confirmed
            return current
        }
        showSuccessIfNeeded(pendingTransfer.recipient)
    }

    let send: () -> Void = {
        let state = stateValue.with { $0 }
        guard isPreview, !preparingForSend, state.previewOperation == .ready || state.previewOperation == .preparing else {
            return
        }
        if state.isAuthorizingComment {
            return
        }
        if state.encryptComment, subjectCollectible == nil, commentSession?.isValid != true {
            requestCommentSession?(true)
            return
        }
        if state.previewOperation == .preparing {
            preparingForSend = true
            return
        }
        guard let preparedTransfer = state.preparedTransfer else {
            prepareCurrentComment?(nil, true)
            return
        }
        let comment = walletTransactionComment(state.comment)
        let isExpired = TimeInterval(preparedTransfer.expiresAt) <= Date().timeIntervalSince1970
        let wantsEncryption = state.encryptComment && comment != nil && subjectCollectible == nil
        if preparedTransferNeedsRefresh || preparedTransfer.comment != comment || preparedTransfer.commentEncrypted != wantsEncryption || isExpired {
            prepareCurrentComment?(nil, true)
        } else {
            submitPrepared?(preparedTransfer)
        }
    }

    let commentInputUpdated: (String) -> Void = { text in
        guard isPreview else {
            return
        }
        let operation = stateValue.with { $0.previewOperation }
        guard operation == .ready || (operation == .preparing && !preparingForSend) else {
            return
        }
        guard stateValue.with({ $0.comment }) != text else {
            return
        }
        updateState { current in
            var current = current
            current.comment = text
            return current
        }
        previewCommentUpdated?()
    }

    let sendToCounterparty: (Int64?, String?) -> Void = { peerId, address in
        let targetWindow = context.window
        let normalized = address.map { walletSendRecipientAddress($0) ?? $0 }
        let openSend: (Peer?) -> Void = { peer in
            close?()
            if let peer {
                showModal(with: WalletSendController(context: context, environment: environment, walletContext: walletContext, peer: peer, address: normalized ?? "", transferAnimation: transferAnimation), for: targetWindow)
            } else if let normalized {
                showModal(with: WalletSendController(context: context, environment: environment, walletContext: walletContext, initialAddress: normalized, transferAnimation: transferAnimation), for: targetWindow)
            }
        }
        guard let peerId else {
            openSend(nil)
            return
        }
        actionsDisposable.add((context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: PeerId(peerId)))
        |> deliverOnMainQueue).start(next: { peer in
            openSend(peer?._asPeer())
        }))
    }

    let toggleEncryptComment: () -> Void = {
        guard isPreview, subjectCollectible == nil else {
            return
        }
        let state = stateValue.with { $0 }
        guard state.previewOperation == .ready || (state.previewOperation == .preparing && !preparingForSend) else {
            return
        }
        if state.encryptComment || state.isAuthorizingComment {
            invalidateCommentSession()
            updateState { current in
                var current = current
                current.encryptComment = false
                return current
            }
            previewCommentUpdated?()
            showCommentPrivacyNotice()
        } else {
            requestCommentSession?(false)
        }
    }

    let toggleCommentExpansion: () -> Void = {
        updateState { current in
            var current = current
            current.isCommentExpanded.toggle()
            return current
        }
    }

    let showWhatsGram: ((() -> NSView?)?) -> Void = { morphSource in
        showModal(with: WalletInfoController(context: context, environment: environment, walletContext: walletContext, mode: .wallet), for: context.window, morphSource: morphSource)
    }

    let arguments = Arguments(context: context, environment: environment, subject: subject, previewTimestamp: previewTimestamp, transferGaslessMinAmount: WalletConfiguration.with(appConfiguration: context.appConfiguration).transferGaslessMinAmount, sendToCounterparty: sendToCounterparty, decryptComment: {
        decryptComment?()
    }, toggleEncryptComment: toggleEncryptComment, toggleCommentExpansion: toggleCommentExpansion, copyAddress: { address in
        walletCopyAddress(address, environment: environment, window: context.window)
    }, commentUpdated: commentInputUpdated, showFeeInfo: {
        let state = stateValue.with { $0 }
        var text = strings().walletTransactionControllerNetworkFeeInfo
        if let transaction = state.transaction, transaction.fee > 0 {
            var feeText = walletGramsUnitText(formatTonAmountText(transaction.fee, maxDecimalPositions: 9))
            if let rate = state.walletState?.fiat.selectedRate, rate.unitsPerGram.isFinite, rate.unitsPerGram > 0 {
                let currency = state.walletState?.fiat.selectedCurrency ?? .usd
                let fiat = formatTonFiatValuePrecise(transaction.fee, rate: rate.unitsPerGram, currencySymbol: currency.symbol)
                if fiat.contains(where: { $0.isNumber && $0 != "0" }) {
                    feeText = fiat
                }
            }
            text += " (\(feeText))"
        }
        text += strings().walletTransactionControllerNetworkFeeGaslessOther(Int(WalletConfiguration.with(appConfiguration: context.appConfiguration).transferGaslessDailyLimit))
        environment.alert(for: context.window, header: strings().walletTransactionControllerNetworkFeesTitle, info: text)
    }, showWhatsGram: showWhatsGram)

    if isPreview, subjectCollectible == nil {
        actionsDisposable.add((walletUIPasscodeLocked()
        |> filter { $0 }
        |> deliverOnMainQueue).start(next: { _ in
            invalidateCommentSession()
        }))
    }

    actionsDisposable.add((walletContext.state
    |> deliverOnMainQueue).start(next: { walletState in
        var walletIdentityChanged = false
        if case let .wallet(previous) = stateValue.with({ $0.walletState?.phase }) {
            if case let .wallet(info) = walletState.phase, info.address == previous.address, info.publicKey == previous.publicKey {
            } else {
                walletIdentityChanged = true
            }
        }
        if walletIdentityChanged {
            decryptCommentDisposable.set(nil)
        }
        updateState { current in
            var current = current
            current.walletState = walletState
            if walletIdentityChanged {
                current.decryptedComment = nil
                current.isDecryptingComment = false
            }
            if !isPreview, let transaction = current.transaction,
               let updatedTransaction = updatedWalletTransaction(transaction, in: walletState.transactions.items) {
                if updatedTransaction.comment != transaction.comment || updatedTransaction.commentEncrypted != transaction.commentEncrypted {
                    current.decryptedComment = nil
                }
                current.transaction = updatedTransaction
            }
            return current
        }
        checkForConfirmation?()
    }))

    let signal = statePromise.get()
    |> deliverOnPrepareQueue
    |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let title: String
    if arguments.usesCollectibleModalHeader {
        title = ""
    } else if isPreview {
        title = strings().walletTransactionControllerConfirmation
    } else {
        title = strings().walletTransactionControllerTransaction
    }

    let controller = InputDataController(dataSignal: signal, title: title, hasDone: false, getBackgroundColor: {
        arguments.usesCollectibleModalHeader ? theme.colors.listBackground : theme.colors.background
    })
    switch subject {
    case .transaction:
        controller.analyticsScreen = AnalyticsScreen.walletTransaction
    case .preview:
        controller.analyticsScreen = AnalyticsScreen.walletTransferConfirmation
    case .collectiblePreview:
        controller.analyticsScreen = AnalyticsScreen.walletCollectibleConfirmation
    }
    getController = { [weak controller] in
        return controller
    }

    controller.onDeinit = {
        decryptComment = nil
        prepareCurrentComment = nil
        submitPrepared = nil
        performSubmit = nil
        checkForConfirmation = nil
        requestCommentSession = nil
        previewCommentUpdated = nil
        let state = stateValue.with { $0 }
        if isPreview, !state.previewOperation.isTerminal, state.previewOperation != .submitting, let preparedTransfer = state.preparedTransfer {
            _ = walletContext.discardPreparedTransfer(preparedTransfer).start()
        }
        if !commentSessionHandedOff {
            commentSession?.invalidate()
        }
        commentSession = nil
        restoreAuthorization.end()
        actionsDisposable.dispose()
    }

    controller.updateDatas = { data in
        if isPreview, let comment = data[_id_comment_input]?.stringValue {
            commentInputUpdated(comment)
        }
        return .none
    }

    let openActions = walletTransactionOpenActions(subject: subject, decryptCommentOnOpen: decryptCommentOnOpen)
    if isPreview {
        controller.didAppear = { controller in
            controller.makeFirstResponderIfPossible(for: _id_comment_input, scrollIfNeeded: false)
        }
    } else if openActions.decryptComment {
        var shouldDecryptComment = true
        controller.didAppear = { _ in
            guard shouldDecryptComment else {
                return
            }
            shouldDecryptComment = false
            decryptComment?()
        }
    } else if openActions.checkFirstIncomingTransfer {
        let firstIncomingTransferDisposable = MetaDisposable()
        actionsDisposable.add(firstIncomingTransferDisposable)
        var checkFirstIncomingTransfer = true
        controller.didAppear = { controller in
            guard checkFirstIncomingTransfer else {
                return
            }
            checkFirstIncomingTransfer = false
            firstIncomingTransferDisposable.set((context.engine.notices.getServerProvidedSuggestions()
            |> take(1)
            |> deliverOnMainQueue).start(next: { [weak controller] suggestions in
                guard suggestions.contains(.walletFirstIncomingTransfer), controller?.window != nil else {
                    return
                }
                showModal(with: WalletInfoController(context: context, environment: environment, walletContext: walletContext, mode: .firstGrams), for: context.window)
                _ = context.engine.notices.dismissServerProvidedSuggestion(suggestion: ServerProvidedSuggestion.walletFirstIncomingTransfer.id).start()
            }))
        }
    }

    if let intro = arguments.intro {
        controller.willAppear = { controller in
            intro.begin(with: controller.view, isReady: { true })
        }
    }

    let finishSheet: () -> Void = {
        close?()
        if origin == .chat {
            showWallet(context: context, environment: environment, walletContext: walletContext, for: context.window)
        }
    }

    controller.validateData = { _ in
        if isPreview, !stateValue.with({ $0.previewOperation }).isTerminal {
            send()
        } else {
            finishSheet()
        }
        return .none
    }

    let acceptTitleForState: () -> String = {
        guard isPreview else {
            return origin == .chat ? strings().walletTransactionControllerOpenMyMoney : strings().walletTransactionControllerOk
        }
        if subjectCollectible != nil {
            return strings().walletTransactionControllerSendCollectible
        }
        let amount = stateValue.with { walletPreviewAmount(preparedAmount: $0.preparedTransfer?.amount, amount: subjectAmount, sendAll: subjectSendAll, displayedFee: $0.displayedFee) }
        return strings().walletTransactionControllerSendAmount(formatGramsText(amount, maxDecimalPositions: 9))
    }

    let modalInteractions = ModalInteractions(acceptTitle: acceptTitleForState(), accept: {
        if isPreview, !stateValue.with({ $0.previewOperation }).isTerminal {
            send()
        } else {
            finishSheet()
        }
    }, singleButton: true, customTheme: { walletModalTheme })

    controller.afterTransaction = { [weak modalInteractions] _ in
        modalInteractions?.updateDone { button in
            if isPreview {
                let operation = stateValue.with { $0.previewOperation }
                let canSign: Bool = {
                    if case let .wallet(info) = stateValue.with({ $0.walletState?.phase }) {
                        return info.canSign
                    }
                    return false
                }()
                button.isEnabled = (operation == .ready && canSign) || operation.isTerminal
                button.set(text: operation.isTerminal ? strings().walletTransactionControllerOk : acceptTitleForState(), for: .Normal)
            } else {
                button.isEnabled = true
            }
        }
    }

    let transactionMenu: () -> [ContextMenuItem] = {
        var items: [ContextMenuItem] = []
        var explorerUrl: String? = nil
        if let transaction = stateValue.with({ $0.transaction }) {
            explorerUrl = walletTransactionExplorerUrl(context: context, environment: environment, transaction: transaction)
        }
        if explorerUrl == nil, let hash = submittedTransfer?.normalizedHash {
            explorerUrl = walletExplorerUrl(context: context, environment: environment, hash: hash)
        }
        if let explorerUrl {
            items.append(ContextMenuItem(strings().walletTransactionControllerViewInExplorer, handler: {
                environment.openExternalURL(explorerUrl)
            }, itemImage: environment.menuImage(.menu_open_with)))
        }
        if let transaction = stateValue.with({ $0.transaction }), transaction.currency == .ton, transaction.collectible == nil {
            items.append(ContextMenuItem(strings().walletTransactionControllerWhatIsGram, handler: { showWhatsGram(nil) }, itemImage: environment.menuImage(.menu_show_info)))
        }
        return items
    }

    if arguments.usesCollectibleModalHeader {
        arguments.updateHeader = walletCollectibleModalHeader(controller: controller, close: { close?() }, menu: transactionMenu)
    }

    let modalController = WalletModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(arguments.usesCollectibleModalHeader ? 400 : 360, 0))
    if arguments.usesCollectibleModalHeader {
        modalController.allowsVerticalScrollElasticity = false
    } else {
        controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
            modalController?.close()
        })
        controller.rightModalHeader = isPreview ? nil : ModalHeaderData(image: theme.icons.chatActionsActive, contextMenu: transactionMenu)
    }

    close = { [weak modalController] in
        modalController?.close()
    }
    arguments.close = { close?() }

    if isPreview, stateValue.with({ $0.preparedTransfer == nil }) {
        prepareCurrentComment?(0, false)
    }

    return modalController
}
