import Cocoa
import TGUIKit
import TelegramCore
import InAppSettings
import Postbox
import SwiftSignalKit
import KeyboardKey

#if !APP_STORE
import Sparkle
import FoundationUtils
#endif

enum UpdateButtonState {
    case common
    case important
    case critical
}

final class UpdateTabView : Control {
    let textView: TextView = TextView()
    let imageView: ImageView = ImageView()
    let shimmer = ShimmerEffectView()
    let progressView: ProgressIndicator = ProgressIndicator(frame: NSMakeRect(0, 0, 24, 24))
    private let glassView = LiquidGlassView(frame: .zero, cornerRadius: 20)
    private var updateState: UpdateButtonState = .common
    
    var bottomOverlayChanged: (() -> Void)?

    override var isHidden: Bool {
        didSet {
            if isHidden != oldValue {
                bottomOverlayChanged?()
            }
        }
    }

    var isChatList: Bool = false
    
    var isInstalling: Bool = false {
        didSet {
            updateContent(animated: isInstalling != oldValue)
        }
    }
    
    var layoutState: SplitViewState = .dual {
        didSet {
            updateContent(animated: false)
        }
    }

    var preferredWidth: CGFloat {
        if layoutState == .minimisize {
            return 40
        }
        return isInstalling ? 60 : textView.frame.width + 40
    }

