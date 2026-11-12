import Foundation

struct TableStickyHeaderLayout {
    let id: AnyHashable
    let naturalY: CGFloat
    private(set) var sectionEnd: CGFloat
    let height: CGFloat
    var y: CGFloat
    private(set) var offsetBy: AnyHashable?

    init(id: AnyHashable, naturalY: CGFloat, sectionEnd: CGFloat, height: CGFloat, inset: CGFloat) {
        self.id = id
        self.naturalY = naturalY
        self.sectionEnd = sectionEnd
        self.height = height
        self.y = min(max(inset, naturalY), sectionEnd - height)
    }

    mutating func end(beforeLeading headers: [TableStickyHeaderLayout]) {
        if let header = headers.first(where: { $0.naturalY > naturalY && $0.naturalY < sectionEnd && abs($0.naturalY + $0.height - sectionEnd) < 1 }) {
            sectionEnd = header.naturalY
            y = min(y, sectionEnd - height)
        }
    }

    mutating func yield(to headers: [TableStickyHeaderLayout], spacing: CGFloat? = nil) {
        for _ in 0 ..< 2 {
            let overlapping = headers.filter { $0.y < y + height && $0.y + $0.height > y }
            if let header = overlapping.max(by: { $0.y + $0.height < $1.y + $1.height }) {
                y = min(sectionEnd - height, max(y, header.y + header.height - height + (spacing ?? height)))
                offsetBy = header.id
            }
        }
    }
}
