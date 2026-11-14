import Cocoa
import Foundation
import WebKit
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import InAppSettings
import FoundationUtils
import ObjcUtils
import KeyboardKey
import TelegramIconsTheme
import TelegramMedia
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import AlertsUI
import LocalAnimations
import FilePanels
import TelegramLinks
import PremiumStatusUI
import SystemPermissions
import Svg
import LocalAuthentication
import InlineStickerLayer
import AppAnalytics


private func webAppOrigin(url: URL) -> String? {
    return webAppOrigin(scheme: url.scheme, host: url.host, port: url.port)
}

private func webAppOrigin(scheme: String?, host: String?, port: Int?) -> String? {
    guard let scheme = scheme?.lowercased(), !scheme.isEmpty, let host = host?.lowercased(), !host.isEmpty else {
        return nil
    }
    let includePort: Bool
    if let port {
        includePort = !(scheme == "http" && port == 80) && !(scheme == "https" && port == 443)
    } else {
        includePort = false
    }
    if includePort, let port {
        return "\(scheme)://\(host):\(port)"
    } else {
        return "\(scheme)://\(host)"
    }
}

private func webAppOrigin(securityOrigin: WKSecurityOrigin) -> String? {
    return webAppOrigin(scheme: securityOrigin.protocol, host: securityOrigin.host, port: securityOrigin.port == 0 ? nil : securityOrigin.port)
}

private func webAppJsStringLiteral(_ value: String) -> String {
    if let data = try? JSONSerialization.data(withJSONObject: [value], options: []), let string = String(data: data, encoding: .utf8), string.hasPrefix("["), string.hasSuffix("]") {
        return String(string.dropFirst().dropLast())
    }
    return "\"\""
}

private func webAppSecuredEventProxySource(trustedOrigin: String) -> String {
    return """
    (function() {
        if (window.location.origin !== \(webAppJsStringLiteral(trustedOrigin))) {
            return;
        }
        var TelegramWebviewProxyProto = function() {};
        TelegramWebviewProxyProto.prototype.postEvent = function(eventName, eventData) {
            window.webkit.messageHandlers.performAction.postMessage({'eventName': eventName, 'eventData': eventData});
        };
        window.TelegramWebviewProxy = new TelegramWebviewProxyProto();
    })();
    """
}

final class BotEmojiStatusPermissionRowItem : GeneralRowItem {
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let peer: EnginePeer
    public init(_ initialSize: NSSize, stableId: AnyHashable, peer: EnginePeer, context: (any AccountContextProtocol)) {
        self.context = context
        self.peer = peer
        
        super.init(initialSize, height: 50, stableId: stableId)
        
    }
    public override func viewClass() -> AnyClass {
        return BotEmojiStatusPermissionRowView.self
    }

    public override var accessibilityLabel: String? {
        return peer._asPeer().displayTitle
    }
}

private final class BotEmojiStatusPermissionRowView : GeneralRowView {
    private final class PeerView: Control {
        private let avatarView = AvatarControl(font: .avatar(10))
        private let nameView: TextView = TextView()
        private var stickerView: InlineStickerView?
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(avatarView)
            addSubview(nameView)
            
            nameView.userInteractionEnabled = false
            
            self.avatarView.setFrameSize(NSMakeSize(26, 26))
            
            layer?.cornerRadius = 13
        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public func set(_ peer: EnginePeer, _ context: (any AccountContextProtocol), file: TelegramMediaFile, maxWidth: CGFloat) {
            self.avatarView.setPeer(account: context.account, peer: peer._asPeer())
            
            let nameLayout = TextViewLayout(.initialize(string: peer._asPeer().displayTitle, color: theme.colors.text, font: .normal(.title)), maximumNumberOfLines: 1)
            nameLayout.measure(width: maxWidth)
            
            nameView.update(nameLayout)
            
            if let stickerView {
                performSubviewRemoval(stickerView, animated: true)
            }
            
            let current: InlineStickerView = .init(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: .init(fileId: file.fileId.id, file: file, emoji: ""), size: NSMakeSize(20, 20))
            addSubview(current)
            self.stickerView = current
            
            setFrameSize(NSMakeSize(avatarView.frame.width + 10 + nameLayout.layoutSize.width + (stickerView != nil ? 20 : 0) + 10, 26))
            
            self.background = theme.colors.grayForeground
            needsLayout = true
        }
        
        public override func layout() {
            super.layout()
            nameView.centerY(x: self.avatarView.frame.maxX + 10, addition: -1)
            stickerView?.centerY(x: self.nameView.frame.maxX + 7)
        }
    }
    
    private let peerView: PeerView = .init(frame: .zero)
    
    private var timer: SwiftSignalKit.Timer?
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(peerView)
    }
    
     public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? BotEmojiStatusPermissionRowItem else {
            return
        }
        
        let signal = item.context.engine.stickers.loadedStickerPack(reference: .iconStatusEmoji, forceActualized: false) |> map { value in
            switch value {
            case let .result(_, items, installed: _):
                return items
            default:
                return []
            }
        } |> deliverOnMainQueue
        
        _ = signal.start(next: { [weak self, weak item] items in
            var index: Int = 0
            
            let invokeNext:()->Void = {
                if let item = item, let self, items.count > 0 {
                    let file = items[index].file
                    self.peerView.set(item.peer, item.context, file: file._parse(), maxWidth: self.frame.width - 40)
                    self.needsLayout = true
                }
                index += 1
                
                if items.count <= index {
                    index = 0
                }
            }
            self?.timer = .init(timeout: 2, repeat: true, completion: invokeNext, queue: .mainQueue())
            
            self?.timer?.start()
            invokeNext()
        })
    }
    
    
    
    public override var backdorColor: NSColor {
        return theme.colors.listBackground
    }
    
    public override func layout() {
        super.layout()
        
        peerView.centerX(y: frame.height - peerView.frame.height)
    }
}


//
//private class SelectChatRequired : SelectPeersBehavior {
//    private let peerType: ReplyMarkupButtonRequestPeerType
//    private let context: (any AccountContextProtocol)
//
//    init(peerType: [String], context: (any AccountContextProtocol)) {
//        self.peerType = peerType
//        self.context = context
//        super.init(settings: [.remote, .], limit: 1)
//    }
//
//    override func filterPeer(_ peer: Peer) -> Bool {
//
//    }
//}


private class NoScrollWebView: WKWebView {
    public override func scrollWheel(with theEvent: NSEvent) {
        super.scrollWheel(with: theEvent)
    }
    public override var isOpaque: Bool {
        return false
    }
}

private let durgerKingBotIds: [Int64] = [5104055776, 2200339955]



public final class WebpageHeaderView : Control {
    
    public enum Left {
        case back
        case dismiss
    }
    
    private let titleContainer = View()
    
    private let titleView: TextView = TextView()
    private var statusView: PremiumStatusControl?
    private var verificationView: PremiumStatusControl?
    
    private let subtitleView: TextView = TextView()
    private var leftButton: Control?
    private let rightButton: ImageButton = ImageButton()
    private var leftCallback:(()->Void)?
    private var rightCallback:(()->ContextMenu?)?
    private var context: (any AccountContextProtocol)?
    private var bot: Peer?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        addSubview(titleContainer)
        titleContainer.addSubview(titleView)
        addSubview(subtitleView)
        addSubview(rightButton)
                
        subtitleView.userInteractionEnabled = false
        subtitleView.isSelectable = false
        
        forceMouseDownCanMoveWindow = true
        
        titleView.isSelectable = false
        titleView.userInteractionEnabled = false
        
        self.rightButton.contextMenu = { [weak self] in
            return self?.rightCallback?()
        }
        self.leftButton?.set(handler: { [weak self] _ in
            self?.leftCallback?()
        }, for: .Click)
        
