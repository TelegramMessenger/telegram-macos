import Cocoa
import TGUIKit
import TelegramCore
import Localization
import Postbox
import SwiftSignalKit
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import TelegramMediaUtils
import GeneralRows
import ShortPeerRow
import InputDataUI
import AlertsUI
import LocalAnimations
import ProxyUtils
import ChatModeTypes
import CurrencyFormat




struct SetupPasswordConfiguration {
    
    let setup2Fa: Bool
    
    static func with(appConfiguration: AppConfiguration) -> SetupPasswordConfiguration {
        if let data = appConfiguration.data {
            return .init(setup2Fa: data["SETUP_PASSWORD"] != nil)
        } else {
            return .init(setup2Fa: false)
        }
    }
}

private final class AccountSearchBarView: View {
    fileprivate let searchView = SearchView(frame: NSMakeRect(0, 0, 100, 30))
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(searchView)
        updateLocalizationAndTheme(theme: theme)
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = theme as! TelegramPresentationTheme
        searchView.searchTheme = .init(theme.colors.background, theme.search.searchImage, theme.search.clearImage, {
            return strings().searchFieldSearch
        }, theme.search.textColor, theme.search.placeholderColor)
        searchView.layer?.borderWidth = 1
        searchView.layer?.borderColor = theme.colors.border.withAlphaComponent(0.75).cgColor
        needsLayout = true
    }
    
    override func layout() {
        super.layout()
        searchView.setFrameSize(NSMakeSize(frame.width - 20, 30))
        searchView.centerY(x: 10)
    }
    
}


fileprivate final class AccountInfoArguments<Context: AccountContextProtocol> {
    let context: Context
    var storyList: PeerStoryListContext
    let presentController:(ViewController, Bool) -> Void
    let openFaq:()->Void
    let ask:()->Void
    let openUpdateApp:() -> Void
    let openPremium:(Bool)->Void
    let giftPremium:()->Void
    let stars:()->Void
    let ton:()->Void
    let openWallet:()->Void
    let addAccount:([AccountWithInfo])->Void
    let setStatus:(Control, TelegramUser)->Void
    let runStatusPopover:()->Void
    let setProfileColor:(Peer)->Void
    let set2Fa:(TwoStepVeriticationAccessConfiguration?)->Void
    let openStory:(StoryInitialIndex?)->Void
    let openWebBot:(AttachMenuBot)->Void
    init(context: Context, storyList: PeerStoryListContext, presentController:@escaping(ViewController, Bool)->Void, openFaq: @escaping()->Void, ask:@escaping()->Void, openUpdateApp: @escaping() -> Void, openPremium:@escaping(Bool)->Void, giftPremium:@escaping()->Void, addAccount:@escaping([AccountWithInfo])->Void, setStatus:@escaping(Control, TelegramUser)->Void, runStatusPopover:@escaping()->Void, set2Fa:@escaping(TwoStepVeriticationAccessConfiguration?)->Void, openStory:@escaping(StoryInitialIndex?)->Void, openWebBot:@escaping(AttachMenuBot)->Void, stars:@escaping()->Void, ton:@escaping()->Void, openWallet:@escaping()->Void, setProfileColor:@escaping(Peer)->Void) {
        self.context = context
        self.storyList = storyList
        self.presentController = presentController
        self.openFaq = openFaq
        self.ask = ask
        self.openUpdateApp = openUpdateApp
        self.giftPremium = giftPremium
        self.openPremium = openPremium
        self.addAccount = addAccount
        self.setStatus = setStatus
        self.runStatusPopover = runStatusPopover
        self.set2Fa = set2Fa
        self.openStory = openStory
        self.openWebBot = openWebBot
        self.stars = stars
        self.ton = ton
        self.openWallet = openWallet
        self.setProfileColor = setProfileColor
    }
}


private enum AccountInfoEntryId : Hashable {
    case index(Int)
    case account(AccountWithInfo)
    
    func hash(into hasher: inout Hasher) {
        switch self {
        case let .index(value):
            hasher.combine(value)
        case let .account(info):
            hasher.combine(info.account.id.int64)
        }
    }
}

private final class AnyUpdateStateEquatable  : Equatable {
    let any: Any
    init(any: Any) {
        self.any = any
    }
    static func ==(lhs: AnyUpdateStateEquatable, rhs: AnyUpdateStateEquatable) -> Bool {
        return lhs === rhs
    }
}


private enum AccountInfoEntry<Context: AccountContextProtocol> : TableItemListNodeEntry {
    case info(index:Int, viewType: GeneralViewType, PeerEquatable, EngineStorySubscriptions.Item?)
    case setStatus(index:Int, viewType: GeneralViewType, PeerEquatable)
    case setProfileColor(index:Int, viewType: GeneralViewType, PeerEquatable)
    case set2FaAlert(index:Int, viewType: GeneralViewType)
    case set2Fa(index:Int, settings: TwoStepVeriticationAccessConfiguration?, viewType: GeneralViewType)
    case accountRecord(index: Int, viewType: GeneralViewType, info: AccountWithInfo)
    case addAccount(index: Int, [AccountWithInfo], viewType: GeneralViewType)
    case proxy(index: Int, viewType: GeneralViewType, status: String?)
    case stories(index: Int, viewType: GeneralViewType)
    case attach(index: Int, AttachMenuBot, viewType: GeneralViewType)
    case general(index: Int, viewType: GeneralViewType)
    case stickers(index: Int, viewType: GeneralViewType)
    case notifications(index: Int, viewType: GeneralViewType, status: NotificationAuthorizationStatus)
    case language(index: Int, viewType: GeneralViewType, current: String)
    case appearance(index: Int, viewType: GeneralViewType)
    case privacy(index: Int, viewType: GeneralViewType, AccountPrivacySettings?, TwoStepVeriticationAccessConfiguration?, WebSessionsContextState)
    case dataAndStorage(index: Int, viewType: GeneralViewType)
    case activeSessions(index: Int, viewType: GeneralViewType, activeSessions: Int)
    case passport(index: Int, viewType: GeneralViewType, peer: PeerEquatable)
    case update(index: Int, viewType: GeneralViewType, state: AnyUpdateStateEquatable)
    case filters(index: Int, viewType: GeneralViewType)
    case premium(index: Int, viewType: GeneralViewType)
    case business(index: Int, viewType: GeneralViewType)
    case giftPremium(index: Int, viewType: GeneralViewType)
    case stars(index: Int, count: StarsAmount, viewType: GeneralViewType)
    case ton(index: Int, count: StarsAmount, viewType: GeneralViewType)
    case wallet(index: Int, balance: Int64?, viewType: GeneralViewType)
    case about(index: Int, viewType: GeneralViewType)
    case faq(index: Int, viewType: GeneralViewType)
    case ask(index: Int, viewType: GeneralViewType)

    case whiteSpace(index:Int, height:CGFloat)
    
    var stableId: AccountInfoEntryId {
        switch self {
        case .info:
            return .index(0)
        case .setStatus:
            return .index(1)
        case .setProfileColor:
            return .index(2)
        case .set2FaAlert:
            return .index(3)
        case .set2Fa:
            return .index(4)
        case let .accountRecord(_, _, info):
            return .account(info)
        case .addAccount:
            return .index(5)
        case .stories:
            return .index(6)
        case .general:
            return .index(7)
        case .proxy:
            return .index(8)
        case .notifications:
            return .index(9)
        case .dataAndStorage:
            return .index(10)
        case .activeSessions:
            return .index(11)
        case .privacy:
            return .index(12)
        case .language:
            return .index(13)
        case .stickers:
            return .index(14)
        case .filters:
            return .index(15)
        case .update:
            return .index(16)
        case .appearance:
            return .index(17)
        case .passport:
            return .index(18)
        case .premium:
            return .index(19)
        case .business:
            return .index(20)
        case .giftPremium:
            return .index(21)
        case .stars:
            return .index(22)
        case .ton:
            return .index(23)
        case .faq:
            return .index(24)
        case .ask:
            return .index(25)
        case .wallet:
            return .index(999)
        case .about:
            return .index(26)
        case let .attach(index, _, _):
            return .index(27 + index)
        case let .whiteSpace(index, _):
            return .index(1000 + index)
        }
    }
    
