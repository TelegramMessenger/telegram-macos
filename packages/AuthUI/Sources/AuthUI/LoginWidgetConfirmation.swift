import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramContext
import TelegramTheme
import TelegramUtils
import Localization
import InputDataUI
import GeneralRows
import AvatarUI
import AlertsUI
import PhoneNumberUtils
import InlineStickerLayer
import AppAnalytics

private final class Arguments {
    let context: any AccountContextProtocol
    let toggleAllowMessages: () -> Void
    let dismiss: () -> Void
    let cancel: () -> Void
    let confirm: () -> Void
    let selectAccount: (AccountRecordId) -> Void
    let selectMatchCode: (String) -> Void

    init(context: any AccountContextProtocol,
         toggleAllowMessages: @escaping () -> Void,
         dismiss: @escaping () -> Void,
         cancel: @escaping () -> Void,
         confirm: @escaping () -> Void,
         selectAccount: @escaping (AccountRecordId) -> Void,
         selectMatchCode: @escaping (String) -> Void) {
        self.context = context
        self.toggleAllowMessages = toggleAllowMessages
        self.dismiss = dismiss
        self.cancel = cancel
        self.confirm = confirm
        self.selectAccount = selectAccount
        self.selectMatchCode = selectMatchCode
    }
}

// MARK: - State

private struct DeviceInfo: Equatable {
    let platform: String
    let browser: String
}

private struct LocationInfo: Equatable {
    let ip: String
    let region: String
}

private struct State: Equatable {
    var domain: String
    var bot: EnginePeer
    var clientData: MessageActionUrlAuthResult.ClientData?
    var flags: MessageActionUrlAuthResult.Flags
    var logoUrl: String? = nil
    var allowMessages: Bool = false
    var accounts: [AccountWithInfo] = []
    var selectedAccountId: AccountRecordId? = nil
    var matchCodes: [String]? = nil
    var selectedMatchCode: String? = nil
    var matchCodeVerified: Bool = false
    var animatedEmojiStickers: [String: StickerPackItem] = [:]

    var isApp: Bool {
        return clientData?.isApp == true
    }
    var displayName: String {
        if isApp {
            return clientData?.appName ?? strings().loginWidgetUnverifiedApp
        }
        return domain
    }

    var device: DeviceInfo? {
        guard let clientData = clientData else { return nil }
        return DeviceInfo(platform: clientData.platform, browser: clientData.browser)
    }

    var location: LocationInfo? {
        guard let clientData = clientData else { return nil }
        return LocationInfo(ip: clientData.ip, region: clientData.region)
    }

    var requestWriteAccess: Bool {
        return flags.contains(.requestWriteAccess)
    }

    var requestPhoneNumber: Bool {
        return flags.contains(.requestPhoneNumber)
    }

    var showMatchCodesFirst: Bool {
        return flags.contains(.showMatchCodesFirst)
    }

    var isSelectionMode: Bool {
        if showMatchCodesFirst {
            return matchCodes != nil && !matchCodeVerified
        }
        return matchCodes != nil && selectedMatchCode == nil
    }

    static func == (lhs: State, rhs: State) -> Bool {
        return lhs.domain == rhs.domain &&
            lhs.bot == rhs.bot &&
            lhs.clientData == rhs.clientData &&
            lhs.flags == rhs.flags &&
            lhs.logoUrl == rhs.logoUrl &&
            lhs.allowMessages == rhs.allowMessages &&
            lhs.accounts == rhs.accounts &&
            lhs.selectedAccountId == rhs.selectedAccountId &&
            lhs.matchCodes == rhs.matchCodes &&
            lhs.selectedMatchCode == rhs.selectedMatchCode &&
            lhs.matchCodeVerified == rhs.matchCodeVerified &&
            lhs.animatedEmojiStickers.keys == rhs.animatedEmojiStickers.keys
    }
}

// MARK: - Entry Identifiers

private let _id_header = InputDataIdentifier("_id_header")
private let _id_domain_title = InputDataIdentifier("_id_domain_title")
private let _id_permission_info = InputDataIdentifier("_id_permission_info")
private let _id_device_info = InputDataIdentifier("_id_device_info")
private let _id_device_warning = InputDataIdentifier("_id_device_warning")
private let _id_allow_messages = InputDataIdentifier("_id_allow_messages")
private let _id_allow_messages_info = InputDataIdentifier("_id_allow_messages_info")
private let _id_buttons = InputDataIdentifier("_id_buttons")
private let _id_numbers = InputDataIdentifier("_id_numbers")

