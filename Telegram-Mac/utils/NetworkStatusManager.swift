import Foundation
import TelegramContext
import Localization
import TelegramTheme
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import ObjcUtils
import AppKit

public enum NetworkConnectingStatus: Equatable {
    case core(ConnectionStatus)
    case updated
    case connected

    public var text: String {
        switch self {
        case .connected:
            return strings().connectionStatusConnected
        case .updated:
            return strings().connectionStatusUpdated
        case let .core(status):
            switch status {
            case let .connecting(proxyAddress, _):
                return proxyAddress != nil ? strings().connectionStatusConnectingToProxy : strings().connectionStatusConnecting
            case .waitingForNetwork:
                return strings().connectionStatusWaitingForNetwork
            case .updating:
                return strings().connectionStatusUpdating
            case .online:
                return ""
            }
        }
    }

    public var shouldAddProgress: Bool {
        switch self {
        case .connected, .updated:
            return false
        case let .core(status):
            switch status {
            case .connecting, .waitingForNetwork, .updating:
                return true
            case .online:
                return false
            }
        }
    }
}

public final class NetworkStatusManager {
    private let account: Account
    private let sharedContext: any SharedAccountContextProtocol
    private let window: Window
    private let managesWindowTitle: Bool
    private let disposable = MetaDisposable()

    private let statusPromise = Promise<NetworkConnectingStatus?>(nil)
    public var statusSignal: Signal<NetworkConnectingStatus?, NoError> {
        return statusPromise.get()
    }

    private var peer: EnginePeer?

    public init(account: Account, window: Window, sharedContext: any SharedAccountContextProtocol, managesWindowTitle: Bool = true) {
        self.account = account
        self.window = window
        self.managesWindowTitle = managesWindowTitle
        self.sharedContext = sharedContext
        initialize()
    }

    public func initialize() {
        let updating: Signal<Bool, NoError> = account.stateManager.isUpdating |> mapToSignal { isUpdating in
            return isUpdating ? .single(isUpdating) |> delay(1.0, queue: .mainQueue()) : .single(isUpdating)
        }

        let connecting: Signal<ConnectionStatus, NoError> = account.network.connectionStatus |> mapToSignal { status in
            switch status {
            case .online:
                return .single(status)
            default:
                return .single(status) |> delay(1.0, queue: .mainQueue())
            }
        }

        let previousStatus: Atomic<ConnectionStatus?> = Atomic(value: nil)

        let connectionStatus: Signal<NetworkConnectingStatus?, NoError> = combineLatest(queue: .mainQueue(), connecting, updating) |> deliverOnMainQueue |> map { status, isUpdating -> ConnectionStatus in
            var status = status
            switch status {
            case let .online(proxyAddress):
                if isUpdating {
                    status = .updating(proxyAddress: proxyAddress)
                }
            case let .updating(proxyAddress):
                if isUpdating {
                    status = .updating(proxyAddress: proxyAddress)
                } else {
                    return .connecting(proxyAddress: proxyAddress, proxyHasConnectionIssues: false)
                }
            default:
                break
            }
            return status
        } |> mapToQueue { coreStatus -> Signal<NetworkConnectingStatus?, NoError> in
            let previous = previousStatus.swap(coreStatus)
            if previous != coreStatus {
                switch coreStatus {
                case .online:
                    return .single(nil)
                default:
                    return .single(.core(coreStatus))
                }
            } else {
                return .complete()
            }
        }
        |> deliverOnMainQueue
        |> distinctUntilChanged

        let peerSignal = TelegramEngine(account: account).data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: account.peerId))

        disposable.set(combineLatest(queue: .mainQueue(), connectionStatus, appearanceSignal, window.fullScreen, peerSignal).start(next: { [weak self] status, _, _, peer in
            self?.apply(status: status, peer: peer)
        }))
    }

    private func apply(status: NetworkConnectingStatus?, peer: EnginePeer?) {
        self.peer = peer
        statusPromise.set(.single(status))

        guard managesWindowTitle else {
            return
        }
        if status == nil {
            if let peer {
                window.title = appName + " @ " + peer._asPeer().compactDisplayTitle
            } else {
                window.title = appName
            }
        } else {
            window.title = ""
        }
    }

    deinit {
        cleanup()
    }

    public func cleanup() {
        disposable.dispose()
        statusPromise.set(.single(nil))
    }
}