    var index:Int {
        switch self {
        case let .info(index, _, _, _):
            return index
        case let .setStatus(index, _, _):
            return index
        case let .setProfileColor(index, _, _):
            return index
        case let .set2FaAlert(index, _):
            return index
        case let .set2Fa(index, _, _):
            return index
        case let .accountRecord(index, _, _):
            return index
        case let .addAccount(index, _, _):
            return index
        case let  .stories(index, _):
            return index
        case let .attach(index, _, _):
            return index
        case let  .general(index, _):
            return index
        case let  .proxy(index, _, _):
            return index
        case let .stickers(index, _):
            return index
        case let .notifications(index, _, _):
            return index
        case let .language(index, _, _):
            return index
        case let .appearance(index, _):
            return index
        case let .privacy(index, _, _, _, _):
            return index
        case let .dataAndStorage(index, _):
            return index
        case let .activeSessions(index, _, _):
            return index
        case let .about(index, _):
            return index
        case let .passport(index, _, _):
            return index
        case let .filters(index, _):
            return index
        case let .premium(index, _):
            return index
        case let .business(index, _):
            return index
        case let .giftPremium(index, _):
            return index
        case let .stars(index, _, _):
            return index
        case let .ton(index, _, _):
            return index
        case let .wallet(index, _, _):
            return index
        case let .faq(index, _):
            return index
        case let .ask(index, _):
            return index
        case let .update(index, _, _):
            return index
        case let .whiteSpace(index, _):
            return index
        }
    }
    
    static func <(lhs:AccountInfoEntry, rhs:AccountInfoEntry) -> Bool {
        return lhs.index < rhs.index
    }
    
