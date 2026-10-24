import Cocoa
import TGUIKit
import SwiftSignalKit
import Postbox
import TelegramCore
import InAppSettings
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import FoundationUtils
import AlertsUI
import AvatarUI
import ShortPeerRow
import LocalAnimations
import TelegramIconsTheme
import FilePanels
import TelegramMediaUtils
import AvatarEditorUI
import SystemPermissions

public enum NotificationsAndSoundsEntryTag: ItemListItemTag {
    case allAccounts
    case messagePreviews
    case includeChannels
    case includeMutedChats
    case unreadCountCategory
    case joinedNotifications
    case reset
    case tone
    case messageEffect
    case badgeEnabled
    case reactions
    case privateChats
    case groupChats
    case channels
    case stories

    public var stableId: InputDataEntryId {
        switch self {
        case .allAccounts:
            return .general(_id_all_accounts)
        case .messagePreviews:
            return .general(_id_message_preview)
        case .includeChannels:
            return .general(_id_include_channels)
        case .includeMutedChats:
            return .general(_id_include_muted_chats)
        case .unreadCountCategory:
            return .general(_id_count_unred_messages)
        case .joinedNotifications:
            return .general(_id_new_contacts)
        case .reset:
            return .general(_id_reset)
        case .tone:
            return .general(_id_tone)
        case .messageEffect:
            return .general(_id_message_effect)
        case .badgeEnabled:
            return .general(_id_badge_enabled)
        case .reactions:
            return .custom(_id_reactions)
        case .privateChats:
            return .custom(_id_category(.privateChats))
        case .groupChats:
            return .custom(_id_category(.groupChats))
        case .channels:
            return .custom(_id_category(.channels))
        case .stories:
            return .custom(_id_category(.stories))
        }
    }
    
    public func isEqual(to other: ItemListItemTag) -> Bool {
        if let other = other as? NotificationsAndSoundsEntryTag, self == other {
            return true
        } else {
            return false
        }
    }
}

private final class NotificationArguments {
    public let resetAllNotifications:() -> Void
    public let toggleMessagesPreview:() -> Void
    public let toggleNotifications:() -> Void
    public let notificationTone:() -> Void
    public let toggleIncludeUnreadChats:(Bool) -> Void
    public let toggleCountUnreadMessages:(Bool) -> Void
    public let toggleIncludeGroups:(Bool) -> Void
    public let toggleIncludeChannels:(Bool) -> Void
    public let allAcounts: ()-> Void
    public let snoof: ()-> Void
    public let updateJoinedNotifications: (Bool) -> Void
    public let toggleBadge: (Bool)->Void
    public let toggleRequestUserAttention: ()->Void
    public let toggleInAppSounds:(Bool)->Void
    public let toggleChats:()->Void
    public let toggleIncomingCalls:()->Void
    public let openCategory:(NotificationSettingsCategory)->Void
    public let openReactions:()->Void
    public init(resetAllNotifications: @escaping() -> Void, toggleMessagesPreview:@escaping() -> Void, toggleNotifications:@escaping() -> Void, notificationTone:@escaping() -> Void, toggleIncludeUnreadChats:@escaping(Bool) -> Void, toggleCountUnreadMessages:@escaping(Bool) -> Void, toggleIncludeGroups:@escaping(Bool) -> Void, toggleIncludeChannels:@escaping(Bool) -> Void, allAcounts: @escaping()-> Void, snoof: @escaping()-> Void, updateJoinedNotifications: @escaping(Bool) -> Void, toggleBadge: @escaping(Bool)->Void, toggleRequestUserAttention: @escaping ()->Void, toggleInAppSounds: @escaping(Bool)->Void, toggleChats: @escaping()->Void, toggleIncomingCalls:@escaping()->Void, openCategory:@escaping(NotificationSettingsCategory)->Void, openReactions:@escaping()->Void) {
        self.resetAllNotifications = resetAllNotifications
        self.toggleMessagesPreview = toggleMessagesPreview
        self.toggleNotifications = toggleNotifications
        self.notificationTone = notificationTone
        self.toggleIncludeUnreadChats = toggleIncludeUnreadChats
        self.toggleCountUnreadMessages = toggleCountUnreadMessages
        self.toggleIncludeGroups = toggleIncludeGroups
        self.toggleIncludeChannels = toggleIncludeChannels
        self.allAcounts = allAcounts
        self.snoof = snoof
        self.updateJoinedNotifications = updateJoinedNotifications
        self.toggleBadge = toggleBadge
        self.toggleRequestUserAttention = toggleRequestUserAttention
        self.toggleInAppSounds = toggleInAppSounds
        self.toggleChats = toggleChats
        self.toggleIncomingCalls = toggleIncomingCalls
        self.openCategory = openCategory
        self.openReactions = openReactions
    }
}

