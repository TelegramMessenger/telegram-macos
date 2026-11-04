import Cocoa

import Foundation
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
import SwiftSignalKit
import Postbox
import TelegramCore



public func iconForSession(_ session: RecentAccountSession) -> (CGImage?, LocalAnimatedSticker?, NSColor?, [String]?) {
    let platform = session.platform.lowercased()
    let device = session.deviceModel.lowercased()
    let systemVersion = session.systemVersion.lowercased()
    if session.isCurrent {
        return (NSImage(named: "Icon_Device_Apple")!.precomposed(), LocalAnimatedSticker.device_mac, NSColor(rgb: 0x0079ff), nil)
    }
    if device.contains("xbox") {
        return (NSImage(named: "Icon_Device_Xbox")!.precomposed(), nil, NSColor(rgb: 0x35c759), nil)
    }
    if device.contains("chrome") && !device.contains("chromebook") {
        return (NSImage(named: "Icon_Device_Chrome")!.precomposed(), LocalAnimatedSticker.device_chrome, NSColor(rgb: 0x35c759), ["Vector 20.Vector 20.Обводка 1", "Ellipse 18.Ellipse 18.Обводка 1"])
    }
    if device.contains("brave") {
        return (NSImage(named: "Icon_Device_Brave")!.precomposed(), nil, NSColor(rgb: 0xff9500), nil)
    }
    if device.contains("vivaldi") {
        return (NSImage(named: "Icon_Device_Vivaldi")!.precomposed(), nil, NSColor(rgb: 0xff3c30), nil)
    }
    if device.contains("safari") {
        return (NSImage(named: "Icon_Device_Safari")!.precomposed(), LocalAnimatedSticker.device_safari, NSColor(rgb: 0x0079ff), ["Com 2.Com 2.Заливка 1"])
    }
    if device.contains("firefox") {
        return (NSImage(named: "Icon_Device_Firefox")!.precomposed(), LocalAnimatedSticker.device_firefox, NSColor(rgb: 0xff9500), nil)
    }
    if device.contains("opera") {
        return (NSImage(named: "Icon_Device_Opera")!.precomposed(), nil, NSColor(rgb: 0xff3c30), nil)
    }
    if platform.contains("android") {
        return (NSImage(named: "Icon_Device_Android")!.precomposed(), LocalAnimatedSticker.device_android, NSColor(rgb: 0x35c759), ["Eye L.Eye L.Заливка 1", "Eye R.Eye R.Заливка 1"])
    }
    if (platform.contains("macos") || systemVersion.contains("macos")) && !device.contains("iphone") && !device.contains("ipad") {
        return (NSImage(named: "Icon_Device_Apple")!.precomposed(), LocalAnimatedSticker.device_mac, NSColor(rgb: 0x0079ff), nil)
    }
    if device.contains("ipad") {
        return (NSImage(named: "Icon_Device_Ipad2")!.precomposed(), LocalAnimatedSticker.device_ipad, NSColor(rgb: 0x0079ff), ["apple.apple.Заливка 1"])
    }
    
    if device.contains("iphone") {
        return (NSImage(named: "Icon_Device_Iphone2")!.precomposed(), LocalAnimatedSticker.device_iphone, NSColor(rgb: 0x0079ff), ["apple.apple.Заливка 1"])
    }

    
    if platform.contains("ios") || platform.contains("macos") || systemVersion.contains("macos") {
        return (NSImage(named: "Icon_Device_Iphone2")!.precomposed(), LocalAnimatedSticker.device_iphone, NSColor(rgb: 0x0079ff), ["apple.apple.Заливка 1"])
    }
    if platform.contains("ubuntu") || systemVersion.contains("ubuntu") {
        return (NSImage(named: "Icon_Device_Ubuntu")!.precomposed(), LocalAnimatedSticker.device_ubuntu, NSColor(rgb: 0x0079ff), ["Ellipse 25.Ellipse 24.Обводка 1", "Ellipse 24.Ellipse 24.Обводка 1", "Union.Union.Заливка 1"])
    }
    if platform.contains("linux") || systemVersion.contains("linux") {
        return (NSImage(named: "Icon_Device_Linux")!.precomposed(), LocalAnimatedSticker.device_linux, NSColor(rgb: 0x8e8e93), nil)
    }
    if platform.contains("windows") || systemVersion.contains("windows") {
        return (NSImage(named: "Icon_Device_Windows")!.precomposed(), LocalAnimatedSticker.device_windows, NSColor(rgb: 0x0079ff), ["Union.Union.Заливка 1"])
    }
    return (NSImage(named: "Icon_Device_Ipad2")!.precomposed(), LocalAnimatedSticker.device_ipad, NSColor(rgb: 0x0079ff), ["apple.apple.Заливка 1"])
}


