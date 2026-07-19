#!/usr/bin/env bash
# Meal-AI — приветствие при старте сессии (хук SessionStart в .claude/settings.json).
# Показывает дату, статистику за сегодня, серию дней 🔥 и (если давно не взвешивалась)
# напоминание о весе, плюс быстрые команды.
#
# Читает JSON хука со stdin (поле .source). На source=compact молчит, чтобы не
# мусорить после авто-компакта. Безопасен при отсутствии jq или пустом дневнике.
set -uo pipefail

# Нет jq — приветствия не будет, но старт сессии не ломаем.
command -v jq >/dev/null 2>&1 || exit 0

# Каталог проекта по расположению скрипта — не зависит от cwd.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Порог напоминания о весе — из CLAUDE.md (WEIGH_IN_REMINDER_DAYS), та же
# настройка, что использует log-meal. Фолбэк 2, если в CLAUDE.md не нашли.
WEIGH_NUDGE_DAYS=$(grep -m1 'WEIGH_IN_REMINDER_DAYS' "$PROJECT_DIR/CLAUDE.md" 2>/dev/null | grep -oE '[0-9]+' | head -n1)
[ -z "${WEIGH_NUDGE_DAYS:-}" ] && WEIGH_NUDGE_DAYS=2

input=$(cat)
src=$(printf '%s' "$input" | jq -r '.source // "startup"' 2>/dev/null)
[ "$src" = "compact" ] && exit 0

today=$(date +%d.%m.%Y)
key=$(date +%Y-%m-%d)
diary="$PROJECT_DIR/data/diary.jsonl"
weight="$PROJECT_DIR/data/weight.jsonl"

prev_day() { date -j -v-1d -f "%Y-%m-%d" "$1" +%Y-%m-%d 2>/dev/null || date -d "$1 -1 day" +%Y-%m-%d 2>/dev/null; }
to_epoch() { date -j -f "%Y-%m-%d" "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null; }
day_word() { local n=$1; if [ $((n%100)) -ge 11 ] && [ $((n%100)) -le 14 ]; then echo дней; else case $((n%10)) in 1) echo день;; 2|3|4) echo дня;; *) echo дней;; esac; fi; }
meal_word() { case "$1" in 1) echo приём;; 2|3|4) echo приёма;; *) echo приёмов;; esac; }

wnudge=""
if [ -s "$diary" ]; then
  # Сводка за сегодня.
  read -r meals eaten < <(jq -rs --arg d "$key" '[.[]|select(.date==$d)] as $t | "\($t|length) \([$t[].total.kcal]|add // 0|round)"' "$diary" 2>/dev/null)
  meals=${meals:-0}; eaten=${eaten:-0}
  if [ "$meals" -gt 0 ]; then
    line="Сегодня: ${meals} $(meal_word "$meals"), ${eaten} ккал"
  else
    line="Сегодня записей пока нет."
  fi

  # Серия: подряд идущие дни с записями, заканчивая сегодня (или вчера, если сегодня пусто).
  dates=$(jq -rs '[.[].date]|unique|.[]' "$diary" 2>/dev/null)
  streak=0; d="$key"
  printf '%s\n' "$dates" | grep -qx "$d" || d=$(prev_day "$d")
  while [ -n "$d" ] && printf '%s\n' "$dates" | grep -qx "$d"; do
    streak=$((streak+1)); d=$(prev_day "$d")
  done
  [ "$streak" -ge 2 ] && line="${line} · 🔥 серия ${streak} $(day_word "$streak")"

  # Напоминание о весе — только когда система уже в ходу (есть записи еды).
  lastw=""
  [ -s "$weight" ] && lastw=$(jq -rs '[.[].date]|max // empty' "$weight" 2>/dev/null)
  if [ -z "$lastw" ]; then
    wnudge="⚖️ Запиши вес — скажи число, добавлю в журнал."
  else
    gap=$(( ( $(to_epoch "$key") - $(to_epoch "$lastw") ) / 86400 ))
    [ "$gap" -ge "$WEIGH_NUDGE_DAYS" ] && wnudge="⚖️ Вес не писала ${gap} дн. — скажи число, обновлю."
  fi
else
  line="Сегодня записей пока нет."
fi

# Сборка сообщения (напоминание о весе — отдельной строкой, если есть).
body="$line"
[ -n "${wnudge:-}" ] && body="${body}"$'\n'"${wnudge}"

msg=$(printf '🥗 Meal-AI · %s\n%s\n\n• фото еды → запишу приём\n• «мой вес 68» → журнал веса\n• «отчёт за неделю» → сводка\n• «разбери инбокс» → телефон' "$today" "$body")
jq -n --arg m "$msg" '{systemMessage:$m}'
