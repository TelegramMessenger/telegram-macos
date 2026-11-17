import Cocoa
import TGUIKit
import TelegramTheme
import Localization

private final class PageFindSearchView: SearchView {
    var navigate: ((Bool) -> Void)?
    var close: (() -> Void)?

    override func cancelSearch() {
        if query.isEmpty {
            close?()
        } else {
            super.cancelSearch()
        }
    }

    override func didBecomeResponder() {
        _window?.removeAllHandlers(for: self)
        _window?.removeObserver(for: self)
        super.didBecomeResponder()
        _window?.remove(object: self, for: .Escape)
        _window?.set(escape: { [weak self] event in
            guard let self, !self.input.hasMarkedText(), event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else {
                return .invokeNext
            }
            self.close?()
            return .invoked
        }, with: self, priority: .modal)
        _window?.set(handler: { [weak self] event in
            guard let self, !self.input.hasMarkedText(), event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
                return .invokeNext
            }
            self.navigate?(event.modifierFlags.contains(.shift))
            return .invoked
        }, with: self, for: .Return, priority: .modal)
    }

    override func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)), !textView.hasMarkedText() {
            navigate?(NSApp.currentEvent?.modifierFlags.contains(.shift) == true)
            return true
        }
        if commandSelector == #selector(cancelOperation(_:)), !textView.hasMarkedText() {
            close?()
            return true
        }
        return super.textView(textView, doCommandBy: commandSelector)
    }
}

public final class PageFindBarView: View {
    public var queryUpdated: ((String) -> Void)?
    public var navigate: ((Bool) -> Void)?
    public var close: (() -> Void)?

    private let searchView = PageFindSearchView(frame: .zero)
    private let previous = ImageButton()
    private let next = ImageButton()
    private let closeButton = ImageButton()
    private let result = TextView()
    private let separator = View()
    private var resultIndex: Int?
    private var resultCount: Int?
    private var matchFound: Bool?

    public var query: String { searchView.query }

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(searchView)
        addSubview(previous)
        addSubview(next)
        addSubview(closeButton)
        addSubview(result)
        addSubview(separator)
        result.isSelectable = false
        result.userInteractionEnabled = false
        separator.isEventLess = true
        for button in [previous, next, closeButton] {
            button.autohighlight = false
            button.scaleOnClick = true
        }
        searchView.searchInteractions = SearchInteractions({ _, _ in }, { [weak self] state in
            self?.queryUpdated?(state.request)
        })
        searchView.navigate = { [weak self] backwards in self?.navigate?(backwards) }
        searchView.close = { [weak self] in self?.close?() }
        previous.set(handler: { [weak self] _ in self?.navigate?(true) }, for: .Click)
        next.set(handler: { [weak self] _ in self?.navigate?(false) }, for: .Click)
        closeButton.set(handler: { [weak self] _ in self?.close?() }, for: .Click)
        updateLocalizationAndTheme(theme: theme)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func focus() {
        searchView.change(state: .Focus, false)
        window?.makeFirstResponder(searchView.input)
        searchView.input.selectAll(nil)
    }

    public func containsResponder(_ responder: NSResponder?) -> Bool {
        if let view = responder as? NSView, view === self || view.isDescendant(of: self) {
            return true
        }
        if let editor = responder as? NSTextView, editor.isFieldEditor, let field = editor.delegate as? NSView {
            return field === self || field.isDescendant(of: self)
        }
        return false
    }

    public func updateResult(index: Int? = nil, count: Int? = nil, found: Bool? = nil, loading: Bool = false) {
        resultIndex = index
        resultCount = count
        matchFound = found
        searchView.isLoading = loading
        updateResultPresentation()
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        backgroundColor = theme.colors.background
        separator.backgroundColor = theme.colors.border
        searchView.searchTheme = .init(theme.colors.grayBackground.withAlphaComponent(0.5), theme.search.searchImage, theme.search.clearImage, theme.search.placeholder, theme.search.textColor, theme.search.placeholderColor)
        previous.setAccessibilityLabel(strings().voiceOverCommonPrevious)
        next.setAccessibilityLabel(strings().voiceOverCommonNext)
        closeButton.setAccessibilityLabel(strings().voiceOverCommonClose)
        updateResultPresentation()
    }

    private func updateResultPresentation() {
        let canNavigate = !query.isEmpty && !searchView.isLoading && (resultCount.map { $0 > 0 } ?? (matchFound == true))
        previous.isEnabled = canNavigate
        next.isEnabled = canNavigate
        previous.set(image: canNavigate ? theme.icons.chat_search_prev : theme.icons.chat_search_prev_disabled, for: .Normal)
        next.set(image: canNavigate ? theme.icons.chat_search_next : theme.icons.chat_search_next_disabled, for: .Normal)
        closeButton.set(image: theme.icons.chat_search_cancel, for: .Normal)
        for button in [previous, next, closeButton] { _ = button.sizeToFit() }
        let text: String
        if !query.isEmpty, let count = resultCount, count > 0 {
            text = strings().chatSearchCount((resultIndex ?? 0) + 1, count)
        } else if !query.isEmpty, !searchView.isLoading, resultCount == 0 || matchFound == false {
            text = strings().requestJoinListSearchEmptyHeader
        } else {
            text = ""
        }
        let layout = TextViewLayout(.initialize(string: text, color: theme.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 1)
        layout.measure(width: 180)
        result.update(layout)
        result.setAccessibilityLabel(text)
        needsLayout = true
    }

    public override func layout() {
        super.layout()
        let inset: CGFloat = 8
        let gap: CGFloat = 6
        closeButton.centerY(x: max(inset, frame.width - inset - closeButton.frame.width))
        next.centerY(x: max(inset, closeButton.frame.minX - gap - next.frame.width))
        previous.centerY(x: max(inset, next.frame.minX - gap - previous.frame.width))
        let countWidth = result.frame.width
        let showCount = countWidth > 0 && previous.frame.minX - countWidth - gap * 2 - inset >= 140
        result.isHidden = !showCount
        result.centerY(x: max(inset, previous.frame.minX - gap - countWidth))
        let right = showCount ? result.frame.minX - gap : previous.frame.minX - gap
        searchView.frame = NSRect(x: inset, y: max(0, floor((frame.height - 30) / 2)), width: max(0, right - inset), height: min(30, frame.height))
        searchView.updateLayout(size: searchView.frame.size, transition: .immediate)
        separator.frame = NSRect(x: 0, y: max(0, frame.height - .borderSize), width: frame.width, height: .borderSize)
    }
}
