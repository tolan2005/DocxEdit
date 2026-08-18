#!/usr/bin/env bash
#
# release.sh — комплексный сценарий выпуска релиза одной командой.
#
# Шаги:
#   1. Тесты (swift test, условно — только при наличии полного Xcode)
#   2. Сборка .app + smoke-тест + .app.zip + .dmg + SHA256SUMS (build.sh) → build/v<VERSION>/
#   3. Подпись и нотаризация DMG (notarize.sh, опционально)
#   4. Заготовка секции в CHANGELOG.md (update-changelog.sh)
#   5. Обновление CLAUDE.md (update-claude-md.sh)
#   6. Создание git-тега (если это git-репозиторий)
#
# Использование:
#   ./scripts/release.sh VERSION CODENAME [KEYCHAIN_PROFILE] [CHANGES]
#
# Параметры:
#   VERSION          — семантическая версия, например 0.1.8
#   CODENAME         — кодовое имя релиза, например "Paragraphs"
#   KEYCHAIN_PROFILE — профиль notarytool в keychain (опц.; пусто = без нотаризации)
#   CHANGES          — краткое описание изменений для таблицы истории CLAUDE.md
#                      (опц.; по умолчанию «см. CHANGELOG.md»)
#
# Примечание: упаковкой DMG/ZIP занимается build.sh. Скрипт make-dmg.sh — легаси
# (требует create-dmg и ассеты) и в этом сценарии не используется.
#

set -euo pipefail

# --no-publish можно передавать в любой позиции (v1.1.0, R11).
NO_PUBLISH=0
FILTERED_ARGS=()
for arg in "$@"; do
  if [[ "$arg" == "--no-publish" ]]; then NO_PUBLISH=1; else FILTERED_ARGS+=("$arg"); fi
done
set -- "${FILTERED_ARGS[@]}"

VERSION="${1:?Usage: $0 VERSION CODENAME [KEYCHAIN_PROFILE] [CHANGES] [--no-publish]}"
CODENAME="${2:?Usage: $0 VERSION CODENAME [KEYCHAIN_PROFILE] [CHANGES] [--no-publish]}"
KEYCHAIN_PROFILE="${3:-}"
CHANGES="${4:-см. CHANGELOG.md}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATE=$(date +%Y-%m-%d)
RELEASE_DIR="${REPO_ROOT}/build/v${VERSION}"
DMG_PATH="${RELEASE_DIR}/DocxEdit-${VERSION}.dmg"

echo "==> DocxEdit release ${VERSION} (${CODENAME}) — ${DATE}"

# 0. Панель «О программе» обязана включать выпускаемый релиз первым элементом
#    (AboutReleaseNotes.recent обновляется вручную; забыт в 0.1.22 и 0.1.23 —
#    оба раза баг дошёл до пользователя, поэтому проверка валит релиз).
if ! grep -q "(\"${VERSION}\"," "${REPO_ROOT}/Sources/DocxEdit/Sources/DocxEditApp.swift"; then
    echo "ОШИБКА: AboutReleaseNotes.recent в DocxEditApp.swift не содержит запись для ${VERSION}." >&2
    echo "        Добавь текущий релиз ПЕРВЫМ элементом (список из 3 последних) и повтори." >&2
    exit 1
fi

# 1. Тесты (условно). Гоняем swift test только при наличии полного Xcode:
#    в окружении Command Line Tools модуля XCTest нет — честно пропускаем.
#    Принудительный пропуск: SKIP_TESTS=1. Красные тесты валят релиз.
#
#    С v0.5.2 в тест-сьюте (184 теста, включая snapshot-тесты рендера).
#    Правило: если XCTest доступен, тесты ОБЯЗАНЫ пройти — иначе релиз падает.
echo "==> [1/6] Tests"
XCODE_PATH="$(xcode-select -p 2>/dev/null || echo '')"
if [[ "${SKIP_TESTS:-0}" == "1" ]]; then
    echo "    ⏭️  пропущено (SKIP_TESTS=1) — используй ТОЛЬКО когда среда не даёт запустить XCTest."
elif [[ -z "${XCODE_PATH}" || "${XCODE_PATH}" == *"CommandLineTools"* ]]; then
    echo "    ⏭️  пропущено: нет полного Xcode (XCTest недоступен в Command Line Tools)."
    echo "        Тесты не проверены — релиз гарантирует только компиляцию и smoke-тест бандла."
    echo "        Для полного гейта: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
