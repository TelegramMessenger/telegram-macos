import AppKit
import TGUIKit
import SwiftSignalKit

final class HeaderSlotFixture: View, ChatHeaderProtocol {
  var animatedLayouts: [Bool] = []
  func update(with: ChatHeaderState, animated: Bool) {}
  func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
    animatedLayouts.append(transition.isAnimated)
  }
  func remove(animated: Bool) {}
  func measure(_ width: CGFloat) {}
}

final class HeaderLayoutFixture {
  let currentView = View(frame: NSMakeRect(12, 62, 976, 40))
  var hasLayout = false
  struct SlotState { var canDisplayInline = true; var primaryHeight: CGFloat = 36 }
  var _headerState = SlotState()
  __SLOT_FIELDS__

  func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
    __SLOT_LAYOUT__
    hasLayout = true
  }

  func placeRoot(_ headerFrame: NSRect, transition: ContainedViewLayoutTransition) {
    let header = self
    __ROOT_LAYOUT__
  }
}

func runHeaderLayoutChecks() {
  let animation = ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeOut)
  let header = HeaderLayoutFixture()
  let first = HeaderSlotFixture(frame: NSMakeRect(0, 0, 976, 40))
  header.primaryView = first
  header.currentView.addSubview(first)
  let target = NSMakeRect(280, 12, 598, 40)
  header.placeRoot(target, transition: animation)
  check(header.currentView.frame == target, "Header did not start at its final inline position")
  check(
    header.currentView.layer?.animationKeys()?.isEmpty != false,
    "Header first placement animates from a lower full-width row")
  check(first.animatedLayouts.last == false, "Header first slot layout animates from full width")
  header.updateLayout(size: NSMakeSize(620, 40), transition: animation)
  check(first.animatedLayouts.last == true, "Header stopped animating existing slots on resize")
  first.removeFromSuperview()
  let replacement = HeaderSlotFixture(frame: NSMakeRect(0, 0, 976, 40))
  header.primaryView = replacement
  header.currentView.addSubview(replacement)
  header.updateLayout(size: target.size, transition: animation)
  check(
    replacement.animatedLayouts.last == false,
    "Header replacement slot animates from a stale full-width frame")
  check(
    replacement.layer?.animationKeys()?.isEmpty != false,
    "Header replacement slot has an unexpected frame animation")
#if INLINE_UTILITY_HEADERS
  let utility = HeaderSlotFixture(frame: NSMakeRect(0, 0, 900, 36))
  header.primaryView = utility
  header.currentView.addSubview(utility)
  header.updateLayout(size: NSMakeSize(600, 40), transition: .immediate)
  check(utility.frame.height == 40, "utility hit area does not fill the inline glass")
  header._headerState.canDisplayInline = false
  header.updateLayout(size: NSMakeSize(600, 76), transition: .immediate)
  check(utility.frame.height == 36, "primary slot retained its stretched height when another bar appeared")
  header._headerState.canDisplayInline = true
  header.updateLayout(size: NSMakeSize(320, 36), transition: .immediate)
  check(utility.frame.height == 36, "utility kept the inline height in its fallback row")
  header._headerState.canDisplayInline = false
  let secondary = HeaderSlotFixture(frame: NSMakeRect(0, 36, 600, 40))
  header.seconderyView = secondary
  header.updateLayout(size: NSMakeSize(600, 76), transition: .immediate)
  check(utility.frame.height == 36 && secondary.frame.height == 40, "stacked utility slots were stretched to the full header height")
#endif
}

final class HeaderRemovalFixture {
  var previousPrimary: View? = search
  var currentView: View? = View(frame: NSMakeRect(280, 12, 598, 40))
  var hasLayout = true
  var glassEffect: LiquidGlassView?
  var separatorViews: [View] = []
  let sharedGlassWrapper: GlassContainerView?

  init(_ wrapper: GlassContainerView) {
    sharedGlassWrapper = wrapper
    let ghost = LiquidGlassView(frame: currentView!.frame, cornerRadius: 20)
    glassEffect = ghost
    wrapper.addGhost(ghost)
    wrapper.addSubview(currentView!)
  }

