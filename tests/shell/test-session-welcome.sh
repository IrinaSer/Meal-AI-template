#!/usr/bin/env bash
# Тесты scripts/session-welcome.sh: приветствие, серия, напоминание о весе.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
SCRIPT="$REPO_DIR/scripts/session-welcome.sh"

welcome() {   # welcome [source] → текст systemMessage
  echo "{\"source\":\"${1:-startup}\"}" | bash "$SCRIPT" | jq -r '.systemMessage // ""'
}

test_silent_on_compact() {
  out=$(welcome compact)
  assert_eq "" "$out" "на compact — молчание"
}

test_empty_diary_greeting() {
  out=$(welcome)
  assert_contains "$out" "Сегодня записей пока нет" "заглушка без записей"
  assert_not_contains "$out" "⚖️" "нет напоминания о весе, пока система не в ходу"
}

test_today_summary_and_meal_word() {
  printf '{"date":"%s","total":{"kcal":700}}\n' "$(days_ago 0)" > "$SANDBOX/data/diary.jsonl"
  out=$(welcome)
  assert_contains "$out" "1 приём, 700 ккал" "сводка и склонение"
}

test_streak_counted() {
  for i in 2 1 0; do
    printf '{"date":"%s","total":{"kcal":500}}\n' "$(days_ago "$i")"
  done > "$SANDBOX/data/diary.jsonl"
  out=$(welcome)
  assert_contains "$out" "серия 3 дня" "серия за 3 подряд дня"
}

test_weigh_nudge_no_weight_at_all() {
  printf '{"date":"%s","total":{"kcal":500}}\n' "$(days_ago 0)" > "$SANDBOX/data/diary.jsonl"
  out=$(welcome)
  assert_contains "$out" "⚖️ Запиши вес" "первое взвешивание"
}

test_weigh_nudge_after_threshold() {
  printf '{"date":"%s","total":{"kcal":500}}\n' "$(days_ago 0)" > "$SANDBOX/data/diary.jsonl"
  printf '{"date":"%s","weight_kg":67}\n' "$(days_ago 3)" > "$SANDBOX/data/weight.jsonl"
  out=$(welcome)
  assert_contains "$out" "⚖️ Вес не писала 3 дн" "порог 2 дня из CLAUDE.md превышен"
}

test_no_nudge_when_fresh_weight() {
  printf '{"date":"%s","total":{"kcal":500}}\n' "$(days_ago 0)" > "$SANDBOX/data/diary.jsonl"
  printf '{"date":"%s","weight_kg":67}\n' "$(days_ago 1)" > "$SANDBOX/data/weight.jsonl"
  out=$(welcome)
  assert_not_contains "$out" "⚖️" "вчерашний вес — без напоминания"
}

test_threshold_read_from_claude_md() {
  printf -- '- `WEIGH_IN_REMINDER_DAYS = 5` — порог.\n' > "$SANDBOX/CLAUDE.md"
  printf '{"date":"%s","total":{"kcal":500}}\n' "$(days_ago 0)" > "$SANDBOX/data/diary.jsonl"
  printf '{"date":"%s","weight_kg":67}\n' "$(days_ago 3)" > "$SANDBOX/data/weight.jsonl"
  out=$(welcome)
  assert_not_contains "$out" "⚖️" "порог 5 из CLAUDE.md — 3 дня ещё не повод"
}

run_tests
