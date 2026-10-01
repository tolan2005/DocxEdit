#!/bin/bash
# UI-тесты гоняют SwiftPM-сборку (как в релизе): бинарник из Xcode при cold-start с файлом
# не получает окна от SwiftUI. Копия бандла получает отдельный bundle id, чтобы не трогать
# настройки установленного DocxEdit.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release --scratch-path build/.swift-build
WORK="$ROOT/build/uitest"
rm -rf "$WORK/DocxEdit.app"
mkdir -p "$WORK"
APP="$WORK/DocxEdit.app"
ditto build/DocxEdit.app "$APP"
cp build/.swift-build/release/DocxEdit "$APP/Contents/MacOS/DocxEdit"
plutil -replace CFBundleIdentifier -string app.docxedit.DocxEdit.uitestspm "$APP/Contents/Info.plist"
codesign -f -s - "$APP" >/dev/null 2>&1 || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"

(cd UITests && xcodegen generate --spec project.yml >/dev/null)
TEST_RUNNER_DOCXEDIT_APP="$APP" xcodebuild test \
    -project UITests/DocxEditUI.xcodeproj -scheme DocxEditUI \
    -destination 'platform=macOS' -derivedDataPath "${TMPDIR:-/tmp}/docxedit-uitest-dd" "$@"
