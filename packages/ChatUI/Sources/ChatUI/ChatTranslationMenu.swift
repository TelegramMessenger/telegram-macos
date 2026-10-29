import TGUIKit
import TelegramCore
import Translate
import Localization
import TelegramTheme
import LocalAnimations

func chatTranslationMenuItem(chatInteraction: ChatInteraction) -> ContextMenuItem? {
    guard chatInteraction.presentation.peer?.restrictionText(chatInteraction.presentation.contentSettings) == nil,
          let translate = chatInteraction.presentation.translateState, translate.canTranslate else {
        return nil
    }
    let item = ContextMenuItem(strings().voiceOverCommonTranslate, state: translate.translate ? .on : nil, itemImage: MenuAnimation.menu_translate.value)
    let menu = chatTranslationSettingsMenu(chatInteraction: chatInteraction, translate: translate)
    let title: String
    if translate.translate {
        title = strings().chatTranslateShowOriginal
    } else if let language = Translate.find(translate.to) {
        title = strings().chatTranslateTo(_NSLocalizedString(language.localizationKey))
    } else {
        title = strings().voiceOverCommonTranslate
    }
    let toggle = ContextMenuItem(title, handler: { [weak chatInteraction] in
        chatInteraction?.toggleTranslate()
    }, itemImage: MenuAnimation.menu_translate.value)
    menu.items.insert(contentsOf: [toggle, ContextSeparatorItem()], at: 0)
    item.submenu = menu
    return item
}

func chatTranslationSettingsMenu(chatInteraction: ChatInteraction, translate: ChatPresentationInterfaceState.TranslateState) -> ContextMenu {
    let menu = ContextMenu(betterInside: true)
    var items: [ContextMenuItem] = []

    if translate.paywall {
        items.append(ContextMenuItem(strings().chatTranslateMenuHide, handler: { [weak chatInteraction] in
            chatInteraction?.hideTranslation()
        }, itemImage: MenuAnimation.menu_clear_history.value))

        menu.items = items
        return menu
    }

    let other = ContextMenuItem(strings().chatTranslateMenuTo, itemImage: MenuAnimation.menu_translate.value)

    var codes = Translate.codes.sorted(by: { lhs, rhs in
        let lhsSelected = lhs.code.contains(translate.to)
        let rhsSelected = rhs.code.contains(translate.to)
        if lhsSelected && !rhsSelected {
            return true
        } else if !lhsSelected && rhsSelected {
            return false
        } else {
            return lhs.language < rhs.language
        }
    })

    let languageCode = Translate.normalizeLanguageCode(appAppearance.languageCode)
    let codeIndex = codes.firstIndex(where: {
        $0.code.contains(languageCode)
    })
    if let codeIndex = codeIndex {
        codes.move(at: codeIndex, to: 0)
    }

    let submenu = ContextMenu(betterInside: true)

    for code in codes {
        submenu.addItem(ContextMenuItem(code.language, handler: { [weak chatInteraction] in
            if let first = code.code.first {
                chatInteraction?.translateTo(first)
            }
        }, itemImage: code.code.contains(translate.to) ? MenuAnimation.menu_check_selected.value : nil))
    }
    other.submenu = submenu

    items.append(other)

    let toneItem = ContextMenuItem(strings().chatHeaderTone, itemImage: MenuAnimation.menu_tune_fork.value)
    let toneSubmenu = ContextMenu()
    let toneNames: [(TranslationTone, String)] = [
        (.formal, strings().chatHeaderToneFormal),
        (.neutral, strings().chatHeaderToneNeutral),
        (.casual, strings().chatHeaderToneCasual)
    ]
    for (tone, name) in toneNames {
        toneSubmenu.addItem(ContextMenuItem(name, handler: { [weak chatInteraction] in
            chatInteraction?.setTranslateTone(tone)
        }, state: translate.tone == tone ? .on : nil))
    }
    toneItem.submenu = toneSubmenu
    items.append(toneItem)

    if let from = translate.from, let language = Translate.find(from) {
        items.append(ContextMenuItem(strings().chatTranslateMenuDoNotTranslate(_NSLocalizedString(language.localizationKey)), handler: { [weak chatInteraction] in
            chatInteraction?.doNotTranslate(from)
        }, itemImage: MenuAnimation.menu_restrict.value))
    }

    items.append(ContextMenuItem(strings().chatTranslateMenuHide, handler: { [weak chatInteraction] in
        chatInteraction?.hideTranslation()
    }, itemImage: MenuAnimation.menu_clear_history.value))

    items.append(ContextSeparatorItem())

    let item = ContextMenuItem(strings().chatTranslationPoweredByCocoon, handler: { [weak chatInteraction] in
        guard let context = chatInteraction?.interactionContext else { return }
        ChatUIHooks.shared.showAboutCocoonModal(context)
    }, itemImage: MenuAnimation.menu_cocoon.value, removeTail: false, overrideWidth: 200)

    items.append(item)

    menu.items = items

    return menu

}
