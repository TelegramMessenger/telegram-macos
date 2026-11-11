import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import AlertsUI
import InAppSettings
import AvatarUI
import LocalAnimations
import TelegramMedia
import PremiumUI
import SceneEffects
import AppAnalytics


private final class LevelRowItem : GeneralRowItem {
    fileprivate let rating: TelegramStarRating
    fileprivate let peer: EnginePeer
    fileprivate let context: any AccountContextProtocol
    fileprivate let progress: CGFloat
    public init(_ initialSize: NSSize, stableId: AnyHashable, rating: TelegramStarRating, peer: EnginePeer, context: any AccountContextProtocol) {
        self.rating = rating
        self.peer = peer
        self.context = context
        var progress: CGFloat
        if rating.stars < 0 {
            progress = 0.5
        } else if let nextLevelStars = rating.nextLevelStars {
            progress = CGFloat(rating.stars - rating.currentLevelStars) / CGFloat(nextLevelStars - rating.currentLevelStars)
        } else {
            progress = 1.0
        }
        self.progress = max(0, progress)
        super.init(initialSize, height: 30 + 48, stableId: stableId)
    }
    
    public override func viewClass() -> AnyClass {
        return LevelRowView.self
    }
    
    public override var accessibilityLabel: String? {
        if rating.level < 0 {
            return strings().peerRatingPreviewNegative
        }
        return strings().peerRatingPreviewLevel(Int(rating.level))
    }
    
    public override var accessibilityValue: String? {
        if let nextLevelStars = rating.nextLevelStars {
            return "\(rating.stars.prettyNumber) / \(nextLevelStars.prettyNumber)"
        }
        return rating.stars.prettyNumber
    }
    
    public override var accessibilityRole: NSAccessibility.Role? {
        return .staticText
    }
    
    public override var accessibilityIncludesChildren: Bool {
        return false
    }
}

private final class LevelRowView : GeneralRowView {
    
    
    private final class BadgeView : View {
        private let shapeLayer = SimpleLayer()
        private let bodyLayer = SimpleShapeLayer()
        private let tailLayer = SimpleShapeLayer()
        private let foregroundLayer = SimpleGradientLayer()
        private let textView = InteractiveTextView()
        private let container = View()
        private let crownView = ImageView()

        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)

            textView.userInteractionEnabled = false

            foregroundLayer.colors = [theme.colors.accent, theme.colors.accent].map { $0.cgColor }
            foregroundLayer.startPoint = NSMakePoint(0, 0.5)
            foregroundLayer.endPoint = NSMakePoint(1, 0.2)
            foregroundLayer.mask = shapeLayer


            self.layer?.masksToBounds = false
            self.foregroundLayer.masksToBounds = false


            self.layer?.addSublayer(foregroundLayer)


            self.layer?.masksToBounds = false

            bodyLayer.fillColor = NSColor.red.cgColor
            tailLayer.fillColor = NSColor.red.cgColor
            shapeLayer.addSublayer(bodyLayer)
            shapeLayer.addSublayer(tailLayer)
            shapeLayer.transform = CATransform3DMakeScale(1.0, -1.0, 1.0)



