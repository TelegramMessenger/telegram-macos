import Cocoa
import TGUIKit
import TelegramTheme
import Localization

private let searchCalendar = Calendar(identifier: .gregorian)

private enum CalendarSearchMetrics {
    static let width: CGFloat = 300
    static let headerButton: CGFloat = 30
    static let headerInset: CGFloat = 10
    static let headerCenterY: CGFloat = 25
    static let monthRowCenterY: CGFloat = 60
    static let weekdaysCenterY: CGFloat = 85
    static let gridTop: CGFloat = 97
    static let gridInset: CGFloat = 17
    static let cell: CGFloat = 38
    static let circle: CGFloat = 32
    static let buttonSpacing: CGFloat = 10
    static let buttonHeight: CGFloat = 34
    static let bottomInset: CGFloat = 16

    static func height(rows: Int) -> CGFloat {
        return gridTop + cell * CGFloat(rows) + buttonSpacing + buttonHeight + bottomInset
    }
}

private enum CalendarSearchFonts {
    static let title: NSFont = .medium(.title)
    static let month: NSFont = .semibold(.title)
    static let weekday: NSFont = .medium(.small)
    static let action: NSFont = .medium(.text)
    static let daySize: CGFloat = 13
}

private func monthStart(_ date: Date) -> Date {
    return searchCalendar.date(from: searchCalendar.dateComponents([.year, .month], from: date)) ?? date
}

private func monthOffset(_ month: Date) -> Int {
    return (searchCalendar.component(.weekday, from: month) + 5) % 7
}

private func monthDays(_ month: Date) -> Int {
    return searchCalendar.range(of: .day, in: .month, for: month)?.count ?? 30
}

private func monthRows(_ month: Date) -> Int {
    return (monthOffset(month) + monthDays(month) + 6) / 7
}

private func dayAfter(_ date: Date, _ days: Int) -> Date {
    return searchCalendar.startOfDay(for: searchCalendar.date(byAdding: .day, value: days, to: date) ?? date)
}

private func chevronImage(_ size: NSSize, color: NSColor, mirror: Bool) -> CGImage? {
    return generateImage(size, rotatedContext: { size, ctx in
        ctx.clear(CGRect(origin: .zero, size: size))
        if mirror {
            ctx.translateBy(x: size.width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1.75)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 1, y: 1))
        ctx.addLine(to: CGPoint(x: size.width - 1.5, y: size.height / 2))
        ctx.addLine(to: CGPoint(x: 1, y: size.height - 1))
        ctx.strokePath()
    })
}

private func searchDateFormatter(_ format: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: appAppearance.language.languageCode)
    formatter.calendar = searchCalendar
    formatter.dateFormat = format
    return formatter
}

private func capCenteredY(_ view: TextView, centerY: CGFloat, font: NSFont) -> CGFloat {
    let baseline = view.textLayout?.lines.first?.frame.minY ?? view.frame.height
    return centerY - baseline + font.capHeight / 2
}

private final class CalendarSearchDayOverlay: View {
    weak var monthView: CalendarSearchMonthView?

    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        monthView?.drawDays(in: ctx)
    }
}

private final class CalendarSearchMonthView: Control {
    let month: Date
    let days: Int
    let offset: Int
    var dayEnabled: (Date) -> Bool = { _ in true }
    var onDay: ((Date) -> Void)?
    var onDoubleDay: ((Date) -> Void)?
    var dayPreview: (Int, NSSize) -> NSView? = { _, _ in nil }
    private let dayOverlay = CalendarSearchDayOverlay(frame: .zero)
    private var dayPreviews: [Int: NSView] = [:]
    private var hovered: Int?

    var selected: Date {
        didSet {
            if selected != oldValue {
                dayOverlay.layer?.animateContents()
                dayOverlay.needsDisplay = true
            }
        }
    }

