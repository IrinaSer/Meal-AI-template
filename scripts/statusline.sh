#!/usr/bin/env bash
# Meal-AI — статус-строка Claude Code: живой остаток калорий за сегодня.
# Висит в подвале постоянно. Настроена в .claude/settings.json (ключ statusLine).
#
# Получает JSON сессии со stdin (нам не нужен). Каталог проекта — по расположению
# скрипта, не зависит от cwd. Всегда печатает ровно одну строку и быстро выходит.
# Грейсфул: нет jq → «🥗 Meal-AI»; нет profile.md → показывает только съеденное.
set -uo pipefail

cat >/dev/null 2>&1 || true   # проглотить stdin

# Нет jq — минимальная строка, без падения.
if ! command -v jq >/dev/null 2>&1; then
  echo "🥗 Meal-AI"
  exit 0
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
diary="$PROJECT_DIR/data/diary.jsonl"
profile="$PROJECT_DIR/profile.md"
key=$(date +%Y-%m-%d)

# Норма калорий из профиля (строка вида «- Калории: 1480 ккал»). Пусто, если нет.
norm=""
if [ -f "$profile" ]; then
  norm=$(grep -m1 '^- Калории:' "$profile" 2>/dev/null | grep -oE '[0-9]+' | head -n1)
fi

# Суммы за сегодня + число приёмов.
eaten=0 prot=0 fat=0 carb=0 meals=0
if [ -s "$diary" ]; then
  read -r meals eaten prot fat carb < <(
    jq -rs --arg d "$key" '
      [ .[] | select(.date == $d) ] as $t
      | "\($t|length) \([$t[].total.kcal]|add // 0) \([$t[].total.protein]|add // 0) \([$t[].total.fat]|add // 0) \([$t[].total.carbs]|add // 0)"
    ' "$diary" 2>/dev/null
  )
  meals=${meals:-0}; eaten=${eaten:-0}; prot=${prot:-0}; fat=${fat:-0}; carb=${carb:-0}
fi

# Округлим граммы БЖУ до целых для компактности.
prot=$(printf '%.0f' "$prot" 2>/dev/null || echo 0)
fat=$(printf '%.0f'  "$fat"  2>/dev/null || echo 0)
carb=$(printf '%.0f' "$carb" 2>/dev/null || echo 0)
eaten=$(printf '%.0f' "$eaten" 2>/dev/null || echo 0)

meal_word() { case "$1" in 1) echo "приём";; 2|3|4) echo "приёма";; *) echo "приёмов";; esac; }

# Сборка строки.
if [ -z "$norm" ]; then
  # Без профиля — только съеденное.
  if [ "$meals" -eq 0 ]; then
    echo "🥗 Meal-AI · старт дня"
  else
    echo "🥗 ${eaten} ккал съедено · ⚡${meals} $(meal_word "$meals")"
  fi
  exit 0
fi

if [ "$meals" -eq 0 ]; then
  echo "🥗 старт дня · бюджет ${norm} ккал"
  exit 0
fi

bju="Б${prot} Ж${fat} У${carb}"
if [ "$eaten" -le "$norm" ]; then
  left=$(( norm - eaten ))
  echo "🥗 ${left}/${norm} ккал осталось · ${bju} · ⚡${meals} $(meal_word "$meals")"
else
  over=$(( eaten - norm ))
  echo "🔴 +${over} ккал сверх ${norm} · ${bju} · ⚡${meals} $(meal_word "$meals")"
fi
