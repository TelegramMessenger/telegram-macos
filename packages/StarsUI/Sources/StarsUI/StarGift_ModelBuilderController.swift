import Cocoa
import Foundation
import TGUIKit
import UniqueGiftBackground
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import AlertsUI
import TelegramMediaUtils
import TelegramMedia
import LocalAnimations
import CurrencyFormat
import PremiumStatusUI
import SceneEffects
import DustLayer
import InAppPurchaseManager
import ObjcUtils
import PremiumUI
import CalendarUtils
import DateUtils
import LokiRng
import FoundationUtils
import InputView
import InputTextView
import InlineStickerLayer
import AppAnalytics



extension StarGift.UniqueGift.Attribute {
    public var file: TelegramMediaFile? {
        switch self {
        case .backdrop:
            return nil
        case let .model(_, file, _, _):
            return file
        case let .pattern(_, file, _):
            return file
        case .originalInfo:
            return nil
        }
    }
    public var rarity: Rarity {
        switch self {
        case let .backdrop(_, _, _, _, _, _, rarity):
            return rarity
        case let .model(_, _, rarity, _):
            return rarity
        case let .pattern(_, _, rarity):
            return rarity
        case .originalInfo:
            return .permille(0)
        }
    }
    public var name: String {
        switch self {
        case let .backdrop(name, _, _, _, _, _, _):
            return name
        case let .model(name, _, _, _):
            return name
        case let .pattern(name, _, _):
            return name
        case .originalInfo:
            return ""
        }
    }
}

private final class AttrRowItem: GeneralRowItem {
    fileprivate let entry: GridController.Entry
    fileprivate let arguments: Arguments
    fileprivate let model: TelegramMediaFile
    public init(_ initialSize: NSSize, stableId: AnyHashable, entry: GridController.Entry, arguments: Arguments, model: TelegramMediaFile) {
        self.entry = entry
        self.arguments = arguments
        self.model = model
        super.init(initialSize, height: 110, stableId: stableId)
    }

    public override var accessibilityLabel: String? {
        return entry.mode.accessibilityTitle
    }
    
    public override func viewClass() -> AnyClass {
        return AttrRowItemView.self
    }
}

private final class AttrRowItemView : GeneralRowView {
    private final class OptionView: Control {
        private var selectionView: View?
        private let modelView: NSView = StarsHooks.shared.makeStickerView(NSMakeRect(0, 0, 60, 60))
        private let rarityTextView = TextView()
        private let nameView = TextView()
        private var backgroundView: UniqueGiftBackgroundView?
        private var backgroundContent: UniqueGiftBackgroundContent?
        private var backgroundContext: (any AccountContextProtocol)?
        private var accessibilityAttr: StarGift.UniqueGift.Attribute?
        private var isAccessibilityChosen: Bool = false

        override var accessibilityDefaultLabel: String? {
            return accessibilityAttr?.name
        }

        override func accessibilityValue() -> Any? {
            guard let attr = accessibilityAttr else {
                return nil
            }
            var parts: [String] = [attr.rarity.badgeText]
            if isAccessibilityChosen {
                parts.append(strings().voiceOverCommonSelected)
            }
            return parts.filter { !$0.isEmpty }.joined(separator: ", ")
        }

        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(modelView)
            addSubview(rarityTextView)
            addSubview(nameView)
            nameView.userInteractionEnabled = false
            nameView.isSelectable = false
            nameView.isAccessibilityDecorative = true
            
