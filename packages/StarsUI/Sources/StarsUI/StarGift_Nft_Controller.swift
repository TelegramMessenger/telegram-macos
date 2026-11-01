import Cocoa
import Foundation
import TGUIKit
import UniqueGiftBackground
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import AlertsUI
import TelegramMediaUtils
import TelegramMedia
import LocalAnimations
import CurrencyFormat
import PremiumStatusUI
import SceneEffects
import DustLayer
import InAppPurchaseManager
import ObjcUtils
import PremiumUI
import CalendarUtils
import DateUtils
import LokiRng
import FoundationUtils
import InputView
import InputTextView
import InlineStickerLayer

private func withGiftModalSource<Result>(for window: Window, perform action: () -> Result) -> Result {
    guard let source = Control.currentEventSource, source.window === window else {
        return action()
    }
    return ModalMorphContextSource.withSource({ [weak source] in source }, perform: action)
}

extension StarGift.UniqueGift.Attribute.Rarity {
    public var badgeText: String {
        switch self {
        case let .permille(value):
            if value == 0 {
                return "<0.1%"
            }
            let percent = Double(value) / 10.0
            if percent.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(percent))%"
            } else {
                return String(format: "%.1f%%", percent)
            }
        case .rare:
            return strings().giftUniqueRarityRare
        case .epic:
            return strings().giftUniqueRarityEpic
        case .legendary:
            return strings().giftUniqueRarityLegendary
        case .uncommon:
            return strings().giftUniqueRarityUncommon
        }
    }
}

extension ProfileGiftsContext.State.StarGift {
    public static func placeholder(gift: StarGift.UniqueGift) -> ProfileGiftsContext.State.StarGift {
        return .init(gift: .unique(gift), reference: nil, fromPeer: nil, date: 0, text: nil, entities: nil, nameHidden: false, savedToProfile: false, pinnedToTop: false, convertStars: nil, canUpgrade: false, canExportDate: nil, upgradeStars: nil, transferStars: nil, canTransferDate: nil, canResaleDate: nil, collectionIds: nil, prepaidUpgradeHash: nil, upgradeSeparate: false, dropOriginalDetailsStars: nil, number: nil, isRefunded: false, canCraftAt: nil)
    }
}

// MARK: - Craft Circular Pattern View

extension StarGift.UniqueGift.Attribute.Rarity {
    public var badgeColor: NSColor? {
        switch self {
        case .permille:
            return nil
        case .rare:
            return NSColor(0x25A3B9)
        case .epic:
            return NSColor(0xAF52DE)
        case .legendary:
            return NSColor(0xD57E32)
        case .uncommon:
            return NSColor(0x22B447)
        }
    }
}

public func makeGiftOriginalInfoString(_ gift: StarGift.UniqueGift, peerMap:[PeerId: EnginePeer], context: (any AccountContextProtocol)) -> NSAttributedString? {
    for attr in gift.attributes {
        switch attr {
        case let .originalInfo(senderPeerId, recipientPeerId, date, text, entities):
            
            let senderName = senderPeerId.flatMap { peerMap[$0]?._asPeer().displayTitle }
            let recipientName = peerMap[recipientPeerId]?._asPeer().displayTitle ?? ""

            let dateString = stringForMediumDate(timestamp: date)
            let string = NSMutableAttributedString()
            
            let originalId = UUID().uuidString
            let recipientId = UUID().uuidString
            let senderId = UUID().uuidString
            
            if let text {
                let attributedText = StarsHooks.shared.applyMessageEntities(entities ?? [], text, context, 13, { peerId, _, _, _ in }, nil, false, false).mutableCopy() as! NSMutableAttributedString
                
                let format = senderName != nil ? strings().giftUniqueOriginalInfoSenderWithText(senderId, recipientId, dateString, originalId) : strings().giftUniqueOriginalInfoWithText(recipientId, dateString, originalId)
                string.append(string: format, color: theme.colors.text, font: .normal(.text))
                do {
                    let range = string.string.nsstring.range(of: originalId)
                    if range.location != NSNotFound {
                        string.replaceCharacters(in: range, with: attributedText)
                    }
                }
            } else {
                let format = senderName != nil ? strings().giftUniqueOriginalInfoSender(senderId, recipientId, dateString) : strings().giftUniqueOriginalInfo(recipientId, dateString)
                string.append(string: format, color: theme.colors.text, font: .normal(.text))
            }
            
            do {
                let range = string.string.nsstring.range(of: recipientId)
                if range.location != NSNotFound {
                    string.addAttribute(NSAttributedString.Key.link, value: recipientPeerId, range: range)
                    string.addAttribute(NSAttributedString.Key.foregroundColor, value: theme.colors.accent, range: range)
                    string.replaceCharacters(in: range, with: recipientName)
                    
                }
            }
            
            if let senderPeerId, let senderName {
                let range = string.string.nsstring.range(of: senderId)
                if range.location != NSNotFound {
                    string.addAttribute(NSAttributedString.Key.link, value: senderPeerId, range: range)
                    string.addAttribute(NSAttributedString.Key.foregroundColor, value: theme.colors.accent, range: range)
                    string.replaceCharacters(in: range, with: senderName)
                    
                }
            }
            return string
        default:
            break
        }
    }
    return nil
}

extension StarGift.UniqueGift {
    public func resellStars(_ context: (any AccountContextProtocol)) -> CurrencyAmount? {
        let value = self.resellAmounts?.first(where: { value in
            if value.currency == .stars {
               return true
            } else {
                return false
            }
        })
        
        if let value {
            return value
        } else if let ton = self.resellAmounts?.first(where: { $0.currency == .ton}) {
            let usd_rate = context.appConfiguration.getGeneralValueDouble("ton_usd_rate", orElse: 3)
            let tons = Double(ton.amount.value) / 1_000_000_000
            let usdAmount = tons * usd_rate
            return .init(amount: .init(value: Int64(usdAmount / 0.013), nanos: 0), currency: .stars)
        } else {
            return nil
        }
    }
    
    public var resell: CurrencyAmount? {
        return self.resellAmounts?.first(where: { value in
            if value.currency == (resellForTonOnly ? .ton : .stars) {
               return true
            } else {
                return false
            }
        })
    }
    
    public func resell(_ currency: CurrencyAmount.Currency) -> CurrencyAmount? {
        return self.resellAmounts?.first(where: { value in
            if value.currency == currency {
               return true
            } else {
                return false
            }
        })
    }
}

public func getTransferAttributesRows(gift unique: StarGift.UniqueGift, includeValue: Bool = true) -> [InputDataTableBasedItem.Row] {
    var rows: [InputDataTableBasedItem.Row] = []
    for attr in unique.attributes {
        switch attr {
        case .model(let name, _, let rarity, _):
            rows.append(.init(left: .init(.initialize(string: strings().giftUniqueModel, color: theme.colors.text, font: .normal(.text))), right: .init(name: .init(.initialize(string: name, color: theme.colors.text, font: .normal(.text))), badge: .init(text: rarity.badgeText, color: rarity.badgeColor, callback: {}))))
        case .pattern(let name, _, let rarity):
            rows.append(.init(left: .init(.initialize(string: strings().giftUniqueSymbol, color: theme.colors.text, font: .normal(.text))), right: .init(name: .init(.initialize(string: name, color: theme.colors.text, font: .normal(.text))), badge: .init(text: rarity.badgeText, color: rarity.badgeColor, callback: {}))))
        case .backdrop(let name, _, _, _, _, _, let rarity):
            rows.append(.init(left: .init(.initialize(string: strings().giftUniqueBackdrop, color: theme.colors.text, font: .normal(.text))), right: .init(name: .init(.initialize(string: name, color: theme.colors.text, font: .normal(.text))), badge: .init(text: rarity.badgeText, color: rarity.badgeColor, callback: {}))))
        default:
            break
        }
    }
    
    if let valueAmount = unique.valueAmount, let currency = unique.valueCurrency, includeValue {
        rows.append(.init(
            left: .init(.initialize(
                string: strings().starGiftValueRowLabel,
                color: theme.colors.text,
                font: .normal(.text)
            )),
            right: .init(
                name: .init(.initialize(
                    string: formatCurrencyAmount(valueAmount, currency: currency),
                    color: theme.colors.text,
                    font: .normal(.text)
                ))
            )
        ))
    }
    return rows
}

public final class TransferUniqueGiftHeaderItem : GeneralRowItem {
    public enum TransferType : Equatable {
        case buy(onlyTon: Bool)
        case transfer
        case sell
        case resetTheme
    }
    fileprivate let transferType: TransferType
    fileprivate let gift: StarGift.UniqueGift
    fileprivate let toPeer: EnginePeer
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let layout: TextViewLayout
    
    fileprivate let onlyTonLayout: TextViewLayout?
    
    fileprivate let buyForStars: TextViewLayout?
    fileprivate let buyForTon: TextViewLayout?
    
    fileprivate var buyForSelected: CurrencyAmount.Currency = .stars
    fileprivate let callback: (CurrencyAmount.Currency)->Void
    
    public func toggleBuySelected() {
        switch buyForSelected {
        case .stars:
            buyForSelected = .ton
        case .ton:
            buyForSelected = .stars
        }
        callback(buyForSelected)
        self.redraw(animated: true)
    }
    
    public init(_ initialSize: NSSize, stableId: AnyHashable, gift: StarGift.UniqueGift, toPeer: EnginePeer, context: (any AccountContextProtocol), transferType: TransferType = .transfer, buyForSelected: CurrencyAmount.Currency = .stars, callback: @escaping (CurrencyAmount.Currency)->Void = { _ in }) {
        self.transferType = transferType
        self.buyForSelected = buyForSelected
        self.callback = callback
        self.gift = gift
        self.toPeer = toPeer
        self.context = context
        switch transferType {
        case .transfer:
            self.layout = TextViewLayout(
                .initialize(
                    string: toPeer.id == context.peerId
                        ? strings().giftWithdrawTitle
                        : strings().giftTransferConfirmationTitle,
                    color: theme.colors.text,
                    font: .medium(.title)
                )
            )
        case .buy:
            self.layout = TextViewLayout(
                .initialize(
                    string: strings().starGiftSellAlertTitleConfirmPayment,
                    color: theme.colors.text,
                    font: .medium(.title)
                )
            )
        case .resetTheme:
            self.layout = TextViewLayout(
                .initialize(
                    string: strings().chatThemeUniqueGiftReplaceTitle,
                    color: theme.colors.text,
                    font: .medium(.title)
                )
            )
        case .sell:
            self.layout = TextViewLayout(
                .initialize(
                    string: strings().starGiftNftConfirmSale,
                    color: theme.colors.text,
                    font: .medium(.title)
                )
            )
        }
        layout.measure(width: .greatestFiniteMagnitude)

        if case let .buy(onlyTon) = transferType {
            if onlyTon {
                self.onlyTonLayout = .init(
                    .initialize(
                        string: strings().starGiftSellAlertOnlyTon,
                        color: theme.colors.listGrayText,
                        font: .normal(.text)
                    ),
                    alignment: .center
                )
                self.onlyTonLayout?.measure(width: 200)
                
                self.buyForTon = nil
                self.buyForStars = nil
                
            } else {
                self.onlyTonLayout = nil
                
                self.buyForTon = .init(
                    .initialize(
                        string: strings().starGiftSellAlertPayInTon,
                        color: theme.colors.listGrayText,
                        font: .normal(.text)
                    ),
                    alignment: .center
                )
                self.buyForStars = .init(
                    .initialize(
                        string: strings().starGiftSellAlertPayInStars,
                        color: theme.colors.listGrayText,
                        font: .normal(.text)
                    ),
                    alignment: .center
                )
                
                self.buyForStars?.measure(width: .greatestFiniteMagnitude)
                self.buyForTon?.measure(width: .greatestFiniteMagnitude)
            }
        } else {
            self.onlyTonLayout = nil
            self.buyForTon = nil
            self.buyForStars = nil
        }

        var height: CGFloat = 120
        if let onlyTonLayout {
            height += onlyTonLayout.layoutSize.height
        } else if let _ = buyForTon {
            height += 20
        }
        
        super.init(initialSize, height: height, stableId: stableId)
    }
    
    public override var accessibilityLabel: String? {
        return layout.attributedString.string
    }
    
    public override var accessibilityValue: String? {
        return [gift.title + " #\(gift.number)", toPeer._asPeer().displayTitle].joined(separator: ", ")
    }
    
    public override func viewClass() -> AnyClass {
        return TransferHeaderView.self
    }
}

private final class TransferHeaderView : GeneralRowView {
    private let avatar = AvatarControl(font: .avatar(18))
    private let giftView = StarsHooks.shared.makeStickerView(NSMakeRect(0, 0, 40, 40))
    private let chevron: ImageView = ImageView()
    private let container = View()
    private let textView = TextView()
    private var headerTextView: TextView?
    
    private let transferContainer = View()
    
    private let backgroundView = UniqueGiftBackgroundView(frame: NSMakeRect(0, 0, 60, 60))
    
    private var buyFor: View?
    private var buyForTon: TextView?
    private var buyForStars: TextView?

    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
      
        
        transferContainer.addSubview(backgroundView)
        transferContainer.addSubview(giftView)
        
        transferContainer.backgroundColor = .clear
        
        transferContainer.layer?.cornerRadius = 10
        transferContainer.setFrameSize(NSMakeSize(60, 60))
        
        container.addSubview(transferContainer)
        container.addSubview(chevron)
        container.addSubview(avatar)

        addSubview(textView)

        giftView.setFrameSize(NSMakeSize(50, 50))
        avatar.setFrameSize(NSMakeSize(60, 60))
        addSubview(container)
        
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        chevron.isAccessibilityDecorative = true
        
        giftView.center()
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
                
        super.set(item: item, animated: animated)
        
        guard let item = item as? TransferUniqueGiftHeaderItem else {
            return
        }
        
        switch item.transferType {
        case .buy, .transfer, .sell:
            chevron.image = TelegramThemeHooks.shared.image(.iconAffiliateChevron).precomposed(theme.colors.grayIcon.withAlphaComponent(0.8))
        case .resetTheme:
            chevron.image = TelegramThemeHooks.shared.image(.iconGiftThemeUndo).precomposed(theme.colors.grayIcon.withAlphaComponent(0.8))
        }
        chevron.sizeToFit()
        
        textView.update(item.layout)
        
        container.setFrameSize(NSMakeSize(transferContainer.frame.width + avatar.frame.width + 45, 70))
        
        if item.transferType == .sell {
            avatar.setSignal(generateEmptyPhoto(avatar.frame.size, type: .icon(colors: (top: theme.colors.listBackground, bottom: theme.colors.listBackground), icon: TelegramThemeHooks.shared.image(.iconMarket).precomposed(), iconSize: avatar.frame.size, cornerRadius: nil), bubble: false) |> map {($0, false)})
        } else if item.toPeer.id == item.context.peerId, item.transferType == .transfer {
            avatar.setSignal(generateEmptyPhoto(avatar.frame.size, type: .icon(colors: (top: theme.colors.listBackground, bottom: theme.colors.listBackground), icon: TelegramThemeHooks.shared.image(.iconStarTransactionRowFragment).precomposed(), iconSize: avatar.frame.size, cornerRadius: nil), bubble: false) |> map {($0, false)})
        } else {
            avatar.setPeer(account: item.context.account, peer: item.toPeer._asPeer())
        }
        (giftView as? StarsStickerView)?.updateStarsSticker(file: item.gift.file!, size: giftView.frame.size, context: item.context, colors: [], playback: .standard, animated: animated)
        
        
        if let onlyTonLayout = item.onlyTonLayout {
            let current: TextView
            if let view = self.headerTextView {
                current = view
            } else {
                current = TextView()
                self.headerTextView = current
                self.addSubview(current)
                current.userInteractionEnabled = false
                current.isSelectable = false
                current.disableBackgroundDrawing = true
                current.isEventLess = true
            }
            current.update(onlyTonLayout)
        } else if let view = self.headerTextView {
            performSubviewRemoval(view, animated: animated)
            self.headerTextView = nil
        }
        
        if let buyForTon = item.buyForTon, let buyForStars = item.buyForStars {
            let current: View
            if let view = buyFor {
                current = view
            } else {
                current = View(frame: NSMakeRect(0, 0, frame.width, 26))
                addSubview(current)
                self.buyFor = current
            }
            
            let tonCurrent: TextView
            if let view = self.buyForTon {
                tonCurrent = view
            } else {
                tonCurrent = TextView()
                self.buyForTon = tonCurrent
                current.addSubview(tonCurrent)
                tonCurrent.isSelectable = false
                tonCurrent.scaleOnClick = true
            }
            tonCurrent.update(buyForTon)
            tonCurrent.setFrameSize(NSMakeSize(buyForTon.layoutSize.width + 20, 26))
            tonCurrent.layer?.cornerRadius = tonCurrent.frame.height / 2

            let starsCurrent: TextView
            if let view = self.buyForStars {
                starsCurrent = view
            } else {
                starsCurrent = TextView()
                self.buyForStars = starsCurrent
                current.addSubview(starsCurrent)
                starsCurrent.isSelectable = false
                starsCurrent.scaleOnClick = true
            }
            starsCurrent.update(buyForStars)
            starsCurrent.setFrameSize(NSMakeSize(buyForStars.layoutSize.width + 20, 26))
            starsCurrent.layer?.cornerRadius = starsCurrent.frame.height / 2
            
            
            starsCurrent.setSingle(handler: { [weak item, weak self] _ in
                if item?.buyForSelected != .stars {
                    item?.toggleBuySelected()
                    if let buyForTon = self?.buyForTon {
                        tooltip(for: buyForTon, text: strings().starSellTonTooltip)
                    }
                }
                
            }, for: .Click)
            
            tonCurrent.setSingle(handler: { [weak item] _ in
                if item?.buyForSelected != .ton {
                    item?.toggleBuySelected()
                }
            }, for: .Click)
            
            switch item.buyForSelected {
            case .stars:
                starsCurrent.set(background: theme.colors.listGrayText.withAlphaComponent(0.2), for: .Normal)
                tonCurrent.set(background: .clear, for: .Normal)
            case .ton:
                tonCurrent.set(background: theme.colors.listGrayText.withAlphaComponent(0.2), for: .Normal)
                starsCurrent.set(background: .clear, for: .Normal)
            }
        } else {
            if let view = self.buyFor {
                performSubviewRemoval(view, animated: animated)
                self.buyFor = nil
                self.buyForTon = nil
                self.buyForStars = nil
            }
        }
        
        if let content = UniqueGiftBackgroundContent(gift: item.gift) {
            self.backgroundView.isHidden = false
            self.backgroundView.update(context: item.context, content: content, style: .item(giftCenterY: 30, cornerRadius: 10))
        } else {
            self.backgroundView.isHidden = true
        }
        
        needsLayout = true
        
        
    }
    
    public override func layout() {
        super.layout()
        
        guard item is TransferUniqueGiftHeaderItem else {
            return
        }
        
        
        headerTextView?.centerX(y: 0)
        
        var offset: CGFloat = 15
        
        if let headerTextView {
            offset += headerTextView.frame.height
        }
        if let buyFor {
            offset += buyFor.frame.height
        }
        
        if let buyFor {
            buyFor.frame = bounds.focusX(NSMakeSize(buyFor.subviewsWidthSize.width, 26), y: 0)
            if let buyForTon, let buyForStars {
                buyForStars.centerY(x: 0)
                buyForTon.centerY(x: buyForStars.frame.maxX)
            }
        }
        
        container.centerX(y: offset)
        transferContainer.centerY(x: 0)
        avatar.centerY(x: container.frame.width - avatar.frame.width)
        
        self.backgroundView.frame = transferContainer.bounds
        
        chevron.center()
        chevron.setFrameOrigin(NSMakePoint(chevron.frame.minX + 2, chevron.frame.minY))
        textView.centerX(y: frame.height - textView.frame.height - 10)
    }
}

private final class RowItem : GeneralRowItem {
    
    public let context: (any AccountContextProtocol)
    
    public let options: [OptionsListView.Option]
    fileprivate let toggleName: ()->Void
    fileprivate let nameEnabled: Bool
    fileprivate var nameEnabledLayout: TextViewLayout?
    fileprivate let isPreview: Bool
    
    fileprivate let transaction: StarsContext.State.Transaction?
    
    fileprivate let headerLayout: TextViewLayout?
    fileprivate let infoLayout: TextViewLayout?
    
