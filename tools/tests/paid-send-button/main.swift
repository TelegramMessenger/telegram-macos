import AppKit
import TGUIKit

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
var sends = 0
button.send.set(handler: { _ in sends += 1 }, for: .Click)

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

if let snapshotPath {
    for (name, color, appearance) in [("dark", NSColor(calibratedRed: 0.06, green: 0.09, blue: 0.12, alpha: 1), NSAppearance.Name.darkAqua), ("light", NSColor.white, .aqua)] {
        root.backgroundColor = color
        field.backgroundColor = name == "dark" ? NSColor(calibratedRed: 0.13, green: 0.17, blue: 0.21, alpha: 1) : NSColor(calibratedWhite: 0.93, alpha: 1)
        window.appearance = NSAppearance(named: appearance)
        for amount: Int64 in [1, 1000, 12500] {
            _ = button.update(state: state(.paidStars(amount: amount)), animated: false)
            let frames = composer.frames(width: 350)
            root.setFrameSize(NSMakeSize(350, 60))
            field.frame = frames.field
            button.frame = frames.send
            button.updateLayout(size: frames.send.size, transition: .immediate)
            root.layoutSubtreeIfNeeded()
            let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds)!
            root.cacheDisplay(in: root.bounds, to: rep)
            try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: snapshotPath + "/" + name + "-" + String(amount) + ".png"))
        }
    }
}
print("PASS: \(checks) native paid-send size, placement, hit-test, callback and transition checks")
