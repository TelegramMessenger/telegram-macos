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
import TelegramTheme
import ColorPalette
import TelegramIconsTheme
import LocalAnimations
import TelegramMediaUtils
import TelegramUtils

private enum ExceptionMute: Equatable {
    case alwaysOn
    case alwaysOff
}

private final class Arguments {
    let updateMute:(ExceptionMute)->Void
    let updatePreviews:(Bool)->Void
    let updateSound:(PeerMessageSound)->Void
    let upload:()->Void
    let removeCloudSound:(TelegramMediaFile)->Void
    let remove:()->Void
    init(updateMute:@escaping(ExceptionMute)->Void, updatePreviews:@escaping(Bool)->Void, updateSound:@escaping(PeerMessageSound)->Void, upload:@escaping()->Void, removeCloudSound:@escaping(TelegramMediaFile)->Void, remove:@escaping()->Void) {
        self.updateMute = updateMute
        self.updatePreviews = updatePreviews
        self.updateSound = updateSound
        self.upload = upload
        self.removeCloudSound = removeCloudSound
        self.remove = remove
    }
}

private struct State : Equatable {
    var currentMute: ExceptionMute = .alwaysOn
    var currentPreviews: Bool = true
    var currentSound: PeerMessageSound = .default
    var mute: ExceptionMute?
    var previews: Bool?
    var sound: PeerMessageSound?
    var defaultSound: PeerMessageSound = .default
    var soundList: NotificationSoundList?
    var canRemove: Bool = false
    var isStories: Bool = false
    var maxSavedCount: Int = 0
    var loaded: Bool = false

    var effectiveMute: ExceptionMute {
        return mute ?? currentMute
    }
    var effectivePreviews: Bool {
        return previews ?? currentPreviews
    }
    var effectiveSound: PeerMessageSound {
        return sound ?? currentSound
    }
    var selectedSound: PeerMessageSound {
        let sound = effectiveSound
        if case let .cloud(fileId) = sound, let list = soundList, !list.sounds.contains(where: { $0.file.fileId.id == fileId }) {
            return .default
        }
        return sound
    }
}

private let _id_always_on = InputDataIdentifier("_id_always_on")
private let _id_always_off = InputDataIdentifier("_id_always_off")
private let _id_preview_on = InputDataIdentifier("_id_preview_on")
private let _id_preview_off = InputDataIdentifier("_id_preview_off")
private let _id_upload = InputDataIdentifier("_id_upload")
private let _id_remove = InputDataIdentifier("_id_remove")