    public let hasToggle: Bool
    
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: (any AccountContextProtocol), source: StarGiftNftSource, transaction: StarsContext.State.Transaction?, nameEnabled: Bool, isPreview: Bool, toggleName: @escaping()->Void) {
        self.context = context
        self.toggleName = toggleName
        self.isPreview = isPreview
        self.nameEnabled = nameEnabled
        self.transaction = transaction
        var options:[OptionsListView.Option] = []
        
        switch source {
        case let .previewWear(_, gift):
            headerLayout = .init(.initialize(string: strings().starNftWearTitle("\(gift.title) #\(gift.number)"), color: theme.colors.text, font: .medium(18)))
            infoLayout = .init(.initialize(string: strings().starNftWearInfo, color: theme.colors.text, font: .normal(.text)))
        default:
            headerLayout = nil
            infoLayout = nil
        }
        
        
        var hasToggle: Bool {
            switch source {
            case .giftUpgrade:
                return false
            default:
                if isPreview {
                    return false
                } else if let _ = transaction {
                    return true
                }
            }
            return true
        }
        
        self.hasToggle = hasToggle
        
        if hasToggle {
            nameEnabledLayout = .init(.initialize(string: transaction?.title == nil || transaction?.title?.isEmpty == true ? strings().giftUpgradeAddName : strings().giftUpgradeAddNameAndComment, color: theme.colors.grayText, font: .normal(.text)))
        } else {
            nameEnabledLayout = nil
        }
        
        let title1: String
        let info1: String
        
        let title2: String
        let info2: String

        let title3: String
        let info3: String
        
        
        let image1: CGImage
        let image2: CGImage
        let image3: CGImage
        
        switch source {
        case .previewWear:
            title1 = strings().giftWearBadgeTitle
            info1 = strings().giftWearBadgeText
            
            title2 = strings().giftWearDesignTitle
            info2 = strings().giftWearDesignText

            title3 = strings().giftWearProofTitle
            info3 = strings().giftWearProofText
            
            image1 = TelegramThemeHooks.shared.image(.iconNFTRadiantBadge).precomposed(theme.colors.accent)
            image2 = TelegramThemeHooks.shared.image(.iconChannelFeatureCoverIcon).precomposed(theme.colors.accent)
            image3 = TelegramThemeHooks.shared.image(.iconNFTVerification).precomposed(theme.colors.accent)
        default:
            title1 = strings().giftUpgradeUniqueTitle
            info1 = isPreview ? strings().giftUpgradeUniqueIncludeDescription : strings().giftUpgradeUniqueDescription
            
            title2 = strings().giftUpgradeTransferableTitle
            info2 = isPreview ? strings().giftUpgradeTransferableIncludeDescription : strings().giftUpgradeTransferableDescription
            
            title3 = strings().giftUpgradeTradableTitle
            info3 = isPreview ? strings().giftUpgradeUniqueIncludeDescription : strings().giftUpgradeUniqueDescription
            
            image1 = TelegramThemeHooks.shared.image(.iconNFTUnique).precomposed(theme.colors.accent)
            image2 = TelegramThemeHooks.shared.image(.iconNFTTransferable).precomposed(theme.colors.accent)
            image3 = TelegramThemeHooks.shared.image(.iconNFTTradable).precomposed(theme.colors.accent)
        }

        
        options.append(.init(image: image1, header: .init(.initialize(string: title1, color: theme.colors.text, font: .medium(.text))), text: .init(.initialize(string: info1, color: theme.colors.grayText, font: .normal(.text))), width: initialSize.width - 40))

        
        options.append(.init(image: image2, header: .init(.initialize(string: title2, color: theme.colors.text, font: .medium(.text))), text: .init(.initialize(string: info2, color: theme.colors.grayText, font: .normal(.text))), width: initialSize.width - 40))

        options.append(.init(image: image3, header: .init(.initialize(string: title3, color: theme.colors.text, font: .medium(.text))), text: .init(.initialize(string: info3, color: theme.colors.grayText, font: .normal(.text))), width: initialSize.width - 40))

        
        self.options = options
        
        self.nameEnabledLayout?.measure(width: initialSize.width - 80)

        super.init(initialSize, stableId: stableId, viewType: .singleItem)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        infoLayout?.measure(width: width - 40)
        headerLayout?.measure(width: width - 40)
        return true
    }
    
    public override var height: CGFloat {
        var height: CGFloat = 0
        height += OptionsListView.height(options: options, spacing: 20) + 20
        
        if hasToggle {
            height += 25
        }
        
        if let infoLayout, let headerLayout {
            height += headerLayout.layoutSize.height
            height += 5
            height += infoLayout.layoutSize.height
            height += 20
        }
        
        return height
    }
    
    override var accessibilityLabel: String? {
        return headerLayout?.attributedString.string ?? options.first?.header.attributedString.string
    }
    
    public override func viewClass() -> AnyClass {
        return RowView.self
    }
}

private final class RowView: GeneralContainableRowView {
    
    
        
    private let nameToggle: SelectingControl = SelectingControl(unselectedImage: theme.icons.chatToggleUnselected, selectedImage: theme.icons.chatToggleSelected)
    private let nameView: TextView = TextView()
    private let nameControl = Control()
    
    private var headerView: TextView?
    private var infoView: TextView?
    
    private let optionsView = OptionsListView(frame: .zero)
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(optionsView)
        nameControl.addSubview(nameToggle)
        nameControl.addSubview(nameView)
        addSubview(nameControl)
        
        nameToggle.userInteractionEnabled = false
        nameView.userInteractionEnabled = false
        nameView.isSelectable = false
        
    }
    
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        
        
        if let headerView, let infoView {
            headerView.centerX(y: 0)
            infoView.centerX(y: headerView.frame.maxY + 5)
        }
        
        var offset: CGFloat = 0
        if let infoView {
            offset += infoView.frame.maxY + 20
        }
        optionsView.centerX(y: offset)
                
      
        
        
        nameControl.frame = NSMakeRect(0, frame.height - 22, nameToggle.frame.width + nameView.frame.width + 10, 22)

        
        nameToggle.setFrameOrigin(NSMakePoint(0, 0))
        nameView.setFrameOrigin(NSMakePoint(nameToggle.frame.maxX + 10, 2))
        
        
        nameControl.centerX()
    }
    
    public override var backdorColor: NSColor {
        return theme.colors.background
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? RowItem else {
            return
        }
        
        if let textLayout = item.headerLayout {
            let current: TextView
            if let view = self.headerView {
                current = view
            } else {
                current = TextView()
                current.userInteractionEnabled = false
                current.isSelectable = false
                self.headerView = current
                addSubview(current)
            }
            current.update(textLayout)
        } else if let view = self.headerView {
            performSubviewRemoval(view, animated: animated)
            self.headerView = nil
        }
        
        if let textLayout = item.infoLayout {
            let current: TextView
            if let view = self.infoView {
                current = view
            } else {
                current = TextView()
                current.userInteractionEnabled = false
                current.isSelectable = false
                self.infoView = current
                addSubview(current)
            }
            current.update(textLayout)
        } else if let view = self.infoView {
            performSubviewRemoval(view, animated: animated)
            self.infoView = nil
        }
                     
        optionsView.spacing = 20
        optionsView.update(options: item.options)
        
        nameControl.isHidden = item.isPreview || !item.hasToggle
        
        nameView.update(item.nameEnabledLayout)
        nameToggle.set(selected: item.nameEnabled, animated: animated)
        nameToggle.isAccessibilityDecorative = true
        nameControl.setAccessibilityLabel(item.nameEnabledLayout?.attributedString.string)
        nameControl.setAccessibilityValue(item.nameEnabled ? strings().voiceOverCommonChecked : strings().voiceOverCommonUnchecked)
        
        nameControl.setSingle(handler: { [weak item] _ in
            item?.toggleName()
        }, for: .Click)
        needsLayout = true
    }
    
}




private final class HeaderItem : GeneralRowItem {
    
    
    public class ActionItem {
        public var context: (any AccountContextProtocol)
        public var title: TextViewLayout
        public var image: CGImage
        public var action:()->Void
        public var size: NSSize = .zero
      
        
        public init(context: (any AccountContextProtocol), title: String, image: CGImage, action: @escaping () -> Void, locked: Bool = false, color: NSColor = .white) {
            self.context = context
            let attr = NSMutableAttributedString()

            attr.append(string: title, color: color.withAlphaComponent(0.8), font: .normal(.text))

            if locked {
                attr.insert(.initialize(string: clown), at: 0)
                attr.insertEmbedded(.embedded(name: "Icon_EmojiLock", color: color.withAlphaComponent(0.8), resize: false), for: clown)
                attr.append(string: " ")
            }
            self.title = .init(attr)
            self.image = image.highlight(color: color)
            self.action = action
        }
        
        public func measure(width: CGFloat) {
            self.title.measure(width: width)
            self.size = NSMakeSize(width, 80)
        }
    }
    
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let title: TextViewLayout
    fileprivate let info: TextViewLayout?
    fileprivate let arguments:Arguments
    fileprivate let attributes: [StarGift.UniqueGift.Attribute]
    fileprivate let source: StarGiftNftSource

    fileprivate let variansLayout: TextViewLayout?
    fileprivate let onSaleLayout: TextViewLayout?

    fileprivate var patterns:[TelegramMediaFile] = []
    fileprivate var backdrops:[StarGift.UniqueGift.Attribute] = []
    fileprivate var models:[StarGift.UniqueGift.Attribute] = []

    private var patternIndex: Int = 0
    private var backdropIndex: Int = 0
    private var modelIndex: Int = 0
    
    private let converted: Bool
    
    public let uniqueGift: StarGift.UniqueGift?
    public let state: State

    public var actions: [ActionItem] = []
    
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: (any AccountContextProtocol), arguments: Arguments, state: State, attributes: [StarGift.UniqueGift.Attribute], source: StarGiftNftSource) {
        self.arguments = arguments
        self.context = context
        self.attributes = attributes
        self.converted = state.converted
        self.source = source
        self.state = state
        switch state.gift {
        case let .unique(gift):
            self.uniqueGift = gift
        default:
            self.uniqueGift = nil
        }

        self.patterns = attributes.compactMap { attribute in
            switch attribute {
            case let .pattern(_, file, _):
                return file
            default:
                return nil
            }
        }
        
        self.backdrops = attributes.compactMap { attribute in
            switch attribute {
            case .backdrop:
                return attribute
            default:
                return nil
            }
        }
        
        self.models = attributes.compactMap { attribute in
            switch attribute {
            case .model:
                return attribute
            default:
                return nil
            }
        }
                
        
        if case .upgrade = state.source, let gift = state.gift.generic, gift.upgradeVariantsCount != nil {
            let attr = NSMutableAttributedString()
            attr.append(string: strings().starGiftViewAllVariants(clown_space), color: darkPalette.background, font: .medium(.title))
            attr.insertEmbedded(.embeddedAnimated(gift.file), for: clown)
            attr.replaceChevron(color: darkPalette.background)
            self.variansLayout = .init(attr, alignment: .center)
            self.variansLayout?.measure(width: .greatestFiniteMagnitude)
            self.info = .init(.init(), alignment: .center)
            
            self.onSaleLayout = nil
        } else if state.canManage, let uniqueGift = state.gift.unique, let resell = uniqueGift.resell {
            let attr = NSMutableAttributedString()
            attr.append(string: strings().starNftOnSaleFor(clown_space), color: darkPalette.background, font: .medium(.title))
            if resell.currency == .ton {
                attr.insertEmbedded(.embedded(name: "Icon_Ton_Currency", color: darkPalette.background, resize: false), for: clown)
            } else {
                attr.insertEmbedded(.embedded(name: XTR_ICON, color: darkPalette.background, resize: false), for: clown)
            }
            attr.append(string: resell.formatted, color: darkPalette.background, font: .medium(.title))
            self.onSaleLayout = .init(attr, alignment: .center)
            self.onSaleLayout?.measure(width: .greatestFiniteMagnitude)
            
            self.info = .init(.initialize(string: "", color: NSColor.white.withAlphaComponent(0.8), font: .normal(.text)), alignment: .center)
            
            self.variansLayout = nil
        } else {
            self.variansLayout = nil
            self.onSaleLayout = nil
            self.info = .init(.initialize(string: state.headerInfo, color: NSColor.white.withAlphaComponent(0.8), font: .normal(.text)), alignment: .center)
        }

        self.title = .init(state.headerTitle)
        
       

        for model in models {
            switch model {
            case let .model(_, file, _, _):
                _ = freeMediaFileInteractiveFetched(context: context, fileReference: .standalone(media: file)).start()
            default:
                break
            }
        }
        
        switch source {
        case .quickLook(_, _):
            if let uniqueGift = uniqueGift, let owner = state.owner, owner.id == context.peerId || owner._asPeer().groupAccess.canManageGifts || owner.id == uniqueGift.hostPeerId {
                let actionColor: NSColor = (uniqueGift.backdrop?.first?.lightness ?? 1.0) > 0.8 ? .black : .white
                actions = [.init(context: context, title: strings().starNftTransfer, image: TelegramThemeHooks.shared.image(.iconNFTTransfer).precomposed(.white), action: {
                    arguments.transfer()
                }, locked: uniqueGift.hostPeerId != nil, color: actionColor), .init(context: context, title: state.weared ? strings().starNftTakeOff : strings().starNftWear, image: TelegramThemeHooks.shared.image(.iconNFTWear).precomposed(.white), action: {
                    arguments.toggleWear(uniqueGift)
                }, color: actionColor)]

                if case .starGift = state.purpose {
                    actions.append(.init(context: context, title: uniqueGift.resellStars(context) != nil ? strings().starNftUnlist : strings().starNftSell, image: TelegramThemeHooks.shared.image(uniqueGift.resellStars(context) != nil ? .iconNftUnlist : .iconNftSell).precomposed(.white), action: {
                        arguments.sellNft(uniqueGift, false)
                    }, locked: uniqueGift.hostPeerId != nil, color: actionColor))
                } else {
                    actions.append(.init(context: context, title: strings().starNftShare, image: TelegramThemeHooks.shared.image(.iconNFTShare).precomposed(.white), action: {
                        arguments.shareNft(uniqueGift)
                    }, color: actionColor))
                }
                
            }
        default:
            break
        }
        
        
        
        super.init(initialSize, stableId: stableId)
    }
    
    public func makeNextPattern() {
        if !converted {
            patternIndex = Int.random(in: 0..<patterns.count)
            backdropIndex = Int.random(in: 0..<backdrops.count)
            modelIndex = Int.random(in: 0..<models.count)
        }
        
    }
    
    public var model: TelegramMediaFile {
        switch self.models[self.modelIndex] {
        case let .model(_, file, _, _):
            return file
        default:
            fatalError()
        }
    }
    public var pattern: TelegramMediaFile {
        return self.patterns[self.patternIndex]
    }
    
    public var patternColor: NSColor {
        let value = self.backdrops[self.backdropIndex]
        switch value {
        case let .backdrop(_, _, _, _, patternColor, _, _):
            return NSColor(UInt32(bitPattern: patternColor))
        default:
            fatalError()
        }
    }

    public var cyclesVariants: Bool {
        return !self.converted
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)

        self.title.measure(width: width - 40)
        self.info?.measure(width: width - 40)

        if state.author != nil, case .preview = state.source {
            self.info?.generateAutoBlock(backgroundColor: patternColor.withAlphaComponent(0.4))
        }

        for action in actions {
            action.measure(width: 120)
        }

        return true
    }
    
    public override var height: CGFloat {
        var height: CGFloat = 0

        height += 30
        height += 100
        height += 20

        height += title.layoutSize.height
        height += 5
        height += 20//info.layoutSize.height
        height += 10

        if !actions.isEmpty {
            height += 70
        }

        return height
    }
    
    public override func viewClass() -> AnyClass {
        return HeaderView.self
    }
    
    override var accessibilityLabel: String? {
        return title.attributedString.string
    }
    
    override var accessibilityValue: String? {
        let value = (onSaleLayout ?? info)?.attributedString.string
        return value?.isEmpty == false ? value : nil
    }
    
    public var backgroundContent: UniqueGiftBackgroundContent? {
        switch self.backdrops[self.backdropIndex] {
        case let .backdrop(_, _, inner, outer, patternColor, _, _):
            return UniqueGiftBackgroundContent(colors: UniqueGiftColors(center: inner, edge: outer, pattern: patternColor), pattern: .file(self.pattern))
        default:
            return nil
        }
    }
}

private final class HeaderView : GeneralRowView {
    private let textView = TextView()
    private let infoView = TextView()
    private let dismiss = ImageButton()
    private var actions: ImageButton?
    private var craftButton: ImageButton?
    private let giftView = StarsHooks.shared.makeStickerView(NSMakeRect(0, 0, 100, 100))
    private let backgroundView = UniqueGiftBackgroundView(frame: .zero)

    private var avatarView: AvatarControl?

    private var ownerActions: View?

    private var variantsView: InteractiveTextView?
    private var variantsGlass: LiquidGlassView?
    private var onSaleView: InteractiveTextView?
    private var onSaleGlass: LiquidGlassView?

    private let buttonsContainer = View()
    private weak var tableView: TableView?

    public class ActionView : Control {
        private let textView: InteractiveTextView = InteractiveTextView()
        private let imageView = ImageView()
        private var glassView: LiquidGlassView?
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            textView.userInteractionEnabled = false
            textView.textView.isSelectable = false
            addSubview(textView)
            addSubview(imageView)
            imageView.isAccessibilityDecorative = true
        }

        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        public func set(item: HeaderItem.ActionItem, glassTint: NSColor?, fill: NSColor) {
            self.textView.set(text: item.title, context: item.context)
            self.setAccessibilityLabel(item.title.attributedString.string)
            self.imageView.image = item.image
            self.imageView.sizeToFit()

            if let glassTint {
                let glass: LiquidGlassView
                if let current = self.glassView {
                    glass = current
                } else {
                    glass = LiquidGlassView(frame: bounds, cornerRadius: 20, hasShadow: true, hasBorder: true, forceAppearance: .forceLight)
                    addSubview(glass, positioned: .below, relativeTo: nil)
                    self.glassView = glass
                }
                glass.customTint = glassTint
                self.background = .clear
                self.layer?.cornerRadius = 0
                self.layer?.masksToBounds = false
                self.scaleOnClick = false
                self.stretchReferenceView = glass
            } else {
                if let glass = self.glassView {
                    glass.removeFromSuperview()
                    self.glassView = nil
                }
                self.stretchReferenceView = nil
                self.background = fill
                self.layer?.cornerRadius = 20
                self.scaleOnClick = true
            }

            setSingle(handler: { [weak item] _ in
                item?.action()
            }, for: .Click)

            needsLayout = true
        }