    private func updateContent(animated: Bool) {
        shimmer.change(opacity: isInstalling ? 0 : 1, animated: animated)
        textView.isHidden = isInstalling || layoutState == .minimisize
        progressView.isHidden = !isInstalling
        imageView.isHidden = isInstalling || layoutState != .minimisize
        if isChatList, let superview, frame.width != preferredWidth {
            change(size: NSMakeSize(preferredWidth, frame.height), animated: animated, timingFunction: .spring)
            change(pos: NSMakePoint(superview.bounds.focus(frame.size).minX, frame.minY), animated: animated, timingFunction: .spring)
        }
        needsLayout = true
    }

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        backgroundColor = .clear
        layer?.masksToBounds = false
        glassView.isEventLess = true
        addSubview(glassView)
        interactiveGlassView = glassView
        scaleOnClick = true
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        textView.disableBackgroundDrawing = true
        textView.isAccessibilityDecorative = true
        addSubview(textView)
        progressView.isEventLess = true
        progressView.isAccessibilityDecorative = true
        addSubview(progressView)
        imageView.isEventLess = true
        imageView.isAccessibilityDecorative = true
        addSubview(imageView)
        shimmer.isEventLess = true
        shimmer.layer?.masksToBounds = true
        addSubview(shimmer)
        shimmer.isStatic = true
        updateLocalizationAndTheme(theme: theme)
    }
    
    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }
    
    func update(_ state: UpdateButtonState) {
        updateState = state
        updateLocalizationAndTheme(theme: theme)
    }

    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = theme as! TelegramPresentationTheme
        let tint: NSColor
        switch updateState {
        case .common:
            tint = theme.colors.accent
        case .important:
            tint = theme.colors.greenUI
        case .critical:
            tint = theme.colors.redUI
        }
        glassView.customTint = tint
        let foreground = tint.lightness > 0.8 ? NSColor(0x000000) : NSColor(0xffffff)
        let layout = TextViewLayout(.initialize(string: strings().updateUpdateTelegram, color: foreground, font: .medium(.title)), maximumNumberOfLines: 1)
        layout.measure(width: max(280, frame.width))
        textView.update(layout)
        imageView.image = generateTintedImage(image: theme.icons.appUpdate, color: foreground)
        imageView.sizeToFit()
        progressView.progressColor = foreground
        setAccessibilityLabel(strings().updateUpdateTelegram)
        updateContent(animated: false)
    }

    override func layout() {
        super.layout()
        let cornerRadius: CGFloat = isChatList ? bounds.height / 2 : 0
        layer?.cornerRadius = cornerRadius
        glassView.cornerRadius = cornerRadius
        glassView.frame = bounds
        glassView.updateLayout(size: bounds.size, transition: .immediate)
        shimmer.frame = bounds
        shimmer.layer?.cornerRadius = cornerRadius
        if bounds.width > 0, bounds.height > 0 {
            shimmer.updateAbsoluteRect(bounds, within: bounds.size)
            shimmer.update(backgroundColor: .clear, foregroundColor: .clear, shimmeringColor: NSColor.white.withAlphaComponent(0.3), shapes: [.roundedRect(rect: bounds, cornerRadius: cornerRadius)], horizontal: true, size: bounds.size)
        }
        textView.center()
        progressView.center()
        imageView.center()
        bottomOverlayChanged?()
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class UpdateTabController: GenericViewController<UpdateTabView> {
    private let disposable = MetaDisposable()
    private let shakeDisposable = MetaDisposable()
    private let context: SharedAccountContext
    private var state: UpdateButtonState = .common {
        didSet {
            genericView.update(state)
        }
    }
    private var parentSize: NSSize = .zero
    private let stateDisposable = MetaDisposable()
    #if !APP_STORE
    private var appcastItem: SUAppcastItem? {
        didSet {
            
            genericView.isHidden = appcastItem == nil
            
            
            var state = self.state
            
            if appcastItem != oldValue {
                if let appcastItem = appcastItem {
                    if appcastItem.isCritical {
                        state = .critical
                        stateDisposable.set(nil)
                    } else if oldValue == nil {
                        state = .common
                        
                        let importantDelay: Double = 60 * 60 * 24
                        let criticalDelay: Double = 60 * 60 * 24
                        let updateSignal = Signal<UpdateButtonState, NoError>.single(.important) |> delay(importantDelay, queue: .mainQueue()) |> then(.single(.critical) |> delay(criticalDelay, queue: .mainQueue()))
                        
                        stateDisposable.set(updateSignal.start(next: { [weak self] newState in
                            self?.state = newState
                        }))
                        
                    }
                    
                } else {
                    stateDisposable.set(nil)
                }
            }
            self.state = state
//            self.updateLayout(self.context.layout, parentSize: parentSize, isChatList: true)
        }
    }
    #endif
    init(_ context: SharedAccountContext) {
        self.context = context
        super.init()
        self.bar = NavigationBarStyle(height: 0)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        let context = self.context
        
        
        genericView.set(background: .clear, for: .Normal)
        genericView.isHidden = true
        
        #if APP_STORE
        
        let signal = Signal<Void, NoError>.single(Void()) |> then(.single(Void()) |> delay(24 * 60 * 60, queue: .mainQueue()) |> restart)

        disposable.set(signal.start(next: { [weak self] in
            checkForAppstoreUpdate(completion: { needToUpdate in
                self?.genericView.isHidden = !needToUpdate
                self?.state = .common
            })
        }))
        genericView.set(handler: { control in
            execute(inapp: inAppLink.external(link: itunesAppLink, false))
            control.isHidden = true
        }, for: .Click)
        #else
        disposable.set((appUpdateStateSignal |> deliverOnMainQueue).start(next: { [weak self] state in
            switch state.loadingState {
            case let .readyToInstall(item):
                self?.appcastItem = item
                self?.genericView.isInstalling = false
            case .installing:
                self?.genericView.isInstalling = true
            default:
                self?.appcastItem = nil
                self?.genericView.isInstalling = false
            }
        }))
        
        genericView.set(handler: { _ in
            updateApplication(sharedContext: context)
        }, for: .Click)
        #endif
        
        
        
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        #if !APP_STORE
        let item = self.appcastItem
        self.appcastItem = item
        #endif
    
    }
    
    func updateLayout(_ layout: SplitViewState, parentSize: NSSize, isChatList: Bool) {
        genericView.isChatList = isChatList
        genericView.layoutState = layout
        self.parentSize = parentSize
        if isChatList && layout == .minimisize {
            let side: CGFloat = 40
            genericView.setFrameSize(NSMakeSize(side, side))
            genericView.layer?.cornerRadius = side / 2
            genericView.centerX(y: parentSize.height - side - 10)
            shakeDisposable.set(nil)
        } else if isChatList {
            genericView.setFrameSize(NSMakeSize(genericView.preferredWidth, 40))
            genericView.layer?.cornerRadius = genericView.frame.height / 2
            let bottom = parentSize.height - genericView.frame.height
            genericView.centerX(y: bottom - 60)

            let shakeDelay: Double = 60 * 60


            let signal = Signal<Void, NoError>.single(Void()) |> delay(shakeDelay, queue: .mainQueue()) |> then(.single(Void()) |> delay(shakeDelay, queue: .mainQueue()) |> restart)
            self.shakeDisposable.set(signal.start(next: { [weak self] in
                self?.genericView.shake(beep: false)
            }))
        } else {
            genericView.setFrameSize(NSMakeSize(parentSize.width, 60))
            let bottom = parentSize.height - genericView.frame.height
            genericView.setFrameOrigin(NSMakePoint(0, layout == .minimisize ? bottom : bottom - 60))
            genericView.layer?.cornerRadius = 0
            shakeDisposable.set(nil)
        }
    }
    
    deinit {
        disposable.dispose()
        stateDisposable.dispose()
        shakeDisposable.dispose()
    }
}


final class MainController_View: View {
    private let bgView: View = View()
    private let glassView: LiquidGlassView

    /// 20pt on macOS 26+ to match the liquid-glass aesthetic (on macOS 27
    /// the window radius is raised to 28pt through private API, keeping
    /// this inset pane concentric). Older systems keep the subtle 8pt.
    private static var containerCornerRadius: CGFloat {
        if #available(macOS 26.0, *) {
            return 20
        }
        return 8
    }

    /// In single-window mode the surrounding chrome is smaller, so the
    /// inner corner shrinks to match: 14pt on macOS Tahoe (liquid glass),
    /// 4pt on older systems where the curve is already subtle.
    var compactCorners: Bool = false {
        didSet {
            if compactCorners != oldValue {
                applyCornerRadius()
            }
        }
    }

    private var currentCornerRadius: CGFloat {
        if compactCorners {
            return 0
        }
        return MainController_View.containerCornerRadius
    }

    private func applyCornerRadius() {
        let radius = currentCornerRadius
        bgView.layer?.cornerRadius = radius
        glassView.cornerRadius = radius
    }

    required init(frame frameRect: NSRect) {
        let cornerRadius = MainController_View.containerCornerRadius
        glassView = LiquidGlassView(frame: frameRect.size.bounds, cornerRadius: cornerRadius, hasShadow: true, hasBorder: true, tintAlpha: 0, customTint: presentation.colors.background, forceBlur: true)
        super.init(frame: frameRect)

        self.layer?.masksToBounds = false
        self.backgroundColor = .clear

        bgView.backgroundColor = presentation.colors.background
        bgView.layer?.cornerRadius = cornerRadius
        bgView.layer?.masksToBounds = true

        addSubview(bgView)
        addSubview(glassView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        bgView.backgroundColor = theme.colors.background
        glassView.customTint = theme.colors.background
    }

    override func layout() {
        super.layout()
        updateLayout(size: bounds.size, transition: .immediate)
    }

    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: bgView, frame: CGRect(origin: .zero, size: size))
        transition.updateFrame(view: glassView, frame: CGRect(origin: .zero, size: size))
        glassView.updateLayout(size: size, transition: transition)
    }
}