            container.addSubview(textView)
            container.addSubview(crownView)
            crownView.isAccessibilityDecorative = true
            addSubview(container)
            container.layer?.masksToBounds = false
        }
        
        public func update(realValue: Int64, nextValue: Int64?, showMinus: Bool) -> NSSize {
            
            
            if realValue > 0 {
                foregroundLayer.colors = [theme.colors.accent, theme.colors.accent].map { $0.cgColor }
            } else {
                foregroundLayer.colors = [theme.colors.redUI, theme.colors.redUI].map { $0.cgColor }
            }
            
            
            let attr = NSMutableAttributedString()
            if realValue > 0 || showMinus {
                attr.append(string: "\(realValue.prettyNumber)", color: theme.colors.underSelectedColor, font: .medium(16))
            }
            
            if let nextValue {
                attr.append(string: " / \(nextValue.prettyNumber)", color: theme.colors.underSelectedColor.withAlphaComponent(0.6), font: .normal(14))
            }
            let textLayout = TextViewLayout(attr)
            textLayout.measure(width: .greatestFiniteMagnitude)
            self.textView.set(text: textLayout, context: nil)

            crownView.image = TelegramThemeHooks.shared.image(realValue >= 0 ? .iconRatingCrown : .iconRatingAlert).precomposed(theme.colors.underSelectedColor)
            crownView.sizeToFit()

            
            container.setFrameSize(NSMakeSize(container.subviewsWidthSize.width + 2, container.subviewsWidthSize.height))

            let size = NSMakeSize(container.frame.width + 30, frame.height)


            foregroundLayer.frame = size.bounds.insetBy(dx: 0, dy: -10)
            shapeLayer.frame = foregroundLayer.frame.focus(size)
            bodyLayer.frame = size.bounds
            bodyLayer.path = generateRoundedRectWithTailPath(rectSize: size, tailPosition: nil)


            return size

        }

        public func updateTail(offset: CGFloat) {
            let size = shapeLayer.bounds.size
            let tailShapeWidth = min(size.width, size.height + 28)
            let tailShapeX = max(0, min(size.width - tailShapeWidth, offset - tailShapeWidth / 2))
            let tailPosition = max(0, min(1, (offset - tailShapeX) / tailShapeWidth))
            tailLayer.frame = NSMakeRect(tailShapeX, 0, tailShapeWidth, size.height)
            tailLayer.path = generateRoundedRectWithTailPath(rectSize: tailLayer.frame.size, tailPosition: tailPosition)
        }
        
        public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
            transition.updateFrame(view: container, frame: container.centerFrameX(y: 1))

            transition.updateFrame(view: crownView, frame: NSMakeRect(0, -8, crownView.frame.width, crownView.frame.height))
            transition.updateFrame(view: textView, frame: NSMakeRect(crownView.frame.maxX + 4, -3, textView.frame.width, textView.frame.height))


        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public override func layout() {
            super.layout()
            self.updateLayout(size: self.frame.size, transition: .immediate)
        }
    }

    private class LineView : View {
        private var rating: TelegramStarRating?
        private var progress: CGFloat = 0
        private let limitedView = TextView()
        private let totalView = TextView()
        
        private let limitColorMask = SimpleLayer()
        private let totalColorMask = SimpleLayer()
        
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            self.layer?.cornerRadius = 10
            addSubview(limitedView)
            addSubview(totalView)
            
            self.layer?.addSublayer(self.limitColorMask)
            self.layer?.addSublayer(self.totalColorMask)
            
            limitedView.userInteractionEnabled = false
            limitedView.isSelectable = false
            
            totalView.userInteractionEnabled = false
            totalView.isSelectable = false
        }
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public override func draw(_ layer: CALayer, in ctx: CGContext) {
            super.draw(layer, in: ctx)
            
            guard let rating else {
                return
            }
            
            ctx.setFillColor(theme.colors.grayForeground.cgColor)
            ctx.fill(bounds)



            if rating.level == -1 {
                ctx.setFillColor(theme.colors.redUI.cgColor)
                ctx.fill(NSMakeRect(bounds.width * progress, 0, bounds.width * progress, bounds.height))
            } else {
                ctx.setFillColor(theme.colors.accent.cgColor)
                ctx.fill(NSMakeRect(0, 0, bounds.width * progress, bounds.height))
            }
            
        }
        
        public func set(rating: TelegramStarRating, progress: CGFloat) {
            self.rating = rating
            self.progress = progress
            needsDisplay = true
            
            
            
            
            let limitedLayout = TextViewLayout(
                .initialize(
                    string: strings().peerRatingPreviewLevel(Int(rating.level)),
                    color: .white,
                    font: .medium(.text)
                )
            )
            limitedLayout.measure(width: .greatestFiniteMagnitude)
            self.limitedView.update(limitedLayout)
            

            
            let w = frame.width * progress

            limitColorMask.contents = generateImage(limitedLayout.layoutSize, contextGenerator: { size, ctx in
                let width = w - 10
                ctx.setFillColor(theme.colors.underSelectedColor.cgColor)
                ctx.fill(NSMakeRect(0, 0, width, size.height))
                
                ctx.setFillColor(theme.colors.grayIcon.cgColor)
                ctx.fill(NSMakeRect(width, 0, size.width - width, size.height))
            })
            
            limitColorMask.mask = self.limitedView.drawingLayer
            
            let nextLevel: String

            if let _ = rating.nextLevelStars {
                nextLevel = strings().peerRatingPreviewNextLevel(Int(rating.level) + 1)
            } else if rating.level == -1 {
                nextLevel = strings().peerRatingPreviewNegative
            } else {
                nextLevel = ""
            }
                        
            let totalLayout = TextViewLayout(.initialize(string: nextLevel, color: .white, font: .medium(.text)))
            totalLayout.measure(width: .greatestFiniteMagnitude)
            self.totalView.update(totalLayout)
            
            totalColorMask.contents = generateImage(totalLayout.layoutSize, contextGenerator: { size, ctx in
                let minx = frame.width - 10 - size.width
                
                let width = max(0, w - minx)
                ctx.setFillColor(theme.colors.underSelectedColor.cgColor)
                ctx.fill(NSMakeRect(0, 0, rating.level == -1 ? size.width : width, size.height))
                
                if rating.level != -1 {
                    ctx.setFillColor(theme.colors.grayIcon.cgColor)
                    ctx.fill(NSMakeRect(width, 0, size.width - width, size.height))
                }
                
            })
            
            totalColorMask.mask = self.totalView.drawingLayer
            
            
            self.limitedView.drawingLayer.isHidden = rating.level == -1

            

        }
        
        public override func layout() {
            super.layout()
            limitedView.centerY(x: 10)
            limitColorMask.frame = limitedView.frame
            self.totalView.centerY(x: frame.width - totalView.frame.width - 10)
            self.totalColorMask.frame = totalView.frame
        }
    }
    
    private let lineView = LineView(frame: .zero)
    private let badgeView = BadgeView(frame: NSMakeSize(100, 30).bounds)
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(lineView)
        addSubview(badgeView)
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? LevelRowItem else {
            return
        }
        
        let rating = item.rating

        lineView.frame = NSMakeRect(20, frame.height - 30, frame.width - 40, 30)

        lineView.set(rating: item.rating, progress: item.progress)
        let size = badgeView.update(realValue: rating.stars, nextValue: rating.nextLevelStars, showMinus: item.context.peerId == item.peer.id)
        badgeView.setFrameSize(size)
        
        needsLayout = true
    }
    
    public override func layout() {
        super.layout()
        
        guard let item = item as? LevelRowItem else {
            return
        }
        
        let barWidth = frame.width - 40
        let fillX = 20 + floorToScreenPixels(item.progress * barWidth)
        let badgeWidth = badgeView.frame.width
        let badgeX = max(20, min(20 + barWidth - badgeWidth, floorToScreenPixels(fillX - badgeWidth / 2)))

        badgeView.updateTail(offset: fillX - badgeX)
        badgeView.setFrameOrigin(NSMakePoint(badgeX, 10))

        lineView.frame = NSMakeRect(20, frame.height - 30, frame.width - 40, 30)
        
    }
    
}



