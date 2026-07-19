#!/usr/bin/env bash
# Тесты scripts/backup-data.sh: авто-коммит личных данных и пуш в origin.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
SCRIPT="$REPO_DIR/scripts/backup-data.sh"

# Поверх обычной песочницы — git-репо с bare-origin.
make_git_sandbox() {
  git -C "$SANDBOX" init -q -b main
  git -C "$SANDBOX" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  ORIGIN="$(mktemp -d)/origin.git"
  git init -q --bare "$ORIGIN"
  git -C "$SANDBOX" remote add origin "$ORIGIN"
  git -C "$SANDBOX" push -qu origin main 2>/dev/null
  export GIT_AUTHOR_EMAIL=t@t GIT_AUTHOR_NAME=t GIT_COMMITTER_EMAIL=t GIT_COMMITTER_NAME=t
}

backup() { (cd "$SANDBOX" && bash "$SCRIPT"); }

test_data_committed_and_pushed() {
  make_git_sandbox
  echo '{"date":"2026-07-19","weight_kg":67}' > "$SANDBOX/data/weight.jsonl"
  backup
  msg=$(git -C "$ORIGIN" log -1 --format=%s main)
  assert_contains "$msg" "data: авто-бэкап" "коммит уехал в origin"
}

test_code_changes_not_committed() {
  make_git_sandbox
  echo "код" > "$SANDBOX/scripts/some-script.sh"
  echo '{"x":1}' > "$SANDBOX/data/diary.jsonl"
  backup
  files=$(git -C "$SANDBOX" show --name-only --format= HEAD)
  assert_contains "$files" "data/diary.jsonl" "данные закоммичены"
  assert_not_contains "$files" "scripts/some-script.sh" "код не тронут"
}

test_no_changes_no_commit() {
  make_git_sandbox
  before=$(git -C "$SANDBOX" rev-parse HEAD)
  backup
  assert_eq "$before" "$(git -C "$SANDBOX" rev-parse HEAD)" "без изменений нет коммита"
}

test_push_failure_keeps_commit_local() {
  make_git_sandbox
  git -C "$SANDBOX" remote set-url origin /nonexistent/origin.git
  echo '{"x":1}' > "$SANDBOX/data/diary.jsonl"
  backup
  msg=$(git -C "$SANDBOX" log -1 --format=%s)
  assert_contains "$msg" "data: авто-бэкап" "коммит есть локально при недоступном origin"
  assert_contains "$(cat "$SANDBOX/scripts/backup-data.log")" "пуш не удался" "лог честный"
}

run_tests