private final class RecentSessionsControllerArguments {
    public let context: any AccountContextProtocol
    
    public let removeSession: (Int64) -> Void
    public let terminateOthers:() -> Void
    public let toggleTtl:(Int)->Void
    public let preview:(RecentAccountSession, AnyHashable)->Void
    public let rename:()->Void
    public init(context: any AccountContextProtocol, removeSession: @escaping (Int64) -> Void, terminateOthers: @escaping()->Void, toggleTtl:@escaping(Int)->Void, preview:@escaping(RecentAccountSession, AnyHashable)->Void, rename:@escaping()->Void) {
        self.context = context
        self.removeSession = removeSession
        self.terminateOthers = terminateOthers
        self.toggleTtl = toggleTtl
        self.preview = preview
        self.rename = rename
    }
}


public enum RecentSessionsEntryStableId: Hashable {
    case session(Int64)
    case index(Int32)
    case section(Int)
    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .session(hash):
            hasher.combine(hash)
        case let .index(index):
            hasher.combine(index)
        case let .section(section):
            hasher.combine(section)
        }
    }
    
}

private enum RecentSessionsEntry: Comparable, Identifiable {
    case loading(sectionId:Int)
    case currentSessionHeader(sectionId:Int, viewType: GeneralViewType)
    case currentSession(sectionId:Int, RecentAccountSession, deviceModel: String?, viewType: GeneralViewType)
    case terminateOtherSessions(sectionId:Int, viewType: GeneralViewType)
    case currentSessionInfo(sectionId:Int, viewType: GeneralViewType)
    
    case otherSessionsHeader(sectionId:Int, viewType: GeneralViewType)
    
    case incompleteHeader(sectionId: Int, viewType: GeneralViewType)
    case incompleteDesc(sectionId: Int, viewType: GeneralViewType)
    
    case session(sectionId:Int, index: Int32, session: RecentAccountSession, enabled: Bool, editing: Bool, viewType: GeneralViewType)
    
    case revokeOldHeader(sectionId:Int, viewType: GeneralViewType)
    case revokeOld(sectionId:Int, Int32, viewType: GeneralViewType)

    case section(sectionId:Int)

    public var stableId: RecentSessionsEntryStableId {
        switch self {
        case .loading:
            return .index(0)
        case .currentSessionHeader:
            return .index(1)
        case .currentSession:
            return .index(2)
        case .terminateOtherSessions:
            return .index(3)
        case .currentSessionInfo:
            return .index(4)
        case .incompleteHeader:
            return .index(5)
        case .incompleteDesc:
            return .index(6)
        case .otherSessionsHeader:
            return .index(7)
        case .revokeOldHeader:
            return .index(8)
        case .revokeOld:
            return .index(9)
        case let .session(_, _, session, _, _, _):
            return .session(session.hash)
        case let .section(sectionId):
            return .section(sectionId)
        }
    }
    
