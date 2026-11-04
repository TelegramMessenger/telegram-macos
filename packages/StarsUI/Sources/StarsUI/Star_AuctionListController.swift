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


private final class RowItem : GeneralRowItem {
    fileprivate let value: State.Active
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let gift: StarGift.Gift
    
    fileprivate let titleLayout: TextViewLayout
    fileprivate let infoLayout: TextViewLayout
    
    fileprivate let nextDropTimeout: Int32
    public let open: (StarGift.Gift)->Void
    
    public init(_ initialSize: NSSize, stableId: AnyHashable, value: State.Active, totalRounds: Int32, date: Int32, gift: StarGift.Gift, context: (any AccountContextProtocol), viewType: GeneralViewType, open: @escaping(StarGift.Gift)->Void) {
        self.value = value
        self.context = context
        self.gift = gift
        self.open = open
        self.nextDropTimeout = value.date - date
        
        titleLayout = .init(
            .initialize(
                string: strings().starAuctionActiveListRoundOf(Int(value.round), Int(totalRounds)),
                color: theme.colors.text,
                font: .medium(.title)
            )
        )

        let infoAttr = NSMutableAttributedString()
        if value.acceptedBid.outbid {
            infoAttr.append(
                string: strings().starAuctionActiveListOutbid(clown_space  + value.acceptedBid.amount.formattedWithSeparator),
                color: theme.colors.redUI,
                font: .normal(.text)
            )
        } else {
            infoAttr.append(
                string: strings().starAuctionActiveListRanked(clown_space  + value.acceptedBid.amount.formattedWithSeparator, Int(value.acceptedBid.place)),
                color: theme.colors.text,
                font: .normal(.text)
            )
        }

        infoAttr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.star_currency_new.file), for: clown)
        infoAttr.detectBoldColorInString(with: .medium(.text))
        self.infoLayout = .init(infoAttr)
        
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        titleLayout.measure(width: width - 50 - viewType.innerInset.left - viewType.innerInset.right)
        infoLayout.measure(width: width - 50 - viewType.innerInset.left - viewType.innerInset.right)

        return true
    }
    
    public override var height: CGFloat {
        return 10 + 40 + 5 + 40 + 10
    }
    
    override var accessibilityLabel: String? {
        return gift.title ?? titleLayout.attributedString.string
    }
    
    override var accessibilityValue: String? {
        let info = infoLayout.attributedString.string.replacingOccurrences(of: clown, with: "")
        return [titleLayout.attributedString.string, info].joined(separator: ", ")
    }
    
    public override func viewClass() -> AnyClass {
        return RowView.self
    }
}

private final class RowView : GeneralContainableRowView {
    
    
    private final class AcceptView : Control {
        private let textView = InteractiveTextView()
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(textView)
            layer?.cornerRadius = 20
            scaleOnClick = true
            self.set(background: theme.colors.accent, for: .Normal)
            
            textView.userInteractionEnabled = false
        }
        
        public func update(_ item: RowItem, animated: Bool) {
            let attr = NSMutableAttributedString()
            attr.append(
                string: "\(clown_space)\(strings().starAuctionActiveListRaiseBid)",
                color: theme.colors.underSelectedColor,
                font: .medium(.text)
            )
            attr.append(string: " ")
            
            
            attr.append(string: "\(timerText(Int(item.nextDropTimeout)))", color: theme.colors.underSelectedColor.withAlphaComponent(0.8), font: .normalMonospaced(.text))
            attr.insertEmbedded(.embedded(name: "Icon_Bid_Inline", color: theme.colors.underSelectedColor, resize: false), for: clown)
            
            let layout = TextViewLayout(attr)
            layout.measure(width: item.width - 60)
            
            textView.set(text: layout, context: item.context)
            setAccessibilityLabel(strings().starAuctionActiveListRaiseBid)
            setAccessibilityValue(timerText(Int(item.nextDropTimeout)))
            
            needsLayout = true
        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public override func layout() {
            super.layout()
            textView.center()
        }
    }
    
    private let titleView = TextView()
    private let infoView = InteractiveTextView()
    private let giftView = StarsHooks.shared.makeStickerView(NSMakeRect(0, 0, 30, 30))
    private let button = AcceptView(frame: .zero)
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(titleView)
        addSubview(infoView)
        addSubview(giftView)
        addSubview(button)
        
        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        
        button.scaleOnClick = true
        
        button.setSingle(handler: { [weak self] _ in
            if let item = self?.item as? RowItem {
                item.open(item.gift)
            }
        }, for: .Click)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        
        guard let item = item as? RowItem else {
            return
        }
        
        giftView.frame.origin = NSMakePoint(item.viewType.innerInset.left, item.viewType.innerInset.top)
        titleView.frame.origin = NSMakePoint(giftView.frame.maxX + 10, item.viewType.innerInset.top)
        infoView.frame.origin = NSMakePoint(giftView.frame.maxX + 10, titleView.frame.maxY + 2)
        