        public override func layout() {
            super.layout()

            glassView?.frame = bounds
            glassView?.updateLayout(size: bounds.size, transition: .immediate)
            imageView.centerX(y: 5)
            textView.centerX(y: frame.height - textView.frame.height - 10)
        }
    }
    
    private var timer: SwiftSignalKit.Timer?
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(backgroundView)
        addSubview(giftView)
        addSubview(textView)
        addSubview(infoView)

        buttonsContainer.addSubview(dismiss)
        buttonsContainer.layer?.masksToBounds = false
        infoView.isSelectable = false

        textView.isSelectable = false

        (giftView as? Control)?.scaleOnClick = true
        (giftView as? Control)?.tooltipOnclick = true

    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview != nil {
            if let tv = item?.table, buttonsContainer.superview != tv {
                self.tableView = tv
                tv.addSubview(buttonsContainer)
                updateButtonsLayout()
            }
        } else {
            buttonsContainer.removeFromSuperview()
            tableView = nil
        }
    }

    private func updateButtonsLayout() {
        guard let tableView = tableView else { return }
        let tableSize = tableView.frame.size
        buttonsContainer.frame = NSMakeRect(0, 0, tableSize.width, 50)

        dismiss.setFrameOrigin(NSMakePoint(10, 10))

        if let actions {
            actions.setFrameOrigin(NSMakePoint(tableSize.width - actions.frame.width - 10, 10))
        }

        if let craftButton {
            let x = (actions?.frame.minX ?? (tableSize.width - 10)) - craftButton.frame.width - 5
            craftButton.setFrameOrigin(NSMakePoint(x, 10))
        }
    }

    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? HeaderItem else {
            return
        }
        
        let iconColor: NSColor = (item.uniqueGift?.backdrop?.first?.lightness ?? 1.0) > 0.8 ? NSColor(0x000000) : NSColor(0xffffff)

        dismiss.set(image: TelegramThemeHooks.shared.image(.iconPipClose).precomposed(iconColor), for: .Normal)
        dismiss.scaleOnClick = true
        dismiss.autohighlight = false
        dismiss.setGlassEffect(size: NSMakeSize(36, 36), tintColor: item.uniqueGift?.backdrop?.first, forceAppearance: .forceLight)
        dismiss.glassTintColor = item.uniqueGift?.backdrop?.first
        dismiss.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        dismiss.setAccessibilityLabel(strings().voiceOverCommonClose)

        dismiss.setSingle(handler: { [weak item] _ in
            item?.arguments.dismiss()
        }, for: .Click)
        
        
        
        if let uniqueGift = item.uniqueGift, !item.source.isWearing {
            let current: ImageButton
            if let view = self.actions {
                current = view
            } else {
                current = ImageButton()
                buttonsContainer.addSubview(current)
                self.actions = current
                current.autohighlight = false
                current.scaleOnClick = true
                current.setAccessibilityLabel(strings().voiceOverCommonMore)
            }
            current.set(image: TelegramThemeHooks.shared.image(.iconChatActions).precomposed(iconColor), for: .Normal)
            current.setGlassEffect(size: NSMakeSize(36, 36), tintColor: item.uniqueGift?.backdrop?.first, forceAppearance: .forceLight)

            current.glassTintColor = item.uniqueGift?.backdrop?.first
            current.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)

            current.contextMenu = {
                let menu = ContextMenu()
                if case .quickLook = item.state.source, let profileGiftMenu = item.arguments.profileGiftMenu {
                    menu.items = profileGiftMenu()
                    return menu
                }

                let owner = item.state.owner?._asPeer()
                let visibility = item.state.profileVisibility

                if case let .peerId(peerId) = uniqueGift.owner, peerId == item.arguments.context.peerId || owner?.groupAccess.isCreator == true, let pinnedInfo = item.state.pinnedInfo, visibility?.saved != false {
                    menu.addItem(ContextMenuItem(pinnedInfo.pinnedInfo ? strings().messageContextUnpin : strings().messageContextPin, handler: item.arguments.togglePin, itemImage: pinnedInfo.pinnedInfo ? MenuAnimation.menu_unpin.value : MenuAnimation.menu_pin.value))
                }

                menu.addItem(ContextMenuItem(strings().contextCopy, handler: {
                    item.arguments.copyNftLink(uniqueGift)
                }, itemImage: MenuAnimation.menu_copy_link.value))
                
                menu.addItem(ContextMenuItem(strings().storyMyInputShare, handler: {
                    item.arguments.shareNft(uniqueGift)
                }, itemImage: MenuAnimation.menu_share.value))
                
                
                if case let .peerId(peerId) = uniqueGift.owner, peerId == item.arguments.context.peerId {
                    if uniqueGift.flags.contains(.isThemeAvailable) {
                        menu.addItem(ContextMenuItem(
                            strings().giftContextMenuSetAsTheme,
                            handler: {
                                item.arguments.setAsTheme(uniqueGift)
                            },
                            itemImage: MenuAnimation.menu_change_colors.value
                        ))
                    }
                }
                
                if case let .peerId(peerId) = uniqueGift.owner, peerId == item.arguments.context.peerId || owner?.groupAccess.isCreator == true {
                    
                    
                    if let visibility {
                        menu.addItem(ContextMenuItem(visibility.saved ? strings().giftViewContextHideFromProfile : strings().giftViewContextShowOnProfile, handler: item.arguments.toggleProfileVisibility, itemImage: visibility.saved ? MenuAnimation.menu_eye_slash.value : MenuAnimation.menu_eye.value))
                    }
                                        
                    menu.addItem(ContextMenuItem(strings().giftTransferConfirmationTransferFree, handler: {
                        item.arguments.transfer()
                    }, itemImage: MenuAnimation.menu_replace.value))
                    
                    if uniqueGift.craftChancePermille != nil {
                        menu.addItem(ContextMenuItem(strings().starGiftCraftMenuItem, handler: {
                            item.arguments.startCrafting()
                        }, itemImage: MenuAnimation.menu_craft.value))
                    }
                }
                
                if let moveToGifts = StarsHooks.shared.giftMoveToGiftsAction(item.arguments.context, item.arguments.context.window, uniqueGift) {
                    menu.addItem(ContextMenuItem(strings().giftTransferMoveToGifts, handler: moveToGifts, itemImage: MenuAnimation.menu_replace.value))
                }

                if !item.state.canManage, let peer = item.state.owner {
                    menu.addItem(ContextMenuItem(strings().starGiftNftOfferToBuy, handler: {
                        item.arguments.makeOffer(uniqueGift, peer)
                    }, itemImage: MenuAnimation.menu_paid.value))
                }
                
                return menu
            }

            if case .aboutCraft = item.source {
                if let craftBtn = self.craftButton {
                    craftBtn.removeFromSuperview()
                    self.craftButton = nil
                }
            } else if item.state.canManage, item.state.gift.unique?.craftChancePermille != nil {
                let craftBtn: ImageButton
                if let view = self.craftButton {
                    craftBtn = view
                } else {
                    craftBtn = ImageButton()
                    buttonsContainer.addSubview(craftBtn)
                    self.craftButton = craftBtn
                    craftBtn.autohighlight = false
                    craftBtn.scaleOnClick = true
                    craftBtn.setAccessibilityLabel(strings().starGiftCraftMenuItem)
                }
                let craftColor: NSColor = iconColor
                craftBtn.set(image: TelegramThemeHooks.shared.image(.iconNftAnvil).precomposed(craftColor), for: .Normal)
                craftBtn.setGlassEffect(size: NSMakeSize(36, 36), tintColor: item.uniqueGift?.backdrop?.first, forceAppearance: .forceLight)
                craftBtn.glassTintColor = item.uniqueGift?.backdrop?.first

                craftBtn.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
                craftBtn.removeAllHandlers()
                craftBtn.set(handler: { [weak item] _ in
                    if let uniqueGift = item?.uniqueGift {
                        item?.arguments.openCraftAbout(uniqueGift)
                    }
                }, for: .Click)
            } else {
                if let craftBtn = self.craftButton {
                    craftBtn.removeFromSuperview()
                    self.craftButton = nil
                }
            }
        } else {
            if let craftBtn = self.craftButton {
                craftBtn.removeFromSuperview()
                self.craftButton = nil
            }
        }


        switch item.source {
        case let .previewWear(peer, _):
            let current: AvatarControl
            if let view = avatarView {
                current = view
            } else {
                current = AvatarControl(font: .avatar(18))
                current.setFrameSize(100, 100)
                self.avatarView = current
                addSubview(current)
                
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
            current.setPeer(account: item.context.account, peer: peer._asPeer())
            giftView.setFrameSize(NSMakeSize(25, 25))
            if let gift = item.uniqueGift {
                (giftView as? Control)?.appTooltip = "\(gift.title) #\(gift.number)"
                (giftView as? Control)?.tooltipOnclick = true
            }
        default:
            if let avatarView {
                performSubviewRemoval(avatarView, animated: animated)
                self.avatarView = nil
            }
            giftView.setFrameSize(NSMakeSize(100, 100))
            (giftView as? Control)?.appTooltip = nil
        }
        
        let update:()->Void = { [weak self] in
            guard let self else {
                return
            }
            self.updateBackground(animated: true)
            (self.giftView as? StarsStickerView)?.updateStarsSticker(file: item.model, size: giftView.frame.size, context: item.context, colors: [], playback: .standard, animated: animated)
        }
        
        self.timer?.invalidate()
        if item.cyclesVariants {
            self.timer = .init(timeout: 2.5, repeat: true, completion: {
                item.makeNextPattern()
                update()
            }, queue: .mainQueue())
            self.timer?.start()
        } else {
            self.timer = nil
        }
        update()
        
        if !item.actions.isEmpty {
            
            let current: View
            if let view = ownerActions {
                current = view
            } else {
                current = View()
                current.layer?.masksToBounds = false
                addSubview(current)
                self.ownerActions = current
            }
            
            while current.subviews.count > item.actions.count {
                current.subviews.removeLast()
            }
            
            while current.subviews.count < item.actions.count {
                current.addSubview(ActionView(frame: .zero))
            }
            
            for (i, action) in item.actions.enumerated() {
                let view = current.subviews[i] as! ActionView

                let textColor = item.uniqueGift?.backdrop?.first?.lightness ?? 1.0 > 0.8 ? NSColor(0x000000) : NSColor(0xffffff)
                let glassTint = System.liquidGlass ? item.uniqueGift?.backdrop?.first : nil

                view.set(item: action, glassTint: glassTint, fill: textColor.withAlphaComponent(0.2))
            }
            
        } else if let view = ownerActions {
            performSubviewRemoval(view, animated: animated)
            self.ownerActions = nil
        }
        
                
        textView.update(item.title)
        infoView.update(item.info)

        if let author = item.state.author {
            let context = item.context
            
            infoView.setSingle(handler: { [weak item] view in
                if let event = NSApp.currentEvent {
                    let data = context.engine.data.subscribe(
                        TelegramEngine.EngineData.Item.Peer.Peer(id: author.id),
                        TelegramEngine.EngineData.Item.Peer.AboutText(id: author.id)
                    ) |> take(1) |> deliverOnMainQueue
                    
                    _ = data.start(next: { [weak view, weak item] data in
                        
                        guard let peer = data.0, let view = view else {
                            return
                        }
                        
                        var firstBlock:[ContextMenuItem] = []
                        let secondBlock:[ContextMenuItem] = []
                        let thirdBlock: [ContextMenuItem] = []
                        
                        if let avatarItem = StarsHooks.shared.makeAvatarMenuItem(context, peer._asPeer()) {
                            firstBlock.append(avatarItem)
                        }
                        
                        firstBlock.append(ContextMenuItem(peer._asPeer().displayTitle, handler: {
                            item?.arguments.openPeer(peer, true)
                        }, itemImage: MenuAnimation.menu_open_profile.value))
                        
                        if let username = peer.addressName {
                            firstBlock.append(ContextMenuItem("\(username)", handler: {
                                item?.arguments.openPeer(peer, true)
                            }, itemImage: MenuAnimation.menu_atsign.value))
                        }
                        
                        switch data.1 {
                        case let .known(about):
                            if let about = about, !about.isEmpty {
                                firstBlock.append(ContextMenuItem(about, handler: {
                                    item?.arguments.openPeer(peer, true)
                                }, itemImage: MenuAnimation.menu_bio.value, removeTail: false, overrideWidth: 200))
                            }
                        default:
                            break
                        }
                        
                        let blocks:[[ContextMenuItem]] = [firstBlock,
                                                          secondBlock,
                                                          thirdBlock].filter { !$0.isEmpty }
                        var items: [ContextMenuItem] = []

                        for (i, block) in blocks.enumerated() {
                            if i != 0 {
                                items.append(ContextSeparatorItem())
                            }
                            items.append(contentsOf: block)
                        }
                        
                        let menu = ContextMenu()
                        
                        for item in items {
                            menu.addItem(item)
                        }
                        AppMenu.show(menu: menu, event: event, for: view)
                    })
                }
            }, for: .Click)
        } else {
            infoView.removeAllHandlers()
        }
        
        if let displayLayout = item.variansLayout {
            let current: InteractiveTextView
            if let view = self.variantsView {
                current = view
            } else {
                current = InteractiveTextView(frame: .zero)
                current.userInteractionEnabled = true
                current.scaleOnClick = true
                self.variantsView = current
                self.addSubview(current)
            }
            
            current.set(text: displayLayout, context: item.context)
            current.setFrameSize(NSMakeSize(displayLayout.layoutSize.width + 8, displayLayout.layoutSize.height + 8))
            current.layer?.cornerRadius = current.frame.height / 2

            if self.variantsGlass == nil {
                let glass = LiquidGlassView(frame: current.bounds, cornerRadius: current.frame.height / 2, hasShadow: true, hasBorder: true, forceAppearance: .forceLight)
                glass.autoresizingMask = [.width, .height]
                self.variantsGlass = glass
                current.addSubview(glass, positioned: .below, relativeTo: nil)
            }
            self.variantsGlass?.cornerRadius = current.frame.height / 2
            self.variantsGlass?.customTint = item.uniqueGift?.backdrop?.first
            current.layer?.masksToBounds = false
            current.interactiveGlassView = self.variantsGlass

            current.setSingle(handler: { [weak item] _ in
                if let gift = item?.state.gift {
                    item?.arguments.showModels(gift, .models)
                }
            }, for: .Click)
        } else if let view = self.variantsView {
            performSubviewRemoval(view, animated: animated)
            self.variantsView = nil
            self.variantsGlass = nil
        }

        if let displayLayout = item.onSaleLayout {
            let current: InteractiveTextView
            if let view = self.onSaleView {
                current = view
            } else {
                current = InteractiveTextView(frame: .zero)
                current.userInteractionEnabled = true
                current.scaleOnClick = true
                self.onSaleView = current
                self.addSubview(current)
            }

            current.set(text: displayLayout, context: item.context)
            current.setFrameSize(NSMakeSize(displayLayout.layoutSize.width + 16, displayLayout.layoutSize.height + 8))
            current.layer?.cornerRadius = current.frame.height / 2

            if self.onSaleGlass == nil {
                let glass = LiquidGlassView(frame: current.bounds, cornerRadius: current.frame.height / 2, hasShadow: true, hasBorder: true, forceAppearance: .forceLight)
                glass.autoresizingMask = [.width, .height]
                self.onSaleGlass = glass
                current.addSubview(glass, positioned: .below, relativeTo: nil)
            }
            self.onSaleGlass?.cornerRadius = current.frame.height / 2
            self.onSaleGlass?.customTint = item.uniqueGift?.backdrop?.first
            current.layer?.masksToBounds = false
            current.interactiveGlassView = self.onSaleGlass

            current.setSingle(handler: { [weak item] _ in
                if let uniqueGift = item?.uniqueGift {
                    item?.arguments.sellNft(uniqueGift, true)
                }
            }, for: .Click)
        } else if let view = self.onSaleView {
            performSubviewRemoval(view, animated: animated)
            self.onSaleView = nil
            self.onSaleGlass = nil
        }
    }

    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        
        if let ownerActions {
            ownerActions.setFrameSize(NSMakeSize(size.width, 60))
            ownerActions.centerX(y: size.height - ownerActions.frame.height - 10)

            let itemSize = (frame.width - (CGFloat(ownerActions.subviews.count + 1) * 10)) / CGFloat(ownerActions.subviews.count)
            var x: CGFloat = 10
            for subview in ownerActions.subviews {
                subview.frame = NSMakeRect(x, 0, itemSize, ownerActions.frame.height)
                x += subview.frame.width + 10
            }
        }

        if let ownerActions {
            infoView.centerX(y: ownerActions.frame.minY - 20 - 15)
            variantsView?.centerX(y: ownerActions.frame.minY - 20 - 10)
            onSaleView?.centerX(y: ownerActions.frame.minY - 20 - 15)
        } else {
            infoView.centerX(y: size.height - 20 - 20)
            variantsView?.centerX(y: size.height - 20 - 15)
            onSaleView?.centerX(y: size.height - 20 - 15)
        }
        
        transition.updateFrame(view: backgroundView, frame: size.bounds)

        updateButtonsLayout()

        if let avatarView {
            avatarView.centerX(y: 30)
            textView.centerX(y: infoView.frame.minY - textView.frame.height - 5, addition: -10)
            giftView.setFrameOrigin(NSMakePoint(textView.frame.maxX + 2, textView.frame.minY - 3))
        } else {
            giftView.centerX(y: 30)
            textView.centerX(y: infoView.frame.minY - textView.frame.height - 5)
        }
        updateBackground(animated: false)
    }

    private func updateBackground(animated: Bool) {
        guard let item = item as? HeaderItem, let content = item.backgroundContent else {
            backgroundView.isHidden = true
            return
        }
        backgroundView.isHidden = false
        let giftCenterY = (avatarView ?? giftView).frame.midY
        backgroundView.update(context: item.context, content: content, style: .header(patternCenterY: giftCenterY + 16), animated: animated)
    }
    
    public override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)

    }
}



private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let dismiss:()->Void
    public let toggleName:()->Void
    public let transfer:()->Void
    public let copyNftLink:(StarGift.UniqueGift)->Void
    public let shareNft:(StarGift.UniqueGift)->Void
    public let sellNft:(StarGift.UniqueGift, Bool)->Void
    public let toggleWear:(StarGift.UniqueGift)->Void
    public let togglePin:()->Void
    public let openPeer:(EnginePeer, Bool)->Void
    public let openValue:(StarGift.UniqueGift)->Void
    public let setAsTheme:(StarGift.UniqueGift)->Void
    public let deleteOriginalInfo:(StarGift.UniqueGift, NSAttributedString)->Void
    public let makeOffer:(StarGift.UniqueGift, EnginePeer)->Void
    public let showModels:(StarGift, StarGift_Builder_Section)->Void

    public let startCrafting:()->Void
    public let toggleCraftGift:(ProfileGiftsContext.State.StarGift)->Void
    public let showCraftModels:(StarGift.UniqueGift, StarGift_Builder_Section)->Void
    public let showCraftMarketplace:(Int)->Void
    public let showCraftAbout:()->Void
    public let showBackdropChanceHint:(String, Int)->Void
    public let showPatternChanceHint:(String, Int)->Void
    public let openCraftAbout:(StarGift.UniqueGift)->Void
    public let performCraft:(@escaping()->Void, @escaping(ProfileGiftsContext.State.StarGift)->Void, @escaping([ProfileGiftsContext.State.StarGift])->Void, @escaping()->Void)->Void
    public let showCraftVariants:()->Void
    public let craftAnother:()->Void
    public let showCraftSuccess:(StarGift.UniqueGift)->Void
    public let okAction:()->Void
    public var toggleProfileVisibility:()->Void = {}
    var profileGiftMenu: (() -> [ContextMenuItem])?

    public init(context: (any AccountContextProtocol), window: @escaping () -> Window, dismiss:@escaping()->Void, toggleName:@escaping()->Void, transfer:@escaping()->Void, copyNftLink:@escaping(StarGift.UniqueGift)->Void, shareNft:@escaping(StarGift.UniqueGift)->Void, sellNft:@escaping(StarGift.UniqueGift, Bool)->Void, toggleWear:@escaping(StarGift.UniqueGift)->Void, togglePin:@escaping()->Void, openPeer:@escaping(EnginePeer, Bool)->Void, openValue:@escaping(StarGift.UniqueGift)->Void, setAsTheme:@escaping(StarGift.UniqueGift)->Void, deleteOriginalInfo:@escaping(StarGift.UniqueGift, NSAttributedString)->Void, makeOffer:@escaping(StarGift.UniqueGift, EnginePeer)->Void, showModels:@escaping(StarGift, StarGift_Builder_Section)->Void, startCrafting:@escaping()->Void, toggleCraftGift:@escaping(ProfileGiftsContext.State.StarGift)->Void, showCraftModels:@escaping(StarGift.UniqueGift, StarGift_Builder_Section)->Void, showCraftMarketplace:@escaping(Int)->Void, showCraftAbout:@escaping()->Void, showBackdropChanceHint:@escaping(String, Int)->Void, showPatternChanceHint:@escaping(String, Int)->Void, openCraftAbout:@escaping(StarGift.UniqueGift)->Void, performCraft:@escaping(@escaping()->Void, @escaping(ProfileGiftsContext.State.StarGift)->Void, @escaping([ProfileGiftsContext.State.StarGift])->Void, @escaping()->Void)->Void, showCraftVariants:@escaping()->Void, craftAnother:@escaping()->Void, showCraftSuccess:@escaping(StarGift.UniqueGift)->Void, okAction:@escaping()->Void) {
        self.context = context
        self.dismiss = dismiss
        self.toggleName = toggleName
        self.transfer = { withGiftModalSource(for: window(), perform: transfer) }
        self.copyNftLink = copyNftLink
        self.shareNft = { gift in withGiftModalSource(for: window()) { shareNft(gift) } }
        self.sellNft = { gift, edit in withGiftModalSource(for: window()) { sellNft(gift, edit) } }
        self.toggleWear = toggleWear
        self.togglePin = togglePin
        self.openPeer = openPeer
        self.openValue = { gift in withGiftModalSource(for: window()) { openValue(gift) } }
        self.setAsTheme = { gift in withGiftModalSource(for: window()) { setAsTheme(gift) } }
        self.deleteOriginalInfo = { gift, text in withGiftModalSource(for: window()) { deleteOriginalInfo(gift, text) } }
        self.makeOffer = { gift, peer in withGiftModalSource(for: window()) { makeOffer(gift, peer) } }
        self.showModels = { gift, section in withGiftModalSource(for: window()) { showModels(gift, section) } }
        self.startCrafting = startCrafting
        self.toggleCraftGift = toggleCraftGift
        self.showCraftModels = { gift, section in withGiftModalSource(for: window()) { showCraftModels(gift, section) } }
        self.showCraftMarketplace = { slot in withGiftModalSource(for: window()) { showCraftMarketplace(slot) } }
        self.showCraftAbout = showCraftAbout
        self.showBackdropChanceHint = showBackdropChanceHint
        self.showPatternChanceHint = showPatternChanceHint
        self.openCraftAbout = openCraftAbout
        self.performCraft = performCraft
        self.showCraftVariants = { withGiftModalSource(for: window(), perform: showCraftVariants) }
        self.craftAnother = { withGiftModalSource(for: window(), perform: craftAnother) }
        self.showCraftSuccess = showCraftSuccess
        self.okAction = { withGiftModalSource(for: window(), perform: okAction) }
    }
}

private struct State : Equatable {
    public var source: StarGiftNftSource
    public var gift: StarGift
    public var _nextUpgradeGifts:[ProfileGiftsContext.State.StarGift] = []
    
    public var peerMap:[PeerId: EnginePeer] = [:]
    
    public var nextUpgradeGifts: [ProfileGiftsContext.State.StarGift] {
        return _nextUpgradeGifts.filter({ value in
            if let reference = value.reference {
                return !ignoreUpgradeGifts.contains(reference)
            } else {
                return false
            }
        })
    }
    
    public var takeNextUpgradeGift: ProfileGiftsContext.State.StarGift? {
        return canUpgradeNext ? self.nextUpgradeGifts.first : nil
    }
    
    public var ignoreUpgradeGifts: Set<StarGiftReference> = Set()
    public var transaction: StarsContext.State.Transaction?
    public var nameEnabled: Bool = true
    public var converted: Bool = false
    public var canUpgradeNext: Bool = false
    public var author: EnginePeer?
    
    public var purpose: Star_TransactionPurpose?
    
    public var weared: Bool {
        guard let unique = gift.unique, case let .starGift(id, _, _, _, _, _, _, _, _)? = owner?.emojiStatus?.content else {
            return false
        }
        return id == unique.id
    }
    
    public var upgradeForm: BotPaymentForm?
        
    public var attributes: [StarGift.UniqueGift.Attribute]
    
    public var starsState: StarsContext.State?
    public var myBalance: StarsAmount?
    public var myTonBalance: StarsAmount?
    public var tonAddress: String? = nil
    public var savedToProfileOverride: Bool?

    public var profileVisibility: (reference: StarGiftReference, saved: Bool)? {
        guard case .quickLook = source, let purpose, case let .starGift(_, _, _, _, _, savedToProfile, _, _, _, _, _, _, reference, _, _, _, _, _, _, _, _, _, _, _) = purpose, let reference else {
            return nil
        }
        return (reference, savedToProfileOverride ?? savedToProfile)
    }
    
    public var owner: EnginePeer?
    public var ownerName: String?
    