// MARK: - Entries

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []

    var sectionId: Int32 = 0
    var index: Int32 = 0

    // Header with dismiss and account selector
    struct HeaderTuple: Equatable {
        let logoUrl: String?
        let accounts: [AccountWithInfo]
        let selectedAccountId: AccountRecordId?
        let showLogo: Bool
    }

    if state.isSelectionMode, let matchCodes = state.matchCodes {

        let headerTuple = HeaderTuple(logoUrl: state.logoUrl, accounts: state.accounts, selectedAccountId: state.selectedAccountId, showLogo: false)
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: .init(headerTuple), comparable: nil, item: { initialSize, stableId in
            return LoginWidgetHeaderItem(initialSize, stableId: stableId, context: arguments.context, logoUrl: state.logoUrl, bot: state.bot, accounts: state.accounts, selectedAccountId: state.selectedAccountId, showLogo: false, dismiss: arguments.dismiss, selectAccount: arguments.selectAccount)
        }))
        index += 1

        entries.append(.sectionId(sectionId, type: .customModern(10)))
        sectionId += 1

        struct MatchCodesTuple: Equatable {
            let matchCodes: [String]
            let selectedMatchCode: String?
            let hasAnimatedEmoji: Bool
        }
        let matchCodesTuple = MatchCodesTuple(matchCodes: matchCodes, selectedMatchCode: state.selectedMatchCode, hasAnimatedEmoji: !state.animatedEmojiStickers.isEmpty)
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_numbers, equatable: .init(matchCodesTuple), comparable: nil, item: { initialSize, stableId in
            return LoginWidgetNumbersItem(initialSize, stableId: stableId, context: arguments.context, matchCodes: matchCodes, selectedMatchCode: state.selectedMatchCode, animatedEmojiStickers: state.animatedEmojiStickers, selectMatchCode: arguments.selectMatchCode)
        }))
        index += 1

        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1

        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_buttons, equatable: .init(true), comparable: nil, item: { initialSize, stableId in
            return LoginWidgetButtonsItem(initialSize, stableId: stableId, cancelOnly: true, cancel: arguments.cancel, confirm: {})
        }))
        index += 1

        entries.append(.sectionId(sectionId, type: .customModern(10)))
        sectionId += 1

    } else {

        let headerTuple = HeaderTuple(logoUrl: state.logoUrl, accounts: state.accounts, selectedAccountId: state.selectedAccountId, showLogo: true)
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: .init(headerTuple), comparable: nil, item: { initialSize, stableId in
            return LoginWidgetHeaderItem(initialSize, stableId: stableId, context: arguments.context, logoUrl: state.logoUrl, bot: state.bot, accounts: state.accounts, selectedAccountId: state.selectedAccountId, dismiss: arguments.dismiss, selectAccount: arguments.selectAccount)
        }))
        index += 1

        entries.append(.sectionId(sectionId, type: .customModern(10)))
        sectionId += 1

        // Domain title
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_domain_title, equatable: .init(state.displayName), comparable: nil, item: { initialSize, stableId in
            return LoginWidgetDomainItem(initialSize, stableId: stableId, domain: state.displayName, isApp: state.isApp)
        }))
        index += 1

        // Permission info text
        let permissionText: String
        if state.requestPhoneNumber {
            permissionText = strings().loginWidgetPermissionPhone
        } else {
            permissionText = strings().loginWidgetPermissionInfo
        }
        entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(permissionText, linkHandler: { _ in }), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem, alignment: .center)))
        index += 1


        entries.append(.sectionId(sectionId, type: .customModern(10)))
        sectionId += 1

        // Device and location info (only if clientData is available)
        if let device = state.device, let location = state.location {
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_device_info, data: .init(name: strings().loginWidgetDevice, color: theme.colors.text, type: .twoLinesContext(device.platform, device.browser), viewType: .firstItem)))
            index += 1

            let _id_location_info = InputDataIdentifier("_id_location_info")
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_location_info, data: .init(name: strings().loginWidgetIPAddress, color: theme.colors.text, type: .twoLinesContext(location.ip, location.region), viewType: .lastItem)))
            index += 1

            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().loginWidgetLoginAttemptInfo), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem, alignment: .center)))
            index += 1
        }

        // Allow messages toggle (only if requestWriteAccess is set)
        if state.requestWriteAccess {
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1

            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_allow_messages, data: .init(name: strings().loginWidgetAllowMessages, color: theme.colors.text, type: .switchable(state.allowMessages), viewType: .singleItem, action: {
                arguments.toggleAllowMessages()
            })))
            index += 1

            entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(strings().loginWidgetPermissionApplyTo(state.bot._asPeer().displayTitle), linkHandler: { _ in }), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
            index += 1
        }

        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1

        // Buttons row
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_buttons, equatable: .init(true), comparable: nil, item: { initialSize, stableId in
            return LoginWidgetButtonsItem(initialSize, stableId: stableId, confirmEnabled: true, cancel: arguments.cancel, confirm: arguments.confirm)
        }))
        index += 1

        entries.append(.sectionId(sectionId, type: .customModern(10)))
        sectionId += 1

    }

    return entries
}

