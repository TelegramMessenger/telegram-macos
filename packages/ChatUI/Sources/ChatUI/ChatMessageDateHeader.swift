import Cocoa
import TGUIKit
import TelegramCore
import CalendarUtils
import Postbox
import ChatHistoryModel
import InAppSettings
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import SwiftSignalKit




private let timezoneOffset: Int32 = {
    let nowTimestamp = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
    var now: time_t = time_t(nowTimestamp)
    var timeinfoNow: tm = tm()
    localtime_r(&now, &timeinfoNow)
    return Int32(timeinfoNow.tm_gmtoff)
}()

private let formatter = DateFormatter()

private func chatDateFormat(languageCode: String, withYear: Bool) -> String {
    let fixed = withYear ? "dd MMMM yyyy" : "dd MMMM"
    guard languageCode != "en", let localized = DateFormatter.dateFormat(fromTemplate: withYear ? "dMMMMyyyy" : "dMMMM", options: 0, locale: Locale(identifier: languageCode)) else {
        return fixed
    }
    var fields = ""
    var quoted = false
    for char in localized {
        if char == "'" {
            quoted.toggle()
        } else if !quoted {
            fields.append(char)
        }
    }
    guard let day = fields.firstIndex(of: "d"), let month = fields.firstIndex(of: "M"), month < day else {
        return fixed
    }
    return localized
}
private let granularity: Int32 = 60 * 60 * 24



func chatDateMessageRange(timestamp: Int32, timeDifference: TimeInterval, calendar: Calendar = .current) -> (min: Int32, max: Int32)? {
    guard let interval = calendar.dateInterval(of: .day, for: Date(timeIntervalSince1970: TimeInterval(timestamp))) else {
        return nil
    }
    let lower = ceil(interval.start.timeIntervalSince1970 + timeDifference)
    let upper = ceil(interval.end.timeIntervalSince1970 + timeDifference) - 1
    guard lower > 0, upper < Double(Int32.max), lower <= upper else {
        return nil
    }
    return (Int32(lower), Int32(upper))
}

public class ChatDateStickItem : TableStickItem {
    
    private let entry:ChatHistoryEntry
    public let timestamp:Int32
    fileprivate let chatInteraction:ChatInteraction?
    public let isBubbled: Bool
    public let layout:TextViewLayout
    public let presentation: TelegramPresentationTheme
    
    public var monoforumState: MonoforumUIState? {
        return entry.additionalData.monoforumState
    }
    
    public init(_ initialSize:NSSize, _ entry:ChatHistoryEntry, interaction: ChatInteraction, theme: TelegramPresentationTheme) {
        self.entry = entry
        self.isBubbled = entry.renderType == .bubble
        self.chatInteraction = interaction
        self.presentation = theme
        if case let .DateEntry(index, _, _, _) = entry {
            self.timestamp = index.timestamp
        } else {
            fatalError()
        }
        
        let nowTimestamp = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
        
        var t: time_t = time_t(timestamp)
        var timeinfo: tm = tm()
        localtime_r(&t, &timeinfo)
        
        var now: time_t = time_t(nowTimestamp)
        var timeinfoNow: tm = tm()
        localtime_r(&now, &timeinfoNow)
        
        var text: String
        if timeinfo.tm_year == timeinfoNow.tm_year && timeinfo.tm_yday == timeinfoNow.tm_yday {
            
            switch interaction.mode {
            case .scheduled:
                text = strings().chatDateScheduledForToday
            default:
                text = strings().dateToday
            }
            
        } else {
            let dateFormatter = formatter
            
            dateFormatter.locale = appAppearance.locale
            dateFormatter.calendar = Calendar.current
            dateFormatter.dateFormat = chatDateFormat(languageCode: appAppearance.languageCode, withYear: timeinfoNow.tm_year != timeinfo.tm_year)
            let dateString = dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
            switch interaction.mode {
            case .scheduled:
                if timestamp - 2147460000 > 0 {
                    text = strings().chatDateScheduledUntilOnline
                } else {
                    text = strings().chatDateScheduledFor(dateString)
                }
            default:
                text = dateString
            }
        }
        
        
        self.layout = TextViewLayout(.initialize(string: text, color: TelegramUtilsHooks.shared.isLite(.blur) ? presentation.chatServiceItemTextColor : presentation.colors.text, font: .medium(presentation.fontSize)), maximumNumberOfLines: 1, truncationType: .end, alignment: .center)

        
        super.init(initialSize)
    }
    