class MainViewController: TelegramGenericViewController<MainController_View> {

    let chatList: ChatListController
    let navigation: NavigationViewController
    let tabController:TabBarController = TabBarController()
    let contacts:NavigationViewController
    let settings:AccountViewController
    private let phoneCalls:RecentCallsViewController
    private let layoutDisposable:MetaDisposable = MetaDisposable()
    private let updateController: UpdateTabController
    private let connectingStatusView: ConnectingStatusView = ConnectingStatusView(frame: NSRect(origin: .zero, size: ConnectingStatusView.collapsedSize))
    private let connectingStatusDisposable = MetaDisposable()

    override var containerCornerRadius: CGFloat {
        return 0
    }

    override func initializer() -> MainController_View {
        return MainController_View(frame: _frameRect)
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func viewDidResized(_ size: NSSize) {
        super.viewDidResized(size)
        self.genericView.updateLayout(size: bounds.size, transition: .immediate)
        tabController.view.frame = bounds
        self.navigation.frame = bounds
        self.contacts.frame = bounds
        updateController.updateLayout(context.layout, parentSize: size, isChatList: true)
        updateChatListBottomOverlays()
        layoutConnectingStatusView()
    }

    private func updateChatListBottomOverlays() {
        let updateView = updateController.genericView
        let activeController = tabController.current === navigation ? navigation.controller : nil
        if activeController?.isLoaded() != true || !(activeController?.view is PeerListContainerView) {
            let bottomInset: CGFloat = tabController.contentBottomInset + 12
            updateView.setFrameOrigin(NSMakePoint(updateView.frame.minX, bounds.height - updateView.frame.height - bottomInset))
        }
        let updateContainer: (ViewController) -> Void = { [weak self, updateView] controller in
            guard controller.isLoaded(), let listView = controller.view as? PeerListContainerView else {
                return
            }
            listView.layoutBottomOverlay = { [weak self, weak listView, weak updateView] bottomY, transition in
                guard let self, self.tabController.current === self.navigation, self.navigation.controller.view === listView,
                      let listView, let updateView, !updateView.isHidden, let container = updateView.superview, listView.isDescendant(of: container) else {
                    return nil
                }
                let gap: CGFloat = 12
                let bottom = container.convert(NSMakePoint(0, bottomY), from: listView).y
                var rect = updateView.frame
                rect.origin.y = bottom - rect.height - gap
                if rect != updateView.frame {
                    transition.updateFrame(view: updateView, frame: rect)
                }
                return listView.convert(rect, from: container)
            }
            listView.updateBottomControls(size: listView.frame.size, transition: .immediate)
        }
        updateContainer(navigation.controller)
        navigation.enumerateControllers { controller, _ in
            updateContainer(controller)
            return false
        }
    }

    override var absorbsNavigationHeaderOverflow: Bool {
        return true
    }

    private func layoutConnectingStatusView() {
        let size = connectingStatusView.frame.size
        let y = bounds.height - size.height - tabController.contentBottomInset - 12
        connectingStatusView.setFrameOrigin(NSMakePoint(20, y))
    }
    
    

    override func loadView() {
        
        
        self.contacts.applyAppearOnLoad = false
        self.contacts._frameRect = self._frameRect

        tabController._frameRect = self._frameRect
        self.navigation._frameRect = self._frameRect

        super.loadView()
        
        let context = self.context
        
        

        self.bar = .init(height: 0)
        self.tabController.bar = .init(height: 0)

        addSubview(self.tabController.view)

        if !context.isSupport {
            addSubview(updateController.view)
            updateController.genericView.bottomOverlayChanged = { [weak self] in
                self?.updateChatListBottomOverlays()
            }
        }

        navigation.controllerDidChange = { [weak self] in
            self?.updateChatListBottomOverlays()
        }

        connectingStatusView.isHidden = true
        addSubview(connectingStatusView)
        connectingStatusDisposable.set((context.networkStatusManager.statusSignal |> deliverOnMainQueue).start(next: { [weak self] status in
            guard let self = self else { return }
            self.connectingStatusView.isHidden = status == nil
            self.connectingStatusView.update(status: status, animated: true)
            self.layoutConnectingStatusView()
        }))
                
        tabController.add(tab: TabAnimatedItem(.tab_contacts, image: theme.icons.tab_contacts, selectedImage: theme.icons.tab_contacts_active, controller: contacts))
        
        tabController.add(tab: TabAnimatedItem(.tab_calls, image: theme.icons.tab_calls, selectedImage: theme.icons.tab_calls_active, controller: phoneCalls))
        
        tabController.add(tab: TabBadgeItem(context, controller: navigation, image: theme.icons.tab_chats, selectedImage: theme.icons.tab_chats_active, longHoverHandler: { [weak self] control in
            self?.showFastChatSettings(control)
        }))
        
        tabController.add(tab: TabAllBadgeItem(context, image: theme.icons.tab_settings, selectedImage: theme.icons.tab_settings_active, controller: settings, longHoverHandler: { [weak self] control in
            self?.showFastSettings(control)
        }))
        
        
        tabController.updateLocalizationAndTheme(theme: theme)

        updateTabAccessibility()

        self.ready.set(combineLatest(queue: prepareQueue, self.chatList.ready.get(), self.settings.ready.get()) |> map { $0 && $1 })
        
        
        
        layoutDisposable.set(context.layoutValue.start(next: { [weak self] state in
            guard let `self` = self else {
                return
            }
            self.tabController.hideTabView(state == .minimisize)
            if state == .minimisize {
                self.tabController.select(index: self.chatIndex)
            }
            self.updateController.updateLayout(state, parentSize: self.frame.size, isChatList: true)
            self.updateChatListBottomOverlays()
            self.layoutConnectingStatusView()
        }))
        
        tabController.didChangedIndex = { [weak self] index in
            self?.checkSettings(index)
            self?.updateChatListBottomOverlays()
        }
    }
    
    func prepareControllers() {
        chatList.loadViewIfNeeded(bounds)
        settings.loadViewIfNeeded(bounds)
    }

    private func showContactsTab() {
        tabController.insert(tab: TabAnimatedItem(.tab_contacts, image: theme.icons.tab_contacts, selectedImage: theme.icons.tab_contacts_active, controller: contacts), at: 0)
        previousIndex = tabController.selectedIndex
        updateTabAccessibility()
    }

    private func hideContactsTab() {
        tabController.remove(at: 0)
        previousIndex = tabController.selectedIndex
    }

    private func showCallsTab() {
        tabController.insert(tab: TabAnimatedItem(.tab_calls, image: theme.icons.tab_calls, selectedImage: theme.icons.tab_calls_active, controller: phoneCalls), at: showContactTabs ? 1 : 0)
        previousIndex = tabController.selectedIndex
        updateTabAccessibility()
    }
    private func hideCallsTab() {
        tabController.remove(at: showContactTabs ? 1 : 0)
        previousIndex = tabController.selectedIndex
    }
    
    override var removeAfterDisapper: Bool {
        return false
    }
    
    private var showCallTabs: Bool = true
    private var showContactTabs: Bool = true
    
    override func viewDidLoad() {
        super.viewDidLoad()
                
        tabController.navigationController = navigation
                
        prefDisposable.set((baseAppSettings(accountManager: context.sharedContext.accountManager) |> deliverOnMainQueue).start(next: { [weak self] settings in
            guard let `self` = self else {return}
            if settings.showCallsTab != self.showCallTabs {
                self.showCallTabs = settings.showCallsTab
                if self.showCallTabs {
                    self.showCallsTab()
                } else {
                    self.hideCallsTab()
                }
            }
            if settings.showContactsTab != self.showContactTabs {
                self.showContactTabs = settings.showContactsTab
                if self.showContactTabs {
                    self.showContactsTab()
                } else {
                    self.hideContactsTab()
                }
            }
        }))

    }
    
    private func _showFastChatSettings(_ control: Control, unreadCount: Int32) {
        var items: [ContextMenuItem] = []
        let context = self.context
        
        if unreadCount > 0 {
            items.append(ContextMenuItem(strings().chatListPopoverReadAll, handler: {
                verifyAlert_button(for: context.window, information: strings().chatListPopoverConfirm, successHandler: { _ in
                    _ = context.engine.messages.markAllChatsAsReadInteractively(items: [(.root, nil), (.archive, nil)]).start()
                })
            }, itemImage: MenuAnimation.menu_folder_read.value))
        }
        
        if self.tabController.current == navigation, !items.isEmpty, let event = NSApp.currentEvent {
            let menu = ContextMenu(betterInside: true)
            for item in items {
                menu.addItem(item)
            }
            AppMenu.show(menu: menu, event: event, for: control)
        }
    }
    
    func showFastChatSettings() {
        self.showFastChatSettings(tabController.control(for: self.chatIndex))
    }
    
    private func showFastChatSettings(_ control: Control) {
        
        let context = self.context
        let unreadCountsKey = PostboxViewKey.unreadCounts(items: [.total(nil)])
        
        _ = (context.account.postbox.combinedView(keys: [unreadCountsKey]) |> take(1) |> deliverOnMainQueue).start(next: { [weak self, weak control] view in
            let totalUnreadState: ChatListTotalUnreadState
            if let value = view.views[unreadCountsKey] as? UnreadMessageCountsView, let (_, total) = value.total() {
                totalUnreadState = total
            } else {
                totalUnreadState = ChatListTotalUnreadState(absoluteCounters: [:], filteredCounters: [:])
            }
            let total = totalUnreadState.absoluteCounters.reduce(0, { current, value in
                return current + value.value.messageCount
            })
            if let control = control {
                self?._showFastChatSettings(control, unreadCount: total)
            }
        })
    }
    private let filterMenuDisposable = MetaDisposable()
    private let settingsDisposable = MetaDisposable()
    private let prefDisposable = MetaDisposable()
    private weak var quickController: ViewController?
    private func showFastSettings(_ control:Control) {
        
        
        let passcodeData = context.sharedContext.accountManager.transaction { transaction -> PostboxAccessChallengeData in
            return transaction.getAccessChallengeData()
        } |> deliverOnMainQueue

        let applicationSettings = appNotificationSettings(accountManager: context.sharedContext.accountManager) |> take(1)  |> deliverOnMainQueue


        settingsDisposable.set(combineLatest(passcodeData, applicationSettings, context.sharedContext.activeAccountsWithInfo |> take(1) |> map {$0.accounts} |> deliverOnMainQueue).start(next: { [weak self] passcode, notifications, accounts in
            self?._showFast(control: control, accounts: accounts, passcodeData: passcode, notifications: notifications)
        }))
        
       
    }
    
    private func _showFast( control: Control, accounts: [AccountWithInfo], passcodeData: PostboxAccessChallengeData, notifications: InAppNotificationSettings) {
        

        var items:[ContextMenuItem] = []
        let context = self.context
        
        func makeItem(_ account: AccountWithInfo) -> ContextMenuItem {
            let item = ContextAccountMenuItem(account: account, context: context, handler: {
                context.sharedContext.switchToAccount(id: account.account.id, action: nil)
            })
            return item
        }
        
        if !context.isSupport {
            for account in accounts {
                if account.account.id != context.account.id {
                    items.append(makeItem(account))
                }
            }
            if !items.isEmpty {
                items.append(ContextSeparatorItem())
            }
        }
        
        switch passcodeData {
        case .none:
            items.append(ContextMenuItem(strings().fastSettingsSetPasscode, handler: { [weak self] in
                guard let `self` = self else {return}
                self.tabController.select(index: self.tabController.count - 1)
                self.context.bindings.rootNavigation().push(PasscodeSettingsViewController(self.context))
            }, itemImage: MenuAnimation.menu_lock.value))
        default:
            items.append(ContextMenuItem(strings().fastSettingsLockTelegram, handler: {
                context.window.sendKeyEvent(KeyboardKey.L, modifierFlags: [.command])
            }, itemImage: MenuAnimation.menu_lock.value))
        }
        items.append(ContextMenuItem(theme.colors.isDark ? strings().fastSettingsDisableDarkMode : strings().fastSettingsEnableDarkMode, handler: {
            toggleDarkMode(context: context)
        }, itemImage: theme.colors.isDark ? MenuAnimation.menu_sun.value : MenuAnimation.menu_moon.value))
       
        
        let time = Int32(Date().timeIntervalSince1970)
        let unmuted = notifications.muteUntil < time
        items.append(ContextMenuItem(unmuted ? strings().fastSettingsMute2Hours : strings().fastSettingsUnmute, handler: { [weak self] in
            if let context = self?.context {
                let time = Int32(Date().timeIntervalSince1970 + 2 * 60 * 60)
                _ = updateInAppNotificationSettingsInteractively(accountManager: context.sharedContext.accountManager, {$0.withUpdatedMuteUntil(unmuted ? time : 0)}).start()
            }
            
        }, itemImage: notifications.muteUntil < time ? MenuAnimation.menu_mute.value : MenuAnimation.menu_unmuted.value))
        
        if let event = NSApp.currentEvent {
            let menu = ContextMenu(betterInside: true)
            for item in items {
                menu.addItem(item)
            }
            AppMenu.show(menu: menu, event: event, for: control)
        }
        
//        let controller = SPopoverViewController(items: items, visibility: 10, headerItems: headerItems)
//        showPopover(for: control, with: controller, edge: .maxX, inset: NSMakePoint(control.frame.width - 12, 0))
//        self.quickController = controller
    }
    private var previousTheme:TelegramPresentationTheme?
    private var previousIconColor:NSColor?
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        tabController.updateLocalizationAndTheme(theme: theme)

        navigation.hasBarRightBorder = true
        navigation.hasBarLeftBorder = true


        let theme = (theme as! TelegramPresentationTheme)
        //#if !APP_STORE
        updateController.updateLocalizationAndTheme(theme: theme)
        //#endif

        updateTabsIfNeeded()
        self.tabController.view.needsLayout = true
    }
    
