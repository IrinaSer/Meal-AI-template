#!/usr/bin/env bash
# Meal-AI — рендер дневника питания в читаемый Markdown «по дням».
# Без Claude и API: голый jq читает data/diary.jsonl (+ вес, + норму из профиля)
# и собирает дневник, где свежие дни сверху. Пишет в data/summary/дневник.md и,
# если папка облачного инбокса существует, копирует туда (читать с телефона).
#
# Запуск: scripts/render-diary.sh            # весь дневник
#         scripts/render-diary.sh 2026-06-01 # только с этой даты (включительно)
# Грейсфул: нет jq → выходит молча; пустой дневник → пишет понятную заглушку.
set -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "render-diary: нужен jq" >&2; exit 0; }

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
diary="$PROJECT_DIR/data/diary.jsonl"
weight="$PROJECT_DIR/data/weight.jsonl"
profile="$PROJECT_DIR/profile.md"
out="$PROJECT_DIR/data/summary/дневник.md"

# Облачный инбокс (см. CLAUDE.md, INBOX_PATH). Раскрываем ~ вручную.
INBOX_PATH="${INBOX_PATH:-$HOME/Yandex.Disk.localized/Meal-AI-Inbox}"

since="${1:-0000-00-00}"   # нижняя граница дат (включительно); по умолчанию — всё

# Дневная норма калорий из профиля (строка «- Калории: 1480 ккал»). Пусто, если нет.
norm=""
[ -f "$profile" ] && norm=$(grep -m1 '^- Калории:' "$profile" 2>/dev/null | grep -oE '[0-9]+' | head -n1)

mkdir -p "$PROJECT_DIR/data/summary"

# Пустой дневник — понятная заглушка, не пустой файл.
if [ ! -s "$diary" ]; then
  printf '# 🥗 Дневник питания\n\nПока ни одной записи. Пришли фото еды или скажи, что съела — я добавлю.\n' > "$out"
  echo "render-diary: дневник пуст → $out"
  [ -d "$INBOX_PATH" ] && cp "$out" "$INBOX_PATH/дневник.md" 2>/dev/null
  exit 0
fi

# Вес по датам в JSON-объект {"2026-06-23":68.5,...} — отдадим в jq аргументом.
wmap='{}'
[ -s "$weight" ] && wmap=$(jq -rs 'map({key:.date,value:.weight_kg})|from_entries' "$weight" 2>/dev/null || echo '{}')

gen=$(date '+%d.%m.%Y %H:%M')

jq -rs \
  --arg norm "$norm" \
  --arg since "$since" \
  --arg gen "$gen" \
  --argjson wmap "$wmap" '
  # — справочники —
  ["января","февраля","марта","апреля","мая","июня",
   "июля","августа","сентября","октября","ноября","декабря"] as $months
  | {breakfast:"🍳 Завтрак", lunch:"🍽️ Обед", dinner:"🥗 Ужин", snack:"🍎 Перекус"} as $mealname
  | {breakfast:0, lunch:1, dinner:2, snack:3} as $mealord
  | ($norm | if . == "" then null else tonumber end) as $norm

  # 5-блочный прогресс-бар по проценту от нормы.
  | def bar($eaten):
      if $norm == null or $norm == 0 then ""
      else (([($eaten / $norm * 5 | round), 5] | min) | if . < 0 then 0 else . end) as $f
        | "  " + (if $f > 0 then "▓" * $f else "" end)
              + (if (5 - $f) > 0 then "░" * (5 - $f) else "" end)
      end;
  def ddmm($d): ($d | split("-")) as $p
      | ($p[2] | tonumber | tostring) + " " + $months[($p[1] | tonumber) - 1];

  # — тело —
  [ .[] | select(.date >= $since) ]
  | group_by(.date)
  | sort_by(.[0].date) | reverse                       # свежие дни сверху
  | map([
      (.[0].date) as $date
      | ([ .[].total.kcal ] | add // 0 | round) as $kcal
      | ([ .[].total.protein ] | add // 0 | round) as $p
      | ([ .[].total.fat ] | add // 0 | round) as $f
      | ([ .[].total.carbs ] | add // 0 | round) as $c
      | ($wmap[$date]) as $w
      # заголовок дня
      | "## " + ddmm($date)
        + " — " + ($kcal | tostring)
        + (if $norm != null then " / " + ($norm | tostring) else "" end)
        + " ккал" + bar($kcal)
        + (if $w != null then "  ·  ⚖️ " + ($w | tostring) + " кг" else "" end)
      , "_Б" + ($p|tostring) + " Ж" + ($f|tostring) + " У" + ($c|tostring) + " г_"
      # строки приёмов в порядке завтрак→перекус
      , ( sort_by($mealord[.meal] // 9)
          | map(
              ($mealname[.meal] // .meal) + " — "
              + ([ .items[].name ] | join(", "))
              + " · " + (.total.kcal | round | tostring) + " ккал"
              + (if (.confidence // "") == "low" then " _(±)_" else "" end)
            )
          | .[] )
      , ""                                              # пустая строка между днями
    ])
  | "# 🥗 Дневник питания\n_обновлено " + $gen + "_\n"
    + (if $norm != null then "_норма: " + ($norm|tostring) + " ккал/день_\n" else "" end)
    + "\n"
    + ( [ .[] | join("\n") ] | join("\n") )
  ' "$diary" > "$out"

echo "render-diary: готово → $out"

# Копия в облако — читать дневник с телефона через Яндекс.Диск.
if [ -d "$INBOX_PATH" ]; then
  cp "$out" "$INBOX_PATH/дневник.md" 2>/dev/null && echo "render-diary: копия в инбокс → $INBOX_PATH/дневник.md"
fi
