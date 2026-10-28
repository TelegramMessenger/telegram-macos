import XCTest
import AppKit
@testable import TGUIKit

private final class LabeledRowItem: TableRowItem {
    let title: String
    var pressed = false

    init(_ initialSize: NSSize, title: String, stableId: AnyHashable) {
        self.title = title
        super.init(initialSize, stableId: stableId)
    }

    override var accessibilityLabel: String? {
        return title
    }

    override var accessibilityValue: String? {
        return "value \(title)"
    }

    override func accessibilityPerformPress() -> Bool {
        pressed = true
        return true
    }
}

private final class CollapsedRowItem: TableRowItem {
    override var accessibilityLabel: String? {
        return "Program"
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }

    override func viewClass() -> AnyClass {
        return CollapsedRowView.self
    }
}

private final class CollapsedRowView: TableRowView {
    var events: [String] = []
    private let container = Control(frame: NSMakeRect(0, 0, 400, 60))
    private let info = ImageButton(frame: NSMakeRect(300, 10, 30, 30))
    private let toggle = SwitchView(frame: NSMakeRect(340, 20, 32, 20))

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(container)
        container.addSubview(info)
        container.addSubview(toggle)
        container.set(handler: { [weak self] _ in self?.events.append("open") }, for: .Click)
        info.setAccessibilityLabel("Info")
        info.set(handler: { [weak self] _ in self?.events.append("info") }, for: .Click)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }
}

final class AccessibilityBaseTests: XCTestCase {
    func testTextViewRejectsMissingAccessibilitySelector() {
        XCTAssertFalse(TextView().responds(to: nil))
    }

