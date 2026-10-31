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


private final class HeaderItem : GeneralRowItem {
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let peer: EnginePeer
    fileprivate let request: State.Request
    fileprivate let myBalance: StarsAmount
    fileprivate let close:()->Void
    
    
    fileprivate let balanceLayout: TextViewLayout
    fileprivate let headerLayout: TextViewLayout
    fileprivate let infoLayout: TextViewLayout

    public private(set) var badge: BadgeNode?

    public init(_ initialSize: NSSize, stableId: AnyHashable, context: (any AccountContextProtocol), peer: EnginePeer, myBalance: StarsAmount, request: State.Request, viewType: GeneralViewType, action:@escaping()->Void, close:@escaping()->Void) {
        self.context = context
        self.peer = peer
        self.myBalance = myBalance
        self.request = request
        self.close = close
        
        let balanceAttr = NSMutableAttributedString()
        balanceAttr.append(string: strings().starPurchaseBalance("\(clown + TINY_SPACE)\(myBalance)"), color: theme.colors.text, font: .normal(.text))
        balanceAttr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.star_currency_new.file, playPolicy: .onceEnd), for: clown)
        
        self.balanceLayout = .init(balanceAttr, alignment: .right)
        
        let headerText: String
        switch request.type {
        case .bot, .paidMedia:
            headerText = strings().starPurchaseConfirm
        case .subscription:
            headerText = strings().starsPurchaseSubscribe
        case let .botSubscription(invoice):
            headerText = invoice.title
        }
        
        self.headerLayout = .init(.initialize(string: headerText, color: theme.colors.text, font: .medium(.title)), alignment: .center)
        
        let infoAttr = NSMutableAttributedString()
        switch request.type {
        case .bot:
            infoAttr.append(string: strings().starPurchaseText(request.info, peer._asPeer().displayTitle, strings().starPurchaseTextInOther(Int(request.count))), color: theme.colors.text, font: .normal(.text))
        case .subscription:
            infoAttr.append(string: strings().starsPurchaseSubscribeInfoOther(peer._asPeer().displayTitle, Int(request.count)), color: theme.colors.text, font: .normal(.text))
        case let .botSubscription(invoice):
            infoAttr.append(string: strings().starsPurchaseBotSubscribeInfoOther(invoice.title, peer._asPeer().displayTitle, Int(request.count)), color: theme.colors.text, font: .normal(.text))
        case let .paidMedia(_, count):
            
            var description: String = ""
            
            let photoCount = Int(count.photoCount)
            let videoCount = Int(count.videoCount)
            
            if photoCount > 0 && videoCount > 0 {
                description = strings().starsTransferMediaAnd("**\(strings().starsTransferPhotosOther(photoCount))**", "**\(strings().starsTransferVideosOther(videoCount))**")
            } else if photoCount > 0 {
                if photoCount > 1 {
                    description += "**\(strings().starsTransferPhotosOther(photoCount))**"
                } else {
                    description += "**\(strings().starsTransferSinglePhoto)**"
                }
            } else if videoCount > 0 {
                if videoCount > 1 {
                    description += "**\(strings().starsTransferVideosOther(videoCount))**"
                } else {
                    description += "**\(strings().starsTransferSingleVideo)**"
                }
            }
            
            infoAttr.append(string: strings().starPurchasePaidMediaText(description, peer._asPeer().displayTitle, strings().starPurchaseTextInOther(Int(request.count))), color: theme.colors.text, font: .normal(.text))
        }
        infoAttr.detectBoldColorInString(with: .medium(.text))
        self.infoLayout = .init(infoAttr, alignment: .center)
        
        
        if case let .botSubscription(invoice) = request.type {
            
            var under = theme.colors.underSelectedColor

            let badgeText: String
            let color: NSColor
            badgeText = "\(invoice.totalAmount)"
            color = NSColor(0xFFAC04)
            under = .white
            
            badge = .init(.initialize(string: badgeText, color: under, font: .avatar(.small)), color, aroundFill: theme.colors.background, additionSize: NSMakeSize(16, 7))
            
        }
        
        super.init(initialSize, stableId: stableId, viewType: viewType, action: action, inset: .init())
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        self.balanceLayout.measure(width: .greatestFiniteMagnitude)

        self.headerLayout.measure(width: width - 40)
        self.infoLayout.measure(width: width - 40)

        return true
    }
    
    public override var height: CGFloat {
        var height = 10 + 80 + 10 + headerLayout.layoutSize.height + 10 + infoLayout.layoutSize.height + 10 + 40 + 10 + 10
        
        if case .botSubscription = request.type {
            height += 30
        }
        return height
    }
    
    override var accessibilityLabel: String? {
        return headerLayout.attributedString.string
    }
    
    override var accessibilityValue: String? {
        let balance = balanceLayout.attributedString.string.replacingOccurrences(of: clown, with: "")
        return [infoLayout.attributedString.string, balance].joined(separator: ", ")
    }
    
    public override func viewClass() -> AnyClass {
        return HeaderItemView.self
    }
}

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
    
    public func update(_ item: HeaderItem, animated: Bool) {
        let attr = NSMutableAttributedString()
        
        switch item.request.type {
        case .bot, .paidMedia:
            attr.append(string: strings().starPurchasePay("\(XTRSTAR)\(TINY_SPACE)\(item.request.count)"), color: theme.colors.underSelectedColor, font: .medium(.text))
            attr.insertEmbedded(.embedded(name: XTR_ICON, color: theme.colors.underSelectedColor, resize: false), for: XTRSTAR)
        case .subscription:
            attr.append(string: strings().starsPurchaseSubscribeAction, color: theme.colors.underSelectedColor, font: .medium(.text))
        case let .botSubscription(invoice):
            attr.append(string: strings().starsPurchaseBotSubscribeAcceptMonth("\(XTRSTAR)\(TINY_SPACE)\(invoice.totalAmount.formattedWithSeparator)"), color: theme.colors.underSelectedColor, font: .medium(.text))
            attr.insertEmbedded(.embedded(name: XTR_ICON, color: theme.colors.underSelectedColor, resize: false), for: XTRSTAR)
        }
        
        
        let layout = TextViewLayout(attr)
        layout.measure(width: item.width - 60)
        
        textView.set(text: layout, context: item.context)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        textView.center()
    }
}


