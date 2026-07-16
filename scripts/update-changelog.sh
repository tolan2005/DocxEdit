#!/usr/bin/env bash
#
# update-changelog.sh — добавление секции-заготовки в CHANGELOG.md при релизе.
#
# Использование:
#   ./scripts/update-changelog.sh VERSION DATE CODENAME [CHANGES]
#
# Параметры:
#   VERSION   — версия релиза (например, 0.1.8)
#   DATE      — дата выпуска YYYY-MM-DD
#   CODENAME  — кодовое имя релиза
#   CHANGES   — описание изменений; пункты, разделённые «;», станут буллетами
#               (по умолчанию — один буллет-заглушка)
#
# Поведение:
#   - Новая секция вставляется сверху, сразу после преамбулы (перед первой «## [»).
#   - Идемпотентно: если секция «## [VERSION]» уже есть — пропуск.
#   - Секция-заготовка: буллеты из CHANGES + блок «Артефакты». Детали при
#     необходимости дописываются вручную.
#

set -euo pipefail

VERSION="${1:?Usage: $0 VERSION DATE CODENAME [CHANGES]}"
DATE="${2:?Usage: $0 VERSION DATE CODENAME [CHANGES]}"
CODENAME="${3:?Usage: $0 VERSION DATE CODENAME [CHANGES]}"
CHANGES="${4:-}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHANGELOG="${REPO_ROOT}/CHANGELOG.md"

if [[ ! -f "${CHANGELOG}" ]]; then
    echo "ERROR: ${CHANGELOG} not found" >&2
    exit 1
fi

python3 - <<PYEOF
import re

p = "${CHANGELOG}"
version, date, codename = "${VERSION}", "${DATE}", "${CODENAME}"
changes = """${CHANGES}"""

s = open(p, encoding="utf-8").read()

# Уже есть секция для этой версии?
if re.search(rf"(?m)^## \[{re.escape(version)}\]", s):
    print(f"SKIP: CHANGELOG уже содержит секцию [{version}]")
else:
    items = [c.strip() for c in changes.split(";") if c.strip()]
    if not items:
        items = ["_(заполнить: ключевые изменения релиза)_"]
    bullets = "\n".join(f"- {it}" for it in items)

    section = (
        f"## [{version}] — {date} — {codename}\n\n"
        f"### Изменения\n{bullets}\n\n"
        f"### Артефакты\n"
        f"- \`build/v{version}/DocxEdit-{version}.dmg\`\n"
        f"- \`build/v{version}/DocxEdit-{version}.app.zip\`\n"
        f"- \`build/v{version}/SHA256SUMS\`\n\n"
    )

    # Вставляем перед первой секцией «## [...]».
    m = re.search(r"(?m)^## \[", s)
    if m:
        s = s[:m.start()] + section + s[m.start():]
    else:
        # Секций ещё нет — добавляем в конец.
        s = s.rstrip() + "\n\n" + section
    open(p, "w", encoding="utf-8").write(s)
    print(f"OK: добавлена секция CHANGELOG [{version}]")
PYEOF

# Коммит, если это git-репозиторий.
if git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree &>/dev/null; then
    git -C "${REPO_ROOT}" add "${CHANGELOG}"
    git -C "${REPO_ROOT}" commit -m "docs(changelog): add section for v${VERSION}" || true
fi

echo "==> CHANGELOG.md обновлён для v${VERSION}"
