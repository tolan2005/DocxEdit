# INDEX.md — индекс файлов проекта DocxEdit

Компактный список всех файлов с одной строкой описания. Обновляется вручную
при добавлении/переименовании файлов. Для навигации по смыслам — см.
[КАРТА_ПРОЕКТА.md](./КАРТА_ПРОЕКТА.md).

## Документация (корень)

| Файл | Назначение |
|---|---|
| [CLAUDE.md](./CLAUDE.md) | Память проекта: ADR, история релизов, конвенции, состояние фич |
| [README.md](./README.md) | Публичное описание для GitHub |
| [REQUIREMENTS.md](./REQUIREMENTS.md) | Функциональные требования (R01…R10) |
| [REQUIREMENTS_AUTOUPDATE.md](./REQUIREMENTS_AUTOUPDATE.md) | Требования к встроенному auto-updater |
| [CHANGELOG.md](./CHANGELOG.md) | Пользовательский changelog по релизам |
| [RELEASING.md](./RELEASING.md) | Рабочий процесс выпуска релиза (приватный код + публичные релизы) |
| [PROJECT_ANALYSIS.md](./PROJECT_ANALYSIS.md) | Аудит кодовой базы и план улучшений со статусами пунктов (сверено 2026-10-01) |
| [DESIGN_R06.md](./DESIGN_R06.md) | Дизайн-документ R06: комментарии + track changes |
| [DESIGN_MD_MODE.md](./DESIGN_MD_MODE.md) | Дизайн MD-режима (WYSIWYG + source, ADR-049) |
| [DESIGN_HEADER_FOOTER.md](./DESIGN_HEADER_FOOTER.md) | Дизайн колонтитулов (варианты, first/odd/even) |
| [DESIGN_pagination.md](./DESIGN_pagination.md) | История подходов к пагинации (ADR-037 обосновывает выбор) |
| [LICENSE](./LICENSE) | MIT |
| INDEX.md | ← этот файл |
| [КАРТА_ПРОЕКТА.md](./КАРТА_ПРОЕКТА.md) | Карта проекта: модули, потоки данных, точки входа |

## Модули (SwiftPM targets)

### DocxCore — модель документа
| Файл | Назначение |
|---|---|
| [DocumentModel.swift](Sources/DocxCore/Sources/DocumentModel.swift) | Section/Block/Paragraph/Run/CharacterAttributes/PageSettings/HeaderFooter/DocumentStyles |
| [CharacterAttributes+Merger.swift](Sources/DocxCore/Sources/CharacterAttributes+Merger.swift) | Слияние атрибутов cascade docDefaults→style→direct |
| [DocumentStatistics.swift](Sources/DocxCore/Sources/DocumentStatistics.swift) | Счётчики слов/знаков/страниц для статистики документа |
| [DocumentError.swift](Sources/DocxCore/Sources/DocumentError.swift) | Ошибки импорта/экспорта |

### DocxIO — DOCX ↔ модель
| Файл | Назначение |
|---|---|
| [DocxIO.swift](Sources/DocxIO/Sources/DocxIO.swift) | Точка входа: импорт/экспорт через ZIPFoundation |
| [OoxmlDocumentParser.swift](Sources/DocxIO/Sources/OoxmlDocumentParser.swift) | Разбор word/document.xml (paragraphs, runs, tables) |
| [OoxmlDocumentSerializer.swift](Sources/DocxIO/Sources/OoxmlDocumentSerializer.swift) | Сериализация модели → OOXML (document.xml, numbering, styles) |
| [OoxmlStylesParser.swift](Sources/DocxIO/Sources/OoxmlStylesParser.swift) | Разбор styles.xml + cascade наследования (ADR-030/031) |
| [DocxSupportParsers.swift](Sources/DocxIO/Sources/DocxSupportParsers.swift) | Numbering.xml, header/footer parts, comments, footnotes |
| [DocxZipArchive.swift](Sources/DocxIO/Sources/DocxZipArchive.swift) | ZIPFoundation-обёртка + Content_Types/rels |

### MarkdownIO — Markdown ↔ модель
| Файл | Назначение |
|---|---|
| [MarkdownIO.swift](Sources/MarkdownIO/Sources/MarkdownIO.swift) | Импорт через swift-markdown + экспорт (renderMarkdown/renderTable) |

### RtfIO — RTF/ODT ↔ модель
| Файл | Назначение |
|---|---|
| [RtfIO.swift](Sources/RtfIO/Sources/RtfIO.swift) | RTF через NSAttributedString.documentType = .rtf |
| [OdtIO.swift](Sources/RtfIO/Sources/OdtIO.swift) | ODT через NSAttributedString.openDocument (R09) |

