#!/usr/bin/env bash
#
# publish-github.sh — публикация релиза DocxEdit на GitHub Releases.
#
# Загружает `.dmg`, `.app.zip`, `SHA256SUMS` из `build/vX.Y.Z/` в GitHub Release
# `vX.Y.Z`. Тело релиза берётся из соответствующей секции CHANGELOG.md.
# После успешной публикации — ротация: остаются только N самых свежих релизов
# (по умолчанию 3), остальные GitHub-Releases удаляются (git-теги сохраняются).
#
# Требует установленный и авторизованный `gh` CLI (https://cli.github.com).
#
# Использование:
#   ./scripts/publish-github.sh <version> [--codename "Codename"]
#
# ENV:
#   KEEP_RELEASES   — сколько последних релизов оставить (default 3, диапазон 1–20)
#   DRY_RUN=1       — не выполнять gh-команды, только печатать что бы сделали
#
# Идемпотентно: повторный запуск с тем же `<version>` обновляет asset'ы
# (`gh release upload --clobber`), новый релиз не создаётся.
#

set -euo pipefail

usage() { echo "Usage: $0 <version> [--codename \"Codename\"]"; exit 2; }

VERSION="${1:-}"; [[ -z "$VERSION" ]] && usage
shift || true

CODENAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --codename) CODENAME="${2:-}"; shift 2 ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

TAG="v${VERSION}"
BUILD_DIR="build/${TAG}"
KEEP="${KEEP_RELEASES:-6}"

if ! [[ "$KEEP" =~ ^[0-9]+$ ]] || (( KEEP < 1 || KEEP > 20 )); then
  echo "❌ KEEP_RELEASES=$KEEP вне диапазона 1–20"; exit 1
fi

# ── 0. Проверки окружения ────────────────────────────────────────────────
if ! command -v gh >/dev/null 2>&1; then
  echo "❌ 'gh' CLI не установлен. Установите:  brew install gh"
  echo "   Затем авторизуйтесь:  gh auth login"
  exit 1
fi

# Проверка авторизации через дешёвый эндпоинт (`gh auth status` иногда падает,
# когда /user временно недоступен, но токен на самом деле рабочий).
if ! gh api rate_limit >/dev/null 2>&1; then
  echo "❌ gh не авторизован или GitHub API недоступен."
  echo "   Проверьте:  gh auth status  /  gh auth refresh -h github.com"
  exit 1
fi

# `gh repo view` работает из репо-корня — упадёт, если это не гит-репо или нет remote.
if ! gh repo view --json name >/dev/null 2>&1; then
  echo "⚠️  Нет GitHub remote (или не гит-репо). Пропускаю публикацию."
  echo "    Если это dev-машина без remote — используйте:  release.sh ... --no-publish"
  exit 0
fi

# ── 1. Проверка артефактов ───────────────────────────────────────────────
DMG="${BUILD_DIR}/DocxEdit-${VERSION}.dmg"
ZIP="${BUILD_DIR}/DocxEdit-${VERSION}.app.zip"
SUMS="${BUILD_DIR}/SHA256SUMS"

for f in "$DMG" "$ZIP" "$SUMS"; do
  [[ -f "$f" ]] || { echo "❌ Не найден артефакт: $f  — сначала запустите release.sh"; exit 1; }
done

# ── 2. Тело релиза из CHANGELOG.md ───────────────────────────────────────
NOTES_FILE="$(mktemp)"
trap 'rm -f "$NOTES_FILE"' EXIT

if [[ -f CHANGELOG.md ]]; then
  # Извлекаем секцию `## [X.Y.Z]` или `## vX.Y.Z` до следующего `## `.
  awk -v ver="$VERSION" '
    $0 ~ "^## (\\[?" ver "\\]?|v" ver ")" { in_section = 1; next }
    in_section && /^## / { in_section = 0 }
    in_section { print }
  ' CHANGELOG.md > "$NOTES_FILE"
fi

if ! [[ -s "$NOTES_FILE" ]]; then
  # Fallback: короткое тело.
  cat > "$NOTES_FILE" <<EOF