            rarityTextView.userInteractionEnabled = false
            rarityTextView.isSelectable = false
            rarityTextView.isAccessibilityDecorative = true

            
            (modelView as? View)?.userInteractionEnabled = false
            background = theme.colors.background
            layer?.cornerRadius = 14
        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public func set(entry: GridController.Entry, model:TelegramMediaFile, attr: StarGift.UniqueGift.Attribute, mode: StarGift_Builder_Section, selected: Bool, arguments: Arguments, animated: Bool) {
            self.accessibilityAttr = attr
            self.isAccessibilityChosen = selected
            
            setSingle(handler: { [weak arguments] _ in
                arguments?.selectAttribute(attr, mode)
            }, for: .Click)
            
            let file = attr.file ?? model
            
            var modelColors: [LottieColor] = []
            if mode == .symbols {
                modelColors = [.init(keyPath: "", color: NSColor(0xffffff))]
            }
            
            
            
            (modelView as? StarsStickerView)?.updateStarsSticker(file: file, size: modelView.frame.size, context: arguments.context, colors: modelColors, playback: .loopHidden, animated: animated)
            modelView.centerX(y: 15)
            
            let nameLayout = TextViewLayout(.initialize(string: attr.name, color: mode == .models ? theme.colors.text : .white, font: .normal(.short)), truncationType: .middle, alignment: .center)
            nameLayout.measure(width: frame.width - 10)
            GiftBuilderMotion.updateText(nameView, layout: nameLayout, animated: animated)
            
            nameView.centerX(y: frame.height - 5 - nameView.frame.height - 3)
            
            
            let badgeColor = attr.rarity.badgeColor ?? (mode == .models ? theme.colors.grayIcon : .white)
            let rarityLayout = TextViewLayout(.initialize(string: attr.rarity.badgeText, color: badgeColor, font: .medium(9)), alignment: .center)
            rarityLayout.measure(width: .greatestFiniteMagnitude)

            GiftBuilderMotion.updateText(rarityTextView, layout: rarityLayout, animated: animated)
            rarityTextView.setFrameSize(NSMakeSize(rarityTextView.frame.width + 6, rarityTextView.frame.height + 5))

            rarityTextView.layer?.cornerRadius = rarityTextView.frame.height / 2
            rarityTextView.backgroundColor = badgeColor.withAlphaComponent(0.2)
            
            rarityTextView.setFrameOrigin(NSMakePoint(frame.width - rarityTextView.frame.width - 5, 5))
            
            if selected {
                let current: View
                var isNew: Bool = false
                if let selectionView {
                    current = selectionView
                } else {
                    current = View(frame: bounds.insetBy(dx: 2, dy: 2))
                    self.selectionView = current
                    addSubview(current)
                    current.layer?.cornerRadius = 12
                    current.layer?.borderWidth = 1.5
                    isNew = true
                }
                if isNew, animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
                current.layer?.borderColor = mode == .models ? theme.colors.accent.cgColor : .white
            } else if let selectionView {
                performSubviewRemoval(selectionView, animated: animated)
                self.selectionView = nil
            }
            
            switch mode {
            case .backdrops, .symbols:
                let backdropAttr = mode == .symbols ? entry.effectiveBackdrop : attr
                let symbolAttr = mode == .backdrops ? entry.effectiveSymbol : attr
                if let content = UniqueGiftBackgroundContent(attributes: [backdropAttr, symbolAttr].compactMap { $0 }) {
                    if self.backgroundView == nil {
                        let current = UniqueGiftBackgroundView(frame: bounds)
                        self.addSubview(current, positioned: .below, relativeTo: modelView)
                        self.backgroundView = current
                    }
                    self.backgroundContent = content
                    self.backgroundContext = arguments.context
                    self.updateBackground(animated: animated)
                } else {
                    backgroundView?.removeFromSuperview()
                    self.backgroundView = nil
                    self.backgroundContent = nil
                    self.backgroundContext = nil
                }
            default:
                backgroundView?.removeFromSuperview()
                self.backgroundView = nil
                self.backgroundContent = nil
                self.backgroundContext = nil
            }
        }

        override func layout() {
            super.layout()
            self.updateBackground()
        }

        private func updateBackground(animated: Bool = false) {
            guard let backgroundView, let content = backgroundContent, let context = backgroundContext else {
                return
            }
            backgroundView.frame = bounds
            backgroundView.update(context: context, content: content, style: .item(giftCenterY: modelView.frame.midY, cornerRadius: 14), animated: animated)
        }
    }
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? AttrRowItem else {
            return
        }
        
        let itemSize: NSSize
        let count = 3
        let space = frame.width - (10 * CGFloat(count - 1))
        itemSize = NSMakeSize(floor(space / CGFloat(count)), frame.height - 10)
        
        while self.subviews.count > item.entry.attributes.count {
            self.subviews.last?.removeFromSuperview()
        }
        while self.subviews.count < item.entry.attributes.count {
            self.addSubview(OptionView(frame: itemSize.bounds))
        }
        
        layout()
        
        for (i, subview) in subviews.enumerated() {
            let view = subview as? OptionView
            view?.set(entry: item.entry, model: item.model, attr: item.entry.attributes[i], mode: item.entry.mode, selected: item.entry.selected == item.entry.attributes[i], arguments: item.arguments, animated: animated)
        }
        var x: CGFloat = 0

        for (_, subview) in subviews.enumerated() {
            let view = subview as? OptionView
            view?.setFrameSize(itemSize)
            subview.setFrameOrigin(x, 5)
            x += subview.frame.width + 10
        }
    }
}

public enum StarGift_Builder_Section : Int {
    case models = 0
    case backdrops = 1
    case symbols = 2
}

extension StarGift_Builder_Section {
    fileprivate var accessibilityTitle: String {
        switch self {
        case .models:
            return strings().starGiftModelBuilderModels
        case .backdrops:
            return strings().starGiftModelBuilderBackdrops
        case .symbols:
            return strings().starGiftModelBuilderSymbols
        }
    }
}

private final class GridController : ViewController {
    
    public struct Entry : Comparable, Identifiable {
        public static func < (lhs: GridController.Entry, rhs: GridController.Entry) -> Bool {
            return lhs.index < rhs.index
        }
        public var mode: StarGift_Builder_Section
        public var attributes: [StarGift.UniqueGift.Attribute]
        public var selected: StarGift.UniqueGift.Attribute?
        
        public var effectiveBackdrop: StarGift.UniqueGift.Attribute?
        public var effectiveSymbol: StarGift.UniqueGift.Attribute?

        
        public var model: TelegramMediaFile
        public var index: Int32
        public var stableId: AnyHashable {
            return index
        }
        public init(mode: StarGift_Builder_Section, attributes: [StarGift.UniqueGift.Attribute], selected: StarGift.UniqueGift.Attribute? = nil, effectiveBackdrop: StarGift.UniqueGift.Attribute? = nil, effectiveSymbol: StarGift.UniqueGift.Attribute? = nil, model: TelegramMediaFile, index: Int32) {
            self.mode = mode
            self.attributes = attributes
            self.selected = selected
            self.effectiveBackdrop = effectiveBackdrop
            self.effectiveSymbol = effectiveSymbol
            self.model = model
            self.index = index
        }
    }
    
 
    fileprivate let mode: StarGift_Builder_Section
    fileprivate let tableView: TableView = TableView()
    
