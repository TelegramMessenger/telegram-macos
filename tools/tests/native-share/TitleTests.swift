func emoji(_ range: Range<Int>, _ id: Int64 = 1) -> MessageTextEntity {
    return MessageTextEntity(range: range, type: .CustomEmoji(nil, id))
}

private func make(_ title: String, _ entities: [MessageTextEntity]) -> (text: NSAttributedString, emojis: [Int: SEFolderTitleEmoji]) {
    return SEFolderTitle.make(title: title, entities: entities, color: .black, font: .systemFont(ofSize: 14))
}

private let plain = make("All Chats", [])
assert(plain.text.string == "All Chats" && plain.emojis.isEmpty)

private let mixed = make("Work ⭐️ Dev 👩‍💻", [emoji(5..<7, 10), emoji(12..<17, 20)])
assert(mixed.text.string == "Work 🤡 Dev 🤡")
assert(mixed.emojis.count == 2)
assert(mixed.emojis.values.contains { $0.fileId == 10 && $0.fallback == "⭐️" })
assert(mixed.emojis.values.contains { $0.fileId == 20 && $0.fallback == "👩‍💻" })
var embeddedCount = 0
mixed.text.enumerateAttribute(TextInputAttributes.embedded, in: NSRange(location: 0, length: mixed.text.length)) { value, _, _ in
    if value != nil { embeddedCount += 1 }
}
assert(embeddedCount == 2)

private let adjacent = make("😀😀", [emoji(2..<4, 8), emoji(0..<2, 8)])
assert(adjacent.text.string == "🤡🤡" && adjacent.emojis.count == 2)
assert(adjacent.emojis.values.allSatisfy { $0.fileId == 8 && $0.fallback == "😀" })

private let invalid = make("😀", [emoji(-1..<1), emoji(0..<3), emoji(0..<1), emoji(1..<2), emoji(0..<0)])
assert(invalid.text.string == "😀" && invalid.emojis.isEmpty)

private let combining = make("e\u{301}", [emoji(0..<1), emoji(1..<2)])
assert(combining.text.string == "e\u{301}" && combining.emojis.isEmpty)

private let overlap = make("abcdef", [emoji(0..<4, 1), emoji(2..<6, 2), emoji(2..<6, 3)])
assert(overlap.emojis.count == 1 && overlap.text.string == "ab🤡")

private let rtl = make("عمل 😀", [emoji(4..<6, 9)])
assert(rtl.text.string == "عمل 🤡" && rtl.emojis.count == 1)

private let styling = make("Work", [MessageTextEntity(range: 0..<4, type: .Bold)])
assert(styling.text.string == "Work" && styling.emojis.isEmpty)
assert(make("", [emoji(0..<2)]).emojis.isEmpty)
print("Native share folder title tests passed")
