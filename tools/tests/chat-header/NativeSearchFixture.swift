import AppKit
import TGUIKit

final class InputContextControllerFixture {
    var frame = CGRect.zero
    let view = View()
}

final class InputContextFixture {
    let controller = InputContextControllerFixture()
    func updateLayout(animated: Bool) {}
}

final class NativeSearchFixture: View {
    let searchContainer = View()
    let searchView = SearchView(frame: NSMakeRect(0, 0, 200, 30))
    let prev = ImageButton()
    let next = ImageButton()
    let from = ImageButton()
    let calendar = ImageButton()
    let cancel = ImageButton()
    let countContainer = View()
    var countWidth: CGFloat = 0
    let inputContextHelper = InputContextFixture()
    var tagsView: View?

    required init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(searchContainer)
        searchContainer.addSubview(searchView)
        for button in [prev, next, from, calendar, cancel] {
            button.setFrameSize(NSSize(width: 20, height: 20))
            searchContainer.addSubview(button)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    __SEARCH_AUX__

    __SEARCH_WIDTH__

    __SEARCH_LAYOUT__
}

func runNativeSearchChecks() {
    let window = NSWindow(contentRect: CGRect(x: -4000, y: -4000, width: 1100, height: 125), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let root = View(frame: CGRect(x: 0, y: 0, width: 1100, height: 125))
    window.contentView = root
    let controller = ControllerFixture()
    controller.header.state = HeaderState(main: .search(0, nil, nil, nil, nil, 0))
    let search = NativeSearchFixture(frame: controller.headerFrame())
    root.addSubview(search)
    let before = checks

    for showFrom in [false, true] {
        search.from.isHidden = !showFrom
        for showCalendar in [false, true] {
            search.calendar.isHidden = !showCalendar
            for width: CGFloat in [1100, 800, 650, 520, 350, 900] {
                controller.frame.size.width = width
                root.setFrameSize(CGSize(width: width, height: 125))
                search.frame = controller.headerFrame()
                search.updateLayout(size: search.frame.size, transition: .immediate)
                search.searchView.change(state: .Focus, false)
                check(window.makeFirstResponder(search.searchView.input), "search refused keyboard focus")
                search.searchView.setString("retained query")
                search.frame = controller.headerFrame(overflow: 7)
                search.updateLayout(size: search.frame.size, transition: .immediate)
                check(window.firstResponder === search.searchView.input, "resize lost input focus")
                check(search.searchView.query == "retained query", "resize cleared query")
                check(search.searchView.frame.width >= 120, "search input became unusably narrow")

                let buttons = [search.prev, search.next, search.from, search.calendar, search.cancel].filter { !$0.isHidden }
                for button in buttons {
                    check(button.frame.minX >= search.searchView.frame.maxX && button.frame.maxX <= search.frame.width, "search action clipped or covered the input")
                    let point = CGPoint(x: button.frame.midX, y: button.frame.midY)
                    check(search.searchContainer.hitTest(point) === button, "search action did not receive clicks")
                }
            }
        }
    }

    window.makeFirstResponder(nil)
    print("PASS: \(checks - before) native TGUIKit search focus, query, control-bound and hit-test checks")
}
