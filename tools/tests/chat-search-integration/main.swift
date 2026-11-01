import AppKit
import ColorPalette
import SwiftSignalKit
import TGUIKit

_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)
let assets = imagePaths.map { name, path -> NSImage in
  let image = NSImage(contentsOfFile: path)!
  image.setName(name)
  return image
}
let initial = PresentationTheme.current
let appearance = TelegramPresentationTheme(
  colors: nightAccentPalette,
  search: SearchTheme(
    nightAccentPalette.grayBackground,
    NSImage(named: "Icon_SearchField")!.precomposed(nightAccentPalette.grayText),
    NSImage(named: "Icon_SearchClear")!.precomposed(nightAccentPalette.grayText), { "Search" },
    nightAccentPalette.text, nightAccentPalette.grayText), inputTheme: initial.inputTheme)
theme = appearance
updateTheme(appearance)
System.liquidGlass = true
let window = Window(
  contentRect: NSMakeRect(130, 130, 1000, 550), styleMask: [.titled, .resizable, .closable],
  backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
window.title = "PR40 search integration — generic data"
let root = View(frame: NSMakeRect(0, 0, 1000, 550))
root.backgroundColor = theme.colors.background
window.contentView = root
let context = FixtureContext(window)
let interaction = ChatInteraction(
  chatLocation: .peer(.init(value: 1)), context: context, mode: .history)
interaction.presentation.peer = Peer(1, "Project Updates", group: true)
var requests: [(String, PeerId?)] = []
var jumps: [MessageId] = []
var cancellations = 0
let status = NSTextField(
  labelWithString: "Native search controls · controlled test data · no Telegram account")
status.textColor = theme.colors.grayText
status.frame = NSMakeRect(20, 480, 950, 24)
root.addSubview(status)
var closeSearch: () -> Void = {}
let operations = ChatSearchInteractions(
  searchRequest: { query, peer, _, _ in
    requests.append((query, peer))
    status.stringValue = "Request: \(query) · sender \(peer?.value.description ?? "any")"
    return .single(
      (
        [
          Message(id: .init(value: 1), text: "\(query) — first result"),
          Message(id: .init(value: 2), text: "\(query) — second result"),
          Message(id: .init(value: 3), text: "\(query) — third result"),
        ], .init(offset: 0), 3
      ))
  },
  jump: { message in
    jumps.append(message.id)
    status.stringValue = "Jumped to result #\(message.id.value)"
  }, cancel: { closeSearch() }, calendarAction: { _ in })
let state = ChatHeaderState(main: .search(operations, nil, nil, nil, nil, interaction.chatLocation))
let host = View()
root.addSubview(host)
let search = ChatSearchHeader(interaction, state: state, frame: NSMakeRect(0, 0, 600, 40))
host.addSubview(search)
closeSearch = {
  search.remove(animated: false)
  host.removeFromSuperview()
  window.makeFirstResponder(nil)
  cancellations += 1
  status.stringValue = "Search closed"
}
interaction.clearSearch = closeSearch
func drain(_ seconds: Double = 0.1) { RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds)) }
var checks = 0
var failures: [String] = []
func check(_ v: @autoclosure () -> Bool, _ message: String) {
  if !v() {
    failures.append(message)
    print("FAIL: \(message)")
    fflush(stdout)
  }
  checks += 1
}
func layout(width: CGFloat, height: CGFloat = 550) {
  root.setFrameSize(NSMakeSize(width, height))
  let geometry = ControllerGeometry(header: HeaderFixture(state: state))
  let inline = geometry.inlineHeaderFrame(for: width)
  host.frame = inline ?? NSMakeRect(12, 62, width - 24, 40)
  search.frame = host.bounds
  search.updateLayout(size: host.frame.size, transition: .immediate)
  root.layoutSubtreeIfNeeded()
  drain(0.03)
}
func verifyResults(_ context: String) {
  guard let popup = search.testContext.accessoryView else {
    check(false, "No search results: \(context)")
    return
  }
  let anchor = host.convert(host.bounds, to: root)
  check(
    abs(popup.frame.minX - root.bounds.minX - 12) < 0.1,
    "Results moved away from chat edge: \(context), \(popup.frame) vs \(anchor)")
  check(abs(popup.frame.minY - anchor.maxY - 10) < 0.1, "Results overlap the header: \(context)")
  check(abs(popup.frame.width - root.bounds.width + 24) < 0.1, "Results width differs from chat: \(context)")
  check(
    root.bounds.contains(popup.frame), "Results clipped outside chat: \(context), \(popup.frame)")
  check(
    search.testContext.controller.view.bounds.size == popup.bounds.size,
    "Results list and container disagree: \(context)")
  check(
    popup.hitTest(NSMakePoint(popup.frame.minX + 20, popup.frame.minY + 20)) != nil,
    "Results cannot receive clicks: \(context)")
}
runEmptySearchChecks(search)
layout(width: 1000)
window.makeKeyAndOrderFront(nil)
drain()
if Bundle.main.bundleIdentifier == "local.codex.telegram.SearchIntegration" {
  NSApp.setActivationPolicy(.regular)
  let menu = NSMenu()
  let applicationItem = NSMenuItem()
  menu.addItem(applicationItem)
  let applicationMenu = NSMenu()
  applicationMenu.addItem(withTitle: "Quit Search Validation", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
  applicationItem.submenu = applicationMenu
  NSApp.mainMenu = menu
  NSApp.run()
}
check(
  window.firstResponder === search.testSearchView.input,
  "Opening search did not focus the actual ChatSearchView")
search.testSearchView.input.insertText(
  "Designer from San Francisco", replacementRange: NSRange(location: NSNotFound, length: 0))
drain(0.6)
check(requests.last?.0 == "Designer from San Francisco", "Typing did not reach the search request")
check(
  search.testContext.results.count == 3, "Search response did not reach the visible result list")
verifyResults("initial query")
#if UPSTREAM_SEARCH_RESULT_COUNTER
check(jumps.last?.value == 1, "Upstream automatic first-result selection was lost")
check(search.testCount.current == 1 && search.testCount.total == 3, "Upstream result counter was lost")
check(!search.testCountIsHidden, "Result counter is hidden with sufficient space")
#endif
for width: CGFloat in [742, 600, 360, 1000, 1200, 742] {
  layout(width: width)
  check(window.firstResponder === search.testSearchView.input, "Resize stole input focus")
  check(search.testSearchView.query == "Designer from San Francisco", "Resize changed the query")
  if let clip = search.testSearchView.input.enclosingScrollView?.contentView {
    check(
      clip.frame.width >= (width >= 600 ? 210 : 80),
      "Search text viewport is too short: \(clip.frame.width) at \(width)")
  }
  #if UPSTREAM_SEARCH_RESULT_COUNTER
  if width == 360 {
    check(search.testCountIsHidden, "Result counter crowds the narrow search input")
  } else if width >= 1000 {
    check(!search.testCountIsHidden, "Result counter does not return after widening")
  }
  #endif
  verifyResults("resize to \(width)")
}
layout(width: 742, height: 180)
verifyResults("short window")
layout(width: 1000)
#if UPSTREAM_SEARCH_RESULT_COUNTER
let navigationTargets = [2, 3, 2]
#else
let navigationTargets = [1, 2, 1]
#endif
search.testButtons[0].send(event: .Click)
check(jumps.last?.value == navigationTargets[0], "Previous-result button did not advance from the selected result")
search.testButtons[0].send(event: .Click)
check(jumps.last?.value == navigationTargets[1], "Previous-result button did not advance")
search.testButtons[1].send(event: .Click)
check(jumps.last?.value == navigationTargets[2], "Next-result button did not go back")
search.applySearchResponder(false)
drain()
verifyResults("refocus after jumping")
#if UPSTREAM_SEARCH_RESULT_COUNTER
search.testContext.controller.selected?(search.testContext.results[2])
check(search.testCount.current == 3, "Selecting a result row did not update the counter")
check(!search.testButtons[0].isEnabled && search.testButtons[1].isEnabled, "Selecting the last result left stale navigation buttons")
#endif
interaction.presentation.peer = Peer(1, "Project Group", group: true)
search.update(with: state, animated: false)
search.testButtons[2].send(event: .Click)
drain()
check(
  search.testSearchView.tokenState == .from(query: "", complete: false),
  "Sender filter button did not start a token")
check(search.testContext.results.count == 2, "Sender suggestions are missing")
search.testContext.controller.selected?(search.testContext.results[0])
drain(0.6)
check(search.testPeerId?.value == 42, "Selecting a sender did not update peer filter")
search.testSearchView.input.insertText(
  "hello", replacementRange: NSRange(location: NSNotFound, length: 0))
drain(0.6)
check(requests.last?.1?.value == 42, "Sender filter was not sent with the request")
check(requests.last?.0 == "hello", "Text query after sender selection was lost")
verifyResults("sender query")
#if UPDATED_SEARCH_POPUP_LAYOUT
for above in [false, true] {
  for y: CGFloat in [120, 350] {
    host.setFrameOrigin(NSMakePoint(host.frame.minX, y))
    search.testContext.controller.genericView.position = above ? .above : .below
    search.testContext.controller.getHeight = { 4000 }
    search.testContext.updateLayout(animated: false)
    if let popup = search.testContext.accessoryView {
      check(root.bounds.contains(popup.frame), "Results exceed bounds with a requested tall popup")
      let edge = above ? host.frame.minY - popup.frame.maxY : popup.frame.minY - host.frame.maxY
      check(abs(edge - 10) < 0.1, "Results lost the above/below anchor gap")
    } else {
      check(false, "Results disappeared while changing above/below placement")
    }
  }
}
search.testContext.controller.genericView.position = .below
search.testContext.controller.getHeight = nil
#endif
let composerContext = InputContextHelper(chatInteraction: interaction, highlightInsteadOfSelect: true)
let composerAnchor = View(frame: NSMakeRect(80, 320, 270, 40))
root.addSubview(composerAnchor)
check(
  composerContext.controller.anchorFrame(for: composerAnchor, in: root) == composerAnchor.frame,
  "Composer suggestions no longer follow their own input width")
composerAnchor.removeFromSuperview()
runStorySuggestionChecks()
runHeaderLayoutChecks()
runHeaderRemovalChecks()
runFlippedGlassHostChecks()
runAnimatedGlassCornerChecks()
let savedState = ChatHeaderState(main: .search(operations, nil, nil, [], nil, interaction.chatLocation))
let savedSearch = ChatSearchHeader(interaction, state: savedState, frame: NSMakeRect(0, 0, 742, 75))
for width: CGFloat in [742, 360, 1000] {
  savedSearch.setFrameSize(NSMakeSize(width, 75))
  savedSearch.updateLayout(size: savedSearch.frame.size, transition: .immediate)
  if let tags = savedSearch.testTagsView {
    check(tags.frame.minX >= 12, "Saved tags touch the leading rounded corner")
    check(tags.frame.maxX <= width - 12, "Saved tags touch the trailing rounded corner")
    check(savedSearch.bounds.contains(tags.frame), "Saved tags exceed the search header bounds")
  } else {
    check(false, "Saved tags row is missing")
  }
}
savedSearch.remove(animated: false)
search.testButtons[4].send(event: .Click)
drain(0.5)
check(cancellations > 0, "Cancel did not close search")
check(host.superview == nil, "Cancel left the search header attached")
check(
  window.firstResponder !== search.testSearchView.input,
  "Cancel kept focus in the removed search input")
check(search.testContext.accessoryView == nil, "Cancel left a result panel behind")
window.orderOut(nil)
if CommandLine.arguments.contains("--expect-regression") {
  check(
    failures.contains(where: { $0.contains("viewport") }), "Baseline must reproduce cramped input")
  check(
    failures.contains(where: {
      $0.contains("Results width") || $0.contains("Results moved") || $0.contains("clipped outside")
    }), "Baseline must reproduce detached/clipped result panel")
  if failures.contains(where: { !$0.contains("viewport") && !$0.hasPrefix("Results") && !$0.hasPrefix("Saved tags") && !$0.hasPrefix("Header") && !$0.hasPrefix("Empty search") }) { exit(1) }
  print(
    "Baseline reproduced cramped input and stale result-panel geometry (\(failures.count) failed checks)."
  )
  exit(0)
} else if !failures.isEmpty {
  exit(1)
}
print(
  "Search integration: \(checks) checks passed; actual ChatSearchHeader + ChatSearchView; source-extracted popup geometry; controlled search backend."
)