    fileprivate var messageCountLocation: SearchMessagesLocation? {
        guard let interaction = chatInteraction, !interaction.isLogInteraction, !interaction.isGlobalSearchMessage,
              interaction.peerId.namespace != Namespaces.Peer.SecretChat else {
            return nil
        }
        switch interaction.mode {
        case .history, .thread:
            break
        default:
            return nil
        }
        guard let range = chatDateMessageRange(timestamp: timestamp, timeDifference: interaction.interactionContext.timeDifference) else {
            return nil
        }
        return .peer(peerId: interaction.peerId, fromId: nil, tags: nil, reactions: nil, threadId: interaction.chatLocation.threadId, minDate: range.min, maxDate: range.max)
    }

    public var shouldBlurService: Bool {
        if TelegramUtilsHooks.shared.isLite(.blur) {
            return false
        }
        return presentation.shouldBlurService
    }
    
    public override var canBeAnchor: Bool {
        return false
    }
    
    public required init(_ initialSize: NSSize) {
        entry = .DateEntry(MessageIndex.absoluteLowerBound(), .list, theme, .init())
        timestamp = 0
        self.isBubbled = false
        self.layout = TextViewLayout(NSAttributedString())
        self.chatInteraction = nil
        self.presentation = theme
        super.init(initialSize)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth:CGFloat) -> Bool {
        let success = super.makeSize(width, oldWidth: oldWidth)
        layout.measure(width: width - 40)
        return success
    }
    
    public override var stableId: AnyHashable {
        return entry.stableId
    }
    
    public override var height: CGFloat {
        return 30
    }
    
    public override func viewClass() -> AnyClass {
        return ChatDateStickView.self
    }
    
    
}

public class ChatDateStickView : TableStickView {
    private let textView:TextView
    private let containerView = Control()
    private let contentView = View()
    private let countView = TextView()
    private let countDisposable = MetaDisposable()
    private var countLocation: SearchMessagesLocation?
    private var cachedCount: (value: Int, timestamp: CFAbsoluteTime)?
    private var countLayout: TextViewLayout?
    private var expanded = false
    private var scrollVisible = true
    private var dateTrackingArea: NSTrackingArea?
    private var requestId = 0
    private let glassView = LiquidGlassView(frame: .zero, hasShadow: true, hasBorder: true)
    private var appliedColors: (presentation: TelegramPresentationTheme, usesGlass: Bool)?
    public required init(frame frameRect: NSRect) {
        
        
        
        self.textView = TextView()
        self.textView.isSelectable = false
        self.textView.disableBackgroundDrawing = true
        self.textView.userInteractionEnabled = false
        self.textView.isEventLess = true
        self.countView.isSelectable = false
        self.countView.userInteractionEnabled = false
        self.countView.isEventLess = true
        self.contentView.isEventLess = true
        self.countView.disableBackgroundDrawing = true
        self.glassView.isEventLess = true
        super.init(frame: frameRect)
        layer?.masksToBounds = false
        containerView.layer?.masksToBounds = false
        addSubview(containerView)
        containerView.addSubview(glassView)
        containerView.addSubview(contentView)
        contentView.addSubview(textView)
        contentView.addSubview(countView)
        countView.layer?.opacity = 0
        containerView.set(handler: { [weak self] _ in
            self?.updateDateVisibility(animated: true)
            self?.showCachedCount()
        }, for: .Hover)
        containerView.set(handler: { [weak self] _ in
            self?.requestCount()
        }, for: .LongOver)
        containerView.set(handler: { [weak self] _ in
            self?.cancelCount()
            self?.updateDateVisibility(animated: true)
        }, for: .Normal)
        
        containerView.set(handler: { [weak self] _ in
            guard let self, let item = self.item as? ChatDateStickItem, let interaction = item.chatInteraction else { return }
            var ignore: Bool = false
            let table = item.table ?? (self.superview as? TableView)
            if let table {
                let row = table.visibleRows()
                if row.length > 0 {
                    let minRow = max(0, row.location)
                    let maxRow = min(table.count - 1, row.location + row.length - 1)
                    for i in minRow ... maxRow {
                        if let underItem = table.item(at: i) as? ChatDateStickItem, underItem.timestamp == item.timestamp {
                            ignore = true
                            break
                        }
                    }
                }
            }
            if self.header && !ignore {
                self.cancelCount()
                if let location = item.messageCountLocation, case let .peer(_, _, _, _, _, minDate?, _) = location {
                    interaction.jumpToDate(Date(timeIntervalSince1970: TimeInterval(minDate)))
                } else {
                    let timeDifference = interaction.mode == .scheduled ? 0 : interaction.interactionContext.timeDifference
                    interaction.jumpToDate(Date(timeIntervalSince1970: TimeInterval(item.timestamp) + timeDifference))
                }
                return
            }
            let canOpenCalendar: Bool
            switch interaction.mode {
            case .history, .thread:
                canOpenCalendar = true
            default:
                canOpenCalendar = false
            }
            if canOpenCalendar, !interaction.isLogInteraction, !interaction.isGlobalSearchMessage {
                let chatLocation = interaction.chatLocation
                if let controller = ChatNavigationHooks.shared.makeCalendarPopover(interaction.interactionContext, interaction.peerId, chatLocation.threadId, Date(timeIntervalSince1970: TimeInterval(item.timestamp)), { [weak interaction] date in
                    guard let interaction, interaction.chatLocation == chatLocation else { return }
                    interaction.jumpToDate(date)
                }) {
                    self.cancelCount()
                    showPopover(for: self.containerView, with: controller, edge: .maxY)
                    return
                }
            }
            if let location = item.messageCountLocation, case let .peer(_, _, _, _, _, minDate?, _) = location {
                interaction.jumpToDate(Date(timeIntervalSince1970: TimeInterval(minDate)))
            } else {
                let timeDifference = interaction.mode == .scheduled ? 0 : interaction.interactionContext.timeDifference
                interaction.jumpToDate(Date(timeIntervalSince1970: TimeInterval(item.timestamp) + timeDifference))
            }
        }, for: .Click)
    }
    
