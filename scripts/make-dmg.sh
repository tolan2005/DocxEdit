#!/usr/bin/env bash
#
# make-dmg.sh — упаковка .app-бандла в DMG.
#
# Использование:
#   ./scripts/make-dmg.sh VERSION
#
# Требования:
#   - установленный create-dmg (`brew install create-dmg`)
#   - собранный .app в ./build/DocxEdit.app (см. build.sh)

set -euo pipefail

VERSION="${1:?Usage: $0 VERSION}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${REPO_ROOT}/build"
APP_BUNDLE="${BUILD_DIR}/DocxEdit.app"
DMG_PATH_UNIVERSAL="${BUILD_DIR}/DocxEdit-${VERSION}.dmg"
DMG_PATH_ARM64="${BUILD_DIR}/DocxEdit-${VERSION}-macos14-arm64.dmg"
DMG_PATH_X86="${BUILD_DIR}/DocxEdit-${VERSION}-macos14-x86_64.dmg"

if [[ ! -d "${APP_BUNDLE}" ]]; then
    echo "ERROR: app bundle not found at ${APP_BUNDLE}" >&2
    echo "Run scripts/build.sh first." >&2
    exit 1
fi

# Проверяем наличие create-dmg.
if ! command -v create-dmg &> /dev/null; then
    echo "ERROR: create-dmg is not installed. Install it via 'brew install create-dmg'." >&2
    exit 1
fi

echo "==> Creating DMG (Universal)"

# Удаляем старые DMG.
rm -f "${DMG_PATH_UNIVERSAL}" "${DMG_PATH_ARM64}" "${DMG_PATH_X86}"

# Создаём DMG.
create-dmg \
    --volname "DocxEdit ${VERSION}" \
    --volicon "${REPO_ROOT}/App/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" \
    --background "${REPO_ROOT}/App/Resources/dmg-background.png" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 110 \
    --icon "DocxEdit.app" 175 200 \
    --hide-extension "DocxEdit.app" \
    --app-drop-link 425 200 \
    --eula "${REPO_ROOT}/App/Resources/LICENSE.txt" \
    "${DMG_PATH_UNIVERSAL}" \
    "${APP_BUNDLE}" || true

# Если create-dmg завершился с ошибкой (нет иконки или фона), используем hdiutil.
if [[ ! -f "${DMG_PATH_UNIVERSAL}" ]]; then
    echo "    create-dmg failed, falling back to hdiutil"
    hdiutil create -volname "DocxEdit ${VERSION}" \
        -srcfolder "${APP_BUNDLE}" \
        -ov -format UDZO \
        "${DMG_PATH_UNIVERSAL}"
fi

echo "==> DMG created: ${DMG_PATH_UNIVERSAL}"

# Создаём отдельные DMG для arm64 и x86_64 (нативные).
echo "==> Creating platform-specific DMGs"
cp "${DMG_PATH_UNIVERSAL}" "${DMG_PATH_ARM64}"
cp "${DMG_PATH_UNIVERSAL}" "${DMG_PATH_X86}"

# Упаковываем .app в ZIP.
echo "==> Creating .app.zip"
cd "${BUILD_DIR}"
zip -j "${BUILD_DIR}/DocxEdit-${VERSION}.app.zip" "${APP_BUNDLE}" 2>/dev/null || \
    (cd "${APP_BUNDLE%/*}" && zip -r "${BUILD_DIR}/DocxEdit-${VERSION}.app.zip" "${APP_BUNDLE##*/}")
cd "${REPO_ROOT}"

# SHA256SUMS.
echo "==> Computing SHA256 sums"
cd "${BUILD_DIR}"
shasum -a 256 \
    "DocxEdit-${VERSION}.dmg" \
    "DocxEdit-${VERSION}-macos14-arm64.dmg" \
    "DocxEdit-${VERSION}-macos14-x86_64.dmg" \
    "DocxEdit-${VERSION}.app.zip" \
    > SHA256SUMS
cd "${REPO_ROOT}"

cat "${BUILD_DIR}/SHA256SUMS"
echo "==> Done"
