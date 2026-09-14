# Changelog DocxEdit

Все значимые изменения документируются здесь. Формат основан на [Keep a Changelog](https://keepachangelog.com/),
проект придерживается [Semantic Versioning](https://semver.org/).

## [1.7.4] — 2026-09-14 — Mini Toolbar

### Изменения
- плавающая панель Ж/К/Ч/З/подсветка/⌘K над выделением через NSPopover (Word/Notion-паттерн)
- anchor через layoutManager.boundingRect
- скрытие в reading/source-режимах и над изображением

### Артефакты
- `build/v1.7.4/DocxEdit-1.7.4.dmg`
- `build/v1.7.4/DocxEdit-1.7.4.app.zip`
- `build/v1.7.4/SHA256SUMS`

## [1.7.3] — 2026-09-14 — Open Multi + Recents

### Изменения
- multi-select в Cmd+O (каждый файл в своё окно, multi-doc)
- дата и размер файла в Welcome/Recent
- иконка по расширению

### Артефакты
- `build/v1.7.3/DocxEdit-1.7.3.dmg`
- `build/v1.7.3/DocxEdit-1.7.3.app.zip`
- `build/v1.7.3/SHA256SUMS`

## [1.7.2] — 2026-09-14 — UX Polish 2

### Изменения
- тост «Сохранено/Экспортировано» с кнопкой Finder-reveal
- баннер смены шрифта по умолчанию в открытых окнах с применением одной кнопкой

### Артефакты
- `build/v1.7.2/DocxEdit-1.7.2.dmg`
- `build/v1.7.2/DocxEdit-1.7.2.app.zip`
- `build/v1.7.2/SHA256SUMS`

## [1.7.1] — 2026-09-14 — UX Polish 1

### Изменения
- индикатор сохранения в статусбаре
- empty state в пустом документе
- убрана дубл. * в тайтле
- плюрализация «N копий»
- Esc в диалоге восстановления

### Артефакты
- `build/v1.7.1/DocxEdit-1.7.1.dmg`
- `build/v1.7.1/DocxEdit-1.7.1.app.zip`
- `build/v1.7.1/SHA256SUMS`

## [1.7.0] — 2026-09-14 — Silent Autorecover

### Изменения
- диалог восстановления только после аварий: session.marker создаётся при старте, удаляется в applicationWillTerminate
- чистый сеанс — автосейвы удаляются молча
- «Не сохранять» очищает backup сессии

### Артефакты
- `build/v1.7.0/DocxEdit-1.7.0.dmg`
- `build/v1.7.0/DocxEdit-1.7.0.app.zip`
- `build/v1.7.0/SHA256SUMS`

## [1.6.9] — 2026-09-14 — MD Zoom Reset

### Изменения
- фикс v1.6.8: смена режима MD↔DOCX сбрасывает масштаб к дефолту (MD 100%, DOCX авто-фит) — иначе колонка MD уезжала за край окна после унаследованного 191% зума от DOCX-авто-фита

### Артефакты
- `build/v1.6.9/DocxEdit-1.6.9.dmg`
- `build/v1.6.9/DocxEdit-1.6.9.app.zip`
- `build/v1.6.9/SHA256SUMS`

## [1.6.8] — 2026-09-14 — MD Ribbon

### Изменения
- видимые границы редактируемой области в MD-режиме: серое поле окна + центрированная белая колонка (600/720/900/full — настройка Preferences)

### Артефакты
- `build/v1.6.8/DocxEdit-1.6.8.dmg`
- `build/v1.6.8/DocxEdit-1.6.8.app.zip`
- `build/v1.6.8/SHA256SUMS`

## [1.6.7] — 2026-09-14 — Fit & MD Paste Fix

### Изменения
- авто-масштаб при открытии DOCX (лист занимает ~75% ширины окна)
- фикс умной вставки Markdown в WYSIWYG-режиме .md-документа (гвард пропускал MD целиком, вставка падала как plain-text)

### Артефакты
- `build/v1.6.7/DocxEdit-1.6.7.dmg`
- `build/v1.6.7/DocxEdit-1.6.7.app.zip`
- `build/v1.6.7/SHA256SUMS`

## [1.6.6] — 2026-08-25 — Smart Paste

### Изменения
- Умная вставка Markdown: ⌘V распознаёт MD-исходник из буфера (ChatGPT/Perplexity) и вставляет отформатированным в обоих режимах (Typora-поведение)
- санитайзер артефактов чатов (***Текст ***, zero-width)
- настройка-выключатель
- обычная вставка — ⇧⌥⌘V
- +12 тестов (309)

### Артефакты
- `build/v1.6.6/DocxEdit-1.6.6.dmg`
- `build/v1.6.6/DocxEdit-1.6.6.app.zip`
- `build/v1.6.6/SHA256SUMS`

## [1.6.5] — 2026-08-24 — Navigator & Split

### Изменения
- Навигатор: drag-and-drop разделов + подсветка текущего + контекстное меню перемещения
- autorecover защищает MD-исходник (сырой текст приоритетен при восстановлении)
- распил монолитов без изменения кода: DocxIO 3878→555, DocumentController 3839→1406
- +2 теста (297)

### Артефакты
- `build/v1.6.5/DocxEdit-1.6.5.dmg`
- `build/v1.6.5/DocxEdit-1.6.5.app.zip`
- `build/v1.6.5/SHA256SUMS`

## [1.6.4] — 2026-08-24 — Reliability & Typora

### Изменения
- По итогам аудита: битые XML — ошибка разбора в Отчёт об открытии
- spell-check подчёркивания всегда включены
- ⌘/ на РУ-раскладке
- Typora-поведение в MD-исходнике (Enter-списки, Tab-вложенность, ⌘B/⌘I-обёртка)
- навигатор — повысить/понизить заголовок правым кликом
- measure-тесты производительности
- swiftlint в release.sh
- --latest автоматически
- +3 теста (295)

### Артефакты
- `build/v1.6.4/DocxEdit-1.6.4.dmg`
- `build/v1.6.4/DocxEdit-1.6.4.app.zip`
- `build/v1.6.4/SHA256SUMS`

## [1.6.3] — 2026-08-19 — Highlight Fix & UI Smoke

### Изменения
- Фикс подсветки MD-исходника (оффскрин-проверка): bold через NSFontDescriptor (SF Mono), italic через obliqueness
- scripts/ui-smoke.sh — открытие корпусных документов живым .app без краша, шаг в release.sh (SKIP_UI_SMOKE=1 отключает)
- +2 теста (292)

### Артефакты
- `build/v1.6.3/DocxEdit-1.6.3.dmg`
- `build/v1.6.3/DocxEdit-1.6.3.app.zip`
- `build/v1.6.3/SHA256SUMS`

## [1.6.2] — 2026-08-19 — Obsidian & Endnote UI

### Изменения
- Obsidian-совместимость: YAML front-matter — passthrough при импорте/экспорте .md
- wiki-ссылки [[Страница]]/[[Страница|Текст]] — гиперссылки в обе стороны (в code fences не трогаются)
- создание концевых сносок в UI (Вставка → Концевая сноска, маркер римскими, редактирование в панели)
- +3 теста (290)

### Артефакты
- `build/v1.6.2/DocxEdit-1.6.2.dmg`
- `build/v1.6.2/DocxEdit-1.6.2.app.zip`
- `build/v1.6.2/SHA256SUMS`

## [1.6.1] — 2026-08-19 — Math & Drop Cap

### Изменения
- Бэклог DOCX (P3, завершён): OMML-формулы — текст импортируется (не теряется)
- буквица w:framePr — атрибуты переживают round-trip (рендер буквицы — ограничение)
- форматный бэклог P0-P3 закрыт полностью
- +2 теста (287)

### Артефакты
- `build/v1.6.1/DocxEdit-1.6.1.dmg`
- `build/v1.6.1/DocxEdit-1.6.1.app.zip`
- `build/v1.6.1/SHA256SUMS`

## [1.6.0] — 2026-08-19 — MD Source Mode

### Изменения
- Исходный режим Markdown: сырой .md моноширинным шрифтом с подсветкой синтаксиса (заголовки/Ж/К/код/ссылки/цитаты/списки/HR), переключатель в статусбаре + меню Вид (⌘/)
- в source-режиме источник истины — текст, ⌘S пишет напрямую, модель синхронизируется best-effort
- фикс: applyAttributed терял endnotes и passthrough стилей таблиц
- +6 тестов (285)

### Артефакты
- `build/v1.6.0/DocxEdit-1.6.0.dmg`
- `build/v1.6.0/DocxEdit-1.6.0.app.zip`
- `build/v1.6.0/SHA256SUMS`

## [1.5.18] — 2026-08-19 — Find Highlight

### Изменения
- Расширенный поиск (⇧⌘F): подсветка всех вхождений жёлтым прямо в документе (DocxLayoutManager, без мутации storage) + тумблер «Подсветить все»
- счётчик «N из M» при навигации
- подсветка снимается при правке/закрытии

### Артефакты
- `build/v1.5.18/DocxEdit-1.5.18.dmg`
- `build/v1.5.18/DocxEdit-1.5.18.app.zip`
- `build/v1.5.18/SHA256SUMS`

## [1.5.17] — 2026-08-19 — Table Style & Vertical Text

### Изменения
- Бэклог DOCX (P2, завершён): именованные стили таблиц (w:tblStyle) — имя + определения из styles.xml переживают round-trip (passthrough)
- вертикальный текст в ячейках (w:textDirection) — round-trip (рендер в редакторе горизонтальный, известное ограничение)
- +2 теста (279)
- бэклог P0-P2 закрыт полностью

### Артефакты
- `build/v1.5.17/DocxEdit-1.5.17.dmg`
- `build/v1.5.17/DocxEdit-1.5.17.app.zip`
- `build/v1.5.17/SHA256SUMS`

## [1.5.16] — 2026-08-19 — List Start

### Изменения
- Бэклог DOCX (P2): стартовое значение нумерации (w:start / lvlOverride startOverride) — парсинг в ListInfo.start, счёт в редакторе с нужного числа, запись обратно
- +1 тест (277)

### Артефакты
- `build/v1.5.16/DocxEdit-1.5.16.dmg`
- `build/v1.5.16/DocxEdit-1.5.16.app.zip`
- `build/v1.5.16/SHA256SUMS`

## [1.5.15] — 2026-08-18 — Endnotes

### Изменения
- Бэклог DOCX (P2): концевые сноски — импорт endnotes.xml + w:endnoteReference, маркер superscript римскими (Word-конвенция), секция в панели Сноски с редактированием, экспорт endnotes.xml+rels+Content_Types (только использованные)
- без ссылок в теле — passthrough оригинала
- создание в UI не добавлено (импорт-only)
- +2 теста (276)

### Артефакты
- `build/v1.5.15/DocxEdit-1.5.15.dmg`
- `build/v1.5.15/DocxEdit-1.5.15.app.zip`
- `build/v1.5.15/SHA256SUMS`

## [1.5.14] — 2026-08-18 — Watermarks

### Изменения
- Бэклог DOCX (P1, последний): водяные знаки видны в редакторе — WordArt v:textpath (текст/поворот/цвет) и картинки-подложки v:imagedata парсятся из VML колонтитулов и рисуются на каждом листе в Виде страницы и при печати (полупрозрачные, под текстом)
- mc:Fallback исключён
- passthrough побайтовый
- +2 теста (274)
- бэклог P0/P1 закрыт

### Артефакты
- `build/v1.5.14/DocxEdit-1.5.14.dmg`
- `build/v1.5.14/DocxEdit-1.5.14.app.zip`
- `build/v1.5.14/SHA256SUMS`

## [1.5.13] — 2026-08-18 — RU Shortcuts & Dark Mode

### Изменения
- Шорткаты на русской раскладке: универсальный NSEvent-монитор по keyCode для всех буквенных комбинаций (⌘B/⌘I/⌘U/⌘N/⌘S/⌘P/⌘F и др.)
- устранены конфликты ⇧⌘E (Экспорт PDF → ⌥⌘E) и ⌘⌥F (Заменить → ⇧⌘H, Word-конвенция)
- dark mode: лист A4 и поле Вида страницы адаптивные (белый текст больше не невидим на белом листе
- при печати лист всегда белый)

### Артефакты
- `build/v1.5.13/DocxEdit-1.5.13.dmg`
- `build/v1.5.13/DocxEdit-1.5.13.app.zip`
- `build/v1.5.13/SHA256SUMS`

## [1.5.12] — 2026-08-18 — Floating Images

### Изменения
- Живой плавающий layout изображений: wp:anchor posOffset парсится/пишется
- плавающая картинка — отдельная вьюха поверх текста (behindDoc — под ним через drawBackground), текст огибает рамку через exclusionPaths (работает и в Виде страницы)
- драг мышью с фиксацией в модель одним шагом undo
- якорь в тексте — невидимая точка 1pt
- +1 тест (272)

### Артефакты
- `build/v1.5.12/DocxEdit-1.5.12.dmg`
- `build/v1.5.12/DocxEdit-1.5.12.app.zip`
- `build/v1.5.12/SHA256SUMS`

## [1.5.11] — 2026-08-18 — Navigator

### Изменения
- Панель навигации по заголовкам (Word Navigation Pane-паттерн): левая панель со списком H1-H6, клик — прыжок к разделу
- ширина драг-разделителем, крестик закрытия
- кнопка на вкладке Вид + меню Вид → Панели → Навигация
- живое обновление при правках, работает и в MD-режиме
- инфра: CI на GitHub Actions (приватное зеркало DocxEdit-src), CI поймал баг совместимости Swift 5.10

### Артефакты
- `build/v1.5.11/DocxEdit-1.5.11.dmg`
- `build/v1.5.11/DocxEdit-1.5.11.app.zip`
- `build/v1.5.11/SHA256SUMS`

## [1.5.10] — 2026-08-16 — Clean Ruler

### Изменения
- Фикс: линейка показывала устаревшую accessory-панель NSRulerView (Стили/выравнивание/интервалы/списки, наследие TextEdit), дублирующую ribbon — accessory отключён, остаётся чистая линейка

### Артефакты
- `build/v1.5.10/DocxEdit-1.5.10.dmg`
- `build/v1.5.10/DocxEdit-1.5.10.app.zip`
- `build/v1.5.10/SHA256SUMS`

## [1.5.9] — 2026-08-16 — Sidebar Polish

### Изменения
- Боковые панели (Стили/Комментарии/Сноски): изменяемая ширина драг-разделителем (180-480pt), крестик закрытия в заголовке, отдельные кнопки на вкладке Вид (группа «Панели», с активным состоянием) вместо меню
- в MD-режиме только стили
- +1 тест (271)

### Артефакты
- `build/v1.5.9/DocxEdit-1.5.9.dmg`
- `build/v1.5.9/DocxEdit-1.5.9.app.zip`
- `build/v1.5.9/SHA256SUMS`

## [1.5.8] — 2026-08-16 — Readable Column

### Изменения
- MD-режим: читаемая колонка (паттерн iA Writer/Typora) — ограниченная ширина текста с центрированием в окне
- настройка «Ширина текста в Markdown»: Узкая/Средняя (по умолчанию)/Широкая/Во всю ширину
- применяется к открытым окнам сразу, на содержимое .md не влияет
- +2 теста (270)

### Артефакты
- `build/v1.5.8/DocxEdit-1.5.8.dmg`
- `build/v1.5.8/DocxEdit-1.5.8.app.zip`
- `build/v1.5.8/SHA256SUMS`

## [1.5.7] — 2026-08-16 — SmartArt Preview

### Изменения
- Бэклог DOCX (P1): mc:AlternateContent в теле — из legacy-fallback извлекается картинка-превью SmartArt/диаграмм (v:imagedata + размеры шейпа), раньше было пустое место
- текст VML-fallback'а подавляется — текстбоксы в теле больше не дублируются
- +2 теста (268)

### Артефакты
- `build/v1.5.7/DocxEdit-1.5.7.dmg`
- `build/v1.5.7/DocxEdit-1.5.7.app.zip`
- `build/v1.5.7/SHA256SUMS`

## [1.5.6] — 2026-08-12 — Complex Fields

### Изменения
- Бэклог DOCX (DESIGN_HEADER_FOOTER.md, последнее P0): сложные поля w:fldChar (PAGEREF/REF/SEQ/DATE) — инструкция сохраняется в Run.fieldInstr и пишется обратно (begin/instrText/separate/end) — поле остаётся живым/обновляемым в Word, а не мёртвым текстом
- одноабзацные поля
- многоабзацные (TOC) — как раньше через результат+SDT с записью в отчёте
- проверено на корпусе 21.docx
- +2 теста (266)

### Артефакты
- `build/v1.5.6/DocxEdit-1.5.6.dmg`
- `build/v1.5.6/DocxEdit-1.5.6.app.zip`
- `build/v1.5.6/SHA256SUMS`

## [1.5.5] — 2026-08-12 — Paragraph Borders

### Изменения
- Бэклог DOCX (DESIGN_HEADER_FOOTER.md P0): границы абзацев w:pBdr — парсинг (стороны/толщина/цвет, не-single→сплошная), рендер в редакторе рамкой вокруг абзаца (DocxLayoutManager), запись обратно
- раньше отбрасывались молча
- +2 теста (264)

### Артефакты
- `build/v1.5.5/DocxEdit-1.5.5.dmg`
- `build/v1.5.5/DocxEdit-1.5.5.app.zip`
- `build/v1.5.5/SHA256SUMS`

## [1.5.4] — 2026-08-11 — Columns & Tabs

### Изменения
- Бэклог DOCX (DESIGN_HEADER_FOOTER.md P0): passthrough неизвестных детей sectPr — w:cols (многоколоночная вёрстка), docGrid, vAlign, pgNumType, pgBorders больше не теряются при open-save (рендер колонок — отдельная задача)
- пользовательские таб-стопы w:tabs — парсинг в модель ParagraphAttributes.tabStops, применение в редакторе через NSParagraphStyle, запись обратно
- decimal→right
- дефолтные стопы в модель не пишутся
- +4 теста (262)

### Артефакты
- `build/v1.5.4/DocxEdit-1.5.4.dmg`
- `build/v1.5.4/DocxEdit-1.5.4.app.zip`
- `build/v1.5.4/SHA256SUMS`

## [1.5.3] — 2026-08-11 — Header Images Render

### Изменения
- Закрытие DESIGN_HEADER_FOOTER.md: плавающие картинки колонтитулов (wp:anchor, логотипы) парсятся с позициями (HFImage placements) и рисуются в полях каждого листа A4 в Виде страницы + при печати (DocxTextView.drawBackground, варианты first/even/default)
- раньше сохранялись в файле, но не отображались
- текстбоксы — по-прежнему только текстом (следующий кандидат)
- +1 тест (258)

### Артефакты
- `build/v1.5.3/DocxEdit-1.5.3.dmg`
- `build/v1.5.3/DocxEdit-1.5.3.app.zip`
- `build/v1.5.3/SHA256SUMS`

## [1.5.2] — 2026-08-11 — Package Passthrough

### Изменения
- Продолжение DESIGN_HEADER_FOOTER.md: текстбоксы колонтитулов не дублируются (mc:AlternateContent Fallback пропускается) и не склеиваются (разделители абзацев/табов)
- generic passthrough неизвестных частей пакета (customXml, theme, fontTable, webSettings, endnotes, app.xml) с их Content-Type
- settings.xml пишется из оригинала с инжекцией evenAndOddHeaders (не теряются compat/zoom/proofState)
- +3 теста (257)

### Артефакты
- `build/v1.5.2/DocxEdit-1.5.2.dmg`
- `build/v1.5.2/DocxEdit-1.5.2.app.zip`
- `build/v1.5.2/SHA256SUMS`

## [1.5.1] — 2026-08-10 — Header Passthrough

### Изменения
- Сложные колонтитулы не теряются (DESIGN_HEADER_FOOTER.md): lossless passthrough — сырые байты частей колонтитулов + rels + media пишутся обратно при сохранении, если колонтитул не редактировался (графика/текстбоксы/рамки переживают open-save)
- слоты first/even/default резолвятся через document.xml.rels (фикс перепутанных слотов сторонних файлов)
- флаги evenOdd/titlePg — по settings.xml/sectPr, не по наличию части
- ImportReport видит графику/текстбоксы/рамки в колонтитулах
- 133.docx в тестовом корпусе
- +6 тестов (254)

### Артефакты
- `build/v1.5.1/DocxEdit-1.5.1.dmg`
- `build/v1.5.1/DocxEdit-1.5.1.app.zip`
- `build/v1.5.1/SHA256SUMS`

## [1.5.0] — 2026-08-02 — MD Mode

### Изменения
- Milestone: DocxEdit — полноценный Markdown-редактор (ADR-049, релизы v1.4.0-v1.4.3)
- режим DOCX/Markdown по расширению
- полный MD-цикл: заголовки, Ж/К/Ч/З, код, цитаты, HR, вложенные списки, GFM-таблицы, ссылки
- Typora-поведение Return
- Копировать/Вставить как Markdown
- верификация: образец GitHub-совместим, round-trip идемпотентен
- финальный ADR-049 в CLAUDE.md
- README обновлён
- 248 тестов

### Артефакты
- `build/v1.5.0/DocxEdit-1.5.0.dmg`
- `build/v1.5.0/DocxEdit-1.5.0.app.zip`
- `build/v1.5.0/SHA256SUMS`

## [1.4.3] — 2026-08-01 — MD Polish

### Изменения
- MD-полировка (ADR-049): Return на пустом элементе списка/пустой цитате в MD-режиме — выход из структуры, а не новый пункт (handleReturnOnEmptyMarkdownStructure)
- pretty-print таблиц при сохранении .md (настройка, по умолчанию вкл)
- импорт GFM-таблиц из MD в настоящие таблицы (раньше терялись)
- Правка → Копировать как Markdown / Вставить из Markdown (через MarkdownIO, один шаг undo)
- +3 теста (248)

### Артефакты
- `build/v1.4.3/DocxEdit-1.4.3.dmg`
- `build/v1.4.3/DocxEdit-1.4.3.app.zip`
- `build/v1.4.3/SHA256SUMS`

## [1.4.2] — 2026-08-01 — Full Markdown Export

### Изменения
- Полный MD-экспорт/импорт (ADR-049): blockquote (>), fenced code blocks, горизонтальная линия (---), вложенные списки с уровнями, зачёркивание ~~, гиперссылки с URL (раньше терялись), экранирование спецсимволов, ==подсветка==, sup/sub/u HTML-fallback
- абзацы разделяются пустой строкой (GitHub-совместимость)
- SoftBreak/LineBreak больше не слипают строки
- три новых стиля абзаца — Цитата/Блок кода/Горизонтальная линия (пикер стилей + DOCX round-trip через styles.xml)
- HR рисуется линией (DocxLayoutManager)
- +14 тестов (245)

### Артефакты
- `build/v1.4.2/DocxEdit-1.4.2.dmg`
- `build/v1.4.2/DocxEdit-1.4.2.app.zip`
- `build/v1.4.2/SHA256SUMS`

## [1.4.1] — 2026-08-01 — MD Mode Toolbar

### Изменения
- MD-режим: ribbon и меню показывают только Markdown-совместимые инструменты — скрыты вкладка «Разметка», шрифт/размер/цвет/highlight, над/подстрочные, выравнивание, интервал, закладки/cross-ref, сноски/оглавление, комментарии, track-changes, вид страницы и линейка (через markdownHiddenRibbonGroups + гранулярные if isMarkdown + .disabled в меню)
- вид страницы в MD отключён (applyPageViewStyle + togglePageView guard)
- «Избранное» фильтруется whitelist
- +3 теста (231)

### Артефакты
- `build/v1.4.1/DocxEdit-1.4.1.dmg`
- `build/v1.4.1/DocxEdit-1.4.1.app.zip`
- `build/v1.4.1/SHA256SUMS`

## [1.4.0] — 2026-07-30 — MD Mode Core

### Изменения
- Режим документа DOCX/Markdown (ADR-049): определяется расширением при открытии (.md/.markdown → Markdown)
- в MD-режиме ⌘S сохраняет в .md по умолчанию (фикс: раньше .md перезаписывался DOCX-байтами), остальные форматы — через Экспорт
- индикатор режима в статусбаре с переключением и предупреждением о потере форматирования при DOCX→MD
- настройка «Формат новых документов» (Preferences → Основные)
- ⇧⌘N «Новый Markdown»
- +8 тестов (228)

### Артефакты
- `build/v1.4.0/DocxEdit-1.4.0.dmg`
- `build/v1.4.0/DocxEdit-1.4.0.app.zip`
- `build/v1.4.0/SHA256SUMS`

## [1.3.1] — 2026-07-17 — Empty Doc By Default

### Изменения

- Дефолт настройки «Восстанавливать последний документ» переведён в **OFF** (было ON с v1.2.1). При multi-doc это ожидаемо: запуск даёт пустое окно, а не последний открытый файл.
- Уже установленные пользователи с включённой настройкой могут отключить её вручную: **DocxEdit → Настройки → Основные → При запуске → «Восстанавливать последний документ»**.

### Артефакты

- `build/v1.3.1/DocxEdit-1.3.1.dmg`
- `build/v1.3.1/DocxEdit-1.3.1.app.zip`
- `build/v1.3.1/SHA256SUMS`

## [1.3.0] — 2026-07-17 — Multi-Document

Многодокументный режим. Каждый документ — своё окно, как в Pages и Word.

### Что нового

- **⌘N** — открывает новое пустое окно (не сбрасывает текущее).
- **⌘O** — открывает выбранный файл в новом окне (текущий не трогается).
- **Открытие из Finder** — новый файл открывается в новом окне (если уже есть открытый документ).
- Каждое окно — независимая `DocumentSession` со своим редактором, undo, save, тулбаром, зумом, режимом «Вид страницы».
- Команды форматирования (⌘B/⌘I, стили, вставка таблицы и т.д.) применяются только к **ключевому окну** (тому, на котором фокус) — уведомления NotificationCenter теперь фильтруются `isKeyWindow`-гардом.

### Устройство (для будущей ориентации)

- `WindowGroup(id: "docx-window", for: UUID.self)` — SwiftUI создаёт новое окно на каждое уникальное значение UUID.
- `DocumentWindowRoot` — обёртка с `@StateObject DocumentSession` на каждое окно.
- `SessionAnchor` (`NSViewRepresentable`) — слушает `NSWindow.didBecomeMainNotification` СВОЕГО окна, переключает `AppDelegate.currentSession` при активации.
- `AppDelegate.session` — computed getter, возвращает `currentSession` (weak). Все существующие вызовы `session?.…` автоматически работают с активным окном.
- `Coordinator.observeKeyZero(_:_:)` / `observeKeyNote(_:_:)` — обёртки над `NotificationCenter.addObserver` с проверкой `isKeyForNotifications` (`scrollView?.window?.isKeyWindow == true`); заменяют 76 прежних `nc.addObserver(self, selector:, name:, object: nil)`.
- Autorecover / welcome / update-баннер срабатывают один раз при старте (guard `didPerformInitialWindowActions` в AppDelegate).

### Известные ограничения v1

- **Сохранение при закрытии окна** — используется существующий `WindowCloseGuard`; проверил, что работает per-window.
- **Undo/Redo** — per-window автоматически (у каждого NSTextView свой undoManager).
- **Autorecover** — фиксирует все окна в общий каталог; при восстановлении открывается только самая свежая копия в текущее (первое) окно. Автовосстановление всех окон одновременно — задача v1.3.x.
- **Format Painter** буфер — на уровне контроллера окна, а не глобальный. Копирование в одном окне, вставка в другом не работает (задача v1.3.x).
- **Приложение по-прежнему завершается при закрытии последнего окна** (`applicationShouldTerminateAfterLastWindowClosed: true`) — смены на «оставаться в Dock» пока нет.

### Артефакты

- `build/v1.3.0/DocxEdit-1.3.0.dmg`
- `build/v1.3.0/DocxEdit-1.3.0.app.zip`
- `build/v1.3.0/SHA256SUMS`

## [1.2.5] — 2026-07-17 — Image Dialog Layout Fix

Правка вёрстки диалога «Свойства изображения» после v1.2.4.

### Проблема

- После v1.2.4 окно перестало съезжать за левую границу дисплея, но заголовок «Свойства изображения» и левые части строк формы всё равно оказывались срезанными по левому краю содержимого окна.

### Причина

- SwiftUI `Form` на macOS расширяет свою ширину под собственный grid; VStack растёт под ширину Form; внешний `.frame(width: 480)` **не клипит содержимое**, а центрирует overflow — из-за чего часть контента уходила в отрицательную x-координату.

### Фикс

- Заменил `Form { ... }` на явный `VStack` с фиксированными ширинами (label 130 pt + control + `Spacer(minLength: 0)` для прижатия к левому краю).
- Задал `TextEditor` явную ширину 300 pt (было `.frame(height: 80)` без ширины — растекался и утягивал VStack).
- Внешний `.frame(width: 480, height: 500)` получил `alignment: .topLeading` — если что-то всё же не влезет, overflow уйдёт вправо/вниз, а не влево.

### Артефакты

- `build/v1.2.5/DocxEdit-1.2.5.dmg`
- `build/v1.2.5/DocxEdit-1.2.5.app.zip`
- `build/v1.2.5/SHA256SUMS`

## [1.2.4] — 2026-07-17 — Scroll, Image Dialogs & Visual Crop

Три бага, отправленных пользователем сразу после v1.2.3.

### Прокрутка многостраничного документа

- **Симптом:** при открытии файла >1 страницы нельзя было прокрутить дальше первой; ввод любого символа «разлочивал» скролл.
- **Причина:** `applyPageViewStyle` в `TextEditorRepresentable.updateNSView` вызывался ДО синка `NSTextStorage` из session. `NSLayoutManager.usedRect` был пуст → `pageCount=1` → высота `textView.frame` ограничена одной страницей. Ввод символа триггерил повторный `updateNSView`, storage уже был наполнен, пересчёт «оживлял» скролл.
- **Фикс:** переставили порядок в `updateNSView` — стилизация страниц теперь считает `usedRect` уже после синка storage.

### Диалог «Свойства изображения»

- **Симптом:** окно сдвинуто влево, обрезано за левой границей.
- **Причина:** использовал запрещённый паттерн `NSWindow(contentViewController: NSHostingController)` — тот же класс проблем, что вызывал крах «Свойств таблицы» до v0.1.91 (ADR-039 п.7).
- **Фикс:** перевод на `NSWindow(contentRect:) + NSHostingView(sizingOptions: [])`; вью получила явную высоту 500pt.

### Визуальная обрезка изображения

- **Симптом:** пункт «Обрезать изображение…» открывал форму с четырьмя полями процентов (сверху / справа / снизу / слева) — обрезать приходилось вслепую.
- **Фикс:** переписан `ImageCropView` в визуальный редактор — превью изображения (380 pt по большей стороне) на шахматном фоне (видна альфа-прозрачность), полупрозрачное затемнение обрезаемых полей, 4 драг-угла (drag corners) для изменения границ, драг тела прямоугольника для перемещения crop. Нормализованные координаты (0..1) конвертируются в тот же `DocumentController.cropImageAtCaret(top/right/bottom/left)` — бэкенд не тронут, bake в bitmap + один шаг undo как раньше.

### Артефакты

- `build/v1.2.4/DocxEdit-1.2.4.dmg`
- `build/v1.2.4/DocxEdit-1.2.4.app.zip`
- `build/v1.2.4/SHA256SUMS`

## [1.2.3] — 2026-07-17 — Welcome Window Toggle

По фидбеку после v1.2.1: возможность управлять окном приветствия — прямо из окна и из настроек.

### Изменения

- В окне приветствия — чекбокс **«Открывать при старте приложения»** (bound to `AppPreferences.showWelcomeOnLaunch`, default `true`).
- В Preferences → «Основные» → раздел «При запуске» — второй Toggle «Показывать окно приветствия».
- `AppDelegate.restoreSessionOrShowWelcome` учитывает новую настройку: если восстанавливать нечего, а окно приветствия выключено — приложение просто стартует с пустым «Без имени».

### Артефакты

- `build/v1.2.3/DocxEdit-1.2.3.dmg`
- `build/v1.2.3/DocxEdit-1.2.3.app.zip`
- `build/v1.2.3/SHA256SUMS`

## [1.2.2] — 2026-07-17 — Auto-Install & Markdown Notes

Исправление двух багов автообновления, найденных пользователем в v1.2.1.

### Markdown в баннере обновления

- Раньше release notes из GitHub отображались как сырой markdown (были видны `###`, `**`, `` ` ``).
- Теперь баннер разбирает заголовки (`#`/`##`/`###`), буллиты (`-`/`*`) и inline-разметку (`**bold**`/`*italic*`/`` `code` ``) через `AttributedString(markdown:)`.

### Настоящая авто-установка с прогрессом

- Раньше кнопка «Установить сейчас» просто открывала .dmg в Finder — пользователь должен был вручную перетащить .app в /Applications.
- Теперь: реальный прогресс-бар при скачивании (URLSessionDownloadDelegate стримит fractional progress) + верификация SHA256 + detached bash-installer (§4.5 REQUIREMENTS_AUTOUPDATE).
- Installer ждёт выхода текущего приложения, монтирует .dmg (или распаковывает .zip), атомарно копирует .app на место (через staging-путь), снимает `com.apple.quarantine` (чтобы Gatekeeper не показывал предупреждение) и перезапускает обновлённое приложение.
- Fallback: если установка не удалась — открывает .dmg в Finder, как раньше, чтобы пользователь мог поставить вручную.

### Артефакты

- `build/v1.2.2/DocxEdit-1.2.2.dmg`
- `build/v1.2.2/DocxEdit-1.2.2.app.zip`
- `build/v1.2.2/SHA256SUMS`

## [1.2.1] — 2026-07-17 — Session Restore & Welcome

UX-релиз: три улучшения первого впечатления от запуска приложения.

### Восстановление сессии

- При запуске без файла приложение снова открывает последний документ (путь запоминается при каждом открытии и сохранении).
- Настройка «При запуске → Восстанавливать последний документ» на вкладке «Основные» (по умолчанию включено).
- Восстановление пропускается, если: файл открывается из Finder/CLI; идёт автовосстановление после краша; пользователь уже начал печатать в новом документе.

### Окно приветствия

- Если восстанавливать нечего (первый запуск, файл удалён) или настройка выключена — окно приветствия: «Новый документ», «Открыть…», список недавних документов (до 8, с путями).
- Новый файл `WelcomeView.swift`; окно по обязательному паттерну диалогов (ADR-039 п.7).

### Drag-and-drop файла в окно

- Перетаскивание `.docx`/`.doc`/`.rtf`/`.odt`/`.md`/`.txt` из Finder прямо в область текста открывает документ (раньше файл вставлялся как attachment).
- Изображения по-прежнему вставляются inline в текст.

### Мелочи

- Клик по счётчику слов в статусбаре открывает диалог полной статистики (⌥⌘I).

### Артефакты

- `build/v1.2.1/DocxEdit-1.2.1.dmg`
- `build/v1.2.1/DocxEdit-1.2.1.app.zip`
- `build/v1.2.1/SHA256SUMS`
- GitHub Release: <https://github.com/tolan2005/DocxEdit/releases/tag/v1.2.1>

## [1.2.0] — 2026-07-17 — Ribbon Tabs & Customization

UX-релиз: реорганизация ribbon-тулбара + система пользовательской настройки.

### Вкладки ribbon (было 4 → стало 6, зеркалят структуру меню v1.1.1)

- **Главная** — буфер обмена, шрифт, абзац, стили, редактирование + новая группа «Избранное» (пользовательская).
- **Вставка** — иллюстрации, ссылки (+Закладка, +Перекрёстная ссылка), таблицы, оглавление и сноски (+Оглавление, +Обновить оглавление), символы. Табличные операции убраны.
- **Разметка** *(новая)* — разрывы, колонтитулы (+Колонтитулы…, +Номера страниц).
- **Таблица** *(новая)* — строки и столбцы, ячейки, свойства; всё dimmed вне таблицы с подсказкой «Поставьте курсор в таблицу».
- **Обзор** — правописание + новые группы «Комментарии» (вставить, панель) и «Правки» (записывать с реактивной подсветкой, следующая, меню принять/отклонить), замены, отчёты.
- **Вид** — режим (+Режим чтения), показать (+Линейка, +меню Панелей), масштаб (+По ширине страницы, +Две страницы).

### Настройка тулбара (новое)

- Три точки входа: правый клик по ribbon → «Настроить панель инструментов…», меню Вид → «Настроить панель инструментов…», кнопка-шестерёнка справа от закладок.
- Диалог с двумя колонками: скрытие/показ любой из 23 групп (checkbox по вкладкам) + «Избранное» — выбор из каталога 24 команд.
- Отмеченные «избранные» команды появляются отдельной группой в конце вкладки «Главная» — быстрый доступ без переключения вкладок.
- Хранение в UserDefaults (`pref.hiddenRibbonGroups`, `pref.ribbonFavorites`); кнопка «Сбросить настройки».
- Каталог групп/команд — новый файл `RibbonCustomization.swift`; диалог — `RibbonCustomizeView.swift` (SwiftUI .sheet).

### Тесты

- +5 тестов целостности каталога (`RibbonCustomizationTests`), всего 220, PASS.

### Известные ограничения

- Порядок команд в «Избранном» фиксирован порядком каталога (ручной drag-n-drop — v1.3).
- Скрытие отдельных кнопок внутри группы не поддерживается — только группа целиком.

### Артефакты

- `build/v1.2.0/DocxEdit-1.2.0.dmg`
- `build/v1.2.0/DocxEdit-1.2.0.app.zip`
- `build/v1.2.0/SHA256SUMS`
- GitHub Release: <https://github.com/tolan2005/DocxEdit/releases/tag/v1.2.0>

## [1.1.1] — 2026-07-16 — Menu Reorganization

UX-релиз. Реорганизация всех меню строки меню — от 7 меню с суммарно ~90 пунктами (некоторые до 32 на верхнем уровне) к 7 меню с ≤15 пунктов каждое, сгруппированных по смыслу.

### Изменения структуры

- **Формат** — 5 логических групп через Divider: (1) символьные атрибуты (Ж/К/Ч/З/над/подстрочный), (2) стили абзаца + знака + «Стили…», (3) абзац (выравнивание вынесено в подменю, интервал, отступы, «Абзац…»), (4) списки, (5) прочее (регистр, подсветка, шрифты, format painter, очистка).
- **Таблица** *(новое меню)* — все операции с существующей таблицей: добавить/удалить строки и столбцы, объединить/разделить ячейки, строка-заголовок, высота строки, свойства таблицы. Вынесено из «Вставка → Изменить таблицу».
- **Обзор** *(новое меню)* — правописание, пользовательский словарь, комментарии (подменю), отслеживание правок (подменю), режим чтения. Собрано из бывших «Инструменты» + «Вставка» + «Вид» — как в Word/Pages.
- **Вставка** — теперь только вставка НОВЫХ объектов: ссылки (гиперссылка/закладка/cross-ref), объекты (изображение, таблица), символы, разрывы, колонтитулы, сноска, оглавление.
- **Вид** — сайдбары «Стили/Комментарии/Сноски» объединены в подменю «Панели» (было 3 отдельных строки). «Режим чтения» переехал в «Обзор».
- **Правка** — «Найти/Заменить/Расширенный поиск/Перейти к» собраны в подменю «Найти».
- **Инструменты** — только статистика документа + отчёт об открытии.

### Что сохранено

- Все шорткаты (⌘B/I/U, ⌘⌥1..6, ⌘F, ⌘K, ⌘⌥T, ⌘⇧E, ⌥⌘M и т.д.) — мышечная память пользователя не ломается.
- Все `appDelegate.*` методы работают без изменений (только их места вызова из меню).
- Ribbon и контекстные меню не тронуты.

### Известное ограничение

- Меню «Таблица» отображает пункты всегда — dimmed-состояние (когда курсор не в таблице) требует ObservableObject-биндинга через `@FocusedValue` или подобный механизм; отложено в v1.2. Клик по пункту вне таблицы — no-op (без краша).

### Артефакты

- `build/v1.1.1/DocxEdit-1.1.1.dmg`
- `build/v1.1.1/DocxEdit-1.1.1.app.zip`
- `build/v1.1.1/SHA256SUMS`
- GitHub Release: <https://github.com/tolan2005/DocxEdit/releases/tag/v1.1.1>

## [1.1.0] — 2026-07-16 — R11 — GitHub Publishing & Auto-Update

### Часть A — Публикация релизов на GitHub (ADR-040)
- Новый `scripts/publish-github.sh` — обёртка над `gh` CLI. Создаёт GitHub Release с тегом `vX.Y.Z`, аплоадит `.dmg`/`.app.zip`/`SHA256SUMS`.
- Тело релиза извлекается из соответствующей секции CHANGELOG.md.
- Идемпотентно: повторный запуск с той же версией = `gh release upload --clobber` + `gh release edit`.
- Автоматическая ротация: остаётся `KEEP_RELEASES` последних (env, default 3), остальные удаляются через `gh release delete` (git-теги сохраняются).
- Pre-release суффиксы (`-rc.N`/`-beta.N`) → флаг `--prerelease`.
- `scripts/release.sh` шаг 7 автоматически вызывает publish-github.sh; флаг `--no-publish` пропускает; отсутствие `gh`/remote/репо — graceful skip.
- Trademark-очистка кода и README перед публичным репо: убраны user-visible упоминания «Microsoft Word», добавлен disclaimer в README.

### Часть B — Встроенный auto-updater (ADR-041)
- Новые файлы: `Sources/DocxEdit/Sources/UpdaterEngine.swift`, `UpdateNotificationView.swift`.
- При запуске (через 2 сек после `applicationDidFinishLaunching`) дёргает `https://api.github.com/repos/tolan2005/DocxEdit/releases/latest`; сравнивает semver с `CFBundleShortVersionString`.
- Если новее — banner-окно с release notes, кнопками «Установить сейчас / Позже / Пропустить эту версию».
- Скачивание `.dmg` через `URLSession.download`, обязательная SHA256-верификация против `SHA256SUMS` (при несовпадении — отказ, файл удаляется).
- Успех → `NSWorkspace.open(dmg)`; пользователь перетаскивает в /Applications вручную.
- Ручная проверка — меню DocxEdit → «Проверить обновления…».
- Настройка периодичности в Preferences → Основные: При запуске / Раз в день / Раз в неделю / Никогда.
- При «Никогда» — 0 сетевых запросов.
- Приватность (ADR-008): User-Agent строго `DocxEdit/<v> (macOS)` без ID; никаких промежуточных сервисов, cookies, tokens.
- UI-паттерн — `NSWindow(contentRect:) + NSHostingView(sizingOptions: [])` (ADR-039 п.7 — единственный разрешённый).

### Тесты
- `Tests/DocxEditTests/UpdaterTests.swift`: Semver (10 кейсов), SHA256Verifier (4 кейса), UpdateCheckFrequency.

### Известные ограничения v1.1.0 (осознанные, post-1.1)
- Прогресс-бар при загрузке — сейчас 0→1 по факту завершения (URLSession без делегата).
- In-place replace для `.app.zip` через helper-скрипт — задача v1.2.x (сейчас только `.dmg`-flow).
- Кеш metadata на 1 час против rate-limit кластерного NAT — REQUIREMENTS §8 R2.
- Snapshot-тест `UpdateNotificationView` — не добавлен.
- Nomотаризация (Developer ID + Apple notary) обязательна для in-place replace без Gatekeeper-варнинга: до тех пор пользователь при первом запуске новой версии видит Gatekeeper alert (правый клик → Открыть).

### Артефакты
- `build/v1.1.0/DocxEdit-1.1.0.dmg`
- `build/v1.1.0/DocxEdit-1.1.0.app.zip`
- `build/v1.1.0/SHA256SUMS`
- GitHub Release: <https://github.com/tolan2005/DocxEdit/releases/tag/v1.1.0>

## [1.0.0] — 2026-07-16 — R10 Milestone — Public Release

### Изменения
- Первая публичная стабильная версия. Закрыт весь план R01-R10.

### Артефакты
- `build/v1.0.0/DocxEdit-1.0.0.dmg`
- `build/v1.0.0/DocxEdit-1.0.0.app.zip`
- `build/v1.0.0/SHA256SUMS`

## [0.7.2] — 2026-07-16 — R10b — Dialog Localization

### Изменения
- EN-перевод всех SwiftUI-диалогов (~180 новых ключей)

### Артефакты
- `build/v0.7.2/DocxEdit-0.7.2.dmg`
- `build/v0.7.2/DocxEdit-0.7.2.app.zip`
- `build/v0.7.2/SHA256SUMS`

## [0.7.1] — 2026-07-16 — R10a — Menu Localization

### Изменения
- R10 старт: EN-перевод основных меню через SwiftUI LocalizedStringKey

### Артефакты
- `build/v0.7.1/DocxEdit-0.7.1.dmg`
- `build/v0.7.1/DocxEdit-0.7.1.app.zip`
- `build/v0.7.1/SHA256SUMS`

## [0.7.0] — 2026-07-16 — R09 Milestone — Beta

### Изменения
- R09 закрыт: ODT + EN-локализация infrastructure + grammar (уже с v0.1.56)

### Артефакты
- `build/v0.7.0/DocxEdit-0.7.0.dmg`
- `build/v0.7.0/DocxEdit-0.7.0.app.zip`
- `build/v0.7.0/SHA256SUMS`

## [0.6.2] — 2026-07-16 — R09b — EN Localization Foundation

### Изменения
- R09 EN localization: инфраструктура + первый набор ключей

### Артефакты
- `build/v0.6.2/DocxEdit-0.6.2.dmg`
- `build/v0.6.2/DocxEdit-0.6.2.app.zip`
- `build/v0.6.2/SHA256SUMS`

## [0.6.1] — 2026-07-16 — R09a — ODT Import/Export

### Изменения
- R09 старт: ODT через NSAttributedString.openDocument

### Артефакты
- `build/v0.6.1/DocxEdit-0.6.1.dmg`
- `build/v0.6.1/DocxEdit-0.6.1.app.zip`
- `build/v0.6.1/SHA256SUMS`

## [0.6.0] — 2026-07-16 — R08 Milestone — Performance & Diagnostics

### Изменения
- R08 закрыт: Performance Metrics + Attribute Revisions + Import Report

### Артефакты
- `build/v0.6.0/DocxEdit-0.6.0.dmg`
- `build/v0.6.0/DocxEdit-0.6.0.app.zip`
- `build/v0.6.0/SHA256SUMS`

## [0.5.8] — 2026-07-16 — R08b — Attribute Revisions

### Изменения
- rPrChange track-changes: DOCX round-trip факта ревизии (author/date/id)

### Артефакты
- `build/v0.5.8/DocxEdit-0.5.8.dmg`
- `build/v0.5.8/DocxEdit-0.5.8.app.zip`
- `build/v0.5.8/SHA256SUMS`

## [0.5.7] — 2026-07-16 — R08a — Performance Metrics

### Изменения
- R08 старт: инструментирование open/save latency + отображение в диалоге отчёта

### Артефакты
- `build/v0.5.7/DocxEdit-0.5.7.dmg`
- `build/v0.5.7/DocxEdit-0.5.7.app.zip`
- `build/v0.5.7/SHA256SUMS`

## [0.5.6] — 2026-07-16 — R07 Close — TOC as SDT + Auto-Refresh

### Изменения
- TOC как <w:sdt> + auto-refresh при правке заголовков

### Артефакты
- `build/v0.5.6/DocxEdit-0.5.6.dmg`
- `build/v0.5.6/DocxEdit-0.5.6.app.zip`
- `build/v0.5.6/SHA256SUMS`

## [0.5.5] — 2026-07-14 — Cross-Ref DOCX Round-Trip

### Изменения
- R07 hard-parts: cross-ref DOCX round-trip через w:fldSimple REF + Cmd+клик навигация

### Артефакты
- `build/v0.5.5/DocxEdit-0.5.5.dmg`
- `build/v0.5.5/DocxEdit-0.5.5.app.zip`
- `build/v0.5.5/SHA256SUMS`

## [0.5.1] — 2026-07-13 — Encoding & Markdown Fixes

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.5.1/DocxEdit-0.5.1.dmg`
- `build/v0.5.1/DocxEdit-0.5.1.app.zip`
- `build/v0.5.1/SHA256SUMS`

## [0.5.0] — 2026-07-13 — R06 Milestone

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.5.0/DocxEdit-0.5.0.dmg`
- `build/v0.5.0/DocxEdit-0.5.0.app.zip`
- `build/v0.5.0/SHA256SUMS`

## [0.4.8] — 2026-07-13 — Track Changes Review

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.4.8/DocxEdit-0.4.8.dmg`
- `build/v0.4.8/DocxEdit-0.4.8.app.zip`
- `build/v0.4.8/SHA256SUMS`

## [0.4.7] — 2026-07-13 — Track Changes DOCX

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.4.7/DocxEdit-0.4.7.dmg`
- `build/v0.4.7/DocxEdit-0.4.7.app.zip`
- `build/v0.4.7/SHA256SUMS`

## [0.4.6] — 2026-07-13 — Track Changes

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.4.6/DocxEdit-0.4.6.dmg`
- `build/v0.4.6/DocxEdit-0.4.6.app.zip`
- `build/v0.4.6/SHA256SUMS`

## [0.4.5] — 2026-07-13 — Comments DOCX

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.4.5/DocxEdit-0.4.5.dmg`
- `build/v0.4.5/DocxEdit-0.4.5.app.zip`
- `build/v0.4.5/SHA256SUMS`

## [0.4.4] — 2026-07-13 — Comments

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.4.4/DocxEdit-0.4.4.dmg`
- `build/v0.4.4/DocxEdit-0.4.4.app.zip`
- `build/v0.4.4/SHA256SUMS`

## [0.4.3] — 2026-07-13 — Reading Mode

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.4.3/DocxEdit-0.4.3.dmg`
- `build/v0.4.3/DocxEdit-0.4.3.app.zip`
- `build/v0.4.3/SHA256SUMS`

## [0.4.2] — 2026-07-13 — Header Import Fix & Tests

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.4.2/DocxEdit-0.4.2.dmg`
- `build/v0.4.2/DocxEdit-0.4.2.app.zip`
- `build/v0.4.2/SHA256SUMS`

## [0.4.1] — 2026-07-13 — Recover & Encoding Fixes

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.4.1/DocxEdit-0.4.1.dmg`
- `build/v0.4.1/DocxEdit-0.4.1.app.zip`
- `build/v0.4.1/SHA256SUMS`

## [0.4.0] — 2026-07-13 — R05 Milestone

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.4.0/DocxEdit-0.4.0.dmg`
- `build/v0.4.0/DocxEdit-0.4.0.app.zip`
- `build/v0.4.0/SHA256SUMS`

## [0.3.5] — 2026-07-13 — TXT Export

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.3.5/DocxEdit-0.3.5.dmg`
- `build/v0.3.5/DocxEdit-0.3.5.app.zip`
- `build/v0.3.5/SHA256SUMS`

## [0.3.4] — 2026-07-13 — Autorecover Restore

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.3.4/DocxEdit-0.3.4.dmg`
- `build/v0.3.4/DocxEdit-0.3.4.app.zip`
- `build/v0.3.4/SHA256SUMS`

## [0.3.3] — 2026-07-13 — Find v2

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.3.3/DocxEdit-0.3.3.dmg`
- `build/v0.3.3/DocxEdit-0.3.3.app.zip`
- `build/v0.3.3/SHA256SUMS`

## [0.3.2] — 2026-07-13 — Custom Dictionary

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.3.2/DocxEdit-0.3.2.dmg`
- `build/v0.3.2/DocxEdit-0.3.2.app.zip`
- `build/v0.3.2/SHA256SUMS`

## [0.3.1] — 2026-07-13 — Auto Spell Language

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.3.1/DocxEdit-0.3.1.dmg`
- `build/v0.3.1/DocxEdit-0.3.1.app.zip`
- `build/v0.3.1/SHA256SUMS`

## [0.3.0] — 2026-07-12 — R04 Milestone

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.3.0/DocxEdit-0.3.0.dmg`
- `build/v0.3.0/DocxEdit-0.3.0.app.zip`
- `build/v0.3.0/SHA256SUMS`

## [0.2.7] — 2026-07-12 — Styles Sidebar

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.2.7/DocxEdit-0.2.7.dmg`
- `build/v0.2.7/DocxEdit-0.2.7.app.zip`
- `build/v0.2.7/SHA256SUMS`

## [0.2.6] — 2026-07-12 — Autorecover

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.2.6/DocxEdit-0.2.6.dmg`
- `build/v0.2.6/DocxEdit-0.2.6.app.zip`
- `build/v0.2.6/SHA256SUMS`

## [0.2.5] — 2026-07-12 — Section Breaks

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.2.5/DocxEdit-0.2.5.dmg`
- `build/v0.2.5/DocxEdit-0.2.5.app.zip`
- `build/v0.2.5/SHA256SUMS`

## [0.2.4] — 2026-07-12 — Bookmarks

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.2.4/DocxEdit-0.2.4.dmg`
- `build/v0.2.4/DocxEdit-0.2.4.app.zip`
- `build/v0.2.4/SHA256SUMS`

## [0.2.3] — 2026-07-12 — Header/Footer Variants

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.2.3/DocxEdit-0.2.3.dmg`
- `build/v0.2.3/DocxEdit-0.2.3.app.zip`
- `build/v0.2.3/SHA256SUMS`

## [0.2.2] — 2026-07-12 — Mirror Margins

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.2.2/DocxEdit-0.2.2.dmg`
- `build/v0.2.2/DocxEdit-0.2.2.app.zip`
- `build/v0.2.2/SHA256SUMS`

## [0.2.1] — 2026-07-12 — Document Properties

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.2.1/DocxEdit-0.2.1.dmg`
- `build/v0.2.1/DocxEdit-0.2.1.app.zip`
- `build/v0.2.1/SHA256SUMS`

## [0.2.0] — 2026-07-12 — R01/R03 Milestone

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.2.0/DocxEdit-0.2.0.dmg`
- `build/v0.2.0/DocxEdit-0.2.0.app.zip`
- `build/v0.2.0/SHA256SUMS`

## [0.1.102] — 2026-07-12 — Text Wrap Around Image

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.102/DocxEdit-0.1.102.dmg`
- `build/v0.1.102/DocxEdit-0.1.102.app.zip`
- `build/v0.1.102/SHA256SUMS`

## [0.1.101] — 2026-07-12 — Image Crop

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.101/DocxEdit-0.1.101.dmg`
- `build/v0.1.101/DocxEdit-0.1.101.app.zip`
- `build/v0.1.101/SHA256SUMS`

## [0.1.100] — 2026-07-12 — Ruler

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.100/DocxEdit-0.1.100.dmg`
- `build/v0.1.100/DocxEdit-0.1.100.app.zip`
- `build/v0.1.100/SHA256SUMS`

## [0.1.99] — 2026-07-12 — Language in Status Bar

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.99/DocxEdit-0.1.99.dmg`
- `build/v0.1.99/DocxEdit-0.1.99.app.zip`
- `build/v0.1.99/SHA256SUMS`

## [0.1.98] — 2026-07-12 — Image Rotate & Flip

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.98/DocxEdit-0.1.98.dmg`
- `build/v0.1.98/DocxEdit-0.1.98.app.zip`
- `build/v0.1.98/SHA256SUMS`

## [0.1.97] — 2026-07-12 — HEIC & SVG Import

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.97/DocxEdit-0.1.97.dmg`
- `build/v0.1.97/DocxEdit-0.1.97.app.zip`
- `build/v0.1.97/SHA256SUMS`

## [0.1.96] — 2026-07-12 — Regex Find & Replace

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.96/DocxEdit-0.1.96.dmg`
- `build/v0.1.96/DocxEdit-0.1.96.app.zip`
- `build/v0.1.96/SHA256SUMS`

## [0.1.95] — 2026-07-12 — Fit Page Width & Two Pages

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.95/DocxEdit-0.1.95.dmg`
- `build/v0.1.95/DocxEdit-0.1.95.app.zip`
- `build/v0.1.95/SHA256SUMS`

## [0.1.94] — 2026-07-12 — Paragraph Dialog

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.94/DocxEdit-0.1.94.dmg`
- `build/v0.1.94/DocxEdit-0.1.94.app.zip`
- `build/v0.1.94/SHA256SUMS`

## [0.1.93] — 2026-07-12 — Table Align Overhead Fix

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.93/DocxEdit-0.1.93.dmg`
- `build/v0.1.93/DocxEdit-0.1.93.app.zip`
- `build/v0.1.93/SHA256SUMS`

## [0.1.92] — 2026-07-12 — Visual Table Alignment

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.92/DocxEdit-0.1.92.dmg`
- `build/v0.1.92/DocxEdit-0.1.92.app.zip`
- `build/v0.1.92/SHA256SUMS`

## [0.1.91] — 2026-07-12 — Table Props Crash Fixed

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.91/DocxEdit-0.1.91.dmg`
- `build/v0.1.91/DocxEdit-0.1.91.app.zip`
- `build/v0.1.91/SHA256SUMS`

## [0.1.90] — 2026-07-12 — Row Height Unified

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.90/DocxEdit-0.1.90.dmg`
- `build/v0.1.90/DocxEdit-0.1.90.app.zip`
- `build/v0.1.90/SHA256SUMS`

## [0.1.89] — 2026-07-12 — Row Height From Layout

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.89/DocxEdit-0.1.89.dmg`
- `build/v0.1.89/DocxEdit-0.1.89.app.zip`
- `build/v0.1.89/SHA256SUMS`

## [0.1.88] — 2026-07-12 — Row Height Persistence

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.88/DocxEdit-0.1.88.dmg`
- `build/v0.1.88/DocxEdit-0.1.88.app.zip`
- `build/v0.1.88/SHA256SUMS`

## [0.1.87] — 2026-07-12 — Row Height Fix

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.87/DocxEdit-0.1.87.dmg`
- `build/v0.1.87/DocxEdit-0.1.87.app.zip`
- `build/v0.1.87/SHA256SUMS`

## [0.1.86] — 2026-07-12 — Row Height

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.86/DocxEdit-0.1.86.dmg`
- `build/v0.1.86/DocxEdit-0.1.86.app.zip`
- `build/v0.1.86/SHA256SUMS`

## [0.1.85] — 2026-07-12 — Table Header Row

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.85/DocxEdit-0.1.85.dmg`
- `build/v0.1.85/DocxEdit-0.1.85.app.zip`
- `build/v0.1.85/SHA256SUMS`

## [0.1.84] — 2026-07-12 — Translucent Selection

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.84/DocxEdit-0.1.84.dmg`
- `build/v0.1.84/DocxEdit-0.1.84.app.zip`
- `build/v0.1.84/SHA256SUMS`

## [0.1.83] — 2026-07-12 — Highlight Palette

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.83/DocxEdit-0.1.83.dmg`
- `build/v0.1.83/DocxEdit-0.1.83.app.zip`
- `build/v0.1.83/SHA256SUMS`

## [0.1.82] — 2026-07-12 — Highlight Color

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.82/DocxEdit-0.1.82.dmg`
- `build/v0.1.82/DocxEdit-0.1.82.app.zip`
- `build/v0.1.82/SHA256SUMS`

## [0.1.81] — 2026-07-12 — Painter in Clipboard Group

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.81/DocxEdit-0.1.81.dmg`
- `build/v0.1.81/DocxEdit-0.1.81.app.zip`
- `build/v0.1.81/SHA256SUMS`

## [0.1.80] — 2026-07-12 — Format Painter Buttons

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.80/DocxEdit-0.1.80.dmg`
- `build/v0.1.80/DocxEdit-0.1.80.app.zip`
- `build/v0.1.80/SHA256SUMS`

## [0.1.79] — 2026-07-12 — Format Painter

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.79/DocxEdit-0.1.79.dmg`
- `build/v0.1.79/DocxEdit-0.1.79.app.zip`
- `build/v0.1.79/SHA256SUMS`

## [0.1.78] — 2026-07-11 — Change Case

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.78/DocxEdit-0.1.78.dmg`
- `build/v0.1.78/DocxEdit-0.1.78.app.zip`
- `build/v0.1.78/SHA256SUMS`

## [0.1.77] — 2026-07-08 — Sub/Superscript

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.77/DocxEdit-0.1.77.dmg`
- `build/v0.1.77/DocxEdit-0.1.77.app.zip`
- `build/v0.1.77/SHA256SUMS`

## [0.1.76] — 2026-07-08 — Table Props Segmented Picker Crash

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.76/DocxEdit-0.1.76.dmg`
- `build/v0.1.76/DocxEdit-0.1.76.app.zip`
- `build/v0.1.76/SHA256SUMS`

## [0.1.75] — 2026-07-08 — Revert Visual Table Shift

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.75/DocxEdit-0.1.75.dmg`
- `build/v0.1.75/DocxEdit-0.1.75.app.zip`
- `build/v0.1.75/SHA256SUMS`

## [0.1.74] — 2026-07-08 — Table Align Deferred Apply

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.74/DocxEdit-0.1.74.dmg`
- `build/v0.1.74/DocxEdit-0.1.74.app.zip`
- `build/v0.1.74/SHA256SUMS`

## [0.1.73] — 2026-07-08 — Real Table Shift

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.73/DocxEdit-0.1.73.dmg`
- `build/v0.1.73/DocxEdit-0.1.73.app.zip`
- `build/v0.1.73/SHA256SUMS`

## [0.1.72] — 2026-07-08 — Table Width Round-Trip

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.72/DocxEdit-0.1.72.dmg`
- `build/v0.1.72/DocxEdit-0.1.72.app.zip`
- `build/v0.1.72/SHA256SUMS`

## [0.1.71] — 2026-07-08 — Table Props Crash Fix

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.71/DocxEdit-0.1.71.dmg`
- `build/v0.1.71/DocxEdit-0.1.71.app.zip`
- `build/v0.1.71/SHA256SUMS`

## [0.1.70] — 2026-07-07 — Table Alignment

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.70/DocxEdit-0.1.70.dmg`
- `build/v0.1.70/DocxEdit-0.1.70.app.zip`
- `build/v0.1.70/SHA256SUMS`

## [0.1.69] — 2026-07-07 — Image Alignment

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.69/DocxEdit-0.1.69.dmg`
- `build/v0.1.69/DocxEdit-0.1.69.app.zip`
- `build/v0.1.69/SHA256SUMS`

## [0.1.68] — 2026-07-07 — Image Click-to-Select

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.68/DocxEdit-0.1.68.dmg`
- `build/v0.1.68/DocxEdit-0.1.68.app.zip`
- `build/v0.1.68/SHA256SUMS`

## [0.1.67] — 2026-07-07 — Image Resize Handles

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.67/DocxEdit-0.1.67.dmg`
- `build/v0.1.67/DocxEdit-0.1.67.app.zip`
- `build/v0.1.67/SHA256SUMS`

## [0.1.66] — 2026-07-07 — VMerge Render Fix

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.66/DocxEdit-0.1.66.dmg`
- `build/v0.1.66/DocxEdit-0.1.66.app.zip`
- `build/v0.1.66/SHA256SUMS`

## [0.1.65] — 2026-07-07 — Merge Grid Dialog

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.65/DocxEdit-0.1.65.dmg`
- `build/v0.1.65/DocxEdit-0.1.65.app.zip`
- `build/v0.1.65/SHA256SUMS`

## [0.1.64] — 2026-07-07 — Merge Rectangle Fix

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.64/DocxEdit-0.1.64.dmg`
- `build/v0.1.64/DocxEdit-0.1.64.app.zip`
- `build/v0.1.64/SHA256SUMS`

## [0.1.63] — 2026-07-07 — Vertical Merge

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.63/DocxEdit-0.1.63.dmg`
- `build/v0.1.63/DocxEdit-0.1.63.app.zip`
- `build/v0.1.63/SHA256SUMS`

## [0.1.62] — 2026-07-07 — Table Context Menu

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.62/DocxEdit-0.1.62.dmg`
- `build/v0.1.62/DocxEdit-0.1.62.app.zip`
- `build/v0.1.62/SHA256SUMS`

## [0.1.61] — 2026-07-07 — Cell Merge

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.61/DocxEdit-0.1.61.dmg`
- `build/v0.1.61/DocxEdit-0.1.61.app.zip`
- `build/v0.1.61/SHA256SUMS`

## [0.1.60] — 2026-07-07 — Image Properties

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.60/DocxEdit-0.1.60.dmg`
- `build/v0.1.60/DocxEdit-0.1.60.app.zip`
- `build/v0.1.60/SHA256SUMS`

## [0.1.59] — 2026-07-07 — Symbol Insert Fix

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.59/DocxEdit-0.1.59.dmg`
- `build/v0.1.59/DocxEdit-0.1.59.app.zip`
- `build/v0.1.59/SHA256SUMS`

## [0.1.58] — 2026-07-07 — Symbols & Date/Time

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.58/DocxEdit-0.1.58.dmg`
- `build/v0.1.58/DocxEdit-0.1.58.app.zip`
- `build/v0.1.58/SHA256SUMS`

## [0.1.57] — 2026-07-06 — Auto-Link & Labels

### Изменения
- Подписи под кнопками Правописание (иконка+подпись, Word-like)
- автопревращение URL/email в ссылку по пробелу

### Артефакты
- `build/v0.1.57/DocxEdit-0.1.57.dmg`
- `build/v0.1.57/DocxEdit-0.1.57.app.zip`
- `build/v0.1.57/SHA256SUMS`

## [0.1.56] — 2026-07-06 — Review & Diagnostics

### Изменения
- Настройки страницы применяются к текущему документу
- ribbon Обзор (Правописание/Замены)
- Import Diagnostic (Отчёт об открытии — что не удалось восстановить из DOCX)

### Артефакты
- `build/v0.1.56/DocxEdit-0.1.56.dmg`
- `build/v0.1.56/DocxEdit-0.1.56.app.zip`
- `build/v0.1.56/SHA256SUMS`

## [0.1.55] — 2026-07-06 — Hyperlinks Polish

### Изменения
- Cmd+клик открывает ссылку
- в контекстном меню появились Гиперссылка/Удалить ссылку
- убраны Правописание/Замены/Ориентация/Речь

### Артефакты
- `build/v0.1.55/DocxEdit-0.1.55.dmg`
- `build/v0.1.55/DocxEdit-0.1.55.app.zip`
- `build/v0.1.55/SHA256SUMS`

## [0.1.54] — 2026-07-06 — Hyperlinks

### Изменения
- Гиперссылки (⌘K): вставка/редактирование/удаление, клик открывает в браузере, DOCX round-trip (w:hyperlink + rels)

### Артефакты
- `build/v0.1.54/DocxEdit-0.1.54.dmg`
- `build/v0.1.54/DocxEdit-0.1.54.app.zip`
- `build/v0.1.54/SHA256SUMS`

## [0.1.53] — 2026-07-06 — Images DOCX

### Изменения
- R03: DOCX round-trip inline-изображений — writer пишет word/media/imageN.ext + <w:drawing>/<a:blip> + rels + ContentType
- parser читает media/rels и восстанавливает Run.image через w:drawing/wp:extent/a:blip
- save→reopen верифицирован.

### Артефакты
- `build/v0.1.53/DocxEdit-0.1.53.dmg`
- `build/v0.1.53/DocxEdit-0.1.53.app.zip`
- `build/v0.1.53/SHA256SUMS`

## [0.1.52] — 2026-07-06 — Images Insert

### Изменения
- R03: inline-изображения — меню Вставка → «Изображение…» + ribbon-кнопка «photo» в группе «Иллюстрации»
- NSOpenPanel (PNG/JPEG/GIF/TIFF) → NSTextAttachment + U+FFFC вставляется атомарно (один шаг undo)
- модель
- DOCX round-trip намеренно отложен до v0.1.53 (renderRun пропускает картинки, чтобы U+FFFC не сломал document.xml).

### Артефакты
- `build/v0.1.52/DocxEdit-0.1.52.dmg`
- `build/v0.1.52/DocxEdit-0.1.52.app.zip`
- `build/v0.1.52/SHA256SUMS`

## [0.1.51] — 2026-07-06 — Tables Style

### Изменения
- R03: свойства таблицы (границы/заливка ячейки/ширина колонки) + фикс курсора после add/delete row/col (курсор остаётся в текущей ячейке, не top-left). Диалог «Свойства таблицы…» + DOCX round-trip для tblBorders/tcW/shd.

### Артефакты
- `build/v0.1.51/DocxEdit-0.1.51.dmg`
- `build/v0.1.51/DocxEdit-0.1.51.app.zip`
- `build/v0.1.51/SHA256SUMS`

## [0.1.50] — 2026-07-06 — Tables Ops

### Изменения
- R03: операции строк и столбцов таблицы (добавить строку выше/ниже, столбец слева/справа, удалить строку/столбец/таблицу) — меню Вставка → «Изменить таблицу» и группа кнопок на ribbon (dimmed при курсоре вне таблицы). Через applyTableEdit: from(attributed:) на span → мутация TableBlock → appendTable + один атомарный replaceCharacters (один шаг undo).

### Артефакты
- `build/v0.1.50/DocxEdit-0.1.50.dmg`
- `build/v0.1.50/DocxEdit-0.1.50.app.zip`
- `build/v0.1.50/SHA256SUMS`

## [0.1.49] — 2026-07-06 — Tables Live

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.49/DocxEdit-0.1.49.dmg`
- `build/v0.1.49/DocxEdit-0.1.49.app.zip`
- `build/v0.1.49/SHA256SUMS`

## [0.1.48] — 2026-07-06 — Titlebar Quick Access

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.48/DocxEdit-0.1.48.dmg`
- `build/v0.1.48/DocxEdit-0.1.48.app.zip`
- `build/v0.1.48/SHA256SUMS`

## [0.1.47] — 2026-07-06 — Print Fix

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.47/DocxEdit-0.1.47.dmg`
- `build/v0.1.47/DocxEdit-0.1.47.app.zip`
- `build/v0.1.47/SHA256SUMS`

## [0.1.46] — 2026-07-06 — Headers & Footers

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.46/DocxEdit-0.1.46.dmg`
- `build/v0.1.46/DocxEdit-0.1.46.app.zip`
- `build/v0.1.46/SHA256SUMS`

## [0.1.45] — 2026-07-05 — Real Pagination

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.45/DocxEdit-0.1.45.dmg`
- `build/v0.1.45/DocxEdit-0.1.45.app.zip`
- `build/v0.1.45/SHA256SUMS`

## [0.1.44] — 2026-07-05 — Page View Default & Status Bar

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.44/DocxEdit-0.1.44.dmg`
- `build/v0.1.44/DocxEdit-0.1.44.app.zip`
- `build/v0.1.44/SHA256SUMS`

## [0.1.43] — 2026-07-05 — Live List Renumber

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.43/DocxEdit-0.1.43.dmg`
- `build/v0.1.43/DocxEdit-0.1.43.app.zip`
- `build/v0.1.43/SHA256SUMS`

## [0.1.42] — 2026-07-05 — External Styles Import

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.42/DocxEdit-0.1.42.dmg`
- `build/v0.1.42/DocxEdit-0.1.42.app.zip`
- `build/v0.1.42/SHA256SUMS`

## [0.1.41] — 2026-07-05 — Style Alignment

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.41/DocxEdit-0.1.41.dmg`
- `build/v0.1.41/DocxEdit-0.1.41.app.zip`
- `build/v0.1.41/SHA256SUMS`

## [0.1.40] — 2026-07-05 — Styles & Page Sheet Fix

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.40/DocxEdit-0.1.40.dmg`
- `build/v0.1.40/DocxEdit-0.1.40.app.zip`
- `build/v0.1.40/SHA256SUMS`

## [0.1.39] — 2026-07-04 — Style Import & Word Defaults

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.39/DocxEdit-0.1.39.dmg`
- `build/v0.1.39/DocxEdit-0.1.39.app.zip`
- `build/v0.1.39/SHA256SUMS`

## [0.1.38] — 2026-07-04 — Page Borders

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.38/DocxEdit-0.1.38.dmg`
- `build/v0.1.38/DocxEdit-0.1.38.app.zip`
- `build/v0.1.38/SHA256SUMS`

## [0.1.37] — 2026-07-04 — Insert Menu & Style Fix

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.37/DocxEdit-0.1.37.dmg`
- `build/v0.1.37/DocxEdit-0.1.37.app.zip`
- `build/v0.1.37/SHA256SUMS`

## [0.1.36] — 2026-07-04 — Menus & Styles Editor

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.36/DocxEdit-0.1.36.dmg`
- `build/v0.1.36/DocxEdit-0.1.36.app.zip`
- `build/v0.1.36/SHA256SUMS`

## [0.1.35] — 2026-07-04 — Page View Fix & Insert

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.35/DocxEdit-0.1.35.dmg`
- `build/v0.1.35/DocxEdit-0.1.35.app.zip`
- `build/v0.1.35/SHA256SUMS`

## [0.1.34] — 2026-07-04 — Page View

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.34/DocxEdit-0.1.34.dmg`
- `build/v0.1.34/DocxEdit-0.1.34.app.zip`
- `build/v0.1.34/SHA256SUMS`

## [0.1.33] — 2026-07-04 — Styles Dialog

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.33/DocxEdit-0.1.33.dmg`
- `build/v0.1.33/DocxEdit-0.1.33.app.zip`
- `build/v0.1.33/SHA256SUMS`

## [0.1.32] — 2026-07-04 — Character Styles

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.32/DocxEdit-0.1.32.dmg`
- `build/v0.1.32/DocxEdit-0.1.32.app.zip`
- `build/v0.1.32/SHA256SUMS`

## [0.1.31] — 2026-07-04 — Go To

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.31/DocxEdit-0.1.31.dmg`
- `build/v0.1.31/DocxEdit-0.1.31.app.zip`
- `build/v0.1.31/SHA256SUMS`

## [0.1.30] — 2026-07-04 — Invisibles Fix

### Изменения
- см. CHANGELOG.md

### Артефакты
- `build/v0.1.30/DocxEdit-0.1.30.dmg`
- `build/v0.1.30/DocxEdit-0.1.30.app.zip`
- `build/v0.1.30/SHA256SUMS`

## [0.1.29] — 2026-07-04 — Invisibles & Statistics

### Изменения
- Показ непечатаемых символов (Вид → Непечатаемые символы, ⌘⇧8
- кнопка ¶ в закладке «Вид» ribbon) — через NSLayoutManager.showsInvisibleCharacters + showsControlCharacters, без правок модели/DOCX
- Статистика документа (Инструменты → Статистика документа…, ⌥⌘I) — модальное окно с страницами, словами, знаками с/без пробелов, абзацами, строками (базовые счётчики из DocumentStatisticsCalculator, строки/страницы из живого layout NSLayoutManager)

### Артефакты
- `build/v0.1.29/DocxEdit-0.1.29.dmg`
- `build/v0.1.29/DocxEdit-0.1.29.app.zip`
- `build/v0.1.29/SHA256SUMS`

## [0.1.28] — 2026-07-04 — Default Font Applied

### Изменения
- Фикс: новый документ печатал системным шрифтом (Helvetica) вместо заданного в настройках. NSTextView.typingAttributes для пустых документов теперь инициализируется из AppPreferences.defaultFontName/defaultFontSize (helper DocumentSession.currentDefaultAttributes()) — в makeNSView и в updateNSView после внешнего синка storage. DocumentSession.replace/reset передают preferredDefaultFont в toAttributedString. Также: настройка «Шрифт по умолчанию» перенесена с вкладки Основные на вкладку Шрифты рядом с «Шрифтом заголовков» — раздел «Шрифты для стилей»
- на вкладке Основные осталась только настройка размера шрифта

### Артефакты
- `build/v0.1.28/DocxEdit-0.1.28.dmg`
- `build/v0.1.28/DocxEdit-0.1.28.app.zip`
- `build/v0.1.28/SHA256SUMS`

## [0.1.27] — 2026-07-04 — Styles & Defaults Polish

### Изменения
- Стили абзацев теперь используют шрифт из настроек: «Обычный» берёт «Шрифт по умолчанию» с вкладки Основные, Заголовки 1–6 — новую настройку «Шрифт заголовков» на вкладке Шрифты (выбор из избранных или «(как у Обычный)»)
- фикс: вкладка «По умолчанию» показывала «не определено» для всех форматов — заменено на LSCopyDefaultRoleHandlerForContentType с фолбэком на временный файл, состояние вынесено в @StateObject (было теряется в @State при пересоздании вьюхи TabView)
- теперь видны реальные приложения (DocxEdit для DOCX/DOC/RTF, MD Editor для Markdown, TextEdit для txt), кнопки назначения и смены работают через NSWorkspace.setDefaultApplication с обработкой ошибок

### Артефакты
- `build/v0.1.27/DocxEdit-0.1.27.dmg`
- `build/v0.1.27/DocxEdit-0.1.27.app.zip`
- `build/v0.1.27/SHA256SUMS`

## [0.1.26] — 2026-07-04 — Paragraph Styles

### Изменения
- Стили абзацев (Обычный + Заголовки 1–6) — пикер в тулбаре в группе «Стили», подменю «Стиль» в меню Формат с шорткатами ⌘⌥0..6
- при применении стиль ставит размер шрифта, начертание bold/italic и интервалы до/после абзаца, сохраняя цвет и другие атрибуты рана
- в модели styleId хранится через кастомный NSAttributedString-атрибут
- DOCX round-trip: <w:pStyle> пишется в pPr, полный набор <w:style> с outlineLvl в styles.xml (база для оглавления в R07)

### Артефакты
- `build/v0.1.26/DocxEdit-0.1.26.dmg`
- `build/v0.1.26/DocxEdit-0.1.26.app.zip`
- `build/v0.1.26/SHA256SUMS`

## [0.1.25] — 2026-07-04 — Tab & Paste Plain

### Изменения
- Tab/Shift+Tab в многоуровневом списке меняют уровень вложенности (как в Word) — работает и на РУ-раскладке через textView(_:doCommandBy:)
- «Вставить с сохранением стиля» (⇧⌥⌘V) — новая команда, обезжиривает текст буфера и вставляет с текущим стилем абзаца
- доступна из меню Правка, кнопки тулбара (группа «Буфер обмена») и контекстного меню правой кнопки
- клавиатурный шорткат работает и на РУ-раскладке через NSEvent-монитор по физическому keyCode клавиши V (симметрично фиксу ADR-027 для ⌘]/⌘[)

### Артефакты
- `build/v0.1.25/DocxEdit-0.1.25.dmg`
- `build/v0.1.25/DocxEdit-0.1.25.app.zip`
- `build/v0.1.25/SHA256SUMS`

## [0.1.24] — 2026-07-02 — Multilevel Lists

### Изменения
- многоуровневые списки: формат маркера зависит от уровня вложенности (⌘]/⌘[ меняют и маркер: 1. → a. → i.)
- галерея вариантов многоуровневого списка в тулбаре и меню Формат (1. a. i. / 1. 1.1. 1.1.1. / 1) a) i) / I. A. 1. / • ○ ▪ / – • ◦), вариант применяется ко всему списку
- иерархическая нумерация (вложенный уровень с 1, родительская нумерация продолжается после подсписка, перенумерация всего блока при каждой правке списка)
- DOCX: numbering.xml пишет реальные форматы по уровням с корректными плейсхолдерами lvlText (раньше %1. на всех уровнях) и назначает numId по непрерывному блоку списка, а не по формату маркера (уровни одного списка больше не рвутся на разные списки в Word)
- About-панель снова показывает текущий релиз (в 0.1.23 запись о самом 0.1.23 не была добавлена)

### Артефакты
- `build/v0.1.24/DocxEdit-0.1.24.dmg`
- `build/v0.1.24/DocxEdit-0.1.24.app.zip`
- `build/v0.1.24/SHA256SUMS`

## [0.1.23] — 2026-07-01 — List Fixes

### Изменения
- фикс 4 багов списков v0.1.22: About не показывал текущий релиз, двойные маркеры (TextKit 2 авто-рендерит из textLists — форсирован TextKit 1), Cmd+Z не откатывал список (переход на атомарный replaceCharacters), ⌘]/⌘[ не срабатывали на РУ-раскладке (keyCode-независимый обработчик по charactersIgnoringModifiers)

### Артефакты
- `build/v0.1.23/DocxEdit-0.1.23.dmg`
- `build/v0.1.23/DocxEdit-0.1.23.app.zip`
- `build/v0.1.23/SHA256SUMS`

## [0.1.20] — 2026-06-30 — Page Settings

### Изменения
- настройки страницы в настройках (формат бумаги A3/A4/A5/Letter/Legal, ориентация, поля), WYSIWYG-вид страницы использует реальные поля из документа, функция печати (⌘P) через NSPrintInfo+NSPrintOperation, кнопка Печать в строке быстрого доступа
- RTF-экспорт (фикс ошибки 66062, добавлен documentType: .rtf)
- MD-экспорт: корректные таблицы, нет лишних пробелов в маркерах **/**

### Артефакты
- `build/v0.1.20/DocxEdit-0.1.20.dmg`
- `build/v0.1.20/DocxEdit-0.1.20.app.zip`
- `build/v0.1.20/SHA256SUMS`

## [0.1.19] — 2026-06-30 — DMG Visible

### Изменения
- фикс: DocxEdit.app был невидим в DMG (Finder выставлял флаг kIsInvisible=0x4000 в FinderInfo при AppleScript-стилизации окна)
- после AppleScript добавлен SetFile -a v для сброса флага невидимости
- теперь оба файла — DocxEdit.app и Applications — отображаются в Finder-окне DMG

### Артефакты
- `build/v0.1.19/DocxEdit-0.1.19.dmg`
- `build/v0.1.19/DocxEdit-0.1.19.app.zip`
- `build/v0.1.19/SHA256SUMS`

## [0.1.18] — 2026-06-30 — Open With Fix

### Изменения
- фикс «Открыть в приложении» из Finder: удалён NSDocumentClass из CFBundleDocumentTypes — macOS роутил открытие через NSDocumentController вместо application(open:) и файл тихо терялся
- DMG пересоздан на HFS+ с Finder-стилизацией (иконки и окно позиционированы через AppleScript)

### Артефакты
- `build/v0.1.18/DocxEdit-0.1.18.dmg`
- `build/v0.1.18/DocxEdit-0.1.18.app.zip`
- `build/v0.1.18/SHA256SUMS`

## [0.1.17] — 2026-06-30 — Finder Open

### Изменения
- фикс открытия файла из Finder (Открыть в приложении): гонка инициализации — application(open:) срабатывал раньше привязки session в .onAppear окна, из-за чего loadFromURL молча терялся
- теперь URL буферизуется в pendingOpenURL и догружается в session.didSet

### Артефакты
- `build/v0.1.17/DocxEdit-0.1.17.dmg`
- `build/v0.1.17/DocxEdit-0.1.17.app.zip`
- `build/v0.1.17/SHA256SUMS`

## [0.1.16] — 2026-06-30 — Quick Access

### Изменения
- дублирование пунктов меню на ribbon как в MS Word: строка быстрого доступа (Создать/Открыть/Сохранить/Отменить/Вернуть) над закладками
- на Главной группы Буфер обмена (Вырезать/Копировать/Вставить через цепочку респондеров) и Редактирование (Найти/Заменить через performTextFinderAction)
- меню Найти/Заменить подключены к контроллеру
- экспорт/сохранить как/недавние/о программе оставлены только в меню (в Word их на тулбаре нет)

### Артефакты
- `build/v0.1.16/DocxEdit-0.1.16.dmg`
- `build/v0.1.16/DocxEdit-0.1.16.app.zip`
- `build/v0.1.16/SHA256SUMS`

## [0.1.15] — 2026-06-30 — Document State

### Изменения
- имя файла в заголовке окна
- пометка * для несохранённых изменений (снимается после сохранения), плюс нативный индикатор правки и proxy-иконка
- подтверждение Сохранить/Не сохранять/Отмена при закрытии окна с несохранёнными изменениями (windowShouldClose с форвардингом делегата SwiftUI)
- markSaved уведомляет наблюдателей

### Артефакты
- `build/v0.1.15/DocxEdit-0.1.15.dmg`
- `build/v0.1.15/DocxEdit-0.1.15.app.zip`
- `build/v0.1.15/SHA256SUMS`

## [0.1.14] — 2026-06-30 — Ribbon

### Изменения
- тулбар переделан в ribbon с закладками (Главная/Разметка/Вид) в стиле MS Word for Mac — кастомный SwiftUI-вид вместо NSToolbar
- Главная в 2 строки (Шрифт: пикер+размер+Ж/К/Ч/З+цвет+очистить
- Абзац: выравнивание+отступы+интервал), Разметка: вид страницы A4, Вид: масштаб
- элементы не скрываются и не наезжают
- отменяет ADR-016 (NSToolbar) и ADR-005 (не-Ribbon)

### Артефакты
- `build/v0.1.14/DocxEdit-0.1.14.dmg`
- `build/v0.1.14/DocxEdit-0.1.14.app.zip`
- `build/v0.1.14/SHA256SUMS`

## [0.1.13] — 2026-06-30 — Save Fix

### Изменения
- критический фикс экспорта DOCX: addDirectoryToArchive передавал в ZIPFoundation каталог файла как relativeTo, из-за чего путь задваивался (docProps/docProps/core.xml) и сохранение падало с NSCocoaErrorDomain 260 для всех вложенных частей
- теперь relativeTo — корень staging
- проверено реальным экспортом+реимпортом (все части word/, docProps/, _rels/ с корректными путями)

### Артефакты
- `build/v0.1.13/DocxEdit-0.1.13.dmg`
- `build/v0.1.13/DocxEdit-0.1.13.app.zip`
- `build/v0.1.13/SHA256SUMS`

## [0.1.12] — 2026-06-30 — Paragraph Layout

### Изменения
- атрибуты абзаца подключены к NSTextView через NSParagraphStyle: межстрочный интервал (1.0/1.15/1.5/2.0), увеличение/уменьшение отступа (⌘]/⌘[) с регистрацией undo
- мост from(attributed:) переписан на поабзацный разбор и извлекает стиль абзаца обратно в модель (ParagraphAttributes.from(nsParagraphStyle:)) — выравнивание/отступы/интервалы больше не теряются при сохранении
- рефактор: общий хелпер mutateSelectedParagraphs, applyAlignment через него
- контролы абзаца в тулбаре и меню Формат

### Артефакты
- `build/v0.1.12/DocxEdit-0.1.12.dmg`
- `build/v0.1.12/DocxEdit-0.1.12.app.zip`
- `build/v0.1.12/SHA256SUMS`

## [0.1.11] — 2026-06-30 — Color Compare

### Изменения
- надёжное сравнение NSColor в color well через usingColorSpace(.sRGB) — устранено ложное неравенство между цветовыми пространствами и лишний цикл присваивания (фикс G)

### Артефакты
- `build/v0.1.11/DocxEdit-0.1.11.dmg`
- `build/v0.1.11/DocxEdit-0.1.11.app.zip`
- `build/v0.1.11/SHA256SUMS`

## [0.1.10] — 2026-06-30 — Undoable Format

### Изменения
- форматирование (B/I/U/S, цвет, шрифт, размер, выравнивание) теперь регистрируется в undo-менеджере NSTextView через shouldChangeText/didChangeText — Cmd+Z откатывает изменения и модель не рассинхронизируется
- рефактор: currentFont() больше не мутирует isBold/isItalic как побочный эффект (вынесено в чистую selectionBoldItalicTraits())
- упрощён нечитаемый тернарий обновления isBold/isItalic в toggleTrait

### Артефакты
- `build/v0.1.10/DocxEdit-0.1.10.dmg`
- `build/v0.1.10/DocxEdit-0.1.10.app.zip`
- `build/v0.1.10/SHA256SUMS`

## [0.1.9] — 2026-06-30 — Native Toolbar

### Изменения
- тулбар переведён на нативный NSToolbar (SwiftUI .toolbar) — авто-overflow в », элементы больше не наезжают друг на друга
- фикс первопричины: compression resistance у пикера шрифта
- фикс латентного краша при смене шрифта/размера на выделении (двойной endEditing в applyFont/applyFontSize)
- applyFontSize сбрасывает hasMixedSizes
- magnification пишется только при изменении

### Артефакты
- `build/v0.1.9/DocxEdit-0.1.9.dmg`
- `build/v0.1.9/DocxEdit-0.1.9.app.zip`
- `build/v0.1.9/SHA256SUMS`

## [0.1.8] — 2026-06-29 — Release Automation

### Изменения
- релиз одной командой через release.sh
- автогенерация секции CHANGELOG.md (update-changelog.sh)
- update-claude-md.sh переписан под текущий формат CLAUDE.md
- симлинк /Applications в DMG
- dev-скилл docxedit-dev

### Артефакты
- `build/v0.1.8/DocxEdit-0.1.8.dmg`
- `build/v0.1.8/DocxEdit-0.1.8.app.zip`
- `build/v0.1.8/SHA256SUMS`

## [0.1.1] — 2026-06-28 — Genesis + WYSIWYG-fix

Патч-релиз, устраняющий дефекты MVP: шрифты/цвета/B/I/U из исходного DOCX теперь отображаются корректно, форматирование применяется только к выделению, файлы открываются из Finder.

### Исправлено
- **WYSIWYG:** при открытии DOCX шрифты, размеры, начертания, цвета, подчёркивание и зачёркивание теперь отображаются в NSTextView как в исходном документе. Ранее весь текст показывался одним шрифтом/размером.
- **Selection-aware форматирование:** переключение B/I/U и смена шрифта/размера теперь применяются только к выделенному диапазону (или к `typingAttributes`, если выделения нет). Ранее атрибуты применялись ко всему документу.
- **Активация приложения:** DocxEdit корректно становится активным (frontmost) при запуске через Finder и при file-open; ранее окно могло остаться в фоне.
- **File-open из Finder:** реализованы `application(_:open:)`, `openFile:`, `openFiles:` и парсинг `CommandLine.arguments`. Контекстное меню «Открыть в программе → DocxEdit» и двойной клик по DOCX/DOC/RTF/MD теперь работают.
- **UTI-регистрация:** Info.plist дополнен `CFBundleDocumentTypes` с `LSHandlerRank=Owner` для DOCX, DOC, RTF, Markdown и `Alternate` для TXT; добавлены `UTExportedTypeDeclarations` для `net.daringfireball.markdown`. DocxEdit становится обработчиком по умолчанию для этих типов после установки.

### Добавлено
- **NSAttributedString-мост** (`DocumentModel+AttributedString.swift`): двусторонняя конвертация `DocumentModel` ↔ `NSAttributedString`. DocumentModel хранит runs с `CharacterAttributes`; runs содержат `.font`, `.foregroundColor`, `.underlineStyle`, `.strikethroughStyle`, `.baselineOffset`. Импорт разбивает `NSAttributedString` по `\n` на параграфы, экспорт сливает соседние runs с одинаковыми атрибутами.
- **`DocumentSession`** (shared `ObservableObject`): единый источник правды с `@Published bridge: NSDocumentBridge` и `@Published attributedText: NSAttributedString`. Заменяет прямую связь AppDelegate ↔ DocumentController.
- **Coordinator (NSViewRepresentable.Coordinator)** подписан на `NotificationCenter` для команд форматирования (B/I/U/шрифт/размер). Команды диспетчеризуются из AppDelegate → Coordinator → DocumentController, развязывая lifecycle.
- **Версионирование артефактов:** структура `build/v0.x.y/` для каждого релиза; `build/DocxEdit.app` — текущий dev-бандл. v0.1.0 сохранён в `build/v0.1.0/`.

### Артефакты
- `build/v0.1.1/DocxEdit-0.1.1.dmg` (Universal)
- `build/v0.1.1/DocxEdit-0.1.1-macos14-arm64.dmg`
- `build/v0.1.1/DocxEdit-0.1.1-macos14-x86_64.dmg`
- `build/v0.1.1/DocxEdit-0.1.1.app.zip`
- `build/v0.1.1/SHA256SUMS`
- `build/v0.1.0/` — предыдущий релиз

## [0.1.0] — 2026-06-26 — Genesis (R01, MVP)

### Добавлено
- Базовая модель документа `DocumentModel` (разделы, параграфы, раны, атрибуты).
- Модули импорта/экспорта: **DOCX**, **RTF**, **Markdown**, **TXT** (с автоопределением кодировки).
- Экспорт в **PDF** через CoreText.
- Печать (Cmd+P) с предпросмотром.
- macOS-приложение: SwiftUI-окно с NSTextView (TextKit 2), тулбар «Главная», строка состояния.
- Стандартные меню macOS в стиле MS Word для Mac: «Файл», «Правка», «Формат», «Вид», «Окно», «Справка».
- Базовое форматирование: B/I/U, шрифт, размер, цвет, выравнивание, межстрочный интервал, отступы.
- Списки (маркированные, нумерованные) с базовой вложенностью.
- Настройки страницы: A4/Letter/A3/A5/Legal, книжная/альбомная ориентация, поля.
- Недавние файлы, drag & drop.
- Скрипты сборки и выпуска: `build.sh`, `make-dmg.sh`, `notarize.sh`, `update-claude-md.sh`, `release.sh`.
- Базовые тесты XCTest (ядро + IO + encoding).

### Технические детали
- Swift 5.9+, macOS 14 Sonoma+
- Swift Package Manager + готовый `Package.swift` с локальными модулями
- Universal Binary (arm64 + x86_64)
- Зависимости: ZIPFoundation 0.9.20, swift-markdown 0.8.0

### Известные ограничения
- DOCX: ограниченная поддержка OOXML — только базовые элементы
- Таблицы, изображения, гиперссылки — в следующих релизах
- Полный список — в `REQUIREMENTS.md`, раздел MVP
