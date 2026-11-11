import Cocoa
import Foundation
import TGUIKit
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
import AppAnalytics


private final class HeaderItem : GeneralRowItem {
    fileprivate let infoLayout: TextViewLayout
    fileprivate let titleLayout: TextViewLayout
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let gift: StarGift
    fileprivate let arguments: Arguments
    
    public let upcomingLayout: TextViewLayout?
    
    public init(_ initialSize: NSSize, stableId: AnyHashable, gift: StarGift, state: State, context: (any AccountContextProtocol), arguments: Arguments) {
        self.context = context
        self.gift = gift
        self.arguments = arguments
        
        let value = gift.generic!
        
        let title = value.title ?? strings().starAuctionPreviewAuction

        self.titleLayout = .init(
            .initialize(
                string: title,
                color: theme.colors.text,
                font: .medium(.header)
            ),
            alignment: .center
        )

        let text: String
        if let perks = state.perks, perks.startDate > state.currentDate {
            text =  "[\(strings().starAuctionPreviewLearnMoreAboutGifts)](more)"
            upcomingLayout = .init(.initialize(string: strings().chatListUpcomingAuction, color: .white, font: .medium(.text)), alignment: .center)
            upcomingLayout?.measure(width: .greatestFiniteMagnitude)
        } else if !state.isFinished {
            let biddersText = strings().starAuctionPreviewBiddersOther(Int(value.auctionGiftsPerRound ?? 0))
            text = strings().starAuctionPreviewLearnMore(biddersText, title)
            upcomingLayout = nil
        } else {
            text =  "[\(strings().starAuctionPreviewLearnMoreAboutGifts)](more)"
            upcomingLayout = .init(.initialize(string: strings().starAuctionPreviewEnded, color: .white, font: .medium(.text)), alignment: .center)
            upcomingLayout?.measure(width: .greatestFiniteMagnitude)

        }

        
        let parsed = parseMarkdownIntoAttributedString(text, attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: .normal(.text), textColor: NSColor.white.withAlphaComponent(0.8)), bold: MarkdownAttributeSet(font: .medium(.text), textColor: NSColor.white.withAlphaComponent(0.8)), link: MarkdownAttributeSet(font: .medium(.text), textColor: NSColor.white.withAlphaComponent(0.8)), linkAttribute: { link in
            return (NSAttributedString.Key.link.rawValue, LinkHooks.shared.callbackLink(link, { value in
                if value == "more" {
                    arguments.openLearn()
                } else {
                    arguments.about()
                }
            }))
        })).detectBold(with: .medium(.text)).mutableCopy() as! NSMutableAttributedString

        parsed.replaceChevron(color: NSColor.white.withAlphaComponent(0.8))

        self.infoLayout = .init(parsed, alignment: .center)
        self.infoLayout.interactions = LinkHooks.shared.globalLinkExecutor()
        
        super.init(initialSize, stableId: stableId)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        self.titleLayout.measure(width: width - 40)
        self.infoLayout.measure(width: width - 40)
        return true
    }
    
    override var accessibilityLabel: String? {
        return titleLayout.attributedString.string
    }
    
    override var accessibilityValue: String? {
        return [infoLayout.attributedString.string, upcomingLayout?.attributedString.string].compactMap { $0 }.joined(separator: ", ")
    }
    
    public override func viewClass() -> AnyClass {
        return HeaderView.self
    }
    
    public override var height: CGFloat {
        var height = 130 + 10 + titleLayout.layoutSize.height + infoLayout.layoutSize.height + 5 + 15
        
        if let upcomingLayout {
            height += upcomingLayout.layoutSize.height + 8 + 10
        }
        return height
    }
}

private final class HeaderView: GeneralRowView {
    private let titleView = TextView()
    private let infoView = InteractiveTextView()
    private let dismiss = ImageButton()
    private let actions = ImageButton()
    private let itemView = StarsHooks.shared.makeStickerView(NSMakeRect(0, 0, 100, 100))
    
    private let backgroundView = RadialGradientView(frame: .zero)
    
    private var upcomingView: TextView?
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(backgroundView)
        addSubview(titleView)
        addSubview(infoView)
        addSubview(itemView)
        
        addSubview(dismiss)
        addSubview(actions)
        
        dismiss.scaleOnClick = true
        dismiss.autohighlight = false
        dismiss.setAccessibilityLabel(strings().voiceOverCommonClose)
        
