#!/usr/bin/env bash
#
# update-claude-md.sh — обновление CLAUDE.md при выпуске релиза.
#
# Использование:
#   ./scripts/update-claude-md.sh VERSION DATE CODENAME [CHANGES]
#
# Параметры:
#   VERSION   — версия релиза (например, 0.1.8)
#   DATE      — дата выпуска в формате YYYY-MM-DD
#   CODENAME  — кодовое имя релиза (например, Genesis)
#   CHANGES   — краткое описание изменений для таблицы истории
#               (по умолчанию: «см. CHANGELOG.md»)
#
# Что обновляется (под текущий формат CLAUDE.md):
#   - шапка: «Последнее обновление: <DATE> (v<VERSION>)»
#   - §4: «Активная версия» и «Артефакты»
#   - §5: новая строка сверху в таблице истории релизов
#

set -euo pipefail

VERSION="${1:?Usage: $0 VERSION DATE CODENAME [CHANGES]}"
DATE="${2:?Usage: $0 VERSION DATE CODENAME [CHANGES]}"
CODENAME="${3:?Usage: $0 VERSION DATE CODENAME [CHANGES]}"
CHANGES="${4:-см. CHANGELOG.md}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE_MD="${REPO_ROOT}/CLAUDE.md"

if [[ ! -f "${CLAUDE_MD}" ]]; then
    echo "ERROR: ${CLAUDE_MD} not found" >&2
    exit 1
fi

# 1. Шапка: «… Последнее обновление: <DATE> (v<VERSION>)».
#    Заменяем всё после «Последнее обновление: » на строке-цитате (> …).
sed -i.bak -E "s|^(> .*Последнее обновление: ).*\$|\1${DATE} (v${VERSION})|" "${CLAUDE_MD}"
rm -f "${CLAUDE_MD}.bak"

# 2. §4 «Активная версия».
sed -i.bak -E "s|^- \*\*Активная версия:\*\* .*\$|- **Активная версия:** \`${VERSION}\` — ${CODENAME}|" "${CLAUDE_MD}"
rm -f "${CLAUDE_MD}.bak"

# 3. §4 «Артефакты».
sed -i.bak -E "s|^- \*\*Артефакты:\*\* .*\$|- **Артефакты:** \`build/v${VERSION}/DocxEdit-${VERSION}.dmg\` + \`build/v${VERSION}/DocxEdit-${VERSION}.app.zip\` + \`build/v${VERSION}/SHA256SUMS\`|" "${CLAUDE_MD}"
rm -f "${CLAUDE_MD}.bak"

# 4. §5 Таблица истории релизов — вставляем строку сразу после строки-разделителя
#    (новые релизы сверху). Используем python3 для надёжной работы с многострочьем.
python3 - <<PYEOF
import re

p = "${CLAUDE_MD}"
version, date, codename, changes = "${VERSION}", "${DATE}", "${CODENAME}", """${CHANGES}"""

s = open(p, encoding="utf-8").read()

# Уже есть строка для этой версии?
if re.search(rf"(?m)^\|\s*{re.escape(version)}\s*\|", s):
    print(f"SKIP: история уже содержит строку v{version}")
else:
    new_row = f"| {version} | {date} | {codename} | {changes} | \`build/v{version}/\` |"
    # Заголовок таблицы + строка-разделитель из дефисов.
    m = re.search(
        r"\| Версия \| Дата \| Кодовое имя \| Ключевые изменения \| Артефакты \|\n\|[-| ]+\|\n",
        s,
    )
    if m:
        s = s[:m.end()] + new_row + "\n" + s[m.end():]
        open(p, "w", encoding="utf-8").write(s)
        print(f"OK: вставлена строка истории для v{version}")
    else:
        print("WARN: таблица истории не найдена, пропуск")
PYEOF

# 5. Коммитим, если это git-репозиторий.
if git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree &>/dev/null; then
    git -C "${REPO_ROOT}" add "${CLAUDE_MD}"
    git -C "${REPO_ROOT}" commit -m "chore(release): update CLAUDE.md for v${VERSION}" || true
fi

echo "==> CLAUDE.md обновлён для v${VERSION} (${CODENAME}) на ${DATE}"
