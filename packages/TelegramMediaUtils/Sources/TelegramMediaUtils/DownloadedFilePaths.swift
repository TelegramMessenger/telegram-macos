import Foundation
import Cocoa
import TelegramCore
import Postbox
import SwiftSignalKit
import TGUIKit
import InAppSettings
import TelegramTheme

public func copyToDownloads(_ file: TelegramMediaFile, postbox: Postbox, saveAnyway: Bool = false) -> Signal<String?, NoError>  {
    let path = downloadFilePath(file, postbox)
    return combineLatest(queue: resourcesQueue, path, downloadedFilePaths(postbox)) |> map { (expanded, paths) in
        guard case (let boxPath, var adopted)? = expanded else {
            return nil
        }
        let id = file.fileId
        if let path = paths.path(for: id), !saveAnyway {
            let lastModified = Int32(FileManager.default.modificationDateForFileAtPath(path: path.downloadedPath)?.timeIntervalSince1970 ?? 0)
            if fileSize(path.downloadedPath) == Int64(path.size), lastModified == path.lastModified {
                return path.downloadedPath
            }
        }
        var i:Int = 1
        let deletedPathExt = adopted.nsstring.deletingPathExtension
        while FileManager.default.fileExists(atPath: adopted, isDirectory: nil) {
            let ext = adopted.nsstring.pathExtension
            adopted = "\(deletedPathExt) (\(i)).\(ext)"
            i += 1
        }
        
        do {
            try FileManager.default.copyItem(atPath: boxPath, toPath: adopted)
        } catch {
            return nil
        }

        let quarantineData = "does not really matter what is here".cString(using: String.Encoding.utf8)!
        _ = Int(strlen(quarantineData))
        
//        setxattr(adopted.cString(using: .utf8), "com.apple.quarantine", quarantineData, quarantineDataLength, 0, XATTR_CREATE)
        
        //removexattr(adopted.cString(using: .utf8), "com.apple.quarantine", 0)
        
        let lastModified = FileManager.default.modificationDateForFileAtPath(path: adopted)?.timeIntervalSince1970 ?? FileManager.default.creationDateForFileAtPath(path: adopted)?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
        
        let fs = fileSize(boxPath)
        let fileSize = fs ?? file.size ?? 0
        let path = DownloadedPath(id: id, downloadedPath: adopted, size: Int64(fileSize), lastModified: Int32(lastModified))
        
        _ = updateDownloadedFilePaths(postbox, {
            $0.withAddedPath(path)
        }).start()
        
        return adopted
    }
    
//    return downloadFilePath(file, postbox) |> deliverOn(resourcesQueue) |> map { (boxPath, adopted) in
//        var adopted = adopted
//        var i:Int = 1
//        let deletedPathExt = adopted.nsstring.deletingPathExtension
//        while FileManager.default.fileExists(atPath: adopted, isDirectory: nil) {
//            let ext = adopted.nsstring.pathExtension
//            let box = FileManager.xattrStringValue(forKey: TelegramFileMediaBoxPath, at: URL(fileURLWithPath: adopted))
//            if box == boxPath {
//                return
//            }
//
//            adopted = "\(deletedPathExt) (\(i)).\(ext)"
//            i += 1
//        }
//
//        try? FileManager.default.copyItem(atPath: boxPath, toPath: adopted)
//        FileManager.setXAttrStringValue(boxPath, forKey: TelegramFileMediaBoxPath, at: URL(fileURLWithPath: adopted))
//    }
//
}

public func downloadFilePath(_ file: TelegramMediaFile, _ postbox: Postbox) -> Signal<(String, String)?, NoError> {
    return combineLatest(postbox.mediaBox.resourceData(file.resource), automaticDownloadSettings(postbox: postbox)) |> take(1) |> mapToSignal { data, settings -> Signal< (String, String)?, NoError> in
        if data.complete {
            return .single((data.path, "\(settings.downloadFolder)/\(savedFileName(file, cachePath: data.path))"))
        } else {
            return .single(nil)
        }
    }
}

private func savedFileName(_ file: TelegramMediaFile, cachePath: String) -> String {
    let fileName = (file.fileName ?? cachePath.nsstring.lastPathComponent).fixedFileName
    var ext = fileName.nsstring.pathExtension
    if ext.isEmpty {
        ext = fileExt(file.mimeType) ?? ""
    }
    if !ext.isEmpty {
        return "\(fileName.nsstring.deletingPathExtension).\(ext)"
    } else {
        return fileName.nsstring.deletingPathExtension
    }
}