  func remove(animated: Bool, mergeGlassOnRemoval: Bool) {
    __HEADER_REMOVAL__
  }
}

func runHeaderRemovalChecks() {
  let wrapper = GlassContainerView(frame: NSMakeRect(0, 0, 1000, 62), flipped: true, spacing: 5)
  root.addSubview(wrapper)
  let header = HeaderRemovalFixture(wrapper)
  let ghost = header.glassEffect!
  header.remove(animated: true, mergeGlassOnRemoval: true)
  check(header.currentView == nil && !header.hasLayout, "Header removal left stale layout state")
  check(wrapper.ghosts.contains { $0 === ghost }, "Header closing removed its glass before the title expanded")
  check(ghost.effectView.superview != nil, "Header closing detached the native glass surface immediately")
  check(ghost.layer?.animationKeys()?.isEmpty != false, "Header closing fades its glass before merging")
  drain(0.1)
  check(ghost.effectView.superview != nil, "Header closing left a gap during the title expansion")
  let replacement = HeaderRemovalFixture(wrapper)
  let replacementGhost = replacement.glassEffect!
  drain(0.2)
  check(!wrapper.ghosts.contains { $0 === ghost }, "Header closing leaked its old glass after merging")
  check(ghost.effectView.superview == nil, "Header closing left its old glass effect attached")
  check(wrapper.ghosts.contains { $0 === replacementGhost }, "Header reopening lost its replacement glass")
  replacement.remove(animated: false, mergeGlassOnRemoval: true)
  check(wrapper.ghosts.isEmpty, "Header immediate removal retained glass unnecessarily")
  let fallback = HeaderRemovalFixture(wrapper)
  let fallbackGhost = fallback.glassEffect!
  fallback.remove(animated: true, mergeGlassOnRemoval: false)
  check(fallbackGhost.effectView.superview == nil, "Header below the title kept an unwanted glass surface")
  drain(0.3)
  check(fallbackGhost.effectView.superview == nil, "Standalone search retained its native glass after fading")
  check(wrapper.ghosts.isEmpty, "Header fallback removal leaked its glass")
  wrapper.removeFromSuperview()
}

func runAnimatedGlassCornerChecks() {
  func radius(_ glass: LiquidGlassView) -> CGFloat {
    if #available(macOS 26.0, *), let effect = glass.effectView as? NSGlassEffectView {
      return effect.cornerRadius
    }
    return glass.effectView.layer?.cornerRadius ?? -1
  }
  let transition = ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeOut)
  let wrapper = GlassContainerView(frame: NSMakeRect(0, 0, 800, 100), flipped: true)
  root.addSubview(wrapper)
  let shared = LiquidGlassView(frame: NSMakeRect(0, 0, 600, 0), cornerRadius: 20)
  wrapper.addGhost(shared)
  shared.updateLayout(size: shared.bounds.size, transition: .immediate)
  check(radius(shared) == 0, "collapsed shared glass should start with zero radius")
  wrapper.setGhostFrame(shared, frame: NSMakeRect(10, 10, 600, 36), transition: transition)
  check(radius(shared) == 18, "animated shared search glass must restore rounded corners")
  wrapper.setGhostFrame(shared, frame: NSMakeRect(10, 10, 600, 0), transition: .immediate)
  wrapper.setGhostFrame(shared, frame: NSMakeRect(10, 10, 300, 40), transition: transition)
  check(radius(shared) == 20, "reopened shared glass must restore its radius after collapse")
  wrapper.setGhostFrame(shared, frame: NSMakeRect(10, 10, 300, 12), transition: transition)
  check(radius(shared) == 6, "animated shared glass must clamp its radius to the target height")
  let standalone = LiquidGlassView(frame: NSMakeRect(0, 0, 600, 0), cornerRadius: 20)
  root.addSubview(standalone)
  standalone.updateLayout(size: standalone.bounds.size, transition: .immediate)
  standalone.setAnimatorFrame(NSMakeRect(0, 0, 600, 36))
  check(radius(standalone) == 18, "animated standalone glass must restore rounded corners")
  standalone.setAnimatorFrame(NSMakeRect(0, 0, 600, 10))
  check(radius(standalone) == 5, "animated standalone glass must clamp the new radius")
  wrapper.removeFromSuperview()
  standalone.removeFromSuperview()
}

