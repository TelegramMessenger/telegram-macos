import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore

import Postbox
import TGModernGrowingTextView
import InAppSettings
import Localization
import Strings
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMediaUtils
import ChatModeTypes
import InlineStickerLayer
import PremiumStatusUI
import InputDataUI


public enum ESearchCommand {
    case loading
    case normal
    case close
    case clearText
    case apply(String)
}



public enum EntertainmentStickerDrag {
    case moved(NSPoint)
    case ended(NSPoint)
}

public enum EntertainmentDragItem {
    case file(TelegramMediaFile)
    case emoji(String)
}

public final class EntertainmentInteractions {
    
    public var current:EntertainmentState = .emoji
    
    public var sendEmoji:(String, CGRect?) ->Void = { _,_ in }
    public var sendAnimatedEmoji:(StickerPackItem, StarGift.UniqueGift?, StickerPackCollectionInfo?, Int32?, NSRect?) ->Void = { _, _, _, _, _ in}
    public var sendLargeReaction:((StickerPackItem, NSRect?) ->Void)?
    public var sendSticker:(TelegramMediaFile, Bool, Bool, ItemCollectionId?) ->Void = { _, _, _, _ in}
    public var sendGIF:(TelegramMediaFile, Bool, Bool) ->Void = { _, _, _ in}
    public var dragItem: ((EntertainmentDragItem, CGImage?, EntertainmentStickerDrag) -> Void)?
    
    public var showEntertainment:(EntertainmentState, Bool)->Void = { _,_  in}
    public var close:()->Void = {}

    public var toggleSearch:()->Void = { }
    
    public var showStickerPremium:(TelegramMediaFile, NSView)->Void = { _, _ in }
    
    public let peerId:PeerId
    
    public init(_ defaultState: EntertainmentState, peerId:PeerId) {
        current = defaultState
        self.peerId = peerId
    }
}

public final class EntertainmentView : View {
    fileprivate static let tabsAreaHeight: CGFloat = 56

    static let glassTintAlpha: CGFloat = 0.55

    fileprivate var sectionView: NSView
    private let glassView = LiquidGlassView(frame: NSZeroRect, cornerRadius: 18, hasShadow: false, hasBorder: true, tintAlpha: 0, forceBlur: true)
    private let edgeView = ShadowView()
    private let tabs = GlassSegmentView(frame: NSZeroRect)
    private var tabStates: [EntertainmentState] = []
    fileprivate private(set) var selectedState: EntertainmentState?
    fileprivate var didSelectState: ((EntertainmentState) -> Void)?

    var showsTabsEdge: Bool = true {
        didSet {
            edgeView.isHidden = !showsTabsEdge
        }
    }

    var showsGlassBackground: Bool = true {
        didSet {
            glassView.isHidden = !showsGlassBackground
        }
    }
    
    private var premiumView: StickerPremiumHolderView?
    private let tabAccessibilityCells = EntertainmentAccessibilityCells()

    public override func accessibilityChildren() -> [Any]? {
        guard TGUIKitAccessibility.isEnabled else {
            return super.accessibilityChildren()
        }
        var children = NSAccessibility.unignoredChildren(from: subviews.filter { $0 !== tabs })
        let labels = tabs.subviews.compactMap { $0 as? TextView }
        var cells: [EntertainmentAccessibilityCell] = []
        for (index, title) in tabs.titles.enumerated() where index < labels.count && index < tabStates.count {
            let label = labels[index]
            let state = tabStates[index]
            let rect = tabs.convert(NSMakeRect(label.frame.minX - 12, 0, label.frame.width + 24, tabs.frame.height), to: self)
            cells.append(EntertainmentAccessibilityCell(id: AnyHashable(index), label: title, frame: rect, isSelected: state == selectedState, press: { [weak self] in
                self?.didSelectState?(state)
            }))
        }
        children.append(contentsOf: tabAccessibilityCells.elements(for: cells, in: self))
        return children
    }

