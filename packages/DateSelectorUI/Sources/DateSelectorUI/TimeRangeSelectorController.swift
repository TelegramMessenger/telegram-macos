import Foundation
import ColorPalette
import DateUtils
import CalendarUtils
import InputDataUI
import GeneralRows
import TelegramUtils
import TelegramContext
import TelegramTheme
import Localization
import Cocoa
import TGUIKit
import SwiftSignalKit
import AppAnalytics

private final class Arguments {
    public let context: any AccountContextProtocol
    public let updateFrom:(TimePickerOption)->Void
    public let updateTo:(TimePickerOption)->Void
    public init(context: any AccountContextProtocol, updateFrom:@escaping(TimePickerOption)->Void, updateTo:@escaping(TimePickerOption)->Void) {
        self.context = context
        self.updateFrom = updateFrom
        self.updateTo = updateTo
    }
}

private struct State : Equatable {
    public var from: TimePickerOption
    public var to: TimePickerOption
}

private final class TimeRangeSelectorItem : GeneralRowItem {
    public let from: TimePickerOption
    public let to: TimePickerOption
    public let fromString: String
    public let toString: String
    public let updateFrom:(TimePickerOption)->Void
    public let updateTo:(TimePickerOption)->Void
    public init(_ initialSize: NSSize, stableId: AnyHashable, viewType: GeneralViewType, from: TimePickerOption, to: TimePickerOption, fromString: String, toString: String, updateFrom:@escaping(TimePickerOption)->Void, updateTo:@escaping(TimePickerOption)->Void) {
        self.from = from
        self.to = to
        self.fromString = fromString
        self.toString = toString
        self.updateFrom = updateFrom
        self.updateTo = updateTo
        super.init(initialSize, height: 55, stableId: stableId)
    }
    
    public override func viewClass() -> AnyClass {
        return TimeRangeSelectorView.self
    }

    public override var accessibilityLabel: String? {
        return "\(fromString), \(toString)"
    }

    public override var accessibilityValue: String? {
        return String(format: "%02d:%02d – %02d:%02d", Int(from.hours), Int(from.minutes), Int(to.hours), Int(to.minutes))
    }
}

private final class TimeRangeSelectorView : GeneralContainableRowView {
    public let fromView = TimePicker(selected: TimePickerOption(hours: 0, minutes: 0, seconds: nil))
    public let toView = TimePicker(selected: TimePickerOption(hours: 0, minutes: 0, seconds: nil))
    public let fromLabel = TextViewLabel()
    public let toLabel = TextViewLabel()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(fromView)
        addSubview(toView)
        
        addSubview(fromLabel)
        addSubview(toLabel)
    }
    
    public override func layout() {
        super.layout()
        self.fromView.setFrameSize(NSMakeSize(115, 30))
        self.toView.setFrameSize(NSMakeSize(115, 30))


        self.fromView.setFrameOrigin(NSMakePoint(0, containerView.frame.height - fromView.frame.height))
        self.toView.setFrameOrigin(NSMakePoint(self.fromView.frame.maxX + 40, containerView.frame.height - toView.frame.height))
        
        fromLabel.setFrameOrigin(NSMakePoint(floorToScreenPixels((fromView.frame.width - fromLabel.frame.width) / 2), 0))
        toLabel.setFrameOrigin(NSMakePoint(self.toView.frame.minX + floorToScreenPixels((toView.frame.width - toLabel.frame.width) / 2), 0))

    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? TimeRangeSelectorItem else {
            return
        }
        
        self.fromView.update = { [weak item] value in
            item?.updateFrom(value)
            return true
        }
        self.toView.update = { [weak item] value in
            item?.updateTo(value)
            return true
        }
        
        self.fromView.selected = item.from
        self.toView.selected = item.to
        
        fromLabel.attributedString = .initialize(string: item.fromString, color: theme.colors.text, font: .medium(.text))
        toLabel.attributedString = .initialize(string: item.toString, color: theme.colors.text, font: .medium(.text))
        
        fromLabel.sizeToFit()
        toLabel.sizeToFit()

    }
    
    public override var firstResponder: NSResponder? {
        return fromView.firstResponder
    }
    
    public override func nextResponder() -> NSResponder? {
        if window?.firstResponder == fromView.firstResponder {
            return toView.firstResponder
        } else {
            return firstResponder
        }
    }
    
    public override func hasFirstResponder() -> Bool {
        return true
    }
}


private func entries(_ state: State, arguments: Arguments, fromString: String, toString: String) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    let index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
  
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("date"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return TimeRangeSelectorItem(initialSize, stableId: stableId, viewType: .singleItem, from: state.from, to: state.to, fromString: fromString, toString: toString, updateFrom: arguments.updateFrom, updateTo: arguments.updateTo)
    }))
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

public func TimeRangeSelectorController(context: any AccountContextProtocol, from: TimePickerOption, to: TimePickerOption, title: String, ok: String, fromString: String, toString: String, endIsResponder: Bool = false, updatedValue:@escaping(TimePickerOption, TimePickerOption)->Void) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    let initialState = State(from: from, to: to)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    var close:(()->Void)? = nil

    let arguments = Arguments(context: context, updateFrom: { value in
        updateState { current in
            var current = current
            current.from = value
            return current
        }
    }, updateTo: { value in
        updateState { current in
            var current = current
            current.to = value
            return current
        }
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments, fromString: fromString, toString: toString))
    }
    
    let controller = InputDataController(dataSignal: signal, title: title)
    controller.analyticsScreen = .appTimeRangePicker
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    let modalInteractions = ModalInteractions(acceptTitle: ok, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true)
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(310, 300))
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    controller.didAppear = { controller in
        if endIsResponder {
            controller.jumpNext()
        }
    }
    
    controller.validateData = { _ in
        let value = stateValue.with { $0 }
        updatedValue(value.from, value.to)
        
        return .success(.custom({
            close?()
        }))
        
    }
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }

    
    return modalController
}


/*

 */


