import Cocoa
import WebKit
import InstantPageUI

protocol BrowserPageFindContainer: AnyObject, NSTextFinderBarContainer {
    var pageFindBar: PageFindBarView? { get set }
}

func browserFindAction(character: String?, modifiers: NSEvent.ModifierFlags) -> NSTextFinder.Action? {
    let modifiers = modifiers.intersection([.command, .shift, .option, .control])
    switch character?.lowercased() {
    case "f" where modifiers == [.command]:
        return .showFindInterface
    case "g" where modifiers == [.command]:
        return .nextMatch
    case "g" where modifiers == [.command, .shift]:
        return .previousMatch
    default:
        return nil
    }
}

func browserFindContentFrame(bounds: NSRect, findBarHeight: CGFloat, visible: Bool) -> NSRect {
    let height = visible ? max(0, min(bounds.height, findBarHeight)) : 0
    return NSRect(x: bounds.minX, y: bounds.minY + height, width: bounds.width, height: max(0, bounds.height - height))
}

final class BrowserPageFind {
    private let finder = NSTextFinder()
    private weak var webView: WKWebView?
    private var navigationObservation: NSKeyValueObservation?
    private var loadingObservation: NSKeyValueObservation?
    private weak var container: (any BrowserPageFindContainer)?
    private var requests: BrowserFindRequestQueue?

    var isVisible: Bool {
        return container?.pageFindBar != nil || container?.isFindBarVisible == true
    }

    func attach(webView: WKWebView, container: any BrowserPageFindContainer) {
        guard self.webView !== webView else { return }
        dismiss(restoreFocus: false)
        navigationObservation = nil
        loadingObservation = nil
        self.webView = webView
        self.container = container
        if #available(macOS 11.0, *) {
            let requests = BrowserFindRequestQueue { [weak webView] query, backwards, completion in
                guard let webView else { completion(false); return }
                let configuration = WKFindConfiguration()
                configuration.backwards = backwards
                configuration.caseSensitive = false
                configuration.wraps = true
                webView.find(query, configuration: configuration) { result in completion(result.matchFound) }
            }
            requests.result = { [weak self, weak webView, weak requests] query, found in
                guard let self, let requests, self.requests === requests, self.webView === webView else { return }
                self.container?.pageFindBar?.updateResult(found: query.isEmpty ? nil : found)
            }
            self.requests = requests
        }
        if #available(macOS 10.15.4, *) {
            finder.client = webView
            finder.findBarContainer = container
            finder.isIncrementalSearchingEnabled = true
            finder.incrementalSearchingShouldDimContentView = true
        }
        navigationObservation = webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            self?.contentWillChange()
        }
        loadingObservation = webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
            if view.isLoading {
                self?.contentWillChange()
            }
        }
    }

    @discardableResult
    func perform(_ action: NSTextFinder.Action) -> Bool {
        guard #available(macOS 10.15.4, *), webView != nil else { return false }
        switch action {
        case .showFindInterface, .nextMatch, .previousMatch:
            if #available(macOS 11.0, *) {
                if action == .showFindInterface || container?.pageFindBar == nil {
                    showSearch()
                } else {
                    navigate(backwards: action == .previousMatch)
                }
            } else {
                finder.performAction(action)
            }
            return true
        case .hideFindInterface:
            return dismiss()
        default:
            return false
        }
    }

    @available(macOS 11.0, *)
    private func showSearch() {
        guard let container else { return }
        if container.pageFindBar == nil {
            let bar = PageFindBarView(frame: NSRect(x: 0, y: 0, width: webView?.frame.width ?? 0, height: 46))
            bar.queryUpdated = { [weak self] query in self?.search(query, backwards: false) }
            bar.navigate = { [weak self] backwards in
                self?.navigate(backwards: backwards)
            }
            bar.close = { [weak self] in _ = self?.dismiss() }
            container.pageFindBar = bar
        }
        container.pageFindBar?.focus()
    }

    @available(macOS 11.0, *)
    private func search(_ query: String, backwards: Bool) {
        container?.pageFindBar?.updateResult(loading: !query.isEmpty)
        requests?.enqueue(query, backwards: backwards)
    }

    @available(macOS 11.0, *)
    private func navigate(backwards: Bool) {
        guard let query = container?.pageFindBar?.query, !query.isEmpty else { return }
        container?.pageFindBar?.updateResult(loading: true)
        requests?.navigate(backwards: backwards)
    }

    @discardableResult
    func dismiss(restoreFocus: Bool = true) -> Bool {
        guard isVisible else { return false }
        let window = webView?.window
        let shouldRestore = restoreFocus && findBarContains(window?.firstResponder)
        container?.pageFindBar = nil
        if #available(macOS 11.0, *) {
            search("", backwards: false)
        }
        finder.performAction(.hideFindInterface)
        finder.cancelFindIndicator()
        if shouldRestore {
            window?.makeFirstResponder(webView)
        }
        return true
    }

    private func findBarContains(_ responder: NSResponder?) -> Bool {
        if container?.pageFindBar?.containsResponder(responder) == true { return true }
        guard let bar = container?.findBarView, let view = responder as? NSView else { return false }
        if view === bar || view.isDescendant(of: bar) {
            return true
        }
        if let editor = responder as? NSTextView, editor.isFieldEditor, let field = editor.delegate as? NSView {
            return field === bar || field.isDescendant(of: bar)
        }
        return false
    }

    private func contentWillChange() {
        finder.noteClientStringWillChange()
        finder.cancelFindIndicator()
        dismiss(restoreFocus: false)
    }

    deinit {
        finder.cancelFindIndicator()
        finder.client = nil
        finder.findBarContainer = nil
    }
}