private final class LoginWidgetHeaderItem: GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate let logoUrl: String?
    fileprivate let bot: EnginePeer?
    fileprivate let accounts: [AccountWithInfo]
    fileprivate let selectedAccountId: AccountRecordId?
    fileprivate let showLogo: Bool
    fileprivate let dismiss: () -> Void
    fileprivate let selectAccount: (AccountRecordId) -> Void

    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, logoUrl: String?, bot: EnginePeer? = nil, accounts: [AccountWithInfo], selectedAccountId: AccountRecordId?, showLogo: Bool = true, dismiss: @escaping () -> Void, selectAccount: @escaping (AccountRecordId) -> Void) {
        self.context = context
        self.logoUrl = logoUrl
        self.bot = bot
        self.accounts = accounts
        self.selectedAccountId = selectedAccountId
        self.showLogo = showLogo
        self.dismiss = dismiss
        self.selectAccount = selectAccount
        super.init(initialSize, stableId: stableId)
    }

    override func viewClass() -> AnyClass {
        return LoginWidgetHeaderView.self
    }

    override var accessibilityLabel: String? {
        return bot?._asPeer().displayTitle ?? strings().loginWidgetLogIn
    }

    override var height: CGFloat {
        return showLogo ? 100 : 50
    }
}

private final class LoginWidgetHeaderView: GeneralRowView {
    private let dismissButton = ImageButton()
    private let logoContainer = View()
    private let logoImageView = ImageView()
    private let logoAvatarView = AvatarControl(font: .avatar(24))
    private let accountButton = Control()
    private let accountAvatar = AvatarControl(font: .avatar(14))
    private let accountChevron = ImageView()
    private var accountGlass: NSView?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        self.layer?.masksToBounds = false

        dismissButton.setAccessibilityLabel(strings().voiceOverCommonClose)
        logoImageView.isAccessibilityDecorative = true
        accountChevron.isAccessibilityDecorative = true

        dismissButton.setFrameSize(30, 30)
        dismissButton.autohighlight = false
        dismissButton.scaleOnClick = true

        logoContainer.setFrameSize(80, 80)
        logoContainer.layer?.cornerRadius = 40
        logoContainer.layer?.borderWidth = 2
        logoContainer.layer?.borderColor = theme.colors.border.cgColor
        logoContainer.backgroundColor = theme.colors.grayBackground

        accountButton.layer?.masksToBounds = false
        
        logoImageView.setFrameSize(40, 40)

        logoAvatarView.setFrameSize(80, 80)
        logoAvatarView.userInteractionEnabled = false

        accountAvatar.setFrameSize(26, 26)
        accountAvatar.userInteractionEnabled = false

        accountButton.setFrameSize(60, 30)

        accountButton.scaleOnClick = true

        addSubview(dismissButton)
        addSubview(logoContainer)
        logoContainer.addSubview(logoImageView)
        addSubview(logoAvatarView)
        addSubview(accountButton)
        accountButton.addSubview(accountAvatar)
        accountButton.addSubview(accountChevron)

        let glass = LiquidGlassView(frame: NSZeroRect, cornerRadius: accountButton.frame.height / 2, hasShadow: true, hasBorder: true)
        accountButton.addSubview(glass, positioned: .below, relativeTo: nil)
        accountGlass = glass
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? LoginWidgetHeaderItem else { return }

