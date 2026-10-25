import AppKit
import TGUIKit
import ColorPalette

_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)
let images: [NSImage] = __IMAGE_PATHS__.map { name, path in
    let image = NSImage(contentsOfFile: path)!
    image.setName(name)
    return image
}
let snapshotPath: String? = __SNAPSHOT_PATH__
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    precondition(value(), message)
    checks += 1
}
func state(_ kind: ChatInputSendButton.State.Kind, loading: Bool = false) -> ChatInputSendButton.State {
    .init(kind: kind, isEditing: false, isSendEnabled: true, isInlineLoading: loading)
}
let window = PointerWindowFixture(contentRect: NSMakeRect(-4000, -4000, 800, 80), styleMask: [.borderless], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
let root = View(frame: NSMakeRect(0, 0, 800, 80))
window.contentView = root
let field = View()
field.layer?.cornerRadius = 20
root.addSubview(field)
let button = ChatInputSendButton(frame: NSMakeRect(0, 0, 40, 40))
root.addSubview(button)
let composer = ComposerFixture(button)
let actions = ChatInputActionsView(frame: .zero)
field.addSubview(actions)
var sends = 0
button.send.set(handler: { _ in sends += 1 }, for: .Click)

if !__CAPTURES_ONLY__ {
for amount: Int64 in [1, 9, 99, 999, 1000, 12500, 1000000, 999999999] {
    _ = button.update(state: state(.paidStars(amount: amount)), animated: false)
    let paid = button.sendPaidMessages!
    paid.layoutSubtreeIfNeeded()
    check(button.isInField, "paid send left a separate circular glass slot")
    check(paid.frame.height == ChatInputSendButton.fieldSize.height, "paid send height differs from ordinary send")
    check(button.desiredSize.width == paid.frame.width && paid.frame.width >= 40, "price width was not reserved")
    check(paid.text.textLayout?.attributedString.string == amount.prettyNumber, "price label changed")
    check(abs(paid.image.frame.minX - (paid.frame.width - paid.text.frame.maxX)) <= 1, "price contents are not centered")
    check(paid.layer?.cornerRadius == 16, "price capsule radius does not match send")

    for width: CGFloat in [320, 350, 520, 800] {
        let frames = composer.frames(width: width)
        field.frame = frames.field
        button.frame = frames.send
        button.updateLayout(size: frames.send.size, transition: .immediate)
        paid.layoutSubtreeIfNeeded()
        let paidFrame = paid.frame.offsetBy(dx: button.frame.minX, dy: button.frame.minY)
        check(frames.field.contains(paidFrame), "paid send escaped the text field")
        check(frames.ghost == paidFrame, "glass capsule and price button diverged")
        check(composer.sendSlot(gap: 10).inField == paid.frame.width + 10, "text overlaps the price button")
        for x in [paidFrame.minX + 2, paidFrame.midX, paidFrame.maxX - 2] {
            let hit = root.hitTest(root.convert(NSMakePoint(x, paidFrame.midY), to: root.superview))
            check(hit === paid || hit?.isDescendant(of: paid) == true, "price control lost part of its clickable area")
            window.pointer = root.convert(NSMakePoint(x, paidFrame.midY), to: nil)
            let before = sends
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: window.pointer, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
                if type == .leftMouseDown { hit!.mouseDown(with: event) } else { hit!.mouseUp(with: event) }
            }
            check(sends == before + 1, "price click bypassed or repeated the normal send handler")
        }
    }
}

let original = button.sendPaidMessages!
_ = button.update(state: state(.paidStars(amount: 1)), animated: false)
let grew = button.update(state: state(.paidStars(amount: 999)), animated: false)
check(grew && button.sendPaidMessages === original, "price changes did not relayout the existing button")
_ = button.update(state: state(.voice), animated: true)
check(!button.isInField && button.desiredSize == NSMakeSize(40, 40), "record mode lost its external circle")
check(button.fieldTransitions.contains { $0.0 === original && !$0.1 }, "paid send did not use the outgoing field transition")
_ = button.update(state: state(.paidStars(amount: 1000)), animated: true)
check(button.fieldTransitions.last?.0 === button.sendPaidMessages && button.fieldTransitions.last?.1 == true, "paid send did not use the incoming field transition")
_ = button.update(state: state(.paidStars(amount: 1000), loading: true), animated: false)
check(!button.isInField && button.desiredSize.width == 40, "inline loading retained a price-sized slot")
_ = button.update(state: state(.send), animated: false)
check(button.isInField && button.desiredSize == NSMakeSize(40, 40), "ordinary send geometry changed")
_ = button.update(state: state(.slowMode(text: "00:30", isBoost: false)), animated: false)
check(!button.isInField && button.desiredSize.width >= 40, "slow-mode placement changed")
print("PASS: \(checks) native paid-send size, placement, hit-test, callback and transition checks")

let originalChecks = checks
for width: CGFloat in [320, 350, 520, 800] {
    _ = button.update(state: state(.send), animated: false)
    let ordinary = composer.frames(width: width)
    for amount: Int64 in [1, 9, 99, 999, 1000, 12500, 1000000, 999999999] {
        _ = button.update(state: state(.paidStars(amount: amount)), animated: false)
        let paid = composer.frames(width: width)
        field.frame = paid.field
        actions.frame = NSMakeRect(0, 0, paid.field.width - composer.sendSlot(gap: 10).inField, 40)
        actions.updateLayout(size: actions.frame.size, transition: .immediate)
        button.frame = paid.send
        button.updateLayout(size: paid.send.size, transition: .immediate)
        let capsule = button.sendPaidMessages!.frame.offsetBy(dx: paid.send.minX, dy: paid.send.minY)
        let emojiMaxX = paid.field.minX + actions.entertaiments.frame.maxX
        check(paid.field == ordinary.field, "paid sending stretches a different field than ordinary sending")
        check(paid.field.maxX == width - 12, "field right edge stopped short of the send action")
        check(capsule.minX - emojiMaxX == ChatInputSendButton.fieldTextGap, "paid action does not follow the emoji button with the ordinary gap")
    }
}
_ = button.update(state: state(.voice), animated: false)
_ = button.update(state: state(.send), animated: true)
let ordinarySpring = button.send.layer!.animation(forKey: "transform") as! CASpringAnimation
let ordinaryBlur = button.send.layer!.animation(forKey: "fieldTransitionBlur") as? CABasicAnimation
let ordinaryFade = button.send.layer!.animation(forKey: "opacity") as! CABasicAnimation
check(button.send.imageView.layer?.animation(forKey: "planeFlight") != nil, "ordinary send lost its icon flight")
_ = button.update(state: state(.voice), animated: false)
_ = button.update(state: state(.paidStars(amount: 1000)), animated: true)
let animatedPaid = button.sendPaidMessages!
let paidSpring = animatedPaid.layer!.animation(forKey: "transform") as! CASpringAnimation
let paidBlur = animatedPaid.layer!.animation(forKey: "fieldTransitionBlur") as? CABasicAnimation
let paidFade = animatedPaid.layer!.animation(forKey: "opacity") as! CABasicAnimation
check(ordinarySpring.mass == paidSpring.mass && ordinarySpring.stiffness == paidSpring.stiffness && ordinarySpring.damping == paidSpring.damping, "paid send uses a different field spring")
check(ordinarySpring.duration == paidSpring.duration, "paid send uses a different spring duration")
check((ordinarySpring.fromValue as! NSValue).caTransform3DValue.m11 == (paidSpring.fromValue as! NSValue).caTransform3DValue.m11, "paid send starts at a different capsule scale")
check(CATransform3DEqualToTransform((ordinarySpring.toValue as! NSValue).caTransform3DValue, (paidSpring.toValue as! NSValue).caTransform3DValue), "paid send ends at a different capsule scale")
check((ordinaryBlur != nil) == (paidBlur != nil), "paid send has a different blur path")
check(ordinaryBlur?.duration == paidBlur?.duration, "paid send uses a different blur duration")
check(ordinaryFade.duration == paidFade.duration, "paid send uses a different fade duration")
check(animatedPaid.image.layer?.animation(forKey: "planeFlight") == nil, "the price icon incorrectly uses the plane-only animation")
_ = button.update(state: state(.voice), animated: true)
let outgoingPaid = animatedPaid.layer!.animation(forKey: "transform") as! CASpringAnimation
check((outgoingPaid.toValue as! NSValue).caTransform3DValue.m11 < 1, "paid send did not use the outgoing collapse")
print("Shared field spring: mass \(paidSpring.mass), stiffness \(paidSpring.stiffness), damping \(paidSpring.damping); native blur present: \(paidBlur != nil); fade: \(paidFade.duration)s")
print("PASS: \(checks - originalChecks) native emoji-gap, ordinary-send field and Core Animation parity checks")
}

