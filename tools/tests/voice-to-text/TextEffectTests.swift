import Cocoa
import XCTest

final class DictationTextEffectTests: XCTestCase {
    private func makeEditor() -> (NSWindow, NSTextView) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 80), styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        let textView = NSTextView(frame: CGRect(x: 0, y: 0, width: 300, height: 80))
        textView.wantsLayer = true
        window.contentView = textView
        textView.textStorage!.setAttributedString(NSAttributedString(string: "Hello friend", attributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.textColor]))
        textView.layoutManager!.ensureLayout(for: textView.textContainer!)
        return (window, textView)
    }

    private func alpha(_ textView: NSTextView, at index: Int) -> CGFloat? {
        return (textView.layoutManager!.temporaryAttribute(.foregroundColor, atCharacterIndex: index, effectiveRange: nil) as? NSColor)?.alphaComponent
    }

    private func scrambleLayers(_ textView: NSTextView) -> [CALayer] {
        return textView.layer!.sublayers?.filter { $0.name == "dictationScramble" } ?? []
    }

    func testNewTextScramblesThenDecodesAndCancelRestoresIt() throws {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { throw XCTSkip("Reduced motion is enabled") }
        let (window, textView) = makeEditor()
        defer { window.close() }
        let original = textView.attributedString().copy() as! NSAttributedString
        let effect = ChatDictationTextEffect(textView: textView, animationsEnabled: true)
        effect.revealChange(from: "", to: textView.string)
        XCTAssertEqual(try XCTUnwrap(alpha(textView, at: 0)), 0)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
        XCTAssertFalse(scrambleLayers(textView).isEmpty)
        XCTAssertTrue(scrambleLayers(textView).allSatisfy { $0.contents != nil })
        XCTAssertEqual(try XCTUnwrap(alpha(textView, at: 0)), 0)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: ChatDictationTextEffect.scrambleDuration))
        let resolving = alpha(textView, at: 0) ?? 1
        XCTAssertGreaterThan(resolving, 0)
        effect.cancelReveal()
        XCTAssertNil(alpha(textView, at: 0))
        XCTAssertNil(alpha(textView, at: 11))
        XCTAssertTrue(scrambleLayers(textView).isEmpty)
        XCTAssertEqual(textView.attributedString(), original)
    }

    func testDecodingFinishesAndRemovesItsColorsAndLayers() throws {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { throw XCTSkip("Reduced motion is enabled") }
        let (window, textView) = makeEditor()
        defer { window.close() }
        let effect = ChatDictationTextEffect(textView: textView, animationsEnabled: true)
        effect.revealChange(from: "", to: textView.string)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0))
        for index in 0 ..< textView.string.utf16.count {
            XCTAssertNil(alpha(textView, at: index), "\(index)")
        }
        XCTAssertTrue(scrambleLayers(textView).isEmpty)
        _ = effect
    }

    func testAFollowingRecognitionUpdateKeepsCharactersMidDecode() throws {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { throw XCTSkip("Reduced motion is enabled") }
        let (window, textView) = makeEditor()
        defer { window.close() }
        textView.textStorage!.setAttributedString(NSAttributedString(string: "Hello", attributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.textColor]))
        let effect = ChatDictationTextEffect(textView: textView, animationsEnabled: true)
        effect.revealChange(from: "", to: "Hello")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        textView.textStorage!.append(NSAttributedString(string: " friend", attributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.textColor]))
        effect.revealChange(from: "Hello", to: "Hello friend")
        XCTAssertNil(alpha(textView, at: 5))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: ChatDictationTextEffect.scrambleDuration - 0.02))
        XCTAssertGreaterThan(alpha(textView, at: 0) ?? 1, 0)
        XCTAssertEqual(try XCTUnwrap(alpha(textView, at: 6)), 0)
        effect.cancelReveal()
    }

    func testALargeRewriteSwapsInPlaceAndAnimatesOnlyTheGrowth() {
        let rewrite = ChatDictationTextEffect.animatedRange(from: "Hello world how are you", to: "Hello there, how are you doing today")
        let current = "Hello there, how are you doing today" as NSString
        XCTAssertFalse(current.substring(with: rewrite).contains("there"))
        let small = ChatDictationTextEffect.animatedRange(from: "Send four tomorrow", to: "Send five tomorrow")
        XCTAssertEqual(("Send five tomorrow" as NSString).substring(with: small), "ive")
        let append = ChatDictationTextEffect.animatedRange(from: "Hello", to: "Hello friend")
        XCTAssertEqual(("Hello friend" as NSString).substring(with: append), " friend")
        let switched = ChatDictationTextEffect.animatedRange(from: "привет как дела", to: "privet kak dela tut")
        XCTAssertLessThanOrEqual(switched.length, 4)
    }

    func testAStaleRecognitionUpdateCannotHideNewlyEditedText() {
        let (window, textView) = makeEditor()
        defer { window.close() }
        let effect = ChatDictationTextEffect(textView: textView, animationsEnabled: true)
        effect.revealChange(from: "", to: textView.string)
        effect.cancelReveal()
        textView.string = "Typed instead"
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
        XCTAssertNil(textView.layoutManager!.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil))
        XCTAssertFalse(textView.layer!.sublayers?.contains { $0.name == "dictationReveal" } ?? false)
        XCTAssertEqual(textView.string, "Typed instead")
    }

    func testReleasingTheEffectRestoresNativeGlyphsImmediately() throws {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { throw XCTSkip("Reduced motion is enabled") }
        let (window, textView) = makeEditor()
        defer { window.close() }
        var effect: ChatDictationTextEffect? = ChatDictationTextEffect(textView: textView, animationsEnabled: true)
        effect?.revealChange(from: "", to: textView.string)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
        effect = nil
        XCTAssertNil(textView.layoutManager!.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil))
        XCTAssertFalse(textView.layer!.sublayers?.contains { $0.name == "dictationReveal" } ?? false)
    }

    func testCompletionShimmerTouchesOnlyTheAddedTextAndStopsOnEdit() throws {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { throw XCTSkip("Reduced motion is enabled") }
        let (window, textView) = makeEditor()
        defer { window.close() }
        var effect: ChatDictationTextEffect? = ChatDictationTextEffect(textView: textView, animationsEnabled: true)
        effect?.finish(range: NSRange(location: 6, length: 6))
        effect = nil
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        for index in 0 ..< 6 {
            XCTAssertNil(alpha(textView, at: index), "\(index)")
        }
        let dimmed = (6 ..< 12).compactMap { alpha(textView, at: $0) }
        XCTAssertFalse(dimmed.isEmpty)
        XCTAssertTrue(dimmed.allSatisfy { $0 >= 0.3 && $0 <= 1 })
        NotificationCenter.default.post(name: NSText.didChangeNotification, object: textView)
        for index in 0 ..< 12 {
            XCTAssertNil(alpha(textView, at: index), "\(index)")
        }
    }

    func testCompletionShimmerEndsWithTheTextUntouched() throws {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { throw XCTSkip("Reduced motion is enabled") }
        let (window, textView) = makeEditor()
        defer { window.close() }
        let original = textView.attributedString().copy() as! NSAttributedString
        ChatDictationTextEffect(textView: textView, animationsEnabled: true).finish(range: NSRange(location: 0, length: 12))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.6))
        for index in 0 ..< 12 {
            XCTAssertNil(alpha(textView, at: index), "\(index)")
        }
        XCTAssertEqual(textView.attributedString(), original)
    }

    func testFinishingSettlesLettersStillWaitingWithoutShowingTheirGlyphs() throws {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { throw XCTSkip("Reduced motion is enabled") }
        let (window, textView) = makeEditor()
        defer { window.close() }
        var effect: ChatDictationTextEffect? = ChatDictationTextEffect(textView: textView, animationsEnabled: true)
        effect?.revealChange(from: "", to: textView.string)
        effect?.finish(range: NSRange(location: 0, length: 12))
        effect = nil
        XCTAssertTrue(scrambleLayers(textView).allSatisfy { $0.opacity < 0.5 })
        RunLoop.main.run(until: Date(timeIntervalSinceNow: ChatDictationTextEffect.resolveDuration / 2))
        XCTAssertTrue(scrambleLayers(textView).allSatisfy { $0.opacity < 0.5 })
        let settling = (0 ..< 12).map { alpha(textView, at: $0) ?? 1 }
        XCTAssertTrue(settling.allSatisfy { $0 > 0 })
        RunLoop.main.run(until: Date(timeIntervalSinceNow: ChatDictationTextEffect.resolveDuration))
        XCTAssertTrue(scrambleLayers(textView).isEmpty)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.6))
        for index in 0 ..< 12 {
            XCTAssertNil(alpha(textView, at: index), "\(index)")
        }
    }

    func testFinishingWithNothingAddedStillSettlesTheDecode() throws {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { throw XCTSkip("Reduced motion is enabled") }
        let (window, textView) = makeEditor()
        defer { window.close() }
        var effect: ChatDictationTextEffect? = ChatDictationTextEffect(textView: textView, animationsEnabled: true)
        effect?.revealChange(from: "Hello", to: textView.string)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        effect?.finish(range: NSRange(location: 12, length: 0))
        effect = nil
        XCTAssertNotNil(alpha(textView, at: 7))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: ChatDictationTextEffect.resolveDuration + 0.1))
        for index in 0 ..< 12 {
            XCTAssertNil(alpha(textView, at: index), "\(index)")
        }
        XCTAssertTrue(scrambleLayers(textView).isEmpty)
    }

    func testTheWaitingShimmerLoopsUntilSettledAndThenEndsClean() throws {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { throw XCTSkip("Reduced motion is enabled") }
        let (window, textView) = makeEditor()
        defer { window.close() }
        let original = textView.attributedString().copy() as! NSAttributedString
        var effect: ChatDictationTextEffect? = ChatDictationTextEffect(textView: textView, animationsEnabled: true)
        effect?.loopShimmer(range: NSRange(location: 6, length: 6))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: ChatDictationTextEffect.loopPeriod * 2.3))
        XCTAssertNil(alpha(textView, at: 2))
        XCTAssertFalse((6 ..< 12).compactMap { alpha(textView, at: $0) }.isEmpty)
        effect?.settleShimmer(range: NSRange(location: 6, length: 6), text: nil)
        effect = nil
        RunLoop.main.run(until: Date(timeIntervalSinceNow: ChatDictationTextEffect.settleDuration + 0.3))
        for index in 0 ..< 12 {
            XCTAssertNil(alpha(textView, at: index), "\(index)")
        }
        XCTAssertEqual(textView.attributedString(), original)
    }

    func testSettlingWaitsForTheImprovedTextAndMovesToItsRange() throws {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { throw XCTSkip("Reduced motion is enabled") }
        let (window, textView) = makeEditor()
        defer { window.close() }
        var effect: ChatDictationTextEffect? = ChatDictationTextEffect(textView: textView, animationsEnabled: true)
        effect?.loopShimmer(range: NSRange(location: 0, length: 12))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
        effect?.settleShimmer(range: NSRange(location: 0, length: 13), text: "Hello friend!")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertFalse((0 ..< 12).compactMap { alpha(textView, at: $0) }.isEmpty)
        textView.textStorage!.replaceCharacters(in: NSRange(location: 12, length: 0), with: "!")
        NotificationCenter.default.post(name: NSText.didChangeNotification, object: textView)
        effect?.redraw()
        XCTAssertFalse((0 ..< 13).compactMap { alpha(textView, at: $0) }.isEmpty)
        effect = nil
        RunLoop.main.run(until: Date(timeIntervalSinceNow: ChatDictationTextEffect.settleDuration + 0.3))
        for index in 0 ..< 13 {
            XCTAssertNil(alpha(textView, at: index), "\(index)")
        }
    }

    func testWaitingStartsFromTheCompletionShimmerWithoutAJump() throws {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { throw XCTSkip("Reduced motion is enabled") }
        let (window, textView) = makeEditor()
        defer { window.close() }
        let effect = ChatDictationTextEffect(textView: textView, animationsEnabled: true)
        effect.finish(range: NSRange(location: 0, length: 12))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        effect.redraw()
        let before = (0 ..< 12).map { alpha(textView, at: $0) ?? 1 }
        effect.loopShimmer(range: NSRange(location: 0, length: 12))
        let after = (0 ..< 12).map { alpha(textView, at: $0) ?? 1 }
        for index in 0 ..< 12 {
            XCTAssertEqual(before[index], after[index], accuracy: 0.08, "\(index)")
        }
        effect.cancelReveal()
    }

    func testTheLoopWrapsWhileTheBandIsOffTheText() {
        let period = ChatDictationTextEffect.loopPeriod
        for position in [0.0, 5, 11] {
            let end = ChatDictationTextEffect.loopFactor(position: position, count: 12, elapsed: period * 2 - 0.0001, period: period, envelope: 1)
            let start = ChatDictationTextEffect.loopFactor(position: position, count: 12, elapsed: period * 2 + 0.0001, period: period, envelope: 1)
            XCTAssertEqual(end, start, accuracy: 0.02)
            XCTAssertLessThan(start, 0.6)
        }
        XCTAssertEqual(ChatDictationTextEffect.loopFactor(position: 6, count: 12, elapsed: 0.3, period: period, envelope: 0), 1, accuracy: 0.001)
    }

    private func waveLayers(_ textView: NSTextView) -> [CALayer] {
        return textView.layer!.sublayers?.filter { $0.name == "dictationWave" } ?? []
    }

    private func capture(_ window: NSWindow) -> CGImage? {
        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]), image.width > 0 else { return nil }
        return image
    }

    private func pixels(_ image: CGImage, in rect: NSRect, scale: CGFloat) -> [UInt8] {
        let data = CFDataGetBytePtr(image.dataProvider!.data)!
        var result: [UInt8] = []
        for y in Int(rect.minY * scale) ..< min(image.height, Int(rect.maxY * scale)) {
            for x in Int(rect.minX * scale) ..< min(image.width, Int(rect.maxX * scale)) {
                let offset = y * image.bytesPerRow + x * 4
                result.append(contentsOf: [data[offset], data[offset + 1], data[offset + 2]])
            }
        }
        return result
    }

    func testTheWaveCarriesLettersOnCopiesAndHandsTheTextBackUntouched() throws {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { throw XCTSkip("Reduced motion is enabled") }
        let (window, textView) = makeEditor()
        defer { window.close() }
        let original = textView.attributedString().copy() as! NSAttributedString
        var effect: ChatDictationTextEffect? = ChatDictationTextEffect(textView: textView, animationsEnabled: true)
        effect?.ripple(range: NSRange(location: 0, length: 12), from: 6, after: 0, tint: .systemBlue)
        effect = nil
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
        XCTAssertEqual(waveLayers(textView).count, 11)
        XCTAssertEqual(try XCTUnwrap(alpha(textView, at: 6)), 0)
        XCTAssertNil(alpha(textView, at: 5))
        XCTAssertTrue(waveLayers(textView).contains { !CATransform3DIsIdentity($0.transform) })
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.2))
        XCTAssertTrue(waveLayers(textView).isEmpty)
        for index in 0 ..< 12 {
            XCTAssertNil(alpha(textView, at: index), "\(index)")
        }
        XCTAssertEqual(textView.attributedString(), original)
    }

    func testLettersTheWaveHasNotReachedMatchTheTextPixelForPixel() throws {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { throw XCTSkip("Reduced motion is enabled") }
        let (window, textView) = makeEditor()
        defer { window.close() }
        textView.backgroundColor = NSColor.red.withAlphaComponent(0.01)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        guard let before = capture(window) else { throw XCTSkip("Window capture is unavailable") }
        let layout = textView.layoutManager!
        let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: 8, length: 4), actualCharacterRange: nil)
        let far = layout.boundingRect(forGlyphRange: glyphs, in: textView.textContainer!).offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
        let effect = ChatDictationTextEffect(textView: textView, animationsEnabled: true)
        effect.ripple(range: NSRange(location: 0, length: 12), from: 0, after: 0, tint: .clear)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
        XCTAssertFalse(waveLayers(textView).isEmpty)
        XCTAssertEqual(try XCTUnwrap(alpha(textView, at: 9)), 0)
        guard let during = capture(window) else { throw XCTSkip("Window capture is unavailable") }
        let scale = window.backingScaleFactor
        let reference = pixels(before, in: far, scale: scale)
        let copy = pixels(during, in: far, scale: scale)
        XCTAssertEqual(reference.count, copy.count)
        XCTAssertGreaterThan(Set(reference).count, 8)
        let differences = zip(reference, copy).map { abs(Int($0) - Int($1)) }
        XCTAssertLessThanOrEqual(differences.max() ?? 0, 2, "\(differences.filter { $0 > 2 }.count) of \(differences.count) differ")
        effect.cancelReveal()
    }

    func testAnEditDuringTheWaveDropsItAtOnce() throws {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { throw XCTSkip("Reduced motion is enabled") }
        let (window, textView) = makeEditor()
        defer { window.close() }
        let effect = ChatDictationTextEffect(textView: textView, animationsEnabled: true)
        effect.ripple(range: NSRange(location: 0, length: 12), from: 3, after: 0, tint: .systemBlue)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.06))
        XCTAssertFalse(waveLayers(textView).isEmpty)
        textView.textStorage!.replaceCharacters(in: NSRange(location: 0, length: 5), with: "Hey")
        effect.redraw()
        XCTAssertTrue(waveLayers(textView).isEmpty)
        for index in 0 ..< textView.string.utf16.count {
            XCTAssertNil(alpha(textView, at: index), "\(index)")
        }
    }

    func testTheFixArrivesOnlyOnTheLettersItChanged() throws {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { throw XCTSkip("Reduced motion is enabled") }
        let (window, textView) = makeEditor()
        defer { window.close() }
        let original = textView.attributedString().copy() as! NSAttributedString
        var effect: ChatDictationTextEffect? = ChatDictationTextEffect(textView: textView, animationsEnabled: true)
        effect?.arrive(ranges: [NSRange(location: 0, length: 1), NSRange(location: 11, length: 1)], within: NSRange(location: 0, length: 12), text: textView.string, tint: .systemBlue)
        effect?.redraw()
        effect = nil
        XCTAssertEqual(waveLayers(textView).count, 2)
        XCTAssertEqual(try XCTUnwrap(alpha(textView, at: 0)), 0)
        XCTAssertEqual(try XCTUnwrap(alpha(textView, at: 11)), 0)
        XCTAssertNil(alpha(textView, at: 5))
        XCTAssertTrue(waveLayers(textView).allSatisfy { $0.opacity < 0.2 })
        RunLoop.main.run(until: Date(timeIntervalSinceNow: ChatDictationTextEffect.arrivalDuration + 0.5))
        XCTAssertTrue(waveLayers(textView).isEmpty)
        for index in 0 ..< 12 {
            XCTAssertNil(alpha(textView, at: index), "\(index)")
        }
        XCTAssertEqual(textView.attributedString(), original)
    }

    func testTheArrivalWaitsForTheFixedTextToLand() throws {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { throw XCTSkip("Reduced motion is enabled") }
        let (window, textView) = makeEditor()
        defer { window.close() }
        let effect = ChatDictationTextEffect(textView: textView, animationsEnabled: true)
        effect.arrive(ranges: [NSRange(location: 12, length: 1)], within: NSRange(location: 0, length: 13), text: "Hello friend!", tint: .systemBlue)
        effect.redraw()
        XCTAssertTrue(waveLayers(textView).isEmpty)
        textView.textStorage!.replaceCharacters(in: NSRange(location: 12, length: 0), with: "!")
        effect.redraw()
        XCTAssertEqual(waveLayers(textView).count, 1)
        XCTAssertEqual(try XCTUnwrap(alpha(textView, at: 12)), 0)
        effect.cancelReveal()
    }

    func testTheArrivalStartsHiddenAndEndsExactlyAtRest() {
        let start = ChatDictationTextEffect.arrival(progress: 0)
        XCTAssertEqual(start.appear, 0, accuracy: 0.0001)
        XCTAssertEqual(start.offset, 1, accuracy: 0.0001)
        XCTAssertEqual(start.tint, 1, accuracy: 0.0001)
        let end = ChatDictationTextEffect.arrival(progress: 1)
        XCTAssertEqual(end.appear, 1, accuracy: 0.0001)
        XCTAssertEqual(end.offset, 0, accuracy: 0.0001)
        XCTAssertEqual(end.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(end.tint, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(ChatDictationTextEffect.arrival(progress: 0.6).scale, 1)
    }

    func testTheWaveRisesAtItsFrontAndCalmsWhenFaded() {
        let crest = ChatDictationTextEffect.waveLift(distance: 4, front: 4, fade: 1)
        XCTAssertGreaterThan(crest.lift, 0.8)
        XCTAssertGreaterThan(crest.crest, 0.8)
        XCTAssertEqual(ChatDictationTextEffect.waveLift(distance: 20, front: 2, fade: 1).lift, 0, accuracy: 0.0001)
        XCTAssertLessThan(ChatDictationTextEffect.waveLift(distance: 4, front: 7.7, fade: 1).lift, 0)
        XCTAssertEqual(ChatDictationTextEffect.waveLift(distance: 4, front: 4, fade: 0).lift, 0, accuracy: 0.0001)
        XCTAssertLessThan(ChatDictationTextEffect.waveLift(distance: 40, front: 40, fade: 1).lift, crest.lift)
        XCTAssertEqual(ChatDictationTextEffect.waveLift(distance: 20, front: 2, fade: 1).soak, 1, accuracy: 0.001)
        XCTAssertEqual(ChatDictationTextEffect.waveLift(distance: 2, front: 20, fade: 1).soak, 0, accuracy: 0.001)
        XCTAssertGreaterThan(ChatDictationTextEffect.waveLift(distance: 4, front: 4, fade: 1).soak, 0.7)
    }

    func testShimmerWaveNeverDimsAtItsEdgesAndLightsItsCenter() {
        XCTAssertEqual(ChatDictationTextEffect.shimmerFactor(position: 3, count: 20, progress: 0), 1, accuracy: 0.001)
        XCTAssertEqual(ChatDictationTextEffect.shimmerFactor(position: 3, count: 20, progress: 1), 1, accuracy: 0.001)
        XCTAssertEqual(ChatDictationTextEffect.shimmerFactor(position: 10, count: 20, progress: 0.5), 1, accuracy: 0.01)
        XCTAssertEqual(ChatDictationTextEffect.shimmerFactor(position: 0, count: 60, progress: 0.5), 0.35, accuracy: 0.01)
    }

    func testRevealOnlyIncludesTheInsertionBetweenExistingText() {
        let range = ChatDictationTextEffect.changedRange(from: "Hello world", to: "Hello dear world")
        XCTAssertEqual(("Hello dear world" as NSString).substring(with: range), "dear ")
    }

    func testRecognitionCorrectionsRevealOnlyTheChangedSpan() {
        let range = ChatDictationTextEffect.changedRange(from: "Send four tomorrow", to: "Send five tomorrow")
        XCTAssertEqual(("Send five tomorrow" as NSString).substring(with: range), "ive")
    }

    func testRevealNeverSplitsEmojiOrCombiningCharacters() {
        for value in ["🙂", "👨‍👩‍👧‍👦", "e\u{301}", "🇺🇿"] {
            let text = "Hi " + value + " there"
            let range = ChatDictationTextEffect.changedRange(from: "Hi  there", to: text)
            XCTAssertEqual((text as NSString).substring(with: range), value)
            XCTAssertEqual(range.length, value.utf16.count)
        }
    }

    func testDeletionAndUnchangedTextHaveNoReveal() {
        XCTAssertEqual(ChatDictationTextEffect.changedRange(from: "Hello friend", to: "Hello").length, 0)
        XCTAssertEqual(ChatDictationTextEffect.changedRange(from: "Hello", to: "Hello").length, 0)
    }

    func testDisabledEffectsLeaveAttributedTextAndSelectionUntouched() {
        let textView = NSTextView(frame: CGRect(x: 0, y: 0, width: 300, height: 80))
        textView.wantsLayer = true
        let text = NSAttributedString(string: "Hello 🙂 friend", attributes: [.foregroundColor: NSColor.systemBlue, .font: NSFont.boldSystemFont(ofSize: 15)])
        textView.textStorage!.setAttributedString(text)
        let selection = NSRange(location: 6, length: 2)
        textView.setSelectedRange(selection)
        textView.layoutManager!.ensureLayout(for: textView.textContainer!)
        let original = textView.attributedString().copy() as! NSAttributedString
        let effect = ChatDictationTextEffect(textView: textView, animationsEnabled: false)
        effect.revealChange(from: "Hello friend", to: text.string)
        effect.finish(range: NSRange(location: 0, length: 5))
        effect.cancelReveal()
        XCTAssertEqual(textView.attributedString(), original)
        XCTAssertEqual(textView.selectedRange(), selection)
        XCTAssertTrue(textView.layer!.sublayers?.isEmpty ?? true)
    }
}
