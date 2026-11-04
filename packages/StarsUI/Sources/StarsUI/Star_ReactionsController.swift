import Foundation
import Cocoa
import TelegramCore
import SwiftSignalKit
import Postbox
import TGUIKit
import ColorPalette
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import MessageUtils
import LocalAnimations
import InlineStickerLayer





private final class Arguments {
    let context: any AccountContextProtocol
    let presentation: TelegramPresentationTheme
    let dismiss:()->Void
    let react:()->Void
    let updateValue:(Int64)->Void
    let openPeer:(EnginePeer)->Void
    let toggleShowInTop:()->Void
    let toggleSendAs:(EnginePeer)->Void
    init(context: any AccountContextProtocol, presentation: TelegramPresentationTheme, dismiss:@escaping()->Void, react:@escaping()->Void, updateValue:@escaping(Int64)->Void, openPeer:@escaping(EnginePeer)->Void, toggleShowInTop:@escaping()->Void, toggleSendAs:@escaping(EnginePeer)->Void) {
        self.context = context
        self.dismiss = dismiss
        self.react = react
        self.presentation = presentation
        self.updateValue = updateValue
        self.openPeer = openPeer
        self.toggleShowInTop = toggleShowInTop
        self.toggleSendAs = toggleSendAs
    }
}



private struct State : Equatable {
    

    
    struct TopPeer : Equatable {
        var peer: EnginePeer?
        var isMy: Bool
        var count: Int64
        var isAnonymous: Bool
    }
    
    var amount: Star_SliderAmount = Star_SliderAmount(realValue: 1, maxRealValue: 2500, maxSliderValue: 2500, isLogarithmic: true)
    
    var myPeer: EnginePeer
    var myBalance: Int64 = 1000
    var countUpdated: Bool = false
    var source: Star_ReactionsSource
    var showMeInTop: Bool = true
    
    
    var privacy: TelegramPaidReactionPrivacy {
        if !showMeInTop {
            return .anonymous
        } else {
            if myPeer.id == sendAsSelected.id {
                return .default
            } else {
                return .peer(sendAsSelected.id)
            }
        }
    }
    
    var peers: [TopPeer] {
        if let myTopIndex = topPeers.firstIndex(where: { $0.isMy }) {
            var topPeers = self.topPeers
            if countUpdated {
                topPeers[myTopIndex].count += Int64(amount.realValue)
            }
            topPeers[myTopIndex].isAnonymous = !self.showMeInTop
            if sendAsSelected.id != topPeers[myTopIndex].peer?.id {
                topPeers[myTopIndex].peer = sendAsSelected
            } else {
                topPeers[myTopIndex].peer = topPeers[myTopIndex].peer ?? sendAsSelected
            }
            return Array(topPeers.sorted(by: { $0.count > $1.count }).prefix(3))
        } else {
            var topPeers = self.topPeers
            if countUpdated {
                let myTopPeer = TopPeer(peer: self.sendAsSelected, isMy: true, count: Int64(amount.realValue), isAnonymous: !self.showMeInTop)
                topPeers.append(myTopPeer)
            }
            return Array(topPeers.sorted(by: { $0.count > $1.count }).prefix(3))
        }
    }
    
    var topPeers: [TopPeer]
    
    var sendAs: [EnginePeer] = []
    
    var sendAsSelected: EnginePeer
}


private final class HeaderItem : GeneralRowItem {
    
    fileprivate struct Sender : Comparable, Identifiable {
        static func < (lhs: HeaderItem.Sender, rhs: HeaderItem.Sender) -> Bool {
            return lhs.index < rhs.index
        }

        var stableId: AnyHashable {
            return peer?.id.toInt64() ?? Int64(index)
        }
        
        let titleLayout: TextViewLayout
        let amountLayout: TextViewLayout
        let peer: EnginePeer?
        let source: Star_ReactionsSource
        let amount: Int64
        let index: Int
    }
    
    fileprivate let context: any AccountContextProtocol
    fileprivate let state: State
    fileprivate let close:()->Void
    fileprivate let updateValue:(Int64)->Void
    fileprivate let openPeer:(EnginePeer)->Void
    fileprivate let toggleShowInTop:()->Void
    fileprivate let toggleSendAs:(EnginePeer)->Void
    fileprivate let presentation: TelegramPresentationTheme

    var showMe: Bool {
        return state.showMeInTop
    }
    
    let maxValue: Int64
    
    fileprivate let balanceLayout: TextViewLayout
    fileprivate let headerLayout: TextViewLayout
    fileprivate let info: TextViewLayout
    
    fileprivate let liveMessagePreview: StarsLiveMessagePreviewRow?
    