### EncodingDetector — TXT
| Файл | Назначение |
|---|---|
| [EncodingDetector.swift](Sources/EncodingDetector/Sources/EncodingDetector.swift) | UTF-8/16 (BOM/heuristic) + CP1251/KOI8-R кириллица |

### PdfExporter — PDF
| Файл | Назначение |
|---|---|
| [PdfExporter.swift](Sources/PdfExporter/Sources/PdfExporter.swift) | Экспорт модели в PDF через CoreText |

### DocxEdit — приложение (SwiftUI + AppKit)

#### App / lifecycle
| Файл | Назначение |
|---|---|
| [DocxEditApp.swift](Sources/DocxEdit/Sources/DocxEditApp.swift) | Entry point, AppDelegate, меню, Notification-имена, About, session.marker (ADR-055) |
| [DocumentSession.swift](Sources/DocxEdit/Sources/DocumentSession.swift) | ObservableObject поверх NSDocumentBridge; mode DOCX/MD; source/split (ADR-059); attachedController weak (ADR-058); lastSavedAt (ADR-056) |
| [NSDocumentBridge.swift](Sources/DocxEdit/Sources/NSDocumentBridge.swift) | Модель + URL + isDirty + мутаторы (markSaved/markDirty) |
| [DocumentMode.swift](Sources/DocxEdit/Sources/DocumentMode.swift) | Enum DOCX/Markdown (ADR-049) |
| [AppPreferences.swift](Sources/DocxEdit/Sources/AppPreferences.swift) | UserDefaults: шрифты, страница, колонка MD, обновления |
| [L10n.swift](Sources/DocxEdit/Sources/L10n.swift) | Локализация (R09/10, RU/EN) |

#### Controller (ViewModel)
| Файл | Назначение |
|---|---|
| [DocumentController.swift](Sources/DocxEdit/Sources/DocumentController.swift) | Ядро: форматирование, зум, page-view, refreshSelectionState |
| [DocumentController+Tables.swift](Sources/DocxEdit/Sources/DocumentController+Tables.swift) | Операции таблиц (ADR-035 распил v1.6.5) |
| [DocumentController+Images.swift](Sources/DocxEdit/Sources/DocumentController+Images.swift) | Вставка inline-изображений + rotate/flip |
| [DocumentController+ImageProperties.swift](Sources/DocxEdit/Sources/DocumentController+ImageProperties.swift) | Свойства/crop/wrap + zoom (setZoom/zoomIn/fitPageWidth) |
| [DocumentController+Search.swift](Sources/DocxEdit/Sources/DocumentController+Search.swift) | Find/Replace, regex, «Перейти к» |
| [DocumentController+References.swift](Sources/DocxEdit/Sources/DocumentController+References.swift) | Гиперссылки, закладки, cross-ref, TOC |
| [DocumentController+Notes.swift](Sources/DocxEdit/Sources/DocumentController+Notes.swift) | Сноски/концевые сноски (R07) |

#### Мост модель↔UI
| Файл | Назначение |
|---|---|
| [DocumentModel+AttributedString.swift](Sources/DocxEdit/Sources/DocumentModel+AttributedString.swift) | toAttributedString / from(attributed:); listMarkerText, ListCounters |
| [PaginatedTextContainer.swift](Sources/DocxEdit/Sources/PaginatedTextContainer.swift) | Пагинация подходом №1 (ADR-037) |