    deinit {
        countDisposable.dispose()
    }

    private func cancelCount(animated: Bool = true) {
        requestId += 1
        countDisposable.set(nil)
        setExpanded(false, animated: animated)
    }

    private func showCachedCount() {
        guard window != nil, containerView.layer?.opacity != 0,
              let item = item as? ChatDateStickItem, item.messageCountLocation == countLocation,
              let cachedCount, CFAbsoluteTimeGetCurrent() - cachedCount.timestamp < 30 else {
            return
        }
        setExpanded(true, animated: true)
    }

    private func requestCount() {
        guard window != nil, containerView.layer?.opacity != 0, containerView.controlState == .Hover,
              let item = item as? ChatDateStickItem, let interaction = item.chatInteraction,
              let location = countLocation, item.messageCountLocation == location else {
            return
        }
        if let cachedCount, CFAbsoluteTimeGetCurrent() - cachedCount.timestamp < 30 {
            showCachedCount()
            return
        }
        requestId += 1
        let currentRequestId = requestId
        countDisposable.set((chatDateMessageCount(context: interaction.interactionContext, location: location)
        |> deliverOnMainQueue).start(next: { [weak self] count in
            guard let self, self.requestId == currentRequestId,
                  let item = self.item as? ChatDateStickItem, item.messageCountLocation == location,
                  self.containerView.controlState == .Hover, let count, count > 0 else {
                return
            }
            self.cachedCount = (count, CFAbsoluteTimeGetCurrent())
            self.setExpanded(true, animated: true)
        }))
    }