    init(month: Date, selected: Date) {
        self.month = month
        self.days = monthDays(month)
        self.offset = monthOffset(month)
        self.selected = selected
        super.init(frame: .zero)
        dayOverlay.backgroundColor = .clear
        dayOverlay.isEventLess = true
        dayOverlay.monthView = self
        addSubview(dayOverlay)
        set(handler: { [weak self] _ in
            self?.click(double: false)
        }, for: .Click)
        set(handler: { [weak self] _ in
            self?.click(double: true)
        }, for: .DoubleClick)
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var rows: Int {
        return monthRows(month)
    }

    func date(at index: Int) -> Date {
        return dayAfter(month, index)
    }

    private var mouseIndex: Int? {
        guard let window = window, mouseInside() else {
            return nil
        }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let cell = CalendarSearchMetrics.cell
        guard point.x >= 0, point.y >= 0 else {
            return nil
        }
        let column = Int(point.x / cell)
        let index = Int(point.y / cell) * 7 + column - offset
        guard column < 7, index >= 0, index < days else {
            return nil
        }
        return index
    }

    private func click(double: Bool) {
        if !double, let event = NSApp.currentEvent, event.clickCount > 1 {
            return
        }
        guard let index = mouseIndex else {
            return
        }
        let date = self.date(at: index)
        guard dayEnabled(date) else {
            return
        }
        if double {
            onDoubleDay?(date)
        } else {
            onDay?(date)
        }
    }

    private func updateHover() {
        let index = mouseIndex.flatMap { dayEnabled(date(at: $0)) ? $0 : nil }
        if hovered != index {
            hovered = index
            dayOverlay.needsDisplay = true
        }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateHover()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateHover()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        updateHover()
    }

    override func layout() {
        super.layout()
        dayOverlay.frame = bounds
    }

    func updateDayPreviews() {
        let cell = CalendarSearchMetrics.cell
        let circle = CalendarSearchMetrics.circle
        let size = NSMakeSize(circle, circle)
        for index in 0 ..< days where dayPreviews[index] == nil {
            let date = self.date(at: index)
            guard dayEnabled(date), let preview = dayPreview(Int(date.timeIntervalSince1970), size) else {
                continue
            }
            let position = offset + index
            preview.frame = NSMakeRect(CGFloat(position % 7) * cell + (cell - circle) / 2, CGFloat(position / 7) * cell + (cell - circle) / 2, circle, circle)
            dayPreviews[index] = preview
            addSubview(preview, positioned: .below, relativeTo: dayOverlay)
        }
        dayOverlay.frame = bounds
        dayOverlay.needsDisplay = true
    }

    fileprivate func drawDays(in ctx: CGContext) {
        let cell = CalendarSearchMetrics.cell
        let inset = (cell - CalendarSearchMetrics.circle) / 2
        let accent = theme.colors.accent
        let today = searchCalendar.startOfDay(for: Date())
        let scale = backingScaleFactor

        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.setAllowsFontSmoothing(scale == 1.0)
        ctx.setShouldSmoothFonts(scale == 1.0)
        ctx.setAllowsFontSubpixelPositioning(true)
        ctx.setShouldSubpixelPositionFonts(true)

        for index in 0 ..< days {
            let date = self.date(at: index)
            let position = offset + index
            let rect = NSMakeRect(CGFloat(position % 7) * cell, CGFloat(position / 7) * cell, cell, cell)
            let enabled = dayEnabled(date)

            let hasPreview = dayPreviews[index] != nil
            var fill: NSColor?
            var color: NSColor = hasPreview ? .white : date == today ? accent : enabled ? theme.colors.text : theme.colors.grayText
            var weight: NSFont.Weight = hasPreview ? .medium : .regular

            if date == selected {
                fill = accent
                color = hasPreview ? .white : theme.colors.underSelectedColor
                weight = .semibold
            } else if hovered == index {
                fill = theme.colors.grayBackground
            }

            if let fill {
                if hasPreview {
                    ctx.setStrokeColor(fill.cgColor)
                    ctx.setLineWidth(2)
                    ctx.strokeEllipse(in: rect.insetBy(dx: inset - 2, dy: inset - 2))
                } else {
                    ctx.setFillColor(fill.cgColor)
                    ctx.fillEllipse(in: rect.insetBy(dx: inset, dy: inset))
                }
            }

            let text = NSAttributedString.initialize(string: "\(index + 1)", color: color, font: NSFont.monospacedDigitSystemFont(ofSize: CalendarSearchFonts.daySize, weight: weight))
            let line = CTLineCreateWithAttributedString(text)
            let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            ctx.textPosition = CGPoint(x: floorToScreenPixels(scale, rect.midX - ink.midX), y: floorToScreenPixels(scale, rect.midY + ink.midY))
            CTLineDraw(line, ctx)
        }

        ctx.restoreGState()
    }
}

public final class CalendarSearchView: View {
    fileprivate let closeButton = ImageButton()
    fileprivate let monthButton = Control()
    fileprivate let prevButton = ImageButton()
    fileprivate let nextButton = ImageButton()
    fileprivate let actionButton = ImageButton()
    private let actionTextView = TextView()
    private let titleView = TextView()
    private let monthTitleView = TextView()
    private let monthChevronView = ImageView(frame: .zero)
    private let weekdayViews: [TextView] = (0 ..< 7).map { _ in TextView() }
    private let gridView = View()
    fileprivate private(set) var monthView: CalendarSearchMonthView?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        let appearance: LiquidGlassAppearance = theme.colors.background.lightness < 0.5 ? .forceDark : .forceLight