    fileprivate var senders: [Sender] = []
    fileprivate var sendAs: [EnginePeer] = []

    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, state: State, viewType: GeneralViewType, updateValue:@escaping(Int64)->Void, action:@escaping()->Void, close:@escaping()->Void, openPeer:@escaping(EnginePeer)->Void, toggleShowInTop:@escaping()->Void, sendAs: [EnginePeer], toggleSendAs:@escaping(EnginePeer)->Void, presentation: TelegramPresentationTheme) {
        self.context = context
        self.state = state
        self.close = close
        self.presentation = presentation
        self.toggleShowInTop = toggleShowInTop
        self.openPeer = openPeer
        self.sendAs = sendAs
        self.updateValue = updateValue
        self.toggleSendAs = toggleSendAs
        self.maxValue = Int64(context.appConfiguration.getGeneralValue("stars_paid_reaction_amount_max", orElse: 1))
        let balanceAttr = NSMutableAttributedString()
        balanceAttr.append(string: strings().starPurchaseBalance("\(clown + TINY_SPACE)\(state.myBalance)"), color: presentation.colors.text, font: .normal(.text))
        balanceAttr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.star_currency_new.file, playPolicy: .onceEnd), for: clown)
        
        self.balanceLayout = .init(balanceAttr, alignment: .right)
        
        self.headerLayout = .init(.initialize(string: strings().starsReactScreenTitle, color: presentation.colors.text, font: .medium(.title)), alignment: .center)
        
        let title = state.source.mainPeer?.displayTitle ?? ""
        
        let attr = NSMutableAttributedString()
        var currentSentAmount: Int?
        if let myPeer = state.source.topPeers.first(where: { $0.isMy }) {
            currentSentAmount = Int(myPeer.count)
        }
        
        attr.append(string: currentSentAmount != nil ? strings().starsReactScreenSentValueOther(currentSentAmount!) : strings().starsReactScreenInfo(title), color: presentation.colors.text, font: .normal(.text))
        attr.detectBoldColorInString(with: .medium(.text))
        self.info = .init(attr, alignment: .center)
        
        for (i, topPeer) in state.peers.enumerated() {
            let amount = topPeer.count
            let title = topPeer.isAnonymous || topPeer.peer == nil ? strings().starsReactScreenAnonymous : topPeer.peer?._asPeer().compactDisplayTitle ?? ""
            senders.append(.init(titleLayout: .init(.initialize(string: title, color: presentation.colors.text, font: .normal(.text)), maximumNumberOfLines: 1), amountLayout: .init(.initialize(string: "\(amount.prettyNumber)", color: .white, font: .medium(.short))), peer: !topPeer.isAnonymous ? topPeer.peer : nil, source: state.source, amount: amount, index: i))

        }
        
        switch state.source {
        case .message:
            self.liveMessagePreview = nil
        case .liveStream:
            self.liveMessagePreview = StarsHooks.shared.makeLiveMessagePreviewRow(initialSize, stableId, context, .init(id: .init(space: .local, id: 0), stableId: 0, isIncoming: false, author: .init(context.myPeer!), isFromAdmin: false, text: "", entities: [], date: context.timestamp, lifetime: 0, paidStars: Int64(state.amount.realValue)))
        }
        
        super.init(initialSize, stableId: stableId, viewType: viewType, action: action, inset: .init())
    }
    
    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        self.balanceLayout.measure(width: .greatestFiniteMagnitude)

        self.headerLayout.measure(width: width - 40 - balanceLayout.layoutSize.width)
        self.info.measure(width: width - 40)
        
        
        return true
    }
    
    static let topInset: CGFloat = 10

    override var height: CGFloat {
        var height: CGFloat = HeaderItem.topInset + 50 + (48 + 12) + 10 + 30 + info.layoutSize.height + 10 + 40 + 10 + 10

        if !senders.isEmpty {
            height += sendersHeight + 20
        }
        height += 50

        if let liveMessagePreview {
            height += liveMessagePreview.height
        }

        if case .liveStream = state.source {
            height -= 50
        }

        return height
    }
    
    var sendersHeight: CGFloat {
        switch state.source {
        case .message:
            return 20 + 36 + 20 + 40
        case .liveStream:
            return 20 + 40 + 20
        }
    }
    
    override var accessibilityLabel: String? {
        return headerLayout.attributedString.string
    }
    
    override var accessibilityValue: String? {
        let balance = balanceLayout.attributedString.string.replacingOccurrences(of: clown, with: "")
        return [info.attributedString.string, balance].joined(separator: ", ")
    }
    
    override func viewClass() -> AnyClass {
        return HeaderItemView.self
    }
}

private final class AcceptView : Control {
    private let textView = InteractiveTextView()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        layer?.cornerRadius = 20
        scaleOnClick = true
        