    private var entries: [Entry] = []
    
    public init(mode: StarGift_Builder_Section) {
        self.mode = mode
        super.init()
    }
    
    public override func viewDidResized(_ size: NSSize) {
        super.viewDidResized(size)
        tableView.frame = bounds
    }
    
    public func set(model: TelegramMediaFile, attrs: [StarGift.UniqueGift.Attribute], selected: StarGift.UniqueGift.Attribute?, arguments: Arguments, state: State, animated: Bool) {
        let chunks = attrs.chunks(3)
        var index: Int32 = 0
        
        
        var entries: [Entry] = []
        for chunk in chunks {
            entries.append(.init(mode: self.mode, attributes: chunk, selected: selected, effectiveBackdrop: state.selectedBackdrop ?? state.firstBackdrop, effectiveSymbol: state.selectedSymbol ?? state.firstSymbol, model: model, index: index))
            index += 1
        }
        let size = frame.size
        
        let (deleted,inserted,updated) = proccessEntriesWithoutReverse(self.entries, right: entries, { entry -> TableRowItem in
            return AttrRowItem(size, stableId: entry.stableId, entry: entry, arguments: arguments, model: model)
        })
        
        let transition = TableUpdateTransition(deleted: deleted, inserted: inserted, updated: updated, animated: animated, state: .none(nil), grouping: true, animateVisibleOnly: true, searchState: nil)

        self.tableView.merge(with: transition)
        
        self.entries = entries
        
    }
    public override var supportSwipes: Bool {
        return true
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.getBackgroundColor = {
            theme.colors.listBackground
        }
        
        tableView.contentInsets = NSEdgeInsets(top: 112, left: 0, bottom: 20, right: 0)
        tableView.frame = bounds
        addSubview(tableView)
        
        backgroundColor = .clear
        
        readyOnce()
        
    }
}

private final class GridRowItem : GeneralRowItem {
    fileprivate let state: State
    fileprivate let arguments: Arguments
    public init(_ initialSize: NSSize, stableId: AnyHashable, state: State, arguments: Arguments) {
        self.state = state
        self.arguments = arguments
        super.init(initialSize, height: 350, stableId: stableId)
    }

    public override var accessibilityLabel: String? {
        return state.selected.accessibilityTitle
    }
    
    public override func viewClass() -> AnyClass {
        return GridRowItemView.self
    }
}

private final class GridRowItemView : GeneralRowView {
    public let controller: SectionViewController
    private let header = BuilderTabsView(frame: .zero)
    public required init(frame frameRect: NSRect) {
        controller = .init(sections: [
            .init(title: { return "" }, controller: GridController(mode: .models)),
            .init(title: { "" }, controller: GridController(mode: .backdrops)),
            .init(title: { "" }, controller: GridController(mode: .symbols))
        ], selected: 0, hasBar: false)
        
        controller._frameRect = NSMakeRect(16, 0, frameRect.width - 32, frameRect.height)

        super.init(frame: frameRect)
        addSubview(controller.view)
        addSubview(header)
        controller.selectionUpdateHandler = { [weak self] index in
            guard let item = self?.item as? GridRowItem,
                  item.state.selected.rawValue != index,
                  let section = StarGift_Builder_Section(rawValue: index) else { return }
            item.arguments.toggleSection(section)
        }
        controller.selectorPositionHandler = { [weak self] position, animated in
            self?.header.updateSelection(position: position, animated: animated)
        }
        
        controller.genericView._backgroundColor = theme.colors.listBackground
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        controller.view.frame = NSMakeRect(16, 0, frame.width - 32, frame.height)
        header.frame = NSMakeRect(0, 0, frame.width, 112)
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? GridRowItem else {
            return
        }
        
        
        let models = controller.sections[StarGift_Builder_Section.models.rawValue].controller as? GridController
        let backdrops = controller.sections[StarGift_Builder_Section.backdrops.rawValue].controller as? GridController
        let symbols = controller.sections[StarGift_Builder_Section.symbols.rawValue].controller as? GridController
        
        let modelAttr = item.state.selectedModel ?? item.state.attributes.filter({ $0.attributeType == .model }).first
        
        
        var modelFile: TelegramMediaFile?
        switch modelAttr {
        case .model(_, let file, _, _):
            modelFile = file
        default:
            break
        }
        
        guard let modelFile else {
            return
        }
        
        
        models?.set(model: modelFile, attrs: item.state.filteredModels, selected: item.state.selectedModel, arguments: item.arguments, state: item.state, animated: animated)
        backdrops?.set(model: modelFile, attrs: item.state.attributes.filter({ $0.attributeType == .backdrop }), selected: item.state.selectedBackdrop, arguments: item.arguments, state: item.state, animated: animated)
        symbols?.set(model: modelFile, attrs: item.state.attributes.filter({ $0.attributeType == .pattern }), selected: item.state.selectedSymbol, arguments: item.arguments, state: item.state, animated: animated)

        layout()
        header.update(state: item.state, arguments: item.arguments, animated: animated)
        controller.select(Int(item.state.selected.rawValue), animated && !GiftBuilderMotion.reduceMotion)
        
    }