        closeButton.autohighlight = false
        closeButton.scaleOnClick = true
        closeButton.opticalCentering = true
        closeButton.disableActions()
        if let image = NSImage(named: "Icon_Pip_Close") {
            closeButton.set(image: image.precomposed(theme.colors.text), for: .Normal)
        }
        closeButton.setGlassEffect(size: NSMakeSize(CalendarSearchMetrics.headerButton, CalendarSearchMetrics.headerButton), forceAppearance: appearance)
        closeButton.sizeToFit(.zero, NSMakeSize(CalendarSearchMetrics.headerButton, CalendarSearchMetrics.headerButton), thatFit: true)
        closeButton.layer?.masksToBounds = false
        closeButton.setAccessibilityLabel(strings().modalCancel)

        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        let titleLayout = TextViewLayout(.initialize(string: strings().calendarSearchControllerSearch, color: theme.colors.text, font: CalendarSearchFonts.title), maximumNumberOfLines: 1)
        titleLayout.measure(width: frameRect.width - 100)
        titleView.update(titleLayout)

        monthTitleView.userInteractionEnabled = false
        monthTitleView.isSelectable = false
        monthChevronView.image = chevronImage(NSMakeSize(6, 10), color: theme.colors.accent, mirror: false)
        monthChevronView.sizeToFit()
        monthButton.scaleOnClick = true
        monthButton.addSubview(monthTitleView)
        monthButton.addSubview(monthChevronView)

        prevButton.autohighlight = false
        prevButton.scaleOnClick = true
        nextButton.autohighlight = false
        nextButton.scaleOnClick = true

        let weekdays = searchDateFormatter("EEE").shortStandaloneWeekdaySymbols ?? []
        for (index, view) in weekdayViews.enumerated() {
            view.userInteractionEnabled = false
            view.isSelectable = false
            let symbol = weekdays.isEmpty ? "" : weekdays[(index + 1) % weekdays.count]
            let layout = TextViewLayout(.initialize(string: symbol.uppercased(), color: theme.colors.grayText, font: CalendarSearchFonts.weekday), maximumNumberOfLines: 1)
            layout.measure(width: CalendarSearchMetrics.cell)
            view.update(layout)
            addSubview(view)
        }

        gridView.layer?.masksToBounds = true