        dismiss.set(image: TelegramThemeHooks.shared.image(.iconPipClose).precomposed(.white), for: .Normal)
        dismiss.setGlassEffect(size: NSMakeSize(36, 36))
        dismiss.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        
        actions.scaleOnClick = true
        actions.autohighlight = false
        actions.setAccessibilityLabel(strings().voiceOverCommonMore)

        actions.set(image: TelegramThemeHooks.shared.image(.iconChatActionsActive).precomposed(.white), for: .Normal)
        actions.setGlassEffect(size: NSMakeSize(36, 36))
        actions.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)

        
        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        
        
        infoView.textView.isSelectable = false
        infoView.textView.userInteractionEnabled = true

        actions.contextMenu = { [weak self] in
            
            let item = self?.item as? HeaderItem
            
            let menu = ContextMenu()
            
            menu.addItem(
                ContextMenuItem(
                    strings().starAuctionContextMenuAbout,
                    handler: {
                        item?.arguments.about()
                    },
                    itemImage: MenuAnimation.menu_show_info.value
                )
            )

            
            menu.addItem(ContextMenuItem(strings().modalShare, handler: {
                item?.arguments.share()
            }, itemImage: MenuAnimation.menu_share.value))
            
            menu.addItem(ContextMenuItem(strings().modalCopyLink, handler: {
                item?.arguments.copyLink()
            }, itemImage: MenuAnimation.menu_copy_link.value))
            
            return menu
        }
    }
    
    public override func layout() {
        super.layout()
        
        backgroundView.frame = bounds
        
        dismiss.setFrameOrigin(NSMakePoint(10, 10))
        actions.setFrameOrigin(NSMakePoint(frame.width - actions.frame.width - 10, 10))

        itemView.centerX(y: 25)
        
        var y: CGFloat = itemView.frame.maxY + 10
        if let upcomingView {
            upcomingView.centerX(y: y)
            y += upcomingView.frame.height + 10
        }
        
        titleView.centerX(y: y)
        infoView.centerX(y: titleView.frame.maxY + 5)
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? HeaderItem else {
            return
        }
        
        
        (itemView as? StarsStickerView)?.updateStarsSticker(file: item.gift.generic!.file, size: itemView.frame.size, context: item.arguments.context, colors: [], playback: .standard, animated: animated)
        
        if let background = item.gift.generic?.background {
            backgroundView.colors = [NSColor(UInt32(background.centerColor)), NSColor(UInt32(background.edgeColor))]
        }
        
        if let upcomingLayout = item.upcomingLayout {
            let current: TextView
            if let view = self.upcomingView {
                current = view
            } else {
                current = TextView(frame: .zero)
                current.userInteractionEnabled = false
                current.isSelectable = false
                
                self.upcomingView = current
                self.addSubview(current)
            }
            current.update(upcomingLayout)
            current.setFrameSize(NSMakeSize(upcomingLayout.layoutSize.width + 14, upcomingLayout.layoutSize.height + 8))
            current.layer?.cornerRadius = current.frame.height / 2
            current.background = NSColor.black.withAlphaComponent(0.4)
        } else if let view = self.upcomingView {
            performSubviewRemoval(view, animated: animated)
            self.upcomingView = nil
        }
        
        titleView.update(item.titleLayout)
        infoView.set(text: item.infoLayout, context: item.context)

        needsLayout = true
    }
}

private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let about:()->Void
    public let share:()->Void
    public let copyLink:()->Void
    public let openAcquiredItems:()->Void
    public let openVariants:()->Void
    public let openLearn:()->Void
    public init(context: (any AccountContextProtocol), about:@escaping()->Void, share:@escaping()->Void, copyLink:@escaping()->Void, openAcquiredItems:@escaping()->Void, openVariants:@escaping()->Void, openLearn:@escaping()->Void) {
        self.context = context
        self.about = about
        self.share = share
        self.copyLink = copyLink
        self.openAcquiredItems = openAcquiredItems
        self.openVariants = openVariants
        self.openLearn = openLearn
    }
}

private struct State : Equatable {
    public var gift: StarGift
    public var auctionState: GiftAuctionContext.State?
    public var currentDate: Int32 = Int32(Date().timeIntervalSince1970)
    