DocxEdit ${TAG}${CODENAME:+ — ${CODENAME}}

Артефакты:
- \`DocxEdit-${VERSION}.dmg\` — нативный macOS-инсталлятор
- \`DocxEdit-${VERSION}.app.zip\` — zip-архив бандла
- \`SHA256SUMS\` — контрольные суммы

Полный changelog см. в [CHANGELOG.md](CHANGELOG.md).
EOF
fi

# ── 3. Определяем pre-release ────────────────────────────────────────────
PRERELEASE=""
if [[ "$VERSION" == *"-rc."* || "$VERSION" == *"-beta."* || "$VERSION" == *"-alpha."* ]]; then
  PRERELEASE="--prerelease"
fi

# ── 4. Создать или обновить релиз ────────────────────────────────────────
TITLE="${TAG}${CODENAME:+ — ${CODENAME}}"

run() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "→ Релиз $TAG уже существует — обновляю артефакты (--clobber)"
  run gh release upload "$TAG" "$DMG" "$ZIP" "$SUMS" --clobber
  # Опционально обновим notes/title, если пользователь изменил CHANGELOG.
  run gh release edit "$TAG" --title "$TITLE" --notes-file "$NOTES_FILE" ${PRERELEASE:+--prerelease}
else
  echo "→ Создаю релиз $TAG"
  # v1.5.11+: релизные теги с полной историей кода живут в приватном
  # src-remote; в публичном репо тег создаём на его default-ветке (README),
  # чтобы не публиковать исходники.
  TARGET_ARGS=()
  if ! git ls-remote --tags origin 2>/dev/null | grep -q "refs/tags/$TAG"; then
    TARGET_ARGS=(--target "$(git rev-parse origin/main 2>/dev/null || echo main)")
  fi
  run gh release create "$TAG" "$DMG" "$ZIP" "$SUMS" \
    --title "$TITLE" \
    --notes-file "$NOTES_FILE" \
    ${TARGET_ARGS[@]+"${TARGET_ARGS[@]}"} \
    ${PRERELEASE}
fi

# ── 5. Ротация: оставить только KEEP самых свежих ────────────────────────
echo "→ Ротация: оставляю $KEEP последних релизов"

# gh release list возвращает по одному релизу на строку, отсортированных
# по created (новые первые). Draft'ы игнорируем при подсчёте.
ROTATION_LIST="$(mktemp)"
trap 'rm -f "$NOTES_FILE" "$ROTATION_LIST"' EXIT

gh release list --limit 100 --json tagName,isDraft,createdAt \
  --jq 'sort_by(.createdAt) | reverse | .[] | select(.isDraft == false) | .tagName' \
  > "$ROTATION_LIST" 2>/dev/null || true

# v1.5.11: только что опубликованный тег исключаем из ротации — у релизов,
# созданных через --target на README-ветку, createdAt у GitHub может быть
# старее существующих (дата тега), и ротация сносила свежий релиз.
grep -vx "$TAG" "$ROTATION_LIST" > "$ROTATION_LIST.tmp" 2>/dev/null || true
mv "$ROTATION_LIST.tmp" "$ROTATION_LIST"

TOTAL=$(wc -l < "$ROTATION_LIST" | tr -d ' ')
if (( TOTAL <= KEEP )); then
  echo "   всего релизов: $TOTAL ≤ $KEEP, удалять нечего"
else
  # Удаляем всё, что за пределами топ-KEEP.
  tail -n +$((KEEP + 1)) "$ROTATION_LIST" | while read -r OLD_TAG; do
    [[ -z "$OLD_TAG" ]] && continue
    echo "   ✂  удаляю Release $OLD_TAG (git-тег остаётся)"
    run gh release delete "$OLD_TAG" --yes || echo "     (не удалось удалить $OLD_TAG, продолжаю)"
  done
fi

echo "✅ GitHub Release $TAG опубликован: https://github.com/$(gh repo view --json nameWithOwner --jq .nameWithOwner)/releases/tag/${TAG}"