        actionButton.autohighlight = false
        actionButton.scaleOnClick = true
        actionButton.disableActions()
        actionButton.setGlassEffect(tintColor: theme.colors.accent)
        actionButton.set(background: theme.colors.accent, for: .Normal)
        actionButton.set(background: theme.colors.accent.highlighted, for: .Highlight)
        actionButton.layer?.cornerRadius = CalendarSearchMetrics.buttonHeight / 2
        actionButton.setAccessibilityLabel(strings().modalDone)
        actionTextView.userInteractionEnabled = false
        actionTextView.isSelectable = false
        actionTextView.isEventLess = true
        let actionLayout = TextViewLayout(.initialize(string: strings().modalDone, color: theme.colors.underSelectedColor, font: CalendarSearchFonts.action), maximumNumberOfLines: 1)
        actionLayout.measure(width: frameRect.width - CalendarSearchMetrics.gridInset * 2 - 20)
        actionTextView.update(actionLayout)
        actionButton.addSubview(actionTextView)

        addSubview(gridView)
        addSubview(titleView)
        addSubview(monthButton)
        addSubview(prevButton)
        addSubview(nextButton)
        addSubview(closeButton)
        addSubview(actionButton)

        backgroundColor = theme.colors.background
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    fileprivate func setMonth(_ month: Date, selected: Date, direction: Int, animated: Bool, isPrevEnabled: Bool, isNextEnabled: Bool, configure: (CalendarSearchMonthView) -> Void) {
        let previous = monthView
        let view = CalendarSearchMonthView(month: month, selected: selected)
        configure(view)
        view.frame = NSMakeRect(CalendarSearchMetrics.gridInset, 0, CalendarSearchMetrics.cell * 7, CalendarSearchMetrics.cell * CGFloat(view.rows))
        gridView.addSubview(view)
        monthView = view
        view.updateDayPreviews()

        let monthLayout = TextViewLayout(.initialize(string: searchDateFormatter("LLLL yyyy").string(from: month).capitalized, color: theme.colors.text, font: CalendarSearchFonts.month), maximumNumberOfLines: 1)
        monthLayout.measure(width: .greatestFiniteMagnitude)
        monthTitleView.update(monthLayout)

        prevButton.isEnabled = isPrevEnabled
        nextButton.isEnabled = isNextEnabled
        if let image = chevronImage(NSMakeSize(8, 14), color: isPrevEnabled ? theme.colors.accent : theme.colors.grayText, mirror: true) {
            prevButton.set(image: image, for: .Normal)
        }
        if let image = chevronImage(NSMakeSize(8, 14), color: isNextEnabled ? theme.colors.accent : theme.colors.grayText, mirror: false) {
            nextButton.set(image: image, for: .Normal)
        }
        prevButton.sizeToFit(.zero, NSMakeSize(26, 26), thatFit: true)
        nextButton.sizeToFit(.zero, NSMakeSize(26, 26), thatFit: true)

        if animated, let previous {
            let offset = frame.width * CGFloat(direction)
            view.layer?.animatePosition(from: NSMakePoint(offset, 0), to: .zero, duration: 0.35, timingFunction: .spring, additive: true)
            view.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            previous.layer?.animatePosition(from: .zero, to: NSMakePoint(-offset, 0), duration: 0.35, timingFunction: .spring, removeOnCompletion: false, additive: true, completion: { [weak previous] _ in
                previous?.removeFromSuperview()
            })
            previous.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false)
        } else {
            previous?.removeFromSuperview()
        }

        updateLayout(size: frame.size, transition: animated ? .animated(duration: 0.35, curve: .spring) : .immediate)
    }

