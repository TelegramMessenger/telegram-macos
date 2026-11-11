
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import AlertsUI
import GeneralRows
import InputDataUI
import LocalAnimations
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import ColorPalette
import TelegramIconsTheme
import AppAnalytics

private func generate(_ color: NSColor) -> CGImage {
    return generateImage(NSMakeSize(20, 20), contextGenerator: { size, ctx in
        let rect: NSRect = .init(origin: .zero, size: size)
        ctx.clear(rect)
        
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: rect)
        
        let image = TelegramThemeHooks.shared.image(.iconChatActionsActive).precomposed()
        
        ctx.clip(to: rect, mask: image)
        ctx.clear(rect)
        
        
    })!
}


private final class HeaderItem : GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate let headerLayout: TextViewLayout
    fileprivate let infoLayout: TextViewLayout
    fileprivate let presentation: TelegramPresentationTheme
    fileprivate let dismiss: ()->Void
    public init(_ initialSize: NSSize, stableId: AnyHashable, mode: GroupCallInviteMode, link: GroupCallInviteSource, presentation: TelegramPresentationTheme, context: any AccountContextProtocol, dismiss:@escaping()->Void) {
        self.context = context
        self.presentation = presentation
        self.dismiss = dismiss
        self.headerLayout = .init(.initialize(string: strings().groupCallInviteLinkTitle, color: presentation.colors.text, font: .medium(.header)), alignment: .center)
        
        let text: String
        switch mode {
        case .basic:
            text = strings().groupCallInviteLinkBasic
        case .share:
            text = strings().groupCallInviteLinkShare
        }
        
        self.infoLayout = .init(.initialize(string: text, color: presentation.colors.text, font: .normal(.text)).detectBold(with: .medium(.text)), alignment: .center)
                
        super.init(initialSize, stableId: stableId)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        self.headerLayout.measure(width: width - 40)
        self.infoLayout.measure(width: width - 40)
        

        return true
    }
    
    public override var height: CGFloat {
        return 80 + 20 + headerLayout.layoutSize.height + 10 + infoLayout.layoutSize.height + 20 + 20
    }

    public override var accessibilityLabel: String? {
        return headerLayout.attributedString.string
    }

    public override var accessibilityValue: String? {
        return infoLayout.attributedString.string
    }
    
    public override func viewClass() -> AnyClass {
        return HeaderItemView.self
    }
}

private final class HeaderItemView: GeneralRowView {
    
    private let dismiss = ImageButton()
    private let headerView = TextView()
    private let infoView = TextView()
    
    private let iconView = View(frame: NSMakeRect(0, 0, 80, 80))
    private let gradient = SimpleGradientLayer()
    private let stickerView = ImageView()

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(dismiss)
        addSubview(headerView)
        addSubview(infoView)
        
        headerView.userInteractionEnabled = false
        infoView.userInteractionEnabled = false
        headerView.isSelectable = false
        infoView.isSelectable = false
        

        
        dismiss.autohighlight = false
        dismiss.scaleOnClick = true
        dismiss.setAccessibilityLabel(strings().voiceOverCommonClose)
        stickerView.isAccessibilityDecorative = true
        
        addSubview(iconView)
        gradient.frame = iconView.bounds
        iconView.layer?.addSublayer(gradient)
        iconView.addSubview(stickerView)
        


        iconView.layer?.cornerRadius = iconView.frame.height / 2
        

    }
    
    public override var backdorColor: NSColor {
        guard let item = item as? HeaderItem else {
            return super.backdorColor
        }
        return item.presentation.colors.background
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? HeaderItem else {
            return
        }
        self.iconView.backgroundColor = item.presentation.colors.accent
        self.headerView.update(item.headerLayout)
        self.infoView.update(item.infoLayout)
        
        stickerView.image = TelegramThemeHooks.shared.image(.iconGroupCallInviteLarge).precomposed(item.presentation.colors.underSelectedColor)
        stickerView.sizeToFit()
        stickerView.center()

        dismiss.set(image: item.presentation.icons.glass_close, for: .Normal)
        dismiss.setGlassEffect(size: NSMakeSize(36, 36), forceAppearance: item.presentation.appearance.glassAppearance)
        dismiss.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        
        dismiss.setSingle(handler: { [weak item] _ in
            item?.dismiss()
        }, for: .Click)
        
    }
    
    public override func layout() {
        super.layout()
        iconView.centerX(y: 20)
        dismiss.setFrameOrigin(NSMakePoint(10, 10))
        
        self.headerView.centerX(y: iconView.frame.maxY + 20)
        self.infoView.centerX(y: self.headerView.frame.maxY + 10)
                
    }
}

