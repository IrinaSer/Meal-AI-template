#!/usr/bin/env bash
# Тесты scripts/statusline.sh: строка остатка калорий в подвале.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
SCRIPT="$REPO_DIR/scripts/statusline.sh"

status() { echo '{}' | bash "$SCRIPT"; }

test_no_profile_shows_eaten_only() {
  printf '{"date":"%s","total":{"kcal":700,"protein":30,"fat":20,"carbs":80}}\n' \
    "$(days_ago 0)" > "$SANDBOX/data/diary.jsonl"
  out=$(status)
  assert_contains "$out" "700" "съеденное видно и без нормы"
  assert_not_contains "$out" "/" "без нормы нет дроби X/Y"
}

test_norm_from_norms_json() {
  echo '{"kcal":1500}' > "$SANDBOX/data/norms.json"
  printf '{"date":"%s","total":{"kcal":600,"protein":1,"fat":1,"carbs":1}}\n' \
    "$(days_ago 0)" > "$SANDBOX/data/diary.jsonl"
  out=$(status)
  assert_contains "$out" "900/1500 ккал осталось" "остаток = норма − съеденное"
}

test_norm_fallback_profile_md() {
  printf -- '- Калории: 1400 ккал\n' > "$SANDBOX/profile.md"
  printf '{"date":"%s","total":{"kcal":600,"protein":1,"fat":1,"carbs":1}}\n' \
    "$(days_ago 0)" > "$SANDBOX/data/diary.jsonl"
  out=$(status)
  assert_contains "$out" "800/1400 ккал осталось" "фолбэк на grep по profile.md"
}

test_only_today_counted() {
  printf '%s\n' \
    "{\"date\":\"$(days_ago 1)\",\"total\":{\"kcal\":900,\"protein\":1,\"fat\":1,\"carbs\":1}}" \
    "{\"date\":\"$(days_ago 0)\",\"total\":{\"kcal\":300,\"protein\":1,\"fat\":1,\"carbs\":1}}" \
    > "$SANDBOX/data/diary.jsonl"
  echo '{"kcal":1500}' > "$SANDBOX/data/norms.json"
  out=$(status)
  assert_contains "$out" "1200/1500 ккал осталось" "вчерашнее не входит в остаток сегодня"
}

test_always_single_line() {
  out=$(status)
  assert_eq 1 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "ровно одна строка"
}

run_tests