private let _id_all_accounts = InputDataIdentifier("_id_all_accounts")
private let _id_notifications = InputDataIdentifier("_id_notifications")
private let _id_message_preview = InputDataIdentifier("_id_message_preview")
private let _id_reset = InputDataIdentifier("_id_reset")

private let _id_badge_enabled = InputDataIdentifier("_badge_enabled")
private let _id_include_muted_chats = InputDataIdentifier("_id_include_muted_chats")
private let _id_include_public_group = InputDataIdentifier("_id_include_public_group")
private let _id_include_channels = InputDataIdentifier("_id_include_channels")
private let _id_count_unred_messages = InputDataIdentifier("_id_count_unred_messages")
private let _id_new_contacts = InputDataIdentifier("_id_new_contacts")
private let _id_snoof = InputDataIdentifier("_id_snoof")
private let _id_tone = InputDataIdentifier("_id_tone")
private let _id_bounce = InputDataIdentifier("_id_bounce")

private let _id_turnon_notifications = InputDataIdentifier("_id_turnon_notifications")
private let _id_turnon_notifications_title = InputDataIdentifier("_id_turnon_notifications_title")

private let _id_message_effect = InputDataIdentifier("_id_message_effect")
private let _id_reactions = InputDataIdentifier("_id_reactions")
private func _id_category(_ category: NotificationSettingsCategory) -> InputDataIdentifier {
    return InputDataIdentifier("_id_category_\(category)")
}


private let _id_accept_calls = InputDataIdentifier("_id_accept_calls")
private let _id_accept_secret_chats = InputDataIdentifier("_id_accept_secret_chats")

private struct State : Equatable {
    public var acceptSecretChats: Bool = true
    public var acceptCalls: Bool = true
    public var session: RecentAccountSession?
}

private struct CategoryRow : Equatable {
    let title: String
    let value: String
    let description: String?
    let viewType: GeneralViewType
}

private func categoryEntry(sectionId: Int32, index: Int32, identifier: InputDataIdentifier, row: CategoryRow, icon: CGImage, action: @escaping()->Void) -> InputDataEntry {
    return .custom(sectionId: sectionId, index: index, value: .none, identifier: identifier, equatable: .init(row), comparable: nil, item: { initialSize, stableId in
        let item = GeneralInteractedRowItem(initialSize, stableId: stableId, name: row.title, icon: icon, nameStyle: ControlStyle(font: .normal(.title), foregroundColor: theme.colors.text), description: row.description, descTextColor: theme.colors.grayText, type: .nextContext(row.value), viewType: row.viewType, action: action)
        item.balancedDescriptionLayout = true
        return item
    })
}

private func categoryValue(_ category: NotificationSettingsCategory, settings: GlobalNotificationSettingsSet) -> String {
    if case .stories = category {
        switch settings.privateChats.storySettings.mute {
        case .default:
            return strings().notificationSettingsTopChats
        case .muted:
            return strings().notificationSettingsOff
        case .unmuted:
            return strings().notificationSettingsOn
        }
    }
    return category.messageSettings(settings).enabled ? strings().notificationSettingsOn : strings().notificationSettingsOff
}

