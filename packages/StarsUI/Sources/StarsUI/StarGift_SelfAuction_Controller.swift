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
import AppAnalytics


private final class HeaderItem : GeneralRowItem {
    
    
    
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let title: TextViewLayout
    fileprivate let info: TextViewLayout
    fileprivate let arguments:Arguments
    fileprivate let attributes: [StarGift.UniqueGift.Attribute]
    
    fileprivate var patterns:[(String, TelegramMediaFile)] = []
    fileprivate var backdrops:[(String, StarGift.UniqueGift.Attribute)] = []
    fileprivate var models:[(String, StarGift.UniqueGift.Attribute)] = []

    private var patternIndex: Int = 0
    private var backdropIndex: Int = 0
    private var modelIndex: Int = 0
    
    
    public let state: State
    
    
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: (any AccountContextProtocol), arguments: Arguments, state: State, attributes: [StarGift.UniqueGift.Attribute]) {
        self.arguments = arguments
        self.context = context
        self.attributes = attributes
        self.state = state
                
        self.patterns = attributes.compactMap { attribute in
            switch attribute {
            case let .pattern(name, file, _):
                return (name, file)
            default:
                return nil
            }
        }
        
        self.backdrops = attributes.compactMap { attribute in
            switch attribute {
            case let .backdrop(name, _, _, _, _, _, _):
                return (name, attribute)
            default:
                return nil
            }
        }
        
        self.models = attributes.compactMap { attribute in
            switch attribute {
            case let .model(name, _, _, _):
                return (name, attribute)
            default:
                return nil
            }
        }
        
        self.title = .init(.initialize(string: state.peer._asPeer().displayTitle, color: .white, font: .medium(18)))
        let infoAttr = NSMutableAttributedString()
        infoAttr.append(string: strings().starGiftSelfAuctionLearnMore, color: NSColor.white.withAlphaComponent(0.8), font: .normal(.text))
        infoAttr.replaceChevron(color: NSColor.white.withAlphaComponent(0.8))
        self.info = .init(infoAttr, alignment: .center)
        
       

        for (_, model) in models {
            switch model {
            case let .model(_, file, _, _):
                _ = freeMediaFileInteractiveFetched(context: context, fileReference: .standalone(media: file)).start()
            default:
                break
            }
        }
        
        if let pattern = state.selectedSymbol {
            patternIndex = patterns.firstIndex(where: { $0.1.fileId == pattern.file?.fileId }) ?? 0
        } else {
            patternIndex = 0
        }
        if let backdrop = state.selectedBackdrop {
            backdropIndex = backdrops.firstIndex(where: { $0.1 == backdrop }) ?? 0
        } else {
            backdropIndex = 0
        }
        if let model = state.selectedModel {
            modelIndex = models.firstIndex(where: { $0.1 == model }) ?? 0
        } else {
            modelIndex = 0
        }

    
        
        super.init(initialSize, stableId: stableId)
        
        makeNextPattern()
    }
    
    public func makeNextPattern() {
        
        
        let _ = self.makeSize(initialSize.width)
        
        self.redraw(animated: true)
    }
    
    public var model: TelegramMediaFile {
        switch self.models[self.modelIndex].1 {
        case let .model(_, file, _, _):
            return file
        default:
            fatalError()
        }
    }
    public var pattern: TelegramMediaFile {
        return self.patterns[self.patternIndex].1
    }
    
    public var patternColor: NSColor {
        let value = self.backdrops[self.backdropIndex].1
        switch value {
        case let .backdrop(_, _, _, _, patternColor, _, _):
            return NSColor(UInt32(bitPattern: patternColor))
        default:
            fatalError()
        }
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        self.title.measure(width: width - 40)
        self.info.measure(width: width - 40)
        
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
        
        return height
    }
    
    override var accessibilityLabel: String? {
        return title.attributedString.string
    }
    
    override var accessibilityValue: String? {
        let value = info.attributedString.string
        return value.isEmpty ? nil : value
    }
    
    public override func viewClass() -> AnyClass {
        return HeaderView.self
    }
    
    public var backgroundContent: UniqueGiftBackgroundContent? {
        switch self.backdrops[self.backdropIndex].1 {
        case let .backdrop(_, _, inner, outer, patternColor, _, _):
            return UniqueGiftBackgroundContent(colors: UniqueGiftColors(center: inner, edge: outer, pattern: patternColor), pattern: .file(self.pattern))
        default:
            return nil
        }
    }
}