#### Окно / редактор
| Файл | Назначение |
|---|---|
| [DocumentWindowView.swift](Sources/DocxEdit/Sources/DocumentWindowView.swift) | Окно, TextEditorRepresentable, DocxTextView (drawBackground листов + MD-«ленты»), Coordinator, applyPageViewStyle (guard'ы equality-check против layout-loop, ADR-060), updateFloatingImages |
| [MarkdownSourceView.swift](Sources/DocxEdit/Sources/MarkdownSourceView.swift) | Source- и гибридный режим MD (TextKit 1): подсветка, Typora-поведение, `MarkdownTextView` рисует картинки/таблицы/линию, подмена глифов «•»/☐/☑, клик по задаче |
| [MarkdownHybridRenderer.swift](Sources/DocxEdit/Sources/MarkdownHybridRenderer.swift) | Гибридный рендер MD (Typora, ADR-063): скрытие разметки вне блока с курсором, списки/задачи, картинки, таблицы GFM, линия |
| [MarkdownPasteSupport.swift](Sources/DocxEdit/Sources/MarkdownPasteSupport.swift) | Умная вставка MD (Typora-паттерн, v1.6.6): looksLikeMarkdown + sanitize |

#### Ribbon
| Файл | Назначение |
|---|---|
| [RibbonView.swift](Sources/DocxEdit/Sources/RibbonView.swift) | Ribbon с 6 вкладками (ADR-043) + кастомизация + compact-режим ⌃F1 (ADR-059) |
| [RibbonCustomization.swift](Sources/DocxEdit/Sources/RibbonCustomization.swift) | Каталог групп + команд (50 команд, расширено для CommandPalette в v1.8.0) |
| [RibbonCustomizeView.swift](Sources/DocxEdit/Sources/RibbonCustomizeView.swift) | Диалог настройки ribbon (.sheet), «В избранном» с ↑↓/× (ADR-059) |

#### Command Palette
| Файл | Назначение |
|---|---|
| [CommandPaletteView.swift](Sources/DocxEdit/Sources/CommandPaletteView.swift) | ⌘⇧P: FuzzyMatcher (subsequence + streak-bonus), CommandPaletteView, CommandPaletteWindow singleton NSPanel — ADR-058 |

#### Сайдбары / панели
| Файл | Назначение |
|---|---|
| [NavigatorSidebarView.swift](Sources/DocxEdit/Sources/NavigatorSidebarView.swift) | Навигатор по заголовкам + drag-and-drop разделов (v1.6.5) |
| [StylesSidebarView.swift](Sources/DocxEdit/Sources/StylesSidebarView.swift) | Панель стилей (справа) |
| [CommentsSidebarView.swift](Sources/DocxEdit/Sources/CommentsSidebarView.swift) | Панель комментариев (R06) |
| [FootnotesSidebarView.swift](Sources/DocxEdit/Sources/FootnotesSidebarView.swift) | Панель сносок (R07) |

#### Движки-компаньоны (R06+, DESIGN_R06.md §2)
| Файл | Назначение |
|---|---|
| [CommentsEngine.swift](Sources/DocxEdit/Sources/CommentsEngine.swift) | Комментарии: модель + анкеры через .docxEdit… ключи |
| [TrackChangesEngine.swift](Sources/DocxEdit/Sources/TrackChangesEngine.swift) | Отслеживание правок + DOCX round-trip |

#### Auto-updater
| Файл | Назначение |
|---|---|
| [UpdaterEngine.swift](Sources/DocxEdit/Sources/UpdaterEngine.swift) | GitHub Releases API + Semver + SHA256 + detached bash-installer |
| [UpdateNotificationView.swift](Sources/DocxEdit/Sources/UpdateNotificationView.swift) | Баннер обновления с markdown-notes |

#### Диалоги / вспомогательные вью
| Файл | Назначение |
|---|---|
| [PreferencesView.swift](Sources/DocxEdit/Sources/PreferencesView.swift) | Настройки: Основные / Шрифты / Страница / По умолчанию |
| [DefaultAppsView.swift](Sources/DocxEdit/Sources/DefaultAppsView.swift) | «Приложение по умолчанию» через LSCopyDefaultRoleHandlerForContentType |
| [FontPickerView.swift](Sources/DocxEdit/Sources/FontPickerView.swift) | NSPopUpButton: Избранные → Недавние → Все |
| [FontReplaceView.swift](Sources/DocxEdit/Sources/FontReplaceView.swift) | «Заменить шрифты…» (ADR-024) |
| [StylesView.swift](Sources/DocxEdit/Sources/StylesView.swift) | Диалог «Стили…» (ADR-035 п.3) |
| [InsertTableView.swift](Sources/DocxEdit/Sources/InsertTableView.swift) | Диалог вставки таблицы (rows/cols) |
| [TablePropertiesView.swift](Sources/DocxEdit/Sources/TablePropertiesView.swift) | Свойства таблицы (ADR-039 п.7 — NSHostingView, не controller!) |
| [RowHeightView.swift](Sources/DocxEdit/Sources/RowHeightView.swift) | Высота строки таблицы |
| [MergeCellsView.swift](Sources/DocxEdit/Sources/MergeCellsView.swift) | Диалог слияния ячеек (сетка) |
| [ImagePropertiesView.swift](Sources/DocxEdit/Sources/ImagePropertiesView.swift) | Свойства изображения (ADR-047 layout fix) |
| [ImageCropView.swift](Sources/DocxEdit/Sources/ImageCropView.swift) | Визуальный кроп (ADR-046) |
| [ImageResizeOverlay.swift](Sources/DocxEdit/Sources/ImageResizeOverlay.swift) | Ручки ресайза inline-изображения |
| [HyperlinkView.swift](Sources/DocxEdit/Sources/HyperlinkView.swift) | Гиперссылки (⌘K) |
| [SymbolPickerView.swift](Sources/DocxEdit/Sources/SymbolPickerView.swift) | Вставка символа |
| [HeaderFooterView.swift](Sources/DocxEdit/Sources/HeaderFooterView.swift) | Колонтитулы (текст + выравнивание + плейсхолдеры) |
| [ParagraphIndentsView.swift](Sources/DocxEdit/Sources/ParagraphIndentsView.swift) | Диалог отступов/интервалов абзаца |
| [DocumentPropertiesView.swift](Sources/DocxEdit/Sources/DocumentPropertiesView.swift) | Автор/название/тема (docProps/core.xml) |
| [BookmarksView.swift](Sources/DocxEdit/Sources/BookmarksView.swift) | Список закладок |
| [CrossReferenceView.swift](Sources/DocxEdit/Sources/CrossReferenceView.swift) | Диалог перекрёстных ссылок |
| [FindReplaceView.swift](Sources/DocxEdit/Sources/FindReplaceView.swift) | Расширенный поиск (regex, диакритики) |
| [GoToView.swift](Sources/DocxEdit/Sources/GoToView.swift) | «Перейти к…» (страница/строка/абзац) |
| [CustomDictionaryView.swift](Sources/DocxEdit/Sources/CustomDictionaryView.swift) | Пользовательский словарь орфографии |
| [ImportReportView.swift](Sources/DocxEdit/Sources/ImportReportView.swift) | «Отчёт об открытии» (v0.1.56) |
| [StatisticsView.swift](Sources/DocxEdit/Sources/StatisticsView.swift) | Статистика документа (⌥⌘I) |
| [WelcomeView.swift](Sources/DocxEdit/Sources/WelcomeView.swift) | Окно приветствия (ADR-044) |

## Тесты (Tests/)

| Каталог | Что тестирует |
|---|---|
| DocxCoreTests/ | Модель, encoding, Codable, edge-cases |
| DocxIOTests/ | DOCX round-trip, fuzz, реальный корпус (21-24.docx) |
| RtfIOTests/ | RTF импорт/экспорт |
| MarkdownIOTests/ | MD импорт/экспорт |
| DocxEditTests/ | Мост NSAttributedString, property-based, snapshot, SmartMarkdownPaste, гибридный рендер MD (MarkdownHybridRendererTests), исходник .md без потерь и гибрид по умолчанию (MarkdownSourceFidelityTests), «Не сохранять» не оставляет автосейв (AutorecoverDiscardTests) |
| [UITests/](UITests/) | XCUITest: `project.yml` (XcodeGen → DocxEditUI.xcodeproj, в git не хранится), `run-ui-tests.sh` (SwiftPM-сборка с bundle id `…uitestspm`), `DocxEditUITests/` — cold-start с файлом = 1 окно, набор текста, второе окно; `AppShim/` (Bundle.module для Xcode-таргета), `AppInfo.plist` |

## Скрипты (scripts/)

| Файл | Назначение |
|---|---|
| [release.sh](scripts/release.sh) | Полный релиз: тесты (`--scratch-path` в $TMPDIR) → swiftlint/swiftformat (если установлены) → build → CHANGELOG → CLAUDE.md → tag → GitHub |
| [build.sh](scripts/build.sh) | Сборка .app + .zip + .dmg + SHA256SUMS + smoke-тест бандла |
| [publish-github.sh](scripts/publish-github.sh) | gh CLI: загрузка артефактов + ротация KEEP_RELEASES (ADR-040) |
| [update-changelog.sh](scripts/update-changelog.sh) | Заготовка секции в CHANGELOG.md |
| [update-claude-md.sh](scripts/update-claude-md.sh) | Обновление §4 «Текущий релиз» + §5 таблицы истории CLAUDE.md |
| [ui-smoke.sh](scripts/ui-smoke.sh) | Открытие фикстур живым .app без краша (v1.6.3) |
| [UITests/run-ui-tests.sh](UITests/run-ui-tests.sh) | XCUITest-прогон (v1.8.9); нужен `automationmodetool enable-automationmode-without-authentication` |
| [notarize.sh](scripts/notarize.sh) | Нотаризация DMG (опциональная) |
| [make-dmg.sh](scripts/make-dmg.sh) | Легаси: требует create-dmg + ассеты App/; в сценарии не используется |
| [generate-icon.swift](scripts/generate-icon.swift) | Иконка CoreGraphics → iconset → .icns |

## Ресурсы / фикстуры

| Путь | Назначение |
|---|---|
| App/ | AppIcon.appiconset + Info.plist для build.sh |
| Tests/DocxIOTests/Fixtures/ | 21-24.docx + 133.docx — реальный корпус для round-trip |
| build/vX.Y.Z/ | Артефакты релизов: .dmg + .app.zip + SHA256SUMS |
| build/DocxEdit.app | Текущий dev-бандл (ADR-012) |
| 21.docx / 22.docx / 23.docx / 24.docx / 111-114.docx / 133.docx / tabletest.docx | Тестовые документы владельца в корне |