    public var perks: (nextDropTimeout: Int32, minBid: Int64, currentRound: Int32, dropSize: Int32, dropsTotal: Int32, startDate: Int32, endDate: Int32, averagePrice: Int64, rounds: [GiftAuctionContext.State.Round])? {
        if let auctionState, let dropSize = gift.generic?.auctionGiftsPerRound {
            switch auctionState.auctionState {
            case let .ongoing(_, startDate, endDate, minBidAmount, _, _, nextDropDate, _, currentRound, dropsTotal, rounds, _):
                let dropTimeout = max(0, nextDropDate - currentDate)
                return (nextDropTimeout: dropTimeout, minBid: minBidAmount, currentRound: currentRound, dropSize: dropSize, dropsTotal: dropsTotal, startDate: startDate, endDate: endDate, averagePrice: 0, rounds: rounds)
            case let .finished(startDate, endDate, averagePrice, _, _, _):
                return (nextDropTimeout: 0, minBid: 0, currentRound: 0, dropSize: 0, dropsTotal: 0, startDate: startDate, endDate: endDate, averagePrice: averagePrice, rounds: [])
            }
        }
        return nil
    }
    public var isFinished: Bool {
        if case .finished = auctionState?.auctionState {
            return true
        } else {
            return false
        }
    }
}