        dismissButton.set(image: theme.icons.glass_close, for: .Normal)
        dismissButton.setGlassEffect(size: NSMakeSize(36, 36))
        dismissButton.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        dismissButton.removeAllHandlers()
        dismissButton.set(handler: { [weak item] _ in
            item?.dismiss()
        }, for: .Click)

        if let bot = item.bot, item.showLogo {
            logoAvatarView.setPeer(account: item.context.account, peer: bot._asPeer())
            logoAvatarView.isHidden = false
            logoContainer.isHidden = true
        } else {
            logoAvatarView.isHidden = !item.showLogo
            logoContainer.isHidden = !item.showLogo
            logoContainer.layer?.borderColor = theme.colors.border.cgColor
            logoContainer.backgroundColor = theme.colors.grayBackground
            logoImageView.image = TelegramThemeHooks.shared.image(.iconFragmentStarTopUp).precomposed()
            logoImageView.sizeToFit()
        }

        if let selectedAccount = item.accounts.first(where: { $0.account.id == item.selectedAccountId }) ?? item.accounts.first {
            accountAvatar.setPeer(account: selectedAccount.account, peer: selectedAccount.peer)
            accountButton.setAccessibilityLabel(selectedAccount.peer.displayTitle)
        }

        accountChevron.image = TelegramThemeHooks.shared.image(.iconDoubleChevron).precomposed(theme.colors.grayIcon)
        accountChevron.sizeToFit()

        accountButton.setSingle(handler: { [weak item, weak self] control in
            guard let item = item else { return }
            self?.showAccountMenu(item: item, control: control)
        }, for: .Click)

        accountButton.isHidden = item.accounts.count <= 1

        needsLayout = true
    }

    private func showAccountMenu(item: LoginWidgetHeaderItem, control: Control) {
        var items: [ContextMenuItem] = []

        for account in item.accounts {
            let menuItem = AuthUIHooks.shared.makeAccountMenuItem(account, item.context, false, { [weak item] in
                item?.selectAccount(account.account.id)
            })
            if account.account.id == item.selectedAccountId {
                menuItem.state = .on
            }
            items.append(menuItem)
        }

        let menu = ContextMenu()
        for menuItem in items {
            menu.addItem(menuItem)
        }
        AppMenu.show(menu: menu, event: NSApp.currentEvent!, for: control)
    }

    override func layout() {
        super.layout()
        dismissButton.setFrameOrigin(NSMakePoint(10, 10))
        logoContainer.centerX(y: 20)
        logoImageView.center()
        logoAvatarView.centerX(y: 10)
        accountButton.setFrameOrigin(NSMakePoint(frame.width - accountButton.frame.width - 10, 10))
        accountAvatar.setFrameOrigin(NSMakePoint(2, (accountButton.frame.height - accountAvatar.frame.height) / 2))
        accountChevron.setFrameOrigin(NSMakePoint(accountAvatar.frame.maxX + 2, (accountButton.frame.height - accountChevron.frame.height) / 2))
        accountGlass?.frame = accountButton.bounds
    }
}

// MARK: - Domain Item

private final class LoginWidgetDomainItem: GeneralRowItem {
    fileprivate let domain: String
    fileprivate let titleLayout: TextViewLayout

    init(_ initialSize: NSSize, stableId: AnyHashable, domain: String, isApp: Bool = false) {
        self.domain = domain
        let title = isApp ? strings().loginWidgetLogInToApp(domain) : strings().loginWidgetLogInTo(domain)
        self.titleLayout = TextViewLayout(.initialize(string: title, color: theme.colors.text, font: .medium(.header)), alignment: .center)
        super.init(initialSize, stableId: stableId)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        titleLayout.measure(width: width - 40)
        return true
    }

    override func viewClass() -> AnyClass {
        return LoginWidgetDomainView.self
    }

    override var accessibilityLabel: String? {
        return titleLayout.attributedString.string
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }

    override var height: CGFloat {
        return titleLayout.layoutSize.height + 5
    }
}

private final class LoginWidgetDomainView: GeneralRowView {
    private let textView = TextView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textView.isSelectable = false
        textView.userInteractionEnabled = false
        addSubview(textView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? LoginWidgetDomainItem else { return }
        textView.update(item.titleLayout)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        textView.centerX(y: 5)
    }
}

