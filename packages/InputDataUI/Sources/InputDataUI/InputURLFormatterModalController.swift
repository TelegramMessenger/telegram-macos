import ColorPalette
import GeneralRows
import TelegramContext
import TelegramTheme
import TelegramUtils
import Localization
import Cocoa
import TGUIKit
import SwiftSignalKit
import AppAnalytics


private let pasteboardURLDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType([.link]).rawValue)

private func urlFromPasteboard() -> String? {
    let pasteboard = NSPasteboard.general
    guard let urlString = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !urlString.isEmpty else {
        return nil
    }
    let range = NSRange(urlString.startIndex..., in: urlString)
    guard let match = pasteboardURLDetector?.firstMatch(in: urlString, options: [], range: range), match.resultType == .link, match.range == range else {
        return nil
    }
    return urlString
}

public func caseNormalizedURL(_ input: String) -> String {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let hasScheme = trimmed.range(of: "^[A-Za-z][A-Za-z0-9+.-]*://", options: .regularExpression) != nil
    guard var components = URLComponents(string: hasScheme ? trimmed : "https://" + trimmed) else {
        return trimmed.lowercased()
    }
    components.scheme = components.scheme?.lowercased()
    components.host = components.host?.lowercased()
    guard let normalized = components.url?.absoluteString else {
        return trimmed.lowercased()
    }
    return hasScheme ? normalized : String(normalized.dropFirst("https://".count))
}


func inputDataExternalURL(_ string: String) -> String? {
    var candidates = [string]
    let normalized = caseNormalizedURL(string)
    if normalized != string {
        candidates.append(normalized)
    }
    for candidate in candidates {
        if let url = InputDataUIHooks.shared.detectExternalURL(candidate) {
            return url
        }
    }
    return nil
}

private struct State : Equatable {
    var text: String
    var url: String?
    var hosts: [String] = []
    init(text: String, url: String?, hosts: [String]) {
        self.text = text
        self.url = url
        self.hosts = hosts
    }
}

private let _id_input_url = InputDataIdentifier("_id_input_url")
private let _id_text = InputDataIdentifier("_id_text")

private func entries(state: State, presentation: TelegramPresentationTheme) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1

    
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().inputFormatterTextHeader), data: InputDataGeneralTextData(color: presentation.colors.listGrayText, viewType: .textTopItem)))
    index += 1
    
    let itemTheme = GeneralRowItem.Theme.initialize(presentation)
    
    entries.append(.input(sectionId: sectionId, index: index, value: .string(state.text), error: nil, identifier: _id_text, mode: .plain, data: InputDataRowData( viewType: .singleItem, customTheme: itemTheme), placeholder: nil, inputPlaceholder: strings().inputFormatterTextPlaceholder, filter: { $0 }, limit: 10000))
    index += 1
    
    
    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1
    
    
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().inputFormatterURLHeader), data: InputDataGeneralTextData(color: presentation.colors.listGrayText, viewType: .textTopItem)))
    index += 1
    
    entries.append(.input(sectionId: sectionId, index: index, value: .string(state.url), error: nil, identifier: _id_input_url, mode: .plain, data: InputDataRowData( viewType: .singleItem, customTheme: itemTheme), placeholder: nil, inputPlaceholder: strings().inputFormatterURLPlaceholder, filter: { $0 }, limit: 10000))
    index += 1

    
    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1
    
    return entries
}

public func InputURLFormatterModalController(string: String, defaultUrl: String? = nil, completion: @escaping(String, String?) -> Void, presentation: TelegramPresentationTheme? = nil, hosts: [String] = []) -> InputDataModalController {
    
    
    let initialState = State(text: string, url: defaultUrl?.removingPercentEncoding ?? urlFromPasteboard(), hosts: hosts)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    let dataSignal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return entries(state: state, presentation: presentation ?? theme)
    }
    
    
    var close: (() -> Void)? = nil
    
    let controller = InputDataController(dataSignal: dataSignal |> map { InputDataSignalValue(entries: $0) }, title: strings().inputFormatterURLHeader, validateData: { data in
        
        let url = data[_id_input_url]?.stringValue
        let text = data[_id_text]?.stringValue ?? ""
        
        let hosts = stateValue.with { $0.hosts }
        
        if !hosts.isEmpty, let url, let url = NSURL(string: caseNormalizedURL(url)) {
            var accept: Bool = true
            if let host = url.host {
                accept = hosts.contains(host)
            } else {
                accept = hosts.contains(where: {
                    url.path?.hasPrefix($0) ?? false
                })
            }
            if !accept {
                InputDataUIHooks.shared.showModalText(InputDataUIHooks.shared.mainWindow(), strings().urlLinkOnlyAllowed(hosts.joined(separator: ", ")))
                return .fail(.fields([_id_input_url : .shake]))
            }
        }
        
        if text.isEmpty {
            return .fail(.fields([_id_text : .shake]))
        }
        
        if let string = url {

            let url = inputDataExternalURL(string)

            completion(text, url)
            close?()
            return .none
        }
        
        return .fail(.fields([_id_input_url: .shake]))
        
    }, updateDatas: { data in
        updateState { current in
            var current = current
            current.url = data[_id_input_url]?.stringValue
            current.text = data[_id_text]?.stringValue ?? ""
            return current
        }
        return .none
    })
    controller.analyticsScreen = .appLinkInput
    
    let modalInteractions = ModalInteractions(acceptTitle: strings().modalOK, accept: { [weak controller] in
        controller?.validateInputValues()
    }, singleButton: true)
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(320, 300), presentation: presentation ?? theme)
    
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    controller.getBackgroundColor = {
        return presentation?.colors.listBackground ?? theme.colors.listBackground
    }
    
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    controller.didAppear = { controller in
        controller.makeFirstResponderIfPossible(for: _id_input_url, focusIdentifier: nil, scrollDown: false, scrollIfNeeded: true)
        
        let url = stateValue.with { $0.url }
        if url != nil {
            let view = controller.tableView.item(stableId: InputDataEntryId.input(_id_input_url))?.view as? InputDataRowView
            view?.selectAll(nil)
        }
    }
   
    
    return modalController
    
}
