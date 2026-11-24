import Foundation
import RichTextEditorCore
import InputView
import TelegramCore

/// Merging a pasted rich fragment into the text that already sits in the composer.
///
/// When a rich fragment is pasted into the composer, the editor takes over the WHOLE composer
/// content (it seeds itself with the composer's text around the caret plus the fragment), so
/// closing the editor must give the text back. Without that, closing the editor after a paste
/// replaces everything the user had typed with the pasted fragment alone.
///
/// The merge rules mirror the editor's own fragment insertion (`DocumentCanvasView.insertFragment`)
/// so that a paste into the composer produces the same layout as a paste into the editor:
///   • a single-paragraph fragment merges INLINE with the text around the caret
///     ("hello " + "X" + " world" is one paragraph, not three);
///   • a fragment that is not a paragraph (a table, a code block) keeps its own block, with the
///     surrounding text staying in its own paragraphs;
///   • the text before the caret keeps its own paragraph when the fragment has several blocks —
///     it is never glued onto the fragment's first block.
public enum RichTextComposerPasteMerge {

    /// The composer's text split around the caret, as editor blocks.
    ///
    /// `before` is the text before the caret, `after` the text after it. A caret with a non-empty
    /// selection replaces the selected range, exactly like a normal paste.
    public static func surroundingBlocks(_ state: ChatTextInputState) -> (before: [Block], after: [Block]) {
        let length = state.inputText.length
        let lower = min(max(0, state.selectionRange.lowerBound), length)
        let upper = min(max(lower, state.selectionRange.upperBound), length)
        func blocks(_ range: NSRange) -> [Block] {
            guard range.length > 0 else {
                return []
            }
            // `trimWhitespace: false` — the spaces and blank lines around the caret belong to the
            // user's text; trimming them would silently eat "hello | world" into "helloworld".
            let part = state.subInputState(from: range, trimWhitespace: false)
            return richTextDocument(text: part.inputText, entities: part.messageTextEntities()).blocks
        }
        return (blocks(NSMakeRange(0, lower)), blocks(NSMakeRange(upper, length - upper)))
    }

    /// Splices `fragment` between the text around the caret.
    ///
    /// Mirrors `DocumentCanvasView.insertFragment`:
    ///   • a single-paragraph fragment merges inline with the surrounding paragraphs;
    ///   • a single non-paragraph block (a table) stays its own block;
    ///   • with several fragment blocks, the first and the last join the neighbouring paragraph
    ///     (keeping that paragraph's style) while the interior blocks are inserted whole.
    ///
    /// Generic over the block type so the same rules serve both the core `Block` (a pasted
    /// selection) and the outgoing `RichTextOutgoingBlock` (a refetched media-bearing message).
    public static func merge<BlockType>(
        fragment: [BlockType],
        before: [BlockType],
        after: [BlockType],
        paragraph: (BlockType) -> ParagraphBlock?,
        makeParagraph: (ParagraphBlock) -> BlockType
    ) -> [BlockType] {

        guard !fragment.isEmpty else {
            return before + after
        }

        var head = before
        var tail = after
        var blocks = fragment

        // The text before the caret joins the fragment's first block — but only when that block is a
        // paragraph. A table (or any other structural block) keeps the text before it in its own
        // paragraph, so the typed text is never swallowed into the fragment.
        if let headParagraph = head.last.flatMap(paragraph) {
            if let first = blocks.first.flatMap(paragraph) {
                var merged = headParagraph
                merged.runs = headParagraph.runs + first.runs
                blocks[0] = makeParagraph(merged)
                head.removeLast()
            }
        }

        // Symmetrically, the text after the caret joins the fragment's last block.
        if let tailParagraph = tail.first.flatMap(paragraph), let last = blocks.last.flatMap(paragraph) {
            var merged = tailParagraph
            merged.runs = last.runs + tailParagraph.runs
            blocks[blocks.count - 1] = makeParagraph(merged)
            tail.removeFirst()
        }

        return head + blocks + tail
    }
}

/// The plain-text form of a pasted rich fragment, for inserting it into the composer without
/// opening the rich editor.
///
/// A fragment that can be expressed as text + message entities keeps its inline formatting
/// (bold, italic, code, quotes, links); a structural one (a table, a heading, a formula) is
/// flattened to its text rendering, the same one the rich editor's plain preview shows.
public func richTextPastePlainContent(_ document: Document) -> (text: String, entities: [MessageTextEntity]) {
    let blocks = outgoingBlocks(fromSelection: document.blocks)
    return richTextPlainPreview(from: blocks, media: [:])
}
