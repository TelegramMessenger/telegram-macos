import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramContext
import TelegramTheme
import TelegramUtils

public final class EntertainmentSidebarView: View {
    private let glassView: LiquidGlassView
    fileprivate let contentView = View()

    private static var cornerRadius: CGFloat {
        if #available(macOS 26.0, *) {
            return 20
        }
        return 8
    }

    private var currentCornerRadius: CGFloat {
#if compiler(>=6.4)
        if #available(macOS 27.0, *), let radii = effectiveCornerRadii {
            return radii.topLeft
        }
#endif
        return EntertainmentSidebarView.cornerRadius
    }

#if compiler(>=6.4)
    @available(macOS 27.0, *)
    public override var cornerConfiguration: NSViewCornerConfiguration? {
        .uniformCorners(radius: .containerConcentric(8))
    }

    @available(macOS 27.0, *)
    public override func viewDidChangeEffectiveCornerRadii() {
        super.viewDidChangeEffectiveCornerRadii()
        applyCornerRadius()
    }
#endif

    private func applyCornerRadius() {
        let radius = currentCornerRadius
        glassView.cornerRadius = radius
        contentView.layer?.cornerRadius = radius
    }

    public required init(frame frameRect: NSRect) {
        let radius = EntertainmentSidebarView.cornerRadius
        glassView = LiquidGlassView(frame: frameRect.size.bounds, cornerRadius: radius, hasShadow: true, hasBorder: true, tintAlpha: 0, customTint: theme.colors.background.withAlphaComponent(EntertainmentView.glassTintAlpha), forceBlur: true)
        super.init(frame: frameRect)
        layer?.masksToBounds = false
        backgroundColor = .clear

        contentView.layer?.cornerRadius = radius
        contentView.layer?.masksToBounds = true

        addSubview(glassView)
        addSubview(contentView)
        updateLocalizationAndTheme(theme: theme)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = theme as! TelegramPresentationTheme
        glassView.customTint = theme.colors.background.withAlphaComponent(EntertainmentView.glassTintAlpha)
    }

    public override func layout() {
        super.layout()
        applyCornerRadius()
        glassView.frame = bounds
        glassView.updateLayout(size: bounds.size, transition: .immediate)
        contentView.frame = bounds
        for subview in contentView.subviews {
            subview.frame = contentView.bounds
        }
    }

    fileprivate func attach(_ view: NSView) {
        if view.superview !== contentView {
            contentView.addSubview(view, positioned: .below, relativeTo: nil)
        }
        view.frame = contentView.bounds
    }
}

public final class EntertainmentSidebarController: GenericViewController<EntertainmentSidebarView> {
    public static let paneWidth: CGFloat = 358

    private let context: any AccountContextProtocol
    private let entertainment: ViewController
    private let isChat: (ViewController) -> Bool
    private let availabilityDisposable = MetaDisposable()
    private var canSendMessages: Bool?

    public var availabilityUpdated: () -> Void = {}

    public var canShow: Bool {
        return canSendMessages == true && isChat(context.bindings.rootNavigation().controller)
    }

    public init(context: any AccountContextProtocol, entertainment: ViewController, isChat: @escaping (ViewController) -> Bool) {
        self.context = context
        self.entertainment = entertainment
        self.isChat = isChat
        super.init(frame: NSMakeRect(0, 0, EntertainmentSidebarController.paneWidth, 0))
        self.bar = .init(height: 0)
        self.insets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 8)
        context.bindings.rootNavigation().add(listener: WeakReference(value: self))

        let postbox = context.account.postbox
        availabilityDisposable.set((context.globalPeerHandler.get() |> mapToSignal { location -> Signal<Bool, NoError> in
            guard let location = location else {
                return .single(false)
            }
            switch location {
            case let .peer(peerId):
                return getPeerView(peerId: peerId, postbox: postbox) |> map { peer in
                    return peer?.canSendMessage(false) ?? false
                }
            case let .thread(message):
                return combineLatest(getPeerView(peerId: message.peerId, postbox: postbox), postbox.transaction { transaction in
                    return transaction.getMessageHistoryThreadInfo(peerId: message.peerId, threadId: message.threadId)
                }) |> map { peer, info in
                    return peer?.canSendMessage(true, threadData: info?.data.get(MessageHistoryThreadData.self)) ?? false
                }
            }
        } |> deliverOnMainQueue).start(next: { [weak self] value in
            guard let self, self.canSendMessages != value else {
                return
            }
            self.canSendMessages = value
            self.availabilityUpdated()
        }))
    }

    deinit {
        availabilityDisposable.dispose()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        readyOnce()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let popover = entertainment.popover {
            popover.animates = false
            popover.hide()
        }
        genericView.attach(entertainment.view)
        (entertainment.view as? EntertainmentView)?.showsTabsEdge = false
        (entertainment.view as? EntertainmentView)?.showsGlassBackground = false
        entertainment.viewWillAppear(animated)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        entertainment.viewDidAppear(animated)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        entertainment.viewWillDisappear(animated)
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        (entertainment.view as? EntertainmentView)?.showsTabsEdge = true
        (entertainment.view as? EntertainmentView)?.showsGlassBackground = true
        entertainment.viewDidDisappear(animated)
    }

    public override func navigationWillChangeController() {
        super.navigationWillChangeController()
        availabilityUpdated()
    }
}