    public init(sectionView: NSView, frame: NSRect) {
        self.sectionView = sectionView
        super.init(frame: frame)
        self.addSubview(self.glassView)
        self.addSubview(self.sectionView)
        self.addSubview(self.edgeView)
        self.addSubview(self.tabs)

        self.edgeView.direction = .vertical(true)
        self.edgeView.isEventLess = true

        self.tabs.didSelect = { [weak self] index in
            guard let self, index < self.tabStates.count else {
                return
            }
            self.didSelectState?(self.tabStates[index])
        }
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        self.edgeView.shadowBackground = theme.colors.background.withAlphaComponent(0.6)
        self.glassView.customTint = theme.colors.background.withAlphaComponent(EntertainmentView.glassTintAlpha)
        self.glassView.updateLocalizationAndTheme(theme: theme)
        self.updateTabs(animated: false)
    }
    
    public func toggleSearch(_ signal:ValuePromise<SearchState>) {

    }
    
    public func updateSelected(_ state: EntertainmentState, mode: EntertainmentViewController.Mode, animated: Bool) {
        self.tabStates = mode == .selectAvatar ? [.stickers, .gifs] : [.emoji, .stickers, .gifs]
        self.selectedState = state
        self.updateTabs(animated: animated)
    }
    
    fileprivate func updateSelectionPosition(_ position: CGFloat, animated: Bool) {
        self.tabs.setSelection(position: position, animated: animated)
    }
    
    private func updateTabs(animated: Bool) {
        let titles: [String] = self.tabStates.map { state in
            switch state {
            case .emoji:
                return strings().entertainmentEmojiNew
            case .stickers:
                return strings().entertainmentStickersNew
            case .gifs:
                return strings().entertainmentGIFNew
            }
        }
        let selected = self.selectedState.flatMap { self.tabStates.firstIndex(of: $0) }
        self.tabs.set(titles: titles, selected: selected, animated: animated)
        needsLayout = true
    }
    
    public func previewPremium(_ file: TelegramMediaFile, context: any AccountContextProtocol, view: NSView, animated: Bool) {
        let current: StickerPremiumHolderView
        if let view = premiumView {
            current = view
        } else {
            current = StickerPremiumHolderView(frame: bounds)
            self.premiumView = current
            addSubview(current)
            
            if animated {
                current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            }
        }
        current.set(file: file, context: context, callback: { [weak self] in
            FeatureNavigationHooks.shared.showPremiumBoarding(context, context.window, .premiumStickers, false, nil)
            self?.closePremium()
        })
        current.close = { [weak self] in
            self?.closePremium()
        }
    }
    
    public var isPremium: Bool {
        return self.premiumView != nil
    }
    
    public func closePremium() {
        if let view = premiumView {
            performSubviewRemoval(view, animated: true)
            self.premiumView = nil
        }
    }
    
    
    
    public override func layout() {
        super.layout()
        let tabsAreaHeight = EntertainmentView.tabsAreaHeight
        self.glassView.frame = bounds
        self.glassView.updateLayout(size: bounds.size, transition: .immediate)
        self.sectionView.frame = bounds
        self.edgeView.frame = NSMakeRect(0, frame.height - tabsAreaHeight, frame.width, tabsAreaHeight)
        let tabsSize = self.tabs.contentSize
        self.tabs.frame = NSMakeRect(floorToScreenPixels((frame.width - tabsSize.width) / 2), frame.height - tabsAreaHeight + (tabsAreaHeight - tabsSize.height) / 2, tabsSize.width, tabsSize.height)
        self.premiumView?.frame = bounds
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
}


public enum EntertainmentViewControllerMode {
    case common
    case selectAvatar
    case stories
    case intro
}

public class EntertainmentViewController<Context: AccountContextProtocol>: TelegramGenericViewController<EntertainmentView, Context> {
    public override var defaultBarTitle: String {
        return localizedString("Telegram.EntertainmentViewController")
    }
    private let languageDisposable:MetaDisposable = MetaDisposable()

    public private(set) weak var chatInteraction: (any ChatInteractionProtocol)?
    public private(set) var interactions:EntertainmentInteractions?
    