private final class LoginWidgetNumbersItem: GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate let matchCodes: [String]
    fileprivate let selectedMatchCode: String?
    fileprivate let selectMatchCode: (String) -> Void
    fileprivate let titleLayout: TextViewLayout
    fileprivate let subtitleLayout: TextViewLayout
    fileprivate let animatedEmojiStickers: [String: StickerPackItem]

    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, matchCodes: [String], selectedMatchCode: String?, animatedEmojiStickers: [String: StickerPackItem], selectMatchCode: @escaping (String) -> Void) {
        self.context = context
        self.matchCodes = matchCodes
        self.selectedMatchCode = selectedMatchCode
        self.selectMatchCode = selectMatchCode
        self.animatedEmojiStickers = animatedEmojiStickers
        self.titleLayout = TextViewLayout(.initialize(string: strings().loginWidgetConfirmationTapNumber, color: theme.colors.text, font: .medium(.header)), alignment: .center)
        self.subtitleLayout = TextViewLayout(.initialize(string: strings().loginWidgetConfirmationVerifyIdentity, color: theme.colors.listGrayText, font: .normal(.text)), alignment: .center)
        super.init(initialSize, stableId: stableId)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        titleLayout.measure(width: width - 40)
        subtitleLayout.measure(width: width - 40)
        return true
    }

    override func viewClass() -> AnyClass {
        return LoginWidgetNumbersView.self
    }

    override var accessibilityLabel: String? {
        return titleLayout.attributedString.string
    }

    override var accessibilityValue: String? {
        return subtitleLayout.attributedString.string
    }

    override var height: CGFloat {
        return titleLayout.layoutSize.height + 5 + subtitleLayout.layoutSize.height + 15 + 60
    }
}

private final class LoginWidgetNumbersView: GeneralRowView {
    private let titleView = TextView()
    private let subtitleView = TextView()
    private let numbersContainer = View()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleView.isSelectable = false
        titleView.userInteractionEnabled = false
        subtitleView.isSelectable = false
        subtitleView.userInteractionEnabled = false
        addSubview(titleView)
        addSubview(subtitleView)
        addSubview(numbersContainer)
        self.layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }

    private final class NumberButton: Control {
        private let label = InteractiveTextView()
        private var _glassView: NSView?

        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            label.userInteractionEnabled = false
            addSubview(label)
            self.layer?.masksToBounds = false
            let glass = LiquidGlassView(frame: NSZeroRect, cornerRadius: frameRect.height / 2, hasShadow: true, hasBorder: true)
            addSubview(glass, positioned: .below, relativeTo: label)
            _glassView = glass
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func update(code: String, isSelected: Bool, context: any AccountContextProtocol, animatedEmojiStickers: [String: StickerPackItem]) {
            let text: NSMutableAttributedString = .init()
            text.append(string: code, color: theme.colors.text, font: .medium(25))
            if let stickerItem = animatedEmojiStickers[code] {
                text.insertEmbedded(.embeddedAnimated(stickerItem.file._parse()), for: code)
            }
            let layout = TextViewLayout(text, alignment: .center)
            layout.measure(width: .greatestFiniteMagnitude)
            label.set(text: layout, context: context)
            setAccessibilityLabel(code)


            needsLayout = true
        }

        override func layout() {
            super.layout()
            label.center()
            _glassView?.frame = bounds
        }
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? LoginWidgetNumbersItem else { return }
        
        numbersContainer.layer?.masksToBounds = false

        while numbersContainer.subviews.count > item.matchCodes.count {
            numbersContainer.subviews.last?.removeFromSuperview()
        }
        while numbersContainer.subviews.count < item.matchCodes.count {
            numbersContainer.addSubview(NumberButton(frame: NSMakeRect(0, 0, 60, 60)))
        }

        for (i, code) in item.matchCodes.enumerated() {
            let button = numbersContainer.subviews[i] as! NumberButton
            button.update(code: code, isSelected: item.selectedMatchCode == code, context: item.context, animatedEmojiStickers: item.animatedEmojiStickers)
            button.setFrameSize(NSMakeSize(60, 60))
            button.scaleOnClick = true
            button.isEnabled = item.selectedMatchCode == nil
            button.removeAllHandlers()
            button.set(handler: { [weak item] _ in
                item?.selectMatchCode(code)
            }, for: .Click)
        }

        titleView.update(item.titleLayout)
        subtitleView.update(item.subtitleLayout)
        needsLayout = true
    }

    override func layout() {
        super.layout()

        guard let item = item as? LoginWidgetNumbersItem else { return }

        titleView.centerX(y: 0)
        subtitleView.centerX(y: titleView.frame.maxY + 5)

        let buttonWidth: CGFloat = 70
        let spacing: CGFloat = 15
        let totalWidth = CGFloat(item.matchCodes.count) * buttonWidth + CGFloat(max(0, item.matchCodes.count - 1)) * spacing
        var x: CGFloat = 0
        for subview in numbersContainer.subviews {
            subview.setFrameOrigin(NSMakePoint(x, 0))
            x += buttonWidth + spacing
        }
        numbersContainer.setFrameSize(NSMakeSize(totalWidth, 60))
        numbersContainer.centerX(y: subtitleView.frame.maxY + 15)
    }
}

