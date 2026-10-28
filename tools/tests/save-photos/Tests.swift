import Cocoa
import SwiftSignalKit

var checks = 0
var failures = 0
func expect(_ condition: @autoclosure () throws -> Bool, _ name: String) {
    checks += 1
    do {
        if try !condition() { failures += 1; print("FAIL: \(name)") }
    } catch {
        failures += 1
        print("FAIL: \(name): \(error)")
    }
}
func wait(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(3)
    while !condition() && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    expect(condition(), "asynchronous operation completes")
}
let manager = FileManager.default
let root = manager.temporaryDirectory.appendingPathComponent("photo-save-checks-\(UUID().uuidString)")
try manager.createDirectory(at: root, withIntermediateDirectories: false)
defer { try? manager.removeItem(at: root) }
func directory(_ name: String) throws -> URL {
    let url = root.appendingPathComponent(name)
    try manager.createDirectory(at: url, withIntermediateDirectories: false)
    return url
}
let sources = try directory("sources")
let first = sources.appendingPathComponent("first.jpg")
let second = sources.appendingPathComponent("second.jpg")
try Data("first full image".utf8).write(to: first)
try Data("second full image".utf8).write(to: second)
let files = [ChatPhotoBatchWriter.File(source: first, name: "photo.jpg"), ChatPhotoBatchWriter.File(source: second, name: "photo.jpg")]
let output = try directory("collisions")
try Data("existing user file".utf8).write(to: output.appendingPathComponent("photo.jpg"))
let saved = try ChatPhotoBatchWriter.copy(files, to: output)
expect(saved.map(\.lastPathComponent) == ["photo (1).jpg", "photo (2).jpg"], "batch and existing filename collisions receive suffixes")
expect(try Data(contentsOf: output.appendingPathComponent("photo.jpg")) == Data("existing user file".utf8), "existing file is unchanged")
expect(try Data(contentsOf: saved[0]) == Data(contentsOf: first), "first photo retains exact original bytes")
expect(try Data(contentsOf: saved[1]) == Data(contentsOf: second), "second photo retains exact original bytes")
expect(try manager.contentsOfDirectory(atPath: output.path).count == 3, "staging directory is removed after success")
let failed = try directory("failed")
do {
    _ = try ChatPhotoBatchWriter.copy([files[0], .init(source: sources.appendingPathComponent("missing"), name: "other.jpg")], to: failed)
    expect(false, "missing source must fail")
} catch {
    expect(try manager.contentsOfDirectory(atPath: failed.path).isEmpty, "failed preparation leaves no partial output")
}
for cancelAt in [1, 2, 4] {
    let cancelled = try directory("cancelled-\(cancelAt)")
    var calls = 0
    do {
        _ = try ChatPhotoBatchWriter.copy(files, to: cancelled, cancelled: { calls += 1; return calls >= cancelAt })
        expect(false, "cancelled copy must stop")
    } catch {
        expect(try manager.contentsOfDirectory(atPath: cancelled.path).isEmpty, "cancellation removes staging and any newly published files")
    }
}
let invalid = try directory("invalid")
do {
    _ = try ChatPhotoBatchWriter.copy([.init(source: first, name: "../outside.jpg")], to: invalid)
    expect(false, "path traversal must fail")
} catch {
    expect(!manager.fileExists(atPath: root.appendingPathComponent("outside.jpg").path), "export cannot escape selected directory")
    expect(try manager.contentsOfDirectory(atPath: invalid.path).isEmpty, "invalid name leaves no staging files")
}
let small = Resource(id: 1, path: first.path)
let large = Resource(id: 2, path: second.path, local: false)
let image = TelegramMediaImage(representations: [.init(dimensions: PixelDimensions(width: 100, height: 100), resource: small), .init(dimensions: PixelDimensions(width: 4000, height: 3000), resource: large)])
let photo = Message(id: MessageId(id: 10), media: [image])
var later = photo
later = Message(id: MessageId(id: 11), timestamp: 2, media: [image])
var protected = photo
protected.protected = true
var secret = photo
secret.containsSecretMedia = true
var ad = photo
ad.adAttribute = 1
expect(ChatPhotoSaveAction.items(from: [protected, secret, ad], cachedData: nil).isEmpty, "protected, secret and advertising photos are excluded")
expect(ChatPhotoSaveAction.items(from: [photo], cachedData: CachedPeerData(protected: true)).isEmpty, "cached private-chat copy protection is respected")
let items = ChatPhotoSaveAction.items(from: [later, photo, photo], cachedData: nil)
expect(items.map { $0.message.id.id } == [10, 11], "photos are ordered and deduplicated")
expect(items.allSatisfy { $0.representation.resource.id == 2 }, "export uses largest representation instead of cached thumbnail")
expect(ChatPhotoSaveAction.items(from: [Message(id: MessageId(id: 12), media: [])], cachedData: nil).isEmpty, "text-only selection entries are ignored")
let menuEvent = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
func menuDispatches(messages: [Message], state: ChatState, selected: Set<MessageId>) -> Int {
    let interaction = ChatInteraction()
    interaction.presentation.state = state
    interaction.presentation.selectionState = SelectionState(selectedIds: selected)
    let view = ChatRowView()
    view.item = ChatRowItem(messages, interaction)
    view.rightMouseDown(with: menuEvent)
    return view.menuDispatches
}
expect(menuDispatches(messages: [photo], state: .normal, selected: []) == 1, "ordinary photo right click still opens the menu")
expect(menuDispatches(messages: [photo, later], state: .selecting, selected: [photo.id, later.id]) == 1, "selected album right click reaches the batch photo menu")
expect(menuDispatches(messages: [photo], state: .selecting, selected: [photo.id, later.id]) == 1, "selected standalone photo right click reaches the batch menu")
expect(menuDispatches(messages: [photo], state: .selecting, selected: [photo.id]) == 0, "single selection preserves existing context menu suppression")
expect(menuDispatches(messages: [photo], state: .selecting, selected: [later.id, MessageId(id: 50)]) == 0, "right clicking an unselected photo cannot export an unrelated selection")
let textOnly = Message(id: MessageId(id: 12), media: [])
expect(menuDispatches(messages: [textOnly], state: .selecting, selected: [textOnly.id, later.id]) == 0, "selected text keeps existing context menu behavior")
struct PhotoMenuData { let groupped: [Message]? }
func menuPhotoMessages(selectedMessages: [Message], grouped: [Message]?, useGroupIfNeeded: Bool) -> [Message] {
    let data = PhotoMenuData(groupped: grouped)
    __PHOTO_MESSAGES__
    return photoMessages
}
expect(menuPhotoMessages(selectedMessages: [], grouped: [photo, later], useGroupIfNeeded: false).map { $0.id.id } == [10, 11], "right-clicking an individual album tile retains Save All Photos candidates")
expect(menuPhotoMessages(selectedMessages: [], grouped: [photo, later], useGroupIfNeeded: true).count == 2, "album caption menu includes all photos")
expect(menuPhotoMessages(selectedMessages: [later], grouped: [photo, later], useGroupIfNeeded: false).map { $0.id.id } == [11], "explicit selection takes precedence over album")
expect(menuPhotoMessages(selectedMessages: [], grouped: nil, useGroupIfNeeded: false).isEmpty, "single non-album message has no batch candidates")
func interaction(_ output: URL?) -> ChatInteraction {
    let interaction = ChatInteraction()
    let window = interaction.interactionContext.window
    window.directory = output?.path
    FilePanelsHooks.shared = FilePanelsHooks { _ in window.successes += 1 }
    return interaction
}
let remoteOutput = try directory("remote")
let remote = interaction(remoteOutput)
ChatPhotoSaveAction.save([photo, later], chatInteraction: remote)
expect(remote.interactionContext.window.picks == 1, "folder is chosen once for entire batch")
expect(remote.interactionContext.account.postbox.mediaBox.requests == [2, 2], "only full photo resources are fetched")
expect(try manager.contentsOfDirectory(atPath: remoteOutput.path).isEmpty, "incomplete downloads never produce partial photo files")
remote.interactionContext.account.postbox.mediaBox.finish(large)
wait { remote.interactionContext.window.successes == 1 }
let exported = try manager.contentsOfDirectory(at: remoteOutput, includingPropertiesForKeys: nil)
expect(exported.count == 2, "all selected photos are exported")
expect(try exported.allSatisfy { try Data(contentsOf: $0) == Data(contentsOf: second) }, "saved files contain full quality bytes")
expect(remote.interactionContext.window.errors == 0, "successful batch shows no error")
let cancelledPicker = interaction(nil)
ChatPhotoSaveAction.save([photo, later], chatInteraction: cancelledPicker)
expect(cancelledPicker.interactionContext.account.postbox.mediaBox.requests.isEmpty, "cancelling folder picker starts no download")
let cancelledOutput = try directory("cancel-download")
let cancelledDownload = interaction(cancelledOutput)
ChatPhotoSaveAction.save([photo, later], chatInteraction: cancelledDownload)
cancelledDownload.interactionContext.window.operation?.dispose()
cancelledDownload.interactionContext.account.postbox.mediaBox.finish(large)
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
expect(try manager.contentsOfDirectory(atPath: cancelledOutput.path).isEmpty, "cancelling downloads prevents export")
expect(cancelledDownload.interactionContext.account.postbox.mediaBox.disposed.count == 2, "cancellation releases all batch fetches")
let changedOutput = try directory("new-protection")
let changed = interaction(changedOutput)
changed.interactionContext.account.postbox.current.messages[photo.id] = protected
ChatPhotoSaveAction.save([photo], chatInteraction: changed)
wait { changed.interactionContext.window.errors == 1 }
expect(changed.interactionContext.account.postbox.mediaBox.requests.isEmpty, "protection is checked again before downloading")
let failOutput = try directory("download-error")
let fail = interaction(failOutput)
let failedImage = TelegramMediaImage(representations: [.init(dimensions: PixelDimensions(width: 4000, height: 3000), resource: Resource(id: 3, path: first.path, local: false, fails: true))])
ChatPhotoSaveAction.save([Message(id: MessageId(id: 13), media: [failedImage])], chatInteraction: fail)
wait { fail.interactionContext.window.errors == 1 }
expect(try manager.contentsOfDirectory(atPath: failOutput.path).isEmpty, "download failure leaves target folder unchanged")
expect(fail.interactionContext.window.successes == 0, "failed batch never announces success")
print("\(checks - failures)/\(checks) photo save checks passed")
exit(failures == 0 ? 0 : 1)