    override func scrollWheel(with event: NSEvent) {
        guard let item = item as? GridRowItem,
              let page = controller.sections[item.state.selected.rawValue].controller as? GridController else { return }
        page.tableView.scrollWheel(with: event)
    }
}

private final class BuilderTabsView: View {
    private let edge = EdgeEffectView(frame: .zero)
    private let segments = GlassSegmentView(frame: .zero)
    private let info = TextView()
    private var arguments: Arguments?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.masksToBounds = false
        edge.isEventLess = true
        addSubview(edge)
        addSubview(segments)
        addSubview(info)
        info.isSelectable = false
        segments.didSelect = { [weak self] index in
            if let section = StarGift_Builder_Section(rawValue: index) {
                self?.arguments?.toggleSection(section)
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateSelection(position: CGFloat, animated: Bool) {
        segments.setSelection(position: position, animated: animated && !GiftBuilderMotion.reduceMotion)
    }

    func update(state: State, arguments: Arguments, animated: Bool) {
        self.arguments = arguments
        segments.updateLocalizationAndTheme(theme: theme)
        segments.set(titles: [strings().starGiftModelBuilderModels, strings().starGiftModelBuilderBackdrops, strings().starGiftModelBuilderSymbols], selected: state.selected.rawValue, animated: animated && !GiftBuilderMotion.reduceMotion)
        segments.setFrameSize(segments.contentSize)
        let text = NSMutableAttributedString()
        if state.hasCraftableModels {
            let count = state.modelFilter == .primary ? state.primaryModelsCount : state.craftableModelsCount
            let current = state.modelFilter == .primary ? strings().starGiftModelBuilderPrimary : strings().starGiftModelBuilderCraftable
            let other = state.modelFilter == .primary ? strings().starGiftModelBuilderCraftable : strings().starGiftModelBuilderPrimary
            text.append(.initialize(string: strings().starGiftModelBuilderCollectionFeatures(count, current).trimmingCharacters(in: .whitespacesAndNewlines), color: theme.colors.listGrayText, font: .normal(.text)))
            text.append(.initialize(string: "\n", color: theme.colors.listGrayText, font: .normal(.text)))
            let link = NSAttributedString.initialize(string: strings().starGiftModelBuilderViewOtherModels(other), color: theme.colors.accent, font: .normal(.text))
            let range = NSRange(location: text.length, length: link.length)
            text.append(link)
            text.addAttribute(.link, value: "toggle://filter", range: range)
        } else {
            text.append(.initialize(string: strings().starGiftModelBuilderCollectionFeaturesOther(state.attributes.filter { $0.attributeType == .model }.count), color: theme.colors.listGrayText, font: .normal(.text)))
        }
        let layout = TextViewLayout(text, maximumNumberOfLines: 3, alignment: .center)
        layout.measure(width: max(1, frame.width - 32))
        layout.interactions = TextViewInteractions(processURL: { [weak arguments] _ in
            arguments?.toggleModelFilter()
        })
        GiftBuilderMotion.updateText(info, layout: layout, animated: animated)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        segments.centerX(y: 12)
        info.centerX(y: segments.frame.maxY + 10)
        let rect = NSMakeRect(0, 0, frame.width, frame.height + 24)
        edge.frame = rect
        let blur = System.blurEnabled ? EdgeEffectView.Blur(rect: rect, edgeSize: 40) : nil
        edge.update(color: theme.colors.listBackground, blur: blur, edge: .bottom, edgeSize: 40, rect: rect, transition: .immediate)
    }
}

private final class HeaderItem : GeneralRowItem {
    
    
    public class ActionItem {
        public var context: (any AccountContextProtocol)
        public var title: TextViewLayout
        public var subtext: TextViewLayout
        public var action:()->Void
        public var size: NSSize = .zero
        public let rarity: StarGift.UniqueGift.Attribute.Rarity

        public init(context: (any AccountContextProtocol), rarity: StarGift.UniqueGift.Attribute.Rarity, title: String, subtext: String, action: @escaping () -> Void) {
            self.context = context

            self.title = .init(.initialize(string: title, color: .white, font: .medium(.text)), maximumNumberOfLines: 1)
            self.subtext = .init(.initialize(string: subtext, color: NSColor.white.withAlphaComponent(0.75), font: .normal(.small)), maximumNumberOfLines: 1)
            self.action = action
            self.rarity = rarity
        }
        
        public func measure(width: CGFloat) {
            self.title.measure(width: width - 10)
            self.subtext.measure(width: width - 10)

            self.size = NSMakeSize(width, 5 + title.layoutSize.height + 5 + subtext.layoutSize.height + 5)
        }
    }
    
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let title: TextViewLayout
    fileprivate let info: TextViewLayout
    fileprivate let arguments:Arguments
    fileprivate let attributes: [StarGift.UniqueGift.Attribute]
    
    fileprivate var patterns:[(String, TelegramMediaFile)] = []
    fileprivate var backdrops:[(String, StarGift.UniqueGift.Attribute)] = []
    fileprivate var models:[(String, StarGift.UniqueGift.Attribute)] = []

    private var patternIndex: Int = 0
    private var backdropIndex: Int = 0
    private var modelIndex: Int = 0
    
    
    public let uniqueGift: StarGift.UniqueGift?
    public let state: State
    
    public var actions: [ActionItem] = []
    
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: (any AccountContextProtocol), arguments: Arguments, state: State, attributes: [StarGift.UniqueGift.Attribute]) {
        self.arguments = arguments
        self.context = context
        self.attributes = attributes
        self.state = state
        
        self.uniqueGift = state.gift.unique
        
        self.patterns = attributes.compactMap { attribute in
            switch attribute {
            case let .pattern(name, file, _):
                return (name, file)
            default:
                return nil
            }
        }
        
        self.backdrops = attributes.compactMap { attribute in
            switch attribute {
            case let .backdrop(name, _, _, _, _, _, _):
                return (name, attribute)
            default:
                return nil
            }
        }
        
        self.models = attributes.compactMap { attribute in
            switch attribute {
            case let .model(name, _, _, _):
                return (name, attribute)
            default:
                return nil
            }
        }
        
        self.title = .init(.initialize(string: state.gift.title, color: .white, font: .medium(18)))
        self.info = .init(.initialize(string: state.mode == .random ? strings().starGiftModelBuilderRandomizeTraits : strings().starGiftModelBuilderSelectedTraits, color: NSColor.white.withAlphaComponent(0.8), font: .normal(.text)), alignment: .center)
        
       

        if let pattern = state.selectedSymbol {
            patternIndex = patterns.firstIndex(where: { $0.1.fileId == pattern.file?.fileId }) ?? 0
        } else {
            patternIndex = 0
        }
        if let backdrop = state.selectedBackdrop {
            backdropIndex = backdrops.firstIndex(where: { $0.1 == backdrop }) ?? 0
        } else {
            backdropIndex = 0
        }
        if let model = state.selectedModel {
            modelIndex = models.firstIndex(where: { $0.1 == model }) ?? 0
        } else {
            modelIndex = 0
        }
        
        super.init(initialSize, stableId: stableId)
        
        makeNextPattern()
    }
    
    public func makeNextPattern() {
        
        actions = [.init(context: context, rarity: models[modelIndex].1.rarity, title: models[modelIndex].0, subtext: strings().starGiftModelBuilderSubtextModel, action: { [weak self] in
            self?.arguments.toggleSection(.models)
        }), .init(context: context, rarity: backdrops[backdropIndex].1.rarity, title: backdrops[backdropIndex].0, subtext: strings().starGiftModelBuilderSubtextBackdrop, action: { [weak self] in
            self?.arguments.toggleSection(.backdrops)
        }), .init(context: context, rarity: (state.selectedSymbol ?? state.firstSymbol)?.rarity ?? .permille(0), title: patterns[patternIndex].0, subtext: strings().starGiftModelBuilderSubtextSymbol, action: { [weak self] in
            self?.arguments.toggleSection(.symbols)
        })]
        
        let _ = self.makeSize(initialSize.width)
        
        self.redraw(animated: true)
    }
    
    public var model: TelegramMediaFile {
        switch self.models[self.modelIndex].1 {
        case let .model(_, file, _, _):
            return file
        default:
            fatalError()
        }
    }
    public var pattern: TelegramMediaFile {
        return self.patterns[self.patternIndex].1
    }
    
    public var patternColor: NSColor {
        let value = self.backdrops[self.backdropIndex].1
        switch value {
        case let .backdrop(_, _, _, _, patternColor, _, _):
            return NSColor(UInt32(bitPattern: patternColor))
        default:
            fatalError()
        }
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        self.title.measure(width: width - 40)
        self.info.measure(width: width - 40)
        
        
        for action in actions {
            action.measure(width: (width - 48) / 3)
        }
        

        return true
    }
    
    public override var height: CGFloat {
        return 304
    }

    public var glassTint: NSColor? {
        return backgroundContent.map { NSColor($0.colors.center) }
    }

    public override var accessibilityLabel: String? {
        return title.attributedString.string
    }

    public override var accessibilityValue: String? {
        return info.attributedString.string
    }

    public override func viewClass() -> AnyClass {
        return HeaderView.self
    }
    
    public var backgroundContent: UniqueGiftBackgroundContent? {
        switch self.backdrops[self.backdropIndex].1 {
        case let .backdrop(_, _, inner, outer, patternColor, _, _):
            return UniqueGiftBackgroundContent(colors: UniqueGiftColors(center: inner, edge: outer, pattern: patternColor), pattern: .file(self.pattern))
        default:
            return nil
        }
    }
}

private final class HeaderView: GeneralRowView {
    private let textView = GiftBuilderAnimatedText(frame: .zero)
    private let infoView = GiftBuilderAnimatedText(frame: .zero)
    private let dismiss = GiftBuilderButton(frame: NSMakeRect(16, 14, 36, 36))
    private let playView = GiftBuilderButton(frame: NSMakeRect(328, 14, 36, 36))
    private let backgroundView = GiftBuilderBackgroundView(frame: .zero)
    private let giftContainer = View(frame: NSMakeRect(0, 0, 124, 124))
    private var giftView: NSView?
    private var pendingGift: NSView?
    private var outgoingGift: NSView?
    private let giftReadyDisposable = MetaDisposable()
    private var modelId: MediaId?
    private var mode: State.Mode?
    private let actions = [ActionView(frame: .zero), ActionView(frame: .zero), ActionView(frame: .zero)]
    private var timer: SwiftSignalKit.Timer?

