#!/usr/bin/env bash
# Тесты scripts/render-diary.sh: сборка читаемого дневника из diary.jsonl.
# shellcheck disable=SC1091  # путь вычисляется в рантайме
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
SCRIPT="$REPO_DIR/scripts/render-diary.sh"
OUT="дневник.md"

render() { bash "$SCRIPT" "$@" >/dev/null; cat "$SANDBOX/data/summary/$OUT"; }

test_empty_diary_stub() {
  out=$(render)
  assert_contains "$out" "Пока ни одной записи" "заглушка на пустом дневнике"
}

test_day_rendered_with_norm_and_bar() {
  echo '{"kcal":1500}' > "$SANDBOX/data/norms.json"
  printf '{"date":"2026-06-23","meal":"lunch","items":[{"name":"гречка"}],"total":{"kcal":900,"protein":30,"fat":20,"carbs":100},"confidence":"medium"}\n' \
    > "$SANDBOX/data/diary.jsonl"
  out=$(render)
  assert_contains "$out" "## 23 июня — 900 / 1500 ккал" "заголовок дня с нормой"
  assert_contains "$out" "▓▓▓░░" "прогресс-бар 60%"
  assert_contains "$out" "🍽️ Обед — гречка · 900 ккал" "строка приёма"
}

test_norm_fallback_to_profile_md() {
  printf -- '- Калории: 1400 ккал\n' > "$SANDBOX/profile.md"
  printf '{"date":"2026-06-23","meal":"lunch","items":[{"name":"суп"}],"total":{"kcal":400,"protein":1,"fat":1,"carbs":1}}\n' \
    > "$SANDBOX/data/diary.jsonl"
  out=$(render)
  assert_contains "$out" "400 / 1400 ккал" "норма из profile.md без norms.json"
}

test_weight_shown_and_days_desc() {
  printf '%s\n' \
    '{"date":"2026-06-22","meal":"lunch","items":[{"name":"а"}],"total":{"kcal":100,"protein":1,"fat":1,"carbs":1}}' \
    '{"date":"2026-06-23","meal":"lunch","items":[{"name":"б"}],"total":{"kcal":200,"protein":1,"fat":1,"carbs":1}}' \
    > "$SANDBOX/data/diary.jsonl"
  echo '{"date":"2026-06-23","weight_kg":67.5}' > "$SANDBOX/data/weight.jsonl"
  out=$(render)
  assert_contains "$out" "⚖️ 67.5 кг" "вес в заголовке дня"
  first_day=$(printf '%s' "$out" | grep -m1 '^## ')
  assert_contains "$first_day" "23 июня" "свежий день сверху"
}

test_since_argument_filters() {
  printf '%s\n' \
    '{"date":"2026-06-01","meal":"lunch","items":[{"name":"старое"}],"total":{"kcal":100,"protein":1,"fat":1,"carbs":1}}' \
    '{"date":"2026-06-23","meal":"lunch","items":[{"name":"новое"}],"total":{"kcal":200,"protein":1,"fat":1,"carbs":1}}' \
    > "$SANDBOX/data/diary.jsonl"
  out=$(render 2026-06-10)
  assert_contains "$out" "новое" "запись в периоде"
  assert_not_contains "$out" "старое" "запись до границы отфильтрована"
}

test_low_confidence_marked() {
  printf '{"date":"2026-06-23","meal":"snack","items":[{"name":"на глаз"}],"total":{"kcal":100,"protein":1,"fat":1,"carbs":1},"confidence":"low"}\n' \
    > "$SANDBOX/data/diary.jsonl"
  out=$(render)
  assert_contains "$out" "_(±)_" "маркер низкой уверенности"
}

run_tests