        textView.userInteractionEnabled = false
        
    }
    
    func update(_ item: HeaderItem, animated: Bool) {
        let attr = NSMutableAttributedString()
        
        self.set(background: item.presentation.colors.accent, for: .Normal)
        
        attr.append(string: strings().starsReactScreenSendOther(clown_space, Int(item.state.amount.realValue)), color: item.presentation.colors.underSelectedColor, font: .medium(.text))
        attr.insertEmbedded(.embedded(name: XTR_ICON, color: item.presentation.colors.underSelectedColor, resize: false), for: clown)
        
        let layout = TextViewLayout(attr)
        layout.measure(width: item.width - 60)
        
        textView.set(text: layout, context: item.context)
        setAccessibilityLabel(attr.string.replacingOccurrences(of: clown, with: ""))
        
        self.removeAllHandlers()
        self.set(handler: { [weak item] _ in
            item?.action()
        }, for: .Click)
        
        
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

private final class SendersView: View {
    
    private class BadgeView : View {
        private let container: View = View()
        private let gradientLayer = SimpleGradientLayer()
        private let textView = TextView()
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(container)
            
            container.layer?.addSublayer(gradientLayer)
            
            container.addSubview(textView)
            
            textView.userInteractionEnabled = false
            textView.isSelectable = false
            
            let layout = TextViewLayout(.initialize(string: strings().starsReactScreenTopSenders, color: NSColor.white, font: .medium(.text)), alignment: .center)
            layout.measure(width: .greatestFiniteMagnitude)
            self.textView.update(layout)
            
            container.setFrameSize(NSMakeSize(textView.frame.width + 20, frameRect.height))
            container.layer?.cornerRadius = container.frame.height / 2
            
            gradientLayer.colors = starsGradient.map { $0.cgColor }
            gradientLayer.startPoint = NSMakePoint(0, 0.5)
            gradientLayer.endPoint = NSMakePoint(1, 0.5)
            
            gradientLayer.frame = container.bounds
        }
        
        func updateColors(_ gradient: [NSColor]) {
            gradientLayer.colors = gradient.map { $0.cgColor }
        }
        
        override func layout() {
            super.layout()
            textView.center()
            container.center()
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func draw(_ layer: CALayer, in ctx: CGContext) {
            super.draw(layer, in: ctx)
            
            ctx.setFillColor(theme.colors.border.cgColor)
            ctx.fill(NSMakeRect(10, frame.height / 2, container.frame.minX - 20, .borderSize))
            ctx.fill(NSMakeRect(container.frame.maxX + 10, frame.height / 2, container.frame.minX - 20, .borderSize))

        }
    }
    
    private final class PeerView : Control {
        private let avatarView = AvatarControl(font: .avatar(18))
        private let nameView = TextView()
        
        private let badgeView = View()
        private let amountView = InteractiveTextView()
        private let amountIcon = ImageView()
        private let badgeGradient = SimpleGradientLayer()
        
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            avatarView.userInteractionEnabled = false
            self.avatarView.setFrameSize(50, 50)
            addSubview(avatarView)
            self.badgeView.layer?.addSublayer(badgeGradient)
            self.badgeView.addSubview(amountView)
            self.badgeView.addSubview(amountIcon)
            amountIcon.isAccessibilityDecorative = true
            addSubview(self.badgeView)
            addSubview(nameView)
            
            badgeGradient.colors = starsGradient.map { $0.cgColor }
            badgeGradient.startPoint = NSMakePoint(0, 0.5)
            badgeGradient.endPoint = NSMakePoint(1, 0.5)
            
            
            nameView.userInteractionEnabled = false
            nameView.isSelectable = false
            self.layer?.masksToBounds = false
            
            self.scaleOnClick = true
        }
        
        func updateColors(_ gradient: [NSColor]) {
            badgeGradient.colors = gradient.map { $0.cgColor }
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func update(_ sender: HeaderItem.Sender, item: HeaderItem, context: any AccountContextProtocol, animated: Bool) {
            if let peer = sender.peer?._asPeer() {
                self.avatarView.setPeer(account: context.account, peer: peer, message: sender.source.message)
            } else {
                let icon = item.presentation.icons.chat_hidden_author
                self.avatarView.setState(account: context.account, state: .Empty)
                let size = self.avatarView.frame.size
                self.avatarView.setSignal(generateEmptyPhoto(size, type: .icon(colors: (top: NSColor(0xb8b8b8), bottom: NSColor(0xb8b8b8).withAlphaComponent(0.6)), icon: icon, iconSize: icon.backingSize, cornerRadius: nil), bubble: false) |> map {($0, false)})
            }
            switch item.state.source {
            case .message:
                badgeGradient.colors = starsGradient.map { $0.cgColor }
            case .liveStream:
                let color = getStarAmountColorMapping(value: Int64(sender.amount))
                badgeGradient.colors = [color, color].map { $0.cgColor }
            }
            
            sender.titleLayout.measure(width: frame.width + 20)
            nameView.update(sender.titleLayout)
            
            sender.amountLayout.measure(width: .greatestFiniteMagnitude)
            amountView.set(text: sender.amountLayout, context: context)
            setAccessibilityLabel(sender.titleLayout.attributedString.string)
            setAccessibilityValue("\(sender.amount.formattedWithSeparator) \(strings().voiceOverCommonStars)")
            
            badgeView.layer?.borderColor = item.presentation.colors.background.cgColor
            badgeView.layer?.borderWidth = 2
            
            amountIcon.image = TelegramThemeHooks.shared.image(.iconPeerPremium).precomposed(NSColor.white, zoom: 0.875)
            amountIcon.sizeToFit()
            
            badgeView.setFrameSize(NSMakeSize(amountView.frame.width + 14 + amountIcon.frame.width, amountView.frame.height + 5))
            badgeView.layer?.cornerRadius = badgeView.frame.height / 2
            
            needsLayout = true
        }
        
        override func layout() {
            super.layout()
            avatarView.centerX(y: 0)
            nameView.centerX(y: frame.height - nameView.frame.height)
            badgeView.centerX(y: avatarView.frame.maxY - floorToScreenPixels(badgeView.frame.height / 2))
            amountIcon.centerY(x: 6, addition: -1)
            amountView.centerY(x: amountIcon.frame.maxX, addition: -1)
            badgeGradient.frame = badgeView.bounds
        }
    }
    
  
    private let badge: BadgeView
    private let container: View
    required init(frame frameRect: NSRect) {
        badge = BadgeView(frame: NSMakeRect(0, 0, frameRect.width, 36))
        container = View(frame: NSMakeRect(0, badge.frame.height + 20, frameRect.width, 100))
        super.init(frame: frameRect)
        addSubview(badge)
        addSubview(container)
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var senders: [HeaderItem.Sender] = []
    private var views: [PeerView] = []
    
    func update(_ senders: [HeaderItem.Sender], item: HeaderItem, context: any AccountContextProtocol, animated: Bool) {
        
        switch item.state.source {
        case .message:
            badge.isHidden = false
        case .liveStream:
            badge.isHidden = true
        }
        
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate
        
        let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: self.senders, rightList: senders)
        self.senders = senders

        
        for rdx in deleteIndices.reversed() {
            performSubviewRemoval(views.remove(at: rdx), animated: transition.isAnimated)
        }
        
        for (idx, sender, prev) in indicesAndItems {
            let view = PeerView(frame: getRect(prev ?? idx))
            view.update(sender, item: item, context: context, animated: animated)
            view.setSingle(handler: { [weak item] _ in
                if let item = item, let peer = sender.peer {
                    item.openPeer(peer)
                }
            }, for: .Click)
            views.insert(view, at: idx)
            container.addSubview(view)
           
        }
        for (idx, sender, _) in updateIndices {
            views[idx].update(sender, item: item, context: context, animated: animated)
            views[idx].setSingle(handler: { [weak item] _ in
                if let item = item, let peer = sender.peer {
                    item.openPeer(peer)
                }
            }, for: .Click)
        }
        
        self.updateLayout(size: self.frame.size, transition: transition)
    }
    
    override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    private func getRect(_ index: Int) -> CGRect {
        let between = floorToScreenPixels((frame.width - (CGFloat(senders.count) * 70)) / CGFloat(senders.count + 1))
        let x: CGFloat = between + (CGFloat(index) * 70) + (CGFloat(index) * between)
        return NSMakeRect(x, 0, 70, container.frame.height)
    }
    
    
    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        
        ContainedViewLayoutTransition.immediate.updateFrame(view: container, frame: NSMakeRect(0, badge.isHidden ? 0 : badge.frame.height + 20, size.width, 80))
        
        for (i, view) in views.enumerated() {
            transition.updateFrame(view: view, frame: getRect(i))
        }
    }
}




