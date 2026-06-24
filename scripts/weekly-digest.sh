#!/bin/bash
# Meal-AI — еженедельный авто-дайджест. Раз в неделю генерит сводку питания за
# прошедшую неделю в data/summary/<ГГГГ-Wнеделя>.md. Запускается launchd-агентом
# com.meal-ai.weekly (см. scripts/com.meal-ai.weekly.plist), как и инбокс — через
# подписку Claude Code (claude -p), без API-ключа и сервера.
#
# Идемпотентно: если файл за текущую неделю уже есть — тихо выходит.
set -euo pipefail

# Каталог проекта по расположению скрипта — настраивать не нужно.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Полный путь к claude — launchd не наследует PATH. Автопоиск; при необходимости
# задайте вручную: CLAUDE_BIN="$HOME/.local/bin/claude" (узнать путь: `which claude`).
CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || echo "$HOME/.local/bin/claude")}"
LOG="$PROJECT_DIR/scripts/weekly-digest.log"

week=$(date +%G-W%V)                       # ISO-неделя, напр. 2026-W26
out="data/summary/$week.md"                # путь относительно корня проекта

ts() { date '+%Y-%m-%d %H:%M:%S'; }

# Уже сгенерировано за эту неделю — выходим.
if [ -f "$PROJECT_DIR/$out" ]; then
  echo "$(ts) $out exists — skip" >> "$LOG"
  exit 0
fi

echo "$(ts) generating $out ..." >> "$LOG"
cd "$PROJECT_DIR"
mkdir -p data/summary

"$CLAUDE_BIN" -p "Запусти скилл nutrition-review за последнюю неделю и сохрани готовый отчёт в файл $out (по-русски, поддерживающий тон). Если данных за неделю нет — коротко так и напиши." \
  >> "$LOG" 2>&1 || echo "$(ts) claude exited non-zero" >> "$LOG"

echo "$(ts) done" >> "$LOG"
