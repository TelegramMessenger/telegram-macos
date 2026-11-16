import Cocoa
import TGUIKit
import CalendarUtils
import TelegramTheme
import GeneralRows
import Localization

public struct CalendarMonthInteractions {
    public let lowYear: Int
    public let canBeNoYear: Bool
    public let selectAction:(Date)->Void
    public let backAction:((Date)->Void)?
    public let nextAction:((Date)->Void)?
    public let changeYear: (Int32, Date)->Void
    public init(lowYear: Int, canBeNoYear: Bool, selectAction:@escaping (Date)->Void, backAction:((Date)->Void)? = nil, nextAction:((Date)->Void)? = nil, changeYear: @escaping(Int32, Date)->Void) {
        self.selectAction = selectAction
        self.backAction = backAction
        self.nextAction = nextAction
        self.changeYear = changeYear
        self.lowYear = lowYear
        self.canBeNoYear = canBeNoYear
    }
}

public final class CalendarMonthStruct {
    public let month:Date
    public let prevMonth:Date
    public let nextMonth:Date
    
    public let lastDayOfMonth:Int
    public let lastDayOfPrevMonth:Int
    public let lastDayOfNextMonth:Int
    
    public let currentStartDay:Int
    public var selectedDay:Int?
    
    public let components:DateComponents
    public let dayHandler:(Int)->Void
    public let onlyFuture: Bool
    public let limitedBy: Date?
    
    public let dayPreview:(Int)->NSView?
    public var isSelecting: Bool = false
    public var selectedRange: ClosedRange<Int>?
    public var fitsWeeks: Bool = false

    public var weeksCount: Int {
        return (currentStartDay - 1 + lastDayOfMonth + 6) / 7
    }
    
    public var linesCount: Int {
        switch mode {
        case .media:
            var count: Int = 0
            for i in 0 ..< 7 * 6 {
                if i + 1 < currentStartDay {
                    count += 1
                } else if (i + 2) - currentStartDay > lastDayOfMonth {
                } else {
                    count += 1
                }
            }
            let result = Int(ceil(Float(count) / 7))
            return result
        case .normal:
            return fitsWeeks ? weeksCount : 6
        }
       
    }
    
    public enum Mode {
        case media
        case normal
    }
    public let mode: Mode
    
    public init(month:Date, mode: Mode = .normal, selectDayAnyway: Bool, onlyFuture: Bool, limitedBy: Date?, dayHandler:@escaping (Int)->Void, dayPreview:@escaping(Int)->NSView? = { _ in return nil }) {
        self.month = month
        self.onlyFuture = onlyFuture
        self.limitedBy = limitedBy
        self.dayHandler = dayHandler
        self.prevMonth = CalendarUtils.stepMonth(-1, date: month)
        self.nextMonth = CalendarUtils.stepMonth(1, date: month)
        self.lastDayOfMonth = CalendarUtils.lastDay(ofTheMonth: month)
        self.lastDayOfPrevMonth = CalendarUtils.lastDay(ofTheMonth: prevMonth)
        self.lastDayOfNextMonth = CalendarUtils.lastDay(ofTheMonth: nextMonth)
        self.mode = mode
        self.dayPreview = dayPreview
        
        
        let calendar = Calendar(identifier: .gregorian)
        
//        calendar.timeZone = TimeZone(abbreviation: "UTC")!
        let components = calendar.dateComponents([.year, .month, .day], from: month)
        let firstDay = calendar.date(from: DateComponents(year: components.year, month: components.month, day: 1))!
        self.currentStartDay = (calendar.component(.weekday, from: firstDay) + 5) % 7 + 1
        
        if selectDayAnyway {
            selectedDay = components.day!
        } else {
            selectedDay = nil
        }
        
        self.components = components
    }

    public func isDayEnabled(_ day: Int, now: Date = Date()) -> Bool {
        guard (1 ... self.lastDayOfMonth).contains(day) else { return false }
        let calendar = Calendar(identifier: .gregorian)
        let selected = calendar.startOfDay(for: CalendarUtils.monthDay(day, date: self.month))
        let today = calendar.startOfDay(for: now)
        if self.onlyFuture {
            guard let maximum = calendar.date(byAdding: .year, value: 1, to: today), selected >= today, selected <= maximum else { return false }
        } else if selected > today {
            return false
        }
        if let limitedBy = self.limitedBy, selected > calendar.startOfDay(for: limitedBy) {
            return false
        }
        return true
    }
}

open class CalendarMonthView : View {
    private var month:CalendarMonthStruct?

