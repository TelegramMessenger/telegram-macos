import Cocoa
import Foundation
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import ShortPeerRow
import AvatarUI
import AlertsUI
import TelegramMediaUtils
import LocalAnimations
import LocationUI
import ChatModeTypes
import MapKit
import FoundationUtils
import MessageTextUtils
import AppAnalytics

private final class Arguments {
    let context: (any AccountContextProtocol)
    let toggle: (TimeZoneList.Item)->Void
    let updateSearch:(SearchState)->Void
    init(context: (any AccountContextProtocol), toggle: @escaping(TimeZoneList.Item)->Void, updateSearch:@escaping(SearchState)->Void) {
        self.context = context
        self.toggle = toggle
        self.updateSearch = updateSearch
    }
}

private struct State : Equatable {
    var list: [TimeZoneList.Item] = []
    var selected: TimeZoneList.Item
    var searchState: SearchState = .init(state: .None, request: nil)
}
private func _id_timezone(_ timezone: TimeZoneList.Item) -> InputDataIdentifier {
    return .init("_id_timezone\(timezone.id)")
}

private let _id_search = InputDataIdentifier("_id_search")

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    let index: Int32 = 0
    
   
    
    entries.append(.search(sectionId: sectionId, index: index, value: .none, identifier: _id_search, update: arguments.updateSearch))
  
    let list: [TimeZoneList.Item]
    if !state.searchState.request.isEmpty {
        list = state.list.filter({
            $0.text.lowercased().contains(state.searchState.request.lowercased())
        })
    } else {
        list = state.list
    }
    
    if list.isEmpty {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("empty"), equatable: nil, comparable: nil, item: { initialSize, stableId in
            return SearchEmptyRowItem(initialSize, stableId: stableId)
        }))
    } else {
        for (_, timezone) in list.enumerated() {
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_timezone(timezone), data: .init(name: timezone.title, color: theme.colors.text, type: timezone == state.selected ? .image(theme.icons.poll_selected) : .none, viewType: .legacy, description: timezone.gmtText, descTextColor: theme.colors.grayText, action: {
                arguments.toggle(timezone)
            })))
        }
    }
    
    
    // entries
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

public func BusinessTimezonesController(context: (any AccountContextProtocol), timezones: [TimeZoneList.Item] = [], selected: TimeZoneList.Item, complete: @escaping(TimeZoneList.Item)->Void) -> InputDataModalController {

    let actionsDisposable = DisposableSet()
    
    var close:(()->Void)? = nil

    let initialState = State(list: timezones, selected: selected)
    
    let statePromise = ValuePromise<State>(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    let arguments = Arguments(context: context, toggle: { timezone in
        complete(timezone)
        close?()
    }, updateSearch: { searchState in
        updateState { current in
            var current = current
            current.searchState = searchState
            return current
        }
    })
    

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: strings().businessHoursTimezone, identifier: "business_timezones")
    controller.analyticsScreen = .settingsBusinessTimezone
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    controller.validateData = { _ in
        complete(stateValue.with { $0.selected })
        close?()
        return .none
    }

    
    let modalController = InputDataModalController(controller, size: NSMakeSize(370, 0))
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    controller.getBackgroundColor = {
        theme.colors.background
    }
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    return modalController
    
}


