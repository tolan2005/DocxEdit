#!/bin/bash
# ui-smoke.sh — UI-смоук DocxEdit: открытие тестовых документов в живом .app
# без падения. Заменяет XCUITest в текущей инфраструктуре (SwiftPM без
# xcodeproj не хостит UI-тесты; System Events keystrokes требуют Accessibility-
# разрешения, которого у терминала нет — поэтому smoke ограничен открытием).
#
# Что проверяем:
#   1. Бандл собран (build.sh уже делает свой smoke).
#   2. Каждый файл-корпус (docx/md) открывается приложением без краша:
#      запускаем `open -W` не нужен — открываем через CLI-аргумент
#      (openInitialDocumentFromCommandLine), ждём, проверяем, что процесс жив,
#      убиваем. Краш = процесс умер сам.
#
# Запуск: ./scripts/ui-smoke.sh [путь-к-.app]
# Выход: 0 — все открытия успешны; 1 — есть падение.

set -euo pipefail

APP_PATH="${1:-$(dirname "$0")/../build/DocxEdit.app}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES=(
    "${REPO_ROOT}/Tests/DocxIOTests/Fixtures/21.docx"
    "${REPO_ROOT}/Tests/DocxIOTests/Fixtures/22.docx"
    "${REPO_ROOT}/Tests/DocxIOTests/Fixtures/23.docx"
    "${REPO_ROOT}/Tests/DocxIOTests/Fixtures/24.docx"
    "${REPO_ROOT}/Tests/DocxIOTests/Fixtures/133.docx"
)
WAIT_SEC=4
FAILED=0

if [[ ! -d "${APP_PATH}" ]]; then
    echo "❌ Бандл не найден: ${APP_PATH} (сначала ./scripts/build.sh)"
    exit 1
fi

# Отдельный markdown-файл для MD-режима.
TMP_MD="$(mktemp /tmp/docxedit-smoke-XXXX.md)"
printf '# Smoke\n\n**жирный** и [[WikiLink]]\n\n- пункт\n' > "${TMP_MD}"
FIXTURES+=("${TMP_MD}")
trap 'rm -f "${TMP_MD}"' EXIT

echo "==> UI-smoke: ${APP_PATH}"

pkill -x DocxEdit 2>/dev/null || true
sleep 1

for f in "${FIXTURES[@]}"; do
    name="$(basename "${f}")"
    # Краш-репорты до и после — разница = новый краш. (ls || true — каталог
    # может быть пуст; иначе pipefail убивает скрипт.)
    crash_before=$(ls ~/Library/Logs/DiagnosticReports/DocxEdit* 2>/dev/null || true)
    crash_before=$(echo "${crash_before}" | grep -c . || true)
    "${APP_PATH}/Contents/MacOS/DocxEdit" "${f}" &>/dev/null &
    app_pid=$!
    sleep "${WAIT_SEC}"
    if ! kill -0 "${app_pid}" 2>/dev/null; then
        echo "   ❌ процесс умер при открытии ${name}"
        FAILED=1
        continue
    fi
    crash_after=$(ls ~/Library/Logs/DiagnosticReports/DocxEdit* 2>/dev/null || true)
    crash_after=$(echo "${crash_after}" | grep -c . || true)
    if [[ "${crash_after}" -gt "${crash_before}" ]]; then
        echo "   ❌ новый crash report при открытии ${name}"
        FAILED=1
    else
        echo "   ✓ ${name}"
    fi
    pkill -x DocxEdit 2>/dev/null || true
    sleep 1
done

if [[ "${FAILED}" -eq 0 ]]; then
    echo "==> UI-smoke: все ${#FIXTURES[@]} открытий без падений"
else
    echo "==> UI-smoke: ЕСТЬ ПАДЕНИЯ"
fi
exit "${FAILED}"