private func _id_sound(_ sound: PeerMessageSound) -> InputDataIdentifier {
    switch sound {
    case .none:
        return .init("_id_sound_none")
    case .`default`:
        return .init("_id_sound_default")
    case let .bundledClassic(id):
        return .init("_id_sound_classic_\(id)")
    case let .bundledModern(id):
        return .init("_id_sound_modern_\(id)")
    case let .cloud(id):
        return .init("_id_sound_cloud_\(id)")
    }
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []

    var sectionId:Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    if state.canRemove {
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_remove, data: .init(name: strings().notificationSettingsExceptionsRemove, color: theme.colors.redUI, type: .none, viewType: .singleItem, action: arguments.remove)))
        index += 1

        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    }

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(state.isStories ? strings().notificationSettingsExceptionStoriesHeader : strings().notificationSettingsExceptionNotificationsHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_always_on, data: .init(name: strings().notificationSettingsExceptionsAlwaysOn, color: theme.colors.text, type: .selectable(state.effectiveMute == .alwaysOn), viewType: .firstItem, action: {
        arguments.updateMute(.alwaysOn)
    })))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_always_off, data: .init(name: strings().notificationSettingsExceptionsAlwaysOff, color: theme.colors.text, type: .selectable(state.effectiveMute == .alwaysOff), viewType: .lastItem, action: {
        arguments.updateMute(.alwaysOff)
    })))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    if state.effectiveMute != .alwaysOff {
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(state.isStories ? strings().notificationSettingsExceptionAuthorNameHeader : strings().notificationSettingsExceptionPreviewHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1

        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_preview_on, data: .init(name: strings().notificationSettingsExceptionsAlwaysOn, color: theme.colors.text, type: .selectable(state.effectivePreviews), viewType: .firstItem, action: {
            arguments.updatePreviews(true)
        })))
        index += 1

        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_preview_off, data: .init(name: strings().notificationSettingsExceptionsAlwaysOff, color: theme.colors.text, type: .selectable(!state.effectivePreviews), viewType: .lastItem, action: {
            arguments.updatePreviews(false)
        })))
        index += 1

        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    }

    if state.isStories && state.effectiveMute == .alwaysOff {
        return entries
    }

    let selected = state.selectedSound
    let list = state.soundList?.sounds ?? []
    let canAdd = list.count < state.maxSavedCount

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().notificationSoundTonesTitle.uppercased()), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    for (i, item) in list.enumerated() {
        let sound: PeerMessageSound = .cloud(fileId: item.file.fileId.id)
        var viewType = bestGeneralViewType(list, for: i)
        if canAdd {
            viewType = i == 0 ? .firstItem : .innerItem
        }
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_sound(sound), data: .init(name: localizedPeerNotificationSoundString(sound: sound, default: nil, list: list), color: theme.colors.text, type: .selectable(selected == sound), viewType: viewType, action: {
            arguments.updateSound(sound)
        }, menuItems: {
            return [ContextMenuItem(strings().contextRemove, handler: {
                arguments.removeCloudSound(item.file)
            }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value)]
        })))
        index += 1
    }

    if canAdd {
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_upload, data: .init(name: strings().notificationSoundTonesUpload, color: theme.colors.accent, icon: theme.icons.notification_sound_add, type: .none, viewType: list.isEmpty ? .singleItem : .lastItem, action: arguments.upload)))
        index += 1
    }

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().notificationSoundTonesInfo), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    var modern: [PeerMessageSound] = [.default, .none]
    for i in 0 ..< 12 {
        modern.append(.bundledModern(id: Int32(i)))
    }
    var classic: [PeerMessageSound] = []
    for i in 0 ..< 8 {
        classic.append(.bundledClassic(id: Int32(i)))
    }

    let appendTones:(String, [PeerMessageSound]) -> Void = { header, sounds in
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(header), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1
        for (i, sound) in sounds.enumerated() {
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_sound(sound), data: .init(name: localizedPeerNotificationSoundString(sound: sound, default: sound == .default ? state.defaultSound : nil, list: list), color: theme.colors.text, type: .selectable(selected == sound), viewType: bestGeneralViewType(sounds, for: i), action: {
                arguments.updateSound(sound)
            })))
            index += 1
        }
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    }

    appendTones(strings().notificationSettingsExceptionAlertTonesHeader, modern)
    appendTones(strings().notificationSettingsExceptionClassicTonesHeader, classic)

    return entries
}