    public var isTonOwner: Bool = false
    
    public var accountPeerId: PeerId
    
    public var unique: Int64 = arc4random64()
    
    public var pinnedInfo: GiftPinnedInfo?

    public var droppedInfo = false

    // Crafting state
    public var craftSelectedSlots: [ProfileGiftsContext.State.StarGift?] = [nil, nil, nil, nil]
    public var craftAvailableGifts: [ProfileGiftsContext.State.StarGift] = []
    public var craftIsLoading: Bool = true
    public var craftVariantsCount: Int = 0
    public var craftInitialGiftRef: StarGiftReference? = nil
    public var craftAttributePermilles: [[Int32]] = [
        [90],
        [80, 200],
        [70, 190, 460],
        [60, 180, 450, 1000]
    ]
    public var craftCachedGift: StarGift.Gift?
    public var craftingState: GiftCraftingState = .idle

    public var craftSelectedGifts: [ProfileGiftsContext.State.StarGift] {
        return craftSelectedSlots.compactMap { $0 }
    }

    public var craftSelectedCount: Int {
        return craftSelectedSlots.compactMap { $0 }.count
    }

    public var craftSuccessChance: Int {
        let totalPermille = craftSelectedSlots.compactMap { $0?.gift.unique?.craftChancePermille }.reduce(0, +)
        return Int(totalPermille) / 10
    }

    public var craftBackdropChances: [GiftCraftChanceIndicator] {
        let selectedCount = craftSelectedCount
        guard selectedCount > 0 && selectedCount <= craftAttributePermilles.count else {
            return []
        }
        let permillesForSelectedCount = craftAttributePermilles[selectedCount - 1]

        var seenBackdrops: Set<Int32> = []
        var result: [GiftCraftChanceIndicator] = []

        for gift in craftSelectedGifts {
            guard let unique = gift.gift.unique,
                  let backdropColor = gift.gift.backdropColor else {
                continue
            }

            var backdropId: Int32?
            var backdropName: String?
            for attr in unique.attributes {
                if case let .backdrop(name, id, _, _, _, _, _) = attr {
                    backdropId = id
                    backdropName = name
                    break
                }
            }
            guard let backdropId = backdropId, let backdropName = backdropName else {
                continue
            }

            if seenBackdrops.contains(backdropId) {
                continue
            }
            seenBackdrops.insert(backdropId)

            let matchingCount = craftSelectedGifts.filter { otherGift in
                guard let otherUnique = otherGift.gift.unique else { return false }
                for attr in otherUnique.attributes {
                    if case let .backdrop(_, id, _, _, _, _, _) = attr {
                        return id == backdropId
                    }
                }
                return false
            }.count

            guard matchingCount > 0 && matchingCount <= permillesForSelectedCount.count else {
                continue
            }
            let permille = permillesForSelectedCount[matchingCount - 1]
            let percent = Int(permille) / 10
            result.append(.init(style: .backdrop(backdropColor), name: backdropName, percent: percent))
        }
        return result
    }

    public var craftPatternChances: [GiftCraftChanceIndicator] {
        let selectedCount = craftSelectedCount
        guard selectedCount > 0 && selectedCount <= craftAttributePermilles.count else {
            return []
        }
        let permillesForSelectedCount = craftAttributePermilles[selectedCount - 1]

        var seenPatterns: Set<Int64> = []
        var result: [GiftCraftChanceIndicator] = []

        for gift in craftSelectedGifts {
            guard let unique = gift.gift.unique,
                  let pattern = unique.pattern else {
                continue
            }

            var patternName: String?
            for attr in unique.attributes {
                if case let .pattern(name, _, _) = attr {
                    patternName = name
                    break
                }
            }
            guard let patternName = patternName else {
                continue
            }

            let patternId = pattern.fileId.id
            if seenPatterns.contains(patternId) {
                continue
            }
            seenPatterns.insert(patternId)

            let matchingCount = craftSelectedGifts.filter { $0.gift.unique?.pattern?.fileId == pattern.fileId }.count
            guard matchingCount > 0 && matchingCount <= permillesForSelectedCount.count else {
                continue
            }
            let permille = permillesForSelectedCount[matchingCount - 1]
            let percent = Int(permille) / 10
            result.append(.init(style: .pattern(fileId: patternId), name: patternName, percent: percent))
        }
        return result
    }

    public var canManage: Bool {
        if let purpose {
            switch purpose {
            case let .starGift(_, _, _, _, _, _, _, _, _, _, _, _, reference, _, _, _, _, _, _, _, _, _, _, _):
                return reference != nil
            default:
                break
            }
        }
        return false
    }
    
    public var dropDetailsStars: Int64? {
        if let purpose {
            switch purpose {
            case let .starGift(_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, dropDetailsStars, _, _, _, _, _, _):
                return dropDetailsStars
            default:
                break
            }
        }
        return nil
    }

    public func okText(_ context: (any AccountContextProtocol)) -> String {
        switch source {
        case .preview:
            return strings().modalOK
        case let .quickLook(peer, gift):
            if let purpose {
                switch purpose {
                case let .starGift(_, _, _, _, _, _, _, _, _, _, _, _, reference, _, _, _, _, _, _, _, _, _, _, _):
                    if let _ = reference {
                        var canManage: Bool
                        let peer = peer ?? owner
                        
                        if let peer, peer._asPeer().groupAccess.canManageGifts || peer.id == accountPeerId {
                            canManage = true
                        } else {
                            canManage = false
                        }
                        if canManage {
                            if let _ = self.takeNextUpgradeGift {
                                return strings().starGiftUniqueUpgradeNext
                            }
                            return strings().modalOK
                        }
                    }
                default:
                    break
                }
            }
            if let resellStars = gift.resell {
                return strings().starNftBuyFor(resellStars.fullyFormatted)
            }
            return strings().modalOK
        case .previewWear:
            return strings().giftWearStart
        case let .upgrade(_, preview, _):
            if converted {
                return strings().modalOK
            } else {
                if upgradeForm == nil {
                    return strings().giftUpgradeConfirm
                } else if let upgradeStars = gift.generic?.upgradeStars {
                    
                    let nextPrice = preview.nextPrices.filter { $0.date > context.timestamp }.first ?? preview.prices.last
                    
                    return strings().giftUpgradePay(strings().starListItemCountOther(Int(nextPrice?.stars ?? upgradeStars)))
                } else {
                    return strings().modalOK
                }
            }
        case .giftUpgrade:
            if let upgradeStars = gift.generic?.upgradeStars {
                return strings().starGiftValuePayForUpgrade(
                    strings().starListItemCountOther(Int(upgradeStars))
                )
            } else {
                return strings().modalOK
            }
        case .aboutCraft, .crafting:
            return ""
        case .craftSuccess:
            return strings().starGiftCraftAnotherGift
        }
    }

    public var headerTitle: NSAttributedString {
        let baseFontSize: CGFloat = 18
        switch source {
        case .preview:
            return .initialize(string: strings().giftUpgradeIncludeTitle, color: .white, font: .medium(baseFontSize))
        case let .previewWear(peer, _):
            return .initialize(string: peer._asPeer().displayTitle, color: .white, font: .medium(baseFontSize))
        case .giftUpgrade:
            return .initialize(string: strings().starGiftUniqueMake, color: .white, font: .medium(baseFontSize))
        case .aboutCraft:
            return .initialize(string: strings().starGiftCraftHeaderTitle, color: .white, font: .medium(baseFontSize))
        case .crafting:
            return .initialize(string: "", color: .white, font: .medium(baseFontSize))
        default:
            if let unique = gift.unique {
                let attr = NSMutableAttributedString()
                let numberFontSize: CGFloat = unique.number < 1000 ? baseFontSize + 2 : baseFontSize
                attr.append(.initialize(string: unique.title, color: .white, font: .medium(baseFontSize)))
                attr.append(.initialize(string: " #\(unique.number)", color: NSColor.white.withAlphaComponent(0.8), font: .medium(numberFontSize)))
                return attr
            } else {
                return .initialize(string: strings().giftUpgradeTitle, color: .white, font: .medium(baseFontSize))
            }
        }
    }
    public var headerInfo: String {
        switch source {
        case .preview(let peer, _):
            return strings().giftUpgradeIncludeDescription(peer._asPeer().displayTitle)
        case .previewWear:
            return strings().peerStatusOnline
        case let .giftUpgrade(peer, _, _):
            return strings().starGiftValueLetUserMakeUnique(peer._asPeer().compactDisplayTitle)
        case .aboutCraft:
            return strings().starGiftCraftHeaderInfo
        case .crafting:
            return ""
        default:
            if let unique = gift.unique {
                var isCrafted = false
                var modelName: String?
                for attribute in unique.attributes {
                    switch attribute {
                    case .model(let name, _, let rarity, _):
                        modelName = name
                        if !rarity.isPermille {
                            isCrafted = true
                        }
                    default:
                        break
                    }
                }
                var infoText = modelName ?? ""
                if let author {
                    infoText = "@\(author.addressName ?? "")"
                } else {
                    if isCrafted {
                        infoText += strings().starGiftCraftCrafted
                    }
                }
                return infoText
            } else {
                return strings().giftUpgradeDescription
            }
        }
    }
    
    public var closeOnOk: Bool {
        switch source {
        case .preview:
            return true
        default:
            return converted
        }
    }
    
    public var isPreview: Bool {
        switch source {
        case .preview:
            return true
        case .quickLook, .craftSuccess:
            return true
        case .previewWear:
            return true
        default:
            return false
        }
    }
}

private let _id_ton_input = InputDataIdentifier("_id_ton_input")

private let _id_craft_features = InputDataIdentifier("_id_craft_features")
private let _id_craft_start_button = InputDataIdentifier("_id_craft_start_button")
private let _id_crafting_area = InputDataIdentifier("_id_crafting_area")

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []

    var sectionId:Int32 = 0
    var index: Int32 = 0

    if case .crafting = state.source {
    } else {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("header"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            return HeaderItem(initialSize, stableId: stableId, context: arguments.context, arguments: arguments, state: state, attributes: state.attributes, source: state.source)
        }))
    }

    let explorerUrl = arguments.context.appConfiguration.getStringValue("ton_blockchain_explorer_url", orElse: "https://tonviewer.com/")

    
   
    
    if !state.source.isCrafting {
        if let gift = state.gift.unique, let address = gift.giftAddress, gift.hostPeerId != nil {
            entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(strings().starGiftOnBlockchainInfo, linkHandler: { _ in
                LinkHooks.shared.openExternalLink(explorerUrl + address, false)
            }), data: .init(color: theme.colors.grayText, viewType: .singleItem, centerViewAlignment: true, alignment: .center)))
            index += 1
        } else {
            entries.append(.sectionId(sectionId, type: .legacy))
            sectionId += 1
        }
    }

    switch state.source {
    case let .aboutCraft(_, fromManualShow):
        entries.append(.sectionId(sectionId, type: .customModern(20)))
        sectionId += 1

        let features: [GiftCraftFeature] = [
            .init(
                icon: TelegramThemeHooks.shared.image(.iconOptionDiamond).precomposed(theme.colors.accent),
                title: strings().starGiftCraftFeatureRareModels,
                description: strings().starGiftCraftFeatureRareModelsDesc
            ),
            .init(
                icon: TelegramThemeHooks.shared.image(.iconOptionDice).precomposed(theme.colors.accent),
                title: strings().starGiftCraftFeatureMaximizeChances,
                description: strings().starGiftCraftFeatureMaximizeChancesDesc
            ),
            .init(
                icon: TelegramThemeHooks.shared.image(.iconOptionCraft).precomposed(theme.colors.accent),
                title: strings().starGiftCraftFeatureAffectResult,
                description: strings().starGiftCraftFeatureAffectResultDesc
            )
        ]

        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_craft_features, equatable: nil, comparable: nil, item: { initialSize, stableId in
            return StarsHooks.shared.makeCraftAboutFeatureItem(initialSize, stableId, features)
        }))
        index += 1

        entries.append(.sectionId(sectionId, type: .customModern(20)))
        sectionId += 1

        let buttonText = fromManualShow ? strings().monetizationIntroUnderstood : strings().starGiftCraftStartCrafting
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_craft_start_button, equatable: nil, comparable: nil, item: { initialSize, stableId in
            return GeneralActionButtonRowItem(initialSize, stableId: stableId, text: buttonText, viewType: .legacy, action: {
                arguments.startCrafting()
            }, inset: NSEdgeInsets(left: 10, right: 10))
        }))
        index += 1

        entries.append(.sectionId(sectionId, type: .customModern(10)))
        sectionId += 1

        return entries

    case .crafting:
        struct CraftingTuple: Equatable {
            let selectedSlots: [ProfileGiftsContext.State.StarGift?]
            let successChance: Int
            let variantsCount: Int
            let backdropChances: [GiftCraftChanceIndicator]
            let patternChances: [GiftCraftChanceIndicator]
        }

        let tuple = CraftingTuple(
            selectedSlots: state.craftSelectedSlots,
            successChance: state.craftSuccessChance,
            variantsCount: state.craftVariantsCount,
            backdropChances: state.craftBackdropChances,
            patternChances: state.craftPatternChances
        )

        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_crafting_area, equatable: .init(tuple), comparable: nil, item: { initialSize, stableId in
            return StarsHooks.shared.makeCraftingAreaItem(initialSize, stableId, GiftCraftingAreaData(
                context: arguments.context,
                selectedSlots: state.craftSelectedSlots,
                selectedCount: state.craftSelectedCount,
                successChance: state.craftSuccessChance,
                variantsCount: state.craftVariantsCount,
                giftFile: state.source.craftGift?.file,
                initialGiftRef: state.craftInitialGiftRef,
                backdropChances: state.craftBackdropChances,
                patternChances: state.craftPatternChances,
                craftingState: state.craftingState,
                dismiss: arguments.dismiss,
                craft: arguments.performCraft,
                removeGift: arguments.toggleCraftGift,
                showModels: arguments.showCraftVariants,
                showMarketplace: arguments.showCraftMarketplace,
                showAbout: arguments.showCraftAbout,
                showBackdropChanceHint: arguments.showBackdropChanceHint,
                showPatternChanceHint: arguments.showPatternChanceHint,
                craftAnother: arguments.craftAnother,
                showSuccess: arguments.showCraftSuccess
            ))
        }))
        index += 1

        return entries

    default:
        if state.converted {
            
            
            
            var rows: [InputDataTableBasedItem.Row] = []
            
                    
            let ownerAttr: NSAttributedString
            
            if let peer = state.owner {
                ownerAttr = parseMarkdownIntoAttributedString("[\(peer._asPeer().displayTitle)](owner)", attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: .medium(.text), textColor: theme.colors.text), bold: MarkdownAttributeSet(font: .bold(.text), textColor: theme.colors.text), link: MarkdownAttributeSet(font: .medium(.text), textColor: theme.colors.accentIcon), linkAttribute: { contents in
                    return (NSAttributedString.Key.link.rawValue, contents)
                }))
            } else if let ownerName = state.ownerName {
                if state.isTonOwner {
                    ownerAttr = parseMarkdownIntoAttributedString("[\(ownerName.prefixWithDots(20, mode: .middle))](\(ownerName))", attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: .medium(.text), textColor: theme.colors.text), bold: MarkdownAttributeSet(font: .bold(.text), textColor: theme.colors.text), link: MarkdownAttributeSet(font: .medium(.text), textColor: theme.colors.accentIcon), linkAttribute: { contents in
                        return (NSAttributedString.Key.link.rawValue, contents)
                    }))
                } else {
                    ownerAttr = .initialize(string: ownerName, color: theme.colors.text, font: .normal(.text))
                }
            } else {
                ownerAttr = .init()
            }
            
            let ownerText: TextViewLayout = .init(ownerAttr, maximumNumberOfLines: state.isTonOwner ? 3 : 1, alwaysStaticItems: true)
            
            ownerText.interactions.processURL = { url in
                if let url = url as? String, !url.isEmpty {
                    if url == "owner", let peer = state.owner {
                        arguments.openPeer(peer, false)
                    } else {
                        LinkHooks.shared.openExternalLink(explorerUrl + url, false)
                    }
                }
            }
            
            let leftView:((NSView?)->NSView)?
            let rightView:((NSView?)->NSView?)?
    //        let badge: InputDataTableBasedItem.Row.Right.Badge?
            if let owner = state.owner {
                leftView = { previous in
                    let control: AvatarControl
                    if let previous = previous as? AvatarControl {
                        control = previous
                    } else {
                        control = AvatarControl(font: .avatar(6))
                    }
                    control.setFrameSize(NSMakeSize(20, 20))
                    control.setPeer(account: arguments.context.account, peer: owner._asPeer())
                    return control
                }
                if let gift = state.gift.unique, let owner = state.owner {
                    rightView = { previous in
                        let control: PremiumStatusControl? = PremiumStatusControl.control(owner._asPeer(), account: arguments.context.account, inlinePacksContext: arguments.context.inlinePacksContext, left: false, isSelected: false, cached: previous as? PremiumStatusControl, animated: false)
                        control?.userInteractionEnabled = true
                        if state.weared {
                            control?.appTooltip = strings().starNftTooltipWorn("\(gift.title) #\(gift.number)")
                        }
                        return control
                    }
                } else {
                    rightView = nil
                }
    //            if owner.id == arguments.context.peerId {
    //                badge = .init(text: strings().giftUniqueTransfer, callback: arguments.transfer)
    //            } else {
    //                badge = nil
    //            }
            } else {
                leftView = nil
                rightView = nil
    //            badge = nil
            }
            
            let isBlockchainTelegram = state.gift.unique?.hostPeerId != nil && state.gift.unique?.giftAddress != nil
            
            
            if isBlockchainTelegram, let address = state.gift.unique?.giftAddress {
                let ownerAttr = parseMarkdownIntoAttributedString("[\(address.prefixWithDots(20, mode: .middle))](\(address))", attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: .medium(.text), textColor: theme.colors.text), bold: MarkdownAttributeSet(font: .bold(.text), textColor: theme.colors.text), link: MarkdownAttributeSet(font: .medium(.text), textColor: theme.colors.accentIcon), linkAttribute: { contents in
                    return (NSAttributedString.Key.link.rawValue, contents)
                }))
                
                let layout = TextViewLayout(ownerAttr)
                layout.interactions.processURL = { _ in
                    LinkHooks.shared.openExternalLink(explorerUrl + address, false)
                }
                
                rows.append(.init(left: .init(.initialize(string:strings().giftUniqueOwner, color: theme.colors.text, font: .normal(.text))), right: .init(name: layout, leftView: nil, rightView: nil, badge: nil)))
            }
            
            rows.append(.init(left: .init(.initialize(string: isBlockchainTelegram ? strings().giftUniqueTelegram : strings().giftUniqueOwner, color: theme.colors.text, font: .normal(.text))), right: .init(name: ownerText, leftView: leftView, rightView: rightView, badge: nil)))
            
            switch state.gift {
            case let .unique(gift):
                
                let badge: InputDataTableBasedItem.Row.Right.Badge?
                
                if let owner = state.owner, owner.id == arguments.context.peerId || owner._asPeer().groupAccess.canManageGifts {
                    badge = .init(text: strings().starNftPriceEdit, callback: {
                        arguments.sellNft(gift, true)
                    })
                } else {
                    badge = nil
                }
                
                
//                if let resellStars = gift.resell, badge != nil {
//                    rows.append(.init(left: .init(.initialize(string: strings().starNftPriceSale, color: theme.colors.text, font: .normal(.text))), right: .init(name: .init(.initialize(string: "\(resellStars.formatted)", color: theme.colors.text, font: .normal(.text))), leftView: { previous in
//                        let control: ImageView
//                        if let previous = previous as? ImageView {
//                            control = previous
//                        } else {
//                            control = ImageView(frame: NSMakeRect(0, 0, 20, 20))
//                        }
//                        if gift.resellForTonOnly {
//                            control.image = TelegramThemeHooks.shared.image(.iconTonCurrency).precomposed()
//                        } else {
//                            control.image = TelegramThemeHooks.shared.image(.iconStarCurrency).precomposed()
//                        }
//                        return control
//                    }, badge: badge)))
//                }
                
                for attr in gift.attributes {
                    switch attr {
                    case .model(let name, _, let rarity, _):
                        rows.append(.init(left: .init(.initialize(string: strings().giftUniqueModel, color: theme.colors.text, font: .normal(.text))), right: .init(name: .init(.initialize(string: name, color: theme.colors.text, font: .normal(.text))), badge: .init(text: rarity.badgeText, color: rarity.badgeColor, callback: {
                            arguments.showModels(.unique(gift), .models)
                        }))))
                    case .pattern(let name, _, let rarity):
                        rows.append(.init(left: .init(.initialize(string: strings().giftUniqueSymbol, color: theme.colors.text, font: .normal(.text))), right: .init(name: .init(.initialize(string: name, color: theme.colors.text, font: .normal(.text))), badge: .init(text: rarity.badgeText, color: rarity.badgeColor, callback: {
                            arguments.showModels(.unique(gift), .symbols)
                        }))))
                    case .backdrop(let name, _, _, _, _, _, let rarity):
                        rows.append(.init(left: .init(.initialize(string: strings().giftUniqueBackdrop, color: theme.colors.text, font: .normal(.text))), right: .init(name: .init(.initialize(string: name, color: theme.colors.text, font: .normal(.text))), badge: .init(text: rarity.badgeText, color: rarity.badgeColor, callback: {
                            arguments.showModels(.unique(gift), .backdrops)
                        }))))
                    default:
                        break
                    }
                }
                
                rows.append(.init(left: .init(.initialize(string: strings().starTransactionAvailability, color: theme.colors.text, font: .normal(.text))), right: .init(name: .init(.initialize(string: strings().starTransactionGiftUpgradeIssued(Int(gift.availability.issued).formattedWithSeparator, Int(gift.availability.total).formattedWithSeparator), color: theme.colors.text, font: .normal(.text))))))

                if let valueAmount = gift.valueAmount, let currency = gift.valueCurrency {
                    rows.append(.init(
                        left: .init(.initialize(
                            string: strings().starGiftValueRowLabel,
                            color: theme.colors.text,
                            font: .normal(.text)
                        )),
                        right: .init(
                            name: .init(.initialize(
                                string: formatCurrencyAmount(valueAmount, currency: currency),
                                color: theme.colors.text,
                                font: .normal(.text)
                            )),
                            badge: .init(
                                text: strings().starGiftValueRowBadge,
                                callback: {
                                    arguments.openValue(gift)
                                }
                            )
                        )
                    ))
                }
                
                if let string = makeGiftOriginalInfoString(gift, peerMap: state.peerMap, context: arguments.context) {
                    let layout = TextViewLayout(string)
                    layout.interactions.processURL = { url in
                        if let url = url as? PeerId {
                            if let peer = state.peerMap[url] {
                                arguments.openPeer(peer, false)
                            }
                        }
                    }
                    
                    var rightView: ((NSView?)->NSView?)?
                    
                    if let _ = state.dropDetailsStars {
                        rightView = { previous in
                            let control: ImageButton
                            if let previous = previous as? ImageButton {
                                control = previous
                            } else {
                                control = ImageButton()
                            }
                            control.set(image: TelegramThemeHooks.shared.image(.menuDelete).precomposed(theme.colors.accent), for: .Normal)
                            control.sizeToFit()
                            control.autohighlight = false
                            control.scaleOnClick = true
                            control.setSingle(handler: { _ in
                                arguments.deleteOriginalInfo(gift, string)
                            }, for: .Click)
                            return control
                        }
                    }
                    if !state.droppedInfo {
                        rows.append(.init(left: nil, right: .init(name: layout, rightView: rightView)))
                    }
                }
                

            default:
                break
            }

            if let text = state.purpose?.giftText, !text.isEmpty {
                let entities = state.purpose?.giftEntities
                let attr = StarsHooks.shared.applyMessageEntities(entities ?? [], text, arguments.context, theme.fontSize, { _, _, _, _ in }, theme.colors.text, theme.colors.isDark, true).mutableCopy() as! NSMutableAttributedString
                InlineStickerItem.apply(to: attr, associatedMedia: [:], entities: entities ?? [], isPremium: arguments.context.isPremium)
                rows.append(.init(left: nil, right: .init(name: .init(attr))))
            }

            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("attributes"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
                return InputDataTableBasedItem(initialSize, stableId: stableId, viewType: .singleItem, rows: rows, context: arguments.context)
            }))

            if let visibility = state.profileVisibility, state.takeNextUpgradeGift == nil {
                index += 1
                entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(visibility.saved ? strings().starTransactionStarGiftShownInProfile : strings().starTransactionStarGiftHidInProfile, linkHandler: { _ in
                    arguments.toggleProfileVisibility()
                }), data: .init(viewType: .singleItem, fontSize: 13, centerViewAlignment: true, alignment: .center)))
                index += 1
            }
            
            
            if let address = state.gift.unique?.giftAddress, state.gift.unique?.hostPeerId == nil, case .address = state.gift.unique?.owner {
                entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(strings().starGiftOnBlockchainInfo, linkHandler: { _ in
                    LinkHooks.shared.openExternalLink(explorerUrl + address, false)
                }), data: .init(viewType: .singleItem, fontSize: 13, centerViewAlignment: true, alignment: .center)))
            } else {
//                if case .quickLook = state.source {
//                    entries.append(.sectionId(sectionId, type: .legacy))
//                    sectionId += 1
//                }
                /*
                 else if state.convertedGift != nil {
                     entries.append(.sectionId(sectionId, type: .legacy))
                     sectionId += 1
                 }
                 */
            }
                      
            
        } else {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("row"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
                return RowItem(initialSize, stableId: stableId, context: arguments.context, source: state.source, transaction: state.transaction, nameEnabled: state.nameEnabled, isPreview: state.isPreview, toggleName: arguments.toggleName)
            }))
        }

    }

    if !state.okText(arguments.context).isEmpty {
        entries.append(.sectionId(sectionId, type: .customModern(10)))
        sectionId += 1
    }

    return entries
}

