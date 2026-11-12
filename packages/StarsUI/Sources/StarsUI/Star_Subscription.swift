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
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let subscription: Star_Subscription
    fileprivate let headerLayout: TextViewLayout
    fileprivate let infoLayout: TextViewLayout
    fileprivate let arguments: Arguments
    
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: (any AccountContextProtocol), subscription: Star_Subscription, arguments: Arguments) {
        self.context = context
        self.subscription = subscription
        self.arguments = arguments
        
        self.headerLayout = .init(.initialize(string: strings().starSubScreenTitle, color: theme.colors.text, font: .medium(18)), alignment: .center)
        
        let attr = NSMutableAttributedString()
        attr.append(string: strings().starSubScreenPrice("\(clown_space)\(subscription.amount)"), color: theme.colors.listGrayText, font: .normal(.text))
        attr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.star_currency_new.file), for: clown)
        
        self.infoLayout = .init(attr)
        
        super.init(initialSize, stableId: stableId, viewType: .legacy, inset: .init())
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        self.headerLayout.measure(width: width - 40)
        self.infoLayout.measure(width: width - 40)
        return true
    }
    
    public override func viewClass() -> AnyClass {
        return HeaderView.self
    }
    
    override var accessibilityLabel: String? {
        return headerLayout.attributedString.string
    }
    
    override var accessibilityValue: String? {
        let price = infoLayout.attributedString.string.replacingOccurrences(of: clown, with: "")
        return [subscription.peer._asPeer().displayTitle, price].joined(separator: ", ")
    }
    
    public override var height: CGFloat {
        let height = 10 + 80 + 10 + headerLayout.layoutSize.height + 5 + infoLayout.layoutSize.height + 2
        return height
    }
    
}

private final class HeaderView : GeneralContainableRowView {
    private var avatar: AvatarControl?
    private let control = Control(frame: NSMakeRect(0, 0, 80, 80))
    private let sceneView: GoldenStarSceneView
    private let dismiss = ImageButton()
    private let headerView = TextView()
    private let infoView = InteractiveTextView()
    private let infoContainer: View = View()
    private let badgeView = ImageView()
    
    private var photo: TransformImageView?

    
    public required init(frame frameRect: NSRect) {
        self.sceneView = GoldenStarSceneView(frame: NSMakeRect(0, 0, frameRect.width, 150))
        super.init(frame: frameRect)
        addSubview(sceneView)
        addSubview(headerView)
        addSubview(control)
        control.addSubview(badgeView)
        infoContainer.addSubview(infoView)
        addSubview(dismiss)

        self.sceneView.sceneBackground = theme.colors.listBackground
        
        addSubview(infoContainer)
        
        sceneView.hideStar()
        
        control.scaleOnClick = true
        control.layer?.masksToBounds = false
        control.isAccessibilityDecorative = true
        badgeView.isAccessibilityDecorative = true
        dismiss.isAccessibilityDecorative = true
        
    }

    
    public override var backdorColor: NSColor {
        return theme.colors.listBackground
    }
    
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? HeaderItem else {
            return
        }
        self.badgeView.isHidden = item.subscription.native.photo != nil
        
        if let photo = item.subscription.native.photo {
            
            if let view = self.avatar {
                performSubviewRemoval(view, animated: animated)
                self.avatar = nil
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
                control.addSubview(current, positioned: .below, relativeTo: badgeView)
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
            
            
            let current: AvatarControl
            if let view = self.avatar {
                current = view
            } else {
                current = AvatarControl(font: .avatar(20))
                current.setFrameSize(NSMakeSize(80, 80))
                self.avatar = current
                control.addSubview(current, positioned: .below, relativeTo: badgeView)
            }
            current.setPeer(account: item.context.account, peer: item.subscription.peer._asPeer())
        }
       
        
        badgeView.image = theme.icons.avatar_star_badge_large_gray
        badgeView.sizeToFit()
        
        self.headerView.update(item.headerLayout)
        self.infoView.set(text: item.infoLayout, context: item.context)
        
        self.dismiss.set(image: theme.icons.glass_close, for: .Normal)
        self.dismiss.setGlassEffect(size: NSMakeSize(36, 36))
        self.dismiss.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        self.dismiss.scaleOnClick = true
        self.dismiss.autohighlight = false
               
        infoContainer.setFrameSize(NSMakeSize(infoContainer.subviewsWidthSize.width + 4, infoContainer.subviewsWidthSize.height + 2))
        
        needsLayout = true
    }
    
