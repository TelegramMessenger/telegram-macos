import Cocoa
import Foundation

var checks = 0
var failures: [String] = []
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !value() { failures.append(message) }
}

let command: NSEvent.ModifierFlags = [.command]
check(browserFindAction(character: "f", modifiers: command) == .showFindInterface, "Command-F opens page find")
check(browserFindAction(character: "F", modifiers: [.command, .capsLock]) == .showFindInterface, "Caps Lock does not suppress Find")
check(browserFindAction(character: "g", modifiers: command) == .nextMatch, "Command-G moves forward")
check(browserFindAction(character: "g", modifiers: [.command, .shift]) == .previousMatch, "Shift-Command-G moves backward")
for flags: NSEvent.ModifierFlags in [[], [.shift], [.option], [.control], [.command, .option], [.command, .control], [.command, .shift, .option], [.command, .shift, .control]] {
    check(browserFindAction(character: "f", modifiers: flags) == nil, "Other F modifiers are not intercepted")
    check(browserFindAction(character: "g", modifiers: flags) == nil, "Other G modifiers are not intercepted")
}
check(browserFindAction(character: "f", modifiers: [.command, .shift]) == nil, "Shift-Command-F remains available to other handlers")
check(browserFindAction(character: nil, modifiers: command) == nil, "Missing character remains unhandled")
check(browserFindAction(character: "a", modifiers: command) == nil, "Unrelated shortcuts remain unhandled")
for width in [0.0, 1.0, 320.0, 420.0, 1000.0] {
    for height in [0.0, 1.0, 20.0, 32.0, 400.0] {
        let bounds = NSRect(x: 3, y: 7, width: width, height: height)
        for findHeight in [-1.0, 0.0, 24.0, 32.0, 80.0] {
            let hidden = browserFindContentFrame(bounds: bounds, findBarHeight: findHeight, visible: false)
            check(hidden == bounds, "Hidden bar restores full page bounds")
            let shown = browserFindContentFrame(bounds: bounds, findBarHeight: findHeight, visible: true)
            check(shown.width == bounds.width && shown.minX == bounds.minX, "Find preserves page width/origin")
            check(shown.height >= 0 && shown.minY >= bounds.minY && shown.maxY == bounds.maxY, "Find content stays inside bounds")
        }
    }
}

let finder = NSTextFinder()
let helper = BrowserPageFind()
check(!helper.isVisible && !helper.perform(.showFindInterface), "Unattached finder does not claim handled")
let first = WKWebView()
let container = FindContainer()
helper.attach(webView: first, container: container)
check(NSTextFinder.latest?.client === first, "Native client is the current webview")
check(NSTextFinder.latest?.isIncrementalSearchingEnabled == true, "Incremental native search is enabled")
check(NSTextFinder.latest?.incrementalSearchingShouldDimContentView == true, "Native incremental highlights remain enabled")
check(helper.perform(.showFindInterface), "Show action is handled")
check(helper.isVisible, "Find bar belongs to its page container")
check(container.pageFindBar != nil, "Telegram find bar replaces native macOS presentation")
container.pageFindBar?.query = "target"
container.pageFindBar?.queryUpdated?("target")
check(first.searches.map { $0.0 } == ["target"], "Typing reaches public WebKit search")
check(container.pageFindBar?.found == true, "Match feedback reaches Telegram field")
check(helper.perform(.nextMatch) && helper.perform(.previousMatch), "Match navigation reaches public WebKit search")
check(first.searches.map { $0.1 } == [false, false, true], "Previous and next preserve their direction")
check(!helper.perform(.replaceAll), "Page finder does not expose editing actions")
let beforeReattach = NSTextFinder.latest?.actions.count
helper.attach(webView: first, container: container)
check(NSTextFinder.latest?.actions.count == beforeReattach, "Repeated attach does not reset active query")
check(helper.dismiss(restoreFocus: false) && !helper.isVisible, "Escape closes only visible find interface")
check(!helper.dismiss(), "Second Escape can fall through to page navigation")
_ = helper.perform(.showFindInterface)
first.url = URL(string: "https://example.invalid/next")
check(!helper.isVisible, "Navigation hides stale find interface")
check((NSTextFinder.latest?.notes ?? 0) > 0, "Navigation invalidates finder text")
_ = helper.perform(.showFindInterface)
first.isLoading = true
check(!helper.isVisible, "Reload cancels old results")
let second = WKWebView()
helper.attach(webView: second, container: container)
_ = helper.perform(.showFindInterface)
let beforeOldNavigation = NSTextFinder.latest?.notes
first.url = URL(string: "https://example.invalid/stale")
check(helper.isVisible && NSTextFinder.latest?.notes == beforeOldNavigation, "Old tab observation is detached")
second.url = URL(string: "https://example.invalid/current")
check(!helper.isVisible, "Current tab navigation is observed")