public enum StarGiftNftSource : Equatable {
    case preview(EnginePeer, StarGiftUpgradePreview)
    case previewWear(EnginePeer, StarGift.UniqueGift)
    case upgrade(EnginePeer, StarGiftUpgradePreview, StarGiftReference)
    case giftUpgrade(EnginePeer, StarGiftUpgradePreview, prepaidUpgradeHash: String)
    case quickLook(EnginePeer?, StarGift.UniqueGift)
    case craftSuccess(StarGift.UniqueGift)
    case aboutCraft(StarGift.UniqueGift, fromManualShow: Bool)
    case crafting(StarGift.UniqueGift)
    public var attributes: [StarGift.UniqueGift.Attribute] {
        switch self {
        case let .preview(_, attributes):
            return attributes.attributes
        case let .upgrade(_, attributes, _):
            return attributes.attributes
        case let .giftUpgrade(_, attributes, _):
            return attributes.attributes
        case let .quickLook(_, gift):
            return gift.attributes
        case let .craftSuccess(gift):
            return gift.attributes
        case let .previewWear(_, gift):
            return gift.attributes
        case let .aboutCraft(gift, _):
            return gift.attributes
        case let .crafting(gift):
            return gift.attributes
        }
    }

    public var isQuickLook: Bool {
        switch self {
        case .quickLook, .craftSuccess:
            return true
        default:
            return false
        }
    }

    public var isCrafting: Bool {
        switch self {
        case .aboutCraft, .crafting:
            return true
        default:
            return false
        }
    }

    public var craftGift: StarGift.UniqueGift? {
        switch self {
        case let .aboutCraft(gift, _):
            return gift
        case let .crafting(gift):
            return gift
        default:
            return nil
        }
    }

    public var peer: EnginePeer? {
        switch self {
        case .preview(let enginePeer, _):
            return enginePeer
        case .previewWear(let enginePeer, _):
            return enginePeer
        case .upgrade(let enginePeer, _, _):
            return enginePeer
        case .giftUpgrade(let enginePeer, _, _):
            return enginePeer
        case .quickLook(let enginePeer, _):
            return enginePeer
        case .aboutCraft, .crafting, .craftSuccess:
            return nil
        }
    }

    public var isWearing: Bool {
        switch self {
        case .previewWear:
            return true
        default:
            return false
        }
    }


}

public struct GiftPinnedInfo : Equatable {
    public var pinnedInfo: Bool
    public var reference: StarGiftReference
    public init(pinnedInfo: Bool, reference: StarGiftReference) {
        self.pinnedInfo = pinnedInfo
        self.reference = reference
    }
}

