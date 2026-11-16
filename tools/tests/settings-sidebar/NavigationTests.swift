import Foundation

struct Stake { var keepLeft: Int = 0 }
class ViewController {
    var removeAfterDisapper = false
    var stake = Stake()
    func navigationWillChangeController() {}
}
class ChatController: ViewController {}
class PeerInfoController: ViewController {}
class ChannelAdminsViewController: ViewController {}
class EmptyChatViewController: ViewController {}
class AccountViewController: ViewController {}
class InputDataController: ViewController {
 var identifier = ""
 override init() { super.init(); removeAfterDisapper = true }
}
class GeneralSettingsViewController: ViewController {
    init(_ context: Context) {}
}
enum Layout { case single, dual, minimisize }
final class Navigation: ViewController {
    var stack: [ViewController]
    weak var listener: ViewController?
    var toCalls = 0
    var controller: ViewController { stack.last! }
    init(_ controller: ViewController) { stack = [controller] }
    func push(_ controller: ViewController, _ animated: Bool = true, clearStack: Bool = false) {
        let previous = self.controller
        if clearStack { stack = [stack[0]] }
        if previous.removeAfterDisapper || previous.stake.keepLeft > 0 {
            stack.removeAll { $0 === previous }
        }
        stack.append(controller)
        listener?.navigationWillChangeController()
    }
    func back() {
        if stack.count > 1 {
            stack.removeLast()
            listener?.navigationWillChangeController()
        }
    }
    func enumerateControllers(_ body: (ViewController, Int) -> Bool) {
        for index in stack.indices.reversed() {
            if body(stack[index], index) { break }
        }
    }
    func to(index: Int) {
        toCalls += 1
        stack = Array(stack.prefix(index + 1))
        listener?.navigationWillChangeController()
    }
}
final class Bindings {
    let root: Navigation
    init(_ root: Navigation) { self.root = root }
    func rootNavigation() -> Navigation { root }
}
final class Context {
    let bindings: Bindings
    var layout = Layout.dual
    init(_ root: Navigation) { bindings = Bindings(root) }
}
struct Tab { let controller: ViewController }
final class TabController {
    var tabs: [Tab]
    var selectedIndex = 2
    var changed: ((Int) -> Void)?
    var current: ViewController? { tabs[selectedIndex].controller }
    var count: Int { tabs.count }
    init(_ tabs: [ViewController]) { self.tabs = tabs.map(Tab.init) }
    func tab(at index: Int) -> Tab { tabs[index] }
    func select(index: Int) {
        if index != selectedIndex {
            selectedIndex = index
            changed?(index)
        }
    }
}
final class Popover { func hide() {} }
final class QuickController { var popover: Popover? }
final class MainController: ViewController {
    let context: Context
    let settings = AccountViewController()
    let navigation = ViewController()
    let contacts = ViewController()
    let calls = ViewController()
    let tabController: TabController
    var quickController: QuickController?
    var chatIndex: Int { tabController.tabs.firstIndex(where: { $0.controller === navigation })! }
    init(_ root: ViewController = ChatController()) {
        context = Context(Navigation(root))
        tabController = TabController([])
        super.init()
        tabController.tabs = [contacts, calls, navigation, settings].map(Tab.init)
        tabController.changed = { [weak self] in self?.checkSettings($0) }
        context.bindings.root.listener = self
        checkSettings(2)
    }
    func enterSettings() { tabController.select(index: tabController.count - 1) }
__METHODS__
}

