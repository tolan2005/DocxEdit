# DocxEdit

> **Version:** 1.0.0 (R10 Milestone — Public Release)
> **Repository:** <https://github.com/tolan2005/DocxEdit>
> **Platform:** macOS 14 Sonoma+ (Universal — arm64 + x86_64)

Free, native macOS document editor — light, private, offline by default. Reads and writes `.docx`, `.doc`, `.rtf`, `.odt`, `.md`, `.txt`; exports to `.pdf`.

## Highlights

- **DOCX first**. Real OOXML round-trip, not just AppKit's `NSAttributedString` — custom writer/parser (see `Sources/DocxIO`) supports styles, lists, tables, images, hyperlinks, comments, footnotes, cross-references, track-changes, page numbers, headers/footers, TOC as `<w:sdt>`.
- **Full-featured editor**. Ribbon with tabs (Home / Insert / Layout / Review / View). WYSIWYG page view with real A4/Letter sheets + shadows, real pagination, printing.
- **Formatting**. Bold / italic / underline (single/double/dotted/dashed) / strikethrough / sub-super, character styles (Strong/Emphasis/Code), paragraph styles (Normal + Headings 1–6), custom font/size, colors, highlight palette, alignment, indents, line spacing, format painter.
- **Structure**. Multilevel lists (6 gallery presets, live renumber), tables (merge/split, borders, shading, per-row height, header rows, alignment on page), inline images (PNG/JPEG/HEIC/SVG, rotate/crop/wrap around text), hyperlinks (⌘K + Cmd-click to open), bookmarks, cross-references, footnotes, section breaks, headers & footers with placeholders.
- **Review**. Reading mode, comments with sidebar and DOCX round-trip, track changes (insertions/deletions/attribute revisions) with panel navigation, spelling + grammar check, custom dictionary, auto-language detection.
- **Diagnostics**. Import Report (what OOXML we couldn't restore), Performance metrics (open/save latency + throughput), Document Statistics.
- **Multi-format I/O**. Import: docx, doc, rtf, odt, md, txt (with encoding detection: UTF-8/16, Windows-1251, KOI8-R). Export: docx, rtf, odt, md, txt, pdf.
- **Native**. Swift/SwiftUI + AppKit. No Electron, no Java. ~5 MB app, offline by default, no telemetry.
- **Localization**. Russian (base) + English (in progress — menus and dialogs translated in R10a/b).

## Architecture

```
Sources/
├── DocxCore/         # Document model (DocumentModel, Section, Paragraph, Run, ...)
├── DocxIO/           # DOCX import/export (own OOXML parser/writer + ZIPFoundation)
├── RtfIO/            # RTF and ODT (via NSAttributedString document types)
├── MarkdownIO/       # Markdown (via swift-markdown / cmark)
├── PdfExporter/      # PDF (via CoreText)
├── EncodingDetector/ # Text encoding auto-detection
└── DocxEdit/         # Application (SwiftUI + AppKit)
    ├── Sources/                            # Swift files
    └── Sources/Resources/{ru,en}.lproj/    # Localizations
```

Design docs: [`DESIGN_R06.md`](./DESIGN_R06.md), [`DESIGN_pagination.md`](./DESIGN_pagination.md), [`CLAUDE.md`](./CLAUDE.md) (project memory — the source of truth for what's done and why).

## Build

Requirements: macOS 14+ with **full Xcode 15+** (Command Line Tools don't include XCTest, tests will be skipped).

```bash
# 1. Debug build (fast, no packaging)
swift build

# 2. Run tests (204 tests, ~1.4 s)
swift test

# 3. Full release (build + .app bundle + smoke test + .zip + .dmg + SHA256SUMS + CHANGELOG update)
./scripts/release.sh 0.7.2 "R10b — Dialog Localization"

# Artifacts land in build/vX.Y.Z/ — versioned, previous releases stay put.
```

The release script gates on tests (must pass if XCTest is available) and on `AboutReleaseNotes.recent` containing the outgoing version (a guard against forgetting to update the About panel changelog).

## Development

```bash
# Open in Xcode
xed .

# Or in VS Code with sourcekit-lsp
code .
```

Contribution model: each meaningful change is one release. Increments follow semver — patch (0.x.Y) per feature/fix, minor (0.X.0) per milestone (Rxx closed). The CLAUDE.md §5 «Release history» is auto-updated by `scripts/release.sh`.

## Testing standard

Five test targets, 204 tests, ~1.4 s full run:

- **DocxCoreTests** — model, encoding, Codable JSON round-trip
- **DocxIOTests** — DOCX round-trip, fuzz tests, real corpus (21–24.docx), Unicode edges, cross-references, footnotes, TOC, track changes
- **RtfIOTests** — RTF + ODT round-trip
- **MarkdownIOTests** — MD import/export
- **DocxEditTests** — Bridge round-trip, property-based (seeded), snapshot tests (via pointfreeco/swift-snapshot-testing)

Snapshot fixtures live in `Tests/DocxEditTests/__Snapshots__/`. Real .docx corpus in `Tests/DocxIOTests/Fixtures/`. See CLAUDE.md §9 for the standard on where to add each new test.

## Known limitations

- **Multi-document tabs**: single global `DocumentSession` — one window edits one document; opening a second file replaces the current one. Real multi-doc tabs require a session-per-window refactor (post-1.0).
- **Complex TOC field**: written as `<w:sdt>` structured document tag with `docPartGallery="Table of Contents"` — mainstream word processors accept it and offer Update Table, but doesn't rebuild via its own PAGEREF/HYPERLINK sub-fields. Our TOC is a rendered snapshot with auto-refresh on heading edits.
- **Track-changes rPrChange**: preserves the fact of an attribute revision (author/date/id) through DOCX round-trip, but old attributes (`<w:rPr/>` inside `<w:rPrChange>`) are written empty — reviewers see the balloon signature without a proper before/after diff.
- **ODT**: goes through `NSAttributedString.DocumentType.openDocument` — tables collapse to tab-separated paragraphs, track changes / comments / footnotes are lost. Full native ODT `content.xml` writer is a post-1.0 task.
- **English localization**: menus and main dialogs translated in v0.7.1/v0.7.2. A minority of dialog strings, tooltips, error messages still render in Russian even under English system language — being closed release-by-release in R10.

## Signing & distribution

`scripts/notarize.sh` is present but requires an Apple Developer ID. Local dev builds are ad-hoc signed (Gatekeeper will warn on first launch — right-click → Open). Public v1.0.0 release will be Developer-ID-signed and notarized.

## License

MIT — see [`LICENSE`](./LICENSE).

## Trademarks

DocxEdit is an independent project. It is **not affiliated with, endorsed by, or sponsored by Microsoft Corporation, Apple Inc., The Document Foundation, or any other third party**. `Microsoft`, `Word`, `Office`, `Excel`, `PowerPoint`, `Windows`, `macOS`, `Apple`, `Pages`, and other product or company names mentioned in the source, documentation, or UI (for example, as file-type descriptions or reference behaviour) are trademarks or registered trademarks of their respective owners; they are used here solely in descriptive/nominative contexts.

DocxEdit reads and writes the Office Open XML file format as defined by [ECMA-376](https://ecma-international.org/publications-and-standards/standards/ecma-376/) / ISO/IEC 29500, which Microsoft has covered under the [Open Specification Promise](https://learn.microsoft.com/en-us/openspecs/dev_center/ms-devcentlp/1c24c7c8-28b0-4ce1-a47d-95fe1ff504bc). ODT support targets the [OpenDocument Format](https://www.oasis-open.org/standards/#opendocumentv1.3) (OASIS / ISO/IEC 26300).

## Documentation

- [`REQUIREMENTS.md`](./REQUIREMENTS.md) — full specification and release plan
- [`CLAUDE.md`](./CLAUDE.md) — project memory (single source of truth for architecture, ADRs, feature status)
- [`CHANGELOG.md`](./CHANGELOG.md) — release history
- [`DESIGN_R06.md`](./DESIGN_R06.md) — Review-features design (comments, track changes)
- [`DESIGN_pagination.md`](./DESIGN_pagination.md) — pagination approach (single NSTextView + `PaginatedTextContainer`)
