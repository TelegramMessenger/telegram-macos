import Foundation
import Cocoa
import TelegramCore
import Postbox
import SwiftSignalKit
import TGUIKit
import InAppSettings
import TelegramTheme

public func copyToDownloads(_ file: TelegramMediaFile, postbox: Postbox, saveAnyway: Bool = false) -> Signal<String?, NoError> {
    return combineLatest(queue: resourcesQueue, downloadFilePath(file, postbox), downloadedFilePaths(postbox)) |> take(1) |> mapToSignal { expanded, paths -> Signal<String?, NoError> in
        guard let (boxPath, destination) = expanded else {
            return .single(nil)
        }
        if !saveAnyway, let path = paths.path(for: file.fileId), let existing = DownloadedFileStorage.existingPath(path.downloadedPath, size: path.size, lastModified: path.lastModified, in: destination.nsstring.deletingLastPathComponent) {
            return .single(existing)
        }
        guard let adopted = try? DownloadedFileStorage.copy(from: boxPath, to: destination) else {
            return .single(nil)
        }
        let lastModified = FileManager.default.modificationDateForFileAtPath(path: adopted)?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
        let size = fileSize(adopted) ?? file.size ?? 0
        let path = DownloadedPath(id: file.fileId, downloadedPath: adopted, size: Int64(size), lastModified: Int32(lastModified))
        return Signal { subscriber in
            return updateDownloadedFilePaths(postbox, {
                $0.withAddedPath(path)
            }).start(completed: {
                subscriber.putNext(adopted)
                subscriber.putCompletion()
            })
        }
    }
}

public func downloadFilePath(_ file: TelegramMediaFile, _ postbox: Postbox) -> Signal<(String, String)?, NoError> {
    return combineLatest(postbox.mediaBox.resourceData(file.resource), automaticDownloadSettings(postbox: postbox)) |> take(1) |> map { data, settings -> (String, String)? in
        guard data.complete else {
            return nil
        }
        let fileName = (file.fileName ?? data.path.nsstring.lastPathComponent).fixedFileName
        guard !fileName.isEmpty, !fileName.contains("\0") else {
            return nil
        }
        var ext = fileName.nsstring.pathExtension
        if ext.isEmpty {
            ext = fileExt(file.mimeType) ?? ""
        }
        let name = fileName.nsstring.deletingPathExtension + (ext.isEmpty ? "" : "." + ext)
        let directory = settings.usesTemporaryDownloadFolder ? DownloadedFileStorage.temporaryDirectory(mediaBoxPath: postbox.mediaBox.basePath) : settings.downloadFolder
        return (data.path, URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(name).path)
    }
}

public func fileFinderPath(_ file: TelegramMediaFile, _ postbox: Postbox) -> Signal<String?, NoError> {
    return combineLatest(downloadFilePath(file, postbox), downloadedFilePaths(postbox)) |> map { expanded, paths in
        guard let (_, destination) = expanded else {
            return nil
        }
        if let path = paths.path(for: file.fileId), let existing = DownloadedFileStorage.existingPath(path.downloadedPath, size: path.size, lastModified: path.lastModified, in: destination.nsstring.deletingLastPathComponent) {
            return existing
        }
        return destination
    }
}
