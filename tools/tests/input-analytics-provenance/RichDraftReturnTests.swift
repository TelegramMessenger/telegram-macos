extension NSAttributedString {
    static func initialize(string: String) -> NSAttributedString { NSAttributedString(string: string) }
}

private func editorReturn(_ text: String, _ entities: [MessageTextEntity], _ origin: AnalyticsContext) -> ChatTextInputState {
__RICH_RETURN__
    return restored
}

private func seededEditorReturn(_ text: String, _ entities: [MessageTextEntity], _ origin: AnalyticsContext) -> ChatTextInputState {
__PASTED_RETURN__
    return restored
}

private func inlineEditorReturn(_ text: String, _ entities: [MessageTextEntity], _ origin: AnalyticsContext) -> ChatTextInputState {
__INLINE_RETURN__
    return restored
}

final class RichDraftReturnTests: XCTestCase {
    let routes = [editorReturn, seededEditorReturn, inlineEditorReturn]
    var context: FormattingAccountContext!
    var hub: Analytics { Analytics.shared }

    override func setUp() {
        Analytics.shared = Analytics()
        context = FormattingAccountContext()
        hub.policy.setOwner(context.engine.account)
        hub.policy.isEnabled = true
    }

    func testPrivateResultsKeepUTF16ExclusionThroughAllReturnRoutes() throws {
        let origin = hub.captureContext(engine: context.engine, peerId: PeerId(-1))
        for route in routes {
            let result = route("A😀B", [.init(range: 0..<1, type: .Bold)], origin)
            XCTAssertEqual(result.inputText, "A😀B")
            XCTAssertEqual(result.selectionRange, 4..<4)
            XCTAssertTrue(result.hasExcludedAnalytics)
            let excluded = result.attributes.flatMap { attribute -> [Int] in
                if case let .analyticsExcluded(range) = attribute { return Array(range) }
                return []
            }
            XCTAssertEqual(Set(excluded), Set(0..<4))
            XCTAssertTrue(result.attributes.contains(.bold(0..<1)))
            let decoded = try JSONDecoder().decode(ChatTextInputState.self, from: JSONEncoder().encode(result))
            XCTAssertTrue(decoded.hasExcludedAnalytics)
            XCTAssertEqual(result.messageTextEntities(), [.init(range: 0..<1, type: .Bold)])
        }
    }

    func testOrdinaryResultsRetainFormattingWithoutAnExclusionMarker() {
        let origin = hub.captureContext(engine: context.engine, peerId: PeerId(1))
        for route in routes {
            let result = route("hello", [.init(range: 0..<5, type: .Italic)], origin)
            XCTAssertFalse(result.hasExcludedAnalytics)
            XCTAssertEqual(result.inputText, "hello")
            XCTAssertEqual(result.attributes, [.italic(0..<5)])
        }
    }

    func testRevokedAndUnresolvedResultsStayExcluded() {
        let revoked = hub.captureContext(engine: context.engine, peerId: PeerId(1))
        revoked.scope?.exclude()
        for origin in [revoked, hub.unresolvedContext()] {
            for route in routes {
                XCTAssertTrue(route("hello", [], origin).hasExcludedAnalytics)
            }
        }
    }

    func testCodeFencesAreIncludedInTheReturnedExclusionRange() {
        let origin = hub.unresolvedContext()
        for route in [editorReturn, seededEditorReturn] {
            let result = route("print(1)", [.init(range: 0..<8, type: .Pre(language: "swift"))], origin)
            XCTAssertEqual(result.inputText, "```swift\nprint(1)```")
            XCTAssertEqual(result.selectionRange, result.inputText.length..<result.inputText.length)
            XCTAssertTrue(result.attributes.contains(.analyticsExcluded(0..<result.inputText.length)))
        }
    }
}