private let _id_header = InputDataIdentifier("_id_header")

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return HeaderItem(initialSize, stableId: stableId, gift: state.gift, state: state, context: arguments.context, arguments: arguments)
    }))
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    
    guard let perks = state.perks else {
        return entries
    }
        
    var rows: [InputDataTableBasedItem.Row] = []
    
    
    rows.append(
        .init(
            left: .init(
                .initialize(
                    string: perks.startDate > state.currentDate ? strings().starAuctionPreviewStarts : strings().starAuctionPreviewStarted,
                    color: theme.colors.text,
                    font: .normal(.text)
                )
            ),
            right: .init(
                name: .init(
                    .initialize(
                        string: stringForFullDate(timestamp: perks.startDate),
                        color: theme.colors.text,
                        font: .normal(.text)
                    )
                )
            )
        )
    )

    rows.append(
        .init(
            left: .init(
                .initialize(
                    string: strings().starAuctionPreviewEnds,
                    color: theme.colors.text,
                    font: .normal(.text)
                )
            ),
            right: .init(
                name: .init(
                    .initialize(
                        string: stringForFullDate(timestamp: perks.endDate),
                        color: theme.colors.text,
                        font: .normal(.text)
                    )
                )
            )
        )
    )
    
    if perks.startDate > state.currentDate {
        rows.append(
            .init( left: .init(.initialize(string: strings().starAuctionPreviewQuantity, color: theme.colors.text, font: .normal(.text))), right: .init(name: .init(.initialize(string: (perks.dropsTotal * perks.dropSize).formattedWithSeparator, color: theme.colors.text, font: .normal(.text))))
            )
        )
        rows.append(
            .init( left: .init(.initialize(string: strings().starAuctionPreviewRounds, color: theme.colors.text, font: .normal(.text))), right: .init(name: .init(.initialize(string: (perks.dropsTotal).formattedWithSeparator, color: theme.colors.text, font: .normal(.text))))
            )
        )
        
        for (index, round) in perks.rounds.enumerated() {
            
            let from = round.num
            let to: Int32
            if index + 1 < perks.rounds.count {
                to = perks.rounds[index + 1].num - 1
            } else {
                to = perks.dropsTotal
            }
            
            let leftTitle: String
            if from == to {
                leftTitle = strings().starAuctionPreviewRoundSingle("\(from)")
            } else {
                leftTitle = strings().starAuctionPreviewRoundsRange("\(from)", "\(to)")
            }

            let rightTitle: String
            switch round {
            case let .generic(_, duration):
                let suffix = (from == to) ? "" : strings().starAuctionPreviewDurationEach("")
                rightTitle = "\(autoremoveLocalized(Int(duration)))\(suffix)"
            case let .extendable(_, duration, extendTop, extendWindow):
                rightTitle = "\(autoremoveLocalized(Int(duration))) + " +
                "\(autoremoveLocalized(Int(extendWindow))) for late bids in top \(extendTop)"
            }
            rows.append(
                .init( left: .init(.initialize(string: leftTitle, color: theme.colors.text, font: .normal(.text))), right: .init(name: .init(.initialize(string: rightTitle, color: theme.colors.text, font: .normal(.text))))
                )
            )
            
        }
    } else if !state.isFinished {
        rows.append(
            .init(
                left: .init(
                    .initialize(
                        string: strings().starAuctionPreviewCurrentRound,
                        color: theme.colors.text,
                        font: .normal(.text)
                    )
                ),
                right: .init(
                    name: .init(
                        .initialize(
                            string: strings().starAuctionPreviewOf("\(perks.currentRound)", "\(perks.dropsTotal)"),
                            color: theme.colors.text,
                            font: .normal(.text)
                        )
                    )
                )
            )
        )

        rows.append(
            .init(
                left: .init(
                    .initialize(
                        string: strings().starAuctionPreviewAvailability,
                        color: theme.colors.text,
                        font: .normal(.text)
                    )
                ),
                right: .init(
                    name: .init(
                        .initialize(
                            string: strings().starAuctionPreviewOf("\(perks.dropSize * (perks.dropsTotal - perks.currentRound))", "\(perks.dropSize * perks.dropsTotal)"),
                            color: theme.colors.text,
                            font: .normal(.text)
                        )
                    )
                )
            )
        )
    } else if let availability = state.gift.generic?.availability {

        rows.append(
            .init(
                left: .init(
                    .initialize(
                        string: strings().starAuctionPreviewAveragePrice,
                        color: theme.colors.text,
                        font: .normal(.text)
                    )
                ),
                right: .init(
                    name: .init(
                        .initialize(
                            string: "\(perks.averagePrice.formattedWithSeparator)",
                            color: theme.colors.text,
                            font: .normal(.text)
                        )
                    ),
                    leftView: { previous in
                        let imageView = previous as? ImageView ?? ImageView()
                        imageView.image = TelegramThemeHooks.shared.image(.iconStarCurrency).precomposed()
                        imageView.setFrameSize(18, 18)
                        imageView.contentGravity = .resizeAspectFill
                        return imageView
                    }
                )
            )
        )

        rows.append(
            .init(
                left: .init(
                    .initialize(
                        string: strings().starAuctionPreviewAvailability,
                        color: theme.colors.text,
                        font: .normal(.text)
                    )
                ),
                right: .init(
                    name: .init(
                        .initialize(
                            string: "\(availability.remains) \(strings().starAuctionPreviewOf) \(availability.total)",
                            color: theme.colors.text,
                            font: .normal(.text)
                        )
                    )
                )
            )
        )
    }

    



    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("_id_info"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return InputDataTableBasedItem(initialSize, stableId: stableId, viewType: .singleItem, rows: rows, context: arguments.context)
    }))
    index += 1
    
    
    if let gift = state.auctionState?.gift.generic, let acquired = state.auctionState?.myState.acquiredCount, acquired > 0 {
        let text = "[\(clown_space)\(strings().starAuctionItemsBoughtOther(Int(acquired))) >](acq)"

        let parsed = parseMarkdownIntoAttributedString(text, attributes: MarkdownAttributes.init(body: MarkdownAttributeSet(font: .normal(.text), textColor: theme.colors.accent), bold: MarkdownAttributeSet(font: .medium(.text), textColor: theme.colors.accent), link: MarkdownAttributeSet(font: .medium(.text), textColor: theme.colors.accent), linkAttribute: { link in
            return (NSAttributedString.Key.link.rawValue, LinkHooks.shared.callbackLink(link, { value in
                arguments.openAcquiredItems()
            }))
        })).mutableCopy() as! NSMutableAttributedString
        parsed.insertEmbedded(.embeddedAnimated(gift.file), for: clown)
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .attributed(parsed), data: .init(color: theme.colors.accent, detectBold: false, viewType: .singleItem, centerViewAlignment: true, alignment: .center, linkColor: theme.colors.accent, context: arguments.context, linkExecutor: TextViewInteractions(processURL: { value in
            arguments.openAcquiredItems()
        }))))
        index += 1
    } else if let gift = state.auctionState?.gift.generic, let variants = gift.upgradeVariantsCount {
        let text = "[\(strings().starAuctionPreviewViewVariants("\(clown_space)\(variants.formattedWithSeparator)"))](var)"

        let parsed = parseMarkdownIntoAttributedString(text, attributes: MarkdownAttributes.init(body: MarkdownAttributeSet(font: .normal(.text), textColor: theme.colors.accent), bold: MarkdownAttributeSet(font: .medium(.text), textColor: theme.colors.accent), link: MarkdownAttributeSet(font: .medium(.text), textColor: theme.colors.accent), linkAttribute: { link in
            return (NSAttributedString.Key.link.rawValue, LinkHooks.shared.callbackLink(link, { value in
                arguments.openVariants()
            }))
        })).mutableCopy() as! NSMutableAttributedString
        parsed.insertEmbedded(.embeddedAnimated(gift.file), for: clown)
        parsed.replaceChevron(color: theme.colors.accent)

        entries.append(.desc(sectionId: sectionId, index: index, text: .attributed(parsed), data: .init(color: theme.colors.accent, detectBold: false, viewType: .singleItem, centerViewAlignment: true, alignment: .center, linkColor: theme.colors.accent, context: arguments.context, linkExecutor: TextViewInteractions(processURL: { value in
            arguments.openVariants()
        }))))
        index += 1
    } else {
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    }
      
    
    return entries
}

