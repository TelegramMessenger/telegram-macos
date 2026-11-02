import Cocoa
import Postbox
import TGUIKit
import SwiftSignalKit
import TelegramCore
import InAppSettings
import Localization
import TelegramContext

enum SettingsRootSearchTag: Int32, CaseIterable {
    case chatFolders = 1
    case passport = 2
    case premium = 3
    case business = 4
    case sendGift = 5
    case stars = 6
}

extension SettingsRootSearchTag: SettingsSearchTag {
    static var icon: SettingsSearchableItemIcon {
        return .general
    }
    
    static var rootTitle: String {
        return ""
    }
    
    static var includesRoot: Bool {
        return false
    }
    
    static func itemId(_ index: Int32) -> SettingsSearchableItemId {
        return .settings(index)
    }
    
    static func open<Context: AccountContextProtocol>(_ tag: SettingsRootSearchTag?, context: Context, navigation: NavigationViewController?, environment: SettingsSearchEnvironment, present: @escaping (SettingsSearchableItemPresentation, ViewController?) -> Void) {
        guard let tag = tag else {
            return
        }
        switch tag {
        case .chatFolders:
            present(.push, SettingsHooks.shared.makeChatListFiltersListController(context))
        case .passport:
            _ = (context.account.postbox.transaction { transaction in
                return transaction.getPeer(context.peerId)
            } |> deliverOnMainQueue).start(next: { peer in
                if let peer = peer {
                    present(.push, SettingsNavigationHooks.shared.makePassportController(context, peer))
                }
            })
        case .premium:
            SettingsNavigationHooks.shared.showPremiumBoarding(context, .settings, false, context.window, nil)
        case .business:
            if context.isPremium {
                present(.push, SettingsNavigationHooks.shared.makePremiumBoardingController(context, .businessStandalone))
            } else {
                SettingsNavigationHooks.shared.showPremiumBoarding(context, .business, false, context.window, nil)
            }
        case .sendGift:
            SettingsNavigationHooks.shared.showMultigift(context, nil)
        case .stars:
            SettingsNavigationHooks.shared.showStarsList(context, .stars, nil)
        }
    }
    
    var searchTitle: String {
        switch self {
        case .chatFolders:
            return strings().accountSettingsFilters
        case .passport:
            return strings().accountSettingsPassport
        case .premium:
            return strings().accountSettingsPremium
        case .business:
            return strings().accountSettingsTelegramBusiness
        case .sendGift:
            return strings().accountSettingsSendGift
        case .stars:
            return strings().accountSettingsStars
        }
    }
    
    var searchIcon: SettingsSearchableItemIcon {
        switch self {
        case .chatFolders:
            return .filters
        case .passport:
            return .passport
        case .premium:
            return .premium
        case .business:
            return .business
        case .sendGift:
            return .gift
        case .stars:
            return .stars
        }
    }
    
    var searchIndex: Int32 {
        return rawValue
    }
}