    func item(_ arguments: AccountInfoArguments<Context>, initialSize: NSSize) -> TableRowItem {
        switch self {
        case let .info(_, viewType, peer, storyStats):
            return AccountInfoItem(initialSize, stableId: stableId, viewType: viewType, inset: NSEdgeInsets(left: 12, right: 12), context: arguments.context, peer: peer.peer as! TelegramUser, storyStats: storyStats, action: {
                let first: Atomic<Bool> = Atomic(value: true)
                EditAccountInfoController(context: arguments.context, f: { controller in
                    arguments.presentController(controller, first.swap(false))
                })
            }, setStatus: arguments.setStatus, openStory: arguments.openStory)
        case let .setStatus(_, viewType, peer):
            let icon: CGImage = peer.peer.emojiStatus != nil ? theme.icons.account_change_status : theme.icons.account_set_status
            let text = peer.peer.emojiStatus != nil ? strings().accountSettingsChangeStatus : strings().accountSettingsUpdateStatus
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: text, nameStyle: ControlStyle(font: .normal(.title), foregroundColor: theme.colors.accentIcon), type: .none, viewType: viewType, action: arguments.runStatusPopover, thumb: GeneralThumbAdditional(thumb: icon, textInset: 35, thumbInset: 0), inset:NSEdgeInsets(left: 12, right: 12), customTheme: .initialize(theme, background: .clear))
        case let .setProfileColor(_, viewType, peer):
            let icon: CGImage = TelegramThemeHooks.shared.image(.iconChannelFeatureCover).precomposed(theme.colors.accent, flipVertical: true)
            let text = strings().accountSettingsSetProfileColor
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: text, nameStyle: ControlStyle(font: .normal(.title), foregroundColor: theme.colors.accentIcon), type: .none, viewType: viewType, action: {
                arguments.setProfileColor(peer.peer)
            }, thumb: GeneralThumbAdditional(thumb: icon, textInset: 35, thumbInset: 0), inset:NSEdgeInsets(left: 12, right: 12), customTheme: .initialize(theme, background: .clear))
        case let .set2FaAlert(_, viewType):
            return TitleAndInfoAlertItem(initialSize, stableId: stableId, title: strings().accountSettingsProtectAccountTitle, info: strings().accountSettingsProtectAccountInfo, viewType: viewType, inset: NSEdgeInsets(left: 12, right: 12))
        case let .set2Fa(_, privacy, viewType):
            let icon: CGImage = theme.icons.account_settings_set_password
            let text = strings().accountSettingsProtectAccountSet
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: text, nameStyle: ControlStyle(font: .normal(.title), foregroundColor: theme.colors.accentIcon), type: .none, viewType: viewType, action: {
                arguments.set2Fa(privacy)
            }, thumb: GeneralThumbAdditional(thumb: icon, textInset: 35, thumbInset: 0), inset:NSEdgeInsets(left: 12, right: 12), customTheme: .initialize(theme, background: .clear))
        case let .accountRecord(_, viewType, info):
            return ShortPeerRowItem(initialSize, peer: info.peer, account: info.account, context: nil, height: 42, photoSize: NSMakeSize(28, 28), titleStyle: ControlStyle(font: .normal(.title), foregroundColor: theme.colors.text, highlightColor: theme.colors.underSelectedColor), inset: NSEdgeInsets(left: 12, right: 12), viewType: viewType, action: {
                arguments.context.sharedContext.switchToAccount(id: info.account.id, action: nil)
            }, contextMenuItems: {
                
                var items:[ContextMenuItem] = []
                
                items.append(ContextMenuItem(strings().accountOpenInWindow, handler: {
                    SettingsHooks.shared.openAccount(arguments.context, info.account.id)
                }, itemImage: MenuAnimation.menu_open_profile.value))
                
                items.append(ContextSeparatorItem())
                
                items.append(ContextMenuItem(strings().accountSettingsDeleteAccount, handler: {
                    verifyAlert_button(for: arguments.context.window, information: strings().accountConfirmLogoutText, successHandler: { _ in
                        _ = logoutFromAccount(id: info.account.id, accountManager: arguments.context.sharedContext.accountManager, alreadyLoggedOutRemotely: false).start()
                    })
                }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
                
                return .single(items)
            }, alwaysHighlight: true, badgeNode: SettingsHooks.shared.makeAccountBadgeNode(info.account, arguments.context), compactText: true, highlightVerified: true)
        case let .addAccount(_, accounts, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().accountSettingsAddAccount, nameStyle: ControlStyle(font: .normal(.title), foregroundColor: theme.colors.accentIcon), type: .none, viewType: viewType, action: {
                arguments.addAccount(accounts)
            }, thumb: GeneralThumbAdditional(thumb: theme.icons.account_add_account, textInset: 35, thumbInset: 0), inset:NSEdgeInsets(left: 12, right: 12), customTheme: .initialize(theme, background: .clear))
        case let .general(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().accountSettingsGeneral, icon: theme.icons.settingsGeneral, activeIcon: theme.icons.settingsGeneralActive, type: .next, viewType: viewType, action: {
                arguments.presentController(GeneralSettingsViewController(arguments.context), true)
            }, inset:NSEdgeInsets(left: 12, right: 12), customTheme: .initialize(theme, background: .clear))
        case let .stories(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().accountSettingsMyProfile, icon: theme.icons.settingsStories, activeIcon: theme.icons.settingsStoriesActive, type: .next, viewType: viewType, action: {
                SettingsHooks.shared.pushPeerInfo(arguments.context.bindings.rootNavigation(), arguments.context, arguments.context.peerId, false)
//                arguments.presentController(StoryMediaController(context: arguments.context, peerId: arguments.context.peerId, listContext: arguments.storyList, standalone: true), true)
            }, inset:NSEdgeInsets(left: 12, right: 12), customTheme: .initialize(theme, background: .clear))
        case let .attach(_, bot, viewType):
            var icon: CGImage?
            
            if let file = bot.icons[.macOSSettingsStatic] {
                let iconPath = arguments.context.account.postbox.mediaBox.resourcePath(file.resource)
                let linked = link(path: iconPath, ext: "png")!
                
                if let image = NSImage(contentsOf: .init(fileURLWithPath: linked)) {
                    icon = generateSettingsIcon(image.precomposed(flipVertical: true, scale: System.backingScale))
                }
            }
            
            if icon == nil {
                icon = TelegramThemeHooks.shared.image(.iconSettingsBotCap).precomposed(flipVertical: true, scale: System.backingScale)
            }
            let type: GeneralInteractedType
            if bot.flags.contains(.notActivated) || bot.flags.contains(.showInSettingsDisclaimer) {
                type = .imageContext(generateTextIcon_NewBadge(bgColor: theme.colors.accent, textColor: theme.colors.underSelectedColor), "")
            } else {
                type = .next
            }
            
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: bot.shortName, icon: icon!, activeIcon: icon!, type: type, viewType: viewType, action: {
                arguments.openWebBot(bot)
            }, inset:NSEdgeInsets(left: 12, right: 12), customTheme: .initialize(theme, background: .clear))
        case let .proxy(_, viewType, status):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().accountSettingsProxy, icon: theme.icons.settingsProxy, activeIcon: theme.icons.settingsProxyActive, type: .nextContext(status ?? ""), viewType: viewType, action: {
                let controller = SettingsNavigationHooks.shared.makeProxyListController(arguments.context, { servers in
                    var message: String = ""
                    for server in servers {
                        message += server.link + "\n\n"
                    }
                    message = message.trimmed
                    
                    SettingsHooks.shared.shareLink(arguments.context, message)
                }, { controller in
                     arguments.presentController(controller, false)
                })
                arguments.presentController(controller, true)

            }, inset:NSEdgeInsets(left: 12, right: 12), customTheme: .initialize(theme, background: .clear))
        case let .stickers(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().accountSettingsStickersAndEmoji, icon: theme.icons.settingsStickers, activeIcon: theme.icons.settingsStickersActive, type: .next, viewType: viewType, action: {
                arguments.presentController(SettingsNavigationHooks.shared.makeInstalledStickerPacksController(arguments.context, nil), true)
            }, inset:NSEdgeInsets(left: 12, right: 12), customTheme: .initialize(theme, background: .clear))
        case let .notifications(_, viewType, status):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().accountSettingsNotifications, icon: theme.icons.settingsNotifications, activeIcon: theme.icons.settingsNotificationsActive, type: status == .denied ? .image(TelegramThemeHooks.shared.image(.iconMessageSentFailed).precomposed()) : .next, viewType: viewType, action: {
                arguments.presentController(NotificationPreferencesController(arguments.context), true)
            }, inset:NSEdgeInsets(left: 12, right: 12), customTheme: .initialize(theme, background: .clear))
        case let .language(_, viewType, current):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().accountSettingsLanguage, icon: theme.icons.settingsLanguage, activeIcon: theme.icons.settingsLanguageActive, type: .nextContext(current), viewType: viewType, action: {
                arguments.presentController(LanguageController(arguments.context), true)
            }, inset:NSEdgeInsets(left: 12, right: 12), customTheme: .initialize(theme, background: .clear))
        case let .appearance(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().accountSettingsTheme, icon: theme.icons.settingsAppearance, activeIcon: theme.icons.settingsAppearanceActive, type: .next, viewType: viewType, action: {
                arguments.presentController(AppAppearanceViewController(context: arguments.context), true)
            }, inset:NSEdgeInsets(left: 12, right: 12), customTheme: .initialize(theme, background: .clear))
        case let .privacy(_, viewType, privacySettings, twoStep, _):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().accountSettingsPrivacyAndSecurity, icon: theme.icons.settingsSecurity, activeIcon: theme.icons.settingsSecurityActive, type: .next, viewType: viewType, action: {
                arguments.presentController(PrivacyAndSecurityViewController(arguments.context, initialSettings: privacySettings, twoStepVerificationConfiguration: twoStep), true)
            }, inset:NSEdgeInsets(left: 12, right: 12), customTheme: .initialize(theme, background: .clear))
        case let .dataAndStorage(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().accountSettingsDataAndStorage, icon: theme.icons.settingsStorage, activeIcon: theme.icons.settingsStorageActive, type: .next, viewType: viewType, action: {
                arguments.presentController(SettingsNavigationHooks.shared.makeDataAndStorageController(arguments.context, nil), true)
            }, inset:NSEdgeInsets(left: 12, right: 12), customTheme: .initialize(theme, background: .clear))
        case let .activeSessions(_, viewType, count):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().privacySettingsActiveSessions, icon: theme.icons.settingsSessions, activeIcon: theme.icons.settingsSessionsActive, type: count > 0 ? .nextContext("\(count)") : .none, viewType: viewType, action: {
                arguments.presentController(SettingsNavigationHooks.shared.makeRecentSessionsController(arguments.context), true)
            }, inset:NSEdgeInsets(left: 12, right: 12), customTheme: .initialize(theme, background: .clear))
        case .about:
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: APP_VERSION_STRING, nameStyle: ControlStyle(font: .normal(.text), foregroundColor: theme.colors.grayText), type: .none, viewType: .modern(position: .single, insets: .init(left: 14)), action: {
                copyToClipboard(APP_VERSION_STRING)
                showModalText(for: arguments.context.window, text: strings().contextAlertCopied)
            }, inset: NSEdgeInsets(left: 12, right: 12), customTheme: .init(backgroundColor: .clear, highlightColor: .clear))
        case let .passport(_, viewType, peer):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().accountSettingsPassport, icon: theme.icons.settingsPassport, activeIcon: theme.icons.settingsPassportActive, type: .next, viewType: viewType, action: {
                arguments.presentController(SettingsNavigationHooks.shared.makePassportController(arguments.context, peer.peer), true)
            }, inset:NSEdgeInsets(left: 12, right: 12), customTheme: .initialize(theme, background: .clear))
        case let .premium(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().accountSettingsPremium, icon: theme.icons.settingsPremium, activeIcon: theme.icons.settingsPremium, type: .next, viewType: viewType, action: {
                arguments.openPremium(false)
            }, inset:NSEdgeInsets(left: 12, right: 12), customTheme: .initialize(theme, background: .clear))
        case let .business(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().accountSettingsTelegramBusiness, icon: theme.icons.settingsBusiness, activeIcon: theme.icons.settingsBusinessActive, type: .next, viewType: viewType, action: {
                arguments.openPremium(true)
            }, inset:NSEdgeInsets(left: 12, right: 12), customTheme: .initialize(theme, background: .clear))
        case let .giftPremium(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().accountSettingsSendGift, icon: theme.icons.settingsGiftPremium, activeIcon: theme.icons.settingsGiftPremium, type: .next, viewType: viewType, action: arguments.giftPremium, inset:NSEdgeInsets(left: 12, right: 12), customTheme: .initialize(theme, background: .clear))
        case let .stars(_, stars, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().accountSettingsStars, icon: theme.icons.settingsStars, activeIcon: theme.icons.settingsStars, type: .nextContext(stars.value > 0 ? "\(stars.stringValue)" : ""), viewType: viewType, action: arguments.stars, inset:NSEdgeInsets(left: 12, right: 12), customTheme: .initialize(theme, background: .clear))
        case let .ton(_, ton, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().accountViewControllerGramEarnings, icon: theme.icons.settingsWallet, activeIcon: theme.icons.settingsWalletActive, type: .nextContext(ton.value > 0 ? "\(ton.string(.ton))" : ""), viewType: viewType, action: arguments.ton, inset:NSEdgeInsets(left: 12, right: 12), customTheme: .initialize(theme, background: .clear))
        case let .wallet(_, balance, viewType):
            let icon = settingsMoneyIcon()
            var balanceText: String
            if let balance, balance > 10_000_000 {
                balanceText = formatTonAmountText(balance)
                if let decimalRange = balanceText.range(of: walletDecimalSeparator) {
                    let fractionalDigitsCount = balanceText[decimalRange.upperBound...].count
                    balanceText += String(repeating: "0", count: max(0, 2 - fractionalDigitsCount))
                } else {
                    balanceText += walletDecimalSeparator + "00"
                }
            } else {
                balanceText = ""
            }
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().accountViewControllerMoney, icon: icon, activeIcon: icon, type: .nextContext(balanceText), viewType: viewType, action: arguments.openWallet, inset:NSEdgeInsets(left: 12, right: 12), customTheme: .initialize(theme, background: .clear), afterNameImage: SettingsNavigationHooks.shared.newBadgeFlippedIcon(theme.colors.accent, theme.colors.underSelectedColor))
        case let .faq(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().accountSettingsFAQ, icon: theme.icons.settingsFaq, activeIcon: theme.icons.settingsFaqActive, type: .next, viewType: viewType, action: arguments.openFaq, inset:NSEdgeInsets(left: 12, right: 12), customTheme: .initialize(theme, background: .clear))
        case let .ask(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().accountSettingsAskQuestion, icon: theme.icons.settingsAskQuestion, activeIcon: theme.icons.settingsAskQuestionActive, type: .next, viewType: viewType, action: {
                verifyAlert_button(for: arguments.context.window, information: strings().accountConfirmAskQuestion, option: strings().accountConfirmGoToFaq, successHandler: {  result in
                    switch result {
                    case .basic:
                        _ = showModalProgress(signal: arguments.context.engine.peers.supportPeerId(), for: arguments.context.window).start(next: {  peerId in
                            if let peerId = peerId {
                                arguments.presentController(SettingsHooks.shared.makeChatController(arguments.context, .peer(peerId)), true)
                            }
                        })
                    case .thrid:
                        arguments.openFaq()
                    }
                })
                
            }, inset:NSEdgeInsets(left: 12, right: 12), customTheme: .initialize(theme, background: .clear))
        case let .filters(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().accountSettingsFilters, icon: theme.icons.settingsFilters, activeIcon: theme.icons.settingsFiltersActive, type: .next, viewType: viewType, action: {
                arguments.presentController(SettingsHooks.shared.makeChatListFiltersListController(arguments.context), true)
            }, inset:NSEdgeInsets(left: 12, right: 12), customTheme: .initialize(theme, background: .clear))
        case let .update(_, viewType, state):
            
            let text: String = SettingsHooks.shared.appUpdateStateText(state.any)
           
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().accountViewControllerUpdate, icon: theme.icons.settingsUpdate, activeIcon: theme.icons.settingsUpdateActive, type: .nextContext(text), viewType: viewType, action: {
                arguments.openUpdateApp()
            }, inset:NSEdgeInsets(left: 12, right: 12), customTheme: .initialize(theme, background: .clear))
        case let .whiteSpace(_, height):
            return GeneralRowItem(initialSize, height: height, stableId: stableId, backgroundColor: .clear)
        }
    }
    
}