    private func setExpanded(_ expanded: Bool, animated: Bool) {
        guard self.expanded != expanded, let item = item as? ChatDateStickItem else {
            return
        }
        if expanded, let cachedCount {
            let text = "(\(strings().statsGroupTopPosterMessagesOther(cachedCount.value)))"
            let layout = TextViewLayout(.initialize(string: text, color: TelegramUtilsHooks.shared.isLite(.blur) ? item.presentation.chatServiceItemTextColor : item.presentation.colors.text, font: .medium(item.presentation.fontSize)), maximumNumberOfLines: 1, truncationType: .end, alignment: .center)
            countLayout = layout
            updateLayout(size: frame.size, transition: .immediate)
        }
        self.expanded = expanded
        let animate = animated && !TelegramUtilsHooks.shared.isLite(.animations) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let transition: ContainedViewLayoutTransition = animate ? .animated(duration: 0.25, curve: .easeOut) : .immediate
        updateLayout(size: frame.size, transition: transition)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            cancelCount(animated: false)
        }
        updateTrackingAreas()
        updateDateVisibility(animated: false)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let dateTrackingArea {
            removeTrackingArea(dateTrackingArea)
            self.dateTrackingArea = nil
        }
        if header, window != nil {
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
            addTrackingArea(area)
            dateTrackingArea = area
        }
    }

    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateDateVisibility(animated: true)
    }

    public override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateDateVisibility(animated: true)
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        updateDateVisibility(animated: true)
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        return header && containerView.layer?.opacity == 0 ? nil : super.hitTest(point)
    }
    
    public override func mouseDown(with event: NSEvent) {
        guard header, let tableView = superview as? TableView else {
            super.mouseDown(with: event)
            return
        }
        
        tableView.documentView!.hitTest(tableView.documentView!.convert(event.locationInWindow, from: nil))?.mouseDown(with: event)
        
    }
    
    public override func mouseUp(with event: NSEvent) {
        guard header, let tableView = superview as? TableView else {
            super.mouseUp(with: event)
            return
        }

        tableView.documentView!.hitTest(tableView.documentView!.convert(event.locationInWindow, from: nil))?.mouseUp(with: event)
        
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public override func updateIsVisible(_ visible: Bool, animated: Bool) {
        scrollVisible = visible
        updateDateVisibility(animated: animated)
    }

    private func updateDateVisibility(animated: Bool) {
        let pointerNearDate: Bool
        if header, let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor {
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            pointerNearDate = containerView.frame.insetBy(dx: -12, dy: -6).intersection(bounds).contains(point)
        } else {
            pointerNearDate = false
        }
        let visible = scrollVisible || pointerNearDate
        let opacity: Float = visible ? 1 : 0
        if containerView.layer?.opacity != opacity {
            containerView.change(opacity: CGFloat(opacity), animated: animated)
        }
        if !visible {
            cancelCount(animated: false)
        }
    }
    
    
    public override var header: Bool {
        didSet {
            updateColors()
            if header != oldValue {
                updateTrackingAreas()
                updateDateVisibility(animated: false)
            }
        }
    }
    
    
    public override func updateColors() {
        super.updateColors()
        
        if let item = item as? ChatDateStickItem {
            var presentation = item.presentation
            if let table = item.table {
                table.enumerateItems(with: { item in
                    if let item = item as? ChatRowItem {
                        presentation = item.presentation
                        return false
                    } else if let item = item as? ChatDateStickItem {
                        presentation = item.presentation
                        return false
                    }
                    return true
                })
            }
            let usesGlass = !TelegramUtilsHooks.shared.isLite(.blur)
            if let appliedColors = self.appliedColors, appliedColors.presentation === presentation, appliedColors.usesGlass == usesGlass {
                return
            }
            self.appliedColors = (presentation, usesGlass)
            glassView.isHidden = !usesGlass
            glassView.updateLocalizationAndTheme(theme: presentation)
            containerView.backgroundColor = usesGlass ? .clear : presentation.chatServiceItemColor
            textView.backgroundColor = .clear
            textView.blurBackground = nil
        }
        
    }
    
    
    public override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        
        guard let item = item as? ChatDateStickItem else {
            return
        }
        
        let availableWidth = max(0, size.width - (item.monoforumState == .vertical ? 120 : 40))
        let dateWidth = min(item.layout.layoutSize.width, availableWidth)
        countLayout?.measure(width: max(0, availableWidth - dateWidth - 6))
        if let countLayout {
            countView.update(countLayout)
        }
        let countSize = countLayout?.layoutSize ?? .zero
        let countWidth = expanded && countSize.width > 0 ? countSize.width + 6 : 0
        let pillSize = NSMakeSize(dateWidth + countWidth + 16, item.layout.layoutSize.height + 6)
        let rect = NSRect(x: floor((size.width - pillSize.width) / 2) + (item.monoforumState == .vertical ? 40 : 0), y: floor((size.height - pillSize.height) / 2), width: pillSize.width, height: pillSize.height)
        containerView.layer?.cornerRadius = pillSize.height / 2
        contentView.layer?.cornerRadius = pillSize.height / 2
        glassView.cornerRadius = pillSize.height / 2
        transition.updateFrame(view: containerView, frame: rect)
        transition.updateFrame(view: glassView, frame: rect.size.bounds)
        glassView.updateLayout(size: rect.size, transition: transition)
        transition.updateFrame(view: contentView, frame: rect.size.bounds)
        transition.updateFrame(view: textView, frame: NSRect(x: 8, y: 3, width: dateWidth, height: item.layout.layoutSize.height))
        transition.updateFrame(view: countView, frame: NSRect(x: 8 + dateWidth + 6, y: expanded ? 3 : 11, width: countSize.width, height: countSize.height))
        transition.updateAlpha(view: countView, alpha: expanded ? 1 : 0)
    }

    public override func set(item: TableRowItem, animated: Bool) {
        if let item = item as? ChatDateStickItem {
            let previous = self.item as? ChatDateStickItem
            let location = item.messageCountLocation
            if previous?.chatInteraction !== item.chatInteraction || previous?.timestamp != item.timestamp || previous?.presentation !== item.presentation || countLocation != location {
                cancelCount(animated: false)
                cachedCount = nil
                countLayout = nil
                countLocation = location
            }
            textView.update(item.layout)
        }
        super.set(item: item, animated: animated)
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    public override func onInsert(_ animation: NSTableView.AnimationOptions, appearAnimated: Bool) {
        if let item = item as? ChatDateStickItem, !TelegramUtilsHooks.shared.isLite(.animations) {
            if item.isBubbled, appearAnimated {
                self.containerView.layer?.animateScaleSpring(from: 0.5, to: 1, duration: 0.4, bounce: false)
                self.containerView.layer?.animateAlpha(from: 0, to: 1, duration: 0.35)
            }
        }
    }
}
