# DESIGN_HEADER_FOOTER.md — Точная работа со сложными колонтитулами

> Статус: v1.5.1 в работе. Дата: 2026-08-10. Триггер: 133.docx (графика и
> текстбоксы в колонтитулах молча отрезаются при open/save).

## 1. Диагноз (133.docx)

Файл содержит first/even/default колонтитулы (header1-3, footer1-3) с плавающей
графикой (`wp:anchor` + blip → media/image1-3.png), текстовыми фреймами
(`txbxContent`, вертикальный текст), границами (`pBdr`) и таб-стопами (`w:tabs`).

Текущие проблемы DocxEdit (проверено импортером):
1. Графика/текстбоксы/рамки отбрасываются **молча** — парсер колонтитулов не
   пишет в `ImportReport` (отчёт пуст для этого файла).
2. Текст текстбоксов склеивается и дублируется (`ArgentinaAustralia…` × 2).
3. Слоты колонтитулов мапятся **по имени файла** (header1→default, header2→first,
   header3→even — конвенция нашего writer). В 133.docx реальный маппинг по rels:
   header1=even, header2=default, header3=first — слоты **перепутаны**.
4. `differentOddEven=true` выставляется по наличию части, хотя
   `<w:evenAndOddHeaders/>` в settings.xml отсутствует — рисуем even там, где
   Word его не показывает.
5. При ⌘S колонтитулы регенерируются из текста — графика теряется навсегда,
   даже если пользователь колонтитул не редактировал.

## 2. Релизы

### v1.5.1 — Lossless passthrough + отчёт + слоты по rels ✅ (2026-08-10, выпущен)
- **Модель (DocxCore)**: `DocumentModel.preservedHeaderFooter: [String: PreservedHFPart]`
  (слоты headerDefault/headerFirst/headerEven/footer*) — сырые байты части,
  её `.rels` (target'ы media переписаны на `media/hfp_<slot>_<name>` во
  избежание коллизий с генерируемыми `media/imageN`) и media-данные.
  `DocumentModel.headerFooterEdited: Bool` (default false; выставляется в
  `NSDocumentBridge.setHeaderFooter`; проносится через `applyAttributed`).
- **Импорт**: слоты резолвятся через `document.xml.rels` + `headerReference`
  type/r:id в sectPr (фиксит перепутанные слоты третьих файлов; fallback — по
  имени файла для наших документов). Заполняется preservedHeaderFooter.
- **Экспорт**: если `!headerFooterEdited` и слот имеет preserved-часть — пишем
  сырые байты (+rels+media, Target = оригинальное имя части) вместо генерации.
  Если редактировался — текущая регенерация (графика теряется, но текст —
  пользовательский; осознанный trade-off v1).
- **ImportReport**: для каждой hf-части с `<w:drawing`/`<w:pict`/`txbxContent`/
  `<w:tbl`/`pBdr`/`w:tabs` — запись «сохраняется при пересохранении, в редакторе
  отображается упрощённо».
- Тесты: round-trip 133-подобного пакета (zip с графикой в header) — байты
  header-части и media переживают export; edited=true → регенерация; слот-маппинг.

### v1.5.2 — Качество извлечения текста колонтитулов ✅ (2026-08-11, выпущен)
- Дедупликация текстбоксов: mc:AlternateContent Fallback пропускается (список
  стран читался дважды); абзацы/табы разделяются пробелом (не склеиваются).
- differentOddEven/titlePg — по авторитетным источникам (сделано ещё в v1.5.1).
- Generic passthrough прочих частей: customXml/*, word/theme/*, fontTable.xml,
  webSettings.xml, endnotes.xml, docProps/app.xml + их Content-Type;
  settings.xml пишется из оригинала с инжекцией evenAndOddHeaders.
- Дедупликация/разделители текстбоксов; не склеивать paragraphs без пробелов.
- `differentOddEven` — только по `<w:evenAndOddHeaders/>` в settings.xml;
  `differentFirstPage` — по `<w:titlePg/>` в sectPr (не по наличию части).
- Generic passthrough прочих неизвестных частей пакета: `customXml/*`,
  `word/theme/*`, `word/fontTable.xml`, `word/webSettings.xml`, `word/endnotes.xml`
  (по тому же механизму preservedParts, что и v1.5.1).

### v1.5.3 — Рендер изображений колонтитулов ✅ (2026-08-11, выпущен)
- `HFImage` placements в PreservedHFPart: парсинг wp:anchor (positionH/V
  posOffset, wp:extent, r:embed → hfp_media) при импорте.
- DocxTextView.hfImages по слотам; drawBackground рисует картинки в полях
  каждого листа (варианты first/even/default) — экран + печать.
- От первоначальной идеи «модель колонтитула как [Paragraph]» отказались:
  полная переработка HeaderFooter (12 текстовых полей + диалог + регенерация)
  не окупается, т.к. passthrough уже гарантирует сохранность, а рендер картинок
  закрывает видимость. Текстбоксы — по-прежнему только текстом (бэклог).
- Несколько абзацев, табы (`w:tabs`), `pBdr` (линия под колонтитулом) —
  парсинг/рендер/round-trip. `w:drawing` в колонтитулах → картинки через rels
  hf-части, отрисовка в `DocxTextView.drawBackground`.

### Бэклог формата (по частоте в реальных файлах, из §2 анализа 2026-08-10)
- ~~P0: колонки `w:cols`; таб-стопы `w:tabs`~~ — **сделано в v1.5.4** (sectPr
  extras passthrough; tabStops в модели/мосте/DOCX round-trip). Рендер колонок
  в редакторе — отдельная задача.
- ~~P0: сложные поля `w:fldChar` (живой TOC/PAGEREF/SEQ); границы абзацев `w:pBdr`~~
  — **сделано в v1.5.5 (pBdr) и v1.5.6 (fldChar, одноабзацные)**. Многоабзацные
  поля (TOC без SDT) — как раньше, результат+отчёт.
- ~~P1: водяные знаки (VML `w:pict` в колонтитулах)~~ — **сделано в v1.5.14**
  (парсинг v:textpath/v:imagedata + рендер на листах и при печати);
  ~~`mc:AlternateContent` fallback~~ — **сделан в v1.5.7**; плавающие картинки
  в теле — **сделано в v1.5.12** (рендер + обтекание + драг).
- ~~P2: концевые сноски endnotes~~ — **сделано в v1.5.15** (импорт/экспорт +
  панель; создание в UI не добавлено); `w:start`/`lvlOverride` в нумерации;
  стили таблиц `w:tblStyle`; вертикальный текст в ячейках.
- P3: OLE `w:object`; OMML `m:oMath`; буквица `framePr`; границы страницы `pgBorders`.