private func notificationEntries(state: State, settings:InAppNotificationSettings, soundList: NotificationSoundList?, globalSettings: GlobalNotificationSettingsSet, exceptions: [NotificationException], accounts: [AccountWithInfo], unAuthStatus: NotificationAuthorizationStatus, arguments: NotificationArguments) -> [InputDataEntry] {
    
    var entries:[InputDataEntry] = []
    
    var sectionId: Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    switch unAuthStatus {
    case .denied:
        
        entries.append(InputDataEntry.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_turnon_notifications_title, equatable: nil, comparable: nil, item: { initialSize, stableId in
            return TitleAndInfoAlertItem(initialSize, stableId: stableId, title: strings().notificationSettingsTurnOnTextTitle, info: strings().notificationSettingsTurnOnTextText, viewType: .firstItem)
        }))
        index += 1
        
        entries.append(InputDataEntry.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_turnon_notifications, data: InputDataGeneralData(name: strings().notificationSettingsTurnOn, color: theme.colors.text, type: .none, viewType: .lastItem, action: {
            openSystemSettings(.notifications)
        })))
        index += 1
        
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    default:
        break
    }
    
    if accounts.count > 1 {
        entries.append(InputDataEntry.desc(sectionId: sectionId, index: index, text: .plain(strings().notificationSettingsShowNotificationsFrom), data: InputDataGeneralTextData(viewType: .textTopItem)))
        index += 1
        
        entries.append(InputDataEntry.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_all_accounts, data: InputDataGeneralData(name: strings().notificationSettingsAllAccounts, color: theme.colors.text, type: .switchable(settings.notifyAllAccounts), viewType: .singleItem, action: {
            arguments.allAcounts()
        })))
        index += 1
        
        entries.append(InputDataEntry.desc(sectionId: sectionId, index: index, text: .plain(settings.notifyAllAccounts ? strings().notificationSettingsShowNotificationsFromOn : strings().notificationSettingsShowNotificationsFromOff), data: InputDataGeneralTextData(viewType: .textBottomItem)))
        index += 1
        
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        
    }
    
    entries.append(InputDataEntry.desc(sectionId: sectionId, index: index, text: .plain(strings().notificationSettingsMessageNotifications), data: InputDataGeneralTextData(viewType: .textTopItem)))
    index += 1
    
    let categories: [NotificationSettingsCategory] = [.privateChats, .groupChats, .channels, .stories]
    for (i, category) in categories.enumerated() {
        let count = exceptions.filter { $0.hasCustomSettings(for: category) }.count
        let row = CategoryRow(title: category.title, value: categoryValue(category, settings: globalSettings), description: count > 0 ? strings().notificationSettingsExceptionsOther(count) : nil, viewType: i == 0 ? .firstItem : .innerItem)
        entries.append(categoryEntry(sectionId: sectionId, index: index, identifier: _id_category(category), row: row, icon: category.icon, action: {
            arguments.openCategory(category)
        }))
        index += 1
    }
    
    let reactionsRow = CategoryRow(title: strings().notificationSettingsReactions, value: globalSettings.reactionSettings.messages == .nobody ? strings().notificationSettingsOff : strings().notificationSettingsOn, description: nil, viewType: .lastItem)
    entries.append(categoryEntry(sectionId: sectionId, index: index, identifier: _id_reactions, row: reactionsRow, icon: reactionsNotificationIcon, action: arguments.openReactions))
    index += 1
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    entries.append(InputDataEntry.desc(sectionId: sectionId, index: index, text: .plain(strings().notificationSettingsThisDeviceHeader), data: InputDataGeneralTextData(viewType: .textTopItem)))
    index += 1
    
    entries.append(InputDataEntry.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_notifications, data: InputDataGeneralData(name: strings().notificationSettingsToggleNotifications, color: theme.colors.text, type: .switchable(settings.enabled), viewType: .firstItem, action: {
        arguments.toggleNotifications()
    })))
    index += 1
    
    entries.append(InputDataEntry.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_message_preview, data: InputDataGeneralData(name: strings().notificationSettingsThisDeviceShowMessageText, color: theme.colors.text, type: .switchable(settings.displayPreviews), viewType: .innerItem, action: {
        arguments.toggleMessagesPreview()
    })))
    index += 1
    
    entries.append(InputDataEntry.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_tone, data: InputDataGeneralData(name: strings().notificationSettingsThisDeviceDefaultSound, color: theme.colors.text, type: .nextContext(localizedPeerNotificationSoundString(sound: settings.tone, list: soundList?.sounds)), viewType: .innerItem, action: arguments.notificationTone)))
    index += 1

    entries.append(InputDataEntry.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_bounce, data: InputDataGeneralData(name: strings().notificationSettingsBounceDockIcon, color: theme.colors.text, type: .switchable(settings.requestUserAttention), viewType: .lastItem, action: {
        arguments.toggleRequestUserAttention()
    })))
    index += 1
    
    entries.append(InputDataEntry.desc(sectionId: sectionId, index: index, text: .plain(strings().notificationSettingsThisDeviceInfo), data: InputDataGeneralTextData(viewType: .textBottomItem)))
    index += 1
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    entries.append(InputDataEntry.desc(sectionId: sectionId, index: index, text: .plain(strings().notificationSettingsSnoofHeader), data: InputDataGeneralTextData(viewType: .textTopItem)))
    index += 1
    
    entries.append(InputDataEntry.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_snoof, data: InputDataGeneralData(name: strings().notificationSettingsSnoof, color: theme.colors.text, type: .switchable(!settings.showNotificationsOutOfFocus), viewType: .singleItem, action: {
        arguments.snoof()
    })))
    index += 1
    
    entries.append(InputDataEntry.desc(sectionId: sectionId, index: index, text: .plain(!settings.showNotificationsOutOfFocus ? strings().notificationSettingsSnoofOn : strings().notificationSettingsSnoofOff), data: InputDataGeneralTextData(viewType: .textBottomItem)))
    index += 1
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    if let _ = state.session {
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().sessionPreviewAcceptHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1

        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_accept_secret_chats, data: InputDataGeneralData(name: strings().sessionPreviewAcceptSecret, color: theme.colors.text, type: .switchable(state.acceptSecretChats), viewType: .firstItem, enabled: true, action: {
            arguments.toggleChats()
        })))
        index += 1
        
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_accept_calls, data: InputDataGeneralData(name: strings().sessionPreviewAcceptCalls, color: theme.colors.text, type: .switchable(state.acceptCalls), viewType: .lastItem, enabled: true, action: {
            arguments.toggleIncomingCalls()
        })))
        index += 1

        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    }
    
    entries.append(InputDataEntry.desc(sectionId: sectionId, index: index, text: .plain(strings().notificationSettingsSoundEffects), data: InputDataGeneralTextData(viewType: .textTopItem)))
    index += 1

    entries.append(InputDataEntry.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_message_effect, data: InputDataGeneralData(name: strings().notificationSettingsSendMessageEffect, color: theme.colors.text, type: .switchable(FastSettings.inAppSounds), viewType: .singleItem, action: {
        arguments.toggleInAppSounds(!FastSettings.inAppSounds)
    })))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    entries.append(InputDataEntry.desc(sectionId: sectionId, index: index, text: .plain(strings().notificationSettingsBadgeHeader), data: InputDataGeneralTextData(viewType: .textTopItem)))
    index += 1
    
    entries.append(InputDataEntry.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_badge_enabled, data: InputDataGeneralData(name: strings().notificationSettingsBadgeEnabled, color: theme.colors.text, type: .switchable(settings.badgeEnabled), viewType: .firstItem, action: {
        arguments.toggleBadge(!settings.badgeEnabled)
    })))
    index += 1
    
    entries.append(InputDataEntry.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_include_public_group, data: InputDataGeneralData(name: strings().notificationSettingsIncludeGroups, color: theme.colors.text, type: .switchable(settings.totalUnreadCountIncludeTags.contains(.group)), viewType: .innerItem, enabled: settings.badgeEnabled, action: {
        arguments.toggleIncludeGroups(!settings.totalUnreadCountIncludeTags.contains(.group))
    })))
    index += 1
    
    entries.append(InputDataEntry.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_include_channels, data: InputDataGeneralData(name: strings().notificationSettingsIncludeChannels, color: theme.colors.text, type: .switchable(settings.totalUnreadCountIncludeTags.contains(.channel)), viewType: .innerItem, enabled: settings.badgeEnabled, action: {
        arguments.toggleIncludeChannels(!settings.totalUnreadCountIncludeTags.contains(.channel))
    })))
    index += 1
    
    entries.append(InputDataEntry.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_count_unred_messages, data: InputDataGeneralData(name: strings().notificationSettingsCountUnreadMessages, color: theme.colors.text, type: .switchable(settings.totalUnreadCountDisplayCategory == .messages), viewType: .lastItem, enabled: settings.badgeEnabled, action: {
        arguments.toggleCountUnreadMessages(settings.totalUnreadCountDisplayCategory != .messages)
    })))
    index += 1
    
    entries.append(InputDataEntry.desc(sectionId: sectionId, index: index, text: .plain(strings().notificationSettingsBadgeDesc), data: InputDataGeneralTextData(viewType: .textBottomItem)))
    index += 1
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    entries.append(InputDataEntry.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_new_contacts, data: InputDataGeneralData(name: strings().notificationSettingsContactJoined, color: theme.colors.text, type: .switchable(globalSettings.contactsJoined), viewType: .singleItem, action: {
        arguments.updateJoinedNotifications(!globalSettings.contactsJoined)
    })))
    index += 1
    
    entries.append(InputDataEntry.desc(sectionId: sectionId, index: index, text: .plain(strings().notificationSettingsContactJoinedInfo), data: InputDataGeneralTextData(viewType: .textBottomItem)))
    index += 1
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    entries.append(InputDataEntry.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_reset, data: InputDataGeneralData(name: strings().notificationSettingsResetAll, color: theme.colors.redUI, type: .none, viewType: .singleItem, action: {
        arguments.resetAllNotifications()
    })))
    index += 1
    
    entries.append(InputDataEntry.desc(sectionId: sectionId, index: index, text: .plain(strings().notificationSettingsResetAllInfo), data: InputDataGeneralTextData(viewType: .textBottomItem)))
    index += 1
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