    private let section: SectionViewController

    private var disposable:MetaDisposable = MetaDisposable()
    private let preparationDisposable = MetaDisposable()
    public typealias Mode = EntertainmentViewControllerMode
    
    private let mode: Mode

    private let emoji:EmojiesController<Context>
    private let stickers:NStickersViewController<Context>
    private let gifs:GifKeyboardController<Context>
    
    private var effectiveSearchView: SearchView? {
        let controller = self.section.selectedSection.controller
        if controller === self.gifs {
            return self.gifs.genericView.searchView
        }
        if controller === self.emoji {
            return self.emoji.genericView.searchView
        }
        if controller === self.stickers {
            return self.stickers.genericView.searchView
        }
        return nil
    }
    
    public func prepareForPresentation() {
        guard !self.isLoaded() else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isLoaded() else {
                return
            }
            self.loadViewIfNeeded(NSMakeRect(0, 0, 350, min(max(self.context.window.frame.height - 250, 300), 550)))
            self.preparationDisposable.set((self.ready.get() |> filter { $0 } |> take(1)).start(next: { [weak self] _ in
                guard let self, self.view.window == nil, self.popover == nil else {
                    return
                }
                self.viewWillDisappear(false)
                self.viewDidDisappear(false)
            }))
        }
    }

    public func update(with chatInteraction: any ChatInteractionProtocol) -> Void {
        self.chatInteraction = chatInteraction
        
        let context = self.context
        
        let state: EntertainmentState
        if mode == .selectAvatar {
            state = .stickers
        } else {
            state = FastSettings.entertainmentState
        }
        
        let interactions = EntertainmentInteractions(state, peerId: chatInteraction.peerId)

        interactions.close = { [weak self] in
            self?.closePopover()
        }
        interactions.sendSticker = { [weak self] file, silent, scheduled, collectionId in
            let cachedData = self?.chatInteraction?.presentationCachedData
            if let peer = self?.chatInteraction?.peer, let text = permissionText(from: peer, for: .banSendStickers, cachedData: cachedData) {
                showModalText(for: context.window, text: text)
            } else {
                self?.chatInteraction?.sendFile(file, silent: silent, query: self?.effectiveSearchView?.query, scheduled: scheduled, collectionId: collectionId)
            }
            self?.closePopover()
        }
        interactions.sendGIF = { [weak self] file, silent, scheduled in
            let cachedData = self?.chatInteraction?.presentationCachedData
            if let peer = self?.chatInteraction?.peer, let text = permissionText(from: peer, for: .banSendGifs, cachedData: cachedData) {
                showModalText(for: context.window, text: text)
            } else {
                self?.chatInteraction?.sendFile(file, silent: silent, query: self?.effectiveSearchView?.query, scheduled: scheduled, collectionId: nil)
            }
            self?.closePopover()
        }
        interactions.sendEmoji = { [weak self] emoji, fromRect in
            if self?.mode == .selectAvatar {
                _ = self?.chatInteraction?.sendPlainText(emoji)
                self?.closePopover()
            } else {
                let cachedData = self?.chatInteraction?.presentationCachedData
                if let peer = self?.chatInteraction?.peer, let text = permissionText(from: peer, for: .banSendText, cachedData: cachedData) {
                    showModalText(for: context.window, text: text)
                } else {
                    self?.chatInteraction?.appendAttributedText(.initialize(string: emoji))
                }
            }
        }
        
        interactions.sendAnimatedEmoji = { [weak self] sticker, _, info, _, fromRect in
            if self?.mode == .selectAvatar {
              
            } else {
                let cachedData = self?.chatInteraction?.presentationCachedData
                if let peer = self?.chatInteraction?.peer, let text = permissionText(from: peer, for: .banSendText, cachedData: cachedData) {
                    showModalText(for: context.window, text: text)
                } else {
                    let text = (sticker.file._parse().customEmojiText ?? sticker.file._parse().stickerText ?? "😀").normalizedEmoji
                    self?.chatInteraction?.appendAttributedText(.makeAnimated(sticker.file._parse(), text: text, info: info?.id))
                }
            }
        }
        
        interactions.showStickerPremium = { [weak self] file, view in
            self?.genericView.previewPremium(file, context: context, view: view, animated: true)
        }
        
        interactions.toggleSearch = { [weak self] in
            guard let `self` = self else {
                return
            }
            self.toggleSearch()
        }
        self.interactions = interactions
        
        emoji.update(with: interactions, chatInteraction: chatInteraction)
        stickers.update(with: interactions, chatInteraction: chatInteraction)
        gifs.update(with: interactions, chatInteraction: chatInteraction)
    }
    