private final class RowItem : GeneralRowItem {
    
    public let context: any AccountContextProtocol
    public let headerLayout: TextViewLayout
    
    public let options: [OptionsListView.Option]

    public init(_ initialSize: NSSize, stableId: AnyHashable, rating: TelegramStarRating, peer: EnginePeer, context: any AccountContextProtocol) {
        self.context = context
        
        let text: String
        if rating.level == -1 {
            if peer.id != context.peerId {
                text = strings().peerRatingNegativeOther(peer._asPeer().displayTitle)
            } else {
                text = strings().peerRatingNegativeSelf(
                    strings().starListItemCountOther(Int(abs(rating.stars)))
                )
            }
        } else {
            text = peer.id == context.peerId ? strings().peerRatingPreviewInfoHeaderYou : strings().peerRatingPreviewInfoHeader(peer._asPeer().compactDisplayTitle)
        }
        
        let headerText = NSAttributedString.initialize(
            string: text,
            color: rating.level == -1 ? theme.colors.redUI : theme.colors.text,
            font: .normal(rating.level == -1 ? .text : .title)
        ).detectBold(with: .medium(rating.level == -1 ? .text : .title))
        
        
                                                                                    
        self.headerLayout = .init(headerText, alignment: .center)
        self.headerLayout.measure(width: initialSize.width - 40)
                
        var options:[OptionsListView.Option] = []
        
        
        let infoImage_1 = generateTextIcon_AccentBadge(
            text: strings().peerRatingPreviewBadgeAdded,
            bgColor: theme.colors.accent,
            textColor: theme.colors.underSelectedColor
        )

        let infoImage_2 = generateTextIcon_AccentBadge(
            text: strings().peerRatingPreviewBadgeAdded,
            bgColor: theme.colors.accent,
            textColor: theme.colors.underSelectedColor
        )

        let infoImage_3 = generateTextIcon_AccentBadge(
            text: strings().peerRatingPreviewBadgeDeducted,
            bgColor: theme.colors.darkGrayText.withAlphaComponent(0.65),
            textColor: theme.colors.underSelectedColor
        )

        options.append(.init(
            image: TelegramThemeHooks.shared.image(.iconChannelGift).precomposed(theme.colors.accent),
            header: .init(.initialize(
                string: strings().peerRatingPreviewTelegramHeader,
                color: theme.colors.text,
                font: .medium(.text)
            )),
            text: .init(.initialize(
                string: strings().peerRatingPreviewTelegramText("100%"),
                color: theme.colors.grayText,
                font: .normal(.text)
            ), cutout: .init(topLeft: NSMakeSize(infoImage_1.backingSize.width + 5, 20))),
            width: initialSize.width - 40,
            infoImage: infoImage_1
        ))

        options.append(.init(
            image: TelegramThemeHooks.shared.image(.iconGiftStars).precomposed(theme.colors.accent),
            header: .init(.initialize(
                string: strings().peerRatingPreviewUsersHeader,
                color: theme.colors.text,
                font: .medium(.text)
            )),
            text: .init(.initialize(
                string: strings().peerRatingPreviewUsersText("20%"),
                color: theme.colors.grayText,
                font: .normal(.text)
            ), cutout: .init(topLeft: NSMakeSize(infoImage_2.backingSize.width + 5, 20))),
            width: initialSize.width - 40,
            infoImage: infoImage_2
        ))

        options.append(.init(
            image: TelegramThemeHooks.shared.image(.iconStarRefund).precomposed(theme.colors.accent),
            header: .init(.initialize(
                string: strings().peerRatingPreviewRefundsHeader,
                color: theme.colors.text,
                font: .medium(.text)
            )),
            text: .init(.initialize(
                string: strings().peerRatingPreviewRefundsText("85%"),
                color: theme.colors.grayText,
                font: .normal(.text)
            ), cutout: .init(topLeft: NSMakeSize(infoImage_3.backingSize.width + 5, 20))),
            width: initialSize.width - 40,
            infoImage: infoImage_3
        ))

        self.options = options

        super.init(initialSize, stableId: stableId, viewType: .legacy)
    }
    
