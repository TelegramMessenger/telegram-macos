import AppKit
import CoreText
import ImageIO
import XCTest
@testable import TGUIKit

final class AttributedTextNormalizationTests: XCTestCase {
    private func assertEquivalent(_ actual: NSAttributedString, _ expected: NSAttributedString, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.string, expected.string, file: file, line: line)
        XCTAssertTrue(actual.isEqual(to: expected), file: file, line: line)
        guard actual.length == expected.length else { return }
        for index in 0..<actual.length {
            var actualRange = NSRange()
            var expectedRange = NSRange()
            let actualAttributes = actual.attributes(at: index, effectiveRange: &actualRange)
            let expectedAttributes = expected.attributes(at: index, effectiveRange: &expectedRange)
            XCTAssertTrue(NSDictionary(dictionary: actualAttributes).isEqual(to: expectedAttributes), file: file, line: line)
            XCTAssertEqual(actualRange, expectedRange, file: file, line: line)
        }
    }

    private func styled(_ text: String) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.blue])
        for index in stride(from: 0, to: result.length, by: 3) {
            result.addAttribute(NSAttributedString.Key("normalization-run"), value: index, range: NSRange(location: index, length: min(3, result.length - index)))
        }
        return result
    }

    func testNewlinesToSpacesOnlyReplacesLineFeeds() {
        let input = styled("\nA\r\nB\rC\u{0085}D\u{2028}E\u{2029}F\u{fffc}\n\n")
        let result = input.trimNewLinesToSpace
        XCTAssertEqual(result.string, " A\r B\rC\u{0085}D\u{2028}E\u{2029}F\u{fffc}  ")
        assertEquivalent(result, input.referenceTrimNewLinesToSpace)
    }

    func testTrimmedPreservesInternalSeparatorsAndAttributes() {
        let input = styled(" \t\u{2028}👩🏽‍💻\u{2028}e\u{0301}\u{fffc}مرحبا\u{2029}中\n ")
        let result = input.trimmed
        XCTAssertEqual(result.string, "👩🏽‍💻\ne\u{0301}\nمرحبا\u{2029}中")
        assertEquivalent(result, input.referenceTrimmed)
    }

    func testLineSeparatorCombiningMarksKeepCanonicalSearchBehavior() {
        let input = styled("a\u{2028}\u{0301}b\u{2028}c")
        XCTAssertEqual(input.trimmed.string, "a\u{2028}\u{0301}b\nc")
        assertEquivalent(input.trimmed, input.referenceTrimmed)
    }

    func testEmptyAndWhitespaceInputs() {
        for text in ["", " ", "\n\n", "\r\n\t ", "\u{2028}\u{fffc}", "\u{00a0}\u{2003}\u{2029}", " \u{0301}", "\u{fffc}\u{0301}"] {
            let input = styled(text)
            assertEquivalent(input.trimmed, input.referenceTrimmed)
            assertEquivalent(input.trimNewLinesToSpace, input.referenceTrimNewLinesToSpace)
        }
    }

    func testEveryUTF16AttributeAndEffectiveRange() {
        let input = styled("a\n\n👩🏽‍💻\u{2028}\u{fffc}\r\n🇷🇺e\u{0301}\nZ")
        let attachment = NSTextAttachment()
        let attachmentRange = (input.string as NSString).range(of: "\u{fffc}")
        input.addAttribute(.attachment, value: attachment, range: attachmentRange)
        input.addAttribute(.link, value: URL(string: "https://telegram.org")!, range: NSRange(location: 0, length: 3))
        for index in 0..<input.length {
            input.addAttribute(NSAttributedString.Key("utf16-unit"), value: index, range: NSRange(location: index, length: 1))
        }
        assertEquivalent(input.trimmed, input.referenceTrimmed)
        assertEquivalent(input.trimNewLinesToSpace, input.referenceTrimNewLinesToSpace)
    }

    func testArgumentIsUsedInsteadOfReceiver() {
        let receiver = styled("wrong\nreceiver")
        let argument = styled("right\nargument")
        assertEquivalent(receiver.replaceNewlinesWithSpaces(in: argument), argument.referenceTrimNewLinesToSpace)
        XCTAssertEqual(receiver.string, "wrong\nreceiver")
    }

    func testInputAndReturnedCopiesAreIndependent() {
        for normalizer in [{ (input: NSAttributedString) in input.trimmed }, { (input: NSAttributedString) in input.trimNewLinesToSpace }] {
            let input = styled(" \u{2028}hello\nworld\u{fffc} ")
            let snapshot = NSAttributedString(attributedString: input)
            let first = normalizer(input)
            let second = normalizer(input)
            assertEquivalent(input, snapshot)
            let expected = NSAttributedString(attributedString: first)
            input.mutableString.setString("changed input")
            assertEquivalent(first, expected)
            assertEquivalent(second, expected)
            if let mutableFirst = first as? NSMutableAttributedString {
                mutableFirst.mutableString.setString("changed result")
                assertEquivalent(second, expected)
            }
        }
    }

    func testLongInputsMatchReference() {
        for text in [String(repeating: "a\u{2028}b\u{fffc}", count: 1024), String(repeating: "🙂\n\n", count: 1024), String(repeating: "a", count: 4096)] {
            let input = styled(text)
            assertEquivalent(input.trimmed, input.referenceTrimmed)
            assertEquivalent(input.trimNewLinesToSpace, input.referenceTrimNewLinesToSpace)
        }
    }

    func testDeterministicRandomUnicodeInputs() {
        let tokens = ["a", "Z", " ", "\t", "\r", "\n", "\u{2028}", "\u{2029}", "\u{fffc}", "\u{0085}", "\u{00a0}", "\u{2003}", "🙂", "👩🏽‍💻", "🇷🇺", "e\u{0301}", "\u{0301}", "مرحبا", "中文", "\0"]
        var state: UInt64 = 42
        func next() -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int(state >> 33)
        }
        for _ in 0..<1500 {
            let text = (0..<(next() % 80)).map { _ in tokens[next() % tokens.count] }.joined()
            let input = styled(text)
            let snapshot = NSAttributedString(attributedString: input)
            assertEquivalent(input.trimmed, input.referenceTrimmed)
            assertEquivalent(input.trimNewLinesToSpace, input.referenceTrimNewLinesToSpace)
            assertEquivalent(input, snapshot)
        }
    }

    func testConcurrentIndependentNormalization() {
        let input = NSAttributedString(string: " \u{2028}🙂\nhello\u{fffc}world\n ", attributes: [NSAttributedString.Key("marker"): "value"])
        let trimmed = input.referenceTrimmed
        let spaces = input.referenceTrimNewLinesToSpace
        let lock = NSLock()
        var mismatches = 0
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in
            autoreleasepool {
                if !input.trimmed.isEqual(to: trimmed) || !input.trimNewLinesToSpace.isEqual(to: spaces) {
                    lock.lock()
                    mismatches += 1
                    lock.unlock()
                }
            }
        }
        XCTAssertEqual(mismatches, 0)
    }

    func testCoreTextRenderingMatchesReference() throws {
        func render(_ text: NSAttributedString) -> (Data, CGImage) {
            let context = CGContext(data: nil, width: 640, height: 360, bitsPerComponent: 8, bytesPerRow: 640 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
            context.scaleBy(x: 2, y: 2)
            context.textMatrix = .identity
            let path = CGPath(rect: CGRect(x: 8, y: 8, width: 304, height: 164), transform: nil)
            let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
            CTFrameDraw(frame, context)
            return (Data(bytes: context.data!, count: context.bytesPerRow * context.height), context.makeImage()!)
        }
        let texts = [
            "Привет 🙂\nhello\nworld",
            "  a\u{2028}b\u{fffc}c  ",
            "a\u{2028}\u{0301}b\u{2028}c",
            "👩🏽‍💻\nمرحبا\u{2028}中文 e\u{0301} 🇷🇺",
            "\n\t \u{2028}",
            String(repeating: "hello 🙂\u{2028}world\u{fffc}", count: 8)
        ]
        let directory = ProcessInfo.processInfo.environment["TEXT_NORMALIZATION_SNAPSHOTS"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let directory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        for (index, text) in texts.enumerated() {
            let input = styled(text)
            for trim in [false, true] {
                let before = render(trim ? input.referenceTrimmed : input.referenceTrimNewLinesToSpace)
                let after = render(trim ? input.trimmed : input.trimNewLinesToSpace)
                XCTAssertEqual(after.0, before.0, "case \(index), trim=\(trim)")
                if let directory {
                    for (label, image) in [("before", before.1), ("after", after.1)] {
                        let file = directory.appendingPathComponent("\(index)-\(trim ? "trim" : "preview")-\(label).png")
                        let destination = CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil)!
                        CGImageDestinationAddImage(destination, image, nil)
                        XCTAssertTrue(CGImageDestinationFinalize(destination))
                    }
                }
            }
        }
    }
}