    private var dayPreviews: [Int : NSView] = [:]
    private let rangeViews = View()
    private let dayPreviewsViews = View()
    private let dayViews = View()
    private let weekdaysView = View()
    private let containerView = View()

    open var navigationBarHeight: CGFloat = 56 {
        didSet {
            if navigationBarHeight != oldValue {
                needsLayout = true
            }
        }
    }

    private static let weekdaysHeight: CGFloat = 24
    public static let rowHeight: CGFloat = 42

    public static func fittingHeight(weeks: Int, navigationBarHeight: CGFloat = 56) -> CGFloat {
        return navigationBarHeight + weekdaysHeight + 4 + rowHeight * CGFloat(weeks)
    }
    private static let sideInset: CGFloat = 12

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(weekdaysView)
        addSubview(containerView)
        containerView.addSubview(rangeViews)
        containerView.addSubview(dayPreviewsViews)
        containerView.addSubview(dayViews)
        rangeViews.isEventLess = true
        weekdaysView.isEventLess = true
        backgroundColor = .clear
    }
    
    open override func scrollWheel(with event: NSEvent) {
        if let month = month {
            switch month.mode {
            case .media:
                super.scrollWheel(with: event)
            default:
                break
            }
        }
    }

    private func updateWeekdays() {
        weekdaysView.removeAllSubviews()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: appAppearance.language.languageCode)
        formatter.calendar = Calendar(identifier: .gregorian)
        let symbols = formatter.shortWeekdaySymbols ?? []
        guard symbols.count == 7 else { return }
        for symbol in Array(symbols[1...]) + [symbols[0]] {
            let label = TextView()
            label.userInteractionEnabled = false
            label.isSelectable = false
            let layout = TextViewLayout(.initialize(string: symbol.uppercased(), color: theme.colors.grayText, font: .normal(.small)), maximumNumberOfLines: 1, alignment: .center)
            layout.measure(width: 60)
            label.update(layout)
            weekdaysView.addSubview(label)
        }
    }
    
    open func layout(for month:CalendarMonthStruct) {
        dayPreviewsViews.removeAllSubviews()
        dayViews.removeAllSubviews()
        if self.month?.month != month.month {
            self.dayPreviews.removeAll()
        }
        if weekdaysView.subviews.isEmpty {
            updateWeekdays()
        }
        self.month = month

        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())

        for i in 0 ..< 7 * 6 {
            let day = TextButton()
            day.textOffset = NSMakePoint(0, 2)
            day.set(font: .normal(15), for: .Normal)
            day.scaleOnClick = true
            let current:Int
            
            if i + 1 < month.currentStartDay {
                current = (month.lastDayOfPrevMonth - month.currentStartDay) + i + 2
                day.isHidden = true
            } else if (i + 2) - month.currentStartDay > month.lastDayOfMonth {
                current = (i + 2) - (month.currentStartDay + month.lastDayOfMonth)
                day.isHidden = true
            } else {
                current = (i + 1) - month.currentStartDay + 1
                
                let skipDay = !month.isDayEnabled(current)
                let dayDate: Date = CalendarUtils.monthDay(current, date: month.month)
                let dayTimeinterval = dayDate.timeIntervalSince1970
                
                let dayPreview = self.dayPreviews[current] ?? month.dayPreview(Int(dayTimeinterval))
                if let dayPreview = dayPreview {
                    self.dayPreviews[current] = dayPreview
                    self.dayPreviewsViews.addSubview(dayPreview)
                }
                day.contextObject = current
                
                let inRange = month.selectedRange?.contains(current) == true
                let isSelected = !month.isSelecting && month.mode == .normal && month.selectedDay == current
                let isToday = calendar.startOfDay(for: dayDate) == today
                
                if !skipDay {
                    if dayPreview != nil || inRange || isSelected {
                        day.set(color: .white, for: .Normal)
                        day.set(color: .white, for: .Highlight)
                        day.set(font: .medium(15), for: .Normal)
                    } else if isToday {
                        day.set(color: theme.colors.accent, for: .Normal)
                        day.set(color: theme.colors.accent, for: .Highlight)
                        day.set(font: .medium(15), for: .Normal)
                    } else {
                        day.set(color: theme.colors.text, for: .Normal)
                        day.set(color: theme.colors.text, for: .Highlight)
                    }
                    if isSelected {
                        day.set(background: theme.colors.accent, for: .Normal)
                        day.set(background: theme.colors.accent, for: .Highlight)
                    } else if dayPreview != nil || inRange {
                        day.set(background: .clear, for: .Normal)
                        day.set(background: .clear, for: .Highlight)
                    } else {
                        day.set(background: .clear, for: .Normal)
                        day.set(background: theme.colors.grayBackground, for: .Highlight)
                    }
                   
                    day.set(handler: { [weak self] (control) in
                        if month.mode != .media {
                            month.selectedDay = current
                        }
                        month.dayHandler(current)
                        self?.layout(for: month)
                        
                    }, for: .Click)
                } else {
                    day.set(color: theme.colors.grayText, for: .Normal)
                    day.set(color: theme.colors.grayText, for: .Highlight)
                }
            }
            day.set(text: "\(current)", for: .Normal)
            
            dayViews.addSubview(day)
        }
        
        self.needsLayout = true
    }
    
    public func updateDayPreviews(animated: Bool) {
        guard let month else { return }
        layoutSubtreeIfNeeded()
        let animated = animated && window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for case let day as TextButton in dayViews.subviews {
            guard !day.isHidden, let current = day.contextObject as? Int, month.isDayEnabled(current), dayPreviews[current] == nil else { continue }
            let timestamp = Int(CalendarUtils.monthDay(current, date: month.month).timeIntervalSince1970)
            guard let preview = month.dayPreview(timestamp) else { continue }
            let previous: View?
            if animated, let bitmap = day.bitmapImageRepForCachingDisplay(in: day.bounds) {
                day.cacheDisplay(in: day.bounds, to: bitmap)
                let snapshot = View(frame: day.frame)
                snapshot.isEventLess = true
                snapshot.layer?.contents = bitmap.cgImage
                dayViews.addSubview(snapshot)
                previous = snapshot
            } else {
                previous = nil
            }
            dayPreviews[current] = preview
            dayPreviewsViews.addSubview(preview)
            preview.setFrameOrigin(day.frame.midX - preview.frame.width / 2, day.frame.midY - preview.frame.height / 2)
            day.set(background: .clear, for: .Normal)
            day.set(background: .clear, for: .Highlight)
            day.set(color: .white, for: .Normal)
            day.set(color: .white, for: .Highlight)
            day.set(font: .medium(15), for: .Normal)
            day.layoutSubtreeIfNeeded()
            if animated {
                preview.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                day.layer?.animateAlpha(from: 0, to: 1, duration: 0.16)
                previous?.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak previous] _ in
                    previous?.removeFromSuperview()
                })
            }
        }
    }

    open override func layout() {
        super.layout()

        let inset = CalendarMonthView.sideInset
        let cellWidth = floorToScreenPixels(backingScaleFactor, (frame.width - inset * 2) / 7)

        weekdaysView.frame = NSMakeRect(0, navigationBarHeight, frame.width, CalendarMonthView.weekdaysHeight)
        for (i, label) in weekdaysView.subviews.enumerated() {
            label.setFrameOrigin(NSMakePoint(inset + CGFloat(i) * cellWidth + floorToScreenPixels(backingScaleFactor, (cellWidth - label.frame.width) / 2), floorToScreenPixels(backingScaleFactor, (CalendarMonthView.weekdaysHeight - label.frame.height) / 2)))
        }

        let top = weekdaysView.frame.maxY
        containerView.frame = NSMakeRect(0, top, frame.width, max(0, frame.height - top))
        rangeViews.frame = containerView.bounds
        dayViews.frame = containerView.bounds
        dayPreviewsViews.frame = containerView.bounds

        guard let month = self.month else {
            return
        }

        let lines = CGFloat(month.linesCount)
        let rowHeight = month.fitsWeeks ? CalendarMonthView.rowHeight : floorToScreenPixels(backingScaleFactor, (containerView.frame.height - 4) / lines)
        let side = min(cellWidth, rowHeight) - 4

        var rowRanges: [Int: (first: NSRect, last: NSRect)] = [:]
        for i in 0 ..< dayViews.subviews.count {
            if let view = dayViews.subviews[i] as? TextButton {
                let column = CGFloat(i % 7)
                let row = CGFloat(i / 7)
                let cell = NSMakeRect(inset + column * cellWidth, 2 + row * rowHeight, cellWidth, rowHeight)
                view.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, cell.midX - side / 2), floorToScreenPixels(backingScaleFactor, cell.midY - side / 2), side, side)
                view.layer?.cornerRadius = side / 2
                if let currentDay = view.contextObject as? Int, !view.isHidden {
                    if let preview = self.dayPreviews[currentDay] {
                        preview.setFrameOrigin(floorToScreenPixels(backingScaleFactor, view.frame.midX - preview.frame.width / 2), floorToScreenPixels(backingScaleFactor, view.frame.midY - preview.frame.height / 2))
                    }
                    if month.selectedRange?.contains(currentDay) == true {
                        let key = i / 7
                        if let existing = rowRanges[key] {
                            rowRanges[key] = (existing.first, view.frame)
                        } else {
                            rowRanges[key] = (view.frame, view.frame)
                        }
                    }
                }
            }
        }

        rangeViews.removeAllSubviews()
        for (_, segment) in rowRanges {
            let band = View(frame: NSMakeRect(segment.first.minX, segment.first.minY, segment.last.maxX - segment.first.minX, segment.first.height))
            band.isEventLess = true
            band.backgroundColor = theme.colors.accent
            band.layer?.cornerRadius = segment.first.height / 2
            rangeViews.addSubview(band)
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}