    public override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }

    private func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        let scale = backingScaleFactor
        let headerY = CalendarSearchMetrics.headerCenterY
        closeButton.setFrameOrigin(NSMakePoint(CalendarSearchMetrics.headerInset, floorToScreenPixels(scale, headerY - closeButton.frame.height / 2)))
        titleView.setFrameOrigin(NSMakePoint(floorToScreenPixels(scale, (size.width - titleView.frame.width) / 2), floorToScreenPixels(scale, capCenteredY(titleView, centerY: headerY, font: CalendarSearchFonts.title))))

        let monthY = CalendarSearchMetrics.monthRowCenterY
        let monthHeight: CGFloat = 26
        monthButton.frame = NSMakeRect(CalendarSearchMetrics.gridInset + 5, monthY - monthHeight / 2, monthTitleView.frame.width + 7 + monthChevronView.frame.width, monthHeight)
        monthTitleView.setFrameOrigin(NSMakePoint(0, floorToScreenPixels(scale, capCenteredY(monthTitleView, centerY: monthHeight / 2, font: CalendarSearchFonts.month))))
        monthChevronView.setFrameOrigin(NSMakePoint(monthTitleView.frame.maxX + 7, floorToScreenPixels(scale, (monthHeight - monthChevronView.frame.height) / 2)))

        nextButton.setFrameOrigin(NSMakePoint(size.width - CalendarSearchMetrics.gridInset - nextButton.frame.width + 2, floorToScreenPixels(scale, monthY - nextButton.frame.height / 2)))
        prevButton.setFrameOrigin(NSMakePoint(nextButton.frame.minX - 6 - prevButton.frame.width, nextButton.frame.minY))

        for (index, view) in weekdayViews.enumerated() {
            let centerX = CalendarSearchMetrics.gridInset + (CGFloat(index) + 0.5) * CalendarSearchMetrics.cell
            view.setFrameOrigin(NSMakePoint(floorToScreenPixels(scale, centerX - view.frame.width / 2), floorToScreenPixels(scale, capCenteredY(view, centerY: CalendarSearchMetrics.weekdaysCenterY, font: CalendarSearchFonts.weekday))))
        }

        let gridHeight = CalendarSearchMetrics.cell * CGFloat(monthView?.rows ?? 6)
        transition.updateFrame(view: gridView, frame: NSMakeRect(0, CalendarSearchMetrics.gridTop, size.width, gridHeight))
        let actionFrame = NSMakeRect(CalendarSearchMetrics.gridInset, CalendarSearchMetrics.gridTop + gridHeight + CalendarSearchMetrics.buttonSpacing, size.width - CalendarSearchMetrics.gridInset * 2, CalendarSearchMetrics.buttonHeight)
        transition.updateFrame(view: actionButton, frame: actionFrame)
        actionTextView.setFrameOrigin(NSMakePoint(floorToScreenPixels(scale, (actionFrame.width - actionTextView.frame.width) / 2), floorToScreenPixels(scale, capCenteredY(actionTextView, centerY: actionFrame.height / 2, font: CalendarSearchFonts.action))))
    }
}

public final class CalendarSearchController: ModalViewController {
    private let onSelect: (Date) -> Void
    private let minDay: Date
    private let maxDay: Date
    private var month: Date
    private var selected: Date
    public var dayPreview: (Int, NSSize) -> NSView? = { _, _ in nil }

    public func updateDayPreviews() {
        guard isLoaded() else {
            return
        }
        genericView.monthView?.updateDayPreviews()
    }

    public init(current: Date, select: @escaping (Date) -> Void) {
        let today = searchCalendar.startOfDay(for: Date())
        let minDay = searchCalendar.date(from: DateComponents(year: 2013, month: 1, day: 1)) ?? today
        let day = min(max(searchCalendar.startOfDay(for: current), minDay), today)
        self.onSelect = select
        self.minDay = minDay
        self.maxDay = today
        self.month = monthStart(day)
        self.selected = day
        super.init(frame: NSMakeRect(0, 0, CalendarSearchMetrics.width, CalendarSearchMetrics.height(rows: monthRows(monthStart(day)))))
        self.bar = .init(height: 0)
        self.analyticsScreenId = "app.calendar"
    }

    public override func viewClass() -> AnyClass {
        return CalendarSearchView.self
    }

    public var genericView: CalendarSearchView {
        return self.view as! CalendarSearchView
    }

    public override var containerBackground: NSColor {
        return theme.colors.background
    }

    public override var dynamicSize: Bool {
        return true
    }

