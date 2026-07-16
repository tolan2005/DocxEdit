---
name: docxedit-dev
description: >
  Универсальный скилл разработки DocxEdit (нативный macOS-редактор на Swift +
  SwiftUI/AppKit). Используй при любой работе по проекту: выпуск релиза (сборка
  .app + .dmg + SHA256, инкремент версии, обновление CLAUDE.md/CHANGELOG),
  соблюдение конвенций кода (тулбар ADR-013, NotificationCenter-шина, стиль,
  Conventional Commits) и личных договорённостей владельца. Активируй, когда
  пользователь просит «собрать», «выпустить релиз», «добавить фичу в тулбар»,
  «обновить память проекта» или работает с файлами в Sources/DocxEdit.
---

# DocxEdit — dev-скилл

Этот скилл фиксирует, **как** вести разработку DocxEdit. Полная память проекта — в
[`CLAUDE.md`](../../../CLAUDE.md); здесь — операционные правила и чек-листы.

## 0. Личные договорённости (ВСЕГДА соблюдать)

1. **Каждое изменение, идущее в релиз, собирай в двух форматах: `.app` и `.dmg`.**
   Не оставляй только бинарник.
2. **Инкрементная нумерация релизов** — semver `0.MINOR.PATCH`. Каждый видимый
   выпуск повышает версию. Внутренние коды R01, R02… мапятся на `0.MINOR.0`.
3. **Вопросы задавай по одному.** Если нужно уточнение — один вопрос за раз,
   дождись ответа, потом следующий.
4. **Язык UI и общения — русский** (EN-локализация запланирована на R09).
5. После релиза **обнови `CLAUDE.md` и `CHANGELOG.md`** (см. §2).
6. **Каждый релиз обязан пройти тесты.** Релиз делается **только** через
   `release.sh` — он гоняет smoke-тест бандла (всегда) и `swift test` (если есть
   полный Xcode). Не выпускай в обход теста; красный тест = релиза нет. Сообщай
   честно, что именно проверено, а что пропущено (см. §2 «Тесты при релизе»).
7. **Новую фичу добавляй и в меню, и в тулбар — как в MS Word for Mac.** Для каждой
   новой команды: (а) пункт в соответствующем меню (`DocxEditApp.swift`) с горячей
   клавишей как в Word; (б) кнопка/контрол в ribbon (`RibbonView.swift`) в той
   вкладке/группе, где это лежит в Word (Главная: Буфер обмена/Шрифт/Абзац/Стили/
   Редактирование; Вставка; Разметка; Вид; …). **Исключение:** если в MS Word for
   Mac у этого пункта **нет** кнопки на тулбаре (напр. «Сохранить как», «Экспорт»,
   «Недавние», «О программе») — оставляй только в меню, кнопку не выдумывай.
   Обе точки идут через одну `NotificationCenter`-шину / `controller` (см. §3).

## 1. Технологический контекст

- Swift 5.9+, SwiftUI (окна/инспекторы) + AppKit (текстовый движок: NSTextView,
  TextKit 2, NSMenu, NSToolbar). Минимум macOS 14 Sonoma. Universal (arm64+x86_64).
- DOCX: ZIPFoundation + Foundation XML. PDF: PDFKit/Quartz. RTF: `NSAttributedString`.
  Markdown: swift-markdown.
- Единый мост модель↔UI: `DocumentModel` ↔ `NSAttributedString` (ADR-010).
- Команды форматирования идут через NotificationCenter:
  AppDelegate → Coordinator → DocumentController (ADR-011).

## 2. Выпуск релиза (рабочий процесс)

