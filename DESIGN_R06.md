# DESIGN R06 «Review» — комментарии, режим «Чтение», track changes

> Написан по итогам код-ревизии R05 (2026-07-13), ДО начала реализации R06.
> Фиксирует два архитектурных решения, чтобы R06 не усугубил существующий долг:
> (1) новые подсистемы — отдельными объектами, не в DocumentController;
> (2) идентичность фрагментов — через атрибуты, а не через позиции,
> из-за полной пересборки модели на каждую правку (ADR-010/024).

## 1. Контекст: почему нельзя «как раньше»

**DocumentController — 3139 строк** и растёт с каждой фичей. Форматирование,
поиск, списки, таблицы, изображения, закладки, спелчек, autorecover — всё в
одном классе. Для R06 это стало бы +600–800 строк (комментарии + track changes
+ режим чтения).

**Полная пересборка модели**: `DocumentSession.applyAttributed` вызывает
`DocumentModel.from(attributed:)` на каждую правку — модель не имеет
стабильной идентичности фрагментов между правками. Любой дизайн R06,
привязывающий комментарий/правку к «позиции в модели» или «индексу параграфа»,
сломается при первом же нажатии клавиши.

## 2. Правило архитектуры R06: движки-компаньоны

Каждая подсистема R06 — отдельный `final class` в своём файле, владеющий своей
логикой целиком. `DocumentController` только держит ссылки и пробрасывает
`textView`:

```swift
@MainActor final class CommentsEngine {
    weak var textView: NSTextView?
    weak var session: DocumentSession?
    // add/remove/resolve/list/goTo — вся логика здесь
}

@MainActor final class TrackChangesEngine {
    weak var textView: NSTextView?
    var isRecording: Bool
    // перехват правок, accept/reject, обход изменений
}
```

В `DocumentController` добавляются ровно 2 строки на движок:
```swift
let comments = CommentsEngine()
let trackChanges = TrackChangesEngine()
```
и инициализация ссылок в `attach(session:)`. Notification-обработчики в
Coordinator зовут `controller.comments.add(...)` — не методы контроллера.

**Запрещено** в R06: добавлять `@Published`-поля и методы подсистем R06
непосредственно в DocumentController (кроме двух ссылок выше).

## 3. Идентичность через атрибуты (решение проблемы пересборки)

Паттерн уже проверен в проекте трижды: `.docxEditStyleId` (ADR-030),
`.docxEditBookmark` (v0.2.4), `.docxEditRowHeader` (v0.1.85). Custom-атрибут
NSAttributedString живёт НА СИМВОЛАХ, поэтому переживает пересборку модели,
undo/redo, копирование — идентичность носит сам текст, а не индекс.

### Комментарии

- Custom key `.docxEditCommentId: String` (UUID) на диапазоне текста.
- Содержимое комментариев — в модели: `DocumentModel.comments:
  [CommentThread]`, где `CommentThread { id, author, date, text, replies,
  resolved }`. `applyAttributed` сохраняет `comments` из старой модели
  (тот же приём, что pageSettings/metadata/styles).
- Осиротевшие треды (текст с id удалён) — не удалять автоматически; панель
  комментариев помечает «привязка потеряна» (как в Word).
- DOCX round-trip: `word/comments.xml` + `<w:commentRangeStart w:id/>`,
  `<w:commentRangeEnd/>`, `<w:commentReference/>` в ранах. Парсер v0.1.56 уже
  считает эти элементы в ImportReport — заменить учёт на реальный импорт.

### Track changes

- Custom keys `.docxEditInsertion` / `.docxEditDeletion: RevisionInfo`
  (author, date, revId). Вставленный текст получает `.docxEditInsertion`;
  удалённый НЕ удаляется из storage, а помечается `.docxEditDeletion` +
  визуально strikethrough (как в Word).
- Перехват правок: `textView(_:shouldChangeTextIn:replacementString:)` в
  Coordinator делегирует `TrackChangesEngine.interceptEdit(...)` при
  `isRecording` — вставка помечается, удаление конвертируется в пометку.
  Это единственная точка входа всех правок → перехват полный.
- Accept: снять атрибут (для deletion — реально удалить текст).
  Reject: наоборот. Оба — атомарный `replaceCharacters` под
  `shouldChangeText` (паттерн undo ADR-027/028).
- Рендер: цвет по автору + полоса на полях (`DocxTextView.drawBackground`
  уже рисует в полях — колонтитулы, ADR-038).
- DOCX round-trip: `<w:ins>`/`<w:del>` вокруг ранов (парсер уже считает их
  в ImportReport → заменить на импорт), `w:rPrChange` — вне скоупа R06 v1
  (только текстовые вставки/удаления, не изменения форматирования).

### Режим «Чтение»

- Полностью view-слой: `textView.isEditable = false` + скрытие ribbon +
  увеличенные поля. Модели не касается. Логика — в `DocumentController`
  допустима (это переключатель вида, как isPageView, а не подсистема).

## 4. Инкрементальная синхронизация модели — отложено осознанно

Правильное решение долга §7 («полная пересборка на каждую правку») —
инкрементальный apply: правка диапазона storage → правка соответствующего
диапазона модели. Это большая работа (маппинг positions ↔ model-path,
все 30+ мутирующих операций). Дизайн выше выбран так, чтобы R06 **не
зависел** от неё: атрибутная идентичность работает и при полной пересборке.
Возврат к теме — R08 «Performance & Diagnostics», где инкрементальность
даст и производительность на больших документах.

## 5. Порядок реализации R06 (черновик релизов)

1. v0.4.x Reading Mode — режим чтения (дешёвый, изолированный).
2. v0.4.x CommentsEngine: модель + атрибут + панель справа (паттерн
   StylesSidebarView) + вставка/удаление/resolve.
3. v0.4.x Comments DOCX round-trip (comments.xml + commentRange*).
4. v0.4.x TrackChangesEngine: запись вставок/удалений + рендер.
5. v0.4.x Accept/Reject (по одному и «все») + панель обхода правок.
6. v0.4.x Track changes DOCX round-trip (w:ins/w:del).
7. v0.5.0 R06 Milestone.

Попутно в R06 (из ревизии R05): дебаунс `detectLanguageAroundCaret` и
`countMatches`; флаг ручного выбора языка спелчека (не перетирать
автодетектом); резолв типов колонтитулов через rels для сторонних файлов.