    public var stableIndex: Int {
        switch self {
        case .loading:
            return 0
        case .currentSessionHeader:
            return 1
        case .currentSession:
            return 2
        case .terminateOtherSessions:
            return 3
        case .currentSessionInfo:
            return 4
        case .incompleteHeader:
            return 5
        case .incompleteDesc:
            return 6
        case .otherSessionsHeader:
            return 7
        case .revokeOldHeader:
            return 8
        case .revokeOld:
            return 9
        case .session:
            fatalError()
        case let .section(sectionId):
            return (sectionId + 1) * 1000 - sectionId
        }
    }
    
    public var sectionId: Int {
        switch self {
        case let .loading(sectionId):
            return sectionId
        case let .currentSessionHeader(sectionId, _):
            return sectionId
        case let .currentSession(sectionId, _, _, _):
            return sectionId
        case let .terminateOtherSessions(sectionId, _):
            return sectionId
        case let .currentSessionInfo(sectionId, _):
            return sectionId
        case let .incompleteHeader(sectionId, _):
            return sectionId
        case let .incompleteDesc(sectionId, _):
            return sectionId
        case let .otherSessionsHeader(sectionId, _):
            return sectionId
        case let .revokeOldHeader(sectionId, _):
            return sectionId
        case let .revokeOld(sectionId, _, _):
            return sectionId
        case let .session(sectionId, _, _, _, _, _):
            return sectionId
        case let .section(sectionId):
            return sectionId
        }
    }
    
