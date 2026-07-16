#!/usr/bin/env bash
#
# build.sh — сборка релизной версии DocxEdit.
#
# Использование:
#   ./scripts/build.sh [VERSION] [BUILD_NUMBER]
#
# Параметры:
#   VERSION       — семантическая версия (по умолчанию берётся из последнего git-тега v*)
#   BUILD_NUMBER  — монотонно растущий номер сборки (по умолчанию timestamp)
#
# Результат:
#   ./build/DocxEdit.app
#

set -euo pipefail

VERSION="${1:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo '0.1.0')}"
BUILD_NUMBER="${2:-$(date +%Y%m%d%H%M%S)}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${REPO_ROOT}/build"
APP_NAME="DocxEdit"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
BINARY_NAME="DocxEdit"

echo "==> DocxEdit build"
echo "    Version:       ${VERSION}"
echo "    Build number:  ${BUILD_NUMBER}"
echo "    Output:        ${APP_BUNDLE}"

# Чистим предыдущую сборку.
rm -rf "${APP_BUNDLE}"
mkdir -p "${BUILD_DIR}"

# Шаг 1: Swift-сборка исполняемого файла (Release).
echo "==> Compiling Swift package (Release)"
swift build -c release \
    -Xswiftc "-O" \
    --scratch-path "${BUILD_DIR}/.swift-build"

# Шаг 2: Формируем .app-бандл.
echo "==> Assembling .app bundle"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

EXECUTABLE_PATH="${BUILD_DIR}/.swift-build/release/${BINARY_NAME}"
if [[ ! -f "${EXECUTABLE_PATH}" ]]; then
    echo "ERROR: executable not found at ${EXECUTABLE_PATH}" >&2
    exit 1
fi

cp "${EXECUTABLE_PATH}" "${APP_BUNDLE}/Contents/MacOS/${BINARY_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${BINARY_NAME}"

# Шаг 2.5: Иконка приложения.
ICON_PATH="${BUILD_DIR}/DocxEdit.icns"
if [[ ! -f "${ICON_PATH}" ]]; then
    echo "==> Generating app icon"
    swift "${REPO_ROOT}/scripts/generate-icon.swift" "${ICON_PATH}"
fi
cp "${ICON_PATH}" "${APP_BUNDLE}/Contents/Resources/DocxEdit.icns"

# v0.6.2 (R09): базовая EN-локализация. SPM собирает ресурсы в bundle
# `DocxEdit_DocxEdit.bundle` внутри release/. Копируем его целиком в Resources,
# чтобы `Bundle.module` в runtime смог найти .lproj-каталоги через
# NSLocalizedString(_:tableName:bundle:).
RESOURCE_BUNDLE_SRC="${BUILD_DIR}/.swift-build/release/DocxEdit_DocxEdit.bundle"
if [[ -d "${RESOURCE_BUNDLE_SRC}" ]]; then
    cp -R "${RESOURCE_BUNDLE_SRC}" "${APP_BUNDLE}/Contents/Resources/"
fi