    private func updateTabsIfNeeded() {
        if !tabController.isEmpty && (previousTheme?.colors != theme.colors ||  previousIconColor != theme.colors.accentIcon) {
            var index: Int = 0
            if showContactTabs {
                tabController.replace(tab: tabController.tab(at: index).withUpdatedImages(theme.icons.tab_contacts, theme.icons.tab_contacts_active), at: index)
                index += 1
            }
            if showCallTabs {
                tabController.replace(tab: tabController.tab(at: index).withUpdatedImages(theme.icons.tab_calls, theme.icons.tab_calls_active), at: index)
                index += 1
            }
            
            tabController.replace(tab: tabController.tab(at: index).withUpdatedImages(theme.icons.tab_chats, theme.icons.tab_chats_active), at: index)
            index += 1
            tabController.replace(tab: tabController.tab(at: index).withUpdatedImages(theme.icons.tab_settings, theme.icons.tab_settings_active), at: index)
        }
        self.previousTheme = theme
        self.previousIconColor = theme.colors.accentIcon
        updateTabAccessibility()
    }

    private func updateTabAccessibility() {
        for index in 0 ..< tabController.count {
            let tab = tabController.tab(at: index)
            let title: String
            if tab.controller === contacts {
                title = strings().contactsContacsSeparator
            } else if tab.controller === phoneCalls {
                title = strings().telegramLayoutRecentCallsViewController
            } else if tab.controller === settings {
                title = strings().telegramLayoutAccountController
            } else {
                title = strings().peerMediaSavedMessages
            }
            tab.accessibilityTitle = title
            let control = tabController.control(for: index)
            control.setAccessibilityLabel(title)
            control.toolTip = title
        }
    }
    
