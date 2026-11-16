import Cocoa
import TGUIKit
import TelegramTheme
import Localization

private final class CalendarModalView: View {
    var onLayout: () -> Void = {}

    override func layout() {
        super.layout()
        onLayout()
    }
}

open class CalendarModalController: ModalViewController {
    public let calendar: CalendarController
    private let titleText: String
    public var canSelect: Bool {
        didSet {
            if canSelect != oldValue {
                modal?.updateHeader(animated: true)
            }
        }
    }
    private let actionButton = TextButton()
    private var weeks: Int
    public var clearRange: ((ClosedRange<Date>) -> Void)?

    public static let calendarSize = NSMakeSize(380, 336)
    private static let actionHeight: CGFloat = 64
    private static let headerHeight: CGFloat = 56

    public init(calendar: CalendarController, title: String, selectable: Bool = false) {
        self.calendar = calendar
        self.titleText = title
        self.canSelect = selectable
        calendar.fitsWeeks = true
        self.weeks = calendar.weeksCount
        super.init(frame: NSMakeRect(0, 0, CalendarModalController.calendarSize.width, CalendarMonthView.fittingHeight(weeks: weeks) + 8))
        bar = .init(height: 0)
    }

    open override var modalTheme: ModalViewController.Theme {
        return .init(border: .clear)
    }

    open override var containerBackground: NSColor {
        return theme.colors.listBackground
    }

    open override var modalHeader: (left: ModalHeaderData?, center: ModalHeaderData?, right: ModalHeaderData?)? {
        let left = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak self] in
            self?.close()
        })
        let count = calendar.selectedDaysCount
        let center = ModalHeaderData(title: calendar.isSelecting && count > 0 ? strings().messageCalendarDaysSelectedTitleOther(count) : titleText)
        let right: ModalHeaderData?
        if canSelect {
            right = ModalHeaderData(title: calendar.isSelecting ? strings().modalCancel : strings().messageCalendarSelect, handler: { [weak self] in
                self?.toggleSelecting()
            })
        } else {
            right = nil
        }
        return (left, center, right)
    }

    open override func viewClass() -> AnyClass {
        return CalendarModalView.self
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        (view as? CalendarModalView)?.onLayout = { [weak self] in
            self?.layoutContent()
        }
        calendar.view.frame = NSMakeRect(0, CalendarModalController.headerHeight, CalendarModalController.calendarSize.width, calendarHeight)
        view.addSubview(calendar.view)

        actionButton.set(font: .medium(.text), for: .Normal)
        actionButton.set(background: .clear, for: .Normal)
        actionButton.set(background: .clear, for: .Highlight)
        actionButton.set(color: theme.colors.accent.lightness > 0.8 ? NSColor(0x000000) : NSColor(0xffffff), for: .Normal)
        actionButton.setGlassEffect(tintColor: theme.colors.accent)
        actionButton.glassTintColor = theme.colors.accent
        actionButton.autohighlight = false
        actionButton.scaleOnClick = true
        actionButton.isHidden = true
        actionButton.set(handler: { [weak self] _ in
            guard let self, let range = self.calendar.selectedRange else { return }
            self.clearRange?(range)
        }, for: .Click)
        view.addSubview(actionButton)

        calendar.selectionChanged = { [weak self] _ in
            self?.selectionUpdated()
        }
        calendar.weeksChanged = { [weak self] weeks in
            guard let self, self.weeks != weeks else { return }
            self.weeks = weeks
            self.layoutContent()
            self.modal?.resize(with: self.contentSize, animated: true)
        }
        readyOnce()
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        calendar.viewWillAppear(animated)
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        calendar.viewDidAppear(animated)
    }

    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        calendar.viewWillDisappear(animated)
    }

    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        calendar.viewDidDisappear(animated)
    }

    private func toggleSelecting() {
        calendar.setSelecting(!calendar.isSelecting)
        actionButton.isHidden = !calendar.isSelecting
        selectionUpdated()
        modal?.resize(with: contentSize, animated: true)
    }

    private func selectionUpdated() {
        let count = calendar.selectedDaysCount
        actionButton.set(text: count == 1 ? strings().messageCalendarClearHistoryForThisDay : strings().messageCalendarClearHistoryForTheseDays, for: .Normal)
        actionButton.isEnabled = count > 0
        modal?.updateHeader(animated: true)
        layoutContent()
    }

    open override var dynamicSize: Bool {
        return true
    }

    open override func measure(size: NSSize) {
        modal?.resize(with: contentSize, animated: false)
    }

    private var calendarHeight: CGFloat {
        return CalendarMonthView.fittingHeight(weeks: weeks) + 8
    }

    private var contentSize: NSSize {
        let height = calendarHeight + (calendar.isSelecting ? CalendarModalController.actionHeight : 0)
        return NSMakeSize(CalendarModalController.calendarSize.width, height)
    }

    private func layoutContent() {
        let top = CalendarModalController.headerHeight
        calendar.view.frame = NSMakeRect(0, top, view.frame.width, calendarHeight)
        actionButton.frame = NSMakeRect(20, top + calendarHeight + 4, view.frame.width - 40, 40)
        actionButton.layer?.cornerRadius = 20
    }
}
