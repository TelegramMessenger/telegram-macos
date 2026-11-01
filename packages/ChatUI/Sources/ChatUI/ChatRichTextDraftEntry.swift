import Foundation
import Postbox
import TelegramCore

final class ChatRichTextDraftEntry: Codable {
    let page: InstantPage

    init(page: InstantPage) {
        self.page = page
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        let pageData = try container.decode(AdaptedPostboxDecoder.RawObjectData.self, forKey: "page")
        self.page = InstantPage(decoder: PostboxDecoder(buffer: MemoryBuffer(data: pageData.data)))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode(PostboxEncoder().encodeObjectToRawData(self.page), forKey: "page")
    }
}