private let previewFolderPath = NSTemporaryDirectory().nsstring.appendingPathComponent("Telegram Preview")
private let previewFolderLifetime: TimeInterval = 24 * 60 * 60

private let removeExpiredPreviewFiles: Void = {
    let fileManager = FileManager.default
    guard let contents = try? fileManager.contentsOfDirectory(atPath: previewFolderPath) else {
        return
    }
    let expiry = Date().addingTimeInterval(-previewFolderLifetime)
    for name in contents {
        let path = previewFolderPath.nsstring.appendingPathComponent(name)
        let created = (try? fileManager.attributesOfItem(atPath: path))?[.creationDate] as? Date
        if let created = created, created < expiry {
            try? fileManager.removeItem(atPath: path)
        }
    }
}()

private func copyToPreviewFolder(_ file: TelegramMediaFile, postbox: Postbox) -> Signal<String?, NoError> {
    return postbox.mediaBox.resourceData(file.resource) |> take(1) |> deliverOn(resourcesQueue) |> map { data in
        guard data.complete else {
            return nil
        }
        _ = removeExpiredPreviewFiles

        let fileManager = FileManager.default
        let fileName = savedFileName(file, cachePath: data.path)
        let baseName = "\(file.fileId.namespace)_\(file.fileId.id)"

        var index = 0
        while true {
            let directory = previewFolderPath.nsstring.appendingPathComponent(index == 0 ? baseName : "\(baseName)-\(index)")
            let path = directory.nsstring.appendingPathComponent(fileName)
            if fileSize(path) == data.size {
                return path
            }
            if !fileManager.fileExists(atPath: directory) {
                do {
                    try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)
                    try fileManager.copyItem(atPath: data.path, toPath: path)
                } catch {
                    return nil
                }
                return path
            }
            index += 1
        }
    }
}

private func validDownloadedPath(_ paths: DownloadedFilesPaths, file: TelegramMediaFile) -> String? {
    guard let id = file.id, let path = paths.path(for: id) else {
        return nil
    }
    let lastModified = Int32(FileManager.default.modificationDateForFileAtPath(path: path.downloadedPath)?.timeIntervalSince1970 ?? 0)
    if fileSize(path.downloadedPath) == Int64(path.size), lastModified == path.lastModified {
        return path.downloadedPath
    }
    return nil
}

public func quickLookFilePath(_ file: TelegramMediaFile, postbox: Postbox) -> Signal<String?, NoError> {
    return automaticDownloadSettings(postbox: postbox) |> take(1) |> mapToSignal { settings -> Signal<String?, NoError> in
        if settings.saveFilesToDownloadFolder {
            return copyToDownloads(file, postbox: postbox)
        }
        return downloadedFilePaths(postbox) |> deliverOn(resourcesQueue) |> mapToSignal { paths -> Signal<String?, NoError> in
            if let path = validDownloadedPath(paths, file: file) {
                return .single(path)
            }
            return copyToPreviewFolder(file, postbox: postbox)
        }
    }
}

public func fileNeedsManualSave(_ file: TelegramMediaFile, postbox: Postbox) -> Signal<Bool, NoError> {
    let paths = postbox.preferencesView(keys: [ApplicationSpecificPreferencesKeys.downloadedPaths]) |> map { view -> DownloadedFilesPaths in
        return view.values[ApplicationSpecificPreferencesKeys.downloadedPaths]?.get(DownloadedFilesPaths.self) ?? DownloadedFilesPaths.defaultValue
    }
    return combineLatest(queue: resourcesQueue, automaticDownloadSettings(postbox: postbox), paths) |> map { settings, paths -> Bool in
        if settings.saveFilesToDownloadFolder {
            return false
        }
        return validDownloadedPath(paths, file: file) == nil
    } |> distinctUntilChanged
}

public func fileFinderPath(_ file: TelegramMediaFile, _ postbox: Postbox) -> Signal<String?, NoError> {
    return combineLatest(downloadFilePath(file, postbox), downloadedFilePaths(postbox)) |> map { (expanded, paths) in
        guard let (_, adopted) = expanded else {
            return nil
        }
        if let id = file.id {
            do {
                
                if let path = paths.path(for: id) {
                    let lastModified = Int32(FileManager.default.modificationDateForFileAtPath(path: path.downloadedPath)?.timeIntervalSince1970 ?? 0)
                    if fileSize(path.downloadedPath) == Int64(path.size), lastModified == path.lastModified {
                       return path.downloadedPath
                    }
                }
                
                return adopted
            }
        } else {
            return nil
        }
    }
}