private func settingsMoneyIcon() -> CGImage? {
    guard let image = NSImage(named: "Icon_SettingsMoney")?.copy() as? NSImage else {
        return nil
    }
    image.size = NSMakeSize(24, 24)
    return image.precomposed(flipVertical: true)
}

private func accountInfoEntries<Context: AccountContextProtocol>(peerView:PeerView, context: Context, accounts: [AccountWithInfo], language: TelegramLocalization, privacySettings: AccountPrivacySettings?, webSessions: WebSessionsContextState, proxySettings: (ProxySettings, ConnectionStatus), passportVisible: Bool, appUpdateState: Any?, hasFilters: Bool, sessionsCount: Int, unAuthStatus: NotificationAuthorizationStatus, has2fa: Bool, twoStepConfiguration: TwoStepVeriticationAccessConfiguration?, storyStats: EngineStorySubscriptions?, attachMenuBots: [AttachMenuBot], stars: StarsContext.State?, ton: StarsContext.State?, walletBalance: Int64?) -> [AccountInfoEntry<Context>] {
    var entries:[AccountInfoEntry<Context>] = []
    
    var index:Int = 0
        
    if let peer = peerViewMainPeer(peerView) as? TelegramUser {
//        entries.append(.whiteSpace(index: index, height: 20))
//        index += 1
        entries.append(.info(index: index, viewType: .singleItem, PeerEquatable(peer), storyStats?.accountItem))
        index += 1
        
//        entries.append(.whiteSpace(index: index, height: 20))
//        index += 1

       
    }
    
    if let peer = peerViewMainPeer(peerView) {
        if context.isPremium {
            entries.append(.setStatus(index: index, viewType: .singleItem, PeerEquatable(peer)))
            index += 1
        }
        entries.append(.setProfileColor(index: index, viewType: .singleItem, PeerEquatable(peer)))
        index += 1
    }
    
    
    var has2fa = has2fa
    if let twoStepConfiguration = twoStepConfiguration {
        switch twoStepConfiguration {
        case .set:
            has2fa = true
        default:
            has2fa = false
        }
    } else {
        has2fa = true
    }
    if !SetupPasswordConfiguration.with(appConfiguration: context.appConfiguration).setup2Fa {
        has2fa = true
    }
    
    if !has2fa {
        entries.append(.whiteSpace(index: index, height: 10))
        index += 1
        entries.append(.set2FaAlert(index: index, viewType: .firstItem))
        index += 1
        entries.append(.set2Fa(index: index, settings: twoStepConfiguration, viewType: .lastItem))
        index += 1
        entries.append(.whiteSpace(index: index, height: 10))
        index += 1
    }
    
   
//    entries.append(.whiteSpace(index: index, height: 20))
//    index += 1
//
//
    
    if !context.isSupport {
        for account in accounts {
            if account.account.id != context.account.id {
                entries.append(.accountRecord(index: index, viewType: .singleItem, info: account))
                index += 1
            }
        }
    }
    
    let accountsLimit: Int = normalAccountsLimit
    let effectiveLimit: Int
    if context.premiumIsBlocked {
        effectiveLimit = accountsLimit
    } else {
        effectiveLimit = accountsLimit + 1
    }
//    let hasPremium = accounts.filter({ $0.peer.isPremium })
//    let normalCount = accounts.filter({ !$0.peer.isPremium }).count

    if accounts.count < effectiveLimit, !context.isSupport {
        entries.append(.addAccount(index: index, accounts, viewType: .singleItem))
        index += 1
    }
    entries.append(.whiteSpace(index: index, height: 10))
    index += 1
    
    
    entries.append(.stories(index: index, viewType: .singleItem))
    index += 1

    if #available(macOS 10.15, *) {
        if SettingsHooks.shared.walletHooks.hasWallet(context), context.appConfiguration.getBoolValue("wallet_available", orElse: false) {
            entries.append(.wallet(index: index, balance: walletBalance, viewType: .singleItem))
            index += 1
        }
    }

    entries.append(.whiteSpace(index: index, height: 10))
    index += 1

    for bot in attachMenuBots {
        if #available(macOS 10.15, *), SettingsHooks.shared.walletHooks.hasWallet(context), context.account.testingEnvironment, bot.peer.addressName?.lowercased() == "wallet" {
            continue
        }
        if bot.flags.contains(.showInSettings) {
            entries.append(.attach(index: index, bot, viewType: .singleItem))
            index += 1
        }
    }
    
    
    if !proxySettings.0.servers.isEmpty {
        entries.append(.whiteSpace(index: index, height: 10))
        index += 1
        
        let status: String
        switch proxySettings.1 {
        case .online:
            status = proxySettings.0.enabled ? strings().accountSettingsProxyConnected : strings().accountSettingsProxyDisabled
        default:
            status = proxySettings.0.enabled ? strings().accountSettingsProxyConnecting : strings().accountSettingsProxyDisabled
        }
        entries.append(.proxy(index: index, viewType: .singleItem, status: status))
        index += 1
        
    }
    
    entries.append(.whiteSpace(index: index, height: 10))
    index += 1
    
    entries.append(.general(index: index, viewType: .singleItem))
    index += 1
    entries.append(.notifications(index: index, viewType: .singleItem, status: unAuthStatus))
    index += 1
    entries.append(.privacy(index: index, viewType: .singleItem, privacySettings, twoStepConfiguration, webSessions))
    index += 1
    entries.append(.dataAndStorage(index: index, viewType: .singleItem))
    index += 1
    entries.append(.activeSessions(index: index, viewType: .singleItem, activeSessions: sessionsCount))
    index += 1
    entries.append(.appearance(index: index, viewType: .singleItem))
    index += 1
    entries.append(.language(index: index, viewType: .singleItem, current: language.localizedName))
    index += 1
    entries.append(.stickers(index: index, viewType: .singleItem))
    index += 1
    
    if hasFilters {
        entries.append(.filters(index: index, viewType: .singleItem))
        index += 1
    }
    
    if let state = appUpdateState, !context.isSupport {
        entries.append(.update(index: index, viewType: .singleItem, state: AnyUpdateStateEquatable(any: state)))
        index += 1
    }
   

    entries.append(.whiteSpace(index: index, height: 20))
    index += 1
    
    if let peer = peerViewMainPeer(peerView) as? TelegramUser, passportVisible {
        entries.append(.passport(index: index, viewType: .singleItem, peer: PeerEquatable(peer)))
        index += 1
        
        entries.append(.whiteSpace(index: index, height: 20))
        index += 1
    }
    
    if !context.premiumIsBlocked {
        entries.append(.premium(index: index, viewType: .singleItem))
        index += 1
        
        
        let stars_purchase_blocked = context.appConfiguration.getBoolValue("stars_purchase_blocked", orElse: true)
        
        if !stars_purchase_blocked, let stars  {
            entries.append(.stars(index: index, count: stars.balance, viewType: .singleItem))
            index += 1
        }
        
        if let ton, ton.balance.value > 0 || !ton.transactions.isEmpty  {
            entries.append(.ton(index: index, count: ton.balance, viewType: .singleItem))
            index += 1
        }

        entries.append(.business(index: index, viewType: .singleItem))
        index += 1
        
        entries.append(.giftPremium(index: index, viewType: .singleItem))
        index += 1
        
        entries.append(.whiteSpace(index: index, height: 20))
        index += 1
    }
   

    entries.append(.faq(index: index, viewType: .singleItem))
    index += 1
    entries.append(.ask(index: index, viewType: .singleItem))
    index += 1
    
    entries.append(.whiteSpace(index: index, height: 20))
    index += 1
    
    entries.append(.about(index: index, viewType: .singleItem))
    index += 1
    
    entries.append(.whiteSpace(index: index, height: 20))
    index += 1
    
    return entries
}

