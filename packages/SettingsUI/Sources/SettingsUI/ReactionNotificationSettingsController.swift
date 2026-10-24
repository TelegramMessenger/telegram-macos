import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import InAppSettings
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import LocalAnimations
import TelegramMediaUtils

private final class Arguments {
    let context: any AccountContextProtocol
    let toggleMessages:()->Void
    let updateMessages:(PeerReactionNotificationSettings.Sources)->Void
    let toggleShowSender:()->Void
    let openSound:()->Void
    init(context: any AccountContextProtocol, toggleMessages:@escaping()->Void, updateMessages:@escaping(PeerReactionNotificationSettings.Sources)->Void, toggleShowSender:@escaping()->Void, openSound:@escaping()->Void) {
        self.context = context
        self.toggleMessages = toggleMessages
        self.updateMessages = updateMessages
        self.toggleShowSender = toggleShowSender
        self.openSound = openSound
    }
}

private struct State : Equatable {
    var settings: PeerReactionNotificationSettings = .default
    var inAppTone: PeerMessageSound = .default
    var soundList: NotificationSoundList?
    var loaded: Bool = false
}

private let _id_messages = InputDataIdentifier("_id_messages")
private let _id_messages_from = InputDataIdentifier("_id_messages_from")
private let _id_show_sender = InputDataIdentifier("_id_show_sender")
private let _id_sound = InputDataIdentifier("_id_sound")

public enum ReactionNotificationEntryTag: ItemListItemTag {
    case messages
    case showSender
    case sound
    
    public var stableId: InputDataEntryId {
        switch self {
        case .messages:
            return .general(_id_messages)
        case .showSender:
            return .general(_id_show_sender)
        case .sound:
            return .general(_id_sound)
        }
    }
    
    public func isEqual(to other: ItemListItemTag) -> Bool {
        if let other = other as? ReactionNotificationEntryTag, self == other {
            return true
        } else {
            return false
        }
    }
}

private func sourceText(_ source: PeerReactionNotificationSettings.Sources) -> String {
    switch source {
    case .everyone:
        return strings().notificationSettingsReactionsEveryone
    case .contacts, .nobody:
        return strings().notificationSettingsReactionsContacts
    }
}

private func sourceItems(_ current: PeerReactionNotificationSettings.Sources, update: @escaping(PeerReactionNotificationSettings.Sources)->Void) -> [ContextMenuItem] {
    return [ContextMenuItem(strings().notificationSettingsReactionsEveryone, handler: {
        update(.everyone)
    }, itemImage: current == .everyone ? MenuAnimation.menu_check_selected.value : nil), ContextMenuItem(strings().notificationSettingsReactionsContacts, handler: {
        update(.contacts)
    }, itemImage: current == .contacts ? MenuAnimation.menu_check_selected.value : nil)]
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []

    var sectionId:Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    let settings = state.settings
    let messagesEnabled = settings.messages != .nobody

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().notificationSettingsNotifyMeAbout), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_messages, data: .init(name: strings().notificationSettingsReactionsMessages, color: theme.colors.text, type: .switchable(messagesEnabled), viewType: messagesEnabled ? .firstItem : .singleItem, action: arguments.toggleMessages)))
    index += 1

    if messagesEnabled {
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_messages_from, data: .init(name: strings().notificationSettingsReactionsFrom, color: theme.colors.text, type: .contextSelector(sourceText(settings.messages), sourceItems(settings.messages, update: arguments.updateMessages)), viewType: .lastItem)))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    if messagesEnabled {
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().notificationSettingsOptions), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1

        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_show_sender, data: .init(name: strings().notificationSettingsCategoryShowSender, color: theme.colors.text, type: .switchable(settings.hideSender != .hide), viewType: .firstItem, action: arguments.toggleShowSender)))
        index += 1

        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_sound, data: .init(name: strings().notificationSettingsCategorySound, color: theme.colors.text, type: .nextContext(localizedPeerNotificationSoundString(sound: effectiveCategorySound(settings.sound), default: state.inAppTone, list: state.soundList?.sounds)), viewType: .lastItem, action: arguments.openSound)))
        index += 1

        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    }

    return entries
}

public func ReactionNotificationSettingsController(context: any AccountContextProtocol, focusOnItemTag: ReactionNotificationEntryTag? = nil) -> InputDataController {

    let actionsDisposable = DisposableSet()

    let initialState = State()

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }

    let updateSettings:(@escaping (PeerReactionNotificationSettings) -> PeerReactionNotificationSettings) -> Void = { f in
        _ = updateGlobalNotificationSettingsInteractively(postbox: context.account.postbox, { settings in
            var settings = settings
            settings.reactionSettings = f(settings.reactionSettings)
            return settings
        }).start()
    }

    let reactionSettings: Signal<PeerReactionNotificationSettings, NoError> = globalNotificationSettings(postbox: context.account.postbox) |> map { $0.reactionSettings } |> distinctUntilChanged

    let arguments = Arguments(context: context, toggleMessages: {
        updateSettings { current in
            var current = current
            current.messages = current.messages == .nobody ? .contacts : .nobody
            return current
        }
    }, updateMessages: { value in
        updateSettings { current in
            var current = current
            current.messages = value
            return current
        }
    }, toggleShowSender: {
        updateSettings { current in
            var current = current
            current.hideSender = current.hideSender == .hide ? .show : .hide
            return current
        }
    }, openSound: {
        context.bindings.rootNavigation().push(NotificationSoundController(context: context, tone: reactionSettings |> map { effectiveCategorySound($0.sound) }, updateTone: { sound in
            updateSettings { current in
                var current = current
                current.sound = sound
                return current
            }
        }))
    })

    actionsDisposable.add(combineLatest(queue: .mainQueue(), reactionSettings, appNotificationSettings(accountManager: context.sharedContext.accountManager), context.engine.peers.notificationSoundList()).start(next: { settings, inAppSettings, soundList in
        updateState { current in
            var current = current
            current.settings = settings
            current.inAppTone = inAppSettings.tone
            current.soundList = soundList
            current.loaded = true
            return current
        }
    }))

    let signal = statePromise.get() |> filter { $0.loaded } |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: strings().notificationSettingsReactions, removeAfterDisappear: false, hasDone: false, identifier: "reaction-notification-settings")
    
    let pendingFocus = Atomic<Bool>(value: focusOnItemTag != nil)
    controller.afterTransaction = { controller in
        guard let focusOnItemTag = focusOnItemTag, controller.genericView.tableView.item(stableId: focusOnItemTag.stableId) != nil, pendingFocus.swap(false) else {
            return
        }
        controller.genericView.tableView.scroll(to: .center(id: focusOnItemTag.stableId, innerId: nil, animated: true, focus: .init(focus: true), inset: 0), inset: NSEdgeInsets())
    }

    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    return controller
}
