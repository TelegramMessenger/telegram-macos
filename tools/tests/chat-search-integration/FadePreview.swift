import AppKit
import TGUIKit

final class FadePreviewButton: NSButton {
  var actionBlock: (() -> Void)?
  @objc func runPreview() { actionBlock?() }
}
func showFadePreview() {
  root.subviews.forEach { $0.removeFromSuperview() }
  window.title = "Native search closing · PID \(ProcessInfo.processInfo.processIdentifier)"
  let note = NSTextField(labelWithString: "Production search field and header removal · native glass · no account")
  note.textColor = theme.colors.grayText
  note.frame = NSMakeRect(20, 20, 940, 25)
  root.addSubview(note)
  let wrapper = GlassContainerView(frame: root.bounds, flipped: true, spacing: 5)
  root.addSubview(wrapper)
  let lifecycle = HeaderRemovalFixture(wrapper)
  let content = lifecycle.currentView!
  let rect = NSMakeRect(12, 80, 976, 80)
  content.frame = rect
  root.addSubview(content)
  wrapper.setGhostFrame(lifecycle.glassEffect!, frame: rect, transition: .immediate)
  search.frame = NSMakeRect(0, 0, rect.width, 40)
  content.addSubview(search)
  search.updateLayout(size: search.frame.size, transition: .immediate)
  search.applySearchResponder(false)
  let unlock = NSTextField(labelWithString: "Unlock")
  unlock.font = .systemFont(ofSize: 14)
  unlock.textColor = .systemBlue
  unlock.frame = NSMakeRect(28, 44, 200, 25)
  content.addSubview(unlock)
  let close = FadePreviewButton(frame: NSMakeRect(20, 210, 300, 36))
  close.title = "Close after 1.5 seconds"
  close.bezelStyle = .rounded
  close.target = close
  close.action = #selector(FadePreviewButton.runPreview)
  close.actionBlock = { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { lifecycle.remove(animated: true, mergeGlassOnRemoval: false); wrapper.updateLayout(size: NSMakeSize(1000, 62), transition: .animated(duration: 0.2, curve: .easeOut)) } }
  root.addSubview(close)
  let quit = NSButton(title: "Quit Preview", target: NSApp, action: #selector(NSApplication.terminate(_:)))
  quit.frame = NSMakeRect(360, 210, 160, 36)
  root.addSubview(quit)
  root.layoutSubtreeIfNeeded()
}