        button.frame = NSMakeRect(item.viewType.innerInset.left, frame.height - 40 - item.viewType.innerInset.bottom, containerView.frame.width - item.viewType.innerInset.left - item.viewType.innerInset.right, 40)
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? RowItem else {
            return
        }
        
        titleView.update(item.titleLayout)
        infoView.set(text: item.infoLayout, context: item.context)
        (giftView as? StarsStickerView)?.updateStarsSticker(file: item.gift.file, size: NSMakeSize(30, 30), context: item.context, colors: [], playback: .standard, animated: animated)
        
        button.update(item, animated: animated)
        
        needsLayout = true
    }
}

private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let openPeer:(EnginePeer.Id)->Void
    public let openAuction:(StarGift.Gift)->Void
    public init(context: (any AccountContextProtocol), openPeer:@escaping(EnginePeer.Id)->Void, openAuction:@escaping(StarGift.Gift)->Void) {
        self.context = context
        self.openPeer = openPeer
        self.openAuction = openAuction
    }
}

private struct State : Equatable {
    public struct Active: Equatable {
        public struct Bid : Equatable {
            public var amount: Int64
            public var place: Int32
            public var outbid: Bool
            public init(amount: Int64, place: Int32, outbid: Bool) {
                self.amount = amount
                self.place = place
                self.outbid = outbid
            }
        }
        public var gift: StarGift.Gift
        public var round: Int32
        public var date: Int32
        public var acceptedBid: Bid
        public var totalRounds: Int32

        public init(gift: StarGift.Gift, round: Int32, date: Int32, acceptedBid: Bid, totalRounds: Int32) {
            self.gift = gift
            self.round = round
            self.date = date
            self.acceptedBid = acceptedBid
            self.totalRounds = totalRounds
        }
    }
    public var list: [Active] = []
    
    public var currentDate: Int32 = Int32(Date().timeIntervalSince1970)
}


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
  
    // entries
    
    for item in state.list {
        if item.date > arguments.context.timestamp {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("_id_\(item.gift.id)"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
                return RowItem(initialSize, stableId: stableId, value: item, totalRounds: item.totalRounds, date: state.currentDate, gift: item.gift, context: arguments.context, viewType: .singleItem, open: arguments.openAuction)
            }))
            index += 1
            
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1
        }
        
    }
    
    
    return entries
}

public func Star_AuctionListController(context: (any AccountContextProtocol), activeState: [GiftAuctionContext.State]) -> InputDataModalController {
    
    
    let actionsDisposable = DisposableSet()
    
    var close:(()->Void)? = nil

    let initialState = State(list: activeState.compactMap { value in
        switch value.auctionState {
        case let .ongoing(_, _, _, _, _, _, nextRoundDate, _, currentRound, totalRounds, _, _):
            return .init(gift: value.gift.generic!, round: currentRound, date: nextRoundDate, acceptedBid: .init(amount: value.myState.bidAmount ?? 0, place: value.place ?? 0, outbid: (value.place ?? 0) > value.gift.generic!.auctionGiftsPerRound ?? 0), totalRounds: totalRounds)
        default:
            return nil
        }
    })
    
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
    
    var getController:(()->ViewController?)? = nil
    
    var window:Window {
        get {
            return getController?()?.window ?? context.window
        }
    }

    let arguments = Arguments(context: context, openPeer: { peerId in
        closeAllModals(window: window)
        StarsHooks.shared.openPeerInfo(context, peerId)
    }, openAuction: { gift in
        
        guard let value = activeState.first(where: { $0.gift.id == gift.id }) else {
            return
        }
        
        let peerId = value.myState.bidPeerId ?? context.peerId
        
        _ = showModalProgress(signal: context.giftAuctionsManager.auctionContext(for: .giftId(value.gift.id)), for: context.window).startStandalone(next: { auctionContext in
            if let auctionContext {
                showModal(with: Star_AuctionBidController(context: context, peerId: peerId, gift: gift, auctionContext: auctionContext, hideName: true, text: "", entities: []), for: context.window)
            } else {
                showModalText(for: context.window, text: strings().auctionErrorNotExists)
            }
        })
        
        close?()
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(
        dataSignal: signal,
        title: strings().starAuctionListActiveAuctionsOther(activeState.count)
    )

    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    let modalController = InputDataModalController(controller, modalInteractions: nil)
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    controller.afterTransaction = { [weak modalController] controller in
        var contains = false
        controller.tableView.enumerateItems(with: { item in
            if item is RowItem {
                contains = true
                return false
            }
            return true
        })
        
        if !contains {
            modalController?.close()
        }
    }
    
    controller.validateData = { [weak modalController] _ in
        modalController?.close()
        return .none
    }
    
    close = { [weak modalController] in
        modalController?.close()
    }
    
    controller.contextObject = timer

    return modalController
    
}
