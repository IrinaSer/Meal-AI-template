#!/usr/bin/env bash
# Общие assert-функции для shell-тестов Meal-AI. Без bats — голый bash.
# Каждый тест-файл: source helpers.sh, функции test_*, в конце run_tests.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
_FAILS=0
_COUNT=0

fail() { echo "    FAIL: $*" >&2; _FAILS=$((_FAILS + 1)); }

assert_eq() {   # assert_eq <ожидание> <факт> [описание]
  [ "$1" = "$2" ] || fail "${3:-assert_eq}: ожидалось [$1], получено [$2]"
}

assert_contains() {   # assert_contains <строка> <подстрока> [описание]
  case "$1" in *"$2"*) ;; *) fail "${3:-assert_contains}: нет [$2] в [$1]";; esac
}

assert_not_contains() {
  case "$1" in *"$2"*) fail "${3:-assert_not_contains}: найдено [$2]";; esac
}

days_ago() {   # дата N дней назад, YYYY-MM-DD; работает на BSD (Мак) и GNU date
  date -j -v-"$1"d +%Y-%m-%d 2>/dev/null || date -d "-$1 day" +%Y-%m-%d
}

# Песочница-проект: минимальное дерево + CLAUDE.md с настройками по умолчанию.
make_sandbox() {
  SANDBOX="$(mktemp -d)"
  mkdir -p "$SANDBOX/data" "$SANDBOX/scripts"
  printf -- '- `WEIGH_IN_REMINDER_DAYS = 2` — порог напоминания.\n' > "$SANDBOX/CLAUDE.md"
  export MEAL_AI_DIR="$SANDBOX" INBOX_PATH=/nonexistent
}

run_tests() {
  for t in $(declare -F | awk '$3 ~ /^test_/ {print $3}'); do
    _COUNT=$((_COUNT + 1))
    local _fails_before=$_FAILS   # имя с подчёркиванием — не столкнётся с переменными теста
    make_sandbox
    "$t"
    rm -rf "$SANDBOX"
    if [ $_FAILS -eq $_fails_before ]; then echo "  ok: $t"; else echo "  FAILED: $t"; fi
  done
  echo "  -- $_COUNT тестов, ошибок: $_FAILS"
  [ $_FAILS -eq 0 ]
}