let delayedPage = WKWebView()
delayedPage.deferred = true
let delayedContainer = FindContainer()
let delayedHelper = BrowserPageFind()
delayedHelper.attach(webView: delayedPage, container: delayedContainer)
_ = delayedHelper.perform(.showFindInterface)
delayedContainer.pageFindBar?.query = "target"
delayedContainer.pageFindBar?.queryUpdated?("target")
_ = delayedHelper.perform(.nextMatch)
_ = delayedHelper.perform(.nextMatch)
_ = delayedHelper.perform(.nextMatch)
check(delayedPage.searches.count == 1, "Only one WebKit request may be in flight")
delayedPage.drain()
check(delayedPage.searches.map { $0.0 } == ["target", "target", "target", "target"], "Three rapid Next commands survive an in-flight query")
check(delayedContainer.pageFindBar?.loading == false, "Loading ends after navigation drains")
let navigationStart = delayedPage.searches.count
for backwards in [true, false, true] { delayedContainer.pageFindBar?.navigate?(backwards) }
delayedPage.drain()
check(Array(delayedPage.searches.dropFirst(navigationStart)).map { $0.1 } == [true, false, true], "Bar buttons preserve ordered Previous/Next steps")
let editStart = delayedPage.searches.count
_ = delayedHelper.perform(.previousMatch)
_ = delayedHelper.perform(.nextMatch)
delayedContainer.pageFindBar?.query = "new"
delayedContainer.pageFindBar?.queryUpdated?("new")
_ = delayedHelper.perform(.previousMatch)
_ = delayedHelper.perform(.nextMatch)
delayedPage.drain()
check(Array(delayedPage.searches.dropFirst(editStart)).map { $0.0 } == ["target", "new", "new", "new"], "Editing replaces old queued navigation but retains new-query steps")
let closeStart = delayedPage.searches.count
_ = delayedHelper.perform(.nextMatch)
_ = delayedHelper.perform(.previousMatch)
_ = delayedHelper.dismiss(restoreFocus: false)
delayedPage.drain()
check(Array(delayedPage.searches.dropFirst(closeStart)).map { $0.0 } == ["new", ""], "Closing drops queued navigation and clears the old page")
check(!delayedHelper.isVisible, "Completion after closing does not reopen the bar")
_ = delayedHelper.perform(.showFindInterface)
delayedContainer.pageFindBar?.query = "old-page"
delayedContainer.pageFindBar?.queryUpdated?("old-page")
_ = delayedHelper.perform(.nextMatch)
let replacementPage = WKWebView()
delayedHelper.attach(webView: replacementPage, container: delayedContainer)
_ = delayedHelper.perform(.showFindInterface)
delayedContainer.pageFindBar?.query = "replacement"
delayedContainer.pageFindBar?.queryUpdated?("replacement")
delayedPage.drain()
check(replacementPage.searches.map { $0.0 } == ["replacement"], "Retargeted page never receives the previous page's navigation")
check(delayedContainer.pageFindBar?.found == true, "Old page's late clear does not overwrite current match feedback")

print("BROWSER_FIND_RESULT checks=\(checks) failures=\(failures.count)")
for failure in failures { print("FAIL: \(failure)") }
exit(failures.isEmpty ? 0 : 1)