var failures = 0
var checks = 0
func check(_ value: Bool, _ name: String) {
    checks += 1
    print("\(value ? "PASS" : "FAIL"): \(name)")
    if !value { failures += 1 }
}
do {
    let main = MainController()
    let chat = main.context.bindings.root.controller
    main.enterSettings()
    check(main.tabController.current === main.settings && main.context.bindings.root.controller is GeneralSettingsViewController, "enter Settings keeps Settings sidebar")
    main.context.bindings.root.back()
    check(main.tabController.current === main.navigation && main.context.bindings.root.controller === chat, "Back restores chat and Chats sidebar together")
    check(main.context.bindings.root.toCalls == 0, "sidebar restoration never navigates the content stack a second time")
}
do {
    let main = MainController()
    let chat = main.context.bindings.root.controller
    main.enterSettings()
    main.context.bindings.root.push(InputDataController())
    main.context.bindings.root.back()
    check(main.tabController.current === main.settings && main.context.bindings.root.controller is GeneralSettingsViewController, "Back within nested settings retains Settings sidebar")
    main.context.bindings.root.back()
    check(main.tabController.current === main.navigation && main.context.bindings.root.controller === chat, "second Back leaves nested settings and restores Chats")
    main.enterSettings()
    main.tabController.select(index: 2)
    check(main.tabController.current === main.navigation && main.context.bindings.root.controller === chat, "explicit Chats selection still restores the previous content")
    main.enterSettings()
    main.context.bindings.root.back()
    check(main.tabController.current === main.navigation, "repeated entry and Back refresh the saved return target")
}
do {
    let main = MainController(PeerInfoController())
    let profile = main.context.bindings.root.controller
    main.enterSettings()
    main.context.bindings.root.back()
    check(main.context.bindings.root.controller === profile && main.tabController.current === main.navigation, "Back preserves an already-open peer profile")
}
do {
    let main = MainController(EmptyChatViewController())
    main.enterSettings()
    main.context.bindings.root.back()
    check(main.tabController.current === main.navigation, "empty detail pane restores Chats too")
}
do {
    let main = MainController()
    main.tabController.select(index: 0)
    main.enterSettings()
    main.context.bindings.root.back()
    check(main.tabController.current === main.contacts, "entry from Contacts restores Contacts rather than forcing Chats")
}
do {
    let main = MainController()
    main.enterSettings()
    main.tabController.tabs.remove(at: 1)
    main.tabController.selectedIndex = 2
    main.context.bindings.root.back()
    check(main.tabController.current === main.navigation, "return sidebar follows controller identity when Calls tab is removed")
}
do {
    let main = MainController()
    main.context.layout = .single
    let root = main.context.bindings.root.controller
    main.enterSettings()
    main.navigationWillChangeController()
    check(main.context.bindings.root.controller === root && main.tabController.current === main.settings, "single-column Settings does not install a wide-layout return target")
}
do {
    let main = MainController()
    let wallet = InputDataController()
    wallet.identifier = "wallet-create"
    main.context.bindings.root.push(wallet)
    main.enterSettings()
    main.navigationWillChangeController()
    check(main.context.bindings.root.controller === wallet && main.tabController.current === main.settings, "wallet-create exception keeps its navigation unchanged")
}
do {
    let main = MainController(EmptyChatViewController())
    main.enterSettings()
    main.context.bindings.root.push(InputDataController(), clearStack: true)
    main.context.bindings.root.back()
    check(main.tabController.current === main.settings, "Back inside a replaced Settings stack does not switch to Chats")
}
do {
    let main = MainController()
    main.tabController.select(index: 1)
    main.enterSettings()
    main.tabController.tabs.remove(at: 1)
    main.tabController.selectedIndex = 2
    main.context.bindings.root.back()
    check(main.tabController.current === main.navigation, "removed return sidebar falls back to Chats")
    main.enterSettings()
    main.context.bindings.root.back()
    check(main.tabController.current === main.navigation, "fallback clears stale Settings return state")
}
for transientKind in ["input", "keepLeft"] {
 let main = MainController()
 let root = main.context.bindings.root.controller
 let transient: ViewController = transientKind == "input" ? InputDataController() : ViewController()
 if transientKind == "keepLeft" { transient.stake.keepLeft = 1 }
 main.context.bindings.root.push(transient)
 main.enterSettings()
 check(!main.context.bindings.root.stack.contains { $0 === transient }, "Settings push removes transient \(transientKind) detail")
 main.context.bindings.root.back()
 check(main.context.bindings.root.controller === root && main.tabController.current === main.navigation, "Back restores surviving detail and Chats after \(transientKind) removal")
}
print("\(checks - failures)/\(checks) behavior checks passed")
exit(failures == 0 ? 0 : 1)
