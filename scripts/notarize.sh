#!/usr/bin/env bash
#
# notarize.sh — подпись и нотаризация DMG.
#
# Использование:
#   ./scripts/notarize.sh PATH_TO_DMG KEYCHAIN_PROFILE
#
# Параметры:
#   PATH_TO_DMG        — путь к DMG-файлу
#   KEYCHAIN_PROFILE   — имя профиля в keychain (заданный через
#                        `xcrun notarytool store-credentials`)
#

set -euo pipefail

DMG_PATH="${1:?Usage: $0 PATH_TO_DMG KEYCHAIN_PROFILE}"
KEYCHAIN_PROFILE="${2:?Usage: $0 PATH_TO_DMG KEYCHAIN_PROFILE}"

if [[ ! -f "${DMG_PATH}" ]]; then
    echo "ERROR: DMG not found at ${DMG_PATH}" >&2
    exit 1
fi

# Импортируем Developer ID.
echo "==> Signing with Developer ID"
codesign --force --deep \
    --sign "Developer ID Application" \
    --options runtime \
    --timestamp \
    "${DMG_PATH}"

# Нотаризация.
echo "==> Submitting to Apple notary service"
xcrun notarytool submit "${DMG_PATH}" \
    --keychain-profile "${KEYCHAIN_PROFILE}" \
    --wait

# Прикрепляем ticket.
echo "==> Stapling notarization ticket"
xcrun stapler staple "${DMG_PATH}"

# Проверяем.
echo "==> Verifying"
xcrun stapler validate "${DMG_PATH}"
spctl --assess --type open --context context:primary-signature -v "${DMG_PATH}" || true

echo "==> Notarization complete: ${DMG_PATH}"
