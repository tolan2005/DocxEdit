# Changelog DocxEdit

Все значимые изменения документируются здесь. Формат основан на [Keep a Changelog](https://keepachangelog.com/),
проект придерживается [Semantic Versioning](https://semver.org/).

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