private final class HeaderView : GeneralRowView {
    private let textView = TextView()
    private let infoView = InteractiveTextView()
    private let dismiss = ImageButton()
    private let avatarView = AvatarControl(font: .avatar(36))
    private let backgroundView = UniqueGiftBackgroundView(frame: .zero)
    private let modelView = StarsHooks.shared.makeStickerView(NSMakeRect(0, 0, 24, 24))
        
                
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(backgroundView)
        addSubview(avatarView)
        addSubview(textView)
        addSubview(infoView)
        addSubview(dismiss)
        addSubview(modelView)
        
        avatarView.setFrameSize(NSMakeSize(100, 100))
        
        infoView.textView.isSelectable = false

        textView.userInteractionEnabled = false
        textView.isSelectable = false
        avatarView.userInteractionEnabled = false
        
        infoView.setSingle(handler: { [weak self] _ in
            if let item = self?.item as? HeaderItem  {
                item.arguments.learnMore({ [weak self] in self?.infoView })
            }
        }, for: .Click)

    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? HeaderItem else {
            return
        }
        
      
        
        dismiss.set(image: TelegramThemeHooks.shared.image(.iconPipClose).precomposed(.white), for: .Normal)
        dismiss.setGlassEffect(size: NSMakeSize(36, 36))
        dismiss.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        dismiss.scaleOnClick = true
        dismiss.setAccessibilityLabel(strings().voiceOverCommonClose)
        
        dismiss.setSingle(handler: { [weak item] _ in
            item?.arguments.dismiss()
        }, for: .Click)
        
        self.updateBackground(animated: animated)

        self.avatarView.setPeer(account: item.arguments.context.account, peer: item.state.peer._asPeer())
        
        (modelView as? StarsStickerView)?.updateStarsSticker(file: item.model, size: modelView.frame.size, context: item.context, colors: [], playback: .standard, animated: animated)
        
        textView.update(item.title)
        infoView.set(text: item.info, context: item.context)
                
        
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate
        
        updateLayout(size: frame.size, transition: transition)
    }
    
    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        
        transition.updateFrame(view: backgroundView, frame: size.bounds)

        dismiss.setFrameOrigin(NSMakePoint(10, 10))

        avatarView.centerX(y: 30)
        updateBackground(animated: false)
        
        infoView.centerX(y: size.height - 20 - 15)

        textView.centerX(y: infoView.frame.minY - textView.frame.height - 5, addition: -12)
        modelView.setFrameOrigin(NSMakePoint(textView.frame.maxX + 5, textView.frame.minY - 1))
    }
    
    public override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }

    private func updateBackground(animated: Bool) {
        guard let item = item as? HeaderItem, let content = item.backgroundContent else {
            backgroundView.isHidden = true
            return
        }
        backgroundView.isHidden = false
        backgroundView.update(context: item.context, content: content, style: .header(patternCenterY: avatarView.frame.midY + 16), animated: animated)
    }
}

private final class GiftsRowItem : GeneralRowItem {
    fileprivate let arguments: Arguments
    fileprivate let state: State
    fileprivate let from : GiftOptionsRowItem.Option
    fileprivate let to: GiftOptionsRowItem.Option
    public init(_ initialSize: NSSize, stableId: AnyHashable, state: State, arguments: Arguments)  {
        self.state = state
        self.arguments = arguments
        self.from = .initialize(PeerStarGift(media: state.gift.generic!.file, stars: 0, limited: true, native: state.gift), preview: true, customText: strings().starGiftSelfAuctionLimited)

        self.to = .initialize(PeerStarGift(media: state.unique.file!, stars: 0, limited: true, native: .unique(state.unique)), preview: true, customText: strings().starGiftSelfAuctionUpgraded)

        super.init(initialSize, height: 125, stableId: stableId)
    }
    
    override var accessibilityLabel: String? {
        return state.unique.title
    }
    
    public override func viewClass() -> AnyClass {
        return GiftsRowView.self
    }
}

private final class GiftsRowView: GeneralRowView {
    private let fromView: GiftOptionsRowView.OptionView = .init(frame: NSMakeRect(0, 0, 125, 125))
    private let toView: GiftOptionsRowView.OptionView = .init(frame: NSMakeRect(0, 0, 125, 125))
    private let arrowView = ImageView()
    private let infoView = TextView()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(fromView)
        addSubview(toView)
        addSubview(arrowView)
        addSubview(infoView)
        
