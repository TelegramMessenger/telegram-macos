import Cocoa
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
import AppAnalytics


public struct ComplicatedReport : Equatable {
    public enum Subject : Equatable {
        case list([Report])
        case comment(optional: Bool, id: Data)
    }
    public struct Report : Equatable {
        public var string: String
        public var id: Data
        public var inner: ComplicatedReport?
        public init(string: String, id: Data, inner: ComplicatedReport? = nil) {
            self.string = string
            self.id = id
            self.inner = inner
        }
    }
    public var subject: Subject
    public var title: String
    public init(subject: Subject, title: String) {
        self.subject = subject
        self.title = title
    }
}

public func showComplicatedReport(context: (any AccountContextProtocol), title: String, info: String?, header: String, data: ComplicatedReport, report: @escaping(ComplicatedReport.Report)->Signal<ComplicatedReport?, NoError>, window: Window? = nil) {
    showModal(with: ReportController(context: context, title: title, header: header, info: info, data: data, reportCallback: report), for: window ?? context.window)
}




private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let select:(ComplicatedReport.Report)->Void
    public init(context: (any AccountContextProtocol), select:@escaping(ComplicatedReport.Report)->Void) {
        self.context = context
        self.select = select
    }
}

private struct State : Equatable {
    public var data: ComplicatedReport
    public var info: String?
    public var title: String
}

private func _id_report(_ report: ComplicatedReport.Report) -> InputDataIdentifier {
    return .init("_id_report_\(report.id)_\(report.string.hashValue)")
}


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
    
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(state.title.uppercased()), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1
    
    var list: [ComplicatedReport.Report] = []
    
    switch state.data.subject {
    case let .list(_list):
        list = _list
    default:
        break
    }
    for (i, report) in list.enumerated() {
        let viewType: GeneralViewType = bestGeneralViewType(list, for: i)
        let type: GeneralInteractedType = report.inner != nil ? .next : .next
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_report(report), data: .init(name: report.string, color: theme.colors.text, type: type, viewType: viewType, action: {
            arguments.select(report)
        })))
    }
    
    if let info = state.info {
        entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(info, linkHandler: { link in
            LinkHooks.shared.openExternalLink(link, false)
        }), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1
    }
    
    // entries
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

private func ReportController(context: (any AccountContextProtocol), title: String, header: String, info: String?, data: ComplicatedReport, reportCallback: @escaping(ComplicatedReport.Report)->Signal<ComplicatedReport?, NoError>) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    let initialState = State(data: data, info: info, title: title)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let _: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    var close:(()->Void)? = nil
    
    var getModalController:(()->InputDataModalController?)? = nil
    
    var invokeNext:(ComplicatedReport.Report)->Void = { _ in }
    
    let invoke:(ComplicatedReport.Report)->Void = { report in
        actionsDisposable.add((reportCallback(report) |> deliverOnMainQueue).startStandalone(next: { value in
            if let complicated = value {
                if let controller = getModalController?() {
                    switch complicated.subject {
                    case .list:
                        controller.push(ReportController(context: context, title: complicated.title, info: info, data: complicated, modalController: controller, invokeNext: invokeNext), animated: true)
                    case let .comment(optional, id):
                        controller.push(ReportDetailsController(context: context, optional: optional, title: complicated.title, updated: { text in
                            _ = reportCallback(.init(string: text, id: id)).start()
                            close?()
                        }, modalController: controller), animated: true)
                    }
                }
            } else {
                close?()
            }
        }))
    }
    
    invokeNext = { report in
        invoke(report)
    }

    let arguments = Arguments(context: context, select: { report in
        invoke(report)
    })
    
    let signal = statePromise.get() |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: header, hasDone: false)
    controller.analyticsScreen = .reportReason
    
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    let modalController = InputDataModalController(controller, modalInteractions: nil)
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    getModalController = { [weak modalController] in
        return modalController
    }
    
    close = { [weak modalController] in
        modalController?.close()
    }
    
    
    return modalController
    
}



private func ReportController(context: (any AccountContextProtocol), title: String, info: String?, data: ComplicatedReport, modalController: InputDataModalController, invokeNext:@escaping(ComplicatedReport.Report)->Void) -> InputDataController {

    let actionsDisposable = DisposableSet()

    let initialState = State(data: data, info: info, title: title)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let _: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    let arguments = Arguments(context: context, select: { report in
        invokeNext(report)
    })
    
    let signal = statePromise.get() |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: title, hasDone: false)
    controller.analyticsScreen = .reportOption
    controller._frameRect = modalController.frame.size.bounds
    controller.bar = .init(height: 0)
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.chatNavigationBack, handler: { [weak modalController] in
        modalController?.pop(animated: true)
    }, isCloseButton: false)

    return controller
    
}





private final class ReportDetailsArguments {
    public let context: (any AccountContextProtocol)
    public let validate:()->Void
    public init(context: (any AccountContextProtocol), validate:@escaping()->Void) {
        self.context = context
        self.validate = validate
    }
}

private struct ReportDetailsState : Equatable {
    public var text: String
}

private let _id_input = InputDataIdentifier("_id_input")

private func entries(_ state: ReportDetailsState, arguments: ReportDetailsArguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
  
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("sticker"), equatable: nil, comparable: nil, item: { initialSize, stableId in
        return ReportHooks.shared.makeStickerHeaderRow(initialSize, stableId, arguments.context, .initialize(string: strings().reportAdditionText, color: theme.colors.text, font: .normal(.text)))
    }))
    index += 1
    // entries
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.input(sectionId: sectionId, index: index, value: .string(state.text), error: nil, identifier: _id_input, mode: .plain, data: InputDataRowData(viewType: .singleItem), placeholder: nil, inputPlaceholder: strings().reportAdditionTextPlaceholder, filter: { $0 }, limit: 128))
    index += 1


    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("_id_button"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return GeneralActionButtonRowItem(initialSize, stableId: stableId, text: strings().reportComplicatedSendReport, viewType: .legacy, action: arguments.validate, inset: .init(left: 10, right: 10))
    }))
    
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

private func ReportDetailsController(context: (any AccountContextProtocol), optional: Bool, title: String, updated: @escaping(String)->Void, modalController: InputDataModalController) -> InputDataController {

    let actionsDisposable = DisposableSet()

    var getController:(()->InputDataController?)? = nil
    
    let initialState = ReportDetailsState(text: "")
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((ReportDetailsState) -> ReportDetailsState) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }

    let arguments = ReportDetailsArguments(context: context, validate: {
        getController?()?.validateInputValues()
    })
    
    let signal = statePromise.get() |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: title)
    controller.analyticsScreen = .reportDetails
    controller._frameRect = modalController.frame.size.bounds
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.chatNavigationBack, handler: { [weak modalController] in
        modalController?.pop(animated: true)
    }, isCloseButton: false)

    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    controller.updateDatas = { data in
        updateState { current in
            var current = current
            current.text = data[_id_input]?.stringValue ?? ""
            return current
        }
        return .none
    }
    
    controller.validateData = { _ in
        let text = stateValue.with { $0.text }
        if optional || !text.isEmpty {
            updated(text)
        } else {
            return .fail(.fields([_id_input: .shake]))
        }
        return .none
    }
    
    getController = { [weak controller] in
        return controller
    }
    
    return controller
}