private class PreviewMediaView: Control {
    
    private let imageView = TransformImageView()
    private let dustView: MediaDustView2
    private let maskLayer = SimpleShapeLayer()
    private var textView: TextView?
            
    public required init(frame frameRect: NSRect) {
        self.dustView = MediaDustView2(frame: frameRect.size.bounds)
        super.init(frame: frameRect)
        addSubview(imageView)
        addSubview(dustView)
        
    }
    
    public override func layout() {
        super.layout()
        imageView.frame = bounds
        dustView.frame = bounds
        maskLayer.frame = bounds
    }
    
    private func buttonPath(_ basic: CGPath) -> CGPath {
        let buttonPath = CGMutablePath()

        buttonPath.addPath(basic)
        
        return buttonPath
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func update(image: TelegramMediaImage, count: Int, context: (any AccountContextProtocol)) {
                
        let size = image.representationForDisplayAtSize(PixelDimensions.init(100, 100))?.dimensions.size ?? NSMakeSize(100, 100)
        
        let arguments = TransformImageArguments(corners: .init(radius: 10), imageSize: size, boundingSize: self.frame.size, intrinsicInsets: .init())
        
        self.imageView.setSignal(chatMessagePhoto(account: context.account, imageReference: .standalone(media: image), scale: System.backingScale))
        self.imageView.set(arguments: arguments)
        
        let path = CGMutablePath()
        
        let minx:CGFloat = 0, midx = arguments.boundingSize.width/2.0, maxx = arguments.boundingSize.width
        let miny:CGFloat = 0, midy = arguments.boundingSize.height/2.0, maxy = arguments.boundingSize.height
        
        path.move(to: NSMakePoint(minx, midy))
        
        path.addArc(tangent1End: NSMakePoint(minx, miny), tangent2End: NSMakePoint(midx, miny), radius: 10)
        path.addArc(tangent1End: NSMakePoint(maxx, miny), tangent2End: NSMakePoint(maxx, midy), radius: 10)
        path.addArc(tangent1End: NSMakePoint(maxx, maxy), tangent2End: NSMakePoint(midx, maxy), radius: 10)
        path.addArc(tangent1End: NSMakePoint(minx, maxy), tangent2End: NSMakePoint(minx, midy), radius: 10)
        
        maskLayer.frame = bounds
        maskLayer.path = path
        layer?.mask = maskLayer
        
        self.layout()
        self.dustView.update(size: frame.size, color: .white, mask: buttonPath(path))
        
        
        if count > 1 {
            let current: TextView
            if let view = self.textView {
                current = view
            } else {
                current = TextView()
                current.userInteractionEnabled = false
                current.isSelectable = false
                addSubview(current)
                self.textView = current
            }
            let layout = TextViewLayout(.initialize(string: "\(count)", color: NSColor.white, font: .avatar(30)))
            layout.measure(width: .greatestFiniteMagnitude)
            current.update(layout)
            current.center()
        } else if let textView {
            performSubviewRemoval(textView, animated: false)
            self.textView = nil
        }
    }
}

private final class HeaderItemView : GeneralContainableRowView {
 
    
    private final class PeerView: Control {
        private let avatarView = AvatarControl(font: .avatar(13))
        private let nameView: TextView = TextView()
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(avatarView)
            addSubview(nameView)
            
