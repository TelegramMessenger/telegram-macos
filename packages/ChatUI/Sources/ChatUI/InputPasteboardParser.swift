import Cocoa
import TelegramCore

import SwiftSignalKit
import Postbox
import TGUIKit
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMedia
import TelegramMediaUtils
import TelegramMediaResources
import InAppSettings
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils
import ChatHistoryModel
import AlertsUI
import PremiumUI

public class InputPasteboardParser: NSObject {

    
    public class func getPasteboardUrls(_ pasteboard: NSPasteboard, context: any AccountContextProtocol) -> Signal<[URL], NoError> {
        let items = pasteboard.pasteboardItems
        
        if let items = items, !items.isEmpty {
            var files:[URL] = []
            
            for item in items {
                let path = item.string(forType: NSPasteboard.PasteboardType(rawValue: "public.file-url"))
                if let path = path, let url = URL(string: path) {
                    files.append(url)
                }
            }
            
            var image:NSImage? = nil
            
            if files.isEmpty {
                if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage], !images.isEmpty {
                    image = images[0]
                }
            }
            
            
            files = files.filter { path -> Bool in
                if let size = fileSize(path.path) {
                    let exceed = fileSizeLimitExceed(context: context, fileSize: size)
                    return exceed
                }
                return false
            }
            
            
            if !files.isEmpty {
                return .single(files)
            } else if let image = image {
                return putToTemp(image: image, compress: false) |> map {[URL(fileURLWithPath: $0)]} |> deliverOnMainQueue
            }
            
        }
        
