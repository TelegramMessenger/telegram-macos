import Cocoa
import TelegramCore
import TGGifConverter
import Postbox
import SwiftSignalKit
import TelegramMediaResources
import ArchiveUtils
import TelegramUtils

public func fetchGifMediaResource(resource: LocalFileGifMediaResource) -> Signal<MediaResourceDataFetchResult, MediaResourceDataFetchError> {
    return Signal { subscriber in
        subscriber.putNext(.reset)
        
        let queue: Queue = Queue()
        var cancelled: Bool = false
        let exportPath = NSTemporaryDirectory() + "\(resource.randomId).mp4"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: resource.path)) {
            queue.async {
                TGGifConverter.convertGif(toMp4: data, exportPath: exportPath, completionHandler: { path in
                    _ = NSTemporaryDirectory() + "\(arc4random()).mp4"
//                    let remuxed = FFMpegRemuxer.remux(path, to: remuxedPath)
//                    if remuxed {
//                        try? FileManager.default.removeItem(atPath: path)
//                        try? FileManager.default.moveItem(atPath: remuxedPath, toPath: path)
//                    }
                    if let path = path {
                        subscriber.putNext(.moveLocalFile(path: path))
                    }
                    subscriber.putCompletion()
                }, errorHandler: {
                    subscriber.putError(.generic)
                }, cancelHandler: { () -> Bool in
                    return cancelled
                })
            }
        }
        
        return ActionDisposable {
            cancelled = true
        }
    }
}


public func fetchMovMediaResource(resource: LocalFileVideoMediaResource) -> Signal<MediaResourceDataFetchResult, MediaResourceDataFetchError> {
    if let events = PendingVideoRenders.shared.events(for: resource.path) {
        return Signal { subscriber in
            subscriber.putNext(.reset)
            let queue = Queue()
            var state = VideoRenderUploadState()
            let disposable = (events |> deliverOn(queue)).start(next: { event in
                do {
                    try state.update(event, finalPath: resource.path) { chunk in
                        switch chunk {
                        case let .data(offset, data):
                            subscriber.putNext(.dataPart(resourceOffset: offset, data: data, range: 0 ..< Int64(data.count), complete: false))
                        case let .header(data):
                            subscriber.putNext(.replaceHeader(data: data, range: 0 ..< Int64(data.count)))
                        case let .complete(size):
                            subscriber.putNext(.dataPart(resourceOffset: size, data: Data(), range: 0 ..< 0, complete: true))
                            subscriber.putCompletion()
                        case .completeFile:
                            _ = copyMovMediaResource(resource: resource).start(next: { subscriber.putNext($0) }, error: { subscriber.putError($0) }, completed: { subscriber.putCompletion() })
                        }
                    }
                } catch {
                    subscriber.putError(.generic)
                }
            })
            return disposable
        }
    }
    return copyMovMediaResource(resource: resource)
}

private func copyMovMediaResource(resource: LocalFileVideoMediaResource) -> Signal<MediaResourceDataFetchResult, MediaResourceDataFetchError> {
    return Signal { subscriber in
        subscriber.putNext(.reset)
        let exportPath = NSTemporaryDirectory() + "\(resource.randomId).mp4"
        if FileManager.default.fileExists(atPath: exportPath) {
            removeFile(at: exportPath)
        }
        do {
            try FileManager.default.copyItem(atPath: resource.path, toPath: exportPath)
            subscriber.putNext(.moveLocalFile(path: exportPath))
            subscriber.putCompletion()
        } catch {
            try? FileManager.default.removeItem(atPath: exportPath)
            subscriber.putError(.generic)
        }
        return EmptyDisposable
    }
}

public func fetchArchiveMediaResource(resource: LocalFileArchiveMediaResource) -> Signal<MediaResourceDataFetchResult, MediaResourceDataFetchError> {
    return Signal { subscriber in
        subscriber.putNext(.reset)
        let source: ArchiveSource = .resource(resource)
        let disposable = archiver.archive(source, startIfNeeded: true).start(next: { status in
            switch status {
            case let .done(url):
                if resource.path.contains("tg_temp_archive_") {
                    try? FileManager.default.removeItem(atPath: resource.path)
                }
                subscriber.putNext(.moveLocalFile(path: url.path))
                subscriber.putCompletion()
                archiver.remove(source)
            case .fail:
                subscriber.putError(.generic)
                subscriber.putCompletion()
            default:
                break
            }
        }, completed: {
            subscriber.putCompletion()
        })
        
        return ActionDisposable {
            disposable.dispose()
        }
    }
}


public func fetchLottieSoundData(resource: LottieSoundMediaResource) -> Signal<MediaResourceDataFetchResult, MediaResourceDataFetchError> {
    return Signal { subscriber in
        subscriber.putNext(.reset)
        let remuxedPath = NSTemporaryDirectory() + "\(arc4random()).mp4"
        try? resource.data.write(to: URL(fileURLWithPath: remuxedPath))
        subscriber.putNext(.moveLocalFile(path: remuxedPath))
        subscriber.putCompletion()
        
        
        return ActionDisposable {
            
        }
    }
}