private final class ButtonsRowItem: GeneralRowItem {
    fileprivate let copyLink: ()->Void
    fileprivate let shareLink: ()->Void
    fileprivate let presentation: TelegramPresentationTheme
    fileprivate let joinLayout: TextViewLayout
    fileprivate let mode: GroupCallInviteMode
    public init(_ initialSize: NSSize, stableId: AnyHashable, mode: GroupCallInviteMode, copyLink:@escaping()->Void, shareLink:@escaping()->Void, openCall:@escaping()->Void, presentation: TelegramPresentationTheme) {
        self.copyLink = copyLink
        self.shareLink = shareLink
        self.mode = mode
        self.presentation = presentation
        let attr = parseMarkdownIntoAttributedString(strings().groupCallInviteLinksBeFirst, attributes: .init(body: .init(font: .normal(.text), textColor: presentation.colors.text), link: .init(font: .normal(.text), textColor: presentation.colors.link), linkAttribute: { url in
            return (NSAttributedString.Key.link.rawValue, LinkHooks.shared.callbackLink(url, { _ in
                openCall()
            }))
        }))
        self.joinLayout = .init(attr, alignment: .center)
        self.joinLayout.interactions = LinkHooks.shared.globalLinkExecutor()
        super.init(initialSize, height: 70, stableId: stableId)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        joinLayout.measure(width: width - 40)
        return true
    }
    
    public override var accessibilityLabel: String? {
        return strings().groupCallInviteLinkTitle
    }

    public override var height: CGFloat {
        var height: CGFloat = 40
        if case .basic = mode {
            height += joinLayout.layoutSize.height + 5 + 30
        }
        return height
    }
    
    public override func viewClass() -> AnyClass {
        return ButtonsRowView.self
    }
}


private class OrView : View {
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    
    public weak var item: ButtonsRowItem?
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        
        guard let item else {
            return
        }
        
        
        let (text, layout) = TextNode.layoutText(NSAttributedString.initialize(string: strings().passcodeOr, color: item.presentation.colors.grayText, font: .normal(.title)), item.presentation.colors.background, 1, .end, NSMakeSize(.greatestFiniteMagnitude, .greatestFiniteMagnitude), nil, false, .center)
        
        let f = focus(text.size)
        layout.draw(NSMakeRect(f.minX, 0, f.width, f.height), in: ctx, backingScaleFactor: backingScaleFactor, backgroundColor: backgroundColor)
        
        ctx.setFillColor(item.presentation.colors.border.cgColor)
        ctx.fill(NSMakeRect(0, floorToScreenPixels(backingScaleFactor, f.height / 2), f.minX - 10, .borderSize))
        
        ctx.setFillColor(item.presentation.colors.border.cgColor)
        ctx.fill(NSMakeRect(f.maxX + 10, floorToScreenPixels(backingScaleFactor, f.height / 2), f.minX - 10, .borderSize))
    }
}


private final class ButtonsRowView: GeneralRowView {
    private let copyButton = TextButton()
    private let shareButton = TextButton()
    private let separatorView = OrView(frame: .zero)
    private let joinView = TextView();
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(shareButton)
        addSubview(copyButton)
        addSubview(separatorView)
        addSubview(joinView)
        
        joinView.isSelectable = false
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? ButtonsRowItem else {
            return
        }
        
        separatorView.item = item
        
        separatorView.isHidden = item.mode == .share
        joinView.isHidden = item.mode == .share