    private var presentation: TelegramPresentationTheme? = nil
    
    public init(size:NSSize, context:Context, mode: Mode = .common, presentation: TelegramPresentationTheme? = nil) {
        self.mode = mode
        self.presentation = presentation
        self.emoji = EmojiesController(context, mode: mode == .stories ? .stories : .emoji, presentation: presentation)
        self.emoji.isGlass = true
        if mode == .common || mode == .stories {
        }
        self.stickers = NStickersViewController(context, presentation: presentation)
        self.gifs = GifKeyboardController(context, presentation: presentation)

        
        self.stickers.mode = mode
        self.gifs.mode = mode
        
        var items:[SectionControllerItem] = []
        if mode == .common || mode == .stories {
            items.append(SectionControllerItem(title:{strings().entertainmentEmoji.uppercased()}, controller: emoji))
        }
        items.append(SectionControllerItem(title: {strings().entertainmentStickers.uppercased()}, controller: stickers))
        items.append(SectionControllerItem(title: {strings().entertainmentGIF.uppercased()}, controller: gifs))

        

        let index: Int
        if mode == .selectAvatar {
            index = 0
        } else {
            index = Int(FastSettings.entertainmentState.rawValue)
        }
        self.section = SectionViewController(sections: items, selected: index)
        super.init(context)
        _frameRect = size.bounds
        bar = .init(height: 0)
    }


    public override var popoverBackgroundColor: NSColor {
        return .clear
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        self.section.updateLocalizationAndTheme(theme: theme)
        self.view.background = .clear
        self.applyGlassStyle()
    }

    private func applyGlassStyle() {
        if self.section.genericView._backgroundColor != .clear {
            self.section.genericView._backgroundColor = .clear
        }
        if emoji.isLoaded() {
            emoji.view.background = .clear
        }
        if stickers.isLoaded() {
            stickers.view.background = .clear
            stickers.genericView.isGlass = true
        }
        if gifs.isLoaded() {
            gifs.view.background = .clear
            gifs.genericView.isGlass = true
        }
    }
    