public func Star_AuctionPreviewController(context: (any AccountContextProtocol), auctionContext: GiftAuctionContext, peerId: EnginePeer.Id, callback: @escaping()->Void) -> InputDataModalController {
    
    
    let actionsDisposable = DisposableSet()

    let initialState = State(gift: auctionContext.gift)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    let timer = SwiftSignalKit.Timer(timeout: 0.1, repeat: true, completion: {
        updateState { current in
            var current = current
            current.currentDate = context.timestamp
            return current
        }
    }, queue: .mainQueue())
    
    timer.start()
    
    actionsDisposable.add(auctionContext.state.startStrict(next: { auctionState in
        updateState { current in
            var current = current
            current.auctionState = auctionState
            return current
        }
    }))
    
    var getController:(()->ViewController?)? = nil
    var close:(()->Void)? = nil
    
    var window:Window {
        get {
            return getController?()?.window ?? context.window
        }
    }
    
    let link: String = context.meUrlPrefix + "auction/\(auctionContext.gift.generic?.auctionSlug ?? "")"

    let arguments = Arguments(context: context, about: {
        showModal(with: Star_AuctionInfoController(context: context, gift: initialState.gift.generic!, ok: {
            
        }), for: window)
    }, share: {
        StarsHooks.shared.shareLink(context, link, window)
    }, copyLink: {
        copyToClipboard(link)
        showModalText(for: window, text: strings().shareLinkCopied)
    }, openAcquiredItems: {
        let gift = stateValue.with { $0.auctionState?.gift.generic }
        if let gift {
            let signal = context.engine.payments.getGiftAuctionAcquiredGifts(giftId: gift.id) |> deliverOnMainQueue
            _ = showModalProgress(signal: signal, for: window).startStandalone(next: { gifts in
                showModal(with: Star_AuctionAcquiredController(context: context, gift: gift, gifts: gifts), for: window)
            })
        }
    }, openVariants: {
        let gift = stateValue.with { $0.auctionState?.gift }
        if let gift {
            showModal(with: StarGift_ModelBuilderController(context: context, gift: gift, giftId: gift.giftId), for: window)
        }
    }, openLearn: {
        showModal(with: StarGift_LearnAboutGifts(context: context), for: window)
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: "")
    controller.analyticsScreen = .giftsAuction
    
    controller.validateData = { _ in
        if stateValue.with({ !$0.isFinished }) {
            callback()
        }
        close?()
        return .none
    }
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().starAuctionPreviewJoin, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true)
    
    controller.afterTransaction = { [weak modalInteractions] controller in
        modalInteractions?.updateDone { f in
            let perks = stateValue.with { $0.perks }
            let gift = stateValue.with { $0.gift.generic }
            guard let perks, let gift else {
                return
            }
            let left = perks.endDate - context.timestamp
            if left > 0 {
                if let date = gift.auctionStartDate, date > context.timestamp {
                    f.set(text: strings().starAuctionPreviewPlaceEarlyBid, for: .Normal)
                    f.set(subtext: strings().starAuctionPreviewAuctionStartsIn(formatDHm(from: date - context.timestamp)), for: .Normal)
                } else {
                    f.set(text: strings().starAuctionPreviewJoin, for: .Normal)
                    f.set(subtext: strings().starAuctionPreviewLeft(formatDHm(from: left)), for: .Normal)
                }
            } else {
                f.set(text: strings().modalOK, for: .Normal)
                f.set(subtext: nil, for: .Normal)
            }
        }
    }
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    controller.contextObject = auctionContext
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    return modalController
    
}



