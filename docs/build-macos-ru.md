# Сборка ветки с фильтрами фокусирования на Mac

Ветка: `feature/macos-focus-chat-filters` в `zkelo/telegram-macos`.
Ниже описана сборка полного приложения с расширением `FocusIntents` для собственного
запуска. Проверка одного расширения не заменяет сборку приложения.

## 1. Установить Xcode

Нужен полный Xcode 16 или новее, а не только Command Line Tools. В основной
[инструкции](../INSTALL.md) рабочей версией команды указан Xcode 26. Для Xcode 27
есть отдельный шаг подготовки ниже. Для фильтров фокусирования нужна macOS 13 или новее.

Установите Xcode в `/Applications/Xcode.app`, откройте его и завершите первоначальную
настройку. Затем в Терминале:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

Если Xcode установлен под другим именем, используйте его путь вместо
`/Applications/Xcode.app` во всех командах этой инструкции.

## 2. Получить исходники и подготовить инструменты

Выполните в папке, где хотите хранить исходники:

```sh
git clone --branch feature/macos-focus-chat-filters --recurse-submodules \
  https://github.com/zkelo/telegram-macos.git
cd telegram-macos
```

Для уже существующей копии этой ветки с сохранёнными локальными изменениями сначала
завершите или сохраните свою работу, затем обновите её:

```sh
git switch feature/macos-focus-chat-filters
git pull --ff-only
git submodule update --init --recursive
```

Если Rust ещё не установлен, установите rustup и добавьте его в текущий сеанс:

```sh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
. "$HOME/.cargo/env"
```

Подготовьте остальные инструменты:

```sh
sh scripts/setup_build_env.sh
```

Этот сценарий устанавливает Homebrew и инструменты сборки, при необходимости Rosetta 2
на Apple Silicon, получает вложенные подмодули и применяет необходимую правку
совместимости abseil с Clang. Rust устанавливается отдельно командой выше. Если
Homebrew установлен впервые, выполните предложенную установщиком команду `brew shellenv`
и в своём Терминале, чтобы следующие команды находили инструменты Homebrew.

OpenSSL отдельно через Homebrew не устанавливается: его собирает сам проект из
исходников. Не заменяйте его на другую основную версию OpenSSL.

Первичная подготовка требует интернета: помимо подмодулей загружаются исходники
OpenSSL, закреплённые версии Rust и зависимости Cargo.

## 3. Подготовить совместимость с Xcode 27

Этот шаг нужен только при использовании Xcode 27:

```sh
sh scripts/xcode27.sh apply
xcodebuild -showComponent MetalToolchain
```

Если последняя команда не показывает установленный компонент Metal, установите его:

```sh
xcodebuild -downloadComponent MetalToolchain
```

Сценарий обрабатывает приложение, расширения и проекты библиотек, включая
`MTProtoEngine`. Вручную редактировать файлы проектов для этой подготовки не нужно.
Подготовка сохраняет локальные изменения для совместимости с Xcode 27. Перед их
отправкой в репозиторий выполните `sh scripts/xcode27.sh revert`: он отменяет изменения
совместимости, сохраняя остальные правки.

## 4. Собрать библиотеки и подготовить создаваемые исходники