        return .single([])
    }
    
    public class func canProccessPasteboard(_ pasteboard:NSPasteboard, context: any AccountContextProtocol) -> Bool {
        let items = pasteboard.pasteboardItems
        
        if let items = items, !items.isEmpty {
            var files:[URL] = []
            
            for item in items {
                let path = item.string(forType: NSPasteboard.PasteboardType(rawValue: "public.file-url"))
                if let path = path, let url = URL(string: path) {
                    files.append(url)
                }
                
            }
            
            var image:NSImage? = nil
            
            if files.isEmpty {
                if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage], !images.isEmpty {
                    image = images[0]
                }
            }
            
            
            if let _ = items[0].types.firstIndex(of: NSPasteboard.PasteboardType(rawValue: "com.apple.traditional-mac-plain-text")) {
                return true
            }
            
            let previous = files.count
            
            files = files.filter { path -> Bool in
                if let size = fileSize(path.path) {
                    let exceed = fileSizeLimitExceed(context: context, fileSize: size)
                    return exceed
                }
                return false
            }
            
            let afterSizeCheck = files.count
            
            if afterSizeCheck == 0 && previous != afterSizeCheck {
                return false
            }
            
            if !files.isEmpty {
                
                return false
            } else if let _ = image {
                return false
            }
            
        }
        
        return true
    }
    
    public class func proccess(pasteboard:NSPasteboard, chatInteraction:ChatInteraction, window:Window) -> Bool {
        let analyticsContext = chatInteraction.captureAnalyticsContext()
        let analyticsPresentation = analyticsContext.beginPresentation()
        defer { analyticsPresentation.end() }
        let items = pasteboard.pasteboardItems
        
        
        if let items = items, !items.isEmpty {
            var files:[URL] = []
            
            for item in items {
                let path = item.string(forType: NSPasteboard.PasteboardType(rawValue: "public.file-url"))
                if let path = path, let url = URL(string: path) {
                    files.append(url)
                }
            }
            
            var image:NSImage? = nil
            
            if files.isEmpty {
                                                
                if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage], !images.isEmpty {
                    
                    if let representation = images[0].representations.first as? NSPDFImageRep {
                        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "ios_scan_\(arc4random()).pdf")
                        
                        try? representation.pdfRepresentation.write(to: url)
                        
                        files.append(url)
                        image = nil
                    } else {
                        image = images[0]
                    }
                }
            }
            
            if let _ = items[0].types.firstIndex(of: NSPasteboard.PasteboardType(rawValue: "com.microsoft.appbundleid")) {
                return true
            }
            
            let previous = files.count
            var exceedSize: Int64?
            var rejectedForSize = false
            let isMediaReplacement = chatInteraction.presentation.interfaceState.editState?.canEditMedia == true && (files.count == 1 || image != nil)
            let journey = previous > 0 || image != nil ? chatInteraction.makeMediaAnalyticsJourney(context: analyticsContext, entry: .clipboard, mode: .media) : nil

            
            
            files = files.filter { path -> Bool in
                if let size = fileSize(path.path) {
                    let exceed = fileSizeLimitExceed(context: chatInteraction.interactionContext, fileSize: size)
                    if !exceed { rejectedForSize = true }
                    if exceed {
                        exceedSize = size
                    }
                    return exceed
                }
                return false
            }
            
            let afterSizeCheck = files.count
            
            if afterSizeCheck == 0 && previous != afterSizeCheck {
                if isMediaReplacement {
                    chatInteraction.rejectMediaReplacement(entry: .clipboard, mode: .media, context: analyticsContext, reason: rejectedForSize ? .sizeLimit : .fileUnavailable)
                }
                journey?.fail(rejectedForSize ? .sizeLimit : .fileUnavailable)
                showFileLimit(context: chatInteraction.interactionContext, fileSize: exceedSize)
                return false
            }
            if afterSizeCheck < previous {
                journey?.blocked(rejectedForSize ? .sizeLimit : .fileUnavailable)
            }
            if let peer = chatInteraction.presentation.peer, let permissionText = permissionText(from: peer, for: .banSendMedia) {
                if !files.isEmpty || image != nil {
                    if isMediaReplacement {
                        chatInteraction.rejectMediaReplacement(entry: .clipboard, mode: .media, context: analyticsContext, reason: .permission)
                    }
                    journey?.fail(.permission)
                    alert(for: mainWindow, info: permissionText)
                    return false
                }
            }
            
            if files.count == 1, let editState = chatInteraction.presentation.interfaceState.editState, editState.canEditMedia {
                let replacement = chatInteraction.beginMediaReplacement(entry: .clipboard, mode: .media, context: analyticsContext)
                _ = analyticsContext.preservingPresentation(Sender.generateMedia(for: MediaSenderContainer(path: files[0].path, isFile: false), account: chatInteraction.interactionContext.account, isSecretRelated: chatInteraction.peerId.namespace == Namespaces.Peer.SecretChat) |> deliverOnMainQueue).start(next: { [weak chatInteraction] media, _ in
                    chatInteraction?.applyMediaReplacement(media, request: replacement)
                })
                return false
            } else if let image = image, let editState = chatInteraction.presentation.interfaceState.editState, editState.canEditMedia {
                let replacement = chatInteraction.beginMediaReplacement(entry: .clipboard, mode: .media, context: analyticsContext)
                _ = analyticsContext.preservingPresentation(putToTemp(image: image) |> mapToSignal {Sender.generateMedia(for: MediaSenderContainer(path: $0, isFile: false), account: chatInteraction.interactionContext.account, isSecretRelated: chatInteraction.peerId.namespace == Namespaces.Peer.SecretChat) } |> deliverOnMainQueue).start(next: { [weak chatInteraction] media, _ in
                    chatInteraction?.applyMediaReplacement(media, request: replacement)
                })
                return false
            }
            
            if !files.isEmpty {
                chatInteraction.showPreviewSender(files, true, nil, analyticsContext: analyticsContext, journey: journey)
                return false
            } else if let image = image {
                journey?.preparing()
                _ = (putToTemp(image: image, compress: false) |> deliverOnMainQueue).start(next: { [weak chatInteraction] (path) in
                    chatInteraction?.showPreviewSender([URL(fileURLWithPath: path)], true, nil, analyticsContext: analyticsContext, journey: journey)
                })
                return false
            }
   
        }
        
        
        return true
    }
    
}