private final class ShowMeInTopView: View {
    private let textView = TextView()
    private let selection = SelectingControl(unselectedImage: theme.icons.chatToggleUnselected, selectedImage: theme.icons.chatToggleSelected, selected: false)
    private var container = Control()
    private let separator = View()
    
    fileprivate var callback: (()->Void)? = nil
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        container.addSubview(selection)
        container.addSubview(textView)
        addSubview(container)
        addSubview(separator)
        
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        selection.userInteractionEnabled = false
        selection.isAccessibilityDecorative = true
        
        container.set(handler: { [weak self] _ in
            self?.callback?()
        }, for: .Click)
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func update(showMe: Bool, presentation: TelegramPresentationTheme) {
        
        selection.update(unselectedImage: presentation.icons.chatToggleUnselected, selectedImage: presentation.icons.chatToggleSelected, selected: showMe, animated: true)
        
        let layout = TextViewLayout(.initialize(string: strings().starsReactScreenShowMeInTop, color: presentation.colors.text, font: .normal(.text)))
        layout.measure(width: .greatestFiniteMagnitude)
        self.textView.update(layout)
        container.setAccessibilityLabel(layout.attributedString.string)
        container.setAccessibilityValue(showMe ? strings().voiceOverCommonChecked : strings().voiceOverCommonUnchecked)
        
        container.setFrameSize(NSMakeSize(layout.layoutSize.width + selection.frame.width + 10, 40))
        separator.backgroundColor = presentation.colors.border
        needsLayout = true
    }
    