    public override func layout() {
        super.layout()
        sceneView.centerX(y: -10)
        
        control.centerX(y: 10)
        
        avatar?.center()
        
        if let avatar {
            badgeView.setFrameOrigin(avatar.frame.maxX - 25, avatar.frame.midY + 8)
        }
        
        if let photo {
            badgeView.setFrameOrigin(photo.frame.maxX - 25, photo.frame.midY + 8)
        }
        
        dismiss.setFrameOrigin(NSMakePoint(10, floorToScreenPixels((50 - dismiss.frame.height) / 2) - 10))
        
        headerView.centerX(y: 90 + 10)
        
        infoContainer.centerX(y: headerView.frame.maxY + 5)
        infoView.centerY(x: 0)

    }
    
    
}

private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let openPeer:(PeerId)->Void
    public let cancel:()->Void
    public let openLink:(String)->Void
    public init(context: (any AccountContextProtocol), openPeer:@escaping(PeerId)->Void, cancel:@escaping()->Void, openLink:@escaping(String)->Void) {
        self.context = context
        self.openPeer = openPeer
        self.cancel = cancel
        self.openLink = openLink
    }
}

private struct State : Equatable {
    public var subscription: Star_Subscription
}

private let _id_header = InputDataIdentifier("_id_header")
private let _id_rows = InputDataIdentifier("_id_rows")

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return HeaderItem(initialSize, stableId: stableId, context: arguments.context, subscription: state.subscription, arguments: arguments)
    }))
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
  
    
    
    var rows: [InputDataTableBasedItem.Row] = []
    
    let peer = state.subscription.peer
    
    
    let from: TextViewLayout = .init(parseMarkdownIntoAttributedString("[\(peer._asPeer().displayTitle)](\(peer.id.toInt64()))", attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: .medium(.text), textColor: theme.colors.text), bold: MarkdownAttributeSet(font: .bold(.text), textColor: theme.colors.text), link: MarkdownAttributeSet(font: .medium(.text), textColor: theme.colors.accentIcon), linkAttribute: { contents in
        return (NSAttributedString.Key.link.rawValue, contents)
    })), maximumNumberOfLines: 1, alwaysStaticItems: true)
    
    from.interactions.processURL = { _ in
        arguments.openPeer(peer.id)
    }

    rows.append(.init(left: .init(.initialize(string: peer._asPeer().isBot ? strings().starSubScreenRowSubBot : strings().starSubScreenRowSub, color: theme.colors.text, font: .normal(.text))), right: .init(name: from, leftView: { previous in
        let control: AvatarControl
        if let previous = previous as? AvatarControl {
            control = previous
        } else {
            control = AvatarControl(font: .avatar(6))
        }
        control.setFrameSize(NSMakeSize(20, 20))
        control.setPeer(account: arguments.context.account, peer: peer._asPeer())
        return control
    })))
    
    if let title = state.subscription.native.title {
        rows.append(.init(left: .init(.initialize(string: strings().starSubScreenRowSub, color: theme.colors.text, font: .normal(.text))), right: .init(name: .init(.initialize(string: title, color: theme.colors.text, font: .normal(.text))))))
    }

    rows.append(.init(left: .init(.initialize(string: strings().starSubScreenRowSubd, color: theme.colors.text, font: .normal(.text))), right: .init(name: .init(.initialize(string: stringForFullDate(timestamp: state.subscription.date), color: theme.colors.text, font: .normal(.text))))))


    rows.append(.init(left: .init(.initialize(string: strings().starSubScreenRowRenew, color: theme.colors.text, font: .normal(.text))), right: .init(name: .init(.initialize(string: stringForFullDate(timestamp: state.subscription.renewDate), color: theme.colors.text, font: .normal(.text))))))

    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_rows, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return InputDataTableBasedItem(initialSize, stableId: stableId, viewType: .singleItem, rows: rows, context: arguments.context)
    }))
    index += 1
    
  
    
    entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(strings().starTransactionTos, linkHandler: arguments.openLink), data: .init(color: theme.colors.listGrayText, viewType: .singleItem, fontSize: 13, centerViewAlignment: true, alignment: .center)))
    index += 1
    
    

    switch state.subscription.state {
    case let .active(refulfil):
        let cancelText = strings().starSubScreenStatusActive(stringForMediumDate(timestamp: state.subscription.renewDate))
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(cancelText), data: .init(color: theme.colors.listGrayText, viewType: .singleItem, fontSize: 13, centerViewAlignment: true, alignment: .center)))
        index += 1
        
        if !refulfil {
            entries.append(.desc(sectionId: sectionId, index: index, text: .customMarkdown("[\(strings().starSubScreenStatusActiveCancel)]()", linkColor: theme.colors.redUI, linkFont: .medium(.text), linkHandler: { _ in
                arguments.cancel()
            }), data: .init(color: theme.colors.listGrayText, viewType: .singleItem, fontSize: 13, centerViewAlignment: true, alignment: .center)))
            index += 1
        }
    case .cancelled:
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().starSubScreenStatusCancelled), data: .init(color: theme.colors.redUI, viewType: .singleItem, fontSize: 13, centerViewAlignment: true, alignment: .center)))
        index += 1
    case .expired:
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().starSubScreenStatusExpired), data: .init(color: theme.colors.grayText, viewType: .singleItem, fontSize: 13, centerViewAlignment: true, alignment: .center)))
        index += 1
    }
    
   

    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1

    
    return entries
}

