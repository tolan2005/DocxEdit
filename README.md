# DocxEdit

> **Version:** 1.1.0
> **Platform:** macOS 14 Sonoma+ (arm64)
> **Downloads:** <https://github.com/tolan2005/DocxEdit/releases>

Free, native macOS document editor — light, private, offline by default. Reads and writes `.docx`, `.doc`, `.rtf`, `.odt`, `.md`, `.txt`; exports to `.pdf`.

## Download

Latest release: <https://github.com/tolan2005/DocxEdit/releases/latest>

Grab `DocxEdit-<version>.dmg`, open, drag `DocxEdit.app` into `/Applications`, and launch.

**First launch warning.** The build is currently ad-hoc signed (not notarized). macOS Gatekeeper will refuse the first launch. Workaround: **right-click the app → Open → Open**. From then on, launches proceed normally.

Verify the download against `SHA256SUMS` (also attached to every release):

```
shasum -a 256 -c SHA256SUMS
```

## Highlights

- **DOCX first.** Real OOXML round-trip — styles, lists, tables, images, hyperlinks, comments, footnotes, cross-references, track changes, page numbers, headers/footers, TOC.
- **Full-featured editor.** Ribbon with tabs (Home / Insert / Layout / Review / View), WYSIWYG page view with real A4/Letter sheets + shadows, real pagination, printing.
- **Formatting.** Bold / italic / underline / strikethrough / sub-super, character styles, paragraph styles (Normal + Headings 1–6), fonts, colors, highlight palette, alignment, indents, line spacing, format painter.
- **Structure.** Multilevel lists, tables (merge/split, borders, shading, header rows), inline images (PNG/JPEG/HEIC/SVG, rotate/crop/wrap around text), hyperlinks (⌘K + Cmd-click), bookmarks, cross-references, footnotes, section breaks, headers & footers with placeholders.
- **Review.** Reading mode, comments with sidebar, track changes, spelling + grammar check, custom dictionary, auto-language detection.
- **Multi-format I/O.** Import: docx, doc, rtf, odt, md, txt. Export: docx, rtf, odt, md, txt, pdf.
- **Native.** Swift/SwiftUI + AppKit. ~5 MB app, offline by default, no telemetry.
- **Auto-update.** Checks GitHub Releases on launch (configurable in Preferences → Основные → Обновления). SHA256-verified download.
- **Localization.** Russian (base) + English.

## Auto-update

DocxEdit checks this repository on launch for a newer version. When one is available, a banner shows the release notes and offers **Install now / Later / Skip this version**.

Frequency is user-controlled in **Preferences → Основные → Обновления**:

- «При запуске» (default)
- «Раз в день»
- «Раз в неделю»
- «Никогда» — no network requests

Only public GitHub Releases API is contacted (`api.github.com/repos/tolan2005/DocxEdit/releases/latest`). No telemetry, no analytics, no identifiers in User-Agent.

## System requirements

- macOS 14 Sonoma or newer
- Apple Silicon (arm64). Universal binary planned.
- ~10 MB free disk

## License

MIT.

## Trademarks

DocxEdit is an independent project. It is **not affiliated with, endorsed by, or sponsored by Microsoft Corporation, Apple Inc., The Document Foundation, or any other third party**. `Microsoft`, `Word`, `Office`, `Excel`, `PowerPoint`, `Windows`, `macOS`, `Apple`, `Pages`, and other product or company names mentioned in the documentation or UI (for example, as file-type descriptions) are trademarks or registered trademarks of their respective owners; they are used here solely in descriptive/nominative contexts.

DocxEdit reads and writes the Office Open XML file format as defined by [ECMA-376](https://ecma-international.org/publications-and-standards/standards/ecma-376/) / ISO/IEC 29500, which Microsoft has covered under the [Open Specification Promise](https://learn.microsoft.com/en-us/openspecs/dev_center/ms-devcentlp/1c24c7c8-28b0-4ce1-a47d-95fe1ff504bc). ODT support targets the [OpenDocument Format](https://www.oasis-open.org/standards/#opendocumentv1.3) (OASIS / ISO/IEC 26300).

## Issues

Bug reports and feature requests: <https://github.com/tolan2005/DocxEdit/issues>