    private var window: NSWindow!

    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
        TGUIKitAccessibility.isEnabled = true
        window = NSWindow(contentRect: NSMakeRect(0, 0, 400, 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
    }

    override func tearDown() {
        TGUIKitAccessibility.isEnabled = true
        window.close()
        window = nil
        super.tearDown()
    }

    private func host(_ view: NSView) {
        window.contentView?.addSubview(view)
    }

    private func iconButton() -> ImageButton {
        let button = ImageButton()
        button.set(image: testImage(CGSize(width: 24, height: 24)), for: .Normal)
        _ = button.sizeToFit(.zero, NSMakeSize(24, 24), thatFit: true)
        return button
    }

    func testIconButtonWithoutLabelIsReported() {
        let button = iconButton()
        button.set(handler: { _ in }, for: .Click)
        host(button)
        XCTAssertTrue(button.isAccessibilityElement())
        XCTAssertEqual(button.accessibilityRole(), .button)
        XCTAssertEqual(AccessibilityAudit.audit(window).map(\.kind), [.unlabeledControl])
    }

    func testExplicitLabelAndTooltipLabelTheButton() {
        let labeled = iconButton()
        labeled.set(handler: { _ in }, for: .Click)
        labeled.setAccessibilityLabel("Send")
        let tooltipped = iconButton()
        tooltipped.set(handler: { _ in }, for: .Click)
        tooltipped.appTooltip = "Attach"
        host(labeled)
        host(tooltipped)
        XCTAssertEqual(labeled.accessibilityLabel(), "Send")
        XCTAssertEqual(tooltipped.accessibilityLabel(), "Attach")
        XCTAssertEqual(AccessibilityAudit.audit(window), [])
    }

    func testPressRunsClickHandlers() {
        let button = iconButton()
        button.setAccessibilityLabel("Send")
        var events: [String] = []
        button.set(handler: { _ in events.append("down") }, for: .Down)
        button.set(handler: { _ in events.append("single") }, for: .SingleClick)
        button.set(handler: { _ in events.append("click") }, for: .Click)
        host(button)
        XCTAssertTrue(button.accessibilityPerformPress())
        XCTAssertEqual(events, ["down", "single", "click"])
        button.isEnabled = false
        XCTAssertFalse(button.accessibilityPerformPress())
        XCTAssertFalse(button.isAccessibilityEnabled())
    }

    func testDecorativeControlIsHiddenAndNotReported() {
        let button = iconButton()
        button.set(handler: { _ in }, for: .Click)
        button.isAccessibilityDecorative = true
        host(button)
        XCTAssertFalse(button.isAccessibilityElement())
        XCTAssertEqual(AccessibilityAudit.audit(window), [])
    }

    func testTextButtonUsesItsTitle() {
        let button = TextButton()
        button.set(text: "Done", for: .Normal)
        button.set(font: .systemFont(ofSize: 13), for: .Normal)
        button.set(handler: { _ in }, for: .Click)
        _ = button.sizeToFit()
        host(button)
        XCTAssertEqual(button.accessibilityLabel(), "Done")
        XCTAssertEqual(AccessibilityAudit.audit(window), [])
        let children = AccessibilityAudit.elements(button).filter { $0 !== button }
        XCTAssertTrue(children.isEmpty, "the title is read by the button, not as separate text")
    }

    func testTextViewReadsItsText() {
        let text = TextView()
        let layout = TextViewLayout(.initialize(string: "Hello world", color: .black, font: .systemFont(ofSize: 13)))
        layout.measure(width: 200)
        text.update(layout)
        host(text)
        XCTAssertTrue(text.isAccessibilityElement())
        XCTAssertEqual(text.accessibilityRole(), .staticText)
        XCTAssertEqual(text.accessibilityValue() as? String, "Hello world")
        XCTAssertEqual(AccessibilityAudit.audit(window), [])
    }

    func testSensitiveTextIsHiddenWithoutVoiceOver() {
        let text = TextView()
        let layout = TextViewLayout(.initialize(string: "secret words", color: .black, font: .systemFont(ofSize: 13)))
        layout.measure(width: 200)
        text.update(layout)
        text.isAccessibilitySensitive = true
        host(text)
        if NSWorkspace.shared.isVoiceOverEnabled {
            XCTAssertEqual(text.accessibilityValue() as? String, "secret words")
        } else {
            XCTAssertNil(text.accessibilityValue())
            XCTAssertFalse(text.isAccessibilityElement())
        }
    }

    func testSwitchIsACheckboxAndPressToggles() {
        let switchView = SwitchView()
        switchView.setAccessibilityLabel("Notifications")
        host(switchView)
        XCTAssertEqual(switchView.accessibilityRole(), .checkBox)
        XCTAssertEqual(switchView.accessibilityValue() as? NSNumber, 0)
        let committed = expectation(description: "Switch settled")
        switchView.stateChanged = { committed.fulfill() }
        XCTAssertTrue(switchView.accessibilityPerformPress())
        XCTAssertEqual(switchView.accessibilityValue() as? NSNumber, 0)
        wait(for: [committed], timeout: 2)
        XCTAssertEqual(switchView.accessibilityValue() as? NSNumber, 1)
        XCTAssertEqual(AccessibilityAudit.audit(window), [])
    }

    func testImagesNeedADescriptionOrADecorativeMark() {
        let image = ImageView(frame: NSMakeRect(0, 0, 40, 40))
        image.image = testImage(CGSize(width: 40, height: 40))
        host(image)
        XCTAssertFalse(image.isAccessibilityElement())
        XCTAssertEqual(AccessibilityAudit.audit(window).map(\.kind), [.unlabeledImage])
        image.setAccessibilityLabel("Avatar")
        XCTAssertTrue(image.isAccessibilityElement())
        XCTAssertEqual(image.accessibilityRole(), .image)
        XCTAssertEqual(AccessibilityAudit.audit(window), [])
        image.setAccessibilityLabel(nil)
        image.isAccessibilityDecorative = true
        XCTAssertEqual(AccessibilityAudit.audit(window), [])
    }

    func testButtonImageIsNotReportedSeparately() {
        let button = iconButton()
        button.setAccessibilityLabel("Back")
        button.set(handler: { _ in }, for: .Click)
        host(button)
        XCTAssertEqual(AccessibilityAudit.audit(window), [])
    }

    func testTableIsAListOfLabeledRows() {
        let table = TableView(frame: NSMakeRect(0, 0, 400, 400))
        host(table)
        let items = (0 ..< 5).map { LabeledRowItem(NSMakeSize(400, 60), title: "Row \($0)", stableId: $0) }
        for item in items {
            _ = table.addItem(item: item)
        }
        table.layoutSubtreeIfNeeded()
        let list = table.tableView
        XCTAssertTrue(list.isAccessibilityElement())
        XCTAssertEqual(list.accessibilityRole(), .list)
        XCTAssertEqual(list.accessibilityColumnCount(), 0)
        XCTAssertNil(list.accessibilityCell(forColumn: 0, row: 0))
        let rows = list.accessibilityRowViews()
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows.first?.accessibilityLabel(), "Row 0")
        XCTAssertEqual(rows.first?.accessibilityValue() as? String, "value Row 0")
        XCTAssertTrue(rows.first?.isAccessibilityElement() ?? false)
        XCTAssertTrue(rows[2].accessibilityPerformPress())
        XCTAssertTrue(items[2].pressed)
        let labels = AccessibilityAudit.elements(window.contentView!).compactMap { $0.accessibilityLabel() }
        XCTAssertTrue(labels.contains("Row 4"))
        XCTAssertEqual(AccessibilityAudit.audit(window), [])
    }