    override func layout() {
        super.layout()
        container.center()
        selection.centerY(x: 0)
        textView.centerY(x: selection.frame.maxX + 10)
        separator.frame = NSMakeRect(10, 0, frame.width - 20, .borderSize)
    }
}



private final class FromPeerView: Control {
    private let avatarView = AvatarControl(font: .avatar(13))
    private var select: ImageView?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(avatarView)
        avatarView.userInteractionEnabled = false
        self.avatarView.setFrameSize(NSMakeSize(26, 26))
        
        layer?.cornerRadius = 12.5
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func set(_ peer: EnginePeer, sendas: [EnginePeer], _ context: any AccountContextProtocol, presentation: TelegramPresentationTheme, maxWidth: CGFloat, selectAction:@escaping(EnginePeer)->Void) {
        self.avatarView.setPeer(account: context.account, peer: peer._asPeer(), disableForum: true)
        setAccessibilityLabel(peer._asPeer().displayTitle)
        
        self.userInteractionEnabled = !sendas.isEmpty
        self.scaleOnClick = true
        
        if !sendas.isEmpty {
            let current: ImageView
            if let view = self.select {
                current = view
            } else {
                current = ImageView()
                current.isAccessibilityDecorative = true
                self.select = current
                addSubview(current)
            }
            current.image = TelegramThemeHooks.shared.image(.iconAffiliateExpand).precomposed(theme.colors.accent)
            current.sizeToFit()
        } else if let select {
            performSubviewRemoval(select, animated: false)
            self.select = nil
        }
        
        if !sendas.isEmpty {
            self.contextMenu = {
                let menu = ContextMenu(presentation: .init(colors: presentation.colors))
                for senda in sendas {
                    menu.addItem(ContextSendAsMenuItem(peer: .init(peer: senda, subscribers: nil, isPremiumRequired: false), context: context, isSelected: peer.id == senda.id, handler: {
                        selectAction(senda)
                    }))
                }
                return menu
            }
        } else {
            self.contextMenu = nil
        }

        setFrameSize(NSMakeSize(avatarView.frame.width + 5 + (sendas.isEmpty ? 0 : 20), 26))
        
        self.background = presentation.colors.grayForeground
    }
    
    override func layout() {
        super.layout()
        if let select {
            select.centerY(x: self.avatarView.frame.maxX + 5)
        }
    }
}

private final class HeaderItemView : GeneralContainableRowView {
    
    private let dismiss = ImageButton()
    private let balance = InteractiveTextView()
    private let header = InteractiveTextView()
    private let info = InteractiveTextView()
    
    
    
    private let accept: AcceptView = AcceptView(frame: .zero)
    
    let badgeView = Star_BadgeView(frame: NSMakeRect(0, 0, 100, 48))
    let sliderView = Star_SliderView(frame: NSMakeRect(0, 0, 100, 30))
    
    private var sendersView: SendersView?
    
    private let showMeInTop: ShowMeInTopView = .init(frame: .zero)
    
    
    private var sendFromView: FromPeerView?
    
    private var liveMessageView: TableRowView?
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(dismiss)
        addSubview(balance)
        addSubview(header)
        addSubview(info)
        addSubview(accept)
        
        addSubview(badgeView)
        addSubview(sliderView)
        
        addSubview(showMeInTop)
        
        
        sliderView.updateProgress = { [weak self] progress, maybeToBalance in
            if let item = self?.item as? HeaderItem {
                
                var value = progress * CGFloat(item.maxValue)
                let myBalance = CGFloat(item.state.myBalance)
                if maybeToBalance, item.state.amount.realValue < item.state.myBalance, value > myBalance {
                    value = Double(item.state.amount.withRealValue(Int(myBalance + 1)).sliderValue)
                }
                item.updateValue(Int64(ceil(value)))
            }
        }
        
        info.userInteractionEnabled = false
        
        dismiss.set(handler: { [weak self] _ in
            if let item = self?.item as? HeaderItem {
                item.close()
            }
        }, for: .Click)
        
        accept.set(handler: { [weak self] _ in
            if let item = self?.item as? HeaderItem {
                item.action()
            }
        }, for: .Click)
        
        showMeInTop.callback = { [weak self] in
            if let item = self?.item as? HeaderItem {
                item.toggleShowInTop()
            }
        }
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? HeaderItem else {
            return
        }
        