    public override func measure(size: NSSize) {
        self.modal?.resize(with: NSMakeSize(frame.width, CalendarSearchMetrics.height(rows: monthRows(month))), animated: false)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        genericView.closeButton.set(handler: { [weak self] _ in
            self?.close()
        }, for: .Click)

        genericView.prevButton.set(handler: { [weak self] _ in
            self?.step(-1)
        }, for: .Click)

        genericView.nextButton.set(handler: { [weak self] _ in
            self?.step(1)
        }, for: .Click)

        genericView.monthButton.set(handler: { [weak self] control in
            guard let self, let event = NSApp.currentEvent else {
                return
            }
            AppMenu.show(menu: self.monthMenu(), event: event, for: control)
        }, for: .Down)

        genericView.actionButton.set(handler: { [weak self] _ in
            self?.done()
        }, for: .Click)

        showMonth(month, direction: 0, animated: false)
        readyOnce()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.step(-1)
            return .invoked
        }, with: self, for: .LeftArrow, priority: .modal)
        window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.step(1)
            return .invoked
        }, with: self, for: .RightArrow, priority: .modal)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        window?.removeAllHandlers(for: self)
    }

    public override func escapeKeyAction() -> KeyHandlerResult {
        close()
        return .invoked
    }

    public override func returnKeyAction() -> KeyHandlerResult {
        done()
        return .invoked
    }

    private var isPrevEnabled: Bool {
        return month > monthStart(minDay)
    }

    private var isNextEnabled: Bool {
        return month < monthStart(maxDay)
    }

    private func step(_ direction: Int) {
        if direction < 0, !isPrevEnabled {
            return
        }
        if direction > 0, !isNextEnabled {
            return
        }
        guard let target = searchCalendar.date(byAdding: .month, value: direction, to: month) else {
            return
        }
        showMonth(monthStart(target), direction: direction, animated: true)
    }

    private func showMonth(_ target: Date, direction: Int, animated: Bool) {
        self.month = target
        let minDay = self.minDay
        let maxDay = self.maxDay
        genericView.setMonth(target, selected: selected, direction: direction, animated: animated, isPrevEnabled: isPrevEnabled, isNextEnabled: isNextEnabled, configure: { view in
            view.dayPreview = self.dayPreview
            view.dayEnabled = { date in
                return date >= minDay && date <= maxDay
            }
            view.onDay = { [weak self] date in
                self?.select(date)
            }
            view.onDoubleDay = { [weak self] date in
                self?.select(date)
                self?.done()
            }
        })
        let height = CalendarSearchMetrics.height(rows: monthRows(target))
        if animated, genericView.frame.height != height {
            self.modal?.resize(with: NSMakeSize(frame.width, height), animated: true)
        }
    }

    private func monthMenu() -> ContextMenu {
        let menu = ContextMenu()
        let names = searchDateFormatter("LLLL").standaloneMonthSymbols ?? []
        let lastMonth = monthStart(maxDay)
        let maxYear = searchCalendar.component(.year, from: lastMonth)
        let minYear = searchCalendar.component(.year, from: minDay)
        let current = month
        for year in stride(from: maxYear, through: minYear, by: -1) {
            let item = ContextMenuItem("\(year)")
            let submenu = ContextMenu()
            for index in 0 ..< 12 {
                guard let target = searchCalendar.date(from: DateComponents(year: year, month: index + 1, day: 1)), target <= lastMonth else {
                    continue
                }
                let name = index < names.count ? names[index].capitalized : "\(index + 1)"
                submenu.addItem(ContextMenuItem(name, handler: { [weak self] in
                    guard let self, target != self.month else {
                        return
                    }
                    self.showMonth(target, direction: target > self.month ? 1 : -1, animated: true)
                }, state: target == current ? .on : nil))
            }
            item.submenu = submenu
            menu.addItem(item)
        }
        return menu
    }

    private func select(_ date: Date) {
        selected = date
        genericView.monthView?.selected = date
    }

    private func done() {
        let day = selected
        close()
        onSelect(day)
    }
}