public func StarGift_Nft_Controller(context: (any AccountContextProtocol), gift: StarGift, source: StarGiftNftSource, transaction: StarsContext.State.Transaction? = nil, purpose: Star_TransactionPurpose? = nil, giftsContext: ProfileGiftsContext? = nil, resaleContext: ResaleGiftsContext? = nil, pinnedInfo: GiftPinnedInfo? = nil, toPeerId: PeerId? = nil, onPurchase: ((ProfileGiftsContext.State.StarGift) -> Void)? = nil, giftMenuItems: (() -> [ContextMenuItem])? = nil, openCrafting: Bool = false) -> InputDataModalController {

    
    
    let toPeerId = toPeerId ?? context.peerId
    
    let giftsContext = giftsContext ?? ProfileGiftsContext(account: context.account, peerId: toPeerId)
    let nextUpgradeContext = ProfileGiftsContext(account: context.account, peerId: context.peerId, filter: [.displayed, .hidden, .limitedUpgradable])

    var craftGiftsContext: CraftGiftsContext?
    let craftContextDisposables = DisposableSet()

    let actionsDisposable = DisposableSet()
    let wearAction = GiftWearAction()
    let ownerDisposable = MetaDisposable()
    actionsDisposable.add(ownerDisposable)
    let peersDisposable = MetaDisposable()
    actionsDisposable.add(peersDisposable)

    let authorPeer: Signal<EnginePeer?, NoError>
    if let authorId = gift.releasedBy {
        authorPeer = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: authorId))
    } else {
        authorPeer = .single(nil)
    }
    
    
    let initialState = State(source: source, gift: gift, ignoreUpgradeGifts: Set(), transaction: transaction, converted: source.isQuickLook, purpose: purpose, attributes: source.attributes, accountPeerId: context.peerId, pinnedInfo: pinnedInfo)
    
    var close:(()->Void)? = nil
    
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    
    actionsDisposable.add(combineLatest(context.starsContext.state, context.tonContext.state, authorPeer).startStrict(next: { state, tonState, authorPeer in
        updateState { current in
            var current = current
            current.starsState = state
            current.myBalance = state?.balance
            current.myTonBalance = tonState?.balance
            current.author = authorPeer
            return current
        }
    }))
    
    actionsDisposable.add(statePromise.get().start(next: { state in
        
        if let unique = state.gift.unique {
            
            let ownerPeerId: Signal<EnginePeer?, NoError>

            switch unique.owner {
            case let .peerId(peerId):
                ownerPeerId = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
            default:
                if let hostPeerId = unique.hostPeerId {
                    ownerPeerId = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: hostPeerId)) |> map { peer in
                        if let peer {
                            if peer.id == context.peerId || peer._asPeer().groupAccess.canManageGifts {
                                return peer
                            }
                        }
                        return nil
                    }
                } else {
                    ownerPeerId = .single(nil)
                }
            }
            
            switch unique.owner {
            case .peerId:
                ownerDisposable.set(ownerPeerId.startStandalone(next: { peer in
                    updateState { current in
                        var current = current
                        current.owner = peer
                        current.ownerName = nil
                        current.isTonOwner = false
                        return current
                    }
                }))
            case let .name(name):
                ownerDisposable.set(ownerPeerId.startStandalone(next: { peer in
                    updateState { current in
                        var current = current
                        current.owner = peer
                        current.ownerName = name
                        current.isTonOwner = false
                        return current
                    }
                }))
            case let .address(address):
                ownerDisposable.set(ownerPeerId.startStandalone(next: { peer in
                    updateState { current in
                        var current = current
                        current.owner = peer
                        current.ownerName = address
                        current.isTonOwner = true
                        return current
                    }
                }))
            case .none:
                break
            }
            
            peersDisposable.set(nil)
            
            for attr in unique.attributes {
                switch attr {
                case let .originalInfo(senderPeerId, recipientPeerId, _, _, _):
                    var signals:[Signal<EnginePeer?, NoError>] = []
                    signals.append(context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: recipientPeerId)))
                    if let senderPeerId {
                        signals.append(context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: senderPeerId)))
                    }
                    peersDisposable.set(combineLatest(signals).start(next: { peers in
                        updateState { current in
                            var current = current
                            for peer in peers {
                                if let peer = peer {
                                    current.peerMap[peer.id] = peer
                                }
                            }
                            return current
                        }
                    }))
                default:
                    break
                }
            }
        } else {
            ownerDisposable.set(nil)
        }
    }))
    
    
    switch source {
    case let .upgrade(_, _, messageId):
        if (purpose?.upgradeStars ?? 0) == 0 {
            actionsDisposable.add(context.engine.payments.fetchBotPaymentForm(source: .starGiftUpgrade(keepOriginalInfo: false, reference: messageId), themeParams: nil).start(next: { form in
                updateState { current in
                    var current = current
                    current.upgradeForm = form
                    return current
                }
            }, error: { _ in

            }))
        }
    default:
        break
    }
    
    actionsDisposable.add(combineLatest(giftsContext.state, nextUpgradeContext.state).startStrict(next: { state, nextState in
        let unique = state.gifts.first(where: { $0.gift.unique?.slug == gift.unique?.slug })
        
        if let unique = unique?.gift.unique {
            updateState { current in
                var current = current
                current.gift = .unique(unique)
                current._nextUpgradeGifts = nextState.filteredGifts
                switch current.source {
                case let .quickLook(peer, _):
                    current.source = .quickLook(peer, unique)
                default:
                    break
                }
                return current
            }
        } else {
            updateState { current in
                var current = current
                current._nextUpgradeGifts = nextState.filteredGifts
                return current
            }
        }
        
    }))
    
    
    var getController:(()->ViewController?)? = nil
    
    var window:Window {
        get {
            return getController?()?.window ?? context.window
        }
    }
    
   
    
    
    let buyResellGift:(StarGift.UniqueGift, EnginePeer, BotPaymentForm, BotPaymentForm)->Void = { [weak giftsContext, weak resaleContext] gift, peer, starsForm, tonForm in

        var buyForSelected: CurrencyAmount.Currency = gift.resellForTonOnly ? .ton : .stars
        var modifyData:((ModalAlertData)->Void)? = nil
        
        var getData:()->ModalAlertData = { .init(info: "") }
        
        getData = {
            
            let form = buyForSelected == .stars ? starsForm : tonForm
            
            let fullAmount = form.invoice.prices.first?.amount ?? 0
            
            let resellAmount = CurrencyAmount(amount: StarsAmount.init(value: fullAmount, nanos: 0), currency: buyForSelected)
            
            let resellStars = resellAmount.fullyFormatted
            
            let infoText: String
            if peer.id == context.peerId {
                infoText = strings().starNftGiftBuyConfirmSelf(gift.title, resellStars)
            } else {
                infoText = strings().starNftGiftBuyConfirm(gift.title, resellStars, peer._asPeer().displayTitle)
            }
            
            return ModalAlertData(title: strings().starNftGiftConfirmTitle, info: infoText, description: nil, ok: strings().starNftGiftConfirmOk(resellStars), options: [], mode: .confirm(text: strings().modalCancel, isThird: false), header: .init(id: "header", value: { initialSize, stableId, presentation in
                return TransferUniqueGiftHeaderItem(initialSize, stableId: stableId, gift: gift, toPeer: peer, context: context, transferType: .buy(onlyTon: gift.resellForTonOnly), buyForSelected: buyForSelected, callback: { updated in
                    buyForSelected = updated
                    modifyData?(getData())
                })
            }), footer: ModalAlertData.Footer.init(id: "footer", value: { initialSize, stableId, presentation, action in
                return InputDataTableBasedItem(initialSize, stableId: stableId, viewType: .singleItem, rows: getTransferAttributesRows(gift: gift), context: context)
            }))
        }
        
        
        
        let topUpDisposable = MetaDisposable()
        actionsDisposable.add(topUpDisposable)

        var payStep: ((Updated_ChatTextInputState?, Bool) -> Void)? = nil
        payStep = { message, isMessagePublic in
            let messageText = message?.inputText.string ?? ""
            let text: String? = messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : messageText
            var entities: [MessageTextEntity]? = text != nil ? message?.textInputState().messageTextEntities() : nil
            if entities?.isEmpty == true {
                entities = nil
            }
            let hideName = !isMessagePublic

            let form = buyForSelected == .stars ? starsForm : tonForm

            let fullAmount = form.invoice.prices.first?.amount ?? 0

            let presentStarsTopUp: (Int64) -> Void = { required in
                showModal(with: Star_ListScreen(context: context, source: .buy(suffix: nil, amount: required)), for: window)
                // A topped-up balance only re-opens the confirmation — money never moves without an
                // explicit OK (the balance can also grow for reasons unrelated to this purchase).
                topUpDisposable.set((context.starsContext.state
                |> filter { ($0?.balance.value ?? 0) >= required }
                |> take(1)
                |> deliverOnMainQueue).startStrict(next: { _ in
                    showModalAlert(for: window, data: getData(), completion: { _ in
                        payStep?(message, isMessagePublic)
                    }, takeNewData: { f in
                        modifyData = f
                    })
                }))
            }

            let balanceSignal: Signal<StarsAmount, NoError>
            if buyForSelected == .stars {
                balanceSignal = context.starsContext.state |> take(1) |> map { $0?.balance ?? .init(value: 0, nanos: 0) }
            } else {
                balanceSignal = context.tonContext.state |> take(1) |> map { $0?.balance ?? .init(value: 0, nanos: 0) }
            }

            _ = (balanceSignal |> deliverOnMainQueue).startStandalone(next: { myBalance in
                if fullAmount > myBalance.value {
                    if buyForSelected == .ton {
                        StarsHooks.shared.openTonBalance(context, fullAmount - myBalance.value)
                    } else {
                        presentStarsTopUp(fullAmount)
                    }
                    return
                }
                let source: BotPaymentInvoiceSource = .starGiftResale(slug: gift.slug, toPeerId: toPeerId, ton: buyForSelected == .ton, hideName: hideName, text: text, entities: entities)

                let performPayment: (Int64, Int64) -> Void = { formId, paidAmount in
                    let resellAmount = CurrencyAmount(amount: StarsAmount.init(value: paidAmount, nanos: 0), currency: buyForSelected).fullyFormatted
                    _ = showModalProgress(signal: context.engine.payments.sendStarsPaymentForm(formId: formId, source: source), for: window).startStandalone(next: { result in
                        switch result {
                        case .done:
                            context.starsContext.load(force: true)
                            context.tonContext.load(force: true)
                            context.starsSubscriptionsContext.load(force: true)
                            giftsContext?.removeStarGift(gift: .unique(gift))
                            resaleContext?.removeStarGift(gift: .unique(gift))

                            if peer.id == context.peerId {
                                PlayConfetti(for: window, stars: true)
                                showModalText(for: window, text: strings().starNftGiftBuySuccessSelf(gift.title, resellAmount))
                            } else {
                                showModalText(for: window, text: strings().starNftGiftBuySuccess(gift.title, resellAmount, peer._asPeer().displayTitle))
                                StarsHooks.shared.openChat(context, peer.id, nil)
                            }

                            onPurchase?(.placeholder(gift: gift))
                            close?()
                            topUpDisposable.set(nil)
                            payStep = nil
                        default:
                            break
                        }
                    }, error: { error in
                        let errorText: String
                        switch error {
                        case .alreadyPaid:
                            errorText = strings().checkoutErrorInvoiceAlreadyPaid
                        case .generic:
                            errorText = strings().unknownError
                        case .paymentFailed:
                            errorText = strings().checkoutErrorPaymentFailed
                        case .precheckoutFailed:
                            errorText = strings().checkoutErrorPrecheckoutFailed
                        case .starGiftOutOfStock:
                            errorText = strings().giftSoldOutError
                        case .disallowedStarGift:
                            errorText = strings().giftSendDisallowError
                        case .starGiftUserLimit:
                            errorText = strings().giftOptionsGiftBuyLimitReached
                        case let .serverProvided(value):
                            errorText = value
                        }
                        showModalText(for: window, text: errorText)
                        topUpDisposable.set(nil)
                        payStep = nil
                    })
                }

                // Always re-fetch before paying: the cached form can be stale (the composer or a
                // top-up may have taken minutes), and only a fresh invoice makes the price check real.
                _ = showModalProgress(signal: context.engine.payments.fetchBotPaymentForm(source: source, themeParams: nil), for: window).startStandalone(next: { freshForm in
                    let freshAmount = freshForm.invoice.prices.first?.amount ?? 0
                    if freshAmount > fullAmount {
                        let previousAmount = CurrencyAmount(amount: StarsAmount.init(value: fullAmount, nanos: 0), currency: buyForSelected).fullyFormatted
                        let updatedAmount = CurrencyAmount(amount: StarsAmount.init(value: freshAmount, nanos: 0), currency: buyForSelected).fullyFormatted
                        verifyAlert(for: window, header: strings().starNftGiftPriceChangedTitle, information: strings().starNftGiftPriceChangedInfo(previousAmount, updatedAmount), ok: strings().starNftGiftPriceChangedOK(updatedAmount), successHandler: { _ in
                            if freshAmount > myBalance.value {
                                if buyForSelected == .ton {
                                    StarsHooks.shared.openTonBalance(context, freshAmount - myBalance.value)
                                } else {
                                    presentStarsTopUp(freshAmount)
                                }
                            } else {
                                performPayment(freshForm.id, freshAmount)
                            }
                        })
                    } else {
                        performPayment(freshForm.id, freshAmount)
                    }
                }, error: { _ in
                    showModalText(for: window, text: strings().unknownError)
                })
            })
        }

        showModalAlert(for: window, data: getData(), completion: { _ in
            if peer.id == context.peerId {
                payStep?(nil, false)
            } else {
                showModal(with: StarGift_AddMessage_Controller(context: context, gift: gift, toPeer: peer, send: { message, isPublic in
                    payStep?(message, isPublic)
                }), for: window)
            }
        }, takeNewData: { f in
            modifyData = f
        })

    }

    let arguments = Arguments(context: context, window: { window }, dismiss:{
        let state = stateValue.with { $0 }
        if case .failed = state.craftingState {
            close?()
            return
        }
        switch state.source {
        case let .previewWear(owner, gift):
            wearAction.reset()
            updateState { current in
                var current = current
                current.source = .quickLook(owner, gift)
                current.converted = true
                return current
            }
        case let .aboutCraft(gift, _), let .crafting(gift):
            updateState { current in
                var current = current
                current.source = .quickLook(current.owner, gift)
                current.converted = true
                return current
            }
        default:
            close?()
        }
    }, toggleName: {
        updateState { current in
            var current = current
            current.nameEnabled = !current.nameEnabled
            return current
        }
    }, transfer: {
        
        let state = stateValue.with { $0 }
        
        
        
        if let gift = state.gift.unique, gift.hostPeerId != nil, gift.giftAddress != nil {
            verifyAlert(
                for: window,
                header: strings().starGiftActionLockedTitle,
                information: strings().starGiftActionLockedText,
                ok: strings().starGiftActionLockedOpen,
                successHandler: { _ in
                    LinkHooks.shared.openExternalLink(strings().starGiftActionLockedURL, false)
                }
            )
            return
        }
        
        var canExportDate: Int32? = nil
        var transferStars: Int64? = nil
        var convertStars: Int64? = nil
        var canTransferDate: Int32? = nil
        var reference: StarGiftReference? = nil
        if case let .starGift(_, _convertStars, _, _, _, _, _, _, _, _, _transferStars, _canExportDate, _reference, _, _, _, _canTransferDate, _, _, _, _, _, _, _) = state.purpose {
            canExportDate = _canExportDate
            transferStars = _transferStars
            convertStars = _convertStars
            reference = _reference
            canTransferDate = _canTransferDate
        }
        
        if let canTransferDate, canTransferDate > context.timestamp {
            alert(for: window, header: strings().giftTransferUnavailableTitle, info: strings().giftTransferUnavailableText(stringForFullDate(timestamp: canTransferDate)))
            return
        }
        
        
        
        guard let reference, let unique = state.gift.unique else {
            return
        }

        showGiftTransfer(context: context, window: window, gift: unique, reference: reference, giftsContext: giftsContext, canExportDate: canExportDate, transferStars: transferStars, transfer: { peer, dismiss in
            if let convertStars, let starsState = stateValue.with({ $0.starsState }), starsState.balance.value < convertStars {
                FeatureNavigationHooks.shared.showStarsPurchaseWithContext(context, window, .stars, nil, convertStars)
                return
            }
            dismiss()
            _ = (giftsContext.transferStarGift(prepaid: transferStars == nil, reference: reference, peerId: peer.id)).startStandalone()
            _ = (showModalSuccess(for: context.window, icon: theme.icons.successModalProgress, delay: 1.5)).start()
            close?()
        })
    }, copyNftLink: { gift in
        copyToClipboard(gift.link(context))
        showModalText(for: window, text: strings().contextAlertCopied)
    }, shareNft: { gift in
        StarsHooks.shared.shareLink(context, gift.link(context), window)
    }, sellNft: { gift, updatePrice in
        
        let state = stateValue.with { $0 }
        
        if !state.canManage {
            return
        }
        
        if let gift = state.gift.unique, gift.hostPeerId != nil, gift.giftAddress != nil {
            verifyAlert(
                for: window,
                header: strings().starGiftActionLockedTitle,
                information: strings().starGiftActionLockedText,
                ok: strings().starGiftActionLockedOpen,
                successHandler: { _ in
                    LinkHooks.shared.openExternalLink(strings().starGiftActionLockedURL, false)
                }
            )
            return
        }
        
        if case let .starGift(_, _, _, _, _, _, _, _, _, _, _, _, reference, _, _, _, canResaleDate, _, _, _, _, _, _, _) = state.purpose {
            if let _ = gift.resellStars(context), !updatePrice, let reference {
                verifyAlert(for: window, header: strings().giftUnlistConfirmTitle, information: strings().giftUnlistConfirmText, ok: strings().giftUnlistConfirmOk, successHandler: { _ in
                    _ = showModalProgress(signal: giftsContext.updateStarGiftResellPrice(reference: reference, price: nil, id: gift.id), for: window).startStandalone()
                })
            } else if let reference {
                
                if let canResaleDate, canResaleDate > context.timestamp {
                    alert(for: window, header: strings().giftResaleUnavailableTitle, info: strings().giftResaleUnavailableText(stringForFullDate(timestamp: canResaleDate)))
                    return
                }
                
                showModal(with: sellNft(context: context, resellPrice: gift.resellAmounts, defaultCurrency: gift.resellForTonOnly ? .ton : .stars, gift: gift, callback: { value in
                    if !updatePrice {
                        let data = ModalAlertData(title: nil, info: strings().giftSellConfirmText(gift.title, value.fullyFormatted), description: nil, ok: strings().giftSellConfirmTitle, options: [], mode: .confirm(text: strings().modalCancel, isThird: false), header: .init(id: "header", value: { initialSize, stableId, presentation in
                            return TransferUniqueGiftHeaderItem(initialSize, stableId: stableId, gift: gift, toPeer: .init(context.myPeer!), context: context, transferType: .sell)
                        }), footer: ModalAlertData.Footer.init(id: "footer", value: { initialSize, stableId, presentation, action in
                            return InputDataTableBasedItem(initialSize, stableId: stableId, viewType: .singleItem, rows: getTransferAttributesRows(gift: gift), context: context)
                        }))

                        showModalAlert(for: window, data: data, completion: { result in
                            _ = showModalProgress(signal: giftsContext.updateStarGiftResellPrice(reference: reference, price: value, id: gift.id), for: window).startStandalone(error: { error in
                                switch error {
                                case let .starGiftResellTooEarly(value):
                                    showModalText(for: window, text: strings().giftResaleUnavailableText(stringForFullDate(timestamp: value)))
                                default:
                                    break
                                }
                            }, completed: {
                                showModalText(for: window, text: strings().giftResaleSetSuccess)
                            })
                        })
                    } else {
                        _ = showModalProgress(signal: giftsContext.updateStarGiftResellPrice(reference: reference, price: value, id: gift.id), for: window).startStandalone(completed: {
                            showModalText(for: window, text: strings().giftResalePriceUpdate)
                        })
                    }
                }), for: window)
            }
        }
        
    }, toggleWear: { gift in
        wearAction.reset()
        
        let weared = stateValue.with { $0.weared }
        let owner = stateValue.with { $0.owner }
        

        if weared, let owner, let file = gift.file {
            context.reactions.setStatus(file, peer: owner._asPeer(), timestamp: context.timestamp, timeout: nil, fromRect: nil, starGift: gift)
        } else if let owner {
            updateState { current in
                var current = current
                switch current.source {
                case .previewWear(_, _):
                    current.source = .quickLook(owner, gift)
                    current.converted = true
                default:
                    if current.weared {
                        current.source = .quickLook(owner, gift)
                        current.converted = true
                    } else {
                        current.source = .previewWear(owner, gift)
                        current.converted = false
                    }
                }
                return current
            }
        }
    }, togglePin: { [weak giftsContext] in
        let pinnedInfo = stateValue.with { $0.pinnedInfo }
        if let pinnedInfo {
            giftsContext?.updateStarGiftPinnedToTop(reference: pinnedInfo.reference, pinnedToTop: !pinnedInfo.pinnedInfo)
            updateState { current in
                var current = current
                current.pinnedInfo = .init(pinnedInfo: !pinnedInfo.pinnedInfo, reference: pinnedInfo.reference)
                return current
            }
            showModalText(for: window, text: !pinnedInfo.pinnedInfo ? strings().giftTooltipPinned : strings().giftTooltipUnpinned)
        }
    }, openPeer: { peer, toChat in
        close?()
        if toChat {
            StarsHooks.shared.openChat(context, peer.id, nil)
        } else {
            StarsHooks.shared.openPeerInfo(context, peer.id)
        }
    }, openValue: { uniqueGift in
        let morphSource = ModalMorphContextSource.current
        let signal = context.engine.payments.cachedStarGifts() |> take(1)
        let valueSignal = context.engine.payments.getUniqueStarGiftValueInfo(slug: uniqueGift.slug)
        _ = showModalProgress(signal: combineLatest(queue: .mainQueue(), signal, valueSignal), for: window).start(next: { gifts, value in
            let gift = gifts?.first(where: { $0.generic?.id == uniqueGift.giftId })?.generic
            if let gift, let value {
                showModal(with: StarGift_NftValue_Controller(context: context, gift: gift, uniqueGift: uniqueGift, valueInfo: value), for: window, morphSource: morphSource)
            }
        })
    }, setAsTheme: { gift in
        actionsDisposable.add(setStarGiftAsChatTheme(context: context, window: window, gift: gift, completion: { close?() }))
    }, deleteOriginalInfo: { gift, string in
        
        let price = stateValue.with { $0.dropDetailsStars}
        let reference = stateValue.with { $0.purpose?.reference }
        
        if let price, let reference = reference {
            let layout = TextViewLayout(string)
            layout.interactions.processURL = { url in
                
            }
            let data = ModalAlertData(
                title: strings().starGiftRemoveDescriptionTitle,
                info: strings().starGiftRemoveDescriptionInfo,
                description: nil,
                ok: strings().starGiftRemoveDescriptionConfirm(strings().starListItemCountOther(Int(price))),
                options: [],
                mode: .confirm(text: strings().modalCancel, isThird: false),
                footer: .init(id: "footer", value: { initialSize, stableId, presentation, _ in
                    return GeneralBlockTextRowItem(
                        initialSize,
                        stableId: stableId,
                        viewType: .singleItem,
                        text: "",
                        font: .normal(.text),
                        textLayout: layout,
                        context: context
                    )
                })
            )

            showModalAlert(for: window, data: data, completion: { _ in
                _ = context.engine.payments.dropStarGiftOriginalDetails(reference: reference).start()
                updateState { current in
                    var current = current
                    current.droppedInfo = true
                    return current
                }
                _ = showModalSuccess(for: window, icon: theme.icons.successModalProgress, delay: 2.0).start()
            })
        }
        
        
    }, makeOffer: { gift, peer in
        showModal(with: StarNftOfferController(context: context, peer: peer, defaultCurrency: .stars, gift: gift, callback: { amount, duration, stars in
            _ = showModalProgress(signal: context.engine.payments.sendStarGiftOffer(peerId: peer.id, slug: gift.slug, amount: amount, duration: duration, allowPaidStars: stars?.value), for: window).startStandalone()
        }), for: window)
    }, showModels: { gift, defaultSection in
        let rarity = gift.unique?.attributes.first(where: { $0.attributeType == .model })?.rarity
        var onlyCraftedModels = true
        if case .permille = rarity {
            onlyCraftedModels = false
        }
        showModal(with: StarGift_ModelBuilderController(context: context, gift: gift, giftId: gift.giftId, defaultMode: defaultSection, onlyCraftedModels: onlyCraftedModels), for: window)
        
    }, startCrafting: {
        updateState { current in
            var current = current
            if let gift = current.source.craftGift {
                current.source = .crafting(gift)
            }
            return current
        }
    }, toggleCraftGift: { gift in
        updateState { current in
            var current = current
            if let index = current.craftSelectedSlots.firstIndex(where: { $0?.reference == gift.reference }) {
                current.craftSelectedSlots[index] = nil
            } else if let index = current.craftSelectedSlots.firstIndex(where: { $0 == nil }) {
                current.craftSelectedSlots[index] = gift
            }
            return current
        }
    }, showCraftModels: { gift, section in
        
        showModal(with: StarGift_ModelBuilderController(context: context, gift: .unique(gift), giftId: gift.giftId, defaultMode: section, onlyCraftedModels: true), for: window)
    }, showCraftMarketplace: { slotIndex in
        let state = stateValue.with { $0 }
        guard let cachedGift = state.craftCachedGift else { return }
        guard let craftCtx = craftGiftsContext else { return }
        let excludedReferences = Set(state.craftSelectedGifts.compactMap { $0.reference })
        showModal(with: StarGift_MarketplaceController(context: context, peerId: context.peerId, gift: cachedGift, craftGiftsContext: craftCtx, excludedReferences: excludedReferences, selectGift: { selectedGift in
            if slotIndex == 0, selectedGift.gift.unique?.giftAddress != nil {
                alert(for: window, header: strings().starGiftNftCantChooseFirst, info: strings().starGiftNftCantChooseFirstInfo)
                return
            }
            updateState { current in
                var current = current
                current.craftSelectedSlots[slotIndex] = selectedGift
                return current
            }
        }), for: window)
    }, showCraftAbout: {
        let state = stateValue.with { $0 }
        guard let gift = state.source.craftGift else { return }
        updateState { current in
            var current = current
            current.source = .aboutCraft(gift, fromManualShow: true)
            return current
        }
    }, showBackdropChanceHint: { name, percent in
        showModalText(for: window, text: strings().starGiftCraftBackdropChanceHint("\(percent)%", name))
    }, showPatternChanceHint: { name, percent in
        showModalText(for: window, text: strings().starGiftCraftPatternChanceHint("\(percent)%", name))
    }, openCraftAbout: { gift in
        if gift.giftAddress != nil {
            alert(for: window, header: strings().starGiftNftCantChooseFirst, info: strings().starGiftNftCantChooseFirstInfo)
            return
        }

        updateState { current in
            var current = current
            current.craftSelectedSlots[0] = .placeholder(gift: gift)
            return current
        }

        if craftGiftsContext == nil {
            let newContext = CraftGiftsContext(account: context.account, giftId: gift.giftId)
            craftGiftsContext = newContext

            var isFirst = true
            craftContextDisposables.add(newContext.state.startStrict(next: { giftsState in
                updateState { current in
                    var current = current
                    current.craftAvailableGifts = giftsState.gifts.filter { $0.gift.unique != nil }
                    if isFirst {
                        if let initialGift = giftsState.gifts.first(where: { $0.gift.id == gift.id }) {
                            current.craftSelectedSlots[0] = initialGift
                            current.craftInitialGiftRef = initialGift.reference
                            isFirst = false
                        }
                    }
                    current.craftIsLoading = false
                    return current
                }
            }))

            craftContextDisposables.add((context.engine.payments.getStarGiftUpgradeAttributes(giftId: gift.giftId)
            |> deliverOnMainQueue).startStrict(next: { attributes in
                if let attributes = attributes {
                    updateState { current in
                        var current = current
                        current.craftVariantsCount = attributes.count
                        return current
                    }
                }
            }))

            craftContextDisposables.add((context.engine.payments.cachedStarGifts()
            |> deliverOnMainQueue).startStrict(next: { cachedGifts in
                if let cachedGifts = cachedGifts {
                    let found = cachedGifts.first(where: { $0.id == gift.giftId })
                    updateState { current in
                        var current = current
                        current.craftCachedGift = found?.generic
                        return current
                    }
                }
            }))
        }

        let shownCount = FastSettings.craftAboutShownCountAndIncrement()
        if shownCount < 3 {
            updateState { current in
                var current = current
                current.source = .aboutCraft(gift, fromManualShow: false)
                return current
            }
        } else {
            updateState { current in
                var current = current
                current.source = .crafting(gift)
                return current
            }
        }
    }, performCraft: { [weak giftsContext] startAnimation, onSuccess, onFailure, onError in
        guard let craftCtx = craftGiftsContext else { return }
        let state = stateValue.with { $0 }
        let selectedGifts = state.craftSelectedGifts
        let references = selectedGifts.compactMap { $0.reference }
        guard !references.isEmpty else { return }

        var animationStarted = false

        _ = (craftCtx.craft(references: references)
        |> deliverOnMainQueue).startStandalone(next: { [weak giftsContext] result in
            if !animationStarted {
                animationStarted = true
                craftCtx.removeGifts(references: references)
                startAnimation()
            }
            giftsContext?.removeStarGifts(references: references)
            giftsContext?.insertStarGifts(gifts: [result])
            onSuccess(result)
        }, error: { [weak giftsContext] error in
            switch error {
            case .generic:
                onError()
                showModalText(for: window, text: strings().unknownError)
            case .tooEarly(let seconds):
                onError()
                let timeString = autoremoveLocalized(Int(seconds))
                showModalText(for: window, text: strings().starGiftCraftTooEarly(timeString))
            case .unavailable:
                onError()
                showModalText(for: window, text: strings().starGiftCraftUnavailable)
            case .craftFailed:
                if !animationStarted {
                    animationStarted = true
                    craftCtx.removeGifts(references: references)
                    startAnimation()
                }
                giftsContext?.removeStarGifts(references: references)
                updateState { current in
                    var current = current
                    current.craftingState = .failed(gifts: selectedGifts)
                    return current
                }
                onFailure(selectedGifts)
            }
        })
    }, showCraftVariants: {
        let state = stateValue.with { $0 }
        guard let gift = state.source.craftGift else { return }
        showModal(with: StarGift_ModelBuilderController(context: context, gift: .unique(gift), giftId: gift.giftId, onlyCraftedModels: true), for: window)
    }, craftAnother: {
        let state = stateValue.with { $0 }
        guard let cachedGift = state.craftCachedGift else { return }
        guard let craftCtx = craftGiftsContext else { return }

        updateState { current in
            var current = current
            current.craftingState = .idle
            current.craftSelectedSlots = [nil, nil, nil, nil]
            return current
        }

        showModal(with: StarGift_MarketplaceController(context: context, peerId: context.peerId, gift: cachedGift, craftGiftsContext: craftCtx, excludedReferences: [], selectGift: { selectedGift in
            if selectedGift.gift.unique?.giftAddress != nil {
                alert(for: window, header: strings().starGiftNftCantChooseFirst, info: strings().starGiftNftCantChooseFirstInfo)
                return
            }
            updateState { current in
                var current = current
                current.craftSelectedSlots[0] = selectedGift
                current.craftInitialGiftRef = selectedGift.reference
                return current
            }
        }), for: window)
    }, showCraftSuccess: { uniqueGift in
        PlayConfetti(for: window)
        updateState { current in
            var current = current
            current.source = .craftSuccess(uniqueGift)
            current.gift = .unique(uniqueGift)
            current.attributes = uniqueGift.attributes
            return current
        }
    }, okAction: {
        _ = getController?()?.returnKeyAction()
    })

    if let giftMenuItems {
        arguments.profileGiftMenu = {
            let items = giftMenuItems()
            func prepare(_ items: [NSMenuItem]) {
                for case let item as ContextMenuItem in items {
                    if let submenu = item.submenu {
                        prepare(submenu.items)
                    } else if !item.isSeparatorItem, let action = item.handler {
                        item.handler = {
                            close?()
                            action()
                        }
                    }
                }
            }
            prepare(items)
            return items
        }
    }

    arguments.toggleProfileVisibility = {
        guard let visibility = stateValue.with({ $0.profileVisibility }) else {
            return
        }
        let added = !visibility.saved
        giftsContext.updateStarGiftAddedToProfile(reference: visibility.reference, added: added)
        updateState { current in
            var current = current
            current.savedToProfileOverride = added
            return current
        }
    }
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: "")
    
    controller.didLoad = { controller, _ in
        controller.tableView.getBackgroundColor = {
            return theme.colors.background
        }
        if openCrafting, let gift = gift.unique {
            arguments.openCraftAbout(gift)
        }
    }
    
    controller.updateDatas = { data in
        updateState { current in
            var current = current
            current.tonAddress = data[_id_ton_input]?.stringValue
            return current
        }
        return .none
    }
    
    getController = { [weak controller] in
        return controller
    }

    controller.willDisappear = { _ in wearAction.setActive(false) }
    controller.willAppear = { _ in wearAction.setActive(true) }

    controller.onDeinit = {
        wearAction.setActive(false)
        actionsDisposable.dispose()
        craftContextDisposables.dispose()
    }

    let validateGift: ([InputDataIdentifier: InputDataValue]) -> InputDataValidation = { [weak giftsContext, weak controller] _ in
        guard let controller, wearAction.isActive else { return .none }
        let morphSource = ModalMorphContextSource.current
        let state = stateValue.with { $0 }
        _ = stateValue.with { $0.closeOnOk }
        
        switch state.source {
        case .preview:
            close?()
        case let .quickLook(peer, gift):
            var giftReference: StarGiftReference?
            if let purpose = state.purpose, case let .starGift(_, _, _, _, _, _, _, _, _, _, _, _, reference, _, _, _, _, _, _, _, _, _, _, _) = purpose {
                giftReference = reference
            }

            if let reference = giftReference {
                var canManage: Bool
                let peer = peer ?? state.owner

                if let peer, peer._asPeer().groupAccess.canManageGifts || peer.id == context.peerId {
                    canManage = true
                } else {
                    canManage = false
                }
                if canManage {
                    if let next = state.takeNextUpgradeGift, let peer, let reference = next.reference {

                        let formSignal = context.engine.payments.fetchBotPaymentForm(source: .starGiftUpgrade(keepOriginalInfo: false, reference: reference), themeParams: nil)

                        _ = showModalProgress(signal: combineLatest(context.engine.payments.starGiftUpgradePreview(giftId: next.gift.id) |> castError(BotPaymentFormRequestError.self), formSignal |> map(Optional.init) |> `catch` { error in
                            switch error {
                            case .noPaymentNeeded:
                                return .single(nil)
                            default:
                                return .fail(error)
                            }
                        }), for: window).startStandalone(next: { attributes, form in
                            if let attributes {
                                updateState { current in
                                    var current = current
                                    current.gift = next.gift
                                    current.source = .upgrade(peer, attributes, reference)
                                    current.purpose = nil
                                    current.converted = false
                                    current.upgradeForm = form
                                    current.canUpgradeNext = false
                                    return current
                                }
                            }
                        })
                    } else {
                        close?()
                    }
                } else {
                    close?()
                }
            } else if let _ = gift.resell {
                let signal = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: toPeerId)) |> deliverOnMainQueue


                let formAndMaybeValidatedInfo_Stars: Signal<BotPaymentForm?, BotPaymentFormRequestError>
                if gift.resellForTonOnly {
                    formAndMaybeValidatedInfo_Stars = .single(nil)
                } else {
                    formAndMaybeValidatedInfo_Stars = context.engine.payments.fetchBotPaymentForm(source: .starGiftResale(slug: gift.slug, toPeerId: toPeerId, ton: false, hideName: true, text: nil, entities: nil), themeParams: nil)
                    |> map(Optional.init)
                }



                let formAndMaybeValidatedInfo_Ton = context.engine.payments.fetchBotPaymentForm(source: .starGiftResale(slug: gift.slug, toPeerId: toPeerId, ton: true, hideName: true, text: nil, entities: nil), themeParams: nil)

                _ = showModalProgress(signal: combineLatest(signal |> castError(BotPaymentFormRequestError.self), formAndMaybeValidatedInfo_Stars, formAndMaybeValidatedInfo_Ton), for: window).start(next: { peer, starsForm, tonForm in
                    if let peer {
                        ModalMorphContextSource.withSource(morphSource) {
                            buyResellGift(gift, peer, starsForm ?? tonForm, tonForm)
                        }
                    }

                }, error: { _ in
                    showModalText(for: window, text: strings().unknownError)
                })
            } else {
                close?()
            }
        case let .previewWear(peer, gift):
            guard controller.isLoaded(), let targetWindow = controller.view.window as? Window else { return .none }
            guard let owner = state.owner, owner.id == peer.id, state.gift.unique?.id == gift.id else {
                showModalText(for: targetWindow, text: strings().unknownError)
                return .none
            }
            let canPresent: () -> Bool = { [weak controller, weak targetWindow] in
                guard let controller, let targetWindow, controller.isLoaded(), controller.view.window === targetWindow else { return false }
                return stateValue.with { current in
                    guard case let .previewWear(currentPeer, currentGift) = current.source else { return false }
                    return currentPeer.id == peer.id && currentGift.id == gift.id && current.owner?.id == peer.id && current.gift.unique?.id == gift.id
                }
            }
            wearAction.perform(context: context, peer: owner, gift: gift, window: targetWindow, canPresent: canPresent, completion: { [weak controller, weak targetWindow, weak wearAction] outcome in
                guard let controller, let targetWindow, wearAction?.isActive == true else { return }
                switch outcome {
                case .applied:
                    updateState { current in
                        var current = current
                        current.source = .quickLook(peer, gift)
                        current.converted = true
                        return current
                    }
                    guard wearAction?.isActive == true, controller.isLoaded(), controller.view.window === targetWindow else { return }
                    let isCurrent = stateValue.with { current in
                        guard case let .quickLook(currentPeer, currentGift) = current.source else { return false }
                        return currentPeer?.id == peer.id && currentGift.id == gift.id && current.owner?.id == peer.id && current.gift.unique?.id == gift.id
                    }
                    if isCurrent {
                        PlayConfetti(for: targetWindow)
                    }
                case .failed:
                    showModalText(for: targetWindow, text: strings().unknownError)
                case .premiumRequired:
                    showModalText(for: targetWindow, text: strings().giftUniqueNeedsPremium, callback: { [weak context, weak targetWindow, weak wearAction] _ in
                        guard let context, let targetWindow, wearAction?.isActive == true, canPresent() else { return }
                        prem(with: PremiumBoardingController(context: context, source: .emoji_status, openFeatures: true), for: targetWindow)
                    })
                case let .boostRequired(channel, stats, myStatus):
                    ModalMorphContextSource.withSource(morphSource) {
                        StarsHooks.shared.openBoostForWear(context, channel, stats, myStatus, targetWindow)
                    }
                }
            })
        case let .upgrade(_, _, reference):
            guard let starsState = state.starsState else { return .none }
            let isPrepaidUpgrade = (state.purpose?.upgradeStars ?? 0) > 0

            if !isPrepaidUpgrade, state.upgradeForm != nil, let upgradeStars = gift.generic?.upgradeStars, starsState.balance.value < upgradeStars {
                showModal(with: Star_ListScreen(context: context, source: .buy(suffix: nil, amount: upgradeStars)), for: window)
                return .none
            }

            guard let giftsContext else {
                return .none
            }

            let signal = giftsContext.upgradeStarGift(formId: isPrepaidUpgrade ? nil : state.upgradeForm?.id, reference: reference, keepOriginalInfo: state.nameEnabled) |> deliverOnMainQueue
            
            _ = showModalProgress(signal: signal, for: window).startStandalone(next: { converted in
                updateState { current in
                    var current = current
                    current.gift = converted.gift
                    
                    current.purpose = .starGift(gift: converted.gift, convertStars: converted.convertStars, text: converted.text, entities: converted.entities, nameHidden: converted.nameHidden, savedToProfile: converted.savedToProfile, converted: true, fromProfile: false, upgraded: true, prepaidUpgradeHash: nil, transferStars: converted.transferStars, canExportDate: converted.canExportDate, reference: converted.reference, sender: nil, saverId: nil, canTransferDate: converted.canTransferDate, canResaleDate: converted.canResaleDate, dropOriginalDetailsStars: converted.dropOriginalDetailsStars, canUpgrade: converted.canUpgrade, number: converted.number, isRefunded: false, canCraftAt: converted.canCraftAt, craftChancePermille: converted.gift.unique?.craftChancePermille, upgradeStars: nil)
                    
                    current.canUpgradeNext = true
                    current.converted = true
                    current.upgradeForm = nil
                    
                    current.ignoreUpgradeGifts.insert(reference)
                    
                    
                    switch converted.gift {
                    case let .unique(gift):
                        current.source = .quickLook(nil, gift)
                        current.attributes = gift.attributes
                    default:
                        break
                    }
                    return current
                }
                PlayConfetti(for: window)
            }, error: { error in
                switch error {
                case .generic, .alreadyUpgraded:
                    showModalText(for: window, text: strings().unknownError)
                }
            })
        case let .giftUpgrade(peer, _, prepaidUpgradeHash):
            guard let starsState = state.starsState else { return .none }
            if let upgradeStars = gift.generic?.upgradeStars, starsState.balance.value < upgradeStars {
                showModal(with: Star_ListScreen(context: context, source: .buy(suffix: nil, amount: upgradeStars)), for: window)
                return .none
            }
            
            guard giftsContext != nil else {
                return .none
            }
            
            let source: BotPaymentInvoiceSource = .starGiftPrepaidUpgrade(peerId: peer.id, hash: prepaidUpgradeHash)
            
            let signal = context.engine.payments.fetchBotPaymentForm(source: source, themeParams: nil)
            |> mapToSignal { form in
                return context.engine.payments.sendStarsPaymentForm(formId: form.id, source: source) |> mapError { _ in
                    return .generic
                }
            }
            |> deliverOnMainQueue
                        
            _ = showModalProgress(signal: signal, for: window).startStandalone(next: { data in
                StarsHooks.shared.openChat(context, peer.id, nil)
                close?()
                PlayConfetti(for: window)
            }, error: { error in
                showModalText(for: window, text: strings().unknownError)
            })
        case .aboutCraft, .crafting:
            break
        case let .craftSuccess(gift):
            guard let cachedGift = state.craftCachedGift else {
                close?()
                return .none
            }
            guard let craftCtx = craftGiftsContext else {
                close?()
                return .none
            }
            updateState { current in
                var current = current
                current.source = .crafting(gift)
                current.craftingState = .idle
                current.craftSelectedSlots = [nil, nil, nil, nil]
                return current
            }
            showModal(with: StarGift_MarketplaceController(context: context, peerId: context.peerId, gift: cachedGift, craftGiftsContext: craftCtx, excludedReferences: [], selectGift: { selectedGift in
                updateState { current in
                    var current = current
                    current.craftSelectedSlots[0] = selectedGift
                    current.craftInitialGiftRef = selectedGift.reference
                    return current
                }
            }), for: window)
        }

        return .none
    }

    controller.validateData = { data in
        return withGiftModalSource(for: window) {
            validateGift(data)
        }
    }

    let initialOkText = initialState.okText(context)

    let modalInteractions = ModalInteractions(acceptTitle: initialOkText, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, height: initialOkText.isEmpty ? 0 : 60, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)

    modalController._hasBorder = false

    controller.contextObject = (giftsContext, nextUpgradeContext)

    controller.afterTransaction = { [weak modalInteractions, weak modalController] _ in
        let okText = stateValue.with { $0.okText(context) }
        modalInteractions?.updateDone { button in
            button.isHidden = okText.isEmpty
            button.set(text: okText, for: .Normal)
        }
        modalController?.modal?.setInteractionHeight(height: okText.isEmpty ? 0 : 60, animated: false)
    }

    close = { [weak modalController] in
        modalController?.modal?.close()
    }

    return modalController
}