private func prepareEntries<Context: AccountContextProtocol>(left: [AppearanceWrapperEntry<AccountInfoEntry<Context>>], right: [AppearanceWrapperEntry<AccountInfoEntry<Context>>], arguments: AccountInfoArguments<Context>, initialSize: NSSize) -> TableUpdateTransition {
    let (removed, inserted, updated)  = proccessEntriesWithoutReverse(left, right: right) { entry -> TableRowItem in
        return entry.entry.item(arguments, initialSize: initialSize)
    }
    return TableUpdateTransition(deleted: removed, inserted: inserted, updated: updated, animated: true)
}


public final class AccountControllerView : Control {
    fileprivate let searchView: AccountSearchBarView
    fileprivate let tableView: TableView
    fileprivate let edit = TextButton()
    fileprivate let qrCode = ImageButton()
    private let statusContainer: View
    fileprivate var hasSidebar: Bool = false {
        didSet {
            if oldValue != hasSidebar {
                needsLayout = true
            }
        }
    }
    private let textView = TextView()
    
    public required init(frame frameRect: NSRect) {
        statusContainer = .init(frame: NSMakeRect(0, 0, frameRect.width, 40))
        searchView = AccountSearchBarView(frame: NSMakeRect(0, 40, frameRect.width, 50))
        tableView = TableView(frame: NSMakeRect(0, 50, frameRect.width, frameRect.height - 50))
        super.init(frame: frameRect)
        addSubview(statusContainer)
        addSubview(searchView)
        addSubview(qrCode)
        addSubview(tableView)
        
        textView.userInteractionEnabled = false
        textView.isSelectable = false

        statusContainer.addSubview(edit)
        statusContainer.addSubview(textView)
        edit.scaleOnClick = true
        qrCode.scaleOnClick = true
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        borderColor = theme.colors.border
        edit.set(font: .medium(.title), for: .Normal)
        edit.set(text: strings().navigationEdit, for: .Normal)
        edit.set(color: theme.colors.accent, for: .Normal)
        edit.scaleOnClick = true
        qrCode.set(image: (theme as! TelegramPresentationTheme).icons.wallet_qr, for: .Normal)
        qrCode.sizeToFit(.zero, NSMakeSize(30, 30), thatFit: true)
        self.backgroundColor = .clear

        let layout = TextViewLayout(.initialize(string: strings().accountViewControllerTitle, color: theme.colors.text, font: .medium(.title)), maximumNumberOfLines: 1)
        layout.measure(width: .greatestFiniteMagnitude)
        textView.update(layout)
        
        needsLayout = true
    }
    