        sliderView.emptyLayer.backgroundColor = item.presentation.colors.listBackground.cgColor
        sliderView.dotLayer.backgroundColor = item.presentation.colors.background
        
        let transition: ContainedViewLayoutTransition = .immediate
        
        switch item.state.source {
        case .message:
            sliderView.updateColors(starsGradient, effect: NSColor(0xffbe27))
            badgeView.updateColors(starsGradient, effect: NSColor(0xffbe27))
            showMeInTop.isHidden = false
        case .liveStream:
            let color = getStarAmountColorMapping(value: Int64(item.state.amount.realValue))
            sliderView.updateColors([color, color], effect: .white)
            badgeView.updateColors([color, color], effect: .white)
            showMeInTop.isHidden = true
        }
        
        showMeInTop.update(showMe: item.showMe, presentation: item.presentation)
        
        

        let size = badgeView.update(sliderValue: Int64(item.state.amount.sliderValue), realValue: Int64(item.state.amount.realValue), max: item.maxValue, context: item.context)
        
        transition.updateFrame(view: self.badgeView, frame: self.focus(size))
        badgeView.updateLayout(size: size, transition: transition)
        
        info.set(text: item.info, context: item.context)
        
        sliderView.update(count: Int64(item.state.amount.sliderValue), minValue: 1, maxValue: item.maxValue)
        
                
        dismiss.set(image: theme.icons.glass_close, for: .Normal)
        dismiss.setGlassEffect(size: NSMakeSize(36, 36))
        dismiss.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        dismiss.scaleOnClick = true
        dismiss.autohighlight = false
        dismiss.setAccessibilityLabel(strings().voiceOverCommonClose)
        
        balance.set(text: item.balanceLayout, context: item.context)
        header.set(text: item.headerLayout, context: item.context)
        
        accept.update(item, animated: animated)
        accept.setFrameSize(NSMakeSize(frame.width - 20, 40))
        
        if !item.senders.isEmpty {
            let current: SendersView
            if let view = self.sendersView {
                current = view
            } else {
                current = .init(frame: NSMakeRect(0, 0, frame.width, item.sendersHeight))
                addSubview(current)
                self.sendersView = current
            }
            current.update(item.senders, item: item, context: item.context, animated: animated)
        } else if let view = self.sendersView {
            performSubviewRemoval(view, animated: animated)
            self.sendersView = nil
        }
        
        if let liveMessagePreview = item.liveMessagePreview {
            let current: TableRowView
            if let view = liveMessageView {
                current = view
            } else {
                let type = liveMessagePreview.viewClass() as! TableRowView.Type
                current = type.init(frame: NSMakeRect(0, 0, frame.width, liveMessagePreview.height))
                addSubview(current)
                self.liveMessageView = current
            }
            current.set(item: liveMessagePreview, animated: animated)
        } else if let liveMessageView {
            performSubviewRemoval(liveMessageView, animated: animated)
            self.liveMessageView = nil
        }
        
        
        if !item.sendAs.isEmpty {
            let current: FromPeerView
            if let view = self.sendFromView {
                current = view
            } else {
                current = .init(frame: NSMakeRect(0, 0, frame.width, 30))
                addSubview(current)
                self.sendFromView = current
            }
            current.set(item.state.sendAsSelected, sendas: item.sendAs, item.context, presentation: item.presentation, maxWidth: 50, selectAction: item.toggleSendAs)
        } else if let view = self.sendFromView {
            performSubviewRemoval(view, animated: animated)
            self.sendFromView = nil
        }
        
        dismiss.isHidden = sendFromView != nil
        
        needsLayout = true

    }
    
    override var backdorColor: NSColor {
        return .clear
    }
    
    override func layout() {
        super.layout()
        
        guard let item = item as? HeaderItem else {
            return
        }

        let topInset = HeaderItem.topInset

        dismiss.setFrameOrigin(NSMakePoint(10, topInset + floorToScreenPixels((50 - dismiss.frame.height) / 2) - 10))
        balance.setFrameOrigin(NSMakePoint(frame.width - 12 - balance.frame.width, topInset + floorToScreenPixels((50 - balance.frame.height) / 2) - 10))


        header.centerX(y: topInset + floorToScreenPixels((50 - header.frame.height) / 2) - 10)

        accept.centerX(y: frame.height - accept.frame.height)

        showMeInTop.frame = NSMakeRect(0, accept.frame.minY - 50, frame.width, 50)

        sliderView.frame = NSMakeRect(10, topInset + 50 + badgeView.frame.height + 10, frame.width - 20, 30)
        sliderView.layout()


        switch item.state.source {
        case .message:
            if let sendersView {
                sendersView.setFrameOrigin(NSMakePoint(0, showMeInTop.frame.minY - sendersView.frame.height - 20))
            }
            info.centerX(y: sliderView.frame.maxY + 20)
        case .liveStream:
            if let sendersView {
                sendersView.setFrameOrigin(NSMakePoint(0, sliderView.frame.maxY + 20))
                info.centerX(y: sendersView.frame.maxY + 20)
            } else {
                info.centerX(y: sliderView.frame.maxY + 20)
            }
        }

        badgeView.centerX(y: topInset + 50)

        badgeView.setFrameOrigin(NSMakePoint(10 + sliderView.dotLayer.frame.midX - badgeView.frame.width * badgeView.tailPosition, topInset + 50))

        if let liveMessageView {
            liveMessageView.centerX(y: accept.frame.minY - 10 - liveMessageView.frame.height)
        }

        if let sendFromView {
            sendFromView.setFrameOrigin(NSMakePoint(10, topInset + floorToScreenPixels((50 - sendFromView.frame.height) / 2) - 10))
        }
    }
}