    deinit {
        languageDisposable.dispose()
        disposable.dispose()
        preparationDisposable.dispose()
    }

    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        section.viewWillAppear(animated)
        updateLocalizationAndTheme(theme: presentation ?? theme)
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        section.viewWillDisappear(animated)
        window?.removeAllHandlers(for: self)
    }

    
    
    private func toggleSearch() {
        if let searchView = self.effectiveSearchView {
            if searchView.state == .Focus {
                searchView.setString("")
                searchView.cancel(true)
            } else {
                searchView.change(state: .Focus, true)
            }
        }
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        section.viewDidAppear(animated)
        
        window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            guard self != nil else {
                return .rejected
            }
            return .rejected
        }, with: self, for: .F, priority: .modal, modifierFlags: .command)

    }
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        section.viewDidDisappear(animated)
        genericView.closePremium()
    }
    
    public override func initializer() -> EntertainmentView {
        let rect = NSMakeRect(self._frameRect.minX, self._frameRect.minY, self._frameRect.width, self._frameRect.height - self.bar.height)
        self.section._frameRect = rect
        return EntertainmentView(sectionView: self.section.view, frame: rect)
    }

    private func updateSectionsBottomInset() {
        let insets = NSEdgeInsets(bottom: EntertainmentView.tabsAreaHeight)
        var tables: [TableView] = []
        if emoji.isLoaded() {
            tables.append(emoji.genericView.tableView)
        }
        if stickers.isLoaded() {
            tables.append(stickers.genericView.tableView)
        }
        if gifs.isLoaded() {
            tables.append(gifs.genericView.tableView)
        }
        for table in tables where table.contentInsets != insets {
            table.contentInsets = insets
        }
    }

    public override func firstResponder() -> NSResponder? {
        if popover == nil {
            return nil
        }
        return effectiveSearchView//genericView.searchView?.input
    }
    
    public override func becomeFirstResponder() -> Bool? {
        return nil
    }
    
    public override func escapeKeyAction() -> KeyHandlerResult {
        if genericView.isPremium {
            genericView.closePremium()
            return .invoked
        }
        let result = self.section.selectedSection.controller.escapeKeyAction()
        if result == .rejected {
            return super.escapeKeyAction()
        }
        return result
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()

        let state:EntertainmentState
        if mode == .selectAvatar {
            state = .stickers
        } else {
            state = FastSettings.entertainmentState
        }
        
        
        
        self.genericView.updateSelected(state, mode: mode, animated: false)
        self.updateSectionsBottomInset()
        self.applyGlassStyle()

        
        let callSearchCmd:(ESearchCommand, SearchView)->Void = { command, view in
            switch command {
            case .clearText:
                view.setString("")
            case .loading:
                view.isLoading = true
            case .normal:
                view.isLoading = false
            case .close:
                view.cancel(true)
            case let .apply(value):
                view.setString(value)
            }
        }
        
        self.stickers.makeSearchCommand = { [weak self] command in
            if self?.stickers.view.superview != nil, let view = self?.stickers.genericView.searchView  {
                callSearchCmd(command, view)
            }
        }
                
        self.gifs.makeSearchCommand = { [weak self] command in
            if self?.gifs.view.superview != nil, let view = self?.gifs.genericView.searchView  {
                callSearchCmd(command, view)
            }
        }
        
        self.emoji.makeSearchCommand = { [weak self] command in
            if self?.emoji.view.superview != nil, let view = self?.emoji.genericView.searchView  {
                callSearchCmd(command, view)
            }
        }
        
        
        let e_index: Int = 0
        let s_index: Int = mode == .selectAvatar ? 0 : 1
        let g_index: Int = mode == .selectAvatar ? 1 : 2

        self.genericView.didSelectState = { [weak self] state in
            guard let `self` = self else {
                return
            }
            let isSelected = self.genericView.selectedState == state
            switch state {
            case .emoji:
                if isSelected {
                    self.emoji.scrollup()
                }
                self.section.select(e_index, true)
            case .stickers:
                if isSelected {
                    self.stickers.scrollup()
                }
                self.section.select(s_index, true)
            case .gifs:
                if isSelected {
                    self.gifs.scrollup()
                }
                self.section.select(g_index, true)
            }
        }
        

        
        let mode = self.mode
        
        section.selectorPositionHandler = { [weak self] position, animated in
            self?.genericView.updateSelectionPosition(position, animated: animated)
        }
        
        section.selectionUpdateHandler = { [weak self] index in
            var index = index
            if mode == .selectAvatar {
                index += 1
            }
            
            let state = EntertainmentState(rawValue: Int32(index))!
            if mode == .common || mode == .stories {
                FastSettings.changeEntertainmentState(state)
            }
            self?.chatInteraction?.setIsEmojiSection(state == .emoji)
            self?.genericView.updateSelected(state, mode: mode, animated: true)
            self?.updateSectionsBottomInset()
            self?.applyGlassStyle()
        }

        self.ready.set(section.ready.get())
        
        languageDisposable.set((combineLatest(appearanceSignal, ready.get() |> filter {$0} |> take(1))).start(next: { [weak self] _ in
            self?.updateLocalizationAndTheme(theme: self?.presentation ?? theme)
        }))
    }
    
}