else
    echo "    ▶️  swift test (Xcode: ${XCODE_PATH})"
    # Проверим, что snapshot-эталоны присутствуют (иначе тесты сами их запишут
    # и «пройдут» — но это будет запись без гарантии корректности).
    SNAP_DIR="${REPO_ROOT}/Tests/DocxEditTests/__Snapshots__"
    if [[ -d "${SNAP_DIR}" && $(find "${SNAP_DIR}" -name '*.png' | wc -l) -lt 1 ]]; then
        echo "ОШИБКА: snapshot-эталоны в ${SNAP_DIR} не найдены. Проверь, что каталог закоммичен." >&2
        exit 1
    fi
    swift test
    echo "    ✓ тесты пройдены"
fi

# 2. Сборка + упаковка (build.sh: swift build, .app, smoke-тест, .zip, .dmg, SHA256SUMS).
echo "==> [2/6] Building & packaging"
"${REPO_ROOT}/scripts/build.sh" "${VERSION}" "$(date +%Y%m%d%H%M%S)"

if [[ ! -f "${DMG_PATH}" ]]; then
    echo "ERROR: DMG not found at ${DMG_PATH}" >&2
    exit 1
fi

# 2. Нотаризация (опционально). Пересчитываем SHA256SUMS после подписи.
if [[ -n "${KEYCHAIN_PROFILE}" ]]; then
    echo "==> [3/6] Notarizing DMG"
    "${REPO_ROOT}/scripts/notarize.sh" "${DMG_PATH}" "${KEYCHAIN_PROFILE}"
    echo "==> Recomputing checksums after notarization"
    (cd "${RELEASE_DIR}" && shasum -a 256 \
        "DocxEdit-${VERSION}.app.zip" "DocxEdit-${VERSION}.dmg" > SHA256SUMS)
else
    echo "==> [3/6] Notarization skipped (no keychain profile provided)"
fi

# 4. CHANGELOG.md — заготовка секции.
echo "==> [4/6] Updating CHANGELOG.md"
"${REPO_ROOT}/scripts/update-changelog.sh" "${VERSION}" "${DATE}" "${CODENAME}" "${CHANGES}"

# 5. CLAUDE.md.
echo "==> [5/6] Updating CLAUDE.md"
"${REPO_ROOT}/scripts/update-claude-md.sh" "${VERSION}" "${DATE}" "${CODENAME}" "${CHANGES}"

# 6. Git-тег (только если это репозиторий).
if git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree &>/dev/null; then
    echo "==> [6/6] Creating git tag v${VERSION}"
    git -C "${REPO_ROOT}" tag -a "v${VERSION}" -m "Release ${VERSION} — ${CODENAME}" || true
    # Теги — в приватный src-remote (там полная история с исходниками).
    # В публичный origin код и теги с кодом не пушим: gh release создаст
    # пустой тег на его стороне автоматически.
    git -C "${REPO_ROOT}" push src "v${VERSION}" 2>/dev/null || \
        echo "    (push пропущен: нет remote src или нет доступа)"
else
    echo "==> [6/6] Git tag skipped (не git-репозиторий)"
fi

# 7. Публикация на GitHub (v1.1.0+). Пропускается если --no-publish, нет gh,
#    нет GitHub remote, или репо не инициализирован.
if [[ "${NO_PUBLISH}" == "1" ]]; then
    echo "==> [7/7] Публикация на GitHub пропущена (--no-publish)"
else
    echo "==> [7/7] Publishing to GitHub Releases"
    if [[ -x "${REPO_ROOT}/scripts/publish-github.sh" ]]; then
        "${REPO_ROOT}/scripts/publish-github.sh" "${VERSION}" --codename "${CODENAME}" || {
            echo "    ⚠️  Публикация не удалась — артефакты остались в ${RELEASE_DIR}."
            echo "        Повторить вручную:  ./scripts/publish-github.sh ${VERSION} --codename \"${CODENAME}\""
        }
    else
        echo "    ⏭️  scripts/publish-github.sh не найден — пропускаю."
    fi
fi

echo ""
echo "==> Релиз v${VERSION} (${CODENAME}) готов."
echo "    Артефакты: ${RELEASE_DIR}"
ls -lh "${RELEASE_DIR}/"
