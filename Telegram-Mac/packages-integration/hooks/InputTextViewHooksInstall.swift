import Cocoa
import TGUIKit

func installInputTextViewHooks() {
    var hooks = InputTextViewHooks(checkSendingAbility: { event in
        return FastSettings.checkSendingAbility(for: event)
    }, showDateSelector: { context, window, defaultDate, selected in
        guard let context = context as? AccountContext else {
            return
        }
        showModal(with: DateSelectorModalController(context: context, defaultDate: defaultDate, mode: .date(title: strings().editPostSuggestionDateTitle, doneTitle: strings().modalDone), selectedAt: { date, _ in
            selected(date)
        }), for: window)
    }, showPremiumBoarding: { context, window in
        guard let context = context as? AccountContext else {
            return
        }
        prem(with: PremiumBoardingController(context: context, source: .translations, openFeatures: true), for: window)
    }, showTranslate: { context, window, from, text, entities, onUse in
        guard let context = context as? AccountContext else {
            return
        }
        showModal(with: TranslateModalController(context: context, from: from, toLang: appAppearance.languageCode, text: text, entities: entities, onUse: { translated in
            onUse(translated)
        }), for: window)
    }, showURLFormatter: { window, string, defaultUrl, hosts, completion in
        showModal(with: InputURLFormatterModalController(string: string, defaultUrl: defaultUrl, completion: completion, hosts: hosts), for: window)
    }, makeInlineAvatarLayer: { context, frame, peer in
        return InlineAvatarLayer(context: context, frame: frame, peer: peer)
    })
    hooks.showTranslateWithContext = { context, window, from, text, entities, onUse in
        guard let context = context as? AccountContext else { return }
        showModal(with: TranslateModalController(context: context, from: from, toLang: appAppearance.languageCode, text: text, entities: entities, onUse: onUse), for: window)
    }
    hooks.showPremiumBoardingWithContext = { context, window in
        guard let context = context as? AccountContext else { return }
        FeatureNavigationHooks.shared.showPremiumBoardingObserved(context, window, .translations, true, nil)
    }
    InputTextViewHooks.install(hooks)
}

extension InlineAvatarLayer: @retroactive InputInlineAvatarLayer {
}