            nameView.userInteractionEnabled = false
            self.avatarView.setFrameSize(NSMakeSize(26, 26))
            
            layer?.cornerRadius = 12.5
        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public func set(_ peer: EnginePeer, _ context: (any AccountContextProtocol), maxWidth: CGFloat) {
            self.avatarView.setPeer(account: context.account, peer: peer._asPeer())
            
            let nameLayout = TextViewLayout(.initialize(string: peer._asPeer().displayTitle, color: theme.colors.text, font: .normal(.title)), maximumNumberOfLines: 1)
            nameLayout.measure(width: maxWidth)
            
            nameView.update(nameLayout)

            setFrameSize(NSMakeSize(avatarView.frame.width + 10 + nameLayout.layoutSize.width + 10, 26))
            
            self.background = theme.colors.grayForeground
        }
        
        public override func layout() {
            super.layout()
            nameView.centerY(x: self.avatarView.frame.maxX + 10)
        }
    }
    
    private let dismiss = ImageButton()
    private let balance = InteractiveTextView()
    private var photo: TransformImageView?
    private var avatar: AvatarControl?
    private var paidPreview: PreviewMediaView?
    private let header = InteractiveTextView()
    private let info = InteractiveTextView()
    private let sceneView: GoldenStarSceneView
    
    private var subBadgeView: ImageView?
    
    private var subscribeBadge: View?
    
    private var subPeerView: PeerView?
    
    private let accept: AcceptView = AcceptView(frame: .zero)
    