public func Star_SubscriptionScreen(context: (any AccountContextProtocol), subscription: Star_Subscription) -> InputDataModalController {

    let actionsDisposable = DisposableSet()
    var close:(()->Void)? = nil
    

    
    let initialState = State(subscription: subscription)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let _: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
   
    
    var getController:(()->ViewController?)? = nil
    
    var window:Window {
        get {
            return getController?()?.window ?? context.window
        }
    }

    let arguments = Arguments(context: context, openPeer: { peerId in
        StarsHooks.shared.openChat(context, peerId, nil)
        close?()
    }, cancel: {
        context.starsSubscriptionsContext.updateSubscription(id: subscription.id, cancel: true)
        showModalText(for: window, text: strings().starSubScreenCancelledAlert)
        close?()
    }, openLink: { link in
        StarsHooks.shared.openLink(context, link, { _, _, _, _ in })
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: "")
    controller.analyticsScreen = .starsSubscription
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    

    let modalInteractions: ModalInteractions?
    
    switch subscription.state {
    case let .active(refulfil):
        
        modalInteractions = ModalInteractions(acceptTitle: subscription.peer._asPeer().isBot ? strings().starSubScreenActionBot : (refulfil ? strings().starSubScreenActionJoin : strings().starSubScreenActionOpen), accept: {
            if refulfil {
                _ = context.engine.payments.fulfillStarsSubscription(peerId: context.peerId, subscriptionId: subscription.id).start()
            }
            StarsHooks.shared.openChat(context, subscription.peer.id, nil)
            closeAllModals(window: window)
        }, singleButton: true)
    case let .cancelled(refulfil):
        modalInteractions = ModalInteractions(acceptTitle: refulfil ? strings().starSubScreenActionJoin : strings().starSubScreenActionRenew, accept: {
            if refulfil {
                _ = context.engine.payments.fulfillStarsSubscription(peerId: context.peerId, subscriptionId: subscription.id).start()
                StarsHooks.shared.openChat(context, subscription.peer.id, nil)
                closeAllModals(window: window)
            } else {
                context.starsSubscriptionsContext.updateSubscription(id: subscription.id, cancel: false)
                StarsHooks.shared.openChat(context, subscription.peer.id, nil)
                closeAllModals(window: window)
            }
        }, singleButton: true)
    case .expired:
        if let inviteHash = subscription.native.inviteHash {
            modalInteractions = ModalInteractions(acceptTitle: strings().starSubScreenActionRenew, accept: {
                StarsHooks.shared.openInviteHash(context, inviteHash, { _ in
                    delay(1.5, closure: {
                        StarsHooks.shared.openChat(context, subscription.peer.id, nil)
                        closeAllModals(window: window)
                    })
                })
                close?()
            }, singleButton: true)
        } else {
            modalInteractions = nil
        }
    }
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    return modalController
}


