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

public func saveAs(_ file:TelegramMediaFile, account:Account) {
    
    let name = account.postbox.mediaBox.resourceData(file.resource) |> mapToSignal { data -> Signal< (String, String), NoError> in
        if data.complete {
            var ext:String = ""
            let fileName = file.fileName ?? data.path.nsstring.lastPathComponent
            if let ext = file.fileName?.nsstring.pathExtension {
                return .single((data.path, ext))
            }
            ext = fileName.nsstring.pathExtension
            return resourceType(mimeType: file.mimeType) |> mapToSignal { _type -> Signal<(String, String), NoError> in
                let ext = _type == "*" || _type == nil ? (ext.length == 0 ? "file" : ext) : _type!
                
                return .single((data.path, ext))
            }
        } else {
            return .complete()
        }
    } |> deliverOnMainQueue
    
    _ = name.start(next: { path, ext in
        savePanel(file: path, ext: ext, for: mainWindow, defaultName: file.fileName)
    })
}

public func showInFinder(_ file: TelegramMediaFile, account: Account) {
    _ = (copyToDownloads(file, postbox: account.postbox) |> deliverOnMainQueue).start(next: { path in
        if let path = path {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
    })
}