func runFlippedGlassHostChecks() {
  let transition = ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeOut)
  let wrapper = GlassContainerView(frame: NSMakeRect(0, 0, 1000, 137), flipped: true)
  root.addSubview(wrapper)
  wrapper.updateLayout(size: wrapper.frame.size, transition: .immediate)
  let header = HeaderRemovalFixture(wrapper)
  header.currentView!.frame = NSMakeRect(12, 62, 976, 75)
  root.addSubview(header.currentView!)
  let fadingContent = header.currentView!
  let field = ChatSearchView(frame: NSMakeRect(8, 5, 600, 30))
  fadingContent.addSubview(field)
  let outgoing = header.glassEffect!
  wrapper.setGhostFrame(outgoing, frame: header.currentView!.frame, transition: .immediate)
  header.remove(animated: true, mergeGlassOnRemoval: false)
  wrapper.updateLayout(size: NSMakeSize(1000, 62), transition: transition)
  check(wrapper.frame.height == 137, "Header glass host collapsed while search text was fading")
  check(wrapper.glassContainer.frame.height == 137, "Header native glass host clipped the outgoing row")
  check(wrapper.glassContent.frame.height == 137, "Header glass content clipped the outgoing row")
  drain(0.08)
  check(wrapper.glassContainer.frame.height == 137, "Header glass host shrank before the fade finished")
  check((fadingContent.layer?.presentation()?.opacity ?? 0) > 0.35, "Header search input background disappeared before the native glass exit completed")
  check(field.backgroundColor != .clear, "Standalone fade fixture does not exercise the input background")
  let reopened = LiquidGlassView(frame: NSMakeRect(12, 62, 976, 75), cornerRadius: 20)
  wrapper.addGhost(reopened)
  wrapper.updateLayout(size: NSMakeSize(1000, 160), transition: .immediate)
  drain(0.25)
  check(wrapper.frame.height == 160, "Header deferred shrink clipped a reopened search")
  check(wrapper.ghosts.contains { $0 === reopened }, "Header deferred shrink lost the reopened glass")
  wrapper.removeGhost(reopened)
  wrapper.updateLayout(size: NSMakeSize(1000, 62), transition: .immediate)
  check(wrapper.glassContainer.frame.height == 62, "Header immediate resize retained obsolete height")
  wrapper.removeFromSuperview()

  let closing = GlassContainerView(frame: NSMakeRect(0, 0, 1000, 137), flipped: true)
  root.addSubview(closing)
  closing.updateLayout(size: closing.frame.size, transition: .immediate)
  let finalHeader = HeaderRemovalFixture(closing)
  finalHeader.currentView!.frame = NSMakeRect(12, 62, 976, 75)
  root.addSubview(finalHeader.currentView!)
  closing.setGhostFrame(finalHeader.glassEffect!, frame: finalHeader.currentView!.frame, transition: .immediate)
  finalHeader.remove(animated: true, mergeGlassOnRemoval: false)
  closing.updateLayout(size: NSMakeSize(1000, 62), transition: transition)
  drain(0.3)
  check(closing.glassContainer.frame.height == 62, "Header glass host did not release retained height")
  check(closing.glassContent.frame.height == 62, "Header glass content retained obsolete bounds")
  check(closing.ghosts.isEmpty, "Header glass host retained a removed search")
  closing.updateLayout(size: NSMakeSize(1000, 40), transition: transition)
  check(closing.glassContainer.frame.height == 40, "Header glass host delayed a resize without outgoing glass")
  closing.removeFromSuperview()
}