open class CalendarMonthController: GenericViewController<CalendarMonthView> {
    public let interactions:CalendarMonthInteractions
    public let month:CalendarMonthStruct
    public let onlyFuture: Bool
    public let limitedBy: Date?
    public let lowYear: Int
    public let date: Date
    public init(_ month:Date, onlyFuture: Bool, limitedBy: Date?, selectDayAnyway: Bool, interactions:CalendarMonthInteractions, lowYear: Int = 2013, dayPreview: @escaping (Int) -> NSView? = { _ in nil }) {
        self.onlyFuture = onlyFuture
        self.limitedBy = limitedBy
        self.lowYear = lowYear
        self.date = month
        self.month = CalendarMonthStruct(month: month, selectDayAnyway: selectDayAnyway, onlyFuture: self.onlyFuture, limitedBy: self.limitedBy, dayHandler: { day in
            interactions.selectAction(CalendarUtils.monthDay(day, date: month))
        }, dayPreview: dayPreview)
        self.interactions = interactions
        
        super.init()
        self.bar = NavigationBarStyle(height: 56)
    }
    
    open override func getCenterBarViewOnce() -> TitledBarView {
        let formatter:DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: appAppearance.language.languageCode)
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "LLLL"
        let monthString:String = formatter.string(from: month.month)
        formatter.dateFormat = "yyyy"
        let yearString:String
        if CalendarUtils.isYearHidden(month.components.year!) {
            yearString = "—"
        } else {
            yearString = formatter.string(from: month.month)
        }
        