    private final class ActionView: Control {
        let glass = GiftBuilderGlassView(frame: .zero)
        private let title = GiftBuilderAnimatedText(frame: .zero)
        private let subtitle = GiftBuilderAnimatedText(frame: .zero)
        private let rarity = GiftBuilderAnimatedText(frame: .zero)

        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            layer?.masksToBounds = false
            addSubview(glass)
            for view in [title, subtitle, rarity] {
                addSubview(view)
            }
            rarity.padding = NSMakeSize(5, 2)
            stretchReferenceView = glass
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func update(item: HeaderItem.ActionItem, animated: Bool) {
            title.update(item.title, animated: animated)
            subtitle.update(item.subtext, animated: animated)
            let layout = TextViewLayout(.initialize(string: item.rarity.badgeText, color: .white, font: .medium(9)), maximumNumberOfLines: 1, alignment: .center)
            layout.measure(width: max(1, item.size.width - 20))
            rarity.update(layout, animated: animated)
            rarity.layer?.cornerRadius = rarity.frame.height / 2
            rarity.backgroundColor = NSColor.white.withAlphaComponent(0.3)
            rarity.layer?.borderWidth = 1
            rarity.layer?.borderColor = NSColor.white.withAlphaComponent(0.65).cgColor
            setAccessibilityLabel("\(item.subtext.attributedString.string): \(item.title.attributedString.string), \(item.rarity.badgeText)")
            setSingle(handler: { [weak item] _ in item?.action() }, for: .Click)
            needsLayout = true
        }