    public required init(frame frameRect: NSRect) {
        self.sceneView = GoldenStarSceneView(frame: NSMakeRect(0, 0, frameRect.width, 150))
        super.init(frame: frameRect)
        addSubview(sceneView)
        addSubview(dismiss)
        addSubview(balance)
        addSubview(header)
        addSubview(info)
        
        self.sceneView.sceneBackground = theme.colors.background
        
        addSubview(accept)
        
        sceneView.hideStar()
        
        
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
        
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? HeaderItem else {
            return
        }
        
        
        if case let .paidMedia(image, count) = item.request.type {
            if let view = self.avatar {
                performSubviewRemoval(view, animated: animated)
                self.avatar = nil
            }
            if let view = self.subBadgeView {
                performSubviewRemoval(view, animated: animated)
                self.subBadgeView = nil
            }
            if let view = self.photo {
                performSubviewRemoval(view, animated: animated)
                self.photo = nil
            }
            
            let current: PreviewMediaView
            if let view = self.paidPreview {
                current = view
            } else {
                current = PreviewMediaView(frame: NSMakeRect(0, 0, 80, 80))
                addSubview(current)
                self.paidPreview = current
            }
            current.update(image: image, count: Int(count.total), context: item.context)
        } else if let photo = item.request.invoice?.photo {
            if let view = self.avatar {
                performSubviewRemoval(view, animated: animated)
                self.avatar = nil
            }
            if let view = self.subBadgeView {
                performSubviewRemoval(view, animated: animated)
                self.subBadgeView = nil
            }
            if let view = self.paidPreview {
                performSubviewRemoval(view, animated: animated)
                self.paidPreview = nil
            }
            let current: TransformImageView
            if let view = self.photo {
                current = view
            } else {
                current = TransformImageView(frame: NSMakeRect(0, 0, 80, 80))
                current.layer?.cornerRadius = floor(current.frame.height / 2)
                if #available(macOS 10.15, *) {
                    current.layer?.cornerCurve = .continuous
                } 
                addSubview(current)
                self.photo = current
            }
            
            current.setSignal(chatMessageWebFilePhoto(account: item.context.account, photo: photo, scale: backingScaleFactor))
    
            _ = fetchedMediaResource(mediaBox: item.context.account.postbox.mediaBox, userLocation: .other, userContentType: .other, reference: MediaResourceReference.standalone(resource: photo.resource)).start()
    
            current.set(arguments: TransformImageArguments(corners: .init(radius: .cornerRadius), imageSize: photo.dimensions?.size ?? NSMakeSize(80, 80), boundingSize: current.frame.size, intrinsicInsets: .init()))

            
            
        } else {
            if let view = self.photo {
                performSubviewRemoval(view, animated: animated)
                self.photo = nil
            }
            if let view = self.paidPreview {
                performSubviewRemoval(view, animated: animated)
                self.paidPreview = nil
            }
            let current: AvatarControl
            if let view = self.avatar {
                current = view
            } else {
                current = AvatarControl(font: .avatar(20))
                current.setFrameSize(NSMakeSize(80, 80))
                self.avatar = current
                addSubview(current)
            }
            current.setPeer(account: item.context.account, peer: item.peer._asPeer())
        }
        
        if case .subscription = item.request.type {
            let current: ImageView
            if let view = self.subBadgeView {
                current = view
            } else {
                current = ImageView()
                current.isAccessibilityDecorative = true
                self.subBadgeView = current
                addSubview(current)
            }
            current.image = theme.icons.avatar_star_badge_large_gray
            current.sizeToFit()
        } else if let subBadgeView {
            performSubviewRemoval(subBadgeView, animated: animated)
            self.subBadgeView = nil
        }
        
        
        if let badge = item.badge {
            let current: View
            if let view = self.subscribeBadge {
                current = view
            } else {
                current = View()
                self.subscribeBadge = current
                addSubview(current)
            }
            badge.view = current
            current.setFrameSize(badge.size)
        } else if let subscribeBadge = subscribeBadge {
            performSubviewRemoval(subscribeBadge, animated: animated)
            self.subscribeBadge = nil
        }
        
        if case .botSubscription(_) = item.request.type {
            let current: PeerView
            if let view = self.subPeerView {
                current = view
            } else {
                current = PeerView(frame: .zero)
                self.subPeerView = current
                addSubview(current)
            }
            current.set(item.peer, item.context, maxWidth: frame.width - 40)
        } else if let view = self.subPeerView {
            performSubviewRemoval(view, animated: animated)
            self.subPeerView = nil
        }
        
        
        dismiss.set(image: theme.icons.glass_close, for: .Normal)
        dismiss.setGlassEffect(size: NSMakeSize(36, 36))
        dismiss.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        dismiss.scaleOnClick = true
        dismiss.autohighlight = false
        dismiss.setAccessibilityLabel(strings().voiceOverCommonClose)
        
        balance.set(text: item.balanceLayout, context: item.context)
        header.set(text: item.headerLayout, context: item.context)
        info.set(text: item.infoLayout, context: item.context)
        
