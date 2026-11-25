import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import StoriesUI

func installStoriesUIHooks() {
    var hooks = StoriesHooks(navigateToChat: { navigation, context, chatLocation in
        navigateToChat(navigation: navigation, context: context as! AccountContext, chatLocation: chatLocation)
    }, pushPeerInfo: { navigation, context, peerId in
        PeerInfoController.push(navigation: navigation, context: context as! AccountContext, peerId: peerId)
    }, pushStoryMedia: { context, peerId, listContext, standalone, isArchived in
        StoryMediaController.push(context: context as! AccountContext, peerId: peerId, listContext: listContext, standalone: standalone, isArchived: isArchived)
    }, generateLiveStreamBadge: { fontSize, outerColor in
        return generateLiveStreamBadge(fontSize: fontSize, outerColor: outerColor)
    }, showListStory: { context, listContext, peerId, initialId in
        StoryModalController.ShowListStory(context: context as! AccountContext, listContext: listContext, peerId: peerId, initialId: initialId)
    }, makeStoryMonthRowItem: { initialSize, stableId, context, standalone, peerId, peerReference, items, selected, pinnedIds, rowCount, viewType, openStory, toggleSelected, menuItems, presentation in
        return StoryMonthRowItem(initialSize, stableId: stableId, context: context as! AccountContext, standalone: standalone, peerId: peerId, peerReference: peerReference, items: items, selected: selected, pinnedIds: pinnedIds, rowCount: rowCount, viewType: viewType, openStory: openStory, toggleSelected: toggleSelected, menuItems: menuItems, presentation: presentation)
    }, executeInApp: { link in
        switch link {
        case let .external(link, confirm):
            execute(inapp: .external(link: link, confirm))
        }
    }, showShareLink: { context, link, window in
        showModal(with: ShareModalController(ShareLinkObject(context, link: link)), for: window)
    }, generateTheme: { palette, cloudTheme, bubbled, fontSize, wallpaper in
        return generateTheme(palette: palette, cloudTheme: cloudTheme, bubbled: bubbled, fontSize: fontSize, wallpaper: wallpaper)
    }, pushPeerInfoIfNeeded: { context, peerId in
        let controller = context.bindings.rootNavigation().controller as? PeerInfoController

        if controller?.peerId != peerId {
            PeerInfoController.push(navigation: context.bindings.rootNavigation(), context: context as! AccountContext, peerId: peerId)
        }
    }, showShareStory: { context, media, hasLink, storyId, repostAction, presentation in
        let additionTopItems: ShareAdditionItems = .init(items: [.init(peer: TelegramStoryRepostPeerObject(), status: strings().storyRepostToMy)], topSeparator: "", bottomSeparator: "", selectable: false)

        showModal(with: ShareModalController(ShareStoryObject(context, media: media, hasLink: hasLink, storyId: storyId, additionTopItems: additionTopItems, repostAction: {
            repostAction()
        }), presentation: presentation), for: context.window)
    }, findShareModal: { controller in
        return findModal(ShareModalController.self, isAboveTo: controller)
    }, makeInAppLink: { url, context, openInfo in
        return inApp(for: url, context: context as? AccountContext, openInfo: openInfo)
    }, executeInAppLink: { link, afterComplete in
        execute(inapp: link as! inAppLink, afterComplete: afterComplete)
    }, makeSliderContextMenuItem: { volume, minValue, maxValue, midValue, drawable, drawable_muted, didUpdateValue in
        return SliderContextMenuItem(volume: volume, minValue: minValue, maxValue: maxValue, midValue: midValue, drawable: drawable, drawable_muted: drawable_muted, didUpdateValue)
    }, storiesBlockedPeersContext: { context in
        return (context as! AccountContext).storiesBlockedPeersContext
    })
    hooks.showListStoryWithContext = { context, listContext, peerId, initialId, analyticsContext in
        StoryModalController.ShowListStory(context: context as! AccountContext, listContext: listContext, peerId: peerId, initialId: initialId, analyticsContext: analyticsContext)
    }
    StoriesHooks.install(hooks)
}
