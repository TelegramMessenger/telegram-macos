import AppKit
import TGUIKit

final class StoryClueRowItem: ContextClueRowItem {
  override var height: CGFloat { 180 }
}

func runStorySuggestionChecks() {
  for initialHeight: CGFloat in [0, 1] {
    for count in [1, 5] {
      let container = View(frame: NSMakeRect(20, 300, 420, initialHeight))
      container.layer?.masksToBounds = false
      root.addSubview(container)
      let anchor = View(frame: NSMakeRect(0, initialHeight, 420, 1))
      container.addSubview(anchor)
      let helper = InputContextHelper(chatInteraction: interaction, highlightInsteadOfSelect: false)
      helper.getHeight = { 150 }
      var sizes: [NSSize] = []
      helper.updatedSize = { size, _ in
        sizes.append(size)
        container.setFrameSize(size)
        anchor.setFrameOrigin(NSMakePoint(0, size.height))
      }
      let peers = (0..<count).map { Peer(100 + $0, "Story mention \($0)") }
      func show() {
        helper.context(with: .mentions(peers), for: container, relativeView: anchor,
                       position: .above, selectIndex: nil, animated: false, inset: 0)
      }
      show()
      guard let popup = helper.accessoryView else {
        check(false, "Stories suggestions did not attach to their dynamic container")
        container.removeFromSuperview()
        continue
      }
      let expectedHeight = min(CGFloat(count) * 44, 150)
      check(popup.frame.height == expectedHeight, "Stories suggestions collapsed before their container could grow")
      check(sizes.first?.height == expectedHeight, "Stories initial size callback did not expand the container")
      check(container.frame.height == expectedHeight, "Stories reply container stayed at its bootstrap height")
      check(popup.frame.width == anchor.frame.width, "Stories suggestions lost the reply field width")
      check(abs(anchor.frame.minY - popup.frame.maxY - 10) < 0.1, "Stories suggestions lost their anchor gap")
#if UPDATED_SEARCH_POPUP_LAYOUT
      helper.updateLayout(animated: false)
#endif
      check(popup.frame.height == expectedHeight, "Stories suggestions collapsed after their size callback")
      helper.controller.genericView.tableView.removeAll()
      _ = helper.controller.genericView.tableView.addItem(item: StoryClueRowItem(NSMakeSize(420, 180), stableId: "story-emoji"))
#if UPDATED_SEARCH_POPUP_LAYOUT
      helper.updateLayout(animated: false)
      check(popup.frame.height == 120, "Stories emoji suggestions lost their existing height limit")
      check(container.frame.height == 120, "Stories emoji sizing did not reach the reply container")
#endif
      helper.context(with: nil, for: container, relativeView: anchor,
                     position: .above, selectIndex: nil, animated: false, inset: 0)
      check(helper.accessoryView == nil, "Stories suggestions stayed attached after clearing")
      container.setFrameSize(NSMakeSize(420, 1))
      anchor.setFrameOrigin(NSMakePoint(0, 1))
      show()
      check(helper.accessoryView?.frame.height == expectedHeight, "Stories suggestions did not reopen from their collapsed container")
      helper.context(with: nil, for: container, relativeView: anchor,
                     position: .above, selectIndex: nil, animated: false, inset: 0)
      container.removeFromSuperview()
    }
  }
#if UPDATED_SEARCH_POPUP_LAYOUT
  let container = View(frame: NSMakeRect(0, 0, 420, 100))
  root.addSubview(container)
  let anchor = View(frame: NSMakeRect(0, 60, 420, 40))
  container.addSubview(anchor)
  let helper = InputContextHelper(chatInteraction: interaction, highlightInsteadOfSelect: false)
  helper.context(with: .mentions((0..<5).map { Peer(200 + $0, "Ordinary mention") }), for: container, relativeView: anchor, position: .above, selectIndex: nil, animated: false, inset: 0)
  check(helper.accessoryView?.frame.height == 10, "Ordinary suggestions lost their existing viewport cap")
  let oldFrame = helper.accessoryView?.frame
  helper.controller.markAsNeedShown = false
  anchor.setFrameOrigin(NSMakePoint(20, 80))
  helper.updateLayout(animated: true)
  check(helper.accessoryView?.frame == oldFrame, "Dismissing suggestions were repositioned by layout")
  helper.context(with: nil, for: container, relativeView: anchor, position: .above, selectIndex: nil, animated: false, inset: 0)
  container.removeFromSuperview()
#endif

}