        copyButton.set(background: item.presentation.colors.accent, for: .Normal)
        copyButton.set(font: .medium(.text), for: .Normal)
        copyButton.set(color: item.presentation.colors.underSelectedColor, for: .Normal)
        copyButton.set(text: strings().groupCallInviteLinksCopyLink, for: .Normal)
        copyButton.layer?.cornerRadius = 10
        copyButton.autohighlight = false
        copyButton.scaleOnClick = true
        copyButton.removeAllHandlers()
        copyButton.set(handler: { [weak item] _ in
            item?.copyLink()
        }, for: .Click)
        
        
        shareButton.set(background: item.presentation.colors.accent, for: .Normal)
        shareButton.set(font: .medium(.text), for: .Normal)
        shareButton.set(color: item.presentation.colors.underSelectedColor, for: .Normal)
        shareButton.set(text: strings().groupCallInviteLinksShareLink, for: .Normal)
        shareButton.layer?.cornerRadius = 10
        shareButton.autohighlight = false
        shareButton.scaleOnClick = true
        shareButton.removeAllHandlers()
        shareButton.set(handler: { [weak item] _ in
            item?.shareLink()
        }, for: .Click)
        
        joinView.update(item.joinLayout)
        
        needsLayout = true
    }
    
    public override func layout() {
        super.layout()
        let width = (self.frame.width - 50) / 2
        
        copyButton.frame = NSMakeRect(20, 0, width, 40)
        shareButton.frame = NSMakeRect(copyButton.frame.maxX + 10, 0, width, 40)
        
        separatorView.frame = NSMakeRect(60, shareButton.frame.maxY + 10, frame.width - 120, 20)
        
        joinView.centerX(y: separatorView.frame.maxY + 5)
        
    }
}

private final class Arguments {
    public let context: any AccountContextProtocol
    public let presentation: TelegramPresentationTheme
    public let dismiss:()->Void
    public let copyLink:()->Void
    public let shareLink:()->Void
    public let openLink:()->Void
    public let revokeLink:()->Void
    public init(context: any AccountContextProtocol, presentation: TelegramPresentationTheme, dismiss:@escaping()->Void, copyLink:@escaping()->Void, shareLink:@escaping()->Void, openLink:@escaping()->Void, revokeLink:@escaping()->Void) {
        self.context = context
        self.presentation = presentation
        self.dismiss = dismiss
        self.shareLink = shareLink
        self.copyLink = copyLink
        self.openLink = openLink
        self.revokeLink = revokeLink
    }
}

private struct State : Equatable {
    public static func == (lhs: State, rhs: State) -> Bool {
        switch lhs.source {
        case let .groupCall(lhsCall):
            switch rhs.source {
            case let .groupCall(rhsCall):
                if lhsCall.callInfo != rhsCall.callInfo {
                    return false
                }
            }
        }
        return lhs.link == rhs.link && lhs.mode == rhs.mode
    }
    
    public var source: GroupCallInviteSource

    public var callInfo: GroupCallInfo {
        switch self.source {
        case .groupCall(let engineCreatedGroupCall):
            return engineCreatedGroupCall.callInfo
        }
    }
    
    public var link: String
    public var mode: GroupCallInviteMode
    public var reference: InternalGroupCallReference {
        return .id(id: callInfo.id, accessHash: callInfo.accessHash)
    }
}


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    let sectionId:Int32 = 0
    let index: Int32 = 0
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("header"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return HeaderItem(initialSize, stableId: stableId, mode: state.mode, link: state.source, presentation: arguments.presentation, context: arguments.context, dismiss: arguments.dismiss)
    }))
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("link"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return GeneralBlockTextRowItem(initialSize, stableId: stableId, viewType: .singleItem, text: state.link, font: .normal(.text), centerViewAlignment: false, rightAction: .init(image: generate(arguments.presentation.colors.grayIcon), action: { view in
            
            guard let event = NSApp.currentEvent else {
                return
            }
            let menu = ContextMenu(presentation: AppMenu.Presentation.current(arguments.presentation.colors))
            
            menu.addItem(ContextMenuItem(strings().modalCopyLink, handler: arguments.copyLink, itemImage: MenuAnimation.menu_copy_link.value))
            
            if state.callInfo.isCreator {
                menu.addItem(ContextSeparatorItem())
                menu.addItem(ContextMenuItem(strings().channelRevokeLink, handler: arguments.revokeLink, itemMode: .destruct, itemImage: MenuAnimation.menu_clear_history.value))
            }
            
            AppMenu.show(menu: menu, event: event, for: view)
            
        }, accessibilityLabel: strings().voiceOverCommonMore), singleLine: true, customTheme: .initialize(arguments.presentation, background: arguments.presentation.colors.listBackground))
    }))
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("h1"), equatable: nil, comparable: nil, item: { initialSize, stableId in
        return GeneralRowItem(initialSize, height: 20, stableId: stableId, backgroundColor: arguments.presentation.colors.background)
    }))
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("button"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return ButtonsRowItem(initialSize, stableId: stableId, mode: state.mode, copyLink: arguments.copyLink, shareLink: arguments.shareLink, openCall: arguments.openLink, presentation: arguments.presentation)
    }))
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("h2"), equatable: nil, comparable: nil, item: { initialSize, stableId in
        return GeneralRowItem(initialSize, height: 20, stableId: stableId, backgroundColor: arguments.presentation.colors.background)
    }))
    
    
    
    return entries
}


