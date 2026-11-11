import Cocoa

struct InlineStickerKeyCollection {
    var keys: [InlineStickerItemLayer.Key] = []
    var isSequential = true
    var firstIndex = 0

    init() {
    }

    mutating func append(_ key: InlineStickerItemLayer.Key) {
        if keys.isEmpty {
            firstIndex = key.index
        } else if isSequential {
            let (offset, overflow) = key.index.subtractingReportingOverflow(firstIndex)
            isSequential = !overflow && offset == keys.count
        }
        keys.append(key)
    }

    func contains(_ key: InlineStickerItemLayer.Key) -> Bool {
        guard isSequential else {
            return keys.contains(key)
        }
        let (offset, overflow) = key.index.subtractingReportingOverflow(firstIndex)
        return !overflow && offset >= 0 && offset < keys.count && keys[offset] == key
    }
}
