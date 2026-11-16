import Foundation
import TelegramCore
import ThemeSettings
import SwiftSignalKit

private let chatThemePreparationQueue = Queue(name: "ChatThemePreparation", qos: .userInitiated)

public func preparedChatThemes(presentation: Signal<TelegramPresentationTheme, NoError>, themes: Signal<[TelegramTheme], NoError>, cacheWallpaper: @escaping (Wallpaper) -> Signal<Wallpaper, NoError>) -> Signal<[(ChatTheme, TelegramPresentationTheme)], NoError> {
    return preparedChatThemes(presentation: presentation, themes: themes, cacheWallpaper: cacheWallpaper, queue: chatThemePreparationQueue)
}

func preparedChatThemes(presentation: Signal<TelegramPresentationTheme, NoError>, themes: Signal<[TelegramTheme], NoError>, cacheWallpaper: @escaping (Wallpaper) -> Signal<Wallpaper, NoError>, queue: Queue) -> Signal<[(ChatTheme, TelegramPresentationTheme)], NoError> {
    return combineLatest(queue: .mainQueue(), presentation |> distinctUntilChanged, themes |> distinctUntilChanged) |> mapToSignal { presentation, themes in
        return Signal<(TelegramPresentationTheme, [TelegramTheme]), NoError>.single((presentation, themes)) |> deliverOn(queue) |> mapToSignal { presentation, themes in
            var signals: [Signal<(ChatTheme, TelegramPresentationTheme), NoError>] = []
            for theme in themes {
                if let settings = theme.effectiveSettings(isDark: presentation.dark), let emoji = theme.emoticon {
                    let wallpaper: Signal<ThemeWallpaper, NoError>
                    if let value = settings.wallpaper?.uiWallpaper(nil) {
                        wallpaper = cacheWallpaper(value) |> map { ThemeWallpaper(wallpaper: $0, associated: nil) }
                    } else {
                        wallpaper = .single(presentation.wallpaper)
                    }
                    signals.append(wallpaper |> deliverOn(queue) |> map { wallpaper in
                        let result = presentation.withUpdatedColors(settings.palette).withUpdatedWallpaper(wallpaper)
                        return (.emoticon(emoji), result)
                    })
                }
            }
            return combineLatest(signals)
        } |> deliverOnMainQueue
    }
}