public enum GroupCallInviteSource  {
    case groupCall(EngineCreatedGroupCall)
}
public enum GroupCallInviteMode : Equatable {
    case basic
    case share
}

public func GroupCallInviteLinkController(context: any AccountContextProtocol, source: GroupCallInviteSource, mode: GroupCallInviteMode, presentation: TelegramPresentationTheme) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    let link: String
    switch source {
    case let .groupCall(call):
        link = call.link
    }
    
    let initialState = State(source: source, link: link, mode: mode)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    var getController:(()->ViewController?)? = nil
    var close:(()->Void)? = nil
    
    var window:Window {
        get {
            return bestWindow(context, getController?())
        }
    }

    let arguments = Arguments(context: context, presentation: presentation, dismiss: {
        close?()
    }, copyLink: {
        copyToClipboard(initialState.link)
        showModalText(for: window, text: strings().shareLinkCopied)
    }, shareLink: {
        
        let initialState = stateValue.with { $0 }
        
        showModal(with: GroupCallUIHooks.shared.makeShareLinkModal(context, initialState.link, presentation, []), for: window)
    }, openLink: {
        
        let initialState = stateValue.with { $0 }
                
        _ = showModalProgress(signal: context.engine.calls.getCurrentGroupCall(reference: initialState.reference), for: window).start(next: { summary in
            if let summary {
                _ = GroupCallUIHooks.shared.requestOrJoinConferenceCall(context, summary.info, initialState.reference).startStandalone(next: { result in
                    switch result {
                    case let .samePeer(callContext), let .success(callContext):
                        GroupCallUIHooks.shared.applyGroupCallResult(context.sharedContext, callContext)
                    default:
                        alert(for: context.window, info: strings().errorAnError)
                    }
                })
            } else {
                alert(for: context.window, info: strings().errorAnError)
            }
        }, error: { error in
            switch error {
            case .generic:
                showModalText(for: window, text: strings().unknownError)
            }
        })
        
        
        
        close?()
    }, revokeLink: {
        
        let initialState = stateValue.with { $0 }
        
        let signal = context.engine.calls.revokeConferenceInviteLink(reference: initialState.reference, link: initialState.link)
        
        _ = showModalProgress(signal: signal, for: window).start(next: { links in
            updateState { current in
                var current = current
                current.link = links.listenerLink
                return current
            }
            showModalText(for: window, text: strings().groupCallInviteLinkRevoked)
        })
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: "")
    controller.analyticsScreen = mode == .share ? AnalyticsScreen.groupCallShareLink : AnalyticsScreen.groupCallInviteLink
    controller.getBackgroundColor = {
        presentation.colors.background
    }
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }

//    let modalInteractions = ModalInteractions(acceptTitle: strings().modalCopyLink, accept: { [weak controller] in
//        _ = controller?.returnKeyAction()
//    }, singleButton: true, customTheme: {
//        .init(text: presentation.colors.text, grayText: presentation.colors.grayText, background: presentation.colors.background, border: .clear, accent: presentation.colors.accent, grayForeground: .clear, activeBackground: .clear, activeBorder: presentation.colors.border, listBackground: presentation.colors.background)
//    })
    
    controller.validateData = { [weak arguments] _  in
        arguments?.copyLink()
        return .none
    }
    
    let modalController = InputDataModalController(controller, presentation: presentation)
    
    controller.leftModalHeader = ModalHeaderData(image: presentation.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    modalController._hasBorder = false
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    return modalController
    
}


/*

 */