private final class SellNftArguments {
    public let context: (any AccountContextProtocol)
    public let interactions: TextView_Interactions
    public let updateState: (Updated_ChatTextInputState)->Void
    public let toggleOnlyTon:()->Void
    public init(context: (any AccountContextProtocol), interactions: TextView_Interactions, updateState: @escaping(Updated_ChatTextInputState)->Void, toggleOnlyTon:@escaping()->Void) {
        self.context = context
        self.interactions = interactions
        self.updateState = updateState
        self.toggleOnlyTon = toggleOnlyTon
    }
}


private final class SellNftInputItem : GeneralRowItem {
    public let inputState: Updated_ChatTextInputState
    public let arguments: SellNftArguments
    public let interactions: TextView_Interactions
    public let currency: CurrencyAmount.Currency
    
    public let usdLayout: TextViewLayout
    
    public init(_ initialSize: NSSize, stableId: AnyHashable, value: Double, inputState: Updated_ChatTextInputState, currency: CurrencyAmount.Currency, arguments: SellNftArguments) {
        self.currency = currency
        self.inputState = inputState
        self.arguments = arguments
        self.interactions = arguments.interactions
        
        let usd_rate: Double
        switch currency {
        case .ton:
            usd_rate = arguments.context.appConfiguration.getGeneralValueDouble("ton_usd_rate", orElse: 3)
        case .stars:
            usd_rate = arguments.context.appConfiguration.getGeneralValueDouble("star_usd_rate", orElse: 0.013)
        }
        
        let string: String
        if value > 0 {
            string = "~$\("\((Double(value) * usd_rate))".prettyCurrencyNumberUsd)"
        } else {
            string = ""
        }
        
        self.usdLayout = .init(.initialize(string: string, color: theme.colors.grayText, font: .normal(.short)))
        self.usdLayout.measure(width: .greatestFiniteMagnitude)
        
        super.init(initialSize, stableId: stableId)
        
    }
    
    public override var height: CGFloat {
        return 40
    }
    
    override var accessibilityLabel: String? {
        return strings().starNftSellHeader
    }
    
    override var accessibilityValue: String? {
        let value = usdLayout.attributedString.string
        return value.isEmpty ? nil : value
    }
    
    public override func viewClass() -> AnyClass {
        return SellNftInputView.self
    }
}


private final class SellNftInputView : GeneralRowView {
    
    private final class Input : View {
        
        private weak var item: SellNftInputItem?
        public let inputView: UITextView = UITextView(frame: NSMakeRect(0, 0, 100, 40))
        private let usdView = TextView()
        private let starView = InteractiveTextView()
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(starView)
            addSubview(inputView)
            addSubview(usdView)

            layer?.cornerRadius = 10
        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public func update(item: SellNftInputItem, animated: Bool) {
            self.item = item
            self.backgroundColor = theme.colors.background
            
            let attr = NSMutableAttributedString()
            attr.append(string: clown)
            switch item.currency {
            case .stars:
                attr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.star_currency_new.file), for: clown)
            case .ton:
                attr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.ton_logo.file), for: clown)
            }
            
            let layout = TextViewLayout(attr)
            layout.measure(width: .greatestFiniteMagnitude)
            
            self.starView.set(text: layout, context: item.arguments.context)
            self.usdView.update(item.usdLayout)
            

            
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
            
            let value = Double(item.inputState.string) ?? 0
            
            let min_resale: Double
            let max_resale: Double
            
            switch item.currency {
            case .stars:
                min_resale = item.arguments.context.appConfiguration.getGeneralValueDouble("stars_stargift_resale_amount_min", orElse: 125)
                max_resale = item.arguments.context.appConfiguration.getGeneralValueDouble("stars_stargift_resale_amount_max", orElse: 100000)
            case .ton:
                min_resale = item.arguments.context.appConfiguration.getGeneralValueDouble("ton_stargift_resale_amount_min", orElse: 1) / 1_000_000_000
                max_resale = item.arguments.context.appConfiguration.getGeneralValueDouble("ton_stargift_resale_amount_max", orElse: 10000) / 1_000_000_000
            }

            inputView.inputTheme = inputView.inputTheme.withUpdatedTextColor(Double(value) < min_resale || Double(value) > max_resale ? theme.colors.redUI : theme.colors.text)
            
            
            let currency = item.currency
            item.interactions.filterEvent = { event in
                if let chars = event.characters {
                    switch currency {
                    case .stars:
                        return chars.trimmingCharacters(in: CharacterSet(charactersIn: "1234567890\u{7f}")).isEmpty
                    case .ton:
                        return chars.trimmingCharacters(in: CharacterSet(charactersIn: "1234567890.\u{7f}")).isEmpty
                    }
                } else {
                    return false
                }
            }

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
        
        
        public var textWidth: CGFloat {
            return frame.width - 20
        }
        
        public func textViewSize() -> (NSSize, CGFloat) {
            return StarsHooks.shared.inputTextViewSize(inputView, textWidth)
        }
        
        private func inputDidUpdateLayout(animated: Bool) {
            self.updateLayout(size: frame.size, transition: animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate)
        }
        
        public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
            let (textSize, textHeight) = textViewSize()
            
            transition.updateFrame(view: starView, frame: starView.centerFrameY(x: 10))
            
            transition.updateFrame(view: inputView, frame: CGRect(origin: CGPoint(x: starView.frame.maxX + 10, y: 7), size: textSize))
            inputView.updateLayout(size: textSize, textHeight: textHeight, transition: transition)
            
            ContainedViewLayoutTransition.immediate.updateFrame(view: usdView, frame: usdView.centerFrameY(x: size.width - usdView.frame.width - 10))
        }
        
        private func set(_ state: Updated_ChatTextInputState) {
            guard let item else {
                return
            }
            item.arguments.updateState(state)
            
            item.redraw(animated: true)
        }
    }
    
    private let inputView = Input(frame: NSMakeRect(0, 0, 40, 40))
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(inputView)
    }
    public override var backdorColor: NSColor {
        return theme.colors.listBackground
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? SellNftInputItem else {
            return
        }
        
        self.inputView.update(item: item, animated: animated)
        
               
        self.inputView.updateLayout(size: self.frame.size, transition: animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate)
    }
    
    public override func shakeView() {
        inputView.shake(beep: true)
    }
    
    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        
        transition.updateFrame(view: inputView, frame: NSMakeRect(20, 0, size.width - 40,40))
        inputView.updateLayout(size: inputView.frame.size, transition: transition)
        
    }
    public override var firstResponder: NSResponder? {
        return inputView.inputView.inputView
    }
}

private struct SellNftState : Equatable {
    
    public var inputState: Updated_ChatTextInputState = .init()
    
    public var floorPrice: Int64?
    public var currency: CurrencyAmount.Currency = .stars
    
    public var value: Double {
        if let value = Double(inputState.string) {
            return value
        } else {
            return 0
        }
    }
    
    public func amount(comission: Double) -> StarsAmount {
        switch self.currency {
        case .stars:
            return .init(value: Int64((Double(self.value) * comission)), nanos: 0)
        case .ton:
            return .init(value: Int64((Double(self.value) * comission) * 1_000_000_000), nanos: 0)
        }
    }
}


private let _id_input = InputDataIdentifier("_id_input")
private let _id_only_ton = InputDataIdentifier("_id_only_ton")

private func sellNftEntries(_ state: SellNftState, arguments: SellNftArguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().starNftSellHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_input, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return SellNftInputItem(initialSize, stableId: stableId, value: state.value, inputState: state.inputState, currency: state.currency, arguments: arguments)
    }))
    
    let comission: Double = arguments.context.marketComission(state.currency)
    
    
    
    var text: String
    if state.value == 0 {
        text = strings().starNftSellInfo("\(comission * 100.0)%")
    } else {
        let currency = CurrencyAmount(amount: state.amount(comission: comission), currency: state.currency)
        text = strings().starNftSellInfo(currency.fullyFormatted)
    }
    
   
    entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(text, linkHandler: { _ in }), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    
    entries.append(.general(
        sectionId: sectionId,
        index: index,
        value: .none,
        error: nil,
        identifier: _id_only_ton,
        data: .init(
            name: strings().starSellTonOnlyAccept,
            color: theme.colors.text,
            type: .switchable(state.currency == .ton),
            viewType: .singleItem,
            action: arguments.toggleOnlyTon,
            autoswitch: false
        )
    ))

    entries.append(.desc(
        sectionId: sectionId,
        index: index,
        text: .plain(strings().starSellTonDescription),
        data: .init(
            color: theme.colors.listGrayText,
            viewType: .textBottomItem
        )
    ))

    index += 1


    
    if let floorPrice = state.floorPrice {
        
        entries.append(.sectionId(sectionId, type: .customModern(10)))
        sectionId += 1
        
        let text = strings().starNftSellFloor(strings().starListItemCountOther(Int(floorPrice)))
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(text, linkHandler: { _ in }), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1

    }
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    
    return entries
}



private func sellNft(context: (any AccountContextProtocol), resellPrice: [CurrencyAmount]?, defaultCurrency: CurrencyAmount.Currency, gift: StarGift.UniqueGift, callback:@escaping(CurrencyAmount)->Void) -> InputDataModalController {
    
    
    
    let string: String
    if let resellPrice = resellPrice {
        switch defaultCurrency {
        case .stars:
            if let currency = resellPrice.first(where: { $0.currency == .stars }) {
                string = currency.formatted.numeralFormat()
            } else {
                string = ""
            }
        case .ton:
            if let currency = resellPrice.first(where: { $0.currency == .ton }) {
                string = currency.formatted.numeralFormat()
            } else {
                string = ""
            }
        }
    } else {
        string = ""
    }
    
    
    let initialState = SellNftState(inputState: .init(inputText: .initialize(string: string)), currency: defaultCurrency)

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((SellNftState) -> SellNftState) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    

    let usd_rate = context.appConfiguration.getGeneralValueDouble("ton_usd_rate", orElse: 3)


    let actionsDisposable = DisposableSet()
    
    var close:(()->Void)? = nil
        
    let interactions = TextView_Interactions(presentation: initialState.inputState)
    
    actionsDisposable.add(context.engine.payments.cachedStarGifts().start(next: { gifts in
        updateState { current in
            var current = current
            current.floorPrice = gifts?.first(where: { $0.generic?.title == gift.title })?.generic?.availability?.minResaleStars
            return current
        }
    }))

    let arguments = SellNftArguments(context: context, interactions: interactions, updateState: { [weak interactions] value in
        
        let currency = stateValue.with { $0.currency }
        
        var inputState: Updated_ChatTextInputState
        let doubleValue = Double(value.string) ?? 0
        let doubleString = "\(doubleValue)"
        let hasNonDigits = doubleString.range(of: ".0") != nil ? false : "\(doubleValue)".rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) != nil

        if hasNonDigits {

            switch currency {
            case .stars:
                let safeInt: Int64
                if !doubleValue.isFinite || doubleValue < 0 {
                    safeInt = 0
                } else if doubleValue >= Double(Int64.max) {
                    safeInt = Int64.max
                } else {
                    safeInt = Int64(doubleValue)
                }
                inputState = .init(inputText: .initialize(string: "\(safeInt)"))
            case .ton:
                inputState = .init(inputText: .initialize(string: "\((doubleValue * 100).rounded() / 100)"))
            }
        } else {
            inputState = value
        }
        
        
        interactions?.update { _ in
            return inputState
        }
        updateState { current in
            var current = current
            current.inputState = inputState
            return current
        }
    }, toggleOnlyTon: { [weak interactions] in
        
        let currency = stateValue.with { $0.currency }
        var value = stateValue.with { $0.value }
        
//        let min_ton_resale_stars = context.appConfiguration.getGeneralValueDouble("stars_stargift_stars_ton_min", orElse: 5000)
//
//        
//        if currency == .stars, value < min_ton_resale_stars {
//            showModalText(for: context.window, text: strings().starGiftNftResaleMinPriceInfo(strings().starListItemCountOther(Int(min_ton_resale_stars))))
//            return
//        }
        
        updateState { current in
            var current = current
            switch current.currency {
            case .ton:
                current.currency = .stars
            case .stars:
                current.currency = .ton
            }
            return current
        }
        var inputState: Updated_ChatTextInputState

        switch currency {
        case .ton:
            if value > 0 {
                let usd = Double(value) * usd_rate
                value = Double(Int64(usd / 0.013))
            }
            inputState = .init(inputText: .initialize(string: "\(Int64(value))"))
        case .stars:
            if value > 0 {
                let usd = Double(value) * 0.013
                value = ((usd / usd_rate) * 100).rounded() / 100
            }
            inputState = .init(inputText: .initialize(string: "\(value)"))
        }
        
        
        interactions?.update { _ in
            return inputState
        }
        updateState { current in
            var current = current
            current.inputState = inputState
            return current
        }
        
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: sellNftEntries(state, arguments: arguments))
    }
    
    

    
    let controller = InputDataController(dataSignal: signal, title: strings().starNftSellTitle)
    
    controller.validateData = { _ in
        
        let state = stateValue.with { $0 }
        
        let min_resale: Double
        let max_resale: Double
        
        
        switch state.currency {
        case .stars:
            min_resale = context.appConfiguration.getGeneralValueDouble("stars_stargift_resale_amount_min", orElse: 125)
            max_resale = context.appConfiguration.getGeneralValueDouble("stars_stargift_resale_amount_max", orElse: 100000)
        case .ton:
            min_resale = context.appConfiguration.getGeneralValueDouble("ton_stargift_resale_amount_min", orElse: 1) / 1_000_000_000
            max_resale = context.appConfiguration.getGeneralValueDouble("ton_stargift_resale_amount_max", orElse: 10000) / 1_000_000_000
        }
        
        let value = state.value
        
        if Double(value) < min_resale || Double(value) > max_resale {
            return .fail(.fields([_id_input : .shake]))
        }
        
                
        callback(.init(amount: state.amount(comission: 1), currency: state.currency))
        close?()
        return .none
    }
        
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
   
    
    let modalInteractions = ModalInteractions(acceptTitle: resellPrice != nil ? strings().starNftSellButtonUpdate : strings().starNftSellButtonSell, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true)

    
    
    actionsDisposable.add(statePromise.get().startStrict(next: { [weak modalInteractions] state in
        DispatchQueue.main.async {
            modalInteractions?.updateDone { button in
                button.isEnabled = true
            }
        }
    }))
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    close = { [weak modalController] in
        modalController?.close()
    }
    
    
    return modalController
}