    public override func layout() {
        super.layout()
        statusContainer.frame = NSMakeRect(0, 0, frame.width, 40)
        edit.sizeToFit(NSMakeSize(10, 14))
        edit.setFrameOrigin(NSMakePoint(statusContainer.frame.width - edit.frame.width - 10, statusContainer.frame.height - edit.frame.height))
        textView.centerX(y: 14)

        if hasSidebar {
            searchView.frame = NSMakeRect(0, statusContainer.frame.maxY, frame.width, 50)
            qrCode.setFrameOrigin(NSMakePoint(10, floor(edit.frame.midY - qrCode.frame.height / 2)))
        } else {
            searchView.frame = NSMakeRect(qrCode.frame.width + 10, statusContainer.frame.maxY, frame.width - qrCode.frame.width - 10, 50)
            qrCode.setFrameOrigin(NSMakePoint(10, floor(searchView.frame.midY - qrCode.frame.height / 2)))
        }
        tableView.frame = NSMakeRect(0, searchView.frame.maxY, frame.width, frame.height - searchView.frame.maxY)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

open class AccountViewController<Context: AccountContextProtocol> : TelegramGenericViewController<AccountControllerView, Context>, TableViewDelegate {
    
    
    private let disposable = MetaDisposable()
    
    let actionsDisposable = DisposableSet()
    
    private var searchController: InputDataController?
    private let searchState: ValuePromise<SearchState> = ValuePromise(ignoreRepeated: true)
    var navigation:NavigationViewController? {
        return context.bindings.rootNavigation()
    }
    
    open override func viewDidResized(_ size: NSSize) {
        super.viewDidResized(size)
        self.searchController?.view.frame = bounds
    }

    open override func updateContainerContentInsets(_ insets: NSEdgeInsets, transition: ContainedViewLayoutTransition) {
        super.updateContainerContentInsets(insets, transition: transition)
        if isLoaded() {
            tableView.contentInsets.bottom = insets.bottom
            tableView.scrollerInsets.bottom = 0
            searchController?.updateContainerContentInsets(insets, transition: transition)
        }
    }
    
    
    private func showSearchController(animated: Bool) {
        if searchController == nil {
            let rect = tableView.frame
            let searchController = SearchSettingsController(context: context, searchQuery: self.searchState.get(), archivedStickerPacks: .single(nil), privacySettings: self.settings.get() |> map { $0.0 })
            searchController.bar = .init(height: 0)
            searchController._frameRect = rect
            searchController.updateContainerContentInsets(containerContentInsets, transition: .immediate)
            self.searchController = searchController
            searchController.navigationController = self.navigationController
            searchController.viewWillAppear(true)
            if animated {
                searchController.view.layer?.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
            } else {
                searchController.viewDidAppear(animated)
            }

            self.addSubview(searchController.view)
            searchController.viewDidAppear(animated)

            tableView.change(opacity: 0, animated: animated)
        }
    }



    private func hideSearchController(animated: Bool) {
        if let searchController = self.searchController {
            searchController.viewWillDisappear(animated)
            searchController.view.layer?.opacity = animated ? 1.0 : 0.0
            searchController.viewDidDisappear(true)
            self.searchController = nil
            let view = searchController.view

            searchController.view._change(opacity: 0, animated: animated, duration: 0.25, timingFunction: CAMediaTimingFunctionName.spring, completion: { [weak view] completed in
                view?.removeFromSuperview()
            })

            tableView.change(opacity: 1, animated: animated)
        }
    }
    
    open override func escapeKeyAction() -> KeyHandlerResult {
        guard context.layout != .minimisize else {
            return .invoked
        }
        if searchView.state == .None {
            return searchView.changeResponder() ? .invoked : .rejected
        } else if searchView.state == .Focus && searchView.query.length > 0 {
            searchView.change(state: .None,  true)
            return .invoked
        }
        return .rejected
    }
    
 
    
    public func selectionWillChange(row: Int, item: TableRowItem, byClick: Bool) -> Bool {
        return item is GeneralInteractedRowItem || item is AccountInfoItem || item is ShortPeerRowItem
    }
    public func selectionDidChange(row: Int, item: TableRowItem, byClick: Bool, isNew: Bool) {
        
    }
    public func isSelectable(row: Int, item: TableRowItem) -> Bool {
        return true
    }
    
    private let settings: Promise<(AccountPrivacySettings?, WebSessionsContextState, (ProxySettings, ConnectionStatus), (Bool, Bool))> = Promise()
    
    public func updateMessagesPrivacy(noPaidMessages: SelectivePrivacySettings, globalSettings: GlobalPrivacySettings) {
        let privacy = self.settings.get() |> deliverOnMainQueue |> take(1)
        _ = privacy.startStandalone(next: { [weak self] privacy, web, proxy, value in
            var privacy = privacy
            privacy?.noPaidMessages = noPaidMessages
            privacy?.globalSettings = globalSettings
            DispatchQueue.main.async {
                self?.settings.set(.single((privacy, web, proxy, value)))
            }
        })
    }
    
    public func updatePrivacy(_ updated: SelectivePrivacySettings, kind: SelectivePrivacySettingsKind) {
        let privacy = self.settings.get() |> deliverOnMainQueue |> take(1)
        
        _ = privacy.startStandalone(next: { [weak self] privacy, web, proxy, value in
            var privacy = privacy
            switch kind {
            case .presence:
                privacy?.presence = updated
            case .groupInvitations:
                privacy?.groupInvitations = updated
            case .voiceCalls:
                privacy?.voiceCalls = updated
            case .profilePhoto:
                privacy?.profilePhoto = updated
            case .forwards:
                privacy?.forwards = updated
            case .phoneNumber:
                privacy?.phoneNumber = updated
            case .voiceMessages:
                privacy?.voiceMessages = updated
            case .bio:
                privacy?.bio = updated
            case .birthday:
                privacy?.birthday = updated
            case .gifts:
                privacy?.giftsAutoSave = updated
            case .savedMusic:
                privacy?.savedMusic = updated
            }
            DispatchQueue.main.async {
                self?.settings.set(.single((privacy, web, proxy, value)))
            }
        })
    }
    
    public var privacySettings: Signal<AccountPrivacySettings?, NoError> {
        return settings.get() |> map { $0.0 }
    }
    
    private let syncLocalizations = MetaDisposable()
    private var hasAppeared = false
    private let twoStepConfiguration = Promise<TwoStepVeriticationAccessConfiguration?>(nil)
    fileprivate let passportPromise: Promise<(Bool, Bool)> = Promise((false, false))
    fileprivate let hasFilters: Promise<Bool> = Promise(false)

    private weak var arguments: AccountInfoArguments<Context>?
    open override func viewDidLoad() {
        super.viewDidLoad()
        updateContainerContentInsets(containerContentInsets, transition: .immediate)
        tableView.delegate = self
        let context = self.context
        //theme.colors.listBackground
        tableView.getBackgroundColor = {
            return .clear
        }
        
        searchView.searchInteractions = SearchInteractions({ [weak self] state, animated in
            guard let `self` = self else {return}
            self.searchState.set(state)
            switch state.state {
            case .Focus:
                self.showSearchController(animated: animated)
            case .None:
                self.hideSearchController(animated: animated)
            }
            
        }, { [weak self] state in
            self?.searchState.set(state)
        })
        
        genericView.qrCode.set(handler: { [weak self] control in
            guard let self else { return }
            SettingsNavigationHooks.shared.openQrStudioObserved(context, { [weak control] in control })
        }, for: .Click)

        actionsDisposable.add((chatListFilterPreferences(engine: context.engine) |> map { $0.sidebar && !$0.isEmpty } |> distinctUntilChanged |> deliverOnMainQueue).start(next: { [weak self] hasSidebar in
            self?.genericView.hasSidebar = hasSidebar
        }))

        genericView.edit.set(handler: { [weak self] _ in
            guard let `self` = self else {return}
            let first: Atomic<Bool> = Atomic(value: true)
            EditAccountInfoController(context: context, f: { [weak self] controller in
                self?.arguments?.presentController(controller, first.swap(false))
            })
        }, for: .Click)
        
        let privacySettings = context.engine.privacy.requestAccountPrivacySettings() |> map(Optional.init)
        
        settings.set(combineLatest(Signal<AccountPrivacySettings?, NoError>.single(nil) |> then(privacySettings), context.webSessions.state, proxySettings(accountManager: context.sharedContext.accountManager) |> mapToSignal { settings in
            return context.account.network.connectionStatus |> map {(settings, $0)}
        }, passportPromise.get()))
        
        
        
        
        syncLocalizations.set(context.engine.localization.synchronizedLocalizationListState().start())
        
        

        self.hasFilters.set(.single(true))
        
        let previous:Atomic<[AppearanceWrapperEntry<AccountInfoEntry<Context>>]> = Atomic(value: [])
        
        
        let setStatus:(Control, TelegramUser)->Void = { control, peer in
            let callback:(TelegramMediaFile, StarGift.UniqueGift?, Int32?, CGRect?)->Void = { file, starGift, timeout, fromRect in
                context.reactions.setStatus(file, peer: peer, timestamp: context.timestamp, timeout: timeout, fromRect: fromRect, starGift: starGift)
            }
            if control.popover == nil {
                showPopover(for: control, with: SettingsHooks.shared.makePremiumStatusController(context, callback, peer), edge: .maxY, inset: NSMakePoint(-80, -35), static: true, animationMode: .reveal)
            }
        }
        
        
        let arguments = AccountInfoArguments(context: context, storyList: PeerStoryListContext(account: context.account, peerId: context.peerId, isArchived: false, folderId: nil), presentController: { [weak self] controller, main in
            guard let navigation = self?.navigation as? MajorNavigationController else {return}
            guard let singleLayout = self?.context.layout else {return}
            navigation.push(controller, !main || singleLayout == .single, clearStack: main)
        }, openFaq: {
            SettingsHooks.shared.openFaq(context)
        }, ask: {
            
        }, openUpdateApp: { [weak self] in
            guard let navigation = self?.navigation as? MajorNavigationController else {return}
            SettingsHooks.shared.pushAppUpdate(navigation)
        }, openPremium: { [weak self] business in
            guard let navigation = self?.navigation as? MajorNavigationController else {return}
            if business, context.isPremium {
                if (navigation.controller as? SettingsSectionController)?.settingsSection != .premium {
                    navigation.push(SettingsNavigationHooks.shared.makePremiumBoardingController(context, .businessStandalone), false)
                }
            } else {
                SettingsNavigationHooks.shared.showPremiumBoarding(context, business ? .business : .settings, false, context.window, { [weak self] in (self?.tableView.item(stableId: AccountInfoEntryId.index(business ? 20 : 19))?.view as? GeneralContainableRowView)?.containerView })
            }
        }, giftPremium: { [weak self] in
            SettingsNavigationHooks.shared.showMultigift(context, { [weak self] in (self?.tableView.item(stableId: AccountInfoEntryId.index(21))?.view as? GeneralContainableRowView)?.containerView })
        }, addAccount: { accounts in
            let testingEnvironment = NSApp.currentEvent?.modifierFlags.contains(.command) == true
            let hasPremium = accounts.contains(where: { $0.peer.isPremium })
            if accounts.count == normalAccountsLimit {
                if hasPremium {
                    context.sharedContext.beginNewAuth(testingEnvironment: testingEnvironment)
                } else {
                    SettingsNavigationHooks.shared.showPremiumLimit(context, .accounts(accounts.count))
                }
            } else {
                context.sharedContext.beginNewAuth(testingEnvironment: testingEnvironment)
            }
        }, setStatus: { control, user in
            setStatus(control, user)
        }, runStatusPopover: { [weak self] in
            guard let item = self?.tableView.item(at: 0) as? AccountInfoItem else {
                return
            }
            if let control = item.statusControl {
                setStatus(control, item.peer)
            }
        }, set2Fa: { [weak self] configuration in
            self?.navigation?.push(twoStepVerificationUnlockController(context: context, mode: .access(configuration), presentController: { [weak self] controller, isRoot, animated in
                guard let `self` = self, let navigation = self.navigation else {return}
                if isRoot {
                    navigation.removeUntil(PrivacyAndSecurityViewController<Context>.self)
                }
                if !animated {
                    navigation.stackInsert(controller, at: navigation.stackCount)
                } else {
                    navigation.push(controller)
                }
            }))
        }, openStory: { [weak self] initialId in
            guard let self else { return }
            SettingsHooks.shared.showStoriesObserved(context, false, initialId, true)
        }, openWebBot: { [weak self] bot in
            guard let self else { return }
            SettingsNavigationHooks.shared.openWebBotObserved(context, bot)
        }, stars: { [weak self] in
            SettingsNavigationHooks.shared.showStarsList(context, .stars, { [weak self] in (self?.tableView.item(stableId: AccountInfoEntryId.index(22))?.view as? GeneralContainableRowView)?.containerView })
        }, ton: { [weak self] in
            SettingsNavigationHooks.shared.showStarsList(context, .ton, { [weak self] in (self?.tableView.item(stableId: AccountInfoEntryId.index(23))?.view as? GeneralContainableRowView)?.containerView })
        }, openWallet: { [weak self] in
            if #available(macOS 10.15, *) {
                guard context.appConfiguration.getBoolValue("wallet_available", orElse: false) else {
                    showModalText(for: context.window, text: strings().accountViewControllerWalletUnavailable)
                    return
                }
                // Re-resolve the current wallet row view at morph time: the settings table reloads
                // (balance updates etc.), replacing the row view, so look it up live by its stableId.
                // Morph from the rounded inset container (the visible pill), not the full-width row.
                SettingsHooks.shared.walletHooks.showWallet(context, context.window, { [weak self] in
                    (self?.tableView.item(stableId: AccountInfoEntryId.index(999))?.view as? GeneralContainableRowView)?.containerView
                })
            }
        }, setProfileColor: { [weak self] peer in
            self?.navigation?.push(SettingsHooks.shared.makeSelectColorParentController(context, peer))
        })
        
        self.arguments = arguments
        
        let atomicSize = self.atomicSize
        

        let appUpdateState: Signal<Any?, NoError> = SettingsHooks.shared.appUpdateState()
        
        
        let sessionsCount = context.activeSessionsContext.state |> map {
            $0.sessions.count
        }
        
        passportPromise.set(twoStepConfiguration.get() |> map { configuration in
            switch configuration {
            case let .set(_, _, hasSecureValues, _):
                return (hasSecureValues, true)
            case .notSet, nil:
                return (false, false)
            }
        })

        twoStepConfiguration.set(context.engine.auth.twoStepVerificationConfiguration() |> map { .init(configuration: $0, password: nil) })
        let twoStep = twoStepConfiguration.get()

        let storyStats: Signal<EngineStorySubscriptions, NoError> = .single(EngineStorySubscriptions.init(accountItem: nil, items: [], hasMoreToken: nil)) |> then(context.engine.messages.storySubscriptions(isHidden: false))
        
        let bots = context.engine.messages.attachMenuBotsUpdates() |> mapToSignal { bots -> Signal<[AttachMenuBot], NoError> in
            let iconStatuses: [Signal<Bool, NoError>] = bots.compactMap { $0.icons[.macOSSettingsStatic] }.map { file in
                return .single(false) |> then(context.account.postbox.mediaBox.resourceData(file.resource) |> filter { $0.complete } |> take(1) |> map { _ in true })
            }
            if iconStatuses.isEmpty {
                return .single(bots)
            }
            return combineLatest(iconStatuses) |> distinctUntilChanged |> map { _ in bots }
        } |> deliverOn(prepareQueue)
        
        let acceptBots:ValuePromise<[AttachMenuBot]> = ValuePromise([], ignoreRepeated: true)
        
        var loading:Set<PeerId> = Set()
        actionsDisposable.add(bots.start(next: { value in
            var ready: [AttachMenuBot] = []
            for value in value {
                if !loading.contains(value.peer.id) {
                    if let file = value.icons[.macOSSettingsStatic] {
                        if let peerReference = PeerReference(value.peer._asPeer()) {
                            _ = freeMediaFileInteractiveFetched(context: context, fileReference: FileMediaReference.attachBot(peer: peerReference, media: file)).start()
                            loading.insert(value.peer.id)
                        }
                    }
                }
                if let file = value.icons[.macOSSettingsStatic] {
                    let iconPath = arguments.context.account.postbox.mediaBox.resourcePath(file.resource)
                    let linked = link(path: iconPath, ext: "png")!
                    
                    if let _ = NSImage(contentsOf: .init(fileURLWithPath: linked)) {
                        ready.append(value)
                    }
                } else {
                    ready.append(value)
                }
            }
            acceptBots.set(ready)
        }))
        
        
        let walletBalance: Signal<Int64?, NoError>
        if #available(macOS 10.15, *) {
            walletBalance = SettingsHooks.shared.walletHooks.balance(context)
        } else {
            walletBalance = .single(nil)
        }

        let apply = combineLatest(queue: prepareQueue, context.account.viewTracker.peerView(context.account.peerId), context.sharedContext.activeAccountsWithInfo, appearanceSignal, settings.get(), appUpdateState, hasFilters.get(), sessionsCount, SettingsHooks.shared.authorizationStatus(context), twoStep, storyStats, acceptBots.get(), context.starsContext.state, context.tonContext.state, walletBalance) |> map { peerView, accounts, appearance, settings, appUpdateState, hasFilters, sessionsCount, unAuthStatus, twoStepConfiguration, storyStats, attachMenuBots, stars, ton, walletBalance -> TableUpdateTransition in
            let entries = accountInfoEntries(peerView: peerView, context: context, accounts: accounts.accounts, language: appearance.language, privacySettings: settings.0, webSessions: settings.1, proxySettings: settings.2, passportVisible: settings.3.0, appUpdateState: appUpdateState, hasFilters: hasFilters, sessionsCount: sessionsCount, unAuthStatus: unAuthStatus, has2fa: settings.3.1, twoStepConfiguration: twoStepConfiguration, storyStats: storyStats, attachMenuBots: attachMenuBots, stars: stars, ton: ton, walletBalance: walletBalance).map {AppearanceWrapperEntry(entry: $0, appearance: appearance)}
            var size = atomicSize.modify {$0}
            size.width = max(size.width, 280)
            return prepareEntries(left: previous.swap(entries), right: entries, arguments: arguments, initialSize: size)
        } |> deliverOnMainQueue
        
        disposable.set(apply.start(next: { [weak self] transition in
            self?.tableView.merge(with: transition)
            self?.readyOnce()
        }))
       
    }
    
    
    var tableView: TableView {
        return genericView.tableView
    }
    public var searchView: SearchView {
        return genericView.searchView.searchView
    }
    
    
    
