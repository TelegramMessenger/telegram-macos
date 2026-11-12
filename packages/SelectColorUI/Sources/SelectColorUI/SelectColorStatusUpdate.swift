import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramContext
import TelegramMediaUtils

enum SelectColorSaveError {
    case generic
}

struct SelectColorStatusUpdate {
    let status: PeerEmojiStatus?
    let gift: StarGift.UniqueGift?

    static func selection(file: TelegramMediaFile, gift: StarGift.UniqueGift?, timeout: Int32?, timestamp: Int32) -> SelectColorStatusUpdate? {
        if gift == nil, file.mimeType.hasPrefix("bundle") {
            return .init(status: nil, gift: nil)
        }
        let expirationDate: Int32?
        if let timeout, timeout != 0 {
            guard timeout > 0, let value = Int32(exactly: Int64(timestamp) + Int64(timeout)) else { return nil }
            expirationDate = value
        } else {
            expirationDate = nil
        }
        if let gift {
            guard let model = gift.file, let pattern = gift.pattern else { return nil }
            for attribute in gift.attributes {
                if case let .backdrop(_, _, innerColor, outerColor, patternColor, textColor, _) = attribute {
                    return .init(status: .init(content: .starGift(id: gift.id, fileId: model.fileId.id, title: gift.title, slug: gift.slug, patternFileId: pattern.fileId.id, innerColor: innerColor, outerColor: outerColor, patternColor: patternColor, textColor: textColor), expirationDate: expirationDate), gift: gift)
                }
            }
            return nil
        }
        guard file.isCustomEmoji else { return nil }
        return .init(status: .init(content: .emoji(fileId: file.fileId.id), expirationDate: expirationDate), gift: nil)
    }

    static func request(context: any AccountContextProtocol, peer: EnginePeer, status: PeerEmojiStatus?, gift: StarGift.UniqueGift?) -> Signal<Never, SelectColorSaveError> {
        guard status != peer.emojiStatus else { return .complete() }
        let engine = context.engine
        let isAccount = peer.id == context.peerId && peer._asPeer() is TelegramUser
        let isChannel = peer._asPeer() is TelegramChannel
        guard isAccount || isChannel else { return .fail(.generic) }
        guard let status else {
            if isAccount {
                return engine.accountData.setEmojiStatusWithResult(file: nil, expirationDate: nil) |> mapError { _ in .generic }
            } else {
                return engine.peers.updatePeerEmojiStatus(peerId: peer.id, fileId: nil, expirationDate: nil) |> mapError { _ in .generic }
            }
        }
        switch status.content {
        case let .emoji(fileId):
            if isChannel {
                return engine.peers.updatePeerEmojiStatus(peerId: peer.id, fileId: fileId, expirationDate: status.expirationDate) |> mapError { _ in .generic }
            }
            return context.inlinePacksContext.load(fileId: fileId)
            |> then(.single(nil))
            |> take(1)
            |> castError(SelectColorSaveError.self)
            |> mapToSignal { file -> Signal<Never, SelectColorSaveError> in
                guard let file, file.fileId.id == fileId, file.isCustomEmoji else { return .fail(.generic) }
                return engine.accountData.setEmojiStatusWithResult(file: file, expirationDate: status.expirationDate) |> mapError { _ in .generic }
            }
        case let .starGift(id, _, _, _, _, _, _, _, _):
            guard let gift, gift.id == id, (gift.owner?.peerId ?? gift.hostPeerId) == peer.id else { return .fail(.generic) }
            if isAccount {
                return engine.accountData.setStarGiftStatusWithResult(starGift: gift, expirationDate: status.expirationDate) |> mapError { _ in .generic }
            } else {
                return engine.peers.updatePeerStarGiftStatus(peerId: peer.id, starGift: gift, expirationDate: status.expirationDate) |> mapError { _ in .generic }
            }
        }
    }
}
