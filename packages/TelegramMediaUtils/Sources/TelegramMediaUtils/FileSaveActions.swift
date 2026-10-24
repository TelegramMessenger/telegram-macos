import Cocoa
import TelegramCore
import Postbox
import SwiftSignalKit
import InAppSettings
import TGUIKit
import FilePanels
import TelegramTheme
import TelegramUtils
import FoundationUtils
import Localization
import TelegramContext

public func saveAs(_ file: TelegramMediaFile, account: Account, context: (any AccountContextProtocol)? = nil, message: Message? = nil) {
    let extSignal: Signal<String, NoError>
    if let ext = file.fileName?.nsstring.pathExtension, !ext.isEmpty {
        extSignal = .single(ext)
    } else {
        extSignal = resourceType(mimeType: file.mimeType) |> map { _type in
            return (_type == "*" || _type == nil) ? "file" : _type!
        }
    }

    _ = (extSignal |> deliverOnMainQueue).start(next: { ext in
        let savePanel: NSSavePanel = NSSavePanel()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        savePanel.nameFieldStringValue = file.fileName ?? "\(dateFormatter.string(from: Date())).\(ext)"

        let window = context?.window ?? mainWindow
        let wLevel = window.level
        window.level = .normal

        savePanel.begin { result in
            if result == NSApplication.ModalResponse.OK, let saveUrl = savePanel.url {
                let targetPath = saveUrl.path

                let checkComplete = account.postbox.mediaBox.resourceData(file.resource) |> take(1) |> deliverOnMainQueue
                _ = checkComplete.start(next: { initialData in
                    if initialData.complete {
                        try? FileManager.default.removeItem(atPath: targetPath)
                        try? FileManager.default.copyItem(atPath: initialData.path, toPath: targetPath)
                        delay(0.3, closure: {
                            FilePanelsHooks.shared?.showSavedPathSuccess(targetPath)
                        })
                    } else {
                        showModalText(for: window, text: strings().galleryContextAlertDownloading)

                        var fetchDisposable: Disposable? = nil
                        let dataDisposable = MetaDisposable()

                        dataDisposable.set((account.postbox.mediaBox.resourceData(file.resource) |> deliverOnMainQueue).start(next: { data in
                            if data.complete {
                                fetchDisposable?.dispose()
                                dataDisposable.dispose()
                                try? FileManager.default.removeItem(atPath: targetPath)
                                try? FileManager.default.copyItem(atPath: data.path, toPath: targetPath)
                                delay(0.3, closure: {
                                    FilePanelsHooks.shared?.showSavedPathSuccess(targetPath)
                                })
                            }
                        }))

                        if let context = context, let message = message {
                            fetchDisposable = messageMediaFileInteractiveFetched(context: context, messageId: message.id, messageReference: .init(message), file: file, userInitiated: true).start()
                        } else if let context = context {
                            fetchDisposable = freeMediaFileInteractiveFetched(context: context, fileReference: .standalone(media: file)).start()
                        } else {
                            fetchDisposable = fetchedMediaResource(mediaBox: account.postbox.mediaBox, userLocation: .other, userContentType: .other, reference: FileMediaReference.standalone(media: file).resourceReference(file.resource)).start()
                        }
                    }
                })
            }
            window.level = wLevel
        }
    })
}

public func saveImageAs(_ image: TelegramMediaImage, account: Account, context: (any AccountContextProtocol)? = nil, message: Message? = nil) {
    guard let resource = image.representations.last?.resource else { return }

    let savePanel: NSSavePanel = NSSavePanel()
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
    savePanel.nameFieldStringValue = "photo_\(dateFormatter.string(from: Date())).jpg"

    let window = context?.window ?? mainWindow
    let wLevel = window.level
    window.level = .normal

    savePanel.begin { result in
        if result == NSApplication.ModalResponse.OK, let saveUrl = savePanel.url {
            let targetPath = saveUrl.path

            let checkComplete = account.postbox.mediaBox.resourceData(resource) |> take(1) |> deliverOnMainQueue
            _ = checkComplete.start(next: { initialData in
                if initialData.complete {
                    try? FileManager.default.removeItem(atPath: targetPath)
                    try? FileManager.default.copyItem(atPath: initialData.path, toPath: targetPath)
                    delay(0.3, closure: {
                        FilePanelsHooks.shared?.showSavedPathSuccess(targetPath)
                    })
                } else {
                    showModalText(for: window, text: strings().galleryContextAlertDownloading)

                    var fetchDisposable: Disposable? = nil
                    let dataDisposable = MetaDisposable()

                    dataDisposable.set((account.postbox.mediaBox.resourceData(resource) |> deliverOnMainQueue).start(next: { data in
                        if data.complete {
                            fetchDisposable?.dispose()
                            dataDisposable.dispose()
                            try? FileManager.default.removeItem(atPath: targetPath)
                            try? FileManager.default.copyItem(atPath: data.path, toPath: targetPath)
                            delay(0.3, closure: {
                                FilePanelsHooks.shared?.showSavedPathSuccess(targetPath)
                            })
                        }
                    }))

                    let imageReference: ImageMediaReference
                    if let message = message {
                        imageReference = .message(message: MessageReference(message), media: image)
                    } else {
                        imageReference = .standalone(media: image)
                    }
                    fetchDisposable = chatMessagePhotoInteractiveFetched(account: account, imageReference: imageReference).start()
                }
            })
        }
        window.level = wLevel
    }
}

public func showInFinder(_ file:TelegramMediaFile, account:Account)  {
    let path = downloadFilePath(file, account.postbox) |> deliverOnMainQueue
    
    _ = combineLatest(queue: .mainQueue(), path, downloadedFilePaths(account.postbox)).start(next: { (expanded, paths) in
        
        guard let (boxPath, adopted) = expanded else {
            return
        }
        if let id = file.id {
            do {
                
                if let path = paths.path(for: id) {
                    let lastModified = Int32(FileManager.default.modificationDateForFileAtPath(path: path.downloadedPath)?.timeIntervalSince1970 ?? 0)
                    if fileSize(path.downloadedPath) == Int64(path.size), lastModified == path.lastModified {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path.downloadedPath)])
                        return
                    }
                
                }
                
                var adopted = adopted
                var i:Int = 1
                let deletedPathExt = adopted.nsstring.deletingPathExtension
                while FileManager.default.fileExists(atPath: adopted, isDirectory: nil) {
                    let ext = adopted.nsstring.pathExtension
                    adopted = "\(deletedPathExt) (\(i)).\(ext)"
                    i += 1
                }
                
                try? FileManager.default.copyItem(atPath: boxPath, toPath: adopted)
           
                let quarantineData = "does not really matter what is here".cString(using: String.Encoding.utf8)!
                _ = Int(strlen(quarantineData))
                
//                setxattr(adopted.cString(using: .utf8), "com.apple.quarantine", quarantineData, quarantineDataLength, 0, XATTR_CREATE)

                    // removexattr(adopted.cString(using: .utf8), "com.apple.quarantine", 0)

                
                let lastModified = FileManager.default.modificationDateForFileAtPath(path: adopted)?.timeIntervalSince1970 ?? FileManager.default.creationDateForFileAtPath(path: adopted)?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
                
                let fs = fileSize(boxPath)
                let fileSize = fs ?? file.size ?? 0
                let path = DownloadedPath(id: id, downloadedPath: adopted, size: Int64(fileSize), lastModified: Int32(lastModified))
                
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: adopted)])
                _ = updateDownloadedFilePaths(account.postbox, {
                    $0.withAddedPath(path)
                }).start()
                
            }
        }
    })
}
