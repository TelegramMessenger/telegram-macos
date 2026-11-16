import Cocoa
import TGUIKit
import CalendarUtils
import TelegramTheme
import GeneralRows

open class CalendarControllerView : View {
    
}

private final class CalendarNavigation : NavigationViewController {
    
    
   
}

open class CalendarController: GenericViewController<CalendarControllerView> {
    
    private var navigation:CalendarNavigation!
    private var interactions:CalendarMonthInteractions!
    private let onlyFuture: Bool
    private let lowYear: Int
    private var selectedDate: Date
    private var isActive = true
    private let limitedBy: Date?
    public var dayPreview: (Int) -> NSView? = { _ in nil }
    public private(set) var isSelecting = false
    public private(set) var selectedRange: ClosedRange<Date>?
    public var selectionChanged: (ClosedRange<Date>?) -> Void = { _ in }
    public var weeksChanged: (Int) -> Void = { _ in }
    public var fitsWeeks = false {
        didSet {
            refreshSelection()
        }
    }

    public var weeksCount: Int {
        return (navigation.controller as? CalendarMonthController)?.month.linesCount ?? 6
    }

    public func setSelecting(_ selecting: Bool) {
        isSelecting = selecting
        selectedRange = nil
        refreshSelection()
        selectionChanged(nil)
    }

    public var selectedDaysCount: Int {
        guard let range = selectedRange else { return 0 }
        let calendar = Calendar(identifier: .gregorian)
        return (calendar.dateComponents([.day], from: range.lowerBound, to: range.upperBound).day ?? 0) + 1
    }

    private func toggleRange(_ date: Date) {
        let day = Calendar(identifier: .gregorian).startOfDay(for: date)
        if let range = selectedRange {
            if range.lowerBound == day || range.upperBound == day {
                selectedRange = nil
            } else if range.lowerBound == range.upperBound {
                selectedRange = day < range.lowerBound ? day ... range.upperBound : range.lowerBound ... day
            } else {
                selectedRange = day ... day
            }
        } else {
            selectedRange = day ... day
        }
        refreshSelection()
        selectionChanged(selectedRange)
    }

    private func rangeDays(for month: Date) -> ClosedRange<Int>? {
        guard let range = selectedRange else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let first = calendar.startOfDay(for: CalendarUtils.monthDay(1, date: month))
        let last = calendar.startOfDay(for: CalendarUtils.monthDay(CalendarUtils.lastDay(ofTheMonth: month), date: month))
        let lower = max(range.lowerBound, first)
        let upper = min(range.upperBound, last)
        guard lower <= upper else { return nil }
        return calendar.component(.day, from: lower) ... calendar.component(.day, from: upper)
    }

    private func applySelection(to controller: CalendarMonthController) {
        controller.month.fitsWeeks = fitsWeeks
        controller.month.isSelecting = isSelecting
        controller.month.selectedRange = rangeDays(for: controller.month.month)
        if isSelecting {
            controller.month.selectedDay = nil
        }
    }

    private func refreshSelection() {
        guard let controller = navigation.controller as? CalendarMonthController else { return }
        applySelection(to: controller)
        if controller.isLoaded() {
            controller.genericView.layout(for: controller.month)
        }
    }

    public func updateDayPreviews() {
        guard let controller = navigation.controller as? CalendarMonthController, controller.isLoaded() else { return }
        controller.genericView.updateDayPreviews(animated: true)
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        navigation.view.frame = genericView.bounds
        addSubview(navigation.view)
        readyOnce()
    }

