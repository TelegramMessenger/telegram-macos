import Foundation
import XCTest
import TelegramCore
@testable import MessageTextUtils

final class InstantPagePreviewTests: XCTestCase {
    private func page(_ blocks: [InstantPageBlock]) -> InstantPage {
        return InstantPage(blocks: blocks, media: [:], isComplete: true, rtl: false, url: "", views: nil)
    }

    private func caption(_ text: String) -> InstantPageCaption {
        return InstantPageCaption(text: .plain(text), credit: .empty)
    }

    private func table(_ texts: [RichText], title: RichText = .empty) -> InstantPageBlock {
        let cells = texts.map { InstantPageTableCell(text: $0, header: false, alignment: .left, verticalAlignment: .top, colspan: 1, rowspan: 1) }
        return .table(title: title, rows: [InstantPageTableRow(cells: cells)], bordered: false, striped: false, compact: false)
    }

    func testThinkingDoesNotHideAnswerOrProducePreview() {
        let thinking = InstantPageBlock.thinking(.plain(String(repeating: "Thinking ", count: 40)))
        XCTAssertEqual(instantPagePreviewText(page([thinking, .paragraph(.plain("Answer"))])), "Answer")
        XCTAssertEqual(instantPagePreviewText(page([thinking])), "")
        XCTAssertEqual(instantPagePreviewText(page([.cover(thinking), .paragraph(.plain("Answer"))])), "Answer")
        XCTAssertEqual(instantPagePreviewText(page([.details(title: .empty, blocks: [thinking, .paragraph(.plain("Answer"))], expanded: false)])), "Answer")
    }

    func testTableCellsAndButtonsHaveSeparators() {
        XCTAssertEqual(instantPagePreviewText(page([table([.plain("Name"), .plain("Age"), .plain("Alice"), .plain("30")])])), "Name Age Alice 30")
        let buttons = ["Yes", "", "No"].map { InstantPageButton(text: .plain($0), action: .text, color: nil) }
        XCTAssertEqual(instantPagePreviewText(page([.buttonRow(alignment: .left, buttons: buttons)])), "Yes No")
        XCTAssertEqual(instantPagePreviewText(page([table([.plain("Cell")], title: .plain("Title"))])), "Title")
    }

    func testSeparatedCellsPreserveUTF16EmojiRanges() {
        let preview = instantPagePreview(page([table([.plain("Name"), .textCustomEmoji(fileId: 42, alt: "😀"), .plain("Age")])]))
        XCTAssertEqual(preview.text, "Name 😀 Age")
        XCTAssertEqual(preview.entities.count, 1)
        XCTAssertEqual(preview.entities.first?.range, 5 ..< 7)
        XCTAssertEqual(preview.entities.first?.type, .CustomEmoji(stickerPack: nil, fileId: 42))
    }

    func testPreviewCoverExtractionDoesNotChangeLegacyRichText() {
        let emptyCover = InstantPageBlock.cover(.unsupported)
        XCTAssertEqual(instantPagePreviewText(page([.paragraph(.plain("First")), emptyCover, .paragraph(.plain("Last"))])), "First Last")
        let cover = InstantPageBlock.cover(.paragraph(.plain("Covered")))
        XCTAssertEqual(instantPagePreviewText(page([cover])), "Covered")
        XCTAssertEqual(instantPageRichTextFromBlocks([cover]).plainText, "")
        let paragraphs: [InstantPageBlock] = [.paragraph(.plain("First")), .paragraph(.empty), .paragraph(.plain("Last"))]
        XCTAssertEqual(instantPageRichTextFromBlocks(paragraphs).plainText, "First\n\nLast")
        XCTAssertEqual(instantPagePreviewText(page(paragraphs)), "First Last")
    }

    func testNestedPreviewUsesAllSupportedChildrenWithoutEmptySeparators() {
        let blocks: [InstantPageBlock] = [.cover(.unsupported), table([.plain("Name"), .plain("Alice")]), .paragraph(.plain("Answer"))]
        XCTAssertEqual(instantPagePreviewText(page([.blockQuote(blocks: blocks, caption: .empty, collapsed: false)])), "Name Alice Answer")
        XCTAssertEqual(instantPagePreviewText(page([.list(items: [.blocks(blocks, nil, nil)], ordered: false)])), "• Name Alice Answer")
    }

    func testPostEmbedBodyCaptionAndAuthorFallbacks() {
        func embedded(_ blocks: [InstantPageBlock], _ captionText: String, _ author: String) -> InstantPageBlock {
            return .postEmbed(url: "", webpageId: nil, avatarId: nil, author: author, date: 0, blocks: blocks, caption: caption(captionText))
        }
        XCTAssertEqual(instantPagePreviewText(page([embedded([.paragraph(.plain("Body"))], "Caption", "Author")])), "Body")
        XCTAssertEqual(instantPagePreviewText(page([embedded([], "Caption", "Author")])), "Caption")
        XCTAssertEqual(instantPagePreviewText(page([embedded([], "", "Author")])), "Author")
    }

    func testCollageSlideshowAndMediaCaptionFallbacks() {
        let mediaId = EngineMedia.Id(namespace: 0, id: 1)
        let image = InstantPageBlock.image(id: mediaId, caption: caption("Photo"), url: nil, webpageId: nil, spoiler: false)
        XCTAssertEqual(instantPagePreviewText(page([.cover(image)])), "Photo")
        XCTAssertEqual(instantPagePreviewText(page([.collage(items: [image], caption: caption("Collection"))])), "Photo")
        XCTAssertEqual(instantPagePreviewText(page([.slideshow(items: [], caption: caption("Slides"))])), "Slides")
        XCTAssertEqual(instantPagePreviewText(page([.document(id: mediaId, caption: caption("Document"))])), "Document")
        let emptyImage = InstantPageBlock.image(id: mediaId, caption: caption(""), url: nil, webpageId: nil, spoiler: false)
        XCTAssertEqual(instantPageRichTextFromBlocks([.cover(emptyImage), .paragraph(.plain("Answer"))]).plainText, "Answer")
        XCTAssertEqual(instantPagePreviewText(page([.cover(emptyImage), .unsupported])), "")
    }
}