    private var previousIndex: Int? = nil
    
    func checkSettings(_ index:Int) {
        let isSettings = tabController.tab(at: index).controller is AccountViewController
        
        let navigation = context.bindings.rootNavigation()
        
        if let controller = navigation.controller as? InputDataController, controller.identifier == "wallet-create" {
            self.previousIndex = index
            quickController?.popover?.hide()
        } else {
            if previousIndex == tabController.count - 1 || isSettings {
                if isSettings && context.layout != .single {
                    navigation.push(GeneralSettingsViewController(context), false)
                } else {
                    navigation.enumerateControllers( { controller, index in
                        if (controller is ChatController) || (controller is PeerInfoController) || (controller is ChannelAdminsViewController) || (controller is ChannelAdminsViewController) || (controller is EmptyChatViewController) {
                            self.backFromSettings(index)
                            return true
                        }
                        return false
                    })
                }
            }
            self.previousIndex = index
            quickController?.popover?.hide()
        }
    }
    
    private func backFromSettings(_ index:Int) {
        context.bindings.rootNavigation().to(index: index)
    }
    
    override func focusSearch(animated: Bool, text: String? = nil) {
        if context.layout == .minimisize {
            return
        }
        let animated = animated && (context.layout != .single || context.bindings.rootNavigation().stackCount == 1)
        if context.layout == .single {
            context.bindings.rootNavigation().close()
        }
        if let current = tabController.current {
            if current is AccountViewController {
                tabController.select(index: chatIndex)
            }
            tabController.current?.focusSearch(animated: animated, text: text)
        }
    }
    