// MARK: - Buttons Item

private final class LoginWidgetButtonsItem: GeneralRowItem {
    fileprivate let cancel: () -> Void
    fileprivate let confirm: () -> Void
    fileprivate let confirmEnabled: Bool
    fileprivate let cancelOnly: Bool

    init(_ initialSize: NSSize, stableId: AnyHashable, confirmEnabled: Bool = true, cancelOnly: Bool = false, cancel: @escaping () -> Void, confirm: @escaping () -> Void) {
        self.cancel = cancel
        self.confirm = confirm
        self.confirmEnabled = confirmEnabled
        self.cancelOnly = cancelOnly
        super.init(initialSize, stableId: stableId)
    }

    override func viewClass() -> AnyClass {
        return LoginWidgetButtonsView.self
    }

    override var accessibilityLabel: String? {
        return cancelOnly ? strings().loginWidgetCancel : strings().loginWidgetLogIn
    }

    override var height: CGFloat {
        return 50
    }
}

private final class LoginWidgetButtonsView: GeneralRowView {
    private let cancelButton = TextButton()
    private let confirmButton = TextButton()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(cancelButton)
        addSubview(confirmButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? LoginWidgetButtonsItem else { return }

        cancelButton.set(background: .clear, for: .Normal)
        cancelButton.set(color: .white, for: .Normal)
        cancelButton.setGlassEffect(tintColor: theme.colors.redUI)
        cancelButton.set(font: .medium(.text), for: .Normal)
        cancelButton.set(text: strings().loginWidgetCancel, for: .Normal)
        cancelButton.layer?.cornerRadius = 20
        cancelButton.autohighlight = false
        cancelButton.scaleOnClick = true
        cancelButton.removeAllHandlers()
        cancelButton.set(handler: { [weak item] _ in
            item?.cancel()
        }, for: .Click)

        confirmButton.isHidden = item.cancelOnly

        if !item.cancelOnly {
            let accentColor = item.confirmEnabled ? theme.colors.accent : theme.colors.accent.withAlphaComponent(0.5)
            confirmButton.set(background: .clear, for: .Normal)
            confirmButton.set(color: .white, for: .Normal)
            confirmButton.setGlassEffect(tintColor: accentColor)
            confirmButton.set(font: .medium(.text), for: .Normal)
            confirmButton.set(text: strings().loginWidgetLogIn, for: .Normal)
            confirmButton.layer?.cornerRadius = 20
            confirmButton.autohighlight = false
            confirmButton.scaleOnClick = true
            confirmButton.isEnabled = item.confirmEnabled
            confirmButton.removeAllHandlers()
            confirmButton.set(handler: { [weak item] _ in
                item?.confirm()
            }, for: .Click)
        }

        needsLayout = true
    }

    override func layout() {
        super.layout()

        guard let item = item as? LoginWidgetButtonsItem else { return }

        if item.cancelOnly {
            cancelButton.frame = NSMakeRect(20, 5, frame.width - 40, 40)
        } else {
            let buttonWidth = (frame.width - 60) / 2
            cancelButton.frame = NSMakeRect(20, 5, buttonWidth, 40)
            confirmButton.frame = NSMakeRect(cancelButton.frame.maxX + 20, 5, buttonWidth, 40)
        }
    }
}

public struct LoginWidgetData {
    public let domain: String
    public let bot: EnginePeer
    public let clientData: MessageActionUrlAuthResult.ClientData?
    public let flags: MessageActionUrlAuthResult.Flags
    public let subject: MessageActionUrlSubject
    public let matchCodes: [String]?
    public let userIdHint: EnginePeer.Id?