public func NotificationPreferencesController(_ context: any AccountContextProtocol, focusOnItemTag: NotificationsAndSoundsEntryTag? = nil) -> ViewController {
    
    
    let initialState = State()
    
    let exceptionsContext = NotificationExceptionsContext(context: context)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    let arguments = NotificationArguments(resetAllNotifications: {
        verifyAlert_button(for: context.window, header: strings().notificationSettingsConfirmReset, information: strings().chatConfirmActionUndonable, successHandler: { _ in
            exceptionsContext.removeAll()
            _ = resetPeerNotificationSettings(network: context.account.network).start()
        })
    }, toggleMessagesPreview: {
        _ = updateInAppNotificationSettingsInteractively(accountManager: context.sharedContext.accountManager, {$0.withUpdatedDisplayPreviews(!$0.displayPreviews)}).start()
    }, toggleNotifications: {
        _ = updateInAppNotificationSettingsInteractively(accountManager: context.sharedContext.accountManager, {$0.withUpdatedEnables(!$0.enabled)}).start()
    }, notificationTone: {
        context.bindings.rootNavigation().push(NotificationSoundController(context: context))
    }, toggleIncludeUnreadChats: { enable in
        _ = updateInAppNotificationSettingsInteractively(accountManager: context.sharedContext.accountManager, {$0.withUpdatedTotalUnreadCountDisplayStyle(enable ? .raw : .filtered)}).start()
    }, toggleCountUnreadMessages: { enable in
        _ = updateInAppNotificationSettingsInteractively(accountManager: context.sharedContext.accountManager, {$0.withUpdatedTotalUnreadCountDisplayCategory(enable ? .messages : .chats)}).start()
    }, toggleIncludeGroups: { enable in
        _ = updateInAppNotificationSettingsInteractively(accountManager: context.sharedContext.accountManager, { value in
            var tags: PeerSummaryCounterTags = value.totalUnreadCountIncludeTags
            if enable {
                tags.insert(.group)
            } else {
                tags.remove(.group)
            }
            return value.withUpdatedTotalUnreadCountIncludeTags(tags)
        }).start()
    }, toggleIncludeChannels: { enable in
        _ = updateInAppNotificationSettingsInteractively(accountManager: context.sharedContext.accountManager, { value in
            var tags: PeerSummaryCounterTags = value.totalUnreadCountIncludeTags
            if enable {
                tags.insert(.channel)
            } else {
                tags.remove(.channel)
            }
            return value.withUpdatedTotalUnreadCountIncludeTags(tags)
        }).start()
    }, allAcounts: {
        _ = updateInAppNotificationSettingsInteractively(accountManager: context.sharedContext.accountManager, { value in
            return value.withUpdatedNotifyAllAccounts(!value.notifyAllAccounts)
        }).start()
    }, snoof: {
        _ = updateInAppNotificationSettingsInteractively(accountManager: context.sharedContext.accountManager, { value in
            return value.withUpdatedSnoof(!value.showNotificationsOutOfFocus)
        }).start()
    }, updateJoinedNotifications: { value in
        _ = updateGlobalNotificationSettingsInteractively(postbox: context.account.postbox, { settings in
            var settings = settings
            settings.contactsJoined = value
            return settings
        }).start()
    }, toggleBadge: { enabled in
        _ = updateInAppNotificationSettingsInteractively(accountManager: context.sharedContext.accountManager, { value in
            return value.withUpdatedBadgeEnabled(enabled)
        }).start()
    }, toggleRequestUserAttention: {
        _ = updateInAppNotificationSettingsInteractively(accountManager: context.sharedContext.accountManager, { value in
            return value.withUpdatedRequestUserAttention(!value.requestUserAttention)
        }).start()
    }, toggleInAppSounds: { value in
        FastSettings.toggleInAppSouds(value)
    }, toggleChats: {
        let session: RecentAccountSession? = stateValue.with { $0.session }
        updateState { current in
            var current = current
            current.acceptSecretChats = !current.acceptSecretChats
            return current
        }
        if let session = session {
            _ = context.activeSessionsContext.updateSessionAcceptsSecretChats(session, accepts: stateValue.with { $0.acceptSecretChats }).start()
        }
    }, toggleIncomingCalls: {
        let session: RecentAccountSession? = stateValue.with { $0.session }
        updateState { current in
            var current = current
            current.acceptCalls = !current.acceptCalls
            return current
        }
        if let session = session {
            _ = context.activeSessionsContext.updateSessionAcceptsIncomingCalls(session, accepts: stateValue.with { $0.acceptCalls }).start()
        }
    }, openCategory: { category in
        context.bindings.rootNavigation().push(NotificationCategorySettingsController(context: context, category: category, exceptionsContext: exceptionsContext))
    }, openReactions: {
        context.bindings.rootNavigation().push(ReactionNotificationSettingsController(context: context))
    })
    
    let actionsDisposable = DisposableSet()
    
    
    let entriesSignal = combineLatest(queue: prepareQueue, appNotificationSettings(accountManager: context.sharedContext.accountManager), globalNotificationSettings(postbox: context.account.postbox), exceptionsContext.exceptions, context.sharedContext.activeAccountsWithInfo |> map { $0.accounts }, NotificationSettingsHooks.shared.authorizationStatus(context), context.engine.peers.notificationSoundList(), statePromise.get()) |> map { inAppSettings, globalSettings, exceptions, accounts, unAuthStatus, soundList, state -> [InputDataEntry] in
        return notificationEntries(state: state, settings: inAppSettings, soundList: soundList, globalSettings: globalSettings, exceptions: exceptions, accounts: accounts, unAuthStatus: unAuthStatus, arguments: arguments)
    }

    
    let controller = InputDataController(dataSignal: entriesSignal |> map { InputDataSignalValue(entries: $0) }, title: strings().telegramNotificationSettingsViewController, removeAfterDisappear: false, hasDone: false, identifier: "notification-settings")
    
    
    
    controller.didLoad = { controller, _ in
        if let focusOnItemTag = focusOnItemTag {
            controller.genericView.tableView.scroll(to: .center(id: focusOnItemTag.stableId, innerId: nil, animated: true, focus: .init(focus: true), inset: 0), inset: NSEdgeInsets())
        }
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    let sessionsSignal: Signal<ActiveSessionsContextState, NoError> = context.activeSessionsContext.state
    
    actionsDisposable.add(sessionsSignal.start(next: { state in
        updateState { current in
            var current = current
            current.session = state.sessions.first(where: { $0.isCurrent })
            current.acceptCalls = current.session?.flags.contains(.acceptsIncomingCalls) ?? false
            current.acceptSecretChats = current.session?.flags.contains(.acceptsSecretChats) ?? false
            return current
        }
    }))
    
    return controller
}