    public override var height: CGFloat {
        var height: CGFloat = 0
        height += headerLayout.layoutSize.height
        height += 20
        height += OptionsListView.height(options: options, spacing: 20)
        
        return height
    }
    public override func viewClass() -> AnyClass {
        return RowView.self
    }
    
    public override var accessibilityLabel: String? {
        let text = headerLayout.attributedString.string
        return text.isEmpty ? nil : text
    }
}

private final class RowView: GeneralContainableRowView {
    
        
    private let optionsView = OptionsListView(frame: .zero)
    private let headerView = TextView()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(headerView)
        
        addSubview(optionsView)
        
        headerView.isSelectable = false
        
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        headerView.centerX(y: 0)
        
        optionsView.centerX(y: headerView.frame.maxY + 20)
        
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? RowItem else {
            return
        }
        
        headerView.update(item.headerLayout)

        
        
        optionsView.spacing = 20
        optionsView.update(options: item.options)
        
        
        needsLayout = true
    }
}


private final class Arguments {
    public let context: any AccountContextProtocol
    public init(context: any AccountContextProtocol) {
        self.context = context
    }
}

private struct State : Equatable {
    public var rating: TelegramStarRating
    public var pendingRating: TelegramStarPendingRating?
    public var peer: EnginePeer
}


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
//    entries.append(.sectionId(sectionId, type: .normal))
//    sectionId += 1
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("line"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return LevelRowItem(initialSize, stableId: stableId, rating: state.rating, peer: state.peer, context: arguments.context)
    }))
    
    if state.rating.level == -1 {
    } else if let pendingRating = state.pendingRating {
        let pendingAmount = pendingRating.rating.stars - state.rating.stars
        if pendingAmount > 0 {
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().peerRatingPreviewInfoPendingOther(Int(pendingAmount))), data: .init(color: theme.colors.listGrayText, viewType: .singleItem, centerViewAlignment: true, alignment: .center)))
            index += 1
        }
    }
    

    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("info"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return RowItem(initialSize, stableId: stableId, rating: state.rating, peer: state.peer, context: arguments.context)
    }))
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

public func PeerRatingModalController(context: any AccountContextProtocol, peer: Peer, rating: TelegramStarRating, pendingRating: TelegramStarPendingRating?) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    let initialState = State(rating: rating, pendingRating: pendingRating, peer: .init(peer))
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let _: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    var getController:(()->ViewController?)? = nil
    var close:(()->Void)? = nil
    
    var window:Window {
        get {
            return bestWindow(context, getController?())
        }
    }
    
    let arguments = Arguments(context: context)
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(
        dataSignal: signal,
        title: strings().peerRatingPreviewTitle
    )
    controller.analyticsScreen = .peerInfoRating
    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    controller.validateData = { _ in
        close?()
        return .none
    }
    
    let modalInteractions = ModalInteractions(
        acceptTitle: strings().peerRatingPreviewAccept,
        accept: { [weak controller] in
            _ = controller?.returnKeyAction()
        },
        singleButton: true
    )

    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    return modalController
    
}