    open override func navigationWillChangeController() {
        if let navigation = navigation as? MajorNavigationController {
            if (navigation.controller as? SettingsSectionController)?.settingsSection == .dataAndStorage {
                if let item = tableView.item(stableId: AnyHashable(AccountInfoEntryId.index(10))) {
                    _ = tableView.select(item: item)
                }
            } else if navigation.controller is PrivacyAndSecurityViewController<Context> {
                if let item = tableView.item(stableId: AnyHashable(AccountInfoEntryId.index(12))) {
                    _ = tableView.select(item: item)
                }
            } else if (navigation.controller as? SettingsSectionController)?.settingsSection == .stickers {
                if let item = tableView.item(stableId: AnyHashable(AccountInfoEntryId.index(14))) {
                    _ = tableView.select(item: item)
                }
                
            } else if navigation.controller is GeneralSettingsViewController<Context> {
                if let item = tableView.item(stableId: AnyHashable(AccountInfoEntryId.index(7))) {
                    _ = tableView.select(item: item)
                }
            } else if (navigation.controller as? SettingsSectionController)?.settingsSection == .sessions {
                if let item = tableView.item(stableId: AnyHashable(AccountInfoEntryId.index(11))) {
                    _ = tableView.select(item: item)
                }
            } else if let controller = navigation.controller as? SettingsPeerInfoController, controller.peerId == context.peerId {
                if let item = tableView.item(stableId: AccountInfoEntryId.index(Int(6))) {
                    _ = tableView.select(item: item)
                }
            } else if (navigation.controller as? SettingsSectionController)?.settingsSection == .passport {
                if let item = tableView.item(stableId: AccountInfoEntryId.index(Int(18))) {
                    _ = tableView.select(item: item)
                }
            } else if (navigation.controller as? SettingsSectionController)?.settingsSection == .premium {
                if let item = tableView.item(stableId: AnyHashable(AccountInfoEntryId.index(20))) {
                    _ = tableView.select(item: item)
                }
            } else if let controller = navigation.controller as? SettingsChatController {
                switch controller.mode {
                case .customChatContents, .customLink:
                    if let item = tableView.item(stableId: AnyHashable(AccountInfoEntryId.index(20))) {
                        _ = tableView.select(item: item)
                    }
                default:
                    break
                }
            } else if let controller = navigation.controller as? InputDataController {
                switch true {
                case controller.identifier == "proxy":
                    if let item = tableView.item(stableId: AnyHashable(AccountInfoEntryId.index(8))) {
                        _ = tableView.select(item: item)
                    }
                case controller.identifier == "language":
                    if let item = tableView.item(stableId: AnyHashable(AccountInfoEntryId.index(13))) {
                        _ = tableView.select(item: item)
                    }
                case controller.identifier == "account":
                    if let item = tableView.item(stableId: AnyHashable(AccountInfoEntryId.index(0))) {
                        _ = tableView.select(item: item)
                    }
                case controller.identifier == "passport":
                    if let item = tableView.item(stableId: AnyHashable(AccountInfoEntryId.index(18))) {
                        _ = tableView.select(item: item)
                    }
                case controller.identifier == "app_update":
                    if let item = tableView.item(stableId: AnyHashable(AccountInfoEntryId.index(16))) {
                        _ = tableView.select(item: item)
                    }
                case controller.identifier == "filters":
                    if let item = tableView.item(stableId: AnyHashable(AccountInfoEntryId.index(15))) {
                        _ = tableView.select(item: item)
                    }
                case controller.identifier == "notification-settings":
                    if let item = tableView.item(stableId: AnyHashable(AccountInfoEntryId.index(9))) {
                        _ = tableView.select(item: item)
                    }
                case controller.identifier == "app_appearance":
                    if let item = tableView.item(stableId: AnyHashable(AccountInfoEntryId.index(17))) {
                        _ = tableView.select(item: item)
                    }
                case controller.identifier.hasPrefix("business"):
                    if let item = tableView.item(stableId: AnyHashable(AccountInfoEntryId.index(20))) {
                        _ = tableView.select(item: item)
                    }
                default:
                    tableView.cancelSelection()
                }
               
            } else {
                tableView.cancelSelection()
            }
        }
    }
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        (navigation as? MajorNavigationController)?.add(listener: WeakReference(value: self))