private let _id_header = InputDataIdentifier("_id_header")

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    if !state.sendAs.isEmpty {
        var bp = 0
        bp += 1
    }

    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return HeaderItem(initialSize, stableId: stableId, context: arguments.context, state: state, viewType: .legacy, updateValue: arguments.updateValue, action: arguments.react, close: arguments.dismiss, openPeer: arguments.openPeer, toggleShowInTop: arguments.toggleShowInTop, sendAs: state.sendAs, toggleSendAs: arguments.toggleSendAs, presentation: arguments.presentation)
    }))
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("h2"), equatable: nil, comparable: nil, item: { initialSize, stableId in
        return GeneralRowItem(initialSize, height: 10, stableId: stableId, backgroundColor: .clear)
    }))
    sectionId += 1
  
    entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(strings().starsReactScreenFooter, linkHandler: { link in
    }), data: .init(color: arguments.presentation.colors.grayText, viewType: .textBottomItem, fontSize: 12, centerViewAlignment: true, alignment: .center, linkColor: arguments.presentation.colors.link)))
    index += 1
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("h3"), equatable: nil, comparable: nil, item: { initialSize, stableId in
        return GeneralRowItem(initialSize, height: 10, stableId: stableId, backgroundColor: .clear)
    }))
    sectionId += 1
    
    return entries
}

public enum Star_ReactionsSource : Equatable {
    
    public struct Callback : Equatable {
        public static func == (lhs: Star_ReactionsSource.Callback, rhs: Star_ReactionsSource.Callback) -> Bool {
            return true
        }
        
        public var value:(Int, TelegramPaidReactionPrivacy, NSRect?)->Void
        public init(value: @escaping (Int, TelegramPaidReactionPrivacy, NSRect?)->Void) {
            self.value = value
        }
    }
    
    case message(EngineMessage)
    case liveStream(EnginePeer, [GroupCallMessagesContext.TopStarsItem], callback:Callback)
    
    var isAnonymousInStarReaction: Bool {
        switch self {
        case let .message(message):
            return message._asMessage().isAnonymousInStarReaction
        case .liveStream:
            return false
        }
    }
    
    var topPeers: [ReactionsMessageAttribute.TopPeer] {
        switch self {
        case let .message(message):
            return message._asMessage().reactionsAttribute?.topPeers ?? []
        case let .liveStream(_, topPeers, _):
            return topPeers.map {
                .init(peerId: $0.peerId, count: Int32($0.amount), isTop: $0.isTop, isMy: $0.isMy, isAnonymous: $0.isAnonymous)
            }
        }
    }
    
    var mainPeer: Peer? {
        switch self {
        case let .message(message):
            if let peer = message.peers[message.id.peerId] {
                return peer
            }
        case let .liveStream(peer, _, _):
            return peer._asPeer()
        }
        return nil
    }
    
    var message: Message? {
        switch self {
        case let .message(message):
            return message._asMessage()
        case .liveStream:
            return nil
        }
    }
    
    func invoke(context: any AccountContextProtocol, count: Int, privacy: TelegramPaidReactionPrivacy, fromRect: NSRect?) {
        switch self {
        case let .message(message):
            context.reactions.sendStarsReaction(message.id, count: count, privacy: privacy, fromRect: fromRect)
        case let .liveStream(_, _, callback):
            callback.value(count, privacy, fromRect)
        }
    }
    
    func updatePrivacy(context: any AccountContextProtocol, privacy: TelegramPaidReactionPrivacy) {
        switch self {
        case let .message(message):
            _ = context.engine.messages.updateStarsReactionPrivacy(id: message.id, privacy: privacy).startStandalone()
        case .liveStream:
            break
        }
    }
}