        override func layout() {
            super.layout()
            glass.frame = bounds
            glass.layout()
            rarity.setFrameOrigin(NSMakePoint(frame.width - rarity.frame.width - 4, -rarity.frame.height / 2))
            title.centerX(y: 11)
            subtitle.centerX(y: 31)
        }
    }

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(backgroundView)
        addSubview(giftContainer)
        addSubview(textView)
        addSubview(infoView)
        addSubview(dismiss)
        addSubview(playView)
        for action in actions { addSubview(action) }
        giftContainer.layer?.masksToBounds = false
        backgroundView.onReveal = { [weak self] content, reveal, animated in
            guard let self else { return }
            let tint = NSColor(content.colors.center)
            for glass in [self.dismiss.glass, self.playView.glass] + self.actions.map({ $0.glass }) {
                glass.update(tint: tint, coordinateView: self, reveal: reveal, animated: animated)
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        timer?.invalidate()
        giftReadyDisposable.dispose()
    }

    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? HeaderItem else { return }
        let hadModel = modelId != nil
        let animated = hadModel
        dismiss.updateIcon(TelegramThemeHooks.shared.image(.iconPipClose).precomposed(.white), size: NSMakeSize(18, 18), animated: false)
        dismiss.setAccessibilityLabel(strings().voiceOverCommonClose)
        dismiss.setSingle(handler: { [weak item] _ in item?.arguments.dismiss() }, for: .Click)
        if mode != item.state.mode {
            let image = TelegramThemeHooks.shared.image(item.state.mode == .custom ? .iconVideoPlayerPlay : .iconVideoPlayerPause).precomposed(.white)
            playView.updateIcon(image, size: NSMakeSize(14, 14), animated: animated)
            mode = item.state.mode
        }
        playView.setAccessibilityLabel(item.state.mode == .custom ? strings().starGiftModelBuilderRandomizeTraits : strings().starGiftModelBuilderSelectedTraits)
        playView.setSingle(handler: { [weak item] _ in item?.arguments.toggleMode() }, for: .Click)
        textView.update(item.title, animated: animated)
        infoView.update(item.info, animated: animated)
        for (view, action) in zip(actions, item.actions) {
            view.update(item: action, animated: animated)
        }
        updateLayout(size: frame.size, transition: .immediate)
        updateBackground(animated: animated)
        updateGift(item: item, animated: animated)
        timer?.invalidate()
        timer = nil
        if item.state.mode == .random {
            timer = SwiftSignalKit.Timer(timeout: 2.5, repeat: true, completion: { [weak self] in
                guard let self, self.window != nil, !self.visibleRect.isEmpty,
                      let item = self.item as? HeaderItem else { return }
                item.arguments.makeNextPattern()
            }, queue: .mainQueue())
            timer?.start()
        }
    }

