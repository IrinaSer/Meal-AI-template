#!/bin/bash
# Meal-AI — ежедневный авто-бэкап личных данных: коммитит дневник, вес, профиль,
# foods.csv и сводки и пушит в origin (приватный репозиторий инстанса).
# Запускается launchd-агентом com.meal-ai.backup (scripts/com.meal-ai.backup.plist).
#
# Только git, без claude и API. Нет изменений — тихо выходит. Пуш best-effort:
# без сети коммит останется локально и уедет при следующем запуске (git push
# отправляет и накопившиеся коммиты). Для https-remote нужен сохранённый
# credential helper (osxkeychain — стандарт на Маке), для ssh — ключ без пароля.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$PROJECT_DIR/scripts/backup-data.log"
# Только личные данные — код обновляется через update-from-template.sh.
DATA_PATHS=(data profile.md reference/foods.csv)

ts() { date '+%Y-%m-%d %H:%M:%S'; }
cd "$PROJECT_DIR"

existing=()
for p in "${DATA_PATHS[@]}"; do [ -e "$p" ] && existing+=("$p"); done
[ ${#existing[@]} -eq 0 ] && exit 0
git add -- "${existing[@]}"

if git diff --cached --quiet; then
  echo "$(ts) изменений нет — skip" >> "$LOG"
else
  git commit -q -m "data: авто-бэкап ($(date +%Y-%m-%d))" >> "$LOG" 2>&1
  echo "$(ts) закоммичено" >> "$LOG"
fi

if git push -q origin HEAD >> "$LOG" 2>&1; then
  echo "$(ts) запушено" >> "$LOG"
else
  echo "$(ts) пуш не удался (нет сети?) — коммит останется локально" >> "$LOG"
fi