        let barView = CalendarMonthHeaderView(controller: self, title: monthString + " " + yearString, isPrevEnabled: isPrevEnabled, isNextEnabled: isNextEnabled, back: { [weak self] in
            if let backAction = self?.interactions.backAction, let month = self?.month.month {
                backAction(month)
            }
        }, next: { [weak self] in
            if let nextAction = self?.interactions.nextAction, let month = self?.month.month {
                nextAction(month)
            }
        })
        
        let lowYear = self.interactions.lowYear
        let canBeNoYear = self.interactions.canBeNoYear

        barView.titleMenu = { [weak self] in
            guard let `self` = self else {
                return nil
            }
            
            let nowTimestamp = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
            
            var now: time_t = time_t(nowTimestamp)
            var timeinfoNow: tm = tm()
            localtime_r(&now, &timeinfoNow)
            
             var items:[ContextMenuItem] = []
            
            if canBeNoYear {
                items.append(.init("—", handler: { [weak self] in
                    guard let `self` = self else {
                        return
                    }
                    self.interactions.changeYear(Int32(CalendarUtils.yearForNoYear), self.month.month)
                }))
            }
            
            for i in stride(from: 1900 + timeinfoNow.tm_year, to: Int32(lowYear) - 1, by: -1) {
                items.append(.init("\(i)", handler: { [weak self] in
                    guard let `self` = self else {
                        return
                    }
                    self.interactions.changeYear(i, self.month.month)
                }))
            }
            if !items.isEmpty && !self.onlyFuture {
                let menu = ContextMenu(betterInside: true)
                for item in items {
                    menu.addItem(item)
                }
                return menu
            }
            return nil
        }
        
        
        barView.showsChevron = !self.onlyFuture
        return barView
    }
    
    open var isNextEnabled:Bool {
        let monthStart: Date = CalendarUtils.monthDay(1, date: month.month)
        let currentMonth: Date = CalendarUtils.monthDay(1, date: Date())
        if self.onlyFuture {
            let calendar = Calendar(identifier: .gregorian)
            guard let maximum = calendar.date(byAdding: .year, value: 1, to: currentMonth) else { return false }
            return monthStart < maximum
        }
        if CalendarUtils.isYearHidden(month.components.year!) {
            return month.components.month! < 12
        }
        return monthStart < currentMonth
    }

    open var isPrevEnabled:Bool {
        if self.onlyFuture {
            let monthStart: Date = CalendarUtils.monthDay(1, date: month.month)
            let currentMonth: Date = CalendarUtils.monthDay(1, date: Date())
            return monthStart > currentMonth
        }
        return month.components.year! > lowYear || ((month.components.year == lowYear || CalendarUtils.isYearHidden(month.components.year!)) && month.components.month! > 1)
    }
    
    open override func getLeftBarViewOnce() -> BarView {
        return BarView(0, controller: self)
    }
    
    open override func getRightBarViewOnce() -> BarView {
        return BarView(0, controller: self)
    }
    
    open override var removeAfterDisapper: Bool {
        return true
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        
        genericView.layout(for: month)
        
        readyOnce()
    }

    deinit {
        var bp:Int = 0
        bp += 1
    }
    
    
}

