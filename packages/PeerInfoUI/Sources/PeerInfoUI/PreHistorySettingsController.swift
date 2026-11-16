import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import AlertsUI
import InAppSettings
import InactiveChannelsUI
import AppAnalytics


private final class Arguments {
    public let context: any AccountContextProtocol
    public let toggle: (Bool) -> Void
    public init(context: any AccountContextProtocol, toggle: @escaping (Bool) -> Void) {
        self.context = context
        self.toggle = toggle
    }
}

private struct State : Equatable {
    public var enabled: Bool?
    public var defaultValue: Bool = false
    public var isGroup: Bool = false
    public var linkedDiscussionPeerId: PeerId?
    public var peerTitle: String = ""
    public var peerHasAdminRights: Bool = false
    public var peerHasPinPermission: Bool = false
}

private let _id_visible = InputDataIdentifier("_id_visible")
private let _id_hidden = InputDataIdentifier("_id_hidden")

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []

    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().preHistorySettingsHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    let enabled = state.enabled ?? state.defaultValue

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_visible, data: .init(name: strings().peerInfoPreHistoryVisible, color: theme.colors.text, type: .selectable(enabled), viewType: .firstItem, action: {
        arguments.toggle(true)
    })))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_hidden, data: .init(name: strings().peerInfoPreHistoryHidden, color: theme.colors.text, type: .selectable(!enabled), viewType: .lastItem, action: {
        arguments.toggle(false)
    })))
    index += 1

    let description: String
    if enabled {
        description = strings().preHistorySettingsDescriptionVisible
    } else if state.isGroup {
        description = strings().preHistorySettingsDescriptionGroupHidden
    } else {
        description = strings().preHistorySettingsDescriptionHidden
    }
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(description), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

public func PreHistorySettingsController(context: any AccountContextProtocol, peerId: PeerId, onComplete: @escaping (PeerId?) -> Void) -> InputDataController {

    let actionsDisposable = DisposableSet()

    let initialState = State()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    var close: (() -> Void)? = nil
    var completionFired = false
    let fireCompletion: (PeerId?) -> Void = { resultPeerId in
        guard !completionFired else { return }
        completionFired = true
        onComplete(resultPeerId)
    }

    let arguments = Arguments(context: context, toggle: { enabled in
        updateState { current in
            var current = current
            current.enabled = enabled
            return current
        }
    })

    actionsDisposable.add(context.account.postbox.peerView(id: peerId).start(next: { peerView in
        updateState { current in
            var current = current
            let cachedData = peerView.cachedData as? CachedChannelData
            current.defaultValue = cachedData?.flags.contains(.preHistoryEnabled) ?? false
            current.isGroup = peerId.namespace == Namespaces.Peer.CloudGroup
            current.linkedDiscussionPeerId = cachedData?.linkedDiscussionPeerId.peerId
            if let peer = peerViewMainPeer(peerView) {
                current.peerTitle = peer.displayTitle
                if let channel = peer as? TelegramChannel {
                    current.peerHasAdminRights = channel.adminRights != nil
                    current.peerHasPinPermission = channel.hasPermission(.pinMessages)
                }
            }
            return current
        }
    }))

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: strings().peerInfoPreHistory, hasDone: true)
    controller.analyticsScreen = .peerInfoHistoryVisibility


    controller.onDeinit = {
        fireCompletion(nil)
        actionsDisposable.dispose()
    }

    controller.validateData = { _ in
        let state = stateValue.with { $0 }
        let value = state.enabled

        guard let value = value, value != state.defaultValue else {
            fireCompletion(nil)
            close?()
            return .none
        }

        if peerId.namespace == Namespaces.Peer.CloudGroup {
            let convertSignal = context.engine.peers.convertGroupToSupergroup(peerId: peerId)
                |> map(Optional.init)
                |> mapToSignal { upgradedPeerId -> Signal<PeerId?, ConvertGroupToSupergroupError> in
                    guard let upgradedPeerId = upgradedPeerId else {
                        return .single(nil)
                    }
                    return context.engine.peers.updateChannelHistoryAvailabilitySettingsInteractively(peerId: upgradedPeerId, historyAvailableForNewMembers: value)
                        |> mapError { _ in ConvertGroupToSupergroupError.generic }
                        |> mapToSignal { _ -> Signal<PeerId?, ConvertGroupToSupergroupError> in .complete() }
                        |> then(.single(upgradedPeerId) |> mapError { ConvertGroupToSupergroupError.generic })
                }
                |> deliverOnMainQueue

            _ = showModalProgress(signal: convertSignal, for: context.window).start(next: { upgradedPeerId in
                fireCompletion(upgradedPeerId)
                close?()
            }, error: { error in
                switch error {
                case .tooManyChannels:
                    showInactiveChannels(context: context, source: .upgrade)
                case .generic:
                    alert(for: context.window, info: strings().unknownError)
                }
            })
            return .none
        }

        let updateSignal: Signal<PeerId?, NoError> = context.engine.peers.updateChannelHistoryAvailabilitySettingsInteractively(peerId: peerId, historyAvailableForNewMembers: value)
            |> `catch` { _ in .complete() }
            |> map { _ in nil }
            |> deliverOnMainQueue

        if let linkedDiscussionPeerId = state.linkedDiscussionPeerId {
            verifyAlert_button(for: context.window, information: strings().preHistoryConfirmUnlink(state.peerTitle), successHandler: { _ in
                if !state.peerHasAdminRights || !state.peerHasPinPermission {
                    alert(for: context.window, info: strings().channelErrorDontHavePermissions)
                } else {
                    let combined = context.engine.peers.updateGroupDiscussionForChannel(channelId: linkedDiscussionPeerId, groupId: nil)
                        |> `catch` { _ in .complete() }
                        |> map { _ -> PeerId? in nil }
                        |> then(updateSignal)
                    _ = showModalProgress(signal: combined, for: context.window).start(next: { resultPeerId in
                        fireCompletion(resultPeerId)
                        close?()
                    })
                }
            })
        } else {
            _ = showModalProgress(signal: updateSignal, for: context.window).start(next: { resultPeerId in
                fireCompletion(resultPeerId)
                close?()
            })
        }
        return .none
    }

    close = { [weak controller] in
        controller?.navigationController?.back()
    }

    return controller
}