        accept.update(item, animated: animated)
        accept.setFrameSize(NSMakeSize(frame.width - 40, 40))
        
        needsLayout = true

    }
    
    public override var backdorColor: NSColor {
        return theme.colors.background
    }
    
    public override func layout() {
        super.layout()
        dismiss.setFrameOrigin(NSMakePoint(10, floorToScreenPixels((50 - dismiss.frame.height) / 2) - 10))
        if let photo {
            photo.centerX(y: 10)
            
            if let subscribeBadge {
                subscribeBadge.centerX(y: photo.frame.maxY - subscribeBadge.frame.height)
            }
        }
        if let avatar {
            avatar.centerX(y: 10)
            if let subBadgeView {
                subBadgeView.setFrameOrigin(avatar.frame.maxX - 25, avatar.frame.midY + 8)
            }
            
            if let subscribeBadge {
                subscribeBadge.centerX(y: avatar.frame.maxY - subscribeBadge.frame.height / 2)
            }
        }
        if let paidPreview {
            paidPreview.centerX(y: 10)
        }
        
        sceneView.centerX(y: -10)
        balance.setFrameOrigin(NSMakePoint(frame.width - 12 - balance.frame.width, floorToScreenPixels((50 - balance.frame.height) / 2) - 10))
        
        let headerY = photo?.frame.maxY ?? avatar?.frame.maxY ?? paidPreview?.frame.maxY ?? 0
        
        header.centerX(y: headerY + 10)
        info.centerX(y: header.frame.maxY + 10)
        accept.centerX(y: frame.height - accept.frame.height - 10)
        
        if let subPeerView {
            subPeerView.centerX(y: info.frame.maxY + 10)
        }
        
    }
}

private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let dismiss: ()->Void
    public let buy: ()->Void
    public init(context: (any AccountContextProtocol), dismiss: @escaping()->Void, buy: @escaping()->Void) {
        self.context = context
        self.dismiss = dismiss
        self.buy = buy
    }
}

private struct State : Equatable {
    public struct Request : Equatable {
        public let count: Int64
        public let info: String
        public let invoice: TelegramMediaInvoice?
        public let type: StarPurchaseType
        public init(count: Int64, info: String, invoice: TelegramMediaInvoice?, type: StarPurchaseType) {
            self.count = count
            self.info = info
            self.invoice = invoice
            self.type = type
        }
    }
    public var request: Request
    public var peer: EnginePeer?
    public var myBalance: StarsAmount?
    public var starsState: StarsContext.State?
    public var formId: Int64?
}

private let _id_header = InputDataIdentifier("_id_header")

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    let index: Int32 = 0
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("h1"), equatable: nil, comparable: nil, item: { initialSize, stableId in
        return GeneralRowItem(initialSize, height: 10, stableId: stableId, backgroundColor: theme.colors.background)
    }))
    sectionId += 1
    
    if let peer = state.peer, let myBalance = state.myBalance {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            return HeaderItem(initialSize, stableId: stableId, context: arguments.context, peer: peer, myBalance: myBalance, request: state.request, viewType: .legacy, action: arguments.buy, close: arguments.dismiss)
        }))
        
        if case .botSubscription = state.request.type {
            entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(strings().starTransactionBotTos, linkHandler: { url in
                LinkHooks.shared.openExternalLink(url, false)
            }), data: .init(color: theme.colors.listGrayText, viewType: .legacy, centerViewAlignment: true, alignment: .center)))
            sectionId += 1

        }
        
    } else {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("loading"), equatable: nil, comparable: nil, item: { initialSize, stableId in
            return LoadingTableItem(initialSize, height: 219, stableId: stableId, backgroundColor: theme.colors.background)
        }))
    }
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("h2"), equatable: nil, comparable: nil, item: { initialSize, stableId in
        return GeneralRowItem(initialSize, height: 10, stableId: stableId, backgroundColor: theme.colors.background)
    }))
    sectionId += 1
    
    return entries
}

