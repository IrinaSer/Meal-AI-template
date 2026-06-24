#!/usr/bin/env bash
# Meal-AI — приветствие при старте сессии (хук SessionStart в .claude/settings.json).
# Показывает дату, строку статистики за сегодня и быстрые команды.
#
# Читает JSON хука со stdin (поле .source). На source=compact молчит, чтобы не
# мусорить после авто-компакта. Безопасен при отсутствии jq или пустом дневнике —
# в этих случаях просто тихо выходит / показывает «записей пока нет».
set -euo pipefail

# Нет jq — приветствия не будет, но старт сессии не ломаем.
command -v jq >/dev/null 2>&1 || exit 0

# Каталог проекта по расположению скрипта — не зависит от cwd.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

input=$(cat)
src=$(printf '%s' "$input" | jq -r '.source // "startup"' 2>/dev/null)
[ "$src" = "compact" ] && exit 0

today=$(date +%d.%m.%Y)
key=$(date +%Y-%m-%d)
diary="$PROJECT_DIR/data/diary.jsonl"

if [ -s "$diary" ]; then
  line=$(jq -rs --arg d "$key" \
    '[.[]|select(.date==$d)] as $t | "Сегодня: \($t|length) приём(ов), \([$t[].total.kcal]|add // 0) ккал"' \
    "$diary" 2>/dev/null)
else
  line="Сегодня записей пока нет."
fi

msg=$(printf '🥗 Meal-AI · %s\n%s\n\n• фото еды → запишу приём\n• «мой вес 68» → журнал веса\n• «отчёт за неделю» → сводка\n• «разбери инбокс» → телефон' "$today" "$line")
jq -n --arg m "$msg" '{systemMessage:$m}'