    public var sortIndex:Int {
        switch self {
        case let .loading(sectionId):
            return (sectionId * 1000) + stableIndex
        case let .currentSessionHeader(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .currentSession(sectionId, _, _, _):
            return (sectionId * 1000) + stableIndex
        case let .terminateOtherSessions(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .currentSessionInfo(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .incompleteHeader(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .incompleteDesc(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .otherSessionsHeader(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .revokeOldHeader(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .revokeOld(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .session(sectionId, index, _, _, _, _):
            return (sectionId * 1000) + Int(index) + 100
        case let .section(sectionId):
            return (sectionId * 1000) + stableIndex
        }
    }
    
    
    public static func <(lhs: RecentSessionsEntry, rhs: RecentSessionsEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }
    
    public func item(_ arguments: RecentSessionsControllerArguments, initialSize: NSSize) -> TableRowItem {
        switch self {
        case let .currentSessionHeader(_, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: strings().sessionsCurrentSessionHeader, viewType: viewType, rightItem: InputDataGeneralTextRightData(isLoading: false, text: .initialize(string: "Rename", color: theme.colors.accent, font: .medium(.small)), action: arguments.rename)) //TODOLANG
        case let .currentSession(_, session, deviceModel, viewType):
            return RecentSessionRowItem(initialSize, session: session, deviceModel: deviceModel, stableId: stableId, viewType: viewType, icon: iconForSession(session), handler: {
                arguments.preview(session, stableId)
            })
        case let .terminateOtherSessions(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().sessionsTerminateOthers, nameStyle: redActionButton, type: .none, viewType: viewType, action: {
                arguments.terminateOthers()
            })
        case let .currentSessionInfo(_, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: strings().sessionsTerminateDescription, viewType: viewType)
        case let .incompleteHeader(_, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: strings().recentSessionsIncompleteAttemptHeader, viewType: viewType)
        case let .incompleteDesc(_, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: strings().recentSessionsIncompleteAttemptDesc, viewType: viewType)
        case let .otherSessionsHeader(_, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: strings().sessionsActiveSessionsHeader, viewType: viewType)
        case let .session(_, _, session, _, _, viewType):
            return RecentSessionRowItem(initialSize, session: session, stableId: stableId, viewType: viewType, icon: iconForSession(session), handler: {
                arguments.preview(session, stableId)
            })
        case let .revokeOldHeader(_, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: strings().recentSessionsTTLHeader, viewType: viewType)
        case let .revokeOld(_, ttl, viewType):
            
            var items:[ContextMenuItem] = []
            items.append(.init(strings().timerWeeksOther(1), handler: {
                arguments.toggleTtl(7)
            }))
            
            items.append(.init(strings().timerMonthsOther(1), handler: {
                arguments.toggleTtl(30)
            }))
            items.append(.init(strings().timerMonthsOther(3), handler: {
                arguments.toggleTtl(90)
            }))
            items.append(.init(strings().timerMonthsOther(6), handler: {
                arguments.toggleTtl(180)
            }))
            items.append(.init(strings().timerYearsOther(1), handler: {
                arguments.toggleTtl(365)
            }))
            
            let ttlText: String
            if ttl >= 365 {
                ttlText = strings().timerYearsOther(Int(ttl / 365))
            } else {
                ttlText = autoremoveLocalized(Int(ttl * 24 * 60 * 60))
            }
            
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().recentSessionsTTLText, type: .contextSelector(ttlText, items), viewType: viewType)
        case .section(sectionId: _):
            return GeneralRowItem(initialSize, height: 20, stableId: stableId, viewType: .separator)
        case .loading:
            return SearchEmptyRowItem(initialSize, stableId: stableId, isLoading: true)
        }
    }
}

private struct RecentSessionsControllerState: Equatable {
    public let editing: Bool
    public let sessionIdWithRevealedOptions: Int64?
    public let removingSessionId: Int64?
    
    public init() {
        self.editing = false
        self.sessionIdWithRevealedOptions = nil
        self.removingSessionId = nil
    }
    
    public init(editing: Bool, sessionIdWithRevealedOptions: Int64?, removingSessionId: Int64?) {
        self.editing = editing
        self.sessionIdWithRevealedOptions = sessionIdWithRevealedOptions
        self.removingSessionId = removingSessionId
    }
    
    public static func ==(lhs: RecentSessionsControllerState, rhs: RecentSessionsControllerState) -> Bool {
        if lhs.editing != rhs.editing {
            return false
        }
        if lhs.sessionIdWithRevealedOptions != rhs.sessionIdWithRevealedOptions {
            return false
        }
        if lhs.removingSessionId != rhs.removingSessionId {
            return false
        }
        
        return true
    }
    
    public func withUpdatedEditing(_ editing: Bool) -> RecentSessionsControllerState {
        return RecentSessionsControllerState(editing: editing, sessionIdWithRevealedOptions: self.sessionIdWithRevealedOptions, removingSessionId: self.removingSessionId)
    }
    
    public func withUpdatedSessionIdWithRevealedOptions(_ sessionIdWithRevealedOptions: Int64?) -> RecentSessionsControllerState {
        return RecentSessionsControllerState(editing: self.editing, sessionIdWithRevealedOptions: sessionIdWithRevealedOptions, removingSessionId: self.removingSessionId)
    }
    
    public func withUpdatedRemovingSessionId(_ removingSessionId: Int64?) -> RecentSessionsControllerState {
        return RecentSessionsControllerState(editing: self.editing, sessionIdWithRevealedOptions: self.sessionIdWithRevealedOptions, removingSessionId: removingSessionId)
    }
}

private func recentSessionsControllerEntries(state: RecentSessionsControllerState, sessions: ActiveSessionsContextState, deviceModel: String?) -> [RecentSessionsEntry] {
    var entries: [RecentSessionsEntry] = []
    
    
    var sectionId:Int = 1
    entries.append(.section(sectionId: sectionId))
    sectionId += 1
    
    var existingSessionIds = Set<Int64>()
    entries.append(.currentSessionHeader(sectionId: sectionId, viewType: .textTopItem))
    if let index = sessions.sessions.firstIndex(where: { $0.hash == 0 }) {
        existingSessionIds.insert(sessions.sessions[index].hash)
        entries.append(.currentSession(sectionId: sectionId, sessions.sessions[index], deviceModel: deviceModel, viewType: .firstItem))
    }
    entries.append(.terminateOtherSessions(sectionId: sectionId, viewType: existingSessionIds.isEmpty ? .singleItem : .lastItem))
    entries.append(.currentSessionInfo(sectionId: sectionId, viewType: .textBottomItem))
    
    if sessions.sessions.count > 1 {
        entries.append(.section(sectionId: sectionId))
        sectionId += 1
        
        let filteredSessions: [RecentAccountSession] = sessions.sessions.sorted(by: { lhs, rhs in
            return lhs.activityDate > rhs.activityDate
        })
        
        let nonApplied = filteredSessions.filter {$0.flags.contains(.passwordPending)}
        let applied = filteredSessions.filter {!$0.flags.contains(.passwordPending)}
        
        var index: Int32 = 0
        
        if !nonApplied.isEmpty {
            entries.append(.incompleteHeader(sectionId: sectionId, viewType: .textTopItem))
            
            let nonApplied = nonApplied.filter({
                !existingSessionIds.contains($0.hash)
            })
            for session in nonApplied {
                existingSessionIds.insert(session.hash)
                let enabled = state.removingSessionId != session.hash
                entries.append(.session(sectionId: sectionId, index: index, session: session, enabled: enabled, editing: state.editing, viewType: bestGeneralViewType(nonApplied, for: session)))
                index += 1
            }
            entries.append(.incompleteDesc(sectionId: sectionId, viewType: .textBottomItem))
            
            entries.append(.section(sectionId: sectionId))
            sectionId += 1
        }
        
        entries.append(.otherSessionsHeader(sectionId: sectionId, viewType: .textTopItem))
        let newApplied = applied.filter({
            !existingSessionIds.contains($0.hash)
        })
        for session in newApplied {
            existingSessionIds.insert(session.hash)
            let enabled = state.removingSessionId != session.hash
            entries.append(.session(sectionId: sectionId, index: index, session: session, enabled: enabled, editing: state.editing, viewType: bestGeneralViewType(newApplied, for: session)))
            index += 1
        }
        entries.append(.section(sectionId: sectionId))
        sectionId += 1
        
        entries.append(.revokeOldHeader(sectionId: sectionId, viewType: .textTopItem))
        entries.append(.revokeOld(sectionId: sectionId, sessions.ttlDays, viewType: .singleItem))
        
        entries.append(.section(sectionId: sectionId))
        sectionId += 1
    }
    
    return entries
}


private func prepareSessions(left:[AppearanceWrapperEntry<RecentSessionsEntry>], right: [AppearanceWrapperEntry<RecentSessionsEntry>], arguments: RecentSessionsControllerArguments, initialSize: NSSize) -> TableUpdateTransition {
    let (removed, inserted, updated) = proccessEntriesWithoutReverse(left, right: right) { entry -> TableRowItem in
        return entry.entry.item(arguments, initialSize: initialSize)
    }
    
    return TableUpdateTransition(deleted: removed, inserted: inserted, updated: updated, animated: true)
}

public enum RecentSessionsEntryTag {
    case autoTerminate

    public var stableId: RecentSessionsEntryStableId {
        switch self {
        case .autoTerminate:
            return .index(9)
        }
    }

    public var namespace: Int32 { return 0 }
    public var id: ItemCollectionId.Id { return 0 }
}

open class RecentSessionsController<Context: AccountContextProtocol>: TableViewController<Context> {

    open override var defaultBarTitle: String {
        return strings().telegramRecentSessionsController
    }

    private var focusOnItemTag: RecentSessionsEntryTag?

    public init(_ context: Context, focusOnItemTag: RecentSessionsEntryTag? = nil) {
        self.focusOnItemTag = focusOnItemTag
        super.init(context)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        
        
        
        let statePromise = ValuePromise(RecentSessionsControllerState(), ignoreRepeated: true)
        let stateValue = Atomic(value: RecentSessionsControllerState())
        let updateState: ((RecentSessionsControllerState) -> RecentSessionsControllerState) -> Void = { f in
            statePromise.set(stateValue.modify { f($0) })
        }
        let context = self.context
        let initialSize = self.atomicSize
        let actionsDisposable = DisposableSet()
        
        let removeSessionDisposable = MetaDisposable()
        actionsDisposable.add(removeSessionDisposable)
        
        let sessionsPromise = Promise<ActiveSessionsContextState>()
        
        let arguments = RecentSessionsControllerArguments(context: context, removeSession: { sessionId in
            updateState {
                return $0.withUpdatedRemovingSessionId(sessionId)
            }
            
            removeSessionDisposable.set((context.activeSessionsContext.remove(hash: sessionId) |> deliverOnMainQueue).start(error: { error in
                updateState {
                    return $0.withUpdatedRemovingSessionId(nil)
                }
                let text: String
                switch error {
                case .freshReset:
                    text = strings().recentSessionsErrorFreshReset
                case .generic:
                    text = strings().unknownError
                }
                alert(for: context.window, info: text)
            }, completed: {
                updateState {
                    return $0.withUpdatedRemovingSessionId(nil)
                }
            }))
        }, terminateOthers: {
            verifyAlert_button(for: context.window, information: strings().recentSessionsConfirmTerminateOthers, successHandler: { _ in
                _ = showModalProgress(signal: context.activeSessionsContext.removeOther(), for: context.window).start(error: { error in
                    let text: String
                    switch error {
                    case .freshReset:
                        text = strings().recentSessionsErrorFreshReset
                    case .generic:
                        text = strings().unknownError
                    }
                    alert(for: context.window, info: text)
                })
            })
        }, toggleTtl: { ttl in
            _ = showModalProgress(signal: context.activeSessionsContext.updateAuthorizationTTL(days: Int32(ttl)), for: context.window).start(error: { _ in
                context.activeSessionsContext.loadMore()
                alert(for: context.window, info: strings().unknownError)
            })
        }, preview: { [weak self] session, stableId in
            showModal(with: SessionModalController(context: context, session: session), for: context.window, morphSource: {
                (self?.genericView.item(stableId: stableId)?.view as? GeneralContainableRowView)?.containerView
            })
        }, rename: { [weak self] in
            let source = (self?.genericView.item(stableId: RecentSessionsEntryStableId.index(2))?.view as? RecentSessionRowView)?.titleView
            showModal(with: RenameDeviceController(context: context), for: context.window, morphSource: source.map { source in { [weak source] in source } })
        })
        
        let sessionsSignal: Signal<ActiveSessionsContextState, NoError> = context.activeSessionsContext.state
        
        sessionsPromise.set(sessionsSignal)
        
        let previousSessions: Atomic<[AppearanceWrapperEntry<RecentSessionsEntry>]> = Atomic(value: [])
        
        let signal = combineLatest(statePromise.get(), sessionsPromise.get(), renamedDeviceModel.get(), appearanceSignal)
            |> deliverOnMainQueue
            |> map { state, sessions, deviceModel, appearance -> TableUpdateTransition in
                let entries = recentSessionsControllerEntries(state: state, sessions: sessions, deviceModel: deviceModel).map {AppearanceWrapperEntry(entry: $0, appearance: appearance)}
                return prepareSessions(left: previousSessions.swap(entries), right: entries, arguments: arguments, initialSize: initialSize.modify {$0})
            } |> afterDisposed {
                actionsDisposable.dispose()
        }
        
        genericView.merge(with: signal |> afterNext { [weak self] _ in
            if let focusOnItemTag = self?.focusOnItemTag {
                self?.genericView.scroll(to: .center(id: focusOnItemTag.stableId, innerId: nil, animated: true, focus: .init(focus: true), inset: 0), inset: NSEdgeInsets())
                self?.focusOnItemTag = nil
            }
        })

        genericView.setScrollHandler { position in
            switch position.direction {
            case .bottom:
                context.activeSessionsContext.loadMore()
            default:
                break
            }
        }

        readyOnce()
    }

}