        updateLocalizationAndTheme(theme: theme)

        if focusOnSearch {
            focusOnSearch = false
            self.searchView.change(state: .Focus, false)
        }

        context.window.set(handler: { [weak self] _ in
            if let strongSelf = self {
                return strongSelf.escapeKeyAction()
            }
            return .invokeNext
        }, with: self, for: .Escape, priority:.low)

        context.starsContext.load(force: true)
        context.tonContext.load(force: true)
    }
    
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        window?.removeAllHandlers(for: self)
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        SettingsNavigationHooks.shared.prefetchQrStudio(context)
        guard hasAppeared else {
            hasAppeared = true
            return
        }
        let context = self.context
                
        twoStepConfiguration.set(context.engine.auth.twoStepVerificationConfiguration() |> map { .init(configuration: $0, password: nil) })

        let privacySettings = context.engine.privacy.requestAccountPrivacySettings() |> map(Optional.init)

        settings.set(combineLatest(Signal<AccountPrivacySettings?, NoError>.single(nil) |> then(privacySettings), context.webSessions.state, proxySettings(accountManager: context.sharedContext.accountManager) |> mapToSignal { settings in
            return context.account.network.connectionStatus |> map {(settings, $0)}
        }, passportPromise.get()))
        

        syncLocalizations.set(context.engine.localization.synchronizedLocalizationListState().start())
        
    }
    
    open override func getLeftBarViewOnce() -> BarView {
        return BarView(10, controller: self)
    }
    
    public var focusOnSearch: Bool = false

    open override var wantsContainerGlass: Bool {
        return false
    }

    open override var containerCornerRadius: CGFloat {
        return 0
    }

    open override var defaultBarTitle: String {
        return localizedString("Telegram.AccountViewController")
    }

    public init(_ context: Context, focusOnSearch: Bool = false) {
        self.focusOnSearch = focusOnSearch
        super.init(context)
        bar = .init(height: 0)
        self.insets = NSEdgeInsets()
    }


    open override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        navigationController?.updateLocalizationAndTheme(theme: theme)
    }
    
    open override func firstResponder() -> NSResponder? {
        return nil
    }

    
    open override func scrollup(force: Bool = false) {
        
        if searchController != nil {
            self.searchView.cancel(true)
            return
        }
        
        if let currentEvent = NSApp.currentEvent, currentEvent.clickCount == 5, !context.isSupport {
            context.bindings.rootNavigation().push(DeveloperViewController(context: context))
        }
        
        tableView.scroll(to: .up(true))
    }
    
    deinit {
        syncLocalizations.dispose()
        disposable.dispose()
        actionsDisposable.dispose()
    }

}