Из корня репозитория:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CMAKE_POLICY_VERSION_MINIMUM=3.5 \
sh scripts/configure_frameworks.sh
```

Это длительная часть первой сборки, особенно WebRTC. Дождитесь успешного завершения
перед первым открытием рабочего пространства в Xcode. Сценарий создаёт TelegramApi,
FlatSerialization, нативные библиотеки, общие заголовки и библиотеки Rust. Повторный
запуск проверяет отпечатки входных данных и полноту результатов, затем использует
готовые библиотеки или пересобирает необходимые.

## 5. Настроить свою подпись и доступ к Telegram

Для запуска приложения и фильтров фокусирования нужны собственная подпись и общая
группа приложения с расширениями. Простое отключение подписи позволяет проверять
компиляцию, но не обеспечивает доступ к общей группе: приложение не завершит
инициализацию, если не сможет получить её каталог.

Получите свои `api_id` и `api_hash` в разделе **API development tools** на
[my.telegram.org](https://my.telegram.org). Порядок описан в
[документации Telegram](https://core.telegram.org/api/obtaining_api_id).

Откройте рабочее пространство:

```sh
open Telegram-Mac.xcworkspace
```

В настройках Xcode добавьте свой Apple Account. Для целей `Telegram`, `TelegramShare`
и `FocusIntents` в **Signing & Capabilities** выберите одну свою команду разработчика
и автоматическое управление подписью. Узнайте её Team ID; ниже он обозначен `TEAM_ID`,
его нужно заменить своим значением, а не вводить буквально.

Например, используйте собственный основной идентификатор `ru.zkelo.TelegramFocus`:

| Цель | Bundle Identifier |
| --- | --- |
| Telegram | `ru.zkelo.TelegramFocus` |
| TelegramShare | `ru.zkelo.TelegramFocus.TelegramShare` |
| FocusIntents | `ru.zkelo.TelegramFocus.FocusIntents` |

В `packages/ApiCredentials/Sources/ApiCredentials/Config.swift` задайте свои
`apiId`, `apiHash`, `bundleId` и `teamId`. Основной `bundleId` должен совпадать с
идентификатором цели `Telegram`.

В следующих файлах замените `6N38VWS5BX` своим Team ID, а `ru.keepcoder.Telegram` —
своим основным идентификатором, сохранив существующие суффиксы:

- `Telegram-Mac/Telegram-Mac.entitlements`;
- `Telegram-Mac/Telegram-Sandbox.entitlements`;
- `TelegramShare/TelegramShare.entitlements`.

Для `FocusIntents` в **Build Settings** задайте `FOCUS_APP_GROUP` в обеих конфигурациях
Debug и Release. В этом примере значение — `TEAM_ID.ru.zkelo.TelegramFocus`.
Оно должно совпадать с основной общей группой приложения. Файл
`FocusIntents/FocusIntents.entitlements` уже использует `$(FOCUS_APP_GROUP)`.

В используемом `Telegram-Mac/Debug.xcconfig` очистите `SFEED_URL` и `DSA_PEM_FILE`,
чтобы собственная сборка не получала официальные обновления Telegram. Если используемая
конфигурация содержит `APPCENTER_SECRET`, замените или удалите его согласно
[инструкции для форка](../INSTALL.md#if-you-want-to-develop-a-fork).

На macOS Apple поддерживает общую группу вида `<Team ID>.<имя группы>` без отдельной
регистрации группы и профиля, но Team ID в подписи должен совпадать. См.
[документацию Apple](https://developer.apple.com/documentation/xcode/accessing-app-group-containers).
Запуск этой ветки с бесплатной Personal Team отдельно не проверен; наличие такой
команды в Xcode само по себе не подтверждает работоспособность подписи и фильтров.

## 6. Собрать и запустить приложение

В Xcode выберите схему **Telegram**, конфигурацию **Debug** и свой Mac, затем выполните
**Product → Build**. Для запуска используйте **Product → Run**.

Эквивалентная команда сборки с отдельным каталогом результата:

```sh
xcodebuild \
  -workspace Telegram-Mac.xcworkspace \
  -scheme Telegram \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  -allowProvisioningUpdates \
  build
```

При стандартном имени продукта готовое приложение будет в
`build/DerivedData/Build/Products/Debug/Telegram.app`. После успешной подписанной сборки
его можно открыть оттуда:

```sh
open build/DerivedData/Build/Products/Debug/Telegram.app
```

Собственный идентификатор и общая группа отделяют данные этой сборки от официального
Telegram. Ожидается отдельный вход в аккаунт. Не заменяйте ею установленный
`/Applications/Telegram.app`.

После запуска и входа проверьте появление приложения в **Системные настройки →
Фокусирование → нужный режим → Добавить фильтр**. Работа системной формы,
активация фильтра и доставка настоящих уведомлений требуют отдельной проверки на
устройстве. Успешная компиляция их не подтверждает.