public enum StarPurchaseType : Equatable {
    
    public struct PaidMediaCount: Equatable {
        public let photoCount: Int
        public let videoCount: Int
        
        public var total: Int {
            return photoCount + videoCount
        }
        public init(photoCount: Int, videoCount: Int) {
            self.photoCount = photoCount
            self.videoCount = videoCount
        }
    }
    
    case bot
    case paidMedia(TelegramMediaImage, PaidMediaCount)
    case subscription(ExternalJoiningChatState.Invite)
    case botSubscription(TelegramMediaInvoice)

    public static func ==(lhs: StarPurchaseType, rhs: StarPurchaseType) -> Bool {
        switch (lhs, rhs) {
        case (.bot, .bot):
            return true
        case let (.paidMedia(lhsImage, lhsCount), .paidMedia(rhsImage, rhsCount)):
            return lhsImage.isEqual(to: rhsImage) && lhsCount == rhsCount
        case let (.subscription(lhsInvite), .subscription(rhsInvite)):
            return lhsInvite == rhsInvite
        case let (.botSubscription(lhsInvoice), .botSubscription(rhsInvoice)):
            return lhsInvoice.id == rhsInvoice.id
        default:
            return false
        }
    }
}

public enum StarPurchaseCompletionStatus : Equatable {
    case paid(messageId: MessageId?, peerId: PeerId?)
    case cancelled
    case failed
    
    public var rawValue: String {
        switch self {
        case .paid:
            return "paid"
        case .cancelled:
            return "cancelled"
        case .failed:
            return "failed"
        }
    }
}