    public init(domain: String, bot: EnginePeer, clientData: MessageActionUrlAuthResult.ClientData?, flags: MessageActionUrlAuthResult.Flags, subject: MessageActionUrlSubject, matchCodes: [String]? = nil, userIdHint: EnginePeer.Id? = nil) {
        self.domain = domain
        self.bot = bot
        self.clientData = clientData
        self.flags = flags
        self.subject = subject
        self.matchCodes = matchCodes
        self.userIdHint = userIdHint
    }
}

public enum LoginWidgetResult {
    case accepted(url: String?)
    case cancelled
    case failed
}

public func LoginWidgetConfirmationController(context: any AccountContextProtocol, sharedContext: any SharedAccountContextProtocol, data: LoginWidgetData, completion: ((LoginWidgetResult) -> Void)? = nil) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    let initialState = State(
        domain: data.domain,
        bot: data.bot,
        clientData: data.clientData,
        flags: data.flags,
        matchCodes: data.matchCodes
    )

    let statePromise = ValuePromise<State>(ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    var close: (() -> Void)? = nil
    var getController:(()->ViewController?)? = nil

    var window:Window {
        get {
            return bestWindow(context, getController?())
        }
    }

    let performLogin: (Bool) -> Void = { sharePhoneNumber in
        let state = stateValue.with { $0 }
        let allowWriteAccess = state.allowMessages

        let account = state.accounts.first(where: { $0.account.id == state.selectedAccountId })?.account ?? context.account

        let engine = TelegramEngine(account: account)


        _ = showModalProgress(signal: engine.messages.acceptMessageActionUrlAuth(subject: data.subject, allowWriteAccess: allowWriteAccess, sharePhoneNumber: sharePhoneNumber, matchCode: state.selectedMatchCode), for: context.window).start(next: { result in
            switch result {
            case let .accepted(url):
                close?()
                if let completion = completion {
                    completion(.accepted(url: url))
                } else if let url = url {
                    LinkHooks.shared.openExternalLink(url, false)
                } else {
                    let successText: String
                    if state.requestPhoneNumber {
                        if sharePhoneNumber {
                            successText = strings().loginWidgetLoggedInSuccess(state.displayName)
                        } else {
                            successText = strings().loginWidgetLoggedInNoPhone(state.displayName)
                        }
                    } else {
                        successText = strings().loginWidgetLoggedInSuccess(state.displayName)
                    }
                    showModalText(for: context.window, text: successText)
                }
            case .default:
                close?()
                if let completion = completion {
                    completion(.failed)
                } else {
                    showModalText(for: context.window, text: strings().loginWidgetTryAgain(state.displayName))
                }
            default:
                break
            }
        }, error: { error in
            close?()
            if let completion = completion {
                completion(.failed)
            } else {
                showModalText(for: context.window, text: strings().loginWidgetTryAgain(state.displayName))
            }
        })
    }

    let arguments = Arguments(
        context: context,
        toggleAllowMessages: {
            updateState { current in
                var current = current
                current.allowMessages = !current.allowMessages
                return current
            }
        },
        dismiss: {
            close?()
        },
        cancel: {
            if case let .url(url, _) = data.subject {
                let account = stateValue.with({ $0 }).accounts.first(where: { $0.account.id == stateValue.with({ $0 }).selectedAccountId })?.account ?? context.account
                let engine = TelegramEngine(account: account)
                _ = engine.messages.declineUrlAuth(url: url).startStandalone()
            }
            completion?(.cancelled)
            close?()
        },
        confirm: {
            let state = stateValue.with { $0 }
            if state.requestPhoneNumber {
                let selectedAccount = state.accounts.first(where: { $0.account.id == state.selectedAccountId })
                var phoneNumber = ""
                if let user = selectedAccount?.peer as? TelegramUser, let phone = user.phone {
                    phoneNumber = formatPhoneNumber(phone)
                }
                let info = strings().loginWidgetPhoneAccessInfo(state.displayName, phoneNumber)
                verifyAlert_button(for: context.window, header: strings().loginWidgetPhoneNumber, information: info, ok: strings().loginWidgetAllow, cancel: strings().loginWidgetDeny, successHandler: { _ in
                    performLogin(true)
                }, cancelHandler: {
                    performLogin(false)
                })
            } else {
                performLogin(false)
            }
        },
        selectAccount: { accountId in
            updateState { current in
                var current = current
                current.selectedAccountId = accountId
                current.selectedMatchCode = nil
                current.matchCodeVerified = false
                return current
            }
            let account = stateValue.with({ $0 }).accounts.first(where: { $0.account.id == accountId })?.account ?? context.account
            let engine = TelegramEngine(account: account)
            actionsDisposable.add(engine.messages.requestMessageActionUrlAuth(subject: data.subject).start(next: { result in
                if case let .request(domain, bot, clientData, flags, matchCodes, _) = result {
                    updateState { current in
                        var current = current
                        current.domain = domain
                        current.bot = EnginePeer(bot)
                        current.clientData = clientData
                        current.flags = flags
                        current.matchCodes = matchCodes
                        return current
                    }
                }
            }))
        },
        selectMatchCode: { code in
            updateState { current in
                var current = current
                current.selectedMatchCode = code
                return current
            }
            let state = stateValue.with { $0 }
            if state.flags.contains(.showMatchCodesFirst), case let .url(url, _) = data.subject {
                let account = state.accounts.first(where: { $0.account.id == state.selectedAccountId })?.account ?? context.account
                let engine = TelegramEngine(account: account)
                actionsDisposable.add((engine.messages.checkUrlAuthMatchCode(url: url, matchCode: code) |> deliverOnMainQueue).start(next: { result in
                    if result {
                        updateState { current in
                            var current = current
                            current.matchCodeVerified = true
                            return current
                        }
                    } else {
                        close?()
                        completion?(.failed)
                    }
                }))
            }
        }
    )

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: "")
    
    getController = { [weak controller] in
        return controller
    }

    controller.analyticsScreen = initialState.isSelectionMode ? AnalyticsScreen.authWebsiteLoginMatchCode : AnalyticsScreen.authWebsiteLogin

    controller.afterTransaction = { controller in
        let screen = stateValue.with { $0.isSelectionMode } ? AnalyticsScreen.authWebsiteLoginMatchCode : AnalyticsScreen.authWebsiteLogin
        if controller.analyticsScreen != screen {
            controller.analyticsScreen = screen
            Analytics.shared.screens.show(ObjectIdentifier(controller), screen: screen)
        }
    }

    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    actionsDisposable.add(
        (context.diceCache.animatedEmojies |> deliverOnMainQueue).start(next: { emojies in
            updateState { current in
                var current = current
                current.animatedEmojiStickers = emojies
                return current
            }
        })
    )

    actionsDisposable.add(
        (sharedContext.activeAccountsWithInfo
            |> take(1)
            |> deliverOnMainQueue
        ).start(next: { primary, accounts in
            updateState { current in
                var current = current
                current.accounts = accounts
                if let userIdHint = data.userIdHint, let hintedAccount = accounts.first(where: { ($0.peer as? TelegramUser)?.id == userIdHint }) {
                    current.selectedAccountId = hintedAccount.account.id
                } else {
                    current.selectedAccountId = context.account.id
                }
                return current
            }
            if let userIdHint = data.userIdHint {
                let state = stateValue.with { $0 }
                if let hintedAccount = state.accounts.first(where: { ($0.peer as? TelegramUser)?.id == userIdHint }), hintedAccount.account.id != context.account.id {
                    let engine = TelegramEngine(account: hintedAccount.account)
                    actionsDisposable.add(engine.messages.requestMessageActionUrlAuth(subject: data.subject).start(next: { result in
                        if case let .request(domain, bot, clientData, flags, matchCodes, _) = result {
                            updateState { current in
                                var current = current
                                current.domain = domain
                                current.bot = EnginePeer(bot)
                                current.clientData = clientData
                                current.flags = flags
                                current.matchCodes = matchCodes
                                return current
                            }
                        }
                    }))
                }
            }
        })
    )

    let modalInteractions = ModalInteractions(acceptTitle: "", accept: {}, drawBorder: false, height: 0, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(340, 0))

    close = { [weak modalController] in
        modalController?.modal?.close()
    }

    return modalController
}

public func showLoginWidgetConfirmation(context: any AccountContextProtocol, sharedContext: any SharedAccountContextProtocol, data: LoginWidgetData, completion: ((LoginWidgetResult) -> Void)? = nil) {
    let controller = LoginWidgetConfirmationController(context: context, sharedContext: sharedContext, data: data, completion: completion)
    showModal(with: controller, for: context.window)
}

