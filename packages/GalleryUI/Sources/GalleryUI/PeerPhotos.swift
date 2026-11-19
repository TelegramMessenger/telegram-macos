import Cocoa
import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi
import TelegramCore
import TelegramUtils
import TGUIKit
import Localization
import TelegramTheme
import TelegramContext
import ChatModeTypes
import ChatHistoryModel
import GeneralRows
import LocalAnimations
import TelegramMediaUtils
import TelegramMedia
import AvatarUI
import MessageUtils
import InstantPageUI
import SecureIdUtils
import ColorPalette
import InAppSettings
import FoundationUtils
import ObjcUtils

public func peerPhotosGalleryEntries(context: any AccountContextProtocol, peerId: PeerId, firstStableId: AnyHashable) -> Signal<(entries: [GalleryEntry], selected:Int, publicPhoto: TelegramMediaImage?), NoError> {
    
    var isLoading: Bool = !hasCachedPeerPhotos(peerId: peerId)
    
    return combineLatest(queue: prepareQueue, peerPhotos(context: context, peerId: peerId, force: true), context.account.postbox.loadedPeerWithId(peerId), getCachedDataView(peerId: peerId, postbox: context.account.postbox) |> take(1)) |> map { photos, peer, cachedData in
        
        var entries: [GalleryEntry] = []
        
        let publicPhoto = cachedData?.fallbackPhoto

        var representations:[TelegramMediaImageRepresentation] = []
        if let representation = peer.smallProfileImage {
            representations.append(representation)
        }
        if let representation = peer.largeProfileImage {
            representations.append(representation)
        }
        
        let videoRepresentations: [TelegramMediaImage.VideoRepresentation] = []
        
        
        var image:TelegramMediaImage? = nil
        var msg: Message? = nil
        if let base = firstStableId.base as? ChatHistoryEntryId, case let .message(message) = base {
            let action = message.extendedMedia as! TelegramMediaAction
            switch action.action {
            case let .photoUpdated(updated):
                image = updated
                msg = message
            default:
                break
            }
        }
        
        if image == nil {
            image = TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.CloudImage, id: 0), representations: representations, videoRepresentations: videoRepresentations, immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
        }
        
        let isPersonal = image!.representations.contains(where: { $0.isPersonal })
        
        
        let firstEntry: GalleryEntry = .photo(index: 0, stableId: firstStableId, photo: image!, reference: nil, peer: peer, message: msg, date: 0, caption: isPersonal ? strings().galleryContactPhotoByYou : nil, publicPhoto: publicPhoto)
        
        var foundIndex: Bool = peerId.namespace == Namespaces.Peer.CloudUser && !photos.isEmpty
        var currentIndex: Int = 0
        var foundMessage: Message? = nil
        var photosDate:[TimeInterval] = []
        for i in 0 ..< photos.count {
            let photo = photos[i].value
            photosDate.append(TimeInterval(photo.date))
            if let base = firstStableId.base as? ChatHistoryEntryId, case let .message(message) = base {
                let action = message.extendedMedia as! TelegramMediaAction
                switch action.action {
                case let .photoUpdated(updated):
                    if photo.image.id == updated?.id {
                        currentIndex = i
                        foundIndex = true
                        foundMessage = message
                    }
                default:
                    break
                }
            } else if i == 0 {
                foundIndex = true
                currentIndex = i
                
            }
        }
        for i in 0 ..< photos.count {
            let photo = photos[i].value
            if currentIndex == i && foundIndex {
                let image = TelegramMediaImage(imageId: photo.image.imageId, representations: image!.representations, videoRepresentations: photo.image.videoRepresentations, immediateThumbnailData: photo.image.immediateThumbnailData, reference: photo.image.reference, partialReference: photo.image.partialReference, flags: photo.image.flags)
                
                entries.append(.photo(index: photo.index, stableId: firstStableId, photo: image, reference: photo.reference, peer: peer, message: foundMessage, date: photosDate[i], caption: photos[i].caption, publicPhoto: i == 0 ? publicPhoto : nil))
            } else {
                entries.append(.photo(index: photo.index, stableId: photo.image.imageId, photo: photo.image, reference: photo.reference, peer: peer, message: nil, date: photosDate[i], caption: photos[i].caption, publicPhoto: nil))
            }
        }
        
        if !foundIndex && entries.isEmpty {
            entries.append(firstEntry)
        }
        
        
        if let publicPhoto = publicPhoto, !isLoading {
            entries.append(.photo(index: .max, stableId: publicPhoto.imageId, photo: publicPhoto, reference: publicPhoto.reference, peer: peer, message: nil, date: 0, caption: strings().galleryPublicPhoto, publicPhoto: nil))
        }
        isLoading = false
        return (entries: entries, selected: currentIndex, publicPhoto: publicPhoto)
        
    }
}