        rightButton.autohighlight = false
        rightButton.scaleOnClick = true
    }
    
    public override var mouseDownCanMoveWindow: Bool {
        return true
    }
    
    private var prevLeft: Left?
    private var title: String = ""
    private var subtitle: String = ""
    
    public func update(title: String, subtitle: String, left: Left, animated: Bool, leftCallback: @escaping()->Void, contextMenu:@escaping()->ContextMenu?, context: (any AccountContextProtocol), bot: Peer?) {
        
        self.subtitle = subtitle
        self.title = title
        self.context = context
        self.bot = bot
        
        let prevLeft = self.prevLeft
        self.prevLeft = left

        self.leftCallback = leftCallback
        self.rightCallback = contextMenu
        
        let color: NSColor = self.backgroundColor.lightness > 0.8 ? NSColor(0x000000) : NSColor(0xffffff)
                
        titleView.update(TextViewLayout(.initialize(string: title, color: color, font: .medium(.title)), maximumNumberOfLines: 1))
        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        
        
        if let peer = bot, let control = PremiumStatusControl.control(peer, account: context.account, inlinePacksContext: context.inlinePacksContext, left: true, isSelected: false, cached: self.verificationView, animated: false) {
            self.titleContainer.addSubview(control)
            self.verificationView = control
        } else if let view = self.verificationView {
            performSubviewRemoval(view, animated: animated)
            self.verificationView = nil
        }

        if let peer = bot, let control = PremiumStatusControl.control(peer, account: context.account, inlinePacksContext: context.inlinePacksContext, left: false, isSelected: false, cached: self.statusView, animated: false) {
            
            self.titleContainer.addSubview(control)
            self.statusView = control
        } else if let view = self.statusView {
            performSubviewRemoval(view, animated: animated)
            self.statusView = nil
        }
        
        
        let secondColor = self.backgroundColor.lightness > 0.8 ? darkPalette.grayText : dayClassicPalette.grayText
                
        subtitleView.update(TextViewLayout(.initialize(string: subtitle, color: secondColor, font: .normal(.text)), maximumNumberOfLines: 1))
        
        rightButton.set(image: TelegramThemeHooks.shared.image(.iconChatActionsActive).precomposed(color), for: .Normal)
        rightButton.setGlassEffect(size: NSMakeSize(36, 36))
        rightButton.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        rightButton.setAccessibilityLabel(strings().voiceOverCommonMore)
        
        if prevLeft != left || prevLeft == nil || !animated {
            let previousBtn = self.leftButton
            let button: Control
        
            switch left {
            case .dismiss:
                let btn = ImageButton()
                btn.autohighlight = false
                btn.animates = false
                btn.set(image: TelegramThemeHooks.shared.image(.iconPipClose).precomposed(color), for: .Normal)
                btn.setGlassEffect(size: NSMakeSize(36, 36))
                btn.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
                btn.setAccessibilityLabel(strings().voiceOverCommonClose)
                button = btn
            case .back:
                let btn = TextButton()
                btn.autohighlight = false
                btn.animates = false
                btn.set(image: TelegramThemeHooks.shared.image(.iconChatNavigationBack).precomposed(color), for: .Normal)
                btn.set(text: strings().navigationBack, for: .Normal)
                btn.set(font: .normal(.title), for: .Normal)
                btn.set(color: color, for: .Normal)
                btn.sizeToFit()
                button = btn
            }
            button.scaleOnClick = true
            button.set(handler: { [weak self] _ in
                self?.leftCallback?()
            }, for: .Click)
            self.leftButton = button
            addSubview(button)
            if let previousBtn = previousBtn {
                performSubviewRemoval(previousBtn, animated: false, scale: false)
            }
            if animated && prevLeft != nil {
                button.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            }
        }
        
        needsLayout = true
    }
    
    public override var backgroundColor: NSColor {
        didSet {
            if let prevLeft = prevLeft, let leftCallback = leftCallback, let rightCallback = rightCallback, let context = self.context {
                self.update(title: self.title, subtitle: self.subtitle, left: prevLeft, animated: false, leftCallback: leftCallback, contextMenu: rightCallback, context: context, bot: self.bot)
            }
        }
    }
    
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
    }
    
    public override func layout() {
        super.layout()
        var additionalSize: CGFloat = 0
        additionalSize += rightButton.frame.width * 2
        rightButton.centerY(x: frame.width - rightButton.frame.width - 20)
        
        if let leftButton = leftButton {
            additionalSize += leftButton.frame.width * 2
            leftButton.centerY(x: 20)
        }
        
        let availableWidth = max(0, frame.width - 40 - additionalSize)
        let badgeWidth = WebAppTitleLayout.reservedWidth(verificationSize: verificationView?.frame.size, statusSize: statusView?.frame.size)
        titleView.resize(max(1, availableWidth - badgeWidth))
        subtitleView.resize(availableWidth)

        let titleLayout = WebAppTitleLayout(titleSize: titleView.frame.size, verificationSize: verificationView?.frame.size, statusSize: statusView?.frame.size)
        titleContainer.setFrameSize(titleLayout.size)
        
        let center = frame.midY
        titleContainer.centerX(y: center - titleContainer.frame.height - 1)
        subtitleView.centerX(y: center + 1)
        
        
        titleView.frame = titleLayout.titleFrame
        if let frame = titleLayout.verificationFrame {
            verificationView?.frame = frame
        }
        if let frame = titleLayout.statusFrame {
            statusView?.frame = frame
        }
        
        
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class WebpageView : View {
    private var indicator: NSView?
    
    
    fileprivate var _holder: WKWebView!
    private var fakeHolder = View()
    fileprivate var webview: NSView {
        if _holder == nil {
            return fakeHolder
        }
        return _holder
    }
    
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
    }
    
    public var placeholderIcon: (CGImage, Bool)?

    public override var mouseDownCanMoveWindow: Bool {
        return true
    }

    
    public var standalone: Bool = true
    public var state: WebpageModalState?
    
    public var mainButtonAction:(()->Void)?
    public var secondaryButtonAction:(()->Void)?

    private let loading: LinearProgressControl = LinearProgressControl(progressHeight: 2)

   
    private class MainButton : Control {
        
        public var state: WebpageModalState.ButtonState?
        
        private let textView: TextView = TextView()
        private var loading: InfiniteProgressView?
        private var shimmer: ShimmerEffectView?
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            
            addSubview(textView)
            textView.isEventLess = true
            textView.userInteractionEnabled = false
            textView.isSelectable = false
            
        }
        
        public func update(_ state: WebpageModalState.ButtonState, animated: Bool) {
            
            self.state = state
            
            let textLayout = TextViewLayout(.initialize(string: state.text, color: state.textColor, font: .medium(.text)), maximumNumberOfLines: 1, truncationType: .middle)
            textLayout.measure(width: frame.width - 60)
            textView.update(textLayout)
            setAccessibilityLabel(state.text)
            
            set(background: state.backgroundColor, for: .Normal)
            set(background: state.backgroundColor.darker(), for: .Highlight)
            
            if state.isLoading {
                let current: InfiniteProgressView
                if let view = self.loading {
                    current = view
                } else {
                    current = .init(color: state.textColor, lineWidth: 2)
                    current.setFrameSize(NSMakeSize(20, 20))
                    self.loading = current
                    addSubview(current)
                }
                current.progress = nil
            } else if let view = self.loading {
                performSubviewRemoval(view, animated: animated)
                self.loading = nil
            }
            
            self.textView.change(opacity: loading == nil ? 1 : 0, animated: animated)
            
            if state.isShining {
                let current: ShimmerEffectView
                if let view = self.shimmer {
                    current = view
                } else {
                    current = ShimmerEffectView()
                    addSubview(current)
                    self.shimmer = current
                    
                    
                }
                current.isStatic = true
                
            } else if let view = shimmer {
                performSubviewRemoval(view, animated: animated)
                self.shimmer = nil
            }
            
            needsLayout = true
        }
        
        public override func layout() {
            super.layout()
            textView.resize(frame.width - 60)
            updateLayout(self.frame.size, transition: .immediate)
        }
        
        public func updateLayout(_ size: NSSize, transition: ContainedViewLayoutTransition) {
            transition.updateFrame(view: textView, frame: textView.centerFrame())
            if let loading = self.loading {
                transition.updateFrame(view: loading, frame: loading.centerFrame())
            }
            
            if let current = self.shimmer {
                current.frame = size.bounds
                current.updateAbsoluteRect(size.bounds, within: size)
                current.update(backgroundColor: .clear, foregroundColor: .clear, shimmeringColor: NSColor.white.withAlphaComponent(0.3), shapes: [.roundedRect(rect: size.bounds, cornerRadius: size.bounds.height / 2)], horizontal: true, size: size.bounds.size)
            }
        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    
    private class ButtonsBlock: View {
        private var mainButton:MainButton?
        private var secondaryButton:MainButton?
        
        public var mainAction:(()->Void)?
        public var secondaryAction:(()->Void)?

        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            border = [.Top]
        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public func update(_ state: WebpageModalState, animated: Bool) {
            
            
            var animated = animated
            
            self.backgroundColor = state.bottomBarColor ?? theme.colors.grayForeground
            self.borderColor = state.backgroundColor
            
            let (mainRect, secondaryRect) = rects(position: state.secondary?.position ?? .bottom, size: frame.size)
            
            if let state = state.main, state.isVisible, let text = state.text, !text.isEmpty {
                let current: MainButton
                if let view = self.mainButton {
                    current = view
                } else {
                    current = .init(frame: mainRect)
                    self.mainButton = current
                    current.layer?.cornerRadius = 10
                    if animated {
                        current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    }
                    animated = false
                    current.setSingle(handler: { [weak self] _ in
                        self?.mainAction?()
                    }, for: .Click)
                }
                current.update(state, animated: animated)
                self.addSubview(current, positioned: .above, relativeTo: self.secondaryButton)

                
            } else if let view = self.mainButton {
                performSubviewRemoval(view, animated: animated)
                self.mainButton = nil
            }
            
            if let state = state.secondary, state.isVisible, let text = state.text, !text.isEmpty {
                let current: MainButton
                if let view = self.secondaryButton {
                    current = view
                } else {
                    current = .init(frame: secondaryRect)
                    self.secondaryButton = current
                    current.layer?.cornerRadius = 10
                    if animated {
                        current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    }
                    current.setSingle(handler: { [weak self] _ in
                        self?.secondaryAction?()
                    }, for: .Click)
                }
                self.addSubview(current, positioned: .below, relativeTo: self.mainButton)
                current.update(state, animated: animated)
            } else if let view = self.secondaryButton {
                performSubviewRemoval(view, animated: animated)
                self.secondaryButton = nil
            }
            
            self.updateLayout(frame.size, transition: animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate)
        }
        
        public func rects(position: WebpageModalState.ButtonState.Position, size: NSSize) -> (main: NSRect, secondary: NSRect) {
            let mainRect: NSRect
            let secondaryRect: NSRect
            switch position {
            case .top:
                secondaryRect = size.bounds.focusX(NSMakeSize(size.width - 20, 50), y: 10)
                mainRect = size.bounds.focusX(NSMakeSize(size.width - 20, 50), y: secondaryRect.maxY + 10)
            case .bottom:
                mainRect = size.bounds.focusX(NSMakeSize(size.width - 20, 50), y: 10)
                secondaryRect = size.bounds.focusX(NSMakeSize(size.width - 20, 50), y: mainRect.maxY + 10)
            case .left:
                secondaryRect = size.bounds.focusY(NSMakeSize(floorToScreenPixels((size.width - 30) / 2), 50), x: 10)
                mainRect = size.bounds.focusY(NSMakeSize(floorToScreenPixels((size.width - 30) / 2), 50), x: secondaryRect.maxX + 10)
            case .right:
                mainRect = size.bounds.focusY(NSMakeSize(floorToScreenPixels((size.width - 30) / 2), 50), x: 10)
                secondaryRect = size.bounds.focusY(NSMakeSize(floorToScreenPixels((size.width - 30) / 2), 50), x: mainRect.maxX + 10)
            }
            return (main: mainRect, secondary: secondaryRect)
        }
        
        public override func layout() {
            super.layout()
            self.updateLayout(self.frame.size, transition: .immediate)
        }
        
        public func updateLayout(_ size: NSSize, transition: ContainedViewLayoutTransition) {
            
            if let secondaryButton, let mainButton {
                let position = secondaryButton.state?.position ?? .bottom
                let (mainRect, secondaryRect) = self.rects(position: position, size: size)
                transition.updateFrame(view: secondaryButton, frame: secondaryRect)
                transition.updateFrame(view: mainButton, frame: mainRect)
                
            } else if let button = (self.mainButton ?? self.secondaryButton) {
                let rect = size.bounds.insetBy(dx: 10, dy: 10)
                transition.updateFrame(view: button, frame: rect)
                button.updateLayout(rect.size, transition: transition)
            }
        }
        
    }
    
    private var buttonsBlock: ButtonsBlock?
    
    private let headerView = WebpageHeaderView(frame: .zero)
    
    
    public required init(frame frameRect: NSRect, configuration: WKWebViewConfiguration!) {
        _holder = NoScrollWebView(frame: frameRect.size.bounds, configuration: configuration)
        super.init(frame: frameRect)
        addSubview(webview)
        addSubview(loading)
        addSubview(headerView)
        
        webview.setValue(false, forKey: "drawsBackground")

        webview.wantsLayer = true
                        
        updateLocalizationAndTheme(theme: theme)

    }
    
    public override var backgroundColor: NSColor {
        didSet {
            var bp = 0
            bp += 1
        }
    }
    
    
    public var _backgroundColor: NSColor? {
        didSet {
            updateLocalizationAndTheme(theme: theme)
        }
    }
    public var _bottomBarColor: NSColor? {
        didSet {
            updateLocalizationAndTheme(theme: theme)
        }
    }
    
    public var _headerColorKey: String? {
        didSet {
            updateLocalizationAndTheme(theme: theme)
        }
    }
    public var _headerColor: NSColor? {
        didSet {
            updateLocalizationAndTheme(theme: theme)
        }
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        loading.style = ControlStyle(foregroundColor: theme.colors.accent, backgroundColor: .clear, highlightColor: .clear)
        self.backgroundColor = state?.backgroundColor ?? theme.colors.background
        webview.background = state?.backgroundColor ?? theme.colors.background
        buttonsBlock?.background = _bottomBarColor ?? theme.colors.grayForeground
        
        if let key = _headerColorKey {
            if key == "bg_color" {
                self.headerView.backgroundColor = self.backgroundColor
            } else {
                self.headerView.backgroundColor = theme.colors.listBackground
            }
        } else if let color = _headerColor {
            self.headerView.backgroundColor = color
        } else {
            self.headerView.backgroundColor = self.backgroundColor
        }
    }
    
    public func load(url: String, preload: (TelegramMediaFile, (any AccountContextProtocol))?, animated: Bool) {
        if let url = URL(string: url) {
            _holder.load(URLRequest(url: url))
        }
        self.update(inProgress: true, preload: preload, animated: animated)
    }
    
    public func update(inProgress: Bool, preload: (TelegramMediaFile, (any AccountContextProtocol))?, animated: Bool) {
        self.webview._change(opacity: inProgress ? 0 : 1, animated: animated)
        
        
        if inProgress {
            
            if let placeholderIcon = placeholderIcon {
                let current: ImageView
                if let view = self.indicator as? ImageView {
                    current = view
                } else {
                    current = .init(frame: NSMakeRect(0, 0, 50, 50))
                    current.frame = focus(current.frame.size)
                    self.indicator = current
                    self.addSubview(current)
                }
                current.image = placeholderIcon.0

                if let animation = current.layer?.makeAnimation(from: NSNumber(value: 1.0), to: NSNumber(value: 0.2), keyPath: "opacity", timingFunction: .easeOut, duration: 2.0) {
                    animation.repeatCount = 1000
                    animation.autoreverses = true
                    
                    current.layer?.add(animation, forKey: "opacity")
                }
            } else if let preload = preload {
                let current: NSView
                if let view = self.indicator, view is BrowserStickerView {
                    current = view
                } else {
                    current = BrowserHooks.shared.makeStickerView(NSMakeRect(0, 0, 50, 50))
                    current.frame = focus(current.frame.size)
                    self.indicator = current
                    self.addSubview(current)
                }
                (current as? BrowserStickerView)?.updateBrowserSticker(file: preload.0, size: current.frame.size, context: preload.1, tint: theme.colors.grayText, animated: false)

                if let animation = current.layer?.makeAnimation(from: NSNumber(value: 1.0), to: NSNumber(value: 0.2), keyPath: "opacity", timingFunction: .easeOut, duration: 2.0) {
                    animation.repeatCount = 1000
                    animation.autoreverses = true
                    
                    current.layer?.add(animation, forKey: "opacity")
                }
            } else {
                let current: ProgressIndicator
                if let view = self.indicator as? ProgressIndicator {
                    current = view
                } else {
                    current = .init(frame: NSMakeRect(0, 0, 30, 30))
                    current.frame = focus(current.frame.size)
                    self.indicator = current
                    self.addSubview(current)
                }
                current.progressColor = theme.colors.text
            }
        } else if let view = self.indicator {
            performSubviewRemoval(view, animated: animated)
            self.indicator = nil
        }
        self.needsLayout = true
    }
    
    public func set(estimatedProgress: CGFloat?, animated: Bool) {
        if let estimatedProgress = estimatedProgress {
            if estimatedProgress == 0 || estimatedProgress == 1 {
                self.loading.change(opacity: 0, animated: animated)
            } else {
                self.loading.change(opacity: 1, animated: animated)
            }
            self.loading.set(progress: estimatedProgress, animated: animated)
        } else {
            self.loading.change(opacity: 0, animated: animated)
            self.loading.set(progress: 0, animated: animated)
        }
    }
    
    public func update(_ state: WebpageModalState, animated: Bool) {
        
        self.state = state
        
        if state.hasButton {
            let current: ButtonsBlock
            if let view = self.buttonsBlock {
                current = view
            } else {
                current = .init(frame: NSMakeRect(0, frame.height, frame.width, state.buttonsHeight))
                self.buttonsBlock = current
                self.addSubview(current)
                
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
            current.update(state, animated: animated)
            
            current.mainAction = { [weak self] in
                self?.mainButtonAction?()
            }
            current.secondaryAction = { [weak self] in
                self?.secondaryButtonAction?()
            }
        } else if let view = self.buttonsBlock {
            performSubviewRemoval(view, animated: animated)
            view.layer?.animatePosition(from: view.frame.origin, to: view.frame.origin.offset(dx: 0, dy: view.frame.height), removeOnCompletion: false)
            self.buttonsBlock = nil
        }
        self.updateLayout(frame.size, transition: animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate)
    }
    
    
    public func updateHeader(title: String, subtitle: String, left: WebpageHeaderView.Left, animated: Bool, leftCallback: @escaping()->Void, contextMenu:@escaping()->ContextMenu?, context: (any AccountContextProtocol), bot: Peer?) {
        self.headerView.update(title: title, subtitle: subtitle, left: left, animated: animated, leftCallback: leftCallback, contextMenu: contextMenu, context: context, bot: bot)
    }
    
    public override func layout() {
        super.layout()
        self.updateLayout(frame.size, transition: .immediate)
    }

    
    public func updateLayout(_ size: NSSize, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: self.headerView, frame: NSMakeRect(0, 0, size.width, standalone ? 50 : 0))
        if let buttonsBlock = buttonsBlock, let state = state {
            transition.updateFrame(view: buttonsBlock, frame: NSMakeRect(0, size.height - state.buttonsHeight, size.width, state.buttonsHeight))
            buttonsBlock.updateLayout(buttonsBlock.frame.size, transition: transition)
            self.webview.frame = NSMakeRect(0, self.headerView.frame.maxY, size.width, size.height - buttonsBlock.frame.height - self.headerView.frame.height)
        } else {
            self.webview.frame = NSMakeRect(0, self.headerView.frame.maxY, size.width, size.height - self.headerView.frame.height)
        }
        
        if let indicator = indicator {
            transition.updateFrame(view: indicator, frame: indicator.centerFrame())
        }
        transition.updateFrame(view: self.loading, frame: NSMakeRect(0, 0, size.width, 2))
        
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        _holder.stopLoading()
        _holder.loadHTMLString("", baseURL: nil)
        webview.removeFromSuperview()
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
}


public struct WebpageModalState : Equatable {
    
    public struct ButtonState : Equatable {
        public enum Priority {
            case main
            case secondary
        }
        public enum Position : String {
            case top
            case bottom
            case left
            case right
        }
        public var priority: Priority
        public var text: String?
        public var backgroundColor: NSColor
        public var textColor: NSColor
        public var isVisible: Bool
        public var isLoading: Bool
        public var isShining: Bool
        public var position: Position?
        public init(priority: Priority, text: String? = nil, backgroundColor: NSColor, textColor: NSColor, isVisible: Bool, isLoading: Bool, isShining: Bool, position: Position? = nil) {
            self.priority = priority
            self.text = text
            self.backgroundColor = backgroundColor
            self.textColor = textColor
            self.isVisible = isVisible
            self.isLoading = isLoading
            self.isShining = isShining
            self.position = position
        }
    }
    
    
    public var backgroundColor: NSColor?
    public var headerColor: NSColor?
    public var headerColorKey: String?
    public var bottomBarColor: NSColor?
    public var hasSettings: Bool = false
    public var isBackButton: Bool = false
    public var needConfirmation: Bool = false
    
    public var isLoading: Bool = false
    
    public var favicon: NSImage? = nil
    public var error: RequestWebViewError? = nil
    public var isSite: Bool = false
    public var title: String? = nil
    public var url: String?
    
    public var subtitle: String?
    
    public var peer: EnginePeer?
    
    public var main: ButtonState?
    public var secondary: ButtonState?
    
    public var buttonsHeight: CGFloat {
        if let secondary {
            switch secondary.position {
            case .top:
                return 130
            case .bottom:
                return 130
            case .left:
                return 70
            case .right:
                return 70
            case .none:
                return 70
            }
        } else {
            return 70
        }
    }
    
    public var hasButton: Bool {
        return main?.isVisible == true || secondary?.isVisible == true
    }
    public init(backgroundColor: NSColor? = nil, headerColor: NSColor? = nil, headerColorKey: String? = nil, bottomBarColor: NSColor? = nil, hasSettings: Bool = false, isBackButton: Bool = false, needConfirmation: Bool = false, isLoading: Bool = false, favicon: NSImage? = nil, error: RequestWebViewError? = nil, isSite: Bool = false, title: String? = nil, url: String? = nil, subtitle: String? = nil, peer: EnginePeer? = nil, main: ButtonState? = nil, secondary: ButtonState? = nil) {
        self.backgroundColor = backgroundColor
        self.headerColor = headerColor
        self.headerColorKey = headerColorKey
        self.bottomBarColor = bottomBarColor
        self.hasSettings = hasSettings
        self.isBackButton = isBackButton
        self.needConfirmation = needConfirmation
        self.isLoading = isLoading
        self.favicon = favicon
        self.error = error
        self.isSite = isSite
        self.title = title
        self.url = url
        self.subtitle = subtitle
        self.peer = peer
        self.main = main
        self.secondary = secondary
    }
}

public class WebpageModalController: ModalViewController, WKNavigationDelegate, WKUIDelegate, BrowserPage {
    private let invoiceAction = BrowserInvoiceAction()
    private let preparedShareAction = BrowserPreparedShareAction()
    private let locationAction = BrowserLocationAction()
    private let emojiPermissionAction = BrowserEmojiPermissionAction()
    private let emojiStatusAction = BrowserEmojiStatusAction()
    private var acceptsLocationRequests = true
    
    private let statePromise = ValuePromise<WebpageModalState>(WebpageModalState(), ignoreRepeated: true)
    private let stateValue = Atomic(value: WebpageModalState())
    private func updateState(_ f:(WebpageModalState) -> WebpageModalState) {
        statePromise.set(stateValue.modify (f))
    }
    
    public var externalState: Signal<WebpageModalState, NoError> {
        return statePromise.get()
    }
    
    public struct BotData {
        public let queryId: Int64?
        public let bot: Peer
        public let peerId: PeerId?
        public let buttonText: String
        public let keepAliveSignal: Signal<Never, KeepWebViewError>?
        public let sameOrigin: Bool
        public init(queryId: Int64?, bot: Peer, peerId: PeerId?, buttonText: String, keepAliveSignal: Signal<Never, KeepWebViewError>?, sameOrigin: Bool) {
            self.queryId = queryId
            self.bot = bot
            self.peerId = peerId
            self.buttonText = buttonText
            self.keepAliveSignal = keepAliveSignal
            self.sameOrigin = sameOrigin
        }
    }
    
    
    public enum RequestData {
        case simple(url: String, botdata: BotData, source: RequestSimpleWebViewSource)
        case normal(url: String, botdata: BotData)
        
        public var url: String {
            switch self {
            case let .simple(url, _, _):
                return url
            case let .normal(url, _):
                return url
            }
        }
        
        public var bot: Peer {
            switch self {
            case let .simple(_, bot, _):
                return bot.bot
            case let .normal(_, bot):
                return bot.bot
            }
        }
        public var buttonText: String {
            switch self {
            case let .simple(_, botdata, _):
                return botdata.buttonText
            case let .normal(_, botdata):
                return botdata.buttonText
            }
        }
        public var isInline: Bool {
            switch self {
            case let .simple(_, _, source):
                switch source {
                case .inline:
                    return true
                default:
                    return false
                }
            case .normal:
                return false
            }
        }
        public var sameOrigin: Bool {
            switch self {
            case let .simple(_, botdata, _):
                return botdata.sameOrigin
            case let .normal(_, botdata):
                return botdata.sameOrigin
            }
        }
    }
    
    public private(set) var url:String
    private let context:(any AccountContextProtocol)
    private var effectiveSize: NSSize?
    private var data: BotData?
    private var requestData: RequestData?
    private var trustedOrigin: String?
    private var counter: Int = 0
    private let title: String
    private let thumbFile: TelegramMediaFile?
    private var browser: BrowserLinkManager? = nil

    private var keepAliveDisposable: Disposable?
    private let installedBotsDisposable = MetaDisposable()
    private let requestWebDisposable = MetaDisposable()
    private let placeholderDisposable = MetaDisposable()
    private var iconDisposable: Disposable?
    
    private var installedBots:[PeerId] = []
    
    private let laContext = LAContext()

    
    private var needCloseConfirmation = false {
        didSet {
            updateState { current in
                var current = current
                current.needConfirmation = needCloseConfirmation
                return current
            }
        }
    }
    
    
    private var clickCount: Int = 0
    private var lastTouchTimestamp: CFTimeInterval?

    private var isWhiteListedBot: Bool {
        guard let botId = self.requestData?.bot.id else {
            return false
        }
        if let whiteListedBots = context.appConfiguration.data?["whitelisted_bots"] as? [Double] {
            let rawBotId = botId.id._internalGetInt64Value()
            for bot in whiteListedBots {
                if Int64(bot) == rawBotId {
                    return true
                }
            }
        }
        return false
    }
    
    private var _backgroundColor: NSColor? {
        didSet {
            genericView._backgroundColor = .clear
            updateState { current in
                var current = current
                current.backgroundColor = _backgroundColor
                return current
            }
        }
    }
    
    private var _bottomBarColor: NSColor? {
        didSet {
            genericView._bottomBarColor = _bottomBarColor
            updateState { current in
                var current = current
                current.bottomBarColor = _bottomBarColor
                return current
            }
        }
    }

    
    private var _headerColorKey: String? {
        didSet {
            genericView._headerColorKey = _headerColorKey
            updateState { current in
                var current = current
                current.headerColorKey = _headerColorKey
                return current
            }
        }
    }
    private var _headerColor: NSColor? {
        didSet {
            genericView._headerColor = _headerColor
            updateState { current in
                var current = current
                current.headerColor = _headerColor
                return current
            }
        }
    }
    
    private let apperanceDisposable = MetaDisposable()
    
    private var botPeer: Peer? = nil
    
    public var bot: Peer? {
        return self.requestData?.bot ?? botPeer ?? data?.bot
    }
    
    private var biometryState: TelegramBotBiometricsState? = TelegramBotBiometricsState.create() {
        didSet {
            if let biometryState, let bot = requestData?.bot {
                context.engine.peers.updateBotBiometricsState(peerId: bot.id, update: { _ in
                    return biometryState
                })
            }
        }
    }
    private var biometryDisposable: Disposable?
    private let stateDisposable = MetaDisposable()
    private let backDisposable = MetaDisposable()
    
    private let settings: BotAppSettings?
    
    public init(context: (any AccountContextProtocol), url: String, title: String, effectiveSize: NSSize? = nil, requestData: RequestData? = nil, thumbFile: TelegramMediaFile? = nil, botPeer: Peer? = nil, fromMenu: Bool? = nil, hasSettings: Bool = false, browser: BrowserLinkManager? = nil, settings: BotAppSettings? = nil) {
        self.url = url
        self.requestData = requestData
        self.data = nil
        self.hasSettings = hasSettings
        self._fromMenu = fromMenu
        self.browser = browser
        self.context = context
        self.title = title
        self.effectiveSize = effectiveSize
        self.thumbFile = thumbFile
        self.botPeer = botPeer
        self.settings = settings
        
        
        super.init(frame: NSMakeRect(0,0,380,450))
        
        if let settings {
            let isDark = theme.colors.isDark
            self.updateState { current in
                var current = current
                current.backgroundColor = isDark ? settings.backgroundDarkColor.flatMap { NSColor(rgb: UInt32($0)) } : settings.backgroundColor.flatMap { NSColor(rgb: UInt32($0)) }
                current.headerColor = isDark ? settings.headerDarkColor.flatMap { NSColor(rgb: UInt32($0)) } : settings.headerColor.flatMap { NSColor(rgb: UInt32($0)) }
                return current
            }
        }
    }
    
    private let _fromMenu: Bool?
    
    public var fromMenu: Bool {
        if let _fromMenu {
            return _fromMenu
        }
        return false
    }
    
    private var preloadData: (TelegramMediaFile, (any AccountContextProtocol))? {
        if let thumbFile = self.thumbFile {
            return (thumbFile, context)
        } else {
            return nil
        }
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        genericView.update(inProgress: false, preload: self.preloadData, animated: true)
    }
    
    public override var dynamicSize:Bool {
        return true
    }
    
    public override func viewClass() -> AnyClass {
        return WebpageView.self
    }
    
    public var safeInsets: NSEdgeInsets {
        return NSEdgeInsets(top: 50, left: 0, bottom: 50, right: 50)
    }
    
    public override func initializer() -> NSView {
        
        let js = "var TelegramWebviewProxyProto = function() {}; " +
        "TelegramWebviewProxyProto.prototype.postEvent = function(eventName, eventData) { " +
        "window.webkit.messageHandlers.performAction.postMessage({'eventName': eventName, 'eventData': eventData}); " +
        "}; " +
        "var TelegramWebviewProxy = new TelegramWebviewProxyProto();"
        
        let selectionSource = "var css = '*{-webkit-touch-callout:none;} :not(input):not(textarea):not([\"contenteditable\"=\"true\"]){-webkit-user-select:none;}';"
                + " var head = document.head || document.getElementsByTagName('head')[0];"
                + " var style = document.createElement('style'); style.type = 'text/css';" +
                " style.appendChild(document.createTextNode(css)); head.appendChild(style);"


        let configuration = WKWebViewConfiguration()
        let userController = WKUserContentController()
        
        if #available(macOS 14.0, *) {
            if !FastSettings.isDefaultAccount(context.account.id.int64) {
                if let uuid = FastSettings.getUUID(context.account.id.int64) {
                    let store = WKWebsiteDataStore(forIdentifier: uuid)
                    configuration.websiteDataStore = store
                }
            }
        }
       
        

        if FastSettings.debugWebApp {
            configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        }
        
        if let requestData, requestData.sameOrigin {
            self.trustedOrigin = URL(string: requestData.url).flatMap { webAppOrigin(url: $0) }
            if let trustedOrigin = self.trustedOrigin {
                let userScript = WKUserScript(source: webAppSecuredEventProxySource(trustedOrigin: trustedOrigin), injectionTime: .atDocumentStart, forMainFrameOnly: true)
                userController.addUserScript(userScript)
            }
        } else {
            let userScript = WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            userController.addUserScript(userScript)
        }
        
        let selectionScript = WKUserScript(source: selectionSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        userController.addUserScript(selectionScript)

        

        userController.add(WeakScriptMessageHandler { [weak self] message in
            if let strongSelf = self {
                strongSelf.handleScriptMessage(message)
            }
        }, name: "performAction")

        configuration.userContentController = userController
        
        return WebpageView(frame: self._frameRect, configuration: configuration)
    }
    
    private var genericView: WebpageView {
        return self.view as! WebpageView
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        window?.set(mouseHandler: { [weak self] _ in
            guard let strongSelf = self else {
                return .rejected
            }
            strongSelf.clickCount += 1
            strongSelf.lastTouchTimestamp = CACurrentMediaTime()
            delay(10, closure: { [weak strongSelf] in
                strongSelf?.clickCount = 0
            })
            return .rejected
        }, with: self, for: .leftMouseDown, priority: .supreme)
        
        window?.set(escape: { [weak self] _ -> KeyHandlerResult in
            if self?.escapeKeyAction() == .rejected {
                if self?.closable == true {
                    self?.close()
                }
            }
            return .invoked
        }, with: self, priority: responderPriority)
        
        apperanceDisposable.set(appearanceSignal.start(next: { [weak self] appearance in
            self?.updateLocalizationAndTheme(theme: appearance.presentation)
        }))
    }
    
    public override var window: Window? {
        return browser?.window ?? _window ?? view.window as? Window
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        acceptsLocationRequests = true
        super.viewWillAppear(animated)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        acceptsLocationRequests = false
        lastTouchTimestamp = nil
        locationAction.reset()
        emojiPermissionAction.reset()
        emojiStatusAction.reset()
        super.viewWillDisappear(animated)
        window?.removeObserver(for: self)
        apperanceDisposable.set(nil)
    }
    
    public override func viewDidResized(_ size: NSSize) {
        super.viewDidResized(size)
        
        updateSafeInsets()
       
    }
    
    public func updateSafeInsets() {
        let isFullscreen = window?.isFullScreen ?? false
        
        let contentInsetsData = "{top:\(isFullscreen ? 60 : 0), bottom:0.0, left:0.0, right:0.0}"
        sendEvent(name: "safe_area_changed", data: contentInsetsData)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        self.window?.onToggleFullScreen = { [weak self] fullscreen in
            let paramsString = "{is_fullscreen: \( fullscreen ? "true" : "false" )}"
            self?.sendEvent(name: "fullscreen_changed", data: paramsString)

        }
        
        if let data = self.settings?.placeholderData, let svg = generateStickerPlaceholderImage(data: data, size: NSMakeSize(50, 50), scale: System.backingScale, imageSize: NSMakeSize(512, 512), backgroundColor: nil, foregroundColor: theme.colors.grayText) {
            self.genericView.placeholderIcon = (svg, true)
        }
        
        if let peerId = bot?.id {
            FastSettings.markWebAppAsConfirmed(peerId)
        }
        
        genericView.mainButtonAction = { [weak self] in
            self?.pressMainButton()
        }
        genericView.secondaryButtonAction = { [weak self] in
            self?.pressSecondaryButton()
        }
        genericView.standalone = self.browser == nil
        
        
        genericView._holder.background = .clear
        genericView._holder.uiDelegate = self
        genericView._holder.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: [], context: nil)
        genericView._holder.navigationDelegate = self
        genericView.update(inProgress: true, preload: self.preloadData, animated: false)
        
        updateLocalizationAndTheme(theme: theme)
        
        readyOnce()
        let context = self.context
        
        if let requestData = requestData {
            switch requestData {
            case let .simple(url, result, _), let .normal(url, result):
                self.url = url
                self.genericView.load(url: url, preload: self.preloadData, animated: true)
                if let keepAliveSignal = result.keepAliveSignal {
                    self.keepAliveDisposable = (keepAliveSignal |> deliverOnMainQueue).start(error: { [weak self] _ in
                        self?.close()
                    }, completed: { [weak self] in
                        self?.close()
                    })
                }
            }
        } else {
            self.genericView.load(url: url, preload: self.preloadData, animated: true)
        }
        
        let bots = self.context.engine.messages.attachMenuBots() |> deliverOnMainQueue
        installedBotsDisposable.set(bots.start(next: { [weak self] items in
            self?.installedBots = items.filter { $0.flags.contains(.showInAttachMenu) }.map { $0.peer.id }
        }))
                
        guard let botPeer = requestData?.bot else {
            return
        }
        let biometrySignal = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.BotBiometricsState(id: botPeer.id)) |> deliverOnMainQueue
        biometryDisposable = biometrySignal.start(next: { [weak self] result in
            self?.biometryState = result
        })
        
        let signal = statePromise.get() |> deliverOnMainQueue
        
        let first = Atomic(value: true)
        self.stateDisposable.set(signal.startStrict(next: { [weak self] state in
            self?.genericView.update(state, animated: !first.swap(false))
        }))

    }
    
    @available(macOS 10.12, *)
    public func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {

        let allowDirectories: Bool
        if #available(macOS 10.13.4, *) {
            allowDirectories = parameters.allowsDirectories
        } else {
            allowDirectories = true
        }
        
        guard let window = self.window else {
            completionHandler(nil)
            return
        }
        
        filePanel(with: nil, allowMultiple: parameters.allowsMultipleSelection, canChooseDirectories: allowDirectories, for: window, completion: { files in
            completionHandler(files?.map { URL(fileURLWithPath: $0) })
        })
    }
    
    public func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        
        guard let window = self.window else {
            completionHandler(false)
            return
        }
        
        var completion: ((Bool) -> Void)? = completionHandler
        let complete: (Bool) -> Void = { value in
            let handler = completion
            completion = nil
            handler?(value)
        }
        verifyAlert_button(for: window, header: requestData?.bot.displayTitle ?? appName, information: message, successHandler: { _ in
            complete(true)
        }, cancelHandler: {
            complete(false)
        }, onDeinit: {
            complete(false)
        })
    }
    
    public func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        
        guard let window = self.window else {
            completionHandler()
            return
        }
        
        alert(for: window, header: requestData?.bot.displayTitle ?? appName, info: message, onDeinit: completionHandler)
    }


    
    @available(macOS 12.0, *)
    public func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping(WKPermissionDecision)->Void) {
        
        _ = self.context
        var completion: ((WKPermissionDecision) -> Void)? = decisionHandler
        let complete: (WKPermissionDecision) -> Void = { decision in
            let handler = completion
            completion = nil
            handler?(decision)
        }
        
        let request:(Peer)->Void = { [weak self] peer in
            if FastSettings.botAccessTo(type, peerId: peer.id) {
                complete(.grant)
            } else {
                let runConfirm:()->Void = {
                    let info: String
                    switch type {
                    case .camera:
                        info = strings().webAppAccessVideo(peer.displayTitle)
                    case .microphone:
                        info = strings().webAppAccessAudio(peer.displayTitle)
                    case .cameraAndMicrophone:
                        info = strings().webAppAccessAudioVideo(peer.displayTitle)
                    @unknown default:
                        info = "unknown"
                    }
                    if let window = self?.window {
                        verifyAlert_button(for: window, information: info, ok: strings().webAppAccessAllow, successHandler: { _ in
                            complete(.grant)
                            FastSettings.allowBotAccessTo(type, peerId: peer.id)
                        }, cancelHandler: {
                            complete(.deny)
                        }, onDeinit: {
                            complete(.deny)
                        })
                    } else {
                        complete(.deny)
                    }
                }
                switch type {
                case .camera:
                    _ = requestMediaPermission(.video).start(next: { value in
                        if value {
                            runConfirm()
                        } else {
                            complete(.deny)
                        }
                    })
                case .microphone:
                    _ = requestMediaPermission(.audio).start(next: { value in
                        if value {
                            runConfirm()
                        } else {
                            complete(.deny)
                        }
                    })
                case .cameraAndMicrophone:
                    _ = combineLatest(requestMediaPermission(.video), requestMediaPermission(.audio)).start(next: { audio, video in
                        if audio && video {
                            runConfirm()
                        } else {
                            complete(.deny)
                        }
                    })
                @unknown default:
                    if let window = self?.window {
                        alert(for: window, info: strings().unknownError)
                    }
                    complete(.deny)
                }
            }
        }
        
        if let requestData = self.requestData {
            request(requestData.bot)
        } else {
            return complete(.deny)
        }
        
    }
    
    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            if self.bot != nil, url.absoluteString == "tg://resolve" {
                return nil
            }
            BrowserHooks.shared.openLink(context, url.absoluteString, self.window, true, { [weak self] in
                self?.closeAnyway()
            })
        }
        return nil
    }
    
    

    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.sourceFrame.isMainFrame, navigationAction.targetFrame?.isMainFrame == true,
           let url = navigationAction.request.url {
            if self.bot != nil, url.absoluteString == "tg://resolve" {
                decisionHandler(.cancel)
                return
            }
            if case .tonConnect = BrowserHooks.shared.classifyLink(context, url.absoluteString) {
                decisionHandler(.cancel)
                BrowserHooks.shared.openLink(context, url.absoluteString, self.window, true, {})
                return
            }
        }
        if navigationAction.navigationType == .linkActivated {
            if let url = navigationAction.request.url {
                if let currentUrl = URL(string: self.url) {
                    if webAppOrigin(url: currentUrl) == webAppOrigin(url: url) || url.scheme == "tg" {
                        decisionHandler(.allow)
                        return
                    }
                }
                
                let context = self.context
                                
                BrowserHooks.shared.openLink(context, url.absoluteString, self.window, true, { [weak self] in
                    self?.closeAnyway()
                })
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        } else {
            decisionHandler(.allow)
        }
    }
    
    public override func measure(size: NSSize) {
        if browser == nil  {
            let s = NSMakeSize(size.width + 20, size.height + 20)
            let size = NSMakeSize(420, min(420 + 420 * 0.6, s.height - 80))
            let rect = size.bounds.insetBy(dx: 10, dy: 10)
            self.genericView.frame = rect
            self.genericView.updateLayout(rect.size, transition: .immediate)
        }
    }
    
    
    deinit {
        placeholderDisposable.dispose()
        keepAliveDisposable?.dispose()
        installedBotsDisposable.dispose()
        requestWebDisposable.dispose()
        iconDisposable?.dispose()
        biometryDisposable?.dispose()
        apperanceDisposable.dispose()
        stateDisposable.dispose()
        backDisposable.dispose()
        if isLoaded() {
            self.genericView._holder.removeObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress))
        }
    }
    
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "estimatedProgress" {
            self.genericView.set(estimatedProgress: CGFloat(genericView._holder.estimatedProgress), animated: true)
        }
    }
    
    private var isBackButton: Bool = false {
        didSet {
            let isBackButton = isBackButton
            backDisposable.set(delaySignal(0.05).startStrict(completed: { [weak self] in
                self?.updateLocalizationAndTheme(theme: theme)
                self?.updateState { current in
                    var current = current
                    current.isBackButton = isBackButton
                    return current
                }
            }))
            
        }
    }
    private var hasSettings: Bool = false {
        didSet {
            updateState { current in
                var current = current
                current.hasSettings = hasSettings
                return current
            }
        }
    }

    fileprivate func sendClipboardTextEvent(requestId: String, fillData: Bool) {
        var dict: [String: Any] = ["req_id": requestId]
        if fillData {
            dict["data"] = NSPasteboard.general.string(forType: .string) ?? ""
        }
        sendEvent(name: "clipboard_text_received", data: JSON(dictionary: dict)?.string)
    }

    
    private func isTrustedMainFrameMessage(_ message: WKScriptMessage) -> Bool {
        guard message.frameInfo.isMainFrame else {
            return false
        }
        guard self.requestData?.sameOrigin == true else {
            return true
        }
        guard let trustedOrigin = self.trustedOrigin else {
            return false
        }
        guard webAppOrigin(securityOrigin: message.frameInfo.securityOrigin) == trustedOrigin else {
            return false
        }
        if let currentUrl = self.genericView._holder.url, let currentOrigin = webAppOrigin(url: currentUrl), currentOrigin != trustedOrigin {
            return false
        }
        return true
    }

    private func handleScriptMessage(_ message: WKScriptMessage) {

        let context = self.context

        guard let window = self.window else {
            return
        }
        guard isTrustedMainFrameMessage(message) else {
            return
        }

        guard let body = message.body as? [String: Any] else {
            return
        }
        
        guard let eventName = body["eventName"] as? String else {
            return
        }
        
        let eventData = (body["eventData"] as? String)?.data(using: .utf8)
        let json = try? JSONSerialization.jsonObject(with: eventData ?? Foundation.Data(), options: []) as? [String: Any]


        
        switch eventName {
        case "web_app_data_send":
            self.needCloseConfirmation = false
            if let eventData = body["eventData"] as? String {
                if let requestData = requestData {
                    switch requestData {
                    case .simple:
                        self.handleSendData(data: eventData)
                    default:
                        break
                    }
                }
            }
        case "web_app_read_text_from_clipboard":
            if let json = json, let requestId = json["req_id"] as? String {
                let botId = self.requestData?.bot.id
                let isAttachMenu = self.fromMenu
                let isWhiteListedBot = self.isWhiteListedBot

                let _ = (context.engine.messages.attachMenuBots()
                |> take(1)
                |> deliverOnMainQueue).start(next: { [weak self] attachMenuBots in
                    guard let self else {
                        return
                    }
                    let currentTimestamp = CACurrentMediaTime()
                    var fillData = false

                    let attachMenuBot = attachMenuBots.first(where: { bot in
                        guard let botId = botId else {
                            return false
                        }
                        return bot.peer.id == botId && !bot.flags.contains(.notActivated)
                    })

                    if isAttachMenu || attachMenuBot != nil || isWhiteListedBot {
                        if let lastTouchTimestamp = self.lastTouchTimestamp, currentTimestamp < lastTouchTimestamp + 10.0 {
                            self.lastTouchTimestamp = nil
                            fillData = true
                        }
                    }

                    self.sendClipboardTextEvent(requestId: requestId, fillData: fillData)
                })
            }

        case "web_app_ready":
            delay(0.1, closure: { [weak self] in
                self?.webAppReady()
            })
        case "web_app_switch_inline_query":
            if let data = self.bot {
                if let json = json, let query = json["query"] as? String {
                    let address = (data.addressName ?? "")
                    let inputQuery = "@\(address)" + " " + query

                    if let chatTypes = json["chat_types"] as? [String], !chatTypes.isEmpty {
                        BrowserHooks.shared.shareInlineQuery(context, inputQuery, chatTypes, nil, {})
                        self.needCloseConfirmation = false
                        self.close()
                    } else {
                        self.needCloseConfirmation = false
                        self.close()
                        BrowserHooks.shared.shareInlineQuery(context, inputQuery, nil, data.id, {})
                    }
                }
            }
        case "web_app_setup_main_button":
            if let eventData = (body["eventData"] as? String)?.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: eventData, options: []) as? [String: Any] {
                if let isVisible = json["is_visible"] as? Bool {
                    let text = json["text"] as? String
                    let backgroundColorString = json["color"] as? String
                    let backgroundColor = backgroundColorString.flatMap({ NSColor(hexString: $0) }) ?? theme.colors.accent
                    let textColorString = json["text_color"] as? String
                    let textColor = textColorString.flatMap({ NSColor(hexString: $0) }) ?? theme.colors.underSelectedColor
                    
                    let isLoading = json["is_progress_visible"] as? Bool
                    let isShining = json["has_shine_effect"] as? Bool ?? false

                    let state = WebpageModalState.ButtonState(priority: .main, text: text, backgroundColor: backgroundColor, textColor: textColor, isVisible: isVisible, isLoading: isLoading ?? false, isShining: isShining)
                    self.updateState { current in
                        var current = current
                        current.main = state
                        return current
                    }
                }
            }
            self.updateSize()
        case "web_app_setup_secondary_button":
            if let eventData = (body["eventData"] as? String)?.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: eventData, options: []) as? [String: Any] {
                if let isVisible = json["is_visible"] as? Bool {
                    let text = json["text"] as? String
                    let backgroundColorString = json["color"] as? String
                    let backgroundColor = backgroundColorString.flatMap({ NSColor(hexString: $0) }) ?? theme.colors.accent
                    let textColorString = json["text_color"] as? String
                    let textColor = textColorString.flatMap({ NSColor(hexString: $0) }) ?? theme.colors.underSelectedColor
                    
                    let isLoading = json["is_progress_visible"] as? Bool
                    let isShining = json["has_shine_effect"] as? Bool ?? false
                    let position = (json["position"] as? String).flatMap { WebpageModalState.ButtonState.Position(rawValue: $0) }

                    let state = WebpageModalState.ButtonState(priority: .secondary, text: text, backgroundColor: backgroundColor, textColor: textColor, isVisible: isVisible, isLoading: isLoading ?? false, isShining: isShining, position: position)
                    self.updateState { current in
                        var current = current
                        current.secondary = state
                        return current
                    }
                }
            }
            self.updateSize()
        case "web_app_request_viewport":
            self.updateSize()
        case "web_app_expand":
            break
        case "web_app_close":
            self.closeAnyway()
        case "web_app_open_scan_qr_popup":
            alert(for: window, info: strings().webAppQrIsNotSupported)
        case "web_app_setup_closing_behavior":
            if let json = json, let need_confirmation = json["need_confirmation"] as? Bool {
                self.needCloseConfirmation = need_confirmation
            } else {
                self.needCloseConfirmation = false
            }
        case "web_app_open_popup":
            if let json = json {
                let alert:NSAlert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = (json["title"] as? String) ?? appName
                alert.informativeText = (json["message"] as? String) ?? ""
                alert.window.appearance = theme.appearance
                let buttons = json["buttons"] as? Array<[NSString : Any]>
                if let buttons = buttons {
                    for button in buttons {
                        if (button["type"] as? String) == "default" {
                            alert.addButton(withTitle: button["text"] as? String ?? "")
                        } else if (button["type"] as? String) == "ok" {
                            alert.addButton(withTitle: strings().alertOK)
                        } else if (button["type"] as? String) == "close" {
                            alert.addButton(withTitle: strings().navigationClose)
                        } else if (button["type"]  as? String) == "cancel" {
                            alert.addButton(withTitle: strings().alertCancel)
                        } else if (button["type"]  as? String) == "destructive" {
                            alert.addButton(withTitle: button["text"] as? String ?? "")
                        }
                    }
                }
                if !alert.buttons.isEmpty {
                    Analytics.shared.screens.showStandalone(.botMiniAppPopup, owner: alert)
                    alert.beginSheetModal(for: window, completionHandler: { [weak self] response in
                        Analytics.shared.screens.hideStandalone(owner: alert)
                        let index = response.rawValue - 1000
                        if let id = buttons?[index]["id"] as? String {
                            self?.poupDidClose(id)
                        }
                    })
                }

            }
        case "web_app_open_link":
            if clickCount > 0 {
                if let eventData = (body["eventData"] as? String)?.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: eventData, options: []) as? [String: Any] {
                    if let url = json["url"] as? String {
                        
                        let tryInstantView = json["try_instant_view"] as? Bool ?? false
                        if tryInstantView {
                            let signal = showModalProgress(signal: BrowserHooks.shared.resolveInstantView(context, url), for: window)
                            
                            let _ = signal.start(next: { [weak self] webPage in
                                guard let strongSelf = self else {
                                    return
                                }
                                if let webPage = webPage {
                                    strongSelf.browser?.open(.instantView(url: url, webPage: webPage, anchor: nil))
                                } else {
                                    BrowserHooks.shared.openLink(context, url, strongSelf.window, false, {})
                                }
                            })
                        } else {
                            BrowserHooks.shared.openLink(context, url, self.window, false, {})
                        }
                    }
                }
            }
            clickCount = 0
        case "web_app_open_tg_link":
            if let eventData = (body["eventData"] as? String)?.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: eventData, options: []) as? [String: Any] {
                if let path_full = json["path_full"] as? String {
                    
                    BrowserHooks.shared.openLink(context, context.meUrlPrefix + "\(path_full.hasPrefix("/") ? String(path_full.dropFirst()) : path_full)", self.window, false, { [weak self] in
                        self?.closeAnyway()
                    })
                    
                }
            }
        case "web_app_setup_back_button":
            if let eventData = (body["eventData"] as? String)?.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: eventData, options: []) as? [String: Any] {
                if let isVisible = json["is_visible"] as? Bool {
                    self.isBackButton = isVisible
                }
            }
        case "web_app_setup_settings_button":
            if let eventData = (body["eventData"] as? String)?.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: eventData, options: []) as? [String: Any] {
                if let isVisible = json["is_visible"] as? Bool {
                    self.hasSettings = isVisible
                }
            }
        case "web_app_open_invoice":
            if let slug = json?["slug"] as? String {
                let origin = analyticsContext ?? Analytics.shared.unresolvedContext()
                invoiceAction.open(context: context, slug: slug, window: window, analyticsContext: origin, canPresent: { [weak self] in
                    self?.window === window
                }, completion: { [weak self] status in
                    let data: JSON = ["slug": slug, "status": status]
                    self?.sendEvent(name: "invoice_closed", data: data.string)
                })
            }
        case "web_app_set_background_color":
            if let json = json, let colorValue = json["color"] as? String, let color = NSColor(hexString: colorValue) {
                self._backgroundColor = color
            }
        case "web_app_set_header_color":
            if let json = json, let colorKey = json["color_key"] as? String, ["bg_color", "secondary_bg_color"].contains(colorKey) {
                self._headerColorKey = colorKey
                self._headerColor = nil
            } else if let json = json, let color = json["color"] as? String {
                self._headerColor = NSColor(hexString: color)
                self._headerColorKey = nil
            }
        case "web_app_set_bottom_bar_color":
            if let json = json, let colorValue = json["color"] as? String, let color = NSColor(hexString: colorValue) {
                self._bottomBarColor = color
            }
        case "web_app_request_write_access":
            self.requestWriteAccess()
        case "web_app_request_phone":
            self.shareAccountContact()
        case "web_app_invoke_custom_method":
            if let json = json, let requestId = json["req_id"] as? String, let method = json["method"] as? String, let params = json["params"] {
                var paramsString: String?
                if let string = params as? String {
                    paramsString = string
                } else if let data1 = try? JSONSerialization.data(withJSONObject: params, options: []), let convertedString = String(data: data1, encoding: String.Encoding.utf8) {
                    paramsString = convertedString
                }
                self.invokeCustomMethod(requestId: requestId, method: method, params: paramsString ?? "{}")
            }
        case "web_app_biometry_get_info":
            guard let biometryState else {
                return
            }
            self.sendBiometricInfo(biometryState: biometryState)
        case "web_app_biometry_request_access":
            guard let botPeer = requestData?.bot, var biometryState = self.biometryState else {
                return
            }
            var string: String
            if laContext.biometricTypeString == "finger" {
                string = strings().webAppBiometryConfirmTouchId(botPeer.displayTitle)
            } else {
                string = strings().webAppBiometryConfirmFaceId(botPeer.displayTitle)
            }
            
            if let json = json, let reason = json["reason"] as? String {
                string += "\n\n" + reason
            }
            
            let accountId = context.peerId
            
            if biometryState.accessGranted {
                self.sendBiometricInfo(biometryState: biometryState)
                return
            }
            
            verifyAlert(for: window, information: string, ok: strings().webAppAccessAllow, cancel: strings().webAppAccessDeny, successHandler: { [weak self] _ in
                FastSettings.allowBotAccessToBiometric(peerId: botPeer.id, accountId: accountId)
                biometryState.accessGranted = true
                biometryState.accessRequested = true
                self?.sendBiometricInfo(biometryState: biometryState)
            }, cancelHandler: { [weak self] in
                biometryState.accessGranted = false
                biometryState.accessRequested = true
                self?.sendBiometricInfo(biometryState: biometryState)
            })
        case "web_app_biometry_update_token":
            
            guard let botPeer = requestData?.bot, var biometryState = self.biometryState else {
                return
            }
            
            _ = context.peerId
            
            if let json = json, let token = json["token"] as? String {
                
                let sacObject =
                        SecAccessControlCreateWithFlags(kCFAllocatorDefault,
                                            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                                            .userPresence,
                                            nil);

                let secQuery: NSMutableDictionary = [
                    kSecClass: kSecClassGenericPassword,
                    kSecAttrAccessControl: sacObject!,
                    kSecAttrService: "TelegramMiniApp",
                    kSecAttrAccount: "bot_id_\(botPeer.id.toInt64())"
                ];
                
                

                if token.isEmpty {
                    let resultCode = SecItemDelete(secQuery)
                    let status = resultCode == errSecSuccess ? "removed" : "failed"
                    sendEvent(name: "biometry_token_updated", data: "{status: \"\(status)\"}")
                    biometryState.opaqueToken = nil
                } else {
                    let tokenData = token.data(using: .utf8)!
                    secQuery[kSecValueData] = tokenData
                    let resultCode = SecItemAdd(secQuery as CFDictionary, nil);
                    let status = resultCode == errSecSuccess || resultCode == errSecDuplicateItem ? "updated" : "failed"
                    biometryState.opaqueToken = .init(publicKey: Data(), data: Data())
                    sendEvent(name: "biometry_token_updated", data: "{status: \"\(status)\"}")
                }
                self.sendBiometricInfo(biometryState: biometryState)
            }
        case "web_app_biometry_request_auth":
            
            guard let botPeer = requestData?.bot, var biometryState = self.biometryState else {
                return
            }
            
            let sacObject =
                    SecAccessControlCreateWithFlags(kCFAllocatorDefault,
                                        kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                                        .userPresence,
                                        nil);

            let secQuery: NSMutableDictionary = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrAccessControl: sacObject!,
                kSecReturnData: true,
                kSecMatchLimit: kSecMatchLimitOne,
                kSecAttrService: "TelegramMiniApp",
                kSecAttrAccount: "bot_id_\(botPeer.id.toInt64())"
            ];
            
            weak let controller = self
            
            
            DispatchQueue.global().async {
                
                var itemCopy: CFTypeRef?
                let resultCode = SecItemCopyMatching(secQuery, &itemCopy)
                
                let data = (itemCopy as? Data).flatMap { String(data: $0, encoding: .utf8) }
                
                let status = resultCode == errSecSuccess && data != nil ? "authorized" : "failed"
                
    
                DispatchQueue.main.async {
                    if resultCode == errSecItemNotFound {
                        biometryState.opaqueToken = nil
                    }
                    if status == "failed" {
                        let eventData: JSON = ["status": status]
                        controller?.sendEvent(name: "biometry_auth_requested", data: eventData.string)
                    } else {
                        let eventData: JSON = ["status": status, "token": data!]
                        controller?.sendEvent(name: "biometry_auth_requested", data: eventData.string)
                    }
                    controller?.sendBiometricInfo(biometryState: biometryState)
                }
                
                
            }
        case "web_app_share_to_story":
            
            if let json = json, let mediaUrl = json["media_url"] as? String {
                let text = json["text"] as? String
                
                
                enum FetchResult {
                    case result(Data)
                    case progress(Float)
                }
                
                let _ = (showModalProgress(signal: fetchHttpResource(url: mediaUrl), for: window)
                |> map(Optional.init)
                |> `catch` { error in
                    return .single(nil)
                }
                |> mapToSignal { value -> Signal<FetchResult, NoError> in
                    if case let .dataPart(_, data, _, complete) = value, complete {
                        return .single(.result(data))
                    } else if case let .progressUpdated(progress) = value {
                        return .single(.progress(progress))
                    } else {
                        return .complete()
                    }
                }
                |> deliverOnMainQueue).start(next: { [weak self] next in
                    guard let self else {
                        return
                    }
                    
                    switch next {
                    case let .result(data):
                        var source: String?
                        if let _ = NSImage(data: data) {
                            let tempFile = TempBox.shared.tempFile(fileName: "image.jpeg")
                            if let _ = try? data.write(to: URL(fileURLWithPath: tempFile.path), options: .atomic) {
                                source = tempFile.path
                            }
                        } else {
                            let tempFile = TempBox.shared.tempFile(fileName: "image.mp4")
                            if let _ = try? data.write(to: URL(fileURLWithPath: tempFile.path), options: .atomic) {
                                source = tempFile.path
                            }
                        }
                        if let source, let botPeer = self.bot {
                            if let window = self.window {
                                BrowserHooks.shared.uploadStory(context, source, botPeer, text, window)
                            }
                            
                        }
                    default:
                        break
                    }
                })
            }
        case "web_app_set_emoji_status":
            setEmojiStatus(json)
        case "web_app_request_emoji_status_access":
            requestEmojiStatusAccess()
        case "web_app_request_file_download":
            if let json = json, let url = (json["url"] as? String), let fileName = json["file_name"] as? String {
                if let bot = bot {
                    
                    if #available(macOS 10.15, *) {
                        let _ = (FileDownload.getFileSize(url: url)
                                 |> deliverOnMainQueue).start(next: { [weak self] fileSize in
                            guard let self else {
                                return
                            }
                            var fileSizeString = ""
                            if let fileSize {
                                fileSizeString = " (\(fileSize.prettyNumber))"
                            }
                            downloadFile(url: url, fileName: fileName, fileSize: fileSizeString, bot: bot, window: window)

                        })
                    }
                    
                }
            }
        case "web_app_send_prepared_message":
            if let id = json?["id"] as? String, let bot {
                let origin = analyticsContext ?? Analytics.shared.unresolvedContext()
                preparedShareAction.open(context: context, bot: bot, id: id, window: window, analyticsContext: origin, canPresent: { [weak self] in
                    self?.window === window
                }, completion: { [weak self] success in
                    self?.sendEvent(name: success ? "prepared_message_sent" : "prepared_message_failed", data: nil)
                })
            }
        case "web_app_request_fullscreen":
            if !window.isFullScreen {
                window.toggleFullScreen(nil)
            }
        case "web_app_exit_fullscreen":
            if window.isFullScreen {
                window.toggleFullScreen(nil)
            }
        case "web_app_request_safe_area":
            updateSafeInsets()
        case "web_app_request_content_safe_area":
            updateSafeInsets()
        case "web_app_request_location":
            self.requestLocation()
        case "web_app_check_location":
            self.checkLocation()
        case "web_app_open_location_settings":
            self.openLocationSettings()
        case "web_app_device_storage_save_key":
            if let json, let requestId = json["req_id"] as? String, let botId = bot?.id {
                if let key = json["key"] as? String {
                    let value = json["value"]
                    
                    var effectiveValue: String?
                    if let stringValue = value as? String {
                        effectiveValue = stringValue
                    } else if value is NSNull {
                        effectiveValue = nil
                    } else {
                        let data: JSON = [
                            "req_id": requestId,
                            "error": "VALUE_INVALID"
                        ]
                        self.sendEvent(name: "device_storage_failed", data: data.string)
                        return
                    }
                    let _ = (self.context.engine.peers.setBotStorageValue(peerId: botId, key: key, value: effectiveValue)
                    |> deliverOnMainQueue).start(error: { [weak self] error in
                        var errorValue = "UNKNOWN_ERROR"
                        if case .quotaExceeded = error {
                            errorValue = "QUOTA_EXCEEDED"
                        }
                        let data: JSON = [
                            "req_id": requestId,
                            "error": errorValue
                        ]
                        self?.sendEvent(name: "device_storage_failed", data: data.string)
                    }, completed: { [weak self] in
                        let data: JSON = [
                            "req_id": requestId
                        ]
                        self?.sendEvent(name: "device_storage_key_saved", data: data.string)
                    })
                } else {
                    let data: JSON = [
                        "req_id": requestId,
                        "error": "KEY_INVALID"
                    ]
                    self.sendEvent(name: "device_storage_failed", data: data.string)
                }
            }
        case "web_app_device_storage_get_key":
            if let json, let requestId = json["req_id"] as? String, let botId = bot?.id {
                if let key = json["key"] as? String {
                    let _ = (self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.BotStorageValue(id: botId, key: key))
                    |> deliverOnMainQueue).start(next: { [weak self] value in
                        let data: JSON = [
                            "req_id": requestId,
                            "value": value ?? NSNull()
                        ]
                        self?.sendEvent(name: "device_storage_key_received", data: data.string)
                    })
                } else {
                    let data: JSON = [
                        "req_id": requestId,
                        "error": "KEY_INVALID"
                    ]
                    self.sendEvent(name: "device_storage_failed", data: data.string)
                }
            }
        case "web_app_device_storage_clear":
            if let json, let requestId = json["req_id"] as? String, let botId = bot?.id {
                let _ = (self.context.engine.peers.clearBotStorage(peerId: botId)
                |> deliverOnMainQueue).start(completed: { [weak self] in
                    let data: JSON = [
                        "req_id": requestId
                    ]
                    self?.sendEvent(name: "device_storage_cleared", data: data.string)
                })
            }
        case "web_app_secure_storage_save_key":
            if let json, let requestId = json["req_id"] as? String, let botId = bot?.id {
                if let key = json["key"] as? String {
                    let value = json["value"]

                    var effectiveValue: String?
                    if let stringValue = value as? String {
                        effectiveValue = stringValue
                    } else if value is NSNull {
                        effectiveValue = nil
                    } else {
                        let data: JSON = [
                            "req_id": requestId,
                            "error": "VALUE_INVALID"
                        ]
                        self.sendEvent(name: "secure_storage_failed", data: data.string)
                        return
                    }
                    let _ = (WebAppSecureStorage.setValue(context: self.context, botId: botId, key: key, value: effectiveValue)
                    |> deliverOnMainQueue).start(error: { [weak self] error in
                        var errorValue = "UNKNOWN_ERROR"
                        if case .quotaExceeded = error {
                            errorValue = "QUOTA_EXCEEDED"
                        }
                        let data: JSON = [
                            "req_id": requestId,
                            "error": errorValue
                        ]
                        self?.sendEvent(name: "secure_storage_failed", data: data.string)
                    }, completed: { [weak self] in
                        let data: JSON = [
                            "req_id": requestId
                        ]
                        self?.sendEvent(name: "secure_storage_key_saved", data: data.string)
                    })
                } else {
                    let data: JSON = [
                        "req_id": requestId,
                        "error": "KEY_INVALID"
                    ]
                    self.sendEvent(name: "secure_storage_failed", data: data.string)
                }
            }
        case "web_app_secure_storage_get_key":
            if let json, let requestId = json["req_id"] as? String, let botId = bot?.id {
                if let key = json["key"] as? String {
                    let _ = (WebAppSecureStorage.getValue(context: self.context, botId: botId, key: key)
                    |> deliverOnMainQueue).start(next: { [weak self] value in
                        let data: JSON = [
                            "req_id": requestId,
                            "value": value ?? NSNull()
                        ]
                        self?.sendEvent(name: "secure_storage_key_received", data: data.string)
                    }, error: { [weak self] error in
                        if case .canRestore = error {
                            let data: JSON = [
                                "req_id": requestId,
                                "value": NSNull(),
                                "canRestore": true
                            ]
                            self?.sendEvent(name: "secure_storage_key_received", data: data.string)
                        } else {
                            let data: JSON = [
                                "req_id": requestId,
                                "value": NSNull()
                            ]
                            self?.sendEvent(name: "secure_storage_key_received", data: data.string)
                        }
                    })
                } else {
                    let data: JSON = [
                        "req_id": requestId,
                        "error": "KEY_INVALID"
                    ]
                    self.sendEvent(name: "secure_storage_failed", data: data.string)
                }
            }
        case "web_app_secure_storage_restore_key":
            if let json, let requestId = json["req_id"] as? String, let botId = bot?.id {
                if let key = json["key"] as? String {
                    let _ = (WebAppSecureStorage.checkRestoreAvailability(context: self.context, botId: botId, key: key)
                    |> deliverOnMainQueue).start(next: { [weak self] storedKeys in
                        guard let self else {
                            return
                        }
                        guard !storedKeys.isEmpty else {
                            let data: JSON = [
                                "req_id": requestId,
                                "error": "RESTORE_UNAVAILABLE"
                            ]
                            self.sendEvent(name: "secure_storage_failed", data: data.string)
                            return
                        }
                        self.openSecureBotStorageTransfer(requestId: requestId, key: key, storedKeys: storedKeys)
                    }, error: { [weak self] error in
                        var errorValue = "UNKNOWN_ERROR"
                        if case .storageNotEmpty = error {
                            errorValue = "STORAGE_NOT_EMPTY"
                        }
                        let data: JSON = [
                            "req_id": requestId,
                            "error": errorValue
                        ]
                        self?.sendEvent(name: "secure_storage_failed", data: data.string)
                    })
                }
            }
        case "web_app_request_theme":
            self.sendThemeChangedEvent()
        case "web_app_secure_storage_clear":
            if let json, let requestId = json["req_id"] as? String, let botId = bot?.id {
                let _ = (WebAppSecureStorage.clearStorage(context: self.context, botId: botId)
                |> deliverOnMainQueue).start(completed: { [weak self] in
                    let data: JSON = [
                        "req_id": requestId
                    ]
                    self?.sendEvent(name: "secure_storage_cleared", data: data.string)
                })
            }
        case "web_app_verify_age":
            let verify_age_bot = context.appConfiguration.getStringValue("verify_age_bot_username", orElse: "")
            if let json, let passed = json["passed"] as? Bool, let age = json["age"] as? Double, bot?.addressName == verify_age_bot {
                
                let passed = passed && context.appConfiguration.getGeneralValue("verify_age_min", orElse: 18) <= Int32(age)
                
                let header: String
                let info: String
                if passed {
                    header = strings().verifyAgeAlertPassedHeader
                    info = strings().verifyAgeAlertPassedInfo
                } else {
                    header = strings().verifyAgeAlertFailedHeader
                    info = strings().verifyAgeAlertFailedInfo
                }

                showModalText(for: context.window, text: info, title: header)
                _ = updateRemoteContentSettingsConfiguration(postbox: context.account.postbox, network: context.account.network, sensitiveContentEnabled: true).start()
                
                context.contentConfig.sensitiveContentEnabled = true
                
                NotificationCenter.default.post(name: NSNotification.Name("external_age_verify"), object: nil)
                
                FastSettings.lastAgeVerification = Date().timeIntervalSince1970
                
            }
        case "web_app_request_chat":
            if let json, let requestId = json["req_id"] as? String, let bot = self.bot {
                let botPeerId = bot.id
                _ = (context.engine.peers.getRequestedWebViewButton(botId: botPeerId, requestId: requestId)
                |> deliverOnMainQueue).start(next: { [weak self] button in
                    guard let self else { return }
                    if case let .requestPeer(peerType, buttonId, maxQuantity) = button.action {
                        BrowserHooks.shared.selectPeerForWebView(context, peerType, botPeerId, requestId, buttonId, maxQuantity, self.window ?? context.window, { [weak self] success in
                            if success {
                                let data: JSON = ["req_id": requestId]
                                self?.sendEvent(name: "requested_chat_sent", data: data.string)
                            } else {
                                let data: JSON = ["req_id": requestId]
                                self?.sendEvent(name: "requested_chat_failed", data: data.string)
                            }
                        })
                    } else {
                        let data: JSON = ["req_id": requestId]
                        self.sendEvent(name: "requested_chat_failed", data: data.string)
                    }
                }, error: { [weak self] _ in
                    let data: JSON = ["req_id": requestId]
                    self?.sendEvent(name: "requested_chat_failed", data: data.string)
                })
            }
        default:
            break
        }

    }
    
    fileprivate func openSecureBotStorageTransfer(requestId: String, key: String, storedKeys: [WebAppSecureStorage.ExistingKey]) {
        guard let window = self.window, let bot = bot else {
            return
        }
        
        let botId = bot.id
        
        showModal(with: WebappTransferDataController(context: context, peer: .init(bot), storedKeys: storedKeys, completion: { [weak self] uuid in
            guard let self else {
                return
            }
            guard let uuid else {
                let data: JSON = [
                    "req_id": requestId,
                    "error": "RESTORE_CANCELLED"
                ]
                self.sendEvent(name: "secure_storage_failed", data: data.string)
                return
            }
            
            let _ = (WebAppSecureStorage.transferAllValues(context: self.context, fromUuid: uuid, botId: botId)
            |> deliverOnMainQueue).start(completed: { [weak self] in
                guard let self else {
                    return
                }
                let _ = (WebAppSecureStorage.getValue(context: self.context, botId: botId, key: key)
                |> deliverOnMainQueue).start(next: { [weak self] value in
                    let data: JSON = [
                        "req_id": requestId,
                        "value": value ?? NSNull()
                    ]
                    self?.sendEvent(name: "secure_storage_key_restored", data: data.string)
                    showModalText(for: window, text: strings().webAppTransferDataTransfered)
                })
            })
        }), for: window)
        
        
    }
    
    private func sendThemeChangedEvent() {
        let themeParams = generateWebAppThemeParams(theme)
        var themeParamsString = "{theme_params: {"
        for (key, value) in themeParams {
            if let value = value as? Int32 {
                let color = NSColor(rgb: UInt32(bitPattern: value))
                
                if themeParamsString.count > 16 {
                    themeParamsString.append(", ")
                }
                themeParamsString.append("\"\(key)\": \"\(color.hexString)\"")
            }
        }
        themeParamsString.append("}}")
        self.sendEvent(name: "theme_changed", data: themeParamsString)
    }
    
    fileprivate func setEmojiStatus(_ data: [String: Any]?) {
        guard acceptsLocationRequests, !emojiStatusAction.isPending, let timestamp = lastTouchTimestamp else {
            return
        }
        let elapsed = CACurrentMediaTime() - timestamp
        guard elapsed >= 0 && elapsed <= 10 else { return }
        let parameters: BrowserEmojiStatusAction.Parameters
        switch BrowserEmojiStatusAction.parse(data, timestamp: context.timestamp) {
        case let .success(value):
            parameters = value
        case let .failure(error):
            self.sendEvent(name: "emoji_status_failed", data: JSON(dictionary: ["error": error.rawValue])?.string)
            return
        }
        guard let bot = self.bot, let window = self.window else {
            self.sendEvent(name: "emoji_status_failed", data: JSON(dictionary: ["error": "UNKNOWN_ERROR"])?.string)
            return
        }
        let botId = bot.id
        emojiStatusAction.open(context: context, bot: bot, parameters: parameters, window: window, canPresent: { [weak self, weak window] in
            guard let self, let window else { return false }
            return self.acceptsLocationRequests && self.bot?.id == botId && self.window === window
        }, completion: { [weak self] error in
            if let error {
                self?.sendEvent(name: "emoji_status_failed", data: JSON(dictionary: ["error": error.rawValue])?.string)
            } else {
                self?.sendEvent(name: "emoji_status_set", data: nil)
            }
        })
    }

    fileprivate func requestEmojiStatusAccess() {
        guard acceptsLocationRequests, let timestamp = lastTouchTimestamp else {
            return
        }
        let elapsed = CACurrentMediaTime() - timestamp
        guard elapsed >= 0 && elapsed <= 10 else {
            return
        }
        guard let bot = self.bot, let window = self.window else {
            self.sendEvent(name: "emoji_status_access_requested", data: JSON(dictionary: ["status": "cancelled"])?.string)
            return
        }
        let botId = bot.id
        emojiPermissionAction.open(context: context, bot: bot, window: window, canPresent: { [weak self, weak window] in
            guard let self, let window else {
                return false
            }
            return self.acceptsLocationRequests && self.bot?.id == botId && self.window === window
        }, completion: { [weak self] status in
            self?.sendEvent(name: "emoji_status_access_requested", data: JSON(dictionary: ["status": status])?.string)
        })
    }

    fileprivate func openLocationSettings() {
        guard acceptsLocationRequests, let botId = self.bot?.id, let timestamp = lastTouchTimestamp else {
            return
        }
        let elapsed = CACurrentMediaTime() - timestamp
        guard elapsed >= 0 && elapsed <= 10 else {
            return
        }
        lastTouchTimestamp = nil
        BrowserHooks.shared.openPeerInfo(context, botId)
        context.window.makeKeyAndOrderFront(nil)
    }
    
    fileprivate func checkLocation() {
        guard acceptsLocationRequests, let botId = self.bot?.id else {
            return
        }
        locationAction.check(context: context, botId: botId, canPresent: { [weak self] in
            self?.acceptsLocationRequests == true && self?.bot?.id == botId
        }, completion: { [weak self] data in
            self?.sendEvent(name: "location_checked", data: JSON(dictionary: data)?.string)
        })
    }

    fileprivate func requestLocation() {
        guard acceptsLocationRequests else {
            return
        }
        guard let bot = self.bot, let window = self.window else {
            self.sendEvent(name: "location_requested", data: JSON(dictionary: ["available": false])?.string)
            return
        }
        let botId = bot.id
        locationAction.open(context: context, bot: bot, window: window, canPresent: { [weak self, weak window] in
            guard let self, let window else {
                return false
            }
            return self.acceptsLocationRequests && self.bot?.id == botId && self.window === window
        }, completion: { [weak self, weak window] data, error in
            guard let self, let window else {
                return
            }
            if let error {
                let text: String
                switch error {
                case .denied, .restricted:
                    text = strings().webAppLocationPermissionDeniedError
                case .wifiRequired:
                    text = strings().webAppLocationPermissionWifiError
                default:
                    text = strings().webAppLocationPermissionDisabledError
                }
                showModalText(for: window, text: text)
            }
            self.sendEvent(name: "location_requested", data: JSON(dictionary: data)?.string)
        })
    }

    private func downloadFile(url: String, fileName: String, fileSize: String, bot: Peer, window: Window) {
        var title: String?
        let photoExtensions = [".jpg", ".png", ".gif", ".tiff"]
        let videoExtensions = [".mp4", ".mov"]
        var downloadedText: String = strings().webappDocumentDownloadImage
        let lowercasedFilename = fileName.lowercased()
        for ext in photoExtensions {
            if lowercasedFilename.hasSuffix(ext) {
                title = "Download Photo"
                downloadedText = strings().webappDocumentDownloadImage
                break
            }
        }
        if title == nil {
            for ext in videoExtensions {
                if lowercasedFilename.hasSuffix(ext) {
                    title = "Download Video"
                    downloadedText = strings().webappDocumentDownloadVideo
                    break
                }
            }
        }
        if title == nil {
            title = "Download Document"
        }
        let context = self.context
        
        verifyAlert(for: window, header: title!, information: strings().webappDocumentDownloadInfo(bot.displayTitle, "**\(fileName)**\(fileSize)"), ok: strings().webappDocumentDownloadOK, successHandler: { [weak self, window] _ in
            
            self?.sendEvent(name: "file_download_requested", data: "{status: \"downloading\"}")

            
            enum FetchResult {
                case result(Data)
                case progress(Float)
            }
            
            let signal = (showModalProgress(signal: fetchHttpResource(url: url), for: window)
            |> map(Optional.init)
            |> `catch` { error in
                return .single(nil)
            }
            |> mapToSignal { value -> Signal<FetchResult, NoError> in
                if case let .dataPart(_, data, _, complete) = value, complete {
                    return .single(.result(data))
                } else if case let .progressUpdated(progress) = value {
                    return .single(.progress(progress))
                } else {
                    return .complete()
                }
            })
            
            _ = signal.startStandalone(next: { [weak self, weak window] result in
                guard self != nil, let window = window else {
                    return
                }
                switch result {
                case let .result(data):
                    let tempFile = TempBox.shared.tempFile(fileName: fileName)
                    try? data.write(to: URL(fileURLWithPath: tempFile.path), options: .atomic)
                    
    
                    savePanel(file: tempFile.path, named: fileName, for: window, completion: { [weak window] path  in
                        if let window {
                            
                            let attributedText = parseMarkdownIntoAttributedString(downloadedText, attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: .bold(15), textColor: .white), bold: MarkdownAttributeSet(font: .bold(15), textColor: .white), link: MarkdownAttributeSet(font: .bold(15), textColor: .link), linkAttribute: { contents in
                                return (NSAttributedString.Key.link.rawValue, LinkHooks.shared.callbackLink(contents, { _ in }))
                            })).mutableCopy() as! NSMutableAttributedString
                            
                            let layout = TextViewLayout(attributedText, alignment: .center, lineSpacing: 5.0, alwaysStaticItems: true)
                            layout.interactions = TextViewInteractions(processURL: { _ in 
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                            })
                            layout.measure(width: 160)
                            BrowserHooks.shared.showSavedToDownloads(context, window, layout)
                        }
                    })
                default:
                    break
                }
            })
            
        }, cancelHandler: { [weak self] in
            self?.sendEvent(name: "file_download_requested", data: "{status: \"cancelled\"}")

        })
    }
    
    fileprivate func requestWriteAccess() {
        guard let data = self.requestData, let window = self.window else {
            return
        }
        let context = self.context
        
        let sendEvent: (Bool) -> Void = { [weak self] success in
            var paramsString: String
            if success {
                paramsString = "{status: \"allowed\"}"
            } else {
                paramsString = "{status: \"cancelled\"}"
            }
            self?.sendEvent(name: "write_access_requested", data: paramsString)
        }
        
        let _ = showModalProgress(signal: self.context.engine.messages.canBotSendMessages(botId: data.bot.id), for: window).start(next: { [weak self] result in
            if result {
                sendEvent(true)
            } else if let window = self?.window {
                verifyAlert_button(for: window, header: strings().webappAllowMessagesTitle, information: strings().webappAllowMessagesText(data.bot.displayTitle), ok: strings().webappAllowMessagesOK, successHandler: { _ in
                    let _ = showModalProgress(signal: context.engine.messages.allowBotSendMessages(botId: data.bot.id), for: window).start(completed: {
                        sendEvent(true)
                    })
                }, cancelHandler: {
                    sendEvent(false)
                })
            }
        })

    }
    fileprivate func shareAccountContact() {
        guard let botPeer = self.bot else {
            return
        }
        let context = self.context
        
        let sendEvent: (Bool) -> Void = { [weak self] success in
            var paramsString: String
            if success {
                paramsString = "{status: \"sent\"}"
            } else {
                paramsString = "{status: \"cancelled\"}"
            }
            self?.sendEvent(name: "phone_requested", data: paramsString)
        }
        
        let isBlocked = context.engine.data.get(
            TelegramEngine.EngineData.Item.Peer.IsBlocked(id: botPeer.id)
        )
        |> deliverOnMainQueue
        |> map { $0.knownValue ?? false }
        |> take(1)
        
        _ = isBlocked.start(next: { [weak self] isBlocked in
            let text: String
            if isBlocked {
                text = strings().conversationShareBotContactConfirmationUnblock(botPeer.displayTitle)
            } else {
                text = strings().conversationShareBotContactConfirmation(botPeer.displayTitle)
            }
            if let window = self?.window {
                verifyAlert_button(for: window, header: strings().conversationShareBotContactConfirmationTitle, information: text, ok: strings().conversationShareBotContactConfirmationOK, successHandler: { _ in
                    
                    
                    let _ = (context.account.postbox.loadedPeerWithId(context.peerId) |> deliverOnMainQueue).start(next: { peer in
                        if let peer = peer as? TelegramUser, let phone = peer.phone, !phone.isEmpty {
                            
                            let sendMessageSignal = enqueueMessages(account: context.account, peerId: botPeer.id, messages: [
                                .message(text: "", attributes: [], inlineStickers: [:], mediaReference: .standalone(media: TelegramMediaContact(firstName: peer.firstName ?? "", lastName: peer.lastName ?? "", phoneNumber: phone, peerId: peer.id, vCardData: nil)), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                            ])
                            |> mapToSignal { messageIds -> Signal<Bool, NoError> in
                                if let maybeMessageId = messageIds.first, let messageId = maybeMessageId {
                                    return context.account.pendingMessageManager.pendingMessageStatus(messageId)
                                    |> mapToSignal { status, _ -> Signal<Bool, NoError> in
                                        if status != nil {
                                            return .never()
                                        } else {
                                            return .single(true)
                                        }
                                    }
                                    |> take(1)
                                } else {
                                    return .single(true)
                                }
                            }
                            let invoke:()->Void = {
                                let _ = (sendMessageSignal |> deliverOnMainQueue).start(next: { _ in
                                    sendEvent(true)
                                })
                            }
                            if isBlocked {
                                _ = (context.blockedPeersContext.remove(peerId: botPeer.id) |> deliverOnMainQueue).start(completed: invoke)
                            } else {
                                invoke()
                            }
                        }
                    })
                }, cancelHandler: {
                    sendEvent(false)
                })
            }
            
        })
        
       
    }
    
    fileprivate func sendBiometricInfo(biometryState: TelegramBotBiometricsState) {
        
        let type: String = laContext.biometricTypeString
        let error: NSErrorPointer = .none
        
        
        let available = laContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: error)
        
        let access_requested = biometryState.accessRequested
        let access_granted = biometryState.accessGranted
        let token_saved = biometryState.opaqueToken != nil
        
        self.biometryState = biometryState
        
        if let uuid = FastSettings.defaultUUID()?.uuidString {
            let paramsString: String = "{available: \"\(available)\", type:\"\(type)\", access_requested:\(access_requested), access_granted:\(access_granted), token_saved:\(token_saved), device_id:\"\(uuid)\"}"
            self.sendEvent(name: "biometry_info_received", data: paramsString)
        }
        
    }
    
    fileprivate func invokeCustomMethod(requestId: String, method: String, params: String) {
        
        let id = self.bot?.id
        
        guard let peerId = id else {
            return
        }
        let _ = (self.context.engine.messages.invokeBotCustomMethod(botId: peerId, method: method, params: params)
        |> deliverOnMainQueue).start(next: { [weak self] result in
            guard let self else {
                return
            }
            var payload: [String: Any] = ["req_id": requestId]
            if let data = result.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                payload["result"] = json
            } else {
                payload["result"] = [:]
            }
            guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
                return
            }
            guard let jsonDataString = String(data: jsonData, encoding: .utf8) else {
                return
            }

            self.sendEvent(name: "custom_method_invoked", data: jsonDataString)
        })
    }

    
    private func webAppReady() {
        genericView.update(inProgress: false, preload: self.preloadData, animated: true)
        self.updateLocalizationAndTheme(theme: theme)
    }
    
    
    private func updateSize() {
        if let contentSize = window?.screen?.frame.size {
           measure(size: contentSize)
        }
        self.sendEvent(name: "viewport_changed", data: nil)
    }
    
    private func poupDidClose(_ id: String) {
        let data: JSON = ["button_id": id]
        self.sendEvent(name: "popup_closed", data: data.string)
    }
    
    public func sendEvent(name: String, data: String?) {
        if !Thread.isMainThread {
            Queue.mainQueue().async { [weak self] in
                self?.sendEvent(name: name, data: data)
            }
            return
        }
        if self.requestData?.sameOrigin == true {
            guard let trustedOrigin = self.trustedOrigin, let currentUrl = self.genericView._holder.url, webAppOrigin(url: currentUrl) == trustedOrigin else {
                return
            }
        }
        let script = "window.TelegramGameProxy.receiveEvent(\"\(name)\", \(data ?? "null"))"
        self.genericView._holder.evaluateJavaScript(script, completionHandler: { _, _ in

        })
    }
    
    public func backButtonPressed() {
        self.sendEvent(name: "back_button_pressed", data: nil)
    }
    public func settingsPressed() {
        self.sendEvent(name: "settings_button_pressed", data: nil)
    }
    
    public func add(_ tab: BrowserTabData.Data) -> Bool {
        return false
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        
        self.sendThemeChangedEvent()
        
        
        genericView.updateHeader(title: self.defaultBarTitle, subtitle: strings().presenceMiniapp, left: isBackButton ? .back : .dismiss, animated: true, leftCallback: { [weak self] in
            if self?.isBackButton == true {
                self?.backButtonPressed()
            } else {
                self?.close()
            }
        }, contextMenu: { [weak self] in
            return self?.contextMenu()
        }, context: context, bot: self.bot)

    }
    
    fileprivate func pressMainButton() {
        self.sendEvent(name: "main_button_pressed", data: nil)
    }
    fileprivate func pressSecondaryButton() {
        self.sendEvent(name: "secondary_button_pressed", data: nil)
    }
    
    public func contextMenu() -> ContextMenu {
        var items:[ContextMenuItem] = []
        
        let verify_age_bot = context.appConfiguration.getStringValue("verify_age_bot_username", orElse: "")

        
        if self.bot?.addressName != verify_age_bot {
            let inFullscreen = window?.isFullScreen == true

            items.append(.init(!inFullscreen ? strings().webAppFullscreen : strings().webAppExitFullscreen, handler: { [weak self] in
                self?.window?.toggleFullScreen(nil)
            }, itemImage: self.window?.isFullScreen == false ? MenuAnimation.menu_expand.value : MenuAnimation.menu_collapse.value))

            
            items.append(.init(strings().webAppReload, handler: { [weak self] in
                self?.reloadPage()
            }, itemImage: MenuAnimation.menu_reload.value))

            if self.hasSettings == true {
                items.append(.init(strings().webAppSettings, handler: { [weak self] in
                    self?.settingsPressed()
                }, itemImage: MenuAnimation.menu_gear.value))
            }
            
            if let data = self.data, let bot = data.bot as? TelegramUser, let botInfo = bot.botInfo {
                if botInfo.flags.contains(.canBeAddedToAttachMenu) {
                    if installedBots.contains(where: { $0 == bot.id }) {
                        items.append(ContextSeparatorItem())
                        items.append(.init(strings().webAppRemoveBot, handler: { [weak self] in
                            self?.removeBotFromAttachMenu(bot: bot)
                        }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
                    } else {
                        items.append(.init(strings().webAppInstallBot, handler: { [weak self] in
                            self?.addBotToAttachMenu(bot: bot)
                        }, itemImage: MenuAnimation.menu_plus.value))
                    }
                }
            }
        }
        
        
        if self.isBackButton == true, browser == nil {
            items.append(.init(strings().webAppClose, handler: { [weak self] in
                self?.close()
            }, itemImage: MenuAnimation.menu_clear_history.value))
        }
        
        let menu = ContextMenu()
        for item in items {
            menu.addItem(item)
        }
        return menu
    }

    
    private func handleSendData(data string: String) {
        
        
        counter += 1
        
        
        if let data = string.data(using: .utf8), let jsonArray = try? JSONSerialization.jsonObject(with: data, options : .allowFragments) as? [String: Any], let data = jsonArray["data"] {
            var resultString: String?
            if let string = data as? String {
                resultString = string
            } else if let data1 = try? JSONSerialization.data(withJSONObject: data, options: JSONSerialization.WritingOptions.prettyPrinted), let convertedString = String(data: data1, encoding: String.Encoding.utf8) {
                resultString = convertedString
            }
            if let resultString = resultString {
                if let requestData = self.requestData {
                    let _ = (self.context.engine.messages.sendWebViewData(botId: requestData.bot.id, buttonText: requestData.buttonText, data: resultString)).start()
                }
            }
        }
        self.close()
    }
    
    public func closeAnyway() {
        cancelPendingPageActions()
        if let browser {
            browser.close(confirm: false)
        } else {
            if let window {
                closeAllModals(window: window)
            }
            self.window?.contentView?.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak self] _ in
                self?._window?.orderOut(nil)
                self?._window = nil
            })
        }
    }
    
    public override var shouldCloseAllTheSameModals: Bool {
        return false
    }
    
    public override func close(animationType: ModalAnimationCloseBehaviour = .common) {
        if let browser {
            browser.close(confirm: needCloseConfirmation)
        } else {
            if needCloseConfirmation, let window {
                verifyAlert_button(for: window, information: strings().webpageConfirmClose, ok: strings().webpageConfirmOk, successHandler: { [weak self] _ in
                    self?.closeAnyway()
                })
            } else {
                self.closeAnyway()
            }
        }
        
    }

    public func cancelPendingInvoices() {
        invoiceAction.reset()
    }

    public func cancelPendingPageActions() {
        lastTouchTimestamp = nil
        locationAction.reset()
        emojiPermissionAction.reset()
        emojiStatusAction.reset()
        cancelPendingInvoices()
        preparedShareAction.reset()
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        cancelPendingPageActions()
    }

    public func reloadPage() {
        cancelPendingPageActions()
        self.genericView._holder.reload()
        self.updateLocalizationAndTheme(theme: theme)
    }
    
    
    private func removeBotFromAttachMenu(bot: Peer) {
        let context = self.context
        if let window = self.window {
            _ = showModalProgress(signal: context.engine.messages.removeBotFromAttachMenu(botId: bot.id), for: window).start(next: { [weak self] value in
                if value, let window = self?.window {
                    showModalText(for: window, text: strings().webAppAttachRemoveSuccess(bot.displayTitle))
                }
            })
        }
        
        self.installedBots.removeAll(where: { $0 == bot.id})
    }
    private func addBotToAttachMenu(bot: Peer) {
        let context = self.context
        installAttachMenuBot(context: context, peer: bot, completion: { [weak self] value in
            if value, let window = self?.window {
                self?.installedBots.append(bot.id)
                showModalText(for: window, text: strings().webAppAttachSuccess(bot.displayTitle))
            }
        })
    }
    
    
    public override var canBecomeResponder: Bool {
        return true
    }
    public override func firstResponder() -> NSResponder? {
        return genericView.webview
    }
    
    public override var defaultBarTitle: String {
        return self.title
    }
    
    public override func escapeKeyAction() -> KeyHandlerResult {
        if isBackButton {
            self.backButtonPressed()
            return .invoked
        }
        
        return super.escapeKeyAction()
    }
    
    public override var hasNextResponder: Bool {
        return false
    }
    
    public override var hasBorder: Bool {
        return false
    }
    
    
    
    public override var containerBackground: NSColor {
        return .clear
    }
    
}