        arrowView.isAccessibilityDecorative = true
        infoView.userInteractionEnabled = false
        infoView.isSelectable = false
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var backdorColor: NSColor {
        return theme.colors.listBackground
    }
    
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? GiftsRowItem else {
            return
        }
        
        let layout = TextViewLayout(.initialize(string: "Free\nUpgrade", color: theme.colors.listGrayText, font: .normal(.small)), alignment: .center)
        layout.measure(width: .greatestFiniteMagnitude)
        
        infoView.update(layout)
        
        arrowView.image = TelegramThemeHooks.shared.image(.iconAuctionPreviewArrow).precomposed(theme.colors.grayIcon)
        arrowView.sizeToFit()
        
        fromView.set(option: item.from, context: item.arguments.context, selected: false, animated: animated, callback: { _, _ in })
        toView.set(option: item.to, context: item.arguments.context, selected: false, animated: animated, callback: { _, _ in })
    }
    
    public override func layout() {
        super.layout()
        fromView.centerY(x: 20)
        toView.centerY(x: frame.width - toView.frame.width - 20)
        arrowView.center()
        arrowView.setFrameOrigin(NSMakePoint(arrowView.frame.minX, arrowView.frame.minY - infoView.frame.height / 2 - 5))
        infoView.centerX(y: arrowView.frame.maxY + 10)

    }
}


private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let dismiss:()->Void
    public let makeNextPattern:()->Void
    public let showAuctionInfo:(StarGift.Gift)->Void
    public let learnMore:((() -> NSView?)?)->Void
    public init(context: (any AccountContextProtocol), dismiss:@escaping()->Void, makeNextPattern:@escaping()->Void, showAuctionInfo:@escaping(StarGift.Gift)->Void, learnMore:@escaping((() -> NSView?)?)->Void) {
        self.dismiss = dismiss
        self.makeNextPattern = makeNextPattern
        self.context = context
        self.showAuctionInfo = showAuctionInfo
        self.learnMore = learnMore
    }
}

private struct State : Equatable {
    public var gift: StarGift
    public var peer: EnginePeer
    public var attributes: [StarGift.UniqueGift.Attribute]
    public var auctionState: GiftAuctionContext.State?
    
    public var timestamp: Int32

    public var unique: StarGift.UniqueGift {
        let attributes = [selectedModel, selectedBackdrop, selectedSymbol].compactMap({ $0 })
        return .init(id: 0, giftId: gift.giftId, title: gift.title, number:0, slug: "", owner: .name(""), attributes: attributes, availability: .init(issued: 0, total: 0), giftAddress: nil, resellAmounts: nil, resellForTonOnly: false, releasedBy: nil, valueAmount: nil, valueCurrency: nil, valueUsdAmount: nil, flags: [], themePeerId: nil, peerColor: nil, hostPeerId: nil, minOfferStars: nil, craftChancePermille: nil)
    }
    
    public var selectedModel: StarGift.UniqueGift.Attribute?
    public var selectedBackdrop: StarGift.UniqueGift.Attribute?
    public var selectedSymbol: StarGift.UniqueGift.Attribute?

    
    public var randomBackdrop: StarGift.UniqueGift.Attribute? {
        return self.attributes.filter({ $0.attributeType == .backdrop }).randomElement()
    }
    public var randomModel: StarGift.UniqueGift.Attribute? {
        return self.attributes.filter({ $0.attributeType == .model }).randomElement()
    }
    public var randomSymbol: StarGift.UniqueGift.Attribute? {
        return self.attributes.filter({ $0.attributeType == .pattern }).randomElement()
    }
    