> **Релиз — одной командой через `scripts/release.sh`** (починен под текущий формат).
> Шаги: [1] `swift test` (условно), [2] `build.sh` (`swift build -c release`, `.app`,
> иконка, **smoke-тест бандла**, пакует `.app.zip` + `.dmg` с симлинком
> `/Applications` + `SHA256SUMS` в `build/v<VERSION>/`), [3] нотаризация (опц.),
> [4] секция в `CHANGELOG.md`, [5] `CLAUDE.md`, [6] git-тег (если репозиторий).
>
> **Тесты при релизе (честный статус):** `swift test` гоняется **только при полном
> Xcode**; в Command Line Tools (нет `XCTest`) — пропуск с явной пометкой в логе
> (`SKIP_TESTS=1` форсит пропуск; красные тесты валят релиз). `build.sh` всегда
> делает **smoke-тест бандла** (структура `.app`, `plutil -lint` Info.plist,
> Mach-O/арх через `lipo`, версия; `codesign` — мягко). CI и snapshot-тесты —
> _план_, не реализованы. Не выдавай «всё протестировано» — гейт релиза = компиляция
> + smoke + (если есть Xcode) юнит-тесты.
>
> `scripts/make-dmg.sh` — **легаси** (требует `create-dmg` и ассеты `App/...`); в
> сценарии релиза не используется, упаковку делает `build.sh`.

### Полный релиз одной командой
```bash
bash scripts/release.sh <VERSION> "<CODENAME>" [KEYCHAIN_PROFILE] ["<CHANGES>"]
# пример: bash scripts/release.sh 0.2.0 "Paragraphs" "" "стили абзацев, списки, статистика"
```
`KEYCHAIN_PROFILE` пустой → без нотаризации (ad-hoc подпись). `CHANGES` →
строка истории `CLAUDE.md` И буллеты `CHANGELOG.md` (пункты делятся по `;`).
Оба скрипта (`update-claude-md.sh`, `update-changelog.sh`) идемпотентны:
повторный прогон той же версии не дублирует записи.

### Чек-лист релиза
1. **Определи версию.** Последняя — в таблице истории `CLAUDE.md` и в `build/v*`.
   MINOR — новая фича, PATCH — фикс. Придумай кодовое имя.
2. **Запусти `release.sh`** с осмысленным `CHANGES` (пункты через `;`). Он
   **обязательно прогоняет тесты** (шаг 1: `swift test` при Xcode / smoke-тест
   бандла в `build.sh` — всегда), затем собирает артефакты, добавляет секцию в
   `CHANGELOG.md` и обновляет `CLAUDE.md` (§4 «Текущий релиз», §5 таблица истории,
   дата в шапке).
3. **Убедись, что тесты прошли.** В логе должны быть `✓ тесты пройдены` (или явный
   `⏭️ пропущено: нет полного Xcode`) и `==> Smoke-тест пройден`. Красный тест или
   проваленный smoke = релиза нет, не упаковывай и не публикуй артефакты.
4. **Проверь артефакты:** `ls -lh build/v<VERSION>/` → `DocxEdit-<VERSION>.dmg`,
   `DocxEdit-<VERSION>.app.zip`, `SHA256SUMS`.
5. **Доработай вручную при необходимости:** детали в секции `CHANGELOG.md`
   (скрипт кладёт буллеты-заготовку), а в `CLAUDE.md` — §6 фичи, §3 новый ADR
   (их скрипт не пишет). См. §5 этого скилла.
6. **Сообщи итог:** версия, путь к артефактам, **что протестировано и что
   пропущено**, что вошло. Без формулировок «всё протестировано».

> Только сборка без релиза: `bash scripts/build.sh <VERSION>` — собирает и пакует,
> но не трогает `CLAUDE.md`/тег.

### Сборка без релиза (dev)
```bash
swift build              # быстрая проверка компиляции (работает без полного Xcode)
```
XCTest требует полной установки Xcode; `swift build` — нет.

## 3. Конвенции кода (обязательны при правках)