public func Star_PurschaseInApp(context: (any AccountContextProtocol), invoice: TelegramMediaInvoice?, source: BotPaymentInvoiceSource, type: StarPurchaseType = .bot, completion: @escaping (StarPurchaseCompletionStatus) -> Void = { _ in }) -> InputDataModalController {
    if case let .message(messageId) = source {
    }
    let session = StarPurchaseSession()
    let actionsDisposable = DisposableSet()
    let paymentDisposable = MetaDisposable()
    actionsDisposable.add(paymentDisposable)
    let dismiss = {
        let cancelled = session.close()
        actionsDisposable.dispose()
        if cancelled { completion(.cancelled) }
    }

    let request: State.Request
    if let invoice {
        request = .init(count: invoice.totalAmount, info: invoice.title, invoice: invoice, type: type)
    } else {
        if case let .subscription(state) = type {
            request = .init(count: state.subscriptionPricing!.amount.value, info: "", invoice: nil, type: type)
        } else {
            fatalError()
        }
    }
    
    let initialState = State(request: request, myBalance: nil)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    let starsContext = context.starsContext
    
    starsContext.load(force: true)
    
    actionsDisposable.add((starsContext.state |> deliverOnMainQueue).start(next: { starsState in
        guard session.isOpen else { return }
        updateState { current in
            var current = current
            current.myBalance = starsState?.balance
            current.starsState = starsState
            return current
        }
    }))
    
    switch type {
    case let .subscription(state):
        let photo = state.photoRepresentation.flatMap({ [$0] }) ?? []
        updateState { current in
            var current = current
            current.peer = .init(TelegramUser(id: .init(0), accessHash: nil, firstName: state.title, lastName: nil, username: nil, phone: nil, photo: photo, botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: state.nameColor.flatMap({ .preset($0) }), backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil))
            current.formId = state.subscriptionFormId
            return current
        }
    default:
        let formAndMaybeValidatedInfo = context.engine.payments.fetchBotPaymentForm(source: source, themeParams: nil)
        
        actionsDisposable.add((formAndMaybeValidatedInfo |> take(1) |> deliverOnMainQueue).start(next: { [weak actionsDisposable] form in
            guard session.isOpen else { return }
            updateState { current in
                var current = current
                current.formId = form.id
                return current
            }
            if let paymentBotId = form.paymentBotId {
                actionsDisposable?.add((context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: paymentBotId)) |> deliverOnMainQueue).start(next: { peer in
                    guard session.isOpen else { return }
                    updateState { current in
                        var current = current
                        current.peer = peer
                        return current
                    }
                }))
            }
            
        }))
    }
    
    
    
    
    
    var close:(()->Void)? = nil
    var getController:(()->ViewController?)? = nil
    
    var window:Window {
        get {
            return getController?()?.window ?? context.window
        }
    }

    let arguments = Arguments(context: context, dismiss: {
        close?()
    }, buy: {
        let state = stateValue.with { $0 }
        guard let myBalance = state.myBalance, let peer = state.peer, let attempt = session.begin() else { return }
        if state.request.count > myBalance.value {
            let sourceValue: Star_ListScreenSource
            if case .starsChatSubscription = source {
                sourceValue = .purchaseSubscribe(peer, state.request.count)
            } else {
                sourceValue = .purchase(peer, state.request.count)
            }
            let controller = Star_ListScreen(context: context, source: sourceValue)
            let onDeinit = controller.onDeinit
            controller.onDeinit = {
                onDeinit?()
                session.finish(attempt)
            }
            guard session.isCurrent(attempt) else { return }
            showModal(with: controller, for: window)
        } else {
            if let formId = state.formId {
                let request = MetaDisposable()
                paymentDisposable.set(request)
                let signal = showModalProgress(signal: context.engine.payments.sendStarsPaymentForm(formId: formId, source: source) |> take(1) |> deliverOnMainQueue, for: window)
                guard session.isCurrent(attempt) else { return }
                request.set((signal).start(next: { result in
                    switch result {
                    case let .done(receiptMessageId, subscriptionPeerId, _):
                        guard session.finish(attempt, paid: true) else { return }
                        let text: String
                        switch type {
                        case .bot:
                            text = strings().starPurchaseSuccess(state.request.info, peer._asPeer().displayTitle, strings().starPurchaseTextInOther(Int(state.request.count)))
                        case .paidMedia:
                            text = strings().starPurchasePaidMediaSuccess(strings().starPurchaseTextInOther(Int(state.request.count)))
                        case let .subscription(invite):
                            text = strings().starsPurchaseSubscribeSuccess(invite.title)
                        case let .botSubscription(invoice):
                            text = strings().starsPurchaseBotSubscribeSuccess(invoice.title, peer._asPeer().displayTitle)
                        }
                        showModalText(for: window, text: text)

                        switch type {
                        case .paidMedia, .subscription:
                            PlayConfetti(for: window, stars: true)
                        default:
                            break
                        }
                        context.starsContext.load(force: true)
                        context.starsSubscriptionsContext.load(force: true)

                        completion(.paid(messageId: receiptMessageId, peerId: subscriptionPeerId))
                        close?()
                    default:
                        break
                    }
                }, error: { error in
                    guard session.finish(attempt) else { return }
                    let text: String
                    switch error {
                    case .alreadyPaid:
                        text = strings().checkoutErrorInvoiceAlreadyPaid
                    case .generic:
                        text = strings().unknownError
                    case .paymentFailed:
                        text = strings().checkoutErrorPaymentFailed
                    case .precheckoutFailed:
                        text = strings().checkoutErrorPrecheckoutFailed
                    case .starGiftOutOfStock:
                        text = strings().giftSoldOutError
                    case .disallowedStarGift:
                        text = strings().giftSendDisallowError
                    case .starGiftUserLimit:
                        text = strings().giftOptionsGiftBuyLimitReached
                    case let .serverProvided(value):
                        text = value
                    }
                    completion(.failed)
                    if session.isOpen { showModalText(for: window, text: text) }
                }))
            } else {
                session.finish(attempt)
            }
        }
    })
    
    let signal = (statePromise.get() |> deliverOnPrepareQueue) |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: "")
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = dismiss
    
    controller.contextObject = starsContext
    
    let modalController = InputDataModalController(controller, modalInteractions: nil, closeHandler: { close in
        dismiss()
        close()
    })
    
    close = { [weak modalController] in
        dismiss()
        modalController?.modal?.close()
    }
    
    
    return modalController
}