    override func getCenterBarViewOnce() -> TitledBarView {
        return TitledBarView(controller: self)
    }
    private var firstTime: Bool = true
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigation.viewDidAppear(animated)
        if firstTime {
            firstTime = false
        }
    }
    
    func globalSearch(_ query: String, peerId: PeerId?, cached: CachedSearchMessages?) {
        
        var query = query
        
        let result = extractHashtagAndUsername(from: query)
        
        let peerSignal: Signal<EnginePeer?, NoError>
        
        if let username = result?.username {
            peerSignal = context.engine.peers.resolvePeerByName(name: username, referrer: nil) |> mapToSignal { value in
                switch value {
                case let .result(peer):
                    return .single(peer)
                case .progress:
                    return .never()
                }
            } |> deliverOnMainQueue
            query = result?.hashtag ?? query
        } else if let peerId {
            peerSignal = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)) |> deliverOnMainQueue
        } else {
            peerSignal = .single(nil)
        }
        
        let rootController = navigation.empty

        let searchHost: PeersListController?
        if let controller = navigation.controller as? ChatListController, controller.mode == .folder(.archive) {
            searchHost = controller
        } else {
            searchHost = (navigation.controller as? CommunityListController)
                ?? (rootController as? ChatListController)
                ?? ((rootController as? TabBarController)?.current as? ChatListController)
        }

        guard let searchHost else {
            return
        }

        _ = peerSignal.startStandalone(next: { [weak searchHost] peer in
            searchHost?.globalSearch(
                query,
                peer: peer,
                cached: cached,
                isSuperTag: result != nil
            )
        })
    }
    
    func makeDownloadSearch() {
        if self.tabController.current == navigation {
            let controller = navigation.controller
            if let controller = controller as? ChatListController {
                controller.makeDownloadSearch()
            } else if let controller = controller as? TabBarController {
                (controller.current as? ChatListController)?.makeDownloadSearch()
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigation.viewWillAppear(animated)
        self.tabController.current?.viewWillAppear(animated)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigation.viewWillDisappear(animated)
        self.tabController.current?.viewWillDisappear(animated)
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        navigation.viewDidDisappear(animated)
        self.tabController.current?.viewDidDisappear(animated)
    }
    
    override func didRemovedFromStack() {
        super.didRemovedFromStack()
    }
    
    var chatIndex: Int {
        return (showContactTabs ? 1 : 0) + (showCallTabs ? 1 : 0)
    }
    
    var settingsIndex: Int {
        return chatIndex + 1
    }
    
    
    func openChat(_ index: Int, force: Bool = false) {
        if self.tabController.current == navigation {
            let controller = navigation.controller
            if let controller = controller as? ChatListController {
                controller.openChat(index, force: force)
            } else if let controller = controller as? TabBarController {
                (controller.current as? ChatListController)?.openChat(index, force: force)
            }
        }
    }

    func showPreferences() {
        if self.context.layout != .minimisize {
            if self.context.layout == .single {
                self.navigationController?.close()
            }
            self.tabController.select(index:settingsIndex)
        }
    }

    func showCalls() {
        if showCallTabs {
            context.bindings.switchSplitLayout(.dual)
            if self.context.layout != .minimisize {
                if self.context.layout == .single {
                    self.navigationController?.close()
                }
                self.tabController.select(index: showContactTabs ? 1 : 0)
            }
        }
    }
    
    var effectiveNavigation: NavigationViewController {
        return self.navigation
    }
    
    func showChatList() {
       self.tabController.select(index: self.chatIndex)
    }
    
    override var responderPriority: HandlerPriority {
        return context.layout == .single ? .medium : .low
    }
    
    func isCanMinimisize() -> Bool{
        let current = self.tabController.current
        return current == navigation
    }
    
    override func updateFrame(_ frame: NSRect, transition: ContainedViewLayoutTransition) {
        super.updateFrame(frame, transition: transition)
        self.tabController.updateFrame(frame.size.bounds, transition: transition)
    }
    
    override init(_ context: AccountContext) {

        self.chatList = ChatListController(context, mode: .plain)
        self.contacts = NavigationViewController(ContactsController(context), context.window)
        self.settings = AccountViewController(context)
        self.phoneCalls = RecentCallsViewController(context)
        self.navigation = NavigationViewController(self.chatList, context.window)

            updateController = UpdateTabController(context.sharedContext)
        super.init(context)
        
        self.insets.right = 0
    }

    deinit {
        layoutDisposable.dispose()
        prefDisposable.dispose()
        settingsDisposable.dispose()
        filterMenuDisposable.dispose()
        connectingStatusDisposable.dispose()
    }
}