# Шаг 3: Info.plist.
cat > "${APP_BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>ru</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>ru</string>
        <string>en</string>
    </array>
    <key>CFBundleExecutable</key>
    <string>${BINARY_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>app.docxedit.DocxEdit</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 DocxEdit.</string>
    <key>CFBundleIconFile</key>
    <string>DocxEdit</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <!-- Office Open XML (DOCX) — основной формат. -->
        <dict>
            <key>CFBundleTypeName</key>
            <string>Office Open XML Document (DOCX)</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerContentType</key>
            <string>org.openxmlformats.wordprocessingml.document</string>
            <key>LSHandlerRank</key>
            <string>Owner</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>docx</string>
            </array>
            <key>CFBundleTypeMIMETypes</key>
            <array>
                <string>application/vnd.openxmlformats-officedocument.wordprocessingml.document</string>
            </array>
            <key>LSItemContentTypes</key>
            <array>
                <string>org.openxmlformats.wordprocessingml.document</string>
            </array>
        </dict>
        <!-- Legacy binary DOC — импортируется, сохраняется как DOCX. -->
        <dict>
            <key>CFBundleTypeName</key>
            <string>Legacy Word-Processor Document (DOC)</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerContentType</key>
            <string>com.microsoft.word.doc</string>
            <key>LSHandlerRank</key>
            <string>Owner</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>doc</string>
            </array>
            <key>CFBundleTypeMIMETypes</key>
            <array>
                <string>application/msword</string>
            </array>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.microsoft.word.doc</string>
            </array>
        </dict>
        <!-- Rich Text Format. -->
        <dict>
            <key>CFBundleTypeName</key>
            <string>Rich Text Format</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerContentType</key>
            <string>public.rtf</string>
            <key>LSHandlerRank</key>
            <string>Owner</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>rtf</string>
            </array>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.rtf</string>
            </array>
        </dict>
        <!-- Markdown. -->
        <dict>
            <key>CFBundleTypeName</key>
            <string>Markdown Document</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerContentType</key>
            <string>net.daringfireball.markdown</string>
            <key>LSHandlerRank</key>
            <string>Owner</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>md</string>
                <string>markdown</string>
            </array>
            <key>LSItemContentTypes</key>
            <array>
                <string>net.daringfireball.markdown</string>
            </array>
        </dict>
        <!-- Plain text. -->
        <dict>
            <key>CFBundleTypeName</key>
            <string>Plain Text</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerContentType</key>
            <string>public.plain-text</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>txt</string>
            </array>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.plain-text</string>
            </array>
        </dict>
        <!-- OpenDocument Text (v0.6.1, R09). -->
        <dict>
            <key>CFBundleTypeName</key>
            <string>OpenDocument Text</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerContentType</key>
            <string>org.oasis-open.opendocument.text</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>odt</string>
            </array>
            <key>LSItemContentTypes</key>
            <array>
                <string>org.oasis-open.opendocument.text</string>
            </array>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <!-- Реэкспорт Markdown-UTI на случай, если в системе он не зарегистрирован. -->
        <dict>
            <key>UTTypeIdentifier</key>
            <string>net.daringfireball.markdown</string>
            <key>UTTypeDescription</key>
            <string>Markdown Document</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.plain-text</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>md</string>
                    <string>markdown</string>
                </array>
                <key>public.mime-type</key>
                <array>
                    <string>text/markdown</string>
                </array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Шаг 4: PkgInfo.
echo "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

echo "==> Build complete: ${APP_BUNDLE}"
ls -la "${APP_BUNDLE}/Contents/MacOS/"

# Шаг 4.5: Smoke-тест бандла.
# Быстрые проверки целостности .app, не требующие Xcode и работающие в CI без дисплея.
# Жёсткие проверки (структура, plist, Mach-O, версия) валят сборку; codesign — мягкая.
echo "==> Smoke-testing bundle"
SMOKE_FAIL=0
smoke_check() {  # smoke_check "описание" <код-возврата>
    if [[ "$2" -eq 0 ]]; then
        echo "    ✓ $1"
    else
        echo "    ✗ $1" >&2
        SMOKE_FAIL=1
    fi
}

BIN="${APP_BUNDLE}/Contents/MacOS/${BINARY_NAME}"
PLIST="${APP_BUNDLE}/Contents/Info.plist"

# 1. Структура бандла.
[[ -x "${BIN}" ]]; smoke_check "исполняемый бинарь присутствует" $?
[[ -f "${PLIST}" ]]; smoke_check "Info.plist присутствует" $?
[[ -f "${APP_BUNDLE}/Contents/PkgInfo" ]]; smoke_check "PkgInfo присутствует" $?
[[ -f "${APP_BUNDLE}/Contents/Resources/DocxEdit.icns" ]]; smoke_check "иконка присутствует" $?

# 2. Валидность Info.plist.
plutil -lint "${PLIST}" >/dev/null 2>&1; smoke_check "Info.plist валиден (plutil -lint)" $?

# 3. Версия в plist совпадает с собираемой.
PLIST_VER="$(plutil -extract CFBundleShortVersionString raw "${PLIST}" 2>/dev/null || echo '')"
[[ "${PLIST_VER}" == "${VERSION}" ]]; smoke_check "CFBundleShortVersionString = ${VERSION} (получено: '${PLIST_VER}')" $?

# 4. Бинарь — валидный Mach-O и содержит хотя бы текущую архитектуру.
file "${BIN}" 2>/dev/null | grep -q "Mach-O"; smoke_check "бинарь — Mach-O" $?
ARCHS="$(lipo -archs "${BIN}" 2>/dev/null || echo '')"
echo "${ARCHS}" | grep -q "$(uname -m)"; smoke_check "архитектура включает $(uname -m) (есть: ${ARCHS})" $?

# 5. Подпись (мягкая: build.sh не подписывает, ad-hoc допустим).
if codesign --verify --deep --strict "${APP_BUNDLE}" >/dev/null 2>&1; then
    echo "    ✓ codesign --verify прошёл"
else
    echo "    ⚠ codesign --verify не прошёл (ожидаемо для неподписанной/ad-hoc сборки)"
fi

if [[ "${SMOKE_FAIL}" -ne 0 ]]; then
    echo "ERROR: smoke-тест бандла провален" >&2
    exit 1
fi
echo "==> Smoke-тест пройден"

# Шаг 5: Пакуем в ZIP и DMG.
RELEASE_DIR="${BUILD_DIR}/v${VERSION}"
mkdir -p "${RELEASE_DIR}"

echo "==> Creating app archive"
ZIP_NAME="${APP_NAME}-${VERSION}.app.zip"
ditto -c -k --keepParent "${APP_BUNDLE}" "${RELEASE_DIR}/${ZIP_NAME}"

echo "==> Creating DMG"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
TMP_DMG_DIR="${BUILD_DIR}/.dmg-staging"
TMP_DMG_RW="${BUILD_DIR}/.tmp-rw.dmg"
VOLNAME="${APP_NAME} ${VERSION}"
rm -rf "${TMP_DMG_DIR}" "${TMP_DMG_RW}"
mkdir -p "${TMP_DMG_DIR}"
cp -R "${APP_BUNDLE}" "${TMP_DMG_DIR}/"
# Симлинк на /Applications — чтобы образ ставился перетаскиванием.
ln -s /Applications "${TMP_DMG_DIR}/Applications"

# Создаём read-write HFS+ DMG (APFS не поддерживает Finder-стилизацию окна).
hdiutil create -volname "${VOLNAME}" \
    -srcfolder "${TMP_DMG_DIR}" \
    -fs HFS+ -ov -format UDRW \
    "${TMP_DMG_RW}"
rm -rf "${TMP_DMG_DIR}"

# Монтируем и позиционируем иконки через AppleScript.
hdiutil attach -readwrite -noverify -noautoopen "${TMP_DMG_RW}" >/dev/null
osascript <<ASCRIPT 2>/dev/null || true
tell application "Finder"
    tell disk "${VOLNAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 100, 740, 430}
        set icon size of (icon view options of container window) to 96
        set arrangement of (icon view options of container window) to not arranged
        set position of item "${APP_NAME}.app" of container window to {140, 195}
        set position of item "Applications" of container window to {400, 195}
        update without registering applications
        delay 2
        close
    end tell
end tell
ASCRIPT
# AppleScript может выставить kIsInvisible на .app-бандле (FinderInfo byte 8-9 = 0x4000).
# Сбрасываем флаг через SetFile перед конвертацией — иначе Finder прячет приложение.
if [[ -d "/Volumes/${VOLNAME}/${APP_NAME}.app" ]]; then
    SetFile -a v "/Volumes/${VOLNAME}/${APP_NAME}.app" 2>/dev/null || true
fi
hdiutil detach "/Volumes/${VOLNAME}" -quiet 2>/dev/null || true

# Конвертируем в сжатый read-only DMG.
hdiutil convert "${TMP_DMG_RW}" -format UDZO -imagekey zlib-level=9 \
    -o "${RELEASE_DIR}/${DMG_NAME}" -ov
rm -f "${TMP_DMG_RW}"

echo "==> Computing checksums"
(cd "${RELEASE_DIR}" && shasum -a 256 "${ZIP_NAME}" "${DMG_NAME}" > SHA256SUMS)

echo ""
echo "==> Release artifacts at ${RELEASE_DIR}:"
ls -lh "${RELEASE_DIR}/"
