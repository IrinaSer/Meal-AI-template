#!/usr/bin/env bash
# Раннер shell-тестов Meal-AI: гоняет все tests/shell/test-*.sh, итожит.
# Запуск: tests/shell/run.sh
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

command -v jq >/dev/null 2>&1 || { echo "нужен jq"; exit 1; }

rc=0
for t in test-*.sh; do
  echo "== $t"
  bash "$t" || rc=1
done
[ $rc -eq 0 ] && echo "== все shell-тесты прошли" || echo "== ЕСТЬ ПАДЕНИЯ"
exit $rc