func NotificationExceptionSettingsModalController(context: any AccountContextProtocol, peer: EnginePeer, category: NotificationSettingsCategory, exceptionsContext: NotificationExceptionsContext, isNew: Bool, isAutomatic: Bool = false) -> InputDataModalController {

    let isStories = category == .stories

    let peerId = peer.id

    let actionsDisposable = DisposableSet()

    let initialState = State()

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }

    var close:(()->Void)? = nil

    let updateSound:(PeerMessageSound)->Void = { value in
        playNotificationTone(context: context, sound: value, list: stateValue.with { $0.soundList?.sounds })
        updateState { current in
            var current = current
            current.sound = value
            return current
        }
    }

    let arguments = Arguments(updateMute: { value in
        updateState { current in
            var current = current
            current.mute = value
            return current
        }
    }, updatePreviews: { value in
        updateState { current in
            var current = current
            current.previews = value
            return current
        }
    }, updateSound: updateSound, upload: {
        uploadNotificationTone(context: context, completion: updateSound)
    }, removeCloudSound: { file in
        _ = showModalProgress(signal: context.engine.peers.removeNotificationSound(file: .standalone(media: file)), for: context.window).start()
    }, remove: {
        removeNotificationExceptions(context: context, category: category, peerIds: [peerId])
        close?()
    })

    let key: PostboxViewKey = .peerNotificationSettings(peerIds: Set([peerId]))
    let peerSettings = context.account.postbox.combinedView(keys: [key]) |> take(1) |> map { view in
        return ((view.views[key] as? PeerNotificationSettingsView)?.notificationSettings[peerId] as? TelegramPeerNotificationSettings) ?? .defaultSettings
    }

    actionsDisposable.add(combineLatest(queue: .mainQueue(), peerSettings, globalNotificationSettings(postbox: context.account.postbox) |> take(1), appNotificationSettings(accountManager: context.sharedContext.accountManager) |> take(1), context.engine.peers.notificationSoundList()).start(next: { settings, globalSettings, inAppSettings, soundList in
        let categorySettings = category.messageSettings(globalSettings)
        let now = Int32(Date().timeIntervalSince1970)
        let currentMute: ExceptionMute
        let currentPreviews: Bool
        let currentSound: PeerMessageSound
        let categorySound: PeerMessageSound
        let isDefaultMute: Bool
        if isStories {
            let storySettings = categorySettings.storySettings
            switch settings.storySettings.mute {
            case .unmuted:
                currentMute = .alwaysOn
            case .muted:
                currentMute = .alwaysOff
            case .default:
                switch storySettings.mute {
                case .unmuted:
                    currentMute = .alwaysOn
                case .muted:
                    currentMute = .alwaysOff
                case .default:
                    currentMute = isAutomatic ? .alwaysOn : .alwaysOff
                }
            }
            switch settings.storySettings.hideSender {
            case .show:
                currentPreviews = true
            case .hide:
                currentPreviews = false
            case .default:
                currentPreviews = storySettings.hideSender != .hide
            }
            currentSound = settings.storySettings.sound
            categorySound = effectiveCategorySound(storySettings.sound)
            isDefaultMute = settings.storySettings.mute == .default
        } else {
            switch settings.muteState {
            case .unmuted:
                currentMute = .alwaysOn
            case let .muted(until):
                currentMute = until > now ? .alwaysOff : .alwaysOn
            case .default:
                currentMute = categorySettings.enabled ? .alwaysOn : .alwaysOff
            }
            switch settings.displayPreviews {
            case .show:
                currentPreviews = true
            case .hide:
                currentPreviews = false
            case .default:
                currentPreviews = categorySettings.displayPreviews
            }
            currentSound = settings.messageSound
            categorySound = effectiveCategorySound(categorySettings.sound)
            if case .default = settings.muteState {
                isDefaultMute = true
            } else {
                isDefaultMute = false
            }
        }
        updateState { current in
            var current = current
            if !current.loaded {
                current.currentMute = currentMute
                current.currentPreviews = currentPreviews
                current.currentSound = currentSound
                if isNew, isDefaultMute {
                    current.mute = currentMute == .alwaysOn ? .alwaysOff : .alwaysOn
                }
            }
            current.defaultSound = categorySound == .default ? inAppSettings.tone : categorySound
            current.soundList = soundList
            current.maxSavedCount = NotificationSoundSettings.extract(from: context.appConfiguration).maxSavedCount
            current.canRemove = !isNew && !isAutomatic
            current.isStories = isStories
            current.loaded = true
            return current
        }
    }))

    let signal = statePromise.get() |> filter { $0.loaded } |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: peer._asPeer().displayTitle)

    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    let apply:() -> Void = {
        let state = stateValue.with { $0 }
        if isStories {
            if let mute = state.mute {
                _ = context.engine.peers.updatePeerStoriesMutedSetting(peerId: peerId, mute: mute == .alwaysOn ? .unmuted : .muted).start()
            }
            if let previews = state.previews {
                _ = context.engine.peers.updatePeerStoriesHideSenderSetting(peerId: peerId, hideSender: previews ? .show : .hide).start()
            }
            if let sound = state.sound {
                _ = context.engine.peers.updatePeerStorySoundInteractive(peerId: peerId, sound: sound).start()
            }
        } else {
            if let mute = state.mute {
                _ = context.engine.peers.updatePeerMuteSetting(peerId: peerId, threadId: nil, muteInterval: mute == .alwaysOn ? 0 : Int32.max).start()
            }
            if let previews = state.previews {
                _ = context.engine.peers.updatePeerDisplayPreviewsSetting(peerId: peerId, threadId: nil, displayPreviews: previews ? .show : .hide).start()
            }
            if let sound = state.sound {
                _ = context.engine.peers.updatePeerNotificationSoundInteractive(peerId: peerId, threadId: nil, sound: sound).start()
            }
        }
        if state.mute != nil || state.previews != nil || state.sound != nil {
            exceptionsContext.add(peerId)
        }
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().modalDone, accept: {
        apply()
        close?()
    }, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: {
        close?()
    })

    close = { [weak modalController] in
        modalController?.modal?.close()
    }

    return modalController
}