### Кнопки тулбара (ADR-013) — критично
Только так:
```swift
Button { action() } label: {
    Image(systemName: "bold")
        .font(.system(size: 12))
        .frame(width: 26, height: 22)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: 4)
            .fill(isOn ? Color.accentColor.opacity(0.2) : .clear))
}
.buttonStyle(.plain)
```
**Никогда** не использовать `Toggle(.button)` или кастомные ButtonStyle без явного
`.frame()` — даёт непредсказуемый padding и битый рендер (буква «I» → «/»).
Для color swatch — `NSColorWell` (default style), **не** `.minimal` (пиль) и не
SwiftUI `ColorPicker` (широкий пиль).

### NotificationCenter-шина
Любая новая команда форматирования/вида — через `Notification.Name.docxEdit*`.
Цепочка: добавь имя в `DocxEditApp.swift` → пост в методе AppDelegate (привязка к
пункту меню/горячей клавише) → наблюдатель в `Coordinator` →
метод в `DocumentController`. Существующие:
`docxEditToggleBold/Italic/Underline/Strikethrough/ClearFormatting`,
`docxEditApplyFont/FontSize/Alignment`,
`docxEditZoomIn/ZoomOut/ZoomReset`, `docxEditTogglePageView`.

### Прочее
- Стиль: 4 пробела, SwiftLint (минимальный набор). Swift API Design Guidelines:
  camelCase — функции/переменные, PascalCase — типы.
- Коммиты: Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`,
  `refactor:`, `test:`).
- Артефакты: `build/v<x.y.z>/` — история релизов; `build/DocxEdit.app` — текущий
  dev-бандл (ADR-012).

## 4. Где что лежит (ключевые файлы)

| Файл | Назначение |
|---|---|
| `Sources/DocxEdit/Sources/DocumentWindowView.swift` | Окно, toolbar-виджеты (AlignmentPicker/FontSizeControl/ColorWellView), TextEditorRepresentable, WindowCloseGuard |
| `Sources/DocxEdit/Sources/RibbonView.swift` | Ribbon-тулбар: закладки Главная/Разметка/Вид + строка быстрого доступа (ADR-019/021) |
| `Sources/DocxEdit/Sources/DocumentController.swift` | ViewModel: форматирование, зум, page-view, refreshSelectionState |
| `Sources/DocxEdit/Sources/DocxEditApp.swift` | Entry point, AppDelegate, меню, имена Notification |
| `Sources/DocxEdit/Sources/AppPreferences.swift` | UserDefaults: избранные/недавние шрифты, дефолтный шрифт/размер |
| `Sources/DocxEdit/Sources/FontPickerView.swift` | NSPopUpButton: Избранные → Недавние → Все |
| `Sources/DocxEdit/Sources/DocumentModel+AttributedString.swift` | Мост DocumentModel ↔ NSAttributedString |
| `Sources/DocxIO/Sources/DocxIO.swift` | DOCX импорт/экспорт: OoxmlStylesParser, RunProps, ParaProps |
| `Sources/DocxCore/Sources/DocumentModel.swift` | Модель: Section, Block, Paragraph, Run, CharacterAttributes |
| `scripts/build.sh` | Сборка .app + .zip + .dmg + SHA256SUMS в `build/v<x.y.z>/` |
| `scripts/generate-icon.swift` | Иконка CoreGraphics → iconset → .icns |

## 5. При обновлении CLAUDE.md

- Шапка: дата + `(vX.Y.Z)`.
- §3 ADR — добавляй новое архитектурное решение с датой и обоснованием.
- §4 «Текущий релиз» — версия, статус, артефакты.
- §5 таблица истории — новая строка сверху (версия, дата, кодовое имя, изменения,
  путь артефактов).
- §6 «Состояние фич» — переноси сделанное в ✅, отклонённое — в ❌ с причиной.
- §7 — фиксируй новые ограничения/техдолг.
- §11 — запись в журнал изменений документа.
- Не дублируй то, что и так видно в коде/гите; в память — только неочевидное.