    private func updateGift(item: HeaderItem, animated: Bool) {
        guard modelId != item.model.fileId else { return }
        modelId = item.model.fileId
        giftReadyDisposable.set(nil)
        pendingGift?.removeFromSuperview()
        pendingGift = nil
        outgoingGift?.removeFromSuperview()
        outgoingGift = nil
        let current = StarsHooks.shared.makeStickerView(giftContainer.bounds)
        (current as? Control)?.scaleOnClick = true
        (current as? Control)?.tooltipOnclick = true
        (current as? StarsStickerView)?.updateStarsSticker(file: item.model, size: giftContainer.bounds.size, context: item.context, colors: [], playback: .standard, animated: false)
        if animated, giftView != nil, let sticker = current as? StarsStickerView {
            current.layer?.opacity = 0
            (current as? View)?.userInteractionEnabled = false
            pendingGift = current
            giftContainer.addSubview(current)
            giftReadyDisposable.set((sticker.starsStickerReady
            |> filter { $0 }
            |> take(1)
            |> deliverOnMainQueue).start(next: { [weak self, weak current] _ in
                guard let self, let current, self.pendingGift === current else { return }
                self.pendingGift = nil
                self.showGift(current, animated: true)
            }))
        } else {
            giftContainer.addSubview(current)
            showGift(current, animated: false)
        }
    }

    private func showGift(_ current: NSView, animated: Bool) {
        let old = giftView
        giftView = current
        current.layer?.opacity = 1
        (current as? View)?.userInteractionEnabled = true
        if animated, let old {
            outgoingGift = old
            (old as? View)?.userInteractionEnabled = false
            old.layer?.animateAlpha(from: CGFloat(old.layer?.presentation()?.opacity ?? 1), to: 0, duration: 0.22, removeOnCompletion: false, completion: { [weak self, weak old] _ in
                old?.removeFromSuperview()
                if self?.outgoingGift === old { self?.outgoingGift = nil }
            })
            current.layer?.animateAlpha(from: 0, to: 1, duration: 0.3)
            if !GiftBuilderMotion.reduceMotion {
                old.layer?.animateScaleCenter(from: old.layer?.presentation()?.transform.m11 ?? 1, to: 0.86, duration: 0.22, removeOnCompletion: false)
                current.layer?.animateScaleSpring(from: 0.8, to: 1, duration: 0.6)
                current.layer?.animatePosition(from: NSMakePoint(0, 12), to: .zero, duration: 0.5, timingFunction: .spring, additive: true)
            }
        } else {
            old?.removeFromSuperview()
        }
    }

    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        backgroundView.frame = size.bounds
        dismiss.frame = NSMakeRect(16, 14, 36, 36)
        playView.frame = NSMakeRect(size.width - 52, 14, 36, 36)
        dismiss.layout()
        playView.layout()
        giftContainer.centerX(y: 26)
        textView.centerX(y: 162)
        infoView.centerX(y: 190)
        let width = (size.width - 48) / 3
        for (index, action) in actions.enumerated() {
            action.frame = NSMakeRect(16 + CGFloat(index) * (width + 8), 232, width, 56)
            action.layout()
        }
    }

    override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }

    private func updateBackground(animated: Bool) {
        guard let item = item as? HeaderItem, let content = item.backgroundContent else { return }
        backgroundView.update(context: item.context, content: content, center: NSMakePoint(frame.width / 2, giftContainer.frame.midY + 16), animated: animated)
    }
}


private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let dismiss:()->Void
    public let toggleMode: ()->Void
    public let toggleSection:(StarGift_Builder_Section)->Void
    public let selectAttribute:(StarGift.UniqueGift.Attribute, StarGift_Builder_Section)->Void
    public let makeNextPattern:()->Void
    public let toggleModelFilter:()->Void
    public init(context: (any AccountContextProtocol), dismiss:@escaping()->Void, toggleMode:@escaping()->Void, toggleSection: @escaping(StarGift_Builder_Section)->Void, selectAttribute:@escaping(StarGift.UniqueGift.Attribute, StarGift_Builder_Section)->Void, makeNextPattern:@escaping()->Void, toggleModelFilter:@escaping()->Void) {
        self.context = context
        self.dismiss = dismiss
        self.toggleMode = toggleMode
        self.toggleSection = toggleSection
        self.selectAttribute = selectAttribute
        self.makeNextPattern = makeNextPattern
        self.toggleModelFilter = toggleModelFilter
    }
}

private struct State : Equatable {
    public enum Mode {
        case random
        case custom
    }
    public enum ModelFilter {
        case primary
        case craftable
    }
    public var mode: Mode = .random
    public var gift: StarGift
    public var attributes: [StarGift.UniqueGift.Attribute] = []
    public var isLoading: Bool = true

    public var selected: StarGift_Builder_Section
    public var modelFilter: ModelFilter = .primary

    public var selectedModel: StarGift.UniqueGift.Attribute?
    public var selectedBackdrop: StarGift.UniqueGift.Attribute?
    public var selectedSymbol: StarGift.UniqueGift.Attribute?

    public var hasCraftableModels: Bool {
        return attributes.contains { attr in
            if case let .model(_, _, _, crafted) = attr {
                return crafted
            }
            return false
        }
    }

    public var filteredModels: [StarGift.UniqueGift.Attribute] {
        let models = attributes.filter { $0.attributeType == .model }
        guard hasCraftableModels else { return models }
        return models.filter { attr in
            if case let .model(_, _, _, crafted) = attr {
                return modelFilter == .craftable ? crafted : !crafted
            }
            return false
        }
    }

    public var primaryModelsCount: Int {
        return attributes.filter { attr in
            if case let .model(_, _, _, crafted) = attr {
                return !crafted
            }
            return false
        }.count
    }

