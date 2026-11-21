import Cocoa
import TelegramCore

import Postbox
import SwiftSignalKit
import TGUIKit
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import GeneralRows
import InputDataUI
import AlertsUI
import AvatarUI
import LocalAnimations
import ColorPalette
import DateUtils
import TelegramIconsTheme


private final class WebSessionArguments {
    public let context: any AccountContextProtocol
    public let logoutSession:(WebAuthorization)->Void
    public let logoutAll:()->Void
    public init(context: any AccountContextProtocol, logoutSession:@escaping(WebAuthorization)->Void, logoutAll:@escaping()->Void) {
        self.context = context
        self.logoutAll = logoutAll
        self.logoutSession = logoutSession
    }
}

private enum WebSessionEntryStableId : Hashable {
   
    case logoutId
    case descriptionId(Int32)
    case sessionId(Int64)
    case loadingId
    case sectionId(Int32)
    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .sectionId(id):
            hasher.combine(Int(id))
        case .logoutId:
            hasher.combine(0)
        case .loadingId:
            hasher.combine(1)
        case let .sessionId(id):
            hasher.combine(Int(id))
        case let .descriptionId(id):
            hasher.combine(Int(id))
        }
    }
}

private enum WebSessionEntry : TableItemListNodeEntry {
    case logout(sectionId: Int32, index: Int32, viewType: GeneralViewType)
    case description(sectionId: Int32, index: Int32, text: String, viewType: GeneralViewType)
    case session(sectionId: Int32, index: Int32, authorization: WebAuthorization, peer: Peer, viewType: GeneralViewType)
    case sectionId(Int32)
    case loading
    
    public var stableId:WebSessionEntryStableId {
        switch self {
        case let .sectionId(id):
            return .sectionId(id)
        case .logout:
            return .logoutId
        case .loading:
            return .loadingId
        case .description(_, let index, _, _):
            return .descriptionId(index)
        case .session(_, _, let authorization, _, _):
            return .sessionId(authorization.hash)
        }
    }
    
    public var index: Int32 {
        switch self {
        case let .logout(sectionId, index, _):
            return (sectionId * 1000) + index
        case .loading:
            return 0
        case let .description(sectionId, index, _, _):
            return (sectionId * 1000) + index
        case let .session(sectionId, index, _, _, _):
            return (sectionId * 1000) + index
        case let .sectionId(sectionId):
            return (sectionId * 1000) + sectionId
        }
    }
    
    
    public func item(_ arguments: WebSessionArguments, initialSize: NSSize) -> TableRowItem {
        switch self {
        case .sectionId:
            return GeneralRowItem(initialSize, height: 20, stableId: stableId, viewType: .separator)
        case let .description(_, _, text, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: text, viewType: viewType)
        case let .logout(_, _, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().webAuthorizationsLogoutAll, nameStyle: ControlStyle(font: .normal(.title), foregroundColor: theme.colors.redUI), type: .none, viewType: viewType, action: {
                arguments.logoutAll()
            })
        case .loading:
            return SearchEmptyRowItem(initialSize, stableId: stableId, isLoading: true)
        case let .session(_, _, authorization, peer, viewType):
            return WebAuthorizationRowItem(initialSize, stableId: stableId, account: arguments.context.account, authorization: authorization, peer: peer, viewType: viewType, logout: {
                arguments.logoutSession(authorization)
            })
        }
    }
}

private func ==(lhs: WebSessionEntry, rhs: WebSessionEntry) -> Bool {
    switch lhs {
    case .loading:
        if case .loading = rhs {
            return true
        } else {
            return false
        }
    case let .description(sectionId, index, text, viewType):
        if case .description(sectionId, index, text, viewType) = rhs {
            return true
        } else {
            return false
        }
    case let .logout(sectionId, index, viewType):
        if case .logout(sectionId, index, viewType) = rhs {
            return true
        } else {
            return false
        }
    case let .sectionId(sectionId):
        if case .sectionId(sectionId) = rhs {
            return true
        } else {
            return false
        }
    case let .session(lhsSectionId, lhsIndex, lhsAuthorization, lhsPeer, lhsViewType):
        if case let .session(rhsSectionId, rhsIndex, rhsAuthorization, rhsPeer, rhsViewType) = rhs {
            return lhsSectionId == rhsSectionId && lhsIndex == rhsIndex && lhsAuthorization == rhsAuthorization && lhsPeer.isEqual(rhsPeer) && lhsViewType == rhsViewType
        } else {
            return false
        }
    }
}
private func <(lhs: WebSessionEntry, rhs: WebSessionEntry) -> Bool {
    return lhs.index < rhs.index
}


private struct WebSessionsControllerState: Equatable {
    public let removingSessionId: Int64?
    public let removedSessions: Set<Int64>
    public init() {
        self.removingSessionId = nil
        self.removedSessions = []
    }
    
    public init(removingSessionId: Int64?, removedSessions: Set<Int64>) {
        self.removingSessionId = removingSessionId
        self.removedSessions = removedSessions
    }
    
    public static func ==(lhs: WebSessionsControllerState, rhs: WebSessionsControllerState) -> Bool {
        if lhs.removingSessionId != rhs.removingSessionId {
            return false
        }
        if lhs.removedSessions != rhs.removedSessions {
            return false
        }
        
        return true
    }
    
    public func withUpdatedRemovedSessionId(_ sessionId: Int64) -> WebSessionsControllerState {
        var sessions = self.removedSessions
        if sessions.contains(sessionId) {
            sessions.remove(sessionId)
        } else {
            sessions.insert(sessionId)
        }
        return WebSessionsControllerState(removingSessionId: removingSessionId, removedSessions: sessions)
    }
    