final class CalendarMonthHeaderView: TitledBarView {
    private let titleControl = Control()
    private let titleView = TextView()
    private let chevronView = ImageView()
    private let prev = ImageButton()
    private let next = ImageButton()
    var titleMenu: (() -> ContextMenu?)? {
        didSet {
            titleControl.contextMenu = titleMenu
        }
    }
    var showsChevron: Bool = false {
        didSet {
            chevronView.isHidden = !showsChevron
            needsLayout = true
        }
    }

    init(controller: ViewController, title: String, isPrevEnabled: Bool, isNextEnabled: Bool, back: @escaping () -> Void, next: @escaping () -> Void) {
        super.init(controller: controller, nil, nil)
        let layout = TextViewLayout(.initialize(string: title, color: theme.colors.text, font: .medium(.header)), maximumNumberOfLines: 1)
        layout.measure(width: 220)
        titleView.update(layout)
        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        chevronView.image = TelegramThemeHooks.shared.image(.iconGeneralNext).precomposed(theme.colors.accent)
        chevronView.sizeToFit()
        chevronView.isHidden = true
        titleControl.addSubview(titleView)
        titleControl.addSubview(chevronView)
        titleControl.scaleOnClick = true
        titleControl.setAccessibilityLabel(title)
        addSubview(titleControl)

        self.prev.set(image: isPrevEnabled ? theme.icons.calendarBack : theme.icons.calendarBackDisabled, for: .Normal)
        self.prev.isEnabled = isPrevEnabled
        self.prev.autohighlight = false
        self.prev.scaleOnClick = true
        self.prev.sizeToFit(.zero, NSMakeSize(32, 32), thatFit: true)
        self.prev.setAccessibilityLabel(strings().voiceOverCommonBack)
        self.prev.set(handler: { _ in back() }, for: .Click)
        self.next.set(image: isNextEnabled ? theme.icons.calendarNext : theme.icons.calendarNextDisabled, for: .Normal)
        self.next.isEnabled = isNextEnabled
        self.next.autohighlight = false
        self.next.scaleOnClick = true
        self.next.sizeToFit(.zero, NSMakeSize(32, 32), thatFit: true)
        self.next.setAccessibilityLabel(strings().voiceOverCommonNext)
        self.next.set(handler: { _ in next() }, for: .Click)
        addSubview(self.prev)
        addSubview(self.next)
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let size = NSMakeSize(titleView.frame.width + 6 + chevronView.frame.width, max(titleView.frame.height, chevronView.frame.height))
        titleControl.frame = NSMakeRect(18, floorToScreenPixels(backingScaleFactor, (frame.height - size.height) / 2), size.width, size.height)
        titleView.setFrameOrigin(NSMakePoint(0, floorToScreenPixels(backingScaleFactor, (size.height - titleView.frame.height) / 2)))
        chevronView.setFrameOrigin(NSMakePoint(titleView.frame.maxX + 6, floorToScreenPixels(backingScaleFactor, (size.height - chevronView.frame.height) / 2)))
        next.setFrameOrigin(NSMakePoint(frame.width - next.frame.width - 12, floorToScreenPixels(backingScaleFactor, (frame.height - next.frame.height) / 2)))
        prev.setFrameOrigin(NSMakePoint(next.frame.minX - prev.frame.width - 8, next.frame.minY))
    }
}
