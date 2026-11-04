struct MessageTextEntity {
    enum EntityType {
        case CustomEmoji(Int?, Int64)
        case Bold
    }
    let range: Range<Int>
    let type: EntityType
}

enum TextInputAttributes {
    static let embedded = NSAttributedString.Key("Attribute__EmbeddedItem")
}