private let addGiftMessageBackgroundColors: [NSColor] = [0xdbddbb, 0x6ba587, 0xd5d88d, 0x88b884].map { NSColor(argb: $0) }

private final class AddGiftMessageArguments {
    public let context: (any AccountContextProtocol)
    public let updateState:(Updated_ChatTextInputState, CGFloat)->Void
    public let togglePublic:()->Void
    public let send:()->Void
    public init(context: (any AccountContextProtocol), updateState:@escaping(Updated_ChatTextInputState, CGFloat)->Void, togglePublic:@escaping()->Void, send:@escaping()->Void) {
        self.context = context
        self.updateState = updateState
        self.togglePublic = togglePublic
        self.send = send
    }
}

private struct AddGiftMessageState: Equatable {
    public var textState: Updated_ChatTextInputState = .init()
    public var isPublic: Bool = false
    public var inputHeight: CGFloat = 56
}

public func measureBalancedGiftMessage(_ layout: TextViewLayout, width: CGFloat) {
    layout.measure(width: width)
    guard layout.numberOfLines > 1 else {
        return
    }

    let trial = TextViewLayout(layout.attributedString)
    trial.measure(width: width)

    let numberOfLines = trial.numberOfLines
    var bestWidth = width
    var bestDifference = trial.layoutSize.width - trial.lastLineWidth
    var currentWidth = width - 8

    while currentWidth > 0 {
        trial.measure(width: currentWidth)
        if trial.numberOfLines > numberOfLines {
            break
        }
        let difference = trial.layoutSize.width - trial.lastLineWidth
        if difference < bestDifference {
            bestWidth = currentWidth
            bestDifference = difference
        }
        currentWidth -= 8
    }

    layout.measure(width: bestWidth)
}


private final class AddGiftMessagePublicItem: GeneralRowItem {
    fileprivate let isPublic: Bool
    fileprivate let toggle:()->Void
    fileprivate let layout: TextViewLayout

    public init(_ initialSize: NSSize, stableId: AnyHashable, isPublic: Bool, toggle: @escaping()->Void) {
        self.isPublic = isPublic
        self.toggle = toggle
        self.layout = TextViewLayout(.initialize(string: strings().starGiftAddMessageMakePublic, color: darkPalette.background, font: .normal(.text)))
        self.layout.measure(width: 260)
        super.init(initialSize, stableId: stableId)
    }

    public override var height: CGFloat {
        return 30
    }

    override var accessibilityLabel: String? {
        return layout.attributedString.string
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return .checkBox
    }

    override var accessibilityToggleState: Bool? {
        return isPublic
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }

    override func accessibilityPerformPress() -> Bool {
        toggle()
        return true
    }

    public override func viewClass() -> AnyClass {
        return AddGiftMessagePublicView.self
    }
}

private final class AddGiftMessagePublicView: TableRowView {
    private let control = Control()
    private let glass = LiquidGlassView(frame: NSZeroRect, cornerRadius: 15, hasShadow: true, hasBorder: true, customTint: addGiftMessageBackgroundColors[1].darker(amount: 0.1))
    private let selecting = SelectingControl(unselectedImage: generateChatGroupToggleUnselected(foregroundColor: darkPalette.background.withAlphaComponent(0.8), backgroundColor: NSColor.black.withAlphaComponent(0.01)), selectedImage: theme.icons.chatToggleSelected)
    private let textView = TextView()

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        control.addSubview(glass)
        control.addSubview(selecting)
        control.addSubview(textView)
        addSubview(control)

        layer?.masksToBounds = false
        control.layer?.masksToBounds = false

        textView.userInteractionEnabled = false
        textView.isSelectable = false
        selecting.userInteractionEnabled = false

        control.scaleOnClick = true
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var backdorColor: NSColor {
        return .clear
    }

    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? AddGiftMessagePublicItem else {
            return
        }

        selecting.set(selected: item.isPublic, animated: animated)
        textView.update(item.layout)

        control.setFrameSize(NSMakeSize(10 + selecting.frame.width + 6 + item.layout.layoutSize.width + 14, 30))

        control.removeAllHandlers()
        control.set(handler: { [weak item] _ in
            item?.toggle()
        }, for: .Click)

        needsLayout = true
    }

    public override func layout() {
        super.layout()

        control.center()
        glass.frame = control.bounds
        selecting.centerY(x: 10)
        textView.centerY(x: selecting.frame.maxX + 6)
    }
}

private final class AddGiftMessageInputView : View {
    private static let capsuleInset: CGFloat = 10
    private static let textInset: CGFloat = 14
    private static let buttonSize = NSMakeSize(30, 30)
    private static let buttonInset: CGFloat = 4

    private let context: (any AccountContextProtocol)
    private let inputGlass = LiquidGlassView(frame: NSZeroRect, cornerRadius: 18, hasShadow: true, hasBorder: true)
    public let textView: UITextView = UITextView(frame: NSMakeRect(0, 0, 100, 22))
    private let emojiButton = ImageButton()
    private let sendButton = ImageButton()
    private let limitView = TextView()
    private let limit: Int32

    public var send: (() -> Void)? = nil
    public var stateDidChange: ((Updated_ChatTextInputState) -> Void)? = nil

    private var singleLineCapsuleHeight: CGFloat = 36

    public init(frame frameRect: NSRect, context: (any AccountContextProtocol), limit: Int32) {
        self.context = context
        self.limit = limit
        super.init(frame: frameRect)

        addSubview(inputGlass)
        addSubview(textView)
        addSubview(emojiButton)
        addSubview(sendButton)
        addSubview(limitView)

        self.backgroundColor = .clear

        limitView.userInteractionEnabled = false
        limitView.isSelectable = false
        limitView.isHidden = true

        textView.context = context
        textView.interactions.min_height = 18
        textView.interactions.max_height = 120
        textView.placeholder = strings().starGiftAddMessageInputPlaceholder
        textView.inputTheme = theme.inputTheme

        textView.interactions.inputDidUpdate = { [weak self] state in
            guard let self else { return }
            var state = state
            if state.inputText.string.contains("\n") {
                let sanitized = NSMutableAttributedString(attributedString: state.inputText)
                sanitized.mutableString.replaceOccurrences(of: "\n", with: " ", options: [], range: NSMakeRange(0, sanitized.length))
                state.inputText = sanitized
                self.textView.interactions.update { _ in state }
            }
            self.updateLimitCounter(with: state)
            self.stateDidChange?(state)
        }

        emojiButton.autohighlight = false
        emojiButton.scaleOnClick = true
        emojiButton.set(image: TelegramThemeHooks.shared.image(.iconCustomEmojiSmall).precomposed(theme.colors.grayIcon), for: .Normal)
        emojiButton.sizeToFit()
        emojiButton.setAccessibilityLabel(strings().voiceOverCommonEmoji)

        let plane = TelegramThemeHooks.shared.image(.iconSendMessage).precomposed(.white)
        let planeIcon = generateImage(NSMakeSize(16, 16), contextGenerator: { size, ctx in
            ctx.clear(size.bounds)
            ctx.draw(plane, in: size.bounds)
        })!

        sendButton.autohighlight = false
        sendButton.scaleOnClick = true
        sendButton.setAccessibilityLabel(strings().voiceOverMessageContextSend)
        sendButton.set(background: theme.colors.accentIcon, for: .Normal)
        sendButton.set(image: planeIcon, for: .Normal)
        sendButton.setFrameSize(AddGiftMessageInputView.buttonSize)
        sendButton.layer?.cornerRadius = AddGiftMessageInputView.buttonSize.height / 2

        sendButton.set(handler: { [weak self] _ in
            self?.send?()
        }, for: .Click)

        emojiButton.set(handler: { [weak self] control in
            self?.showEmojis(control)
        }, for: .Click)

        self.singleLineCapsuleHeight = max(textView.height(for: 1000) + 12, 36)
    }

    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func showEmojis(_ control: Control) {
        StarsHooks.shared.showEmojiPicker(context, control, { [weak self] file, text in
            self?.insertEmoji(.makeAnimated(file, text: text))
        }, { [weak self] string in
            self?.insertEmoji(.initialize(string: string))
        })
    }

    private func insertEmoji(_ text: NSAttributedString) {
        let state = textView.interactions.insertText(text)
        textView.interactions.update { _ in
            return state
        }
        textView.makeFirstResponder()
        updateLimitCounter(with: state)
        stateDidChange?(state)
    }

    // iOS parity: the limit is soft — typing/paste may exceed it; a countdown appears at
    // remaining <= 4, turns red past the limit, and send is blocked upstream.
    private func updateLimitCounter(with state: Updated_ChatTextInputState) {
        let remaining = Int(limit) - state.inputText.string.count
        if remaining < 5 {
            let color: NSColor = remaining < 0 ? theme.colors.redUI : theme.colors.grayText
            let layout = TextViewLayout(.initialize(string: "\(max(remaining, -999))", color: color, font: .normal(.small)))
            layout.measure(width: .greatestFiniteMagnitude)
            limitView.update(layout)
            limitView.isHidden = false
        } else {
            limitView.isHidden = true
        }
        needsLayout = true
    }

    private var capsuleWidth: CGFloat {
        return frame.width - AddGiftMessageInputView.capsuleInset * 2
    }

    public func textViewSize() -> (NSSize, CGFloat) {
        typealias Metrics = AddGiftMessageInputView
        let w = capsuleWidth - Metrics.textInset - emojiButton.frame.width - 6 - Metrics.buttonSize.width - Metrics.buttonInset - 6
        let height = textView.height(for: w)
        return (NSMakeSize(w, min(max(height, textView.min_height), textView.max_height)), height)
    }

    private var capsuleHeight: CGFloat {
        return max(textViewSize().0.height + 12, 36)
    }

    public var idealHeight: CGFloat {
        return capsuleHeight + AddGiftMessageInputView.capsuleInset * 2
    }

    public func updateInputHeight(animated: Bool) {
        let height = idealHeight
        guard abs(frame.height - height) > 1, let superview else {
            self.needsLayout = true
            return
        }
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate
        let newFrame = NSMakeRect(frame.minX, superview.frame.height - height, frame.width, height)
        transition.updateFrame(view: self, frame: newFrame)
        self.updateLayout(size: newFrame.size, transition: transition)
    }

    public override func layout() {
        super.layout()
        self.updateLayout(size: frame.size, transition: .immediate)
    }

    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        typealias Metrics = AddGiftMessageInputView
        let (textSize, textHeight) = textViewSize()
        let capsuleHeight = self.capsuleHeight

        let capsuleFrame = NSMakeRect(Metrics.capsuleInset, Metrics.capsuleInset, capsuleWidth, capsuleHeight)
        transition.updateFrame(view: inputGlass, frame: capsuleFrame)

        transition.updateFrame(view: textView, frame: CGRect(origin: NSMakePoint(capsuleFrame.minX + Metrics.textInset, capsuleFrame.minY + floorToScreenPixels(System.backingScale, (capsuleHeight - textSize.height) / 2)), size: textSize))
        textView.updateLayout(size: textSize, textHeight: textHeight, transition: transition)

        let sendInsetY = floorToScreenPixels(System.backingScale, (singleLineCapsuleHeight - Metrics.buttonSize.height) / 2)
        let sendFrame = CGRect(origin: NSMakePoint(capsuleFrame.maxX - Metrics.buttonSize.width - Metrics.buttonInset, capsuleFrame.maxY - Metrics.buttonSize.height - sendInsetY), size: Metrics.buttonSize)
        transition.updateFrame(view: sendButton, frame: sendFrame)

        let emojiInsetY = floorToScreenPixels(System.backingScale, (singleLineCapsuleHeight - emojiButton.frame.height) / 2)
        let emojiFrame = CGRect(origin: NSMakePoint(sendFrame.minX - 6 - emojiButton.frame.width, capsuleFrame.maxY - emojiButton.frame.height - emojiInsetY), size: emojiButton.frame.size)
        transition.updateFrame(view: emojiButton, frame: emojiFrame)

        if !limitView.isHidden {
            let limitInsetY = floorToScreenPixels(System.backingScale, (singleLineCapsuleHeight - limitView.frame.height) / 2)
            let limitFrame = CGRect(origin: NSMakePoint(emojiFrame.minX - 6 - limitView.frame.width, capsuleFrame.maxY - limitView.frame.height - limitInsetY), size: limitView.frame.size)
            transition.updateFrame(view: limitView, frame: limitFrame)
        }
    }
}

private final class AddGiftMessageServiceTextItem : GeneralRowItem {
    fileprivate let layout: TextViewLayout

    public init(_ initialSize: NSSize, stableId: AnyHashable, text: String) {
        let attr = NSMutableAttributedString()
        attr.append(string: text, color: darkPalette.background, font: .normal(.text))
        attr.detectBoldColorInString(with: .medium(.text))
        self.layout = TextViewLayout(attr, alignment: .center)
        self.layout.measure(width: 300)
        super.init(initialSize, stableId: stableId)
    }

    public override var height: CGFloat {
        return 30
    }

    override var accessibilityLabel: String? {
        return layout.attributedString.string
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override func viewClass() -> AnyClass {
        return AddGiftMessageServiceTextView.self
    }
}

private final class AddGiftMessageServiceTextView : TableRowView {
    private let container = View()
    private let glass = LiquidGlassView(frame: NSZeroRect, cornerRadius: 15, hasShadow: true, hasBorder: true, customTint: addGiftMessageBackgroundColors[1].darker(amount: 0.1))
    private let textView = TextView()

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        container.addSubview(glass)
        container.addSubview(textView)
        addSubview(container)

        layer?.masksToBounds = false
        container.layer?.masksToBounds = false

        textView.userInteractionEnabled = false
        textView.isSelectable = false
        textView.disableBackgroundDrawing = true
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var backdorColor: NSColor {
        return .clear
    }

    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? AddGiftMessageServiceTextItem else {
            return
        }
        textView.update(item.layout)
        container.setFrameSize(NSMakeSize(item.layout.layoutSize.width + 28, 30))
        needsLayout = true
    }

    public override func layout() {
        super.layout()
        container.center()
        glass.frame = container.bounds
        textView.center()
    }
}

private final class AddGiftMessageSpacerItem : GeneralRowItem {
    private let spacerHeight: CGFloat

    public init(_ initialSize: NSSize, stableId: AnyHashable, height: CGFloat) {
        self.spacerHeight = height
        super.init(initialSize, stableId: stableId)
    }

    public override var height: CGFloat {
        return spacerHeight
    }

    override var accessibilityIsSpacer: Bool {
        return true
    }

    public override func viewClass() -> AnyClass {
        return AddGiftMessageSpacerView.self
    }
}

private final class AddGiftMessageSpacerView : TableRowView {
    public override var backdorColor: NSColor {
        return .clear
    }
}

private let _id_gift_message_caption = InputDataIdentifier("_id_gift_message_caption")
private let _id_gift_message_preview = InputDataIdentifier("_id_gift_message_preview")
private let _id_gift_message_public = InputDataIdentifier("_id_gift_message_public")

private func addGiftMessageSpacer(_ entries: inout [InputDataEntry], sectionId: Int32, index: inout Int32, height: CGFloat) {
    let stableIndex = index
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: InputDataIdentifier("_id_gift_message_spacer_\(stableIndex)"), equatable: .init(height), comparable: nil, item: { initialSize, stableId in
        return AddGiftMessageSpacerItem(initialSize, stableId: stableId, height: height)
    }))
    index += 1
}

private func addGiftMessageEntries(_ state: AddGiftMessageState, gift: StarGift.UniqueGift, toPeer: EnginePeer, arguments: AddGiftMessageArguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []

    let sectionId: Int32 = 0
    var index: Int32 = 0

    addGiftMessageSpacer(&entries, sectionId: sectionId, index: &index, height: 20)

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_gift_message_caption, equatable: nil, comparable: nil, item: { initialSize, stableId in
        return AddGiftMessageServiceTextItem(initialSize, stableId: stableId, text: strings().starGiftAddMessagePreviewInChat)
    }))
    index += 1

    addGiftMessageSpacer(&entries, sectionId: sectionId, index: &index, height: 10)

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_gift_message_preview, equatable: .init(state.textState), comparable: nil, item: { initialSize, stableId in
        return StarsHooks.shared.makeGiftMessagePreview(initialSize, stableId, arguments.context, gift, state.textState, arguments.send)
    }))
    index += 1

    addGiftMessageSpacer(&entries, sectionId: sectionId, index: &index, height: 10)

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_gift_message_public, equatable: .init(state.isPublic), comparable: nil, item: { initialSize, stableId in
        return AddGiftMessagePublicItem(initialSize, stableId: stableId, isPublic: state.isPublic, toggle: arguments.togglePublic)
    }))
    index += 1

    addGiftMessageSpacer(&entries, sectionId: sectionId, index: &index, height: state.inputHeight + 10)

    return entries
}

public func StarGift_AddMessage_Controller(context: (any AccountContextProtocol), gift: StarGift.UniqueGift, toPeer: EnginePeer, send: @escaping(Updated_ChatTextInputState, Bool)->Void) -> InputDataModalController {

    let initialState = AddGiftMessageState()

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((AddGiftMessageState) -> AddGiftMessageState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    var close: (() -> Void)? = nil
    var shakeOnOverLimit: (() -> Void)? = nil

    let maxTextLength = context.appConfiguration.getGeneralValue("stargifts_message_length_max", orElse: 255)

    let arguments = AddGiftMessageArguments(context: context, updateState: { textState, inputHeight in
        updateState { current in
            var current = current
            current.textState = textState
            current.inputHeight = inputHeight
            return current
        }
    }, togglePublic: {
        updateState { current in
            var current = current
            current.isPublic = !current.isPublic
            return current
        }
    }, send: {
        let state = stateValue.with { $0 }
        guard state.textState.inputText.string.count <= Int(maxTextLength) else {
            shakeOnOverLimit?()
            return
        }
        send(state.textState, state.isPublic)
        close?()
    })

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: addGiftMessageEntries(state, gift: gift, toPeer: toPeer, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: "")

    controller.validateData = { _ in
        arguments.send()
        return .none
    }

    let inputView = AddGiftMessageInputView(frame: NSMakeRect(0, 0, 350, 40), context: context, limit: maxTextLength)
    inputView.setFrameSize(NSMakeSize(350, inputView.idealHeight))

    shakeOnOverLimit = { [weak inputView] in
        inputView?.shake(beep: true)
    }

    inputView.send = {
        arguments.send()
    }
    inputView.textView.interactions.processEnter = { event in
        if FastSettings.checkSendingAbility(for: event) {
            arguments.send()
        }
        return true
    }

    let backgroundColors = addGiftMessageBackgroundColors

    let dismiss = ImageButton()
    dismiss.scaleOnClick = true
    dismiss.autohighlight = false
    dismiss.set(image: TelegramThemeHooks.shared.image(.iconPipClose).precomposed(theme.colors.grayText), for: .Normal)
    dismiss.setGlassEffect(size: NSMakeSize(36, 36), tintColor: backgroundColors[1].darker(amount: 0.1))
    dismiss.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
    dismiss.setFrameOrigin(NSMakePoint(10, 10))
    dismiss.setAccessibilityLabel(strings().voiceOverCommonClose)

    controller.afterViewDidLoad = { [weak controller] in
        controller?.genericView.setBottom(inputView)
        controller?.genericView.backgroundMode = .gradient(colors: backgroundColors, rotation: nil)
        controller?.genericView.addSubview(dismiss)
    }

    controller.didLoad = { [weak inputView] controller, _ in
        controller.tableView.getBackgroundColor = {
            return .clear
        }
        if let inputView {
            _ = controller.window?.makeFirstResponder(inputView.textView.inputView)
        }
    }

    let modalController = InputDataModalController(controller)

    modalController._hasBorder = false

    inputView.stateDidChange = { [weak inputView] state in
        inputView?.updateInputHeight(animated: true)
        arguments.updateState(state, inputView?.idealHeight ?? 56)
    }

    dismiss.set(handler: { [weak modalController] _ in
        modalController?.close()
    }, for: .Click)

    close = { [weak modalController] in
        modalController?.close()
    }

    return modalController
}