public func Star_ReactionsController(context: any AccountContextProtocol, source: Star_ReactionsSource, presentation: TelegramPresentationTheme = theme) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    let max_value = Int(context.appConfiguration.getGeneralValue("stars_paid_reaction_amount_max", orElse: 1))
    
    let amount = Star_SliderAmount(realValue: 50, maxRealValue: max_value, maxSliderValue: max_value, isLogarithmic: true)
    
    context.reactions.forceSendStarReactions?()
    
    let initialState = State(amount: amount, myPeer: .init(context.myPeer!), source: source, showMeInTop: !source.isAnonymousInStarReaction, topPeers: [], sendAsSelected: .init(context.myPeer!))
    
    let statePromise = ValuePromise<State>(ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    var getController:(()->InputDataController?)? = nil
    var close:(()->Void)? = nil
    
    var window:Window {
        get {
            return bestWindow(context, getController?())
        }
    }
    context.starsContext.load(force: true)
    

    
    let topPeers = source.topPeers
    
    let topPeersSignal = context.engine.data.get(EngineDataMap(
        topPeers.map(\.peerId).compactMap { $0 }.map { peerId -> TelegramEngine.EngineData.Item.Peer.Peer in
            return TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)
        }
    ))
    
    let sourceView: Signal<Star_ReactionsSource, NoError>
    
    switch source {
    case let .message(message):
        sourceView = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Messages.Message(id: message.id)) |> map { value in
            if let value {
                return .message(value)
            } else {
                return source
            }
        }
    case .liveStream:
        sourceView = .single(source)
    }
    
    
    let sendAs = context.engine.peers.channelsForPublicReaction(useLocalCache: false)
    
    var isFirst: Bool = true
    actionsDisposable.add(combineLatest(context.starsContext.state, topPeersSignal, sourceView, sendAs).start(next: { state, top, updatedSource, sendAs in
        
        var values: [State.TopPeer] = []
        for (_, topPeer) in topPeers.enumerated() {
            let currentPeer: EnginePeer?
            if let peerId = topPeer.peerId, let peer = top[peerId] as? EnginePeer {
                currentPeer = peer
            } else {
                currentPeer = nil
            }
            if values.count < 3 {
                values.append(.init(peer: currentPeer, isMy: topPeer.isMy, count: Int64(topPeer.count), isAnonymous: topPeer.isAnonymous))
            } else {
                break
            }
        }
        updateState { current in
            var current = current
            current.myBalance = state?.balance.value ?? 0
            current.topPeers = values
            current.source = updatedSource
            current.sendAs = sendAs.isEmpty ? [] : [.init(context.myPeer!)] + sendAs
            current.sendAsSelected = values.first(where: { $0.isMy })?.peer ?? current.sendAsSelected
            if isFirst {
                current.showMeInTop = !updatedSource.isAnonymousInStarReaction
            }
            return current
        }
        isFirst = false
    }))
    
    let react:()->Void = {
        let count = stateValue.with { Int($0.amount.realValue) }
        let myBalance = stateValue.with { $0.myBalance }
        let source = stateValue.with { $0.source }
        let privacy = stateValue.with { $0.privacy }
        if let peer = source.mainPeer {
            if count > myBalance {
                showStarsTopup(context: context, source: .purchase(.init(peer), Int64(count)), for: context.window)
            } else {
                let view = getController?()?.tableView.item(stableId: InputDataEntryId.custom(_id_header))?.view as? HeaderItemView
                let rect: NSRect?
                if let view = view {
                    rect = view.sliderView.convert(view.sliderView.dotLayer.frame, to: nil)
                } else {
                    rect = nil
                }
                source.invoke(context: context, count: count, privacy: privacy, fromRect: rect)
                close?()
            }
        }
        
    }

    let arguments = Arguments(context: context, presentation: presentation, dismiss: {
        close?()
    }, react: react, updateValue: { value in
        
        updateState { current in
            var current = current
            current.amount = current.amount.withSliderValue(Int(value))
            current.countUpdated = true
            return current
        }
        let current = stateValue.with { $0.amount.realValue }
        let myBalance = stateValue.with { $0.myBalance }
        if current == myBalance {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
        }
    }, openPeer: { peer in
        close?()
        StarsHooks.shared.openPeerInfo(context, peer.id)
    }, toggleShowInTop: {
        updateState { current in
            var current = current
            current.showMeInTop = !current.showMeInTop
            return current
        }
        stateValue.with { $0.source.updatePrivacy(context: context, privacy: $0.privacy) }

    }, toggleSendAs: { peer in
        updateState { current in
            var current = current
            current.sendAsSelected = peer
            return current
        }
    })
    
    let signal = statePromise.get() |> deliverOnMainQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: "")
    controller.validateData = { _ in
        react()
        return .none
    }
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    
    let modalController = InputDataModalController(controller, modalInteractions: nil)
    
    controller.leftModalHeader = ModalHeaderData(image: presentation.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    controller.getBackgroundColor = {
        presentation.colors.background
    }
    
    getController = { [weak controller] in
        return controller
    }
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    return modalController
}