if let snapshotPath {
    let ghost = LiquidGlassView(frame: .zero, cornerRadius: 999, hasShadow: true, hasBorder: true)
    root.addSubview(ghost, positioned: .below, relativeTo: button)
    window.setFrameOrigin(NSMakePoint(150, 150))
    window.setContentSize(NSMakeSize(350, 60))
    let initial = PresentationTheme.current
    for (name, color, appearance) in [("dark", NSColor(calibratedRed: 0.06, green: 0.09, blue: 0.12, alpha: 1), NSAppearance.Name.darkAqua), ("light", NSColor.white, .aqua)] {
        updateTheme(PresentationTheme(colors: name == "dark" ? darkPalette : whitePalette, search: initial.search, inputTheme: initial.inputTheme))
        root.backgroundColor = color
        field.backgroundColor = name == "dark" ? NSColor(calibratedRed: 0.13, green: 0.17, blue: 0.21, alpha: 1) : NSColor(calibratedWhite: 0.93, alpha: 1)
        window.appearance = NSAppearance(named: appearance)
        let cases: [(String, ChatInputSendButton.State.Kind)] = [("send", .send), ("1", .paidStars(amount: 1)), ("1000", .paidStars(amount: 1000)), ("12500", .paidStars(amount: 12500))]
        for (caseName, kind) in cases {
            _ = button.update(state: state(kind), animated: false)
            let frames = composer.frames(width: 350)
            root.setFrameSize(NSMakeSize(350, 60))
            field.frame = frames.field
            actions.frame = NSMakeRect(0, 0, frames.field.width - composer.sendSlot(gap: 10).inField, 40)
            actions.updateLayout(size: actions.frame.size, transition: .immediate)
            ghost.frame = frames.ghost
            button.frame = frames.send
            button.updateLayout(size: frames.send.size, transition: .immediate)
            root.layoutSubtreeIfNeeded()
            func clearAnimations(_ layer: CALayer) {
                layer.removeAllAnimations()
                layer.sublayers?.forEach(clearAnimations)
            }
            if let layer = root.layer { clearAnimations(layer) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            window.display()
            CATransaction.flush()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), snapshotPath + "/" + name + "-" + caseName + ".png"]
            try! capture.run()
            capture.waitUntilExit()
            precondition(capture.terminationStatus == 0, "Window capture failed")
        }
    }
    window.orderOut(nil)
}
if __CAPTURES_ONLY__ {
    print("Baseline component capture complete; current-layout assertions were not run")
} else {
    print("PASS: \(checks) native paid-send size, placement, hit-test, callback and transition checks")
}