    open override func viewDidResized(_ size: NSSize) {
        super.viewDidResized(size)
        navigation.view.frame = NSRect(origin: .zero, size: size)
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        self.navigation.viewDidAppear(animated)
        
        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            if let current = self?.navigation.controller as? CalendarMonthController, current.isPrevEnabled, let backAction = self?.interactions.backAction {
                backAction(current.month.month)
            }
            return .invoked
        }, with: self, for: .LeftArrow, priority: .modal)
        
        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            if let current = self?.navigation.controller as? CalendarMonthController, current.isNextEnabled, let nextAction = self?.interactions.nextAction {
                nextAction(current.month.month)
            }
            return .invoked
        }, with: self, for: .RightArrow, priority: .modal)
    }
    
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.isActive = false
        self.navigation.viewWillDisappear(animated)
        self.window?.remove(object: self, for: .LeftArrow)
        self.window?.remove(object: self, for: .RightArrow)
    }
    
    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.navigation.viewDidDisappear(animated)
    }
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.isActive = true
        self.navigation.viewWillAppear(animated)
    }
    
    public init(_ frameRect:NSRect, _ window: Window, current: Date = Date(), onlyFuture: Bool = false, limitedBy: Date? = nil, lowYear: Int = 2013, canBeNoYear: Bool = false, selectHandler:@escaping (Date)->Void, autoclose: Bool = true) {
        self.onlyFuture = onlyFuture
        self.selectedDate = current
        self.limitedBy = limitedBy
        self.lowYear = lowYear
        super.init(frame: frameRect)
        bar = .init(height: 0)
        self.interactions = CalendarMonthInteractions(lowYear: lowYear, canBeNoYear: canBeNoYear, selectAction: { [weak self] (selected) in
            guard let self, self.isActive else { return }
            if self.isSelecting {
                self.toggleRange(selected)
                return
            }
            self.selectedDate = selected
            if autoclose {
                self.isActive = false
                self.popover?.hide()
                self.navigationController?.modal?.close()
            }
            selectHandler(selected)
        }, backAction: { [weak self] date in
            if let strongSelf = self, strongSelf.isActive {
                strongSelf.navigation.push(strongSelf.stepMonth(date: CalendarUtils.stepMonth(-1, date: date)), style: .pop)
            }
        }, nextAction: { [weak self] date in
            if let strongSelf = self, strongSelf.isActive {
                strongSelf.navigation.push(strongSelf.stepMonth(date: CalendarUtils.stepMonth(1, date: date)), style: .push)
            }
        }, changeYear: { [weak self] year, date in
            self?.selectYear(Int(year), month: date, style: .push)
        })
        
        self.navigation = CalendarNavigation(stepMonth(date: current), window)
        self.navigation._frameRect = frameRect
        
    }
    
    open func stepMonth(date:Date, selectDayAnyway: Bool = false) -> CalendarMonthController {
        let isSelectedMonth = CalendarUtils.isSameDate(selectedDate, date: date, checkDay: false)
        let controller = CalendarMonthController(isSelectedMonth ? selectedDate : date, onlyFuture: self.onlyFuture, limitedBy: limitedBy, selectDayAnyway: selectDayAnyway || isSelectedMonth, interactions: interactions, lowYear: self.lowYear, dayPreview: { [weak self] timestamp in
            return self?.dayPreview(timestamp)
        })
        applySelection(to: controller)
        weeksChanged(controller.month.linesCount)
        return controller
    }

    open var date: Date {
        return self.selectedDate
    }

    private func selectYear(_ year: Int, month: Date, style: ViewControllerStyle) {
        guard self.isActive else { return }
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.component(.day, from: self.selectedDate)
        let targetMonth: Date = CalendarUtils.year(year, date: month)
        var selected: Date = CalendarUtils.monthDay(min(day, CalendarUtils.lastDay(ofTheMonth: targetMonth)), date: targetMonth)
        if CalendarUtils.isYearHidden(year) {
            guard self.interactions.canBeNoYear, !self.onlyFuture else { return }
        } else {
            guard year >= self.lowYear else { return }
            let today = calendar.startOfDay(for: Date())
            var maximum = today
            if self.onlyFuture {
                guard let nextYear = calendar.date(byAdding: .year, value: 1, to: today) else { return }
                maximum = nextYear
            }
            if let limitedBy {
                maximum = min(maximum, calendar.startOfDay(for: limitedBy))
            }
            if self.onlyFuture {
                guard maximum >= today else { return }
                selected = max(selected, today)
            }
            selected = min(selected, maximum)
        }
        self.selectedDate = selected
        self.navigation.push(self.stepMonth(date: selected, selectDayAnyway: true), style: style)
    }

    open func hideYear() {
        self.selectYear(CalendarUtils.yearForNoYear, month: self.selectedDate, style: .none)
    }

    open override var isAutoclosePopover: Bool {
        return false
    }
}