    public var okText: String {
        if let date = gift.generic?.auctionStartDate, date > timestamp {
            return strings().starAuctionPlaceEarlyBid
        } else {
            return strings().starAuctionPlaceBid
        }
    }
    public var subtext: String? {
        if let date = gift.generic?.auctionStartDate, date > timestamp {
            return nil
        } else {
            if let endDate = auctionState?.endDate {
                return strings().starAuctionPreviewLeft(timerText(Int(endDate - timestamp)))
            } else {
                return nil
            }
        }
    }
}


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("header"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return HeaderItem(initialSize, stableId: stableId, context: arguments.context, arguments: arguments, state: state, attributes: state.attributes)
    }))
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("gifts"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return GiftsRowItem(initialSize, stableId: stableId, state: state, arguments: arguments)
    }))

  
    // entries
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
    
    
    if let gift = state.gift.generic, let auctionState = state.auctionState, let dropSize = gift.auctionGiftsPerRound {
        switch auctionState.auctionState {
        case let .ongoing(_, _, _, _, _, _, _, giftsLeft, _, dropsTotal, _, _):
            entries.append(.sectionId(sectionId, type: .customModern(20)))
            sectionId += 1
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("limit"), equatable: .init(auctionState), comparable: nil, item: { initialSize, stableId in
                return AuctionLimitRowItem(initialSize, stableId: stableId, availability: .init(remains: giftsLeft, total: dropSize * dropsTotal, resale: 0, minResaleStars: nil))
            }))
            let droppedAttr = parseMarkdownIntoAttributedString(
                strings().starAuctionPreviewGiftsDroppedInfoOther(
                    Int(giftsLeft),
                    strings().starAuctionPreviewTopBiddersOther(Int(dropSize))
                ) + " [\(strings().starAuctionPreviewSendLearnMore)]()",
                attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: .normal(11.5), textColor: theme.colors.listGrayText), bold: MarkdownAttributeSet(font: .bold(11.5), textColor: theme.colors.listGrayText), link: MarkdownAttributeSet(font: .normal(11.5), textColor: theme.colors.link), linkAttribute: { link in
                    return (NSAttributedString.Key.link.rawValue, LinkHooks.shared.callbackLink(link, { _ in
                        arguments.showAuctionInfo(gift)
                    }))
                })).mutableCopy() as! NSMutableAttributedString
            droppedAttr.replaceChevron(color: theme.colors.link)
            entries.append(
                .desc(
                    sectionId: sectionId,
                    index: index,
                    text: .attributed(droppedAttr),
                    data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem, context: arguments.context)
                )
            )
            index += 1
        default:
            break
            
        }
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        
    }
    
    return entries
}

public func StarGift_SelfAuction_Controller(context: (any AccountContextProtocol), gift: StarGift, attributes: [StarGift.UniqueGift.Attribute], giftAuctionContext: GiftAuctionContext) -> InputDataModalController {
        

    let actionsDisposable = DisposableSet()

    var initialState = State(gift: gift, peer: .init(context.myPeer!), attributes: attributes, timestamp: context.timestamp)
    
    initialState.selectedModel = initialState.randomModel
    initialState.selectedSymbol = initialState.randomSymbol
    initialState.selectedBackdrop = initialState.randomBackdrop

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    actionsDisposable.add(giftAuctionContext.state.start(next: { state in
        updateState { current in
            var current = current
            current.auctionState = state
            return current
        }
    }))
    
    let timer = SwiftSignalKit.Timer(timeout: 0.1, repeat: true, completion: {
        updateState { current in
            var current = current
            current.timestamp = context.timestamp
            return current
        }
    }, queue: .mainQueue())
    
    timer.start()
    
 
    
    var getController:(()->ViewController?)? = nil
    var close:(()->Void)? = nil
    
    var window:Window {
        get {
            return getController?()?.window ?? context.window
        }
    }

    let arguments = Arguments(context: context, dismiss: {
        close?()
    }, makeNextPattern: {
        updateState { current in
            var current = current
            
            current.selectedModel = current.randomModel
            current.selectedBackdrop = current.randomBackdrop
            current.selectedSymbol = current.randomSymbol

            return current
        }
    }, showAuctionInfo: { gift in
        showModal(with: Star_AuctionInfoController(context: context, gift: gift), for: window)
    }, learnMore: { morphSource in
        showModal(with: StarGift_LearnAboutGifts(context: context), for: window, morphSource: morphSource)
    })
    
    let nextTimer = SwiftSignalKit.Timer(timeout: 2.5, repeat: true, completion: { [weak arguments] in
        arguments?.makeNextPattern()
    }, queue: .mainQueue())
    
    nextTimer.start()
    
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: "")
    controller.analyticsScreen = .giftsAuctionSelfBid
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    controller.validateData = { _ in
        if let gift = gift.generic {
            showModal(with: Star_AuctionBidController(context: context, peerId: context.peerId, gift: gift, auctionContext: giftAuctionContext), for: window)
        }
        return .none
    }

    let modalInteractions = ModalInteractions(acceptTitle: initialState.okText, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true)
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(360, 360))
    
    modalController._hasBorder = false
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    controller.afterTransaction = { [weak modalInteractions] controller in
        modalInteractions?.updateDone { f in
            f.set(text: stateValue.with { $0.okText }, for: .Normal)
            f.set(subtext: stateValue.with { $0.subtext }, for: .Normal)
        }
    }
    
    controller.contextObject = (timer, nextTimer)
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    return modalController
    
}