    public func withUpdatedRemovingSessionId(_ removingSessionId: Int64?) -> WebSessionsControllerState {
        return WebSessionsControllerState(removingSessionId: removingSessionId, removedSessions: self.removedSessions)
    }
    
    public func newState(from value: ([WebAuthorization], [PeerId : Peer])?) -> ([WebAuthorization], [PeerId : Peer])? {
        if let value = value {
            return (value.0.filter({!removedSessions.contains($0.hash)}), value.1)
        }
        return nil
    }
    
}

private func prepareSessions(left:[AppearanceWrapperEntry<WebSessionEntry>], right: [AppearanceWrapperEntry<WebSessionEntry>], arguments: WebSessionArguments, initialSize: NSSize) -> TableUpdateTransition {
    let (removed, inserted, updated) = proccessEntriesWithoutReverse(left, right: right) { entry -> TableRowItem in
        return entry.entry.item(arguments, initialSize: initialSize).settingsRow()
    }
    
    return TableUpdateTransition(deleted: removed, inserted: inserted, updated: updated, animated: true)
}

private func webAuthorizationEntries(webSessions: WebSessionsContextState, state: WebSessionsControllerState) -> [WebSessionEntry] {
    var entries: [WebSessionEntry] = []
    
    
    
    var sectionId:Int32 = 0
    entries.append(.sectionId(sectionId))
    sectionId += 1
    
    var index: Int32 = 1
    
    
    entries.append(.logout(sectionId: sectionId, index: index, viewType: .singleItem))
    index += 1
    
    entries.append(.description(sectionId: sectionId, index: index, text: strings().webAuthorizationsLogoutAllDescription, viewType: .textBottomItem))
    index += 1
    
    entries.append(.sectionId(sectionId))
    sectionId += 1
    
    
    let authorizations = webSessions.sessions.filter {!state.removedSessions.contains($0.hash)}
    
    if authorizations.count > 0 {
        entries.append(.description(sectionId: sectionId, index: index, text: strings().webAuthorizationsLoggedInDescrpiption, viewType: .textTopItem))
        index += 1
    }
    
    for auth in authorizations {
        if let peer = webSessions.peers[auth.botId] {
            entries.append(.session(sectionId: sectionId, index: index, authorization: auth, peer: peer._asPeer(), viewType: bestGeneralViewType(authorizations, for: auth)))
            index += 1
        }
    }
    
    entries.append(.sectionId(sectionId))
    sectionId += 1
    
    
    return entries
}

open class WebSessionsController<Context: AccountContextProtocol>: TableViewController<Context> {

    open override var defaultBarTitle: String {
        return strings().telegramWebSessionsController
    }

    private let disposable = MetaDisposable()
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        let actionsDisposable = MetaDisposable()
        
        let state = Atomic(value: WebSessionsControllerState())
        
        let context = self.context
        
        let stateValue = ValuePromise(WebSessionsControllerState(), ignoreRepeated: true)
        
        let updateState:((WebSessionsControllerState)->WebSessionsControllerState)->Void = { f -> Void in
            stateValue.set(state.modify(f))
        }
                
        let arguments = WebSessionArguments(context: context, logoutSession: { session in
            verifyAlert_button(for: context.window, information: strings().webAuthorizationsConfirmRevoke, successHandler: { result in
                updateState { state in
                    return state.withUpdatedRemovingSessionId(session.hash)
                }
                
                _ = showModalProgress(signal: context.webSessions.remove(hash: session.hash), for: context.window).start(next: { removed in
                    updateState { state in
                        if removed {
                            return state.withUpdatedRemovedSessionId(session.hash).withUpdatedRemovingSessionId(nil)
                        } else {
                            return state.withUpdatedRemovingSessionId(nil)
                        }
                    }
                    if !removed {
                        alert(for: context.window, info: strings().unknownError)
                    }
                })
            })
            
        }, logoutAll: {
            verifyAlert_button(for: context.window, information: strings().webAuthorizationsConfirmRevokeAll, successHandler: { result in
                _ = showModalProgress(signal: context.webSessions.removeAll(), for: context.window).start(next: { removed in
                    if !removed {
                        alert(for: context.window, info: strings().unknownError)
                    }
                })
            })
           
        })
        let initialSize = self.atomicSize
        
        let previous: Atomic<[AppearanceWrapperEntry<WebSessionEntry>]> = Atomic(value: [])
        
        let signal = combineLatest(context.webSessions.state, appearanceSignal, stateValue.get()) |> map { webSessions, appearance, state -> (TableUpdateTransition, WebSessionsContextState) in
            let entries = webAuthorizationEntries(webSessions: webSessions, state: state).map {
                AppearanceWrapperEntry(entry: $0, appearance: appearance)
            }
            
            return (prepareSessions(left: previous.swap(entries), right: entries, arguments: arguments, initialSize: initialSize.modify{$0}), webSessions)
            
        } |> deliverOnMainQueue |> afterDisposed {
            actionsDisposable.dispose()
        }
        
        disposable.set(signal.start(next: { [weak self] transition, state in
            self?.genericView.merge(with: transition)
            self?.readyOnce()
                    
            if !state.isLoadingMore, state.sessions.isEmpty, let strongSelf = self, let navigation = strongSelf.navigationController, navigation.controller === strongSelf {
                navigation.back()
            }
        }))
        
    }
    
    deinit {
        disposable.dispose()
    }
    
}