    func testSwitchOffRestoresTheOldDetachedTree() {
        let button = iconButton()
        button.setAccessibilityLabel("Send")
        button.set(handler: { _ in }, for: .Click)
        host(button)
        TGUIKitAccessibility.isEnabled = false
        XCTAssertFalse(button.isAccessibilityElement())
        XCTAssertNil(button.accessibilityParent())
    }
    func testContextMenuRowsAreMenuItems() {
        var invoked: [String] = []
        var submenus: [String] = []
        let interaction = AppMenuBasicItem.Interaction(action: { invoked.append($0.title) }, presentSubmenu: { submenus.append($0.title) }, cancelSubmenu: { _ in }, hover: { _ in }, close: {})
        let presentation = AppMenu.Presentation.current(PresentationTheme.current.colors)
        let copy = ContextMenuItem("Copy", handler: {})
        let pinned = ContextMenuItem("Pin", handler: {}, state: .on)
        let more = ContextMenuItem("More")
        more.submenu = ContextMenu()
        let disabled = ContextMenuItem("Delete", handler: {})
        disabled.isEnabled = false
        let rows = [copy, pinned, more, disabled].map { AppMenuRowItem(.zero, item: $0, interaction: interaction, presentation: presentation) }
        let separator = AppMenuSeparatorItem(.zero, presentation: presentation)
        let spacer = AppMenuBasicItem(.zero, presentation: presentation)

        XCTAssertEqual(rows.map { $0.accessibilityLabel }, ["Copy", "Pin", "More", "Delete"])
        XCTAssertEqual(rows.map { $0.accessibilityRole }, Array(repeating: .menuItem, count: 4))
        XCTAssertNil(rows[0].accessibilityValue)
        XCTAssertNotNil(rows[1].accessibilityValue)
        XCTAssertFalse(rows[0].accessibilityIncludesChildren)
        XCTAssertTrue(separator.accessibilityIsSpacer)
        XCTAssertTrue(spacer.accessibilityIsSpacer)
        XCTAssertFalse(rows[0].accessibilityIsSpacer)

        XCTAssertTrue(rows[0].accessibilityPerformPress())
        XCTAssertTrue(rows[2].accessibilityPerformPress())
        XCTAssertFalse(rows[3].accessibilityIsEnabled)
        XCTAssertFalse(rows[3].accessibilityPerformPress())
        XCTAssertEqual(invoked, ["Copy"])
        XCTAssertEqual(submenus, ["More"])
    }
    func testContextMenuSubmenuRowIsSelectedWhenPressed() {
        var invoked: [String] = []
        var submenus: [String] = []
        let interaction = AppMenuBasicItem.Interaction(action: { invoked.append($0.title) }, presentSubmenu: { submenus.append($0.title) }, cancelSubmenu: { _ in }, hover: { _ in }, close: {})
        let copy = ContextMenuItem("Copy", handler: {})
        let more = ContextMenuItem("More")
        more.submenu = ContextMenu()
        let menu = ContextMenu()
        [copy, more].forEach(menu.addItem)
        let view = MenuView(frame: NSMakeRect(0, 0, 300, 400))
        view.merge(menu: menu, presentation: .current(PresentationTheme.current.colors), interaction: interaction)
        guard let copyRow = view.item(for: copy.id), let moreRow = view.item(for: more.id) else {
            return XCTFail("menu rows")
        }

        XCTAssertTrue(moreRow.accessibilityPerformPress())
        XCTAssertTrue(moreRow.isSelected)
        XCTAssertTrue(copyRow.accessibilityPerformPress())
        XCTAssertTrue(moreRow.isSelected)
        XCTAssertFalse(copyRow.isSelected)
        XCTAssertEqual(invoked, ["Copy"])
        XCTAssertEqual(submenus, ["More"])
    }
    func testSegmentTabsAreRadioButtons() {
        let segment = ScrollableSegmentView(frame: NSMakeRect(0, 0, 400, 40))
        host(segment)
        let theme = ScrollableSegmentTheme.standard(PresentationTheme.current.colors)
        var chosen: [String] = []
        segment.didChangeSelectedItem = { chosen.append($0.title) }
        let items = ["All", "Unread", "Work"].enumerated().map { ScrollableSegmentItem(title: $0.element, index: $0.offset, uniqueId: Int64($0.offset), selected: $0.offset == 0, insets: NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10), icon: nil, theme: theme, equatable: nil) }
        segment.updateItems(items, animated: false)
        segment.layoutSubtreeIfNeeded()
        let tabs = AccessibilityAudit.elements(segment).filter { $0.accessibilityRole() == .radioButton }
        XCTAssertEqual(tabs.compactMap { $0.accessibilityLabel() }, ["All", "Unread", "Work"])
        XCTAssertEqual((tabs.first?.accessibilityValue() as? NSNumber)?.boolValue, true)
        XCTAssertEqual((tabs.last?.accessibilityValue() as? NSNumber)?.boolValue, false)
        XCTAssertTrue(tabs.last?.accessibilityPerformPress() ?? false)
        XCTAssertEqual(chosen, ["Work"])
        XCTAssertEqual(AccessibilityAudit.audit(segment), [])
    }
    func testDynamicCounterReadsItsWholeText() {
        let counter = DynamicCounterTextView(frame: NSMakeRect(0, 0, 200, 20))
        host(counter)
        let value = DynamicCounterTextView.make(for: "12 participants", count: "12", font: .normal(13), textColor: .black, width: 200)
        counter.update(value, animated: false)
        XCTAssertTrue(counter.isAccessibilityElement())
        XCTAssertEqual(counter.accessibilityRole(), .staticText)
        XCTAssertEqual(counter.accessibilityValue() as? String, "12 participants")
        XCTAssertEqual(counter.accessibilityChildren()?.count, 0)
    }
    func testSeekBarIsAnAdjustableSlider() {
        let bar = LinearProgressControl(progressHeight: 4)
        bar.frame = NSMakeRect(0, 0, 200, 10)
        host(bar)
        XCTAssertFalse(bar.isAccessibilityElement())
        var changes: [Float] = []
        bar.onUserChanged = { changes.append($0) }
        bar.set(progress: 0.5)
        XCTAssertTrue(bar.isAccessibilityElement())
        XCTAssertEqual(bar.accessibilityRole(), .slider)
        XCTAssertEqual(bar.accessibilityValue() as? String, "50%")
        XCTAssertNotNil(bar.accessibilityLabel())
        XCTAssertTrue(bar.accessibilityPerformIncrement())
        XCTAssertEqual(bar.accessibilityValue() as? String, "55%")
        XCTAssertTrue(bar.accessibilityPerformDecrement())
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes.last ?? 0, 0.5, accuracy: 0.001)
        bar.setAccessibilityValue("1:00 / 2:00")
        XCTAssertEqual(bar.accessibilityValue() as? String, "1:00 / 2:00")
    }

    func testDownloadProgressReadsItsStateAndPercent() {
        let progress = RadialProgressView()
        host(progress)
        progress.state = .Remote
        progress.set(handler: { _ in }, for: .Click)
        XCTAssertEqual(progress.accessibilityRole(), .button)
        XCTAssertEqual(progress.accessibilityLabel(), localizedString("VoiceOver.Common.Download"))
        progress.state = .Fetching(progress: 0.42, force: false)
        XCTAssertEqual(progress.accessibilityLabel(), localizedString("VoiceOver.Common.CancelDownload"))
        XCTAssertEqual(progress.accessibilityValue() as? String, "42%")
        let upload = RadialProgressView()
        host(upload)
        upload.state = .ImpossibleFetching(progress: 0.1, force: false)
        XCTAssertTrue(upload.isAccessibilityElement())
        XCTAssertEqual(upload.accessibilityRole(), .progressIndicator)
        XCTAssertEqual(upload.accessibilityValue() as? String, "10%")
    }
    func testClickableContainerWithButtonsIsAGroup() {
        let container = Control(frame: NSMakeRect(0, 0, 300, 50))
        container.set(handler: { _ in }, for: .Click)
        container.setAccessibilityLabel("Header")
        let settings = iconButton()
        settings.setAccessibilityLabel("Settings")
        settings.set(handler: { _ in }, for: .Click)
        container.addSubview(settings)
        host(container)
        XCTAssertEqual(container.accessibilityRole(), .group)
        let labels = AccessibilityAudit.elements(container).compactMap { $0.accessibilityLabel() }
        XCTAssertTrue(labels.contains("Settings"))
        settings.isHidden = true
        XCTAssertEqual(container.accessibilityRole(), .button)
    }
    func testCollapsedRowExposesHiddenButtonsAndPressesItsClickArea() {
        let table = TableView(frame: NSMakeRect(0, 0, 400, 400))
        host(table)
        let item = CollapsedRowItem(NSMakeSize(400, 60), stableId: 0)
        _ = table.addItem(item: item)
        table.layoutSubtreeIfNeeded()
        guard let row = table.tableView.accessibilityRowViews().first as? CollapsedRowView else {
            return XCTFail("no row view")
        }
        XCTAssertEqual(row.accessibilityChildren()?.count, 0)
        let actions = row.accessibilityCustomActions() ?? []
        XCTAssertEqual(actions.map { $0.name }, ["Info", localizedString("VoiceOver.Common.Toggle")])
        XCTAssertTrue(actions[0].handler?() ?? false)
        XCTAssertEqual(row.events, ["info"])
        XCTAssertTrue(row.accessibilityPerformPress())
        XCTAssertEqual(row.events, ["info", "open"])
    }
}