    public var craftableModelsCount: Int {
        return attributes.filter { attr in
            if case let .model(_, _, _, crafted) = attr {
                return crafted
            }
            return false
        }.count
    }

    public var firstBackdrop: StarGift.UniqueGift.Attribute? {
        return self.attributes.first(where: { $0.attributeType == .backdrop })
    }
    public var firstSymbol: StarGift.UniqueGift.Attribute? {
        return self.attributes.first(where: { $0.attributeType == .pattern })
    }

    public var randomBackdrop: StarGift.UniqueGift.Attribute? {
        return self.attributes.filter({ $0.attributeType == .backdrop }).randomElement()
    }
    public var randomModel: StarGift.UniqueGift.Attribute? {
        return self.attributes.filter({ $0.attributeType == .model }).randomElement()
    }
    public var randomSymbol: StarGift.UniqueGift.Attribute? {
        return self.attributes.filter({ $0.attributeType == .pattern }).randomElement()
    }
}


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []

    let sectionId:Int32 = 0
    var index: Int32 = 0

    if state.isLoading {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("loading"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            return GeneralLoadingRowItem(initialSize, stableId: stableId, viewType: .singleItem)
        }))
        return entries
    }

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("header"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return HeaderItem(initialSize, stableId: stableId, context: arguments.context, arguments: arguments, state: state, attributes: state.attributes)
    }))

    index += 1

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("grid"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return GridRowItem(initialSize, stableId: stableId, state: state, arguments: arguments)
    }))

    return entries
}

public func StarGift_ModelBuilderController(context: (any AccountContextProtocol), gift: StarGift, giftId: Int64, defaultMode: StarGift_Builder_Section = .models, onlyCraftedModels: Bool = false) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    let initialState = State(gift: gift, selected: defaultMode, modelFilter: onlyCraftedModels ? .craftable : .primary)

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    var getController:(()->ViewController?)? = nil
    var close:(()->Void)? = nil
    var window:Window {
        get {
            return getController?()?.window ?? context.window
        }
    }

    let arguments = Arguments(context: context, dismiss: {
        close?()
    }, toggleMode: {
        updateState { current in
            var current = current
            current.mode = current.mode == .custom ? .random : .custom
            
            if current.mode == .random {
                current.selectedModel = current.randomModel
                current.selectedBackdrop = current.randomBackdrop
                current.selectedSymbol = current.randomSymbol
            }
            
            return current
        }
    }, toggleSection: { value in
        updateState { current in
            var current = current
            current.selected = value
            return current
        }
    }, selectAttribute: { attr, mode in
        updateState { current in
            var current = current
            switch mode {
            case .models:
                current.selectedModel = attr
            case .backdrops:
                current.selectedBackdrop = attr
            case .symbols:
                current.selectedSymbol = attr
            }
            current.mode = .custom
            return current
        }
    }, makeNextPattern: {
        updateState { current in
            var current = current

            if current.mode == .random {
                current.selectedModel = current.randomModel
                current.selectedBackdrop = current.randomBackdrop
                current.selectedSymbol = current.randomSymbol
            }

            return current
        }
    }, toggleModelFilter: {
        updateState { current in
            var current = current
            current.modelFilter = current.modelFilter == .primary ? .craftable : .primary
            current.selected = .models
            return current
        }
    })
    
    actionsDisposable.add((context.engine.payments.getStarGiftUpgradeAttributes(giftId: giftId)
    |> deliverOnMainQueue).startStrict(next: { attributes in
        if let attributes = attributes {
            for attribute in attributes {
                if let file = attribute.file {
                    actionsDisposable.add(freeMediaFileInteractiveFetched(context: context, fileReference: .standalone(media: file)).start())
                }
            }
            updateState { current in
                var current = current

                current.attributes = attributes
                current.isLoading = false

                switch gift {
                case let .unique(uniqueGift):
                    for attribute in uniqueGift.attributes {
                        switch attribute {
                        case .backdrop:
                            if let index = current.attributes.firstIndex(where: { $0.name == attribute.name }) {
                                current.selectedBackdrop = current.attributes[index]
                            }
                        case .model:
                            if let index = current.attributes.firstIndex(where: { $0.name == attribute.name }) {
                                current.selectedModel = current.attributes[index]
                            }
                        case .pattern:
                            if let index = current.attributes.firstIndex(where: { $0.name == attribute.name }) {
                                current.selectedSymbol = current.attributes[index]
                            }
                        default:
                            break
                        }
                        if let index = current.attributes.firstIndex(where: { $0.name == attribute.name }) {
                            current.attributes.move(at: index, to: 0)
                        }
                    }
                    current.mode = .custom
                default:
                    break
                }

                if current.mode == .random {
                    current.selectedModel = current.randomModel
                    current.selectedBackdrop = current.randomBackdrop
                    current.selectedSymbol = current.randomSymbol
                }

                return current
            }
        }
    }))

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: "")
    controller.analyticsScreen = .giftsAttributes
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }

//    let modalInteractions = ModalInteractions(acceptTitle: "OK", accept: { [weak controller] in
//        _ = controller?.returnKeyAction()
//    }, singleButton: true)
    
    let modalController = InputDataModalController(controller, modalInteractions: nil, size: NSMakeSize(380, 654))
    modalController._hasBorder = false
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    return modalController

}

