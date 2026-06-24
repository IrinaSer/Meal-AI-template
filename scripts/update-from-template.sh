#!/usr/bin/env bash
# Обновляет КОД системы Meal-AI из репозитория-шаблона, НЕ трогая личные данные.
#
# Запускать из инстанса (например ~/Projects/Meal-AI):
#   ./scripts/update-from-template.sh
#
# Требуется один раз добавить remote на шаблон:
#   git remote add template ../Meal-AI-template      # или GitHub-URL
#
# Переопределяемо через окружение: TEMPLATE_REMOTE, TEMPLATE_BRANCH.
set -euo pipefail

REMOTE="${TEMPLATE_REMOTE:-template}"
BRANCH="${TEMPLATE_BRANCH:-main}"

# Пути с КОДОМ — синхронизируются из шаблона.
# Личное (data/, profile.md, photos/, reference/foods.csv) НЕ трогаем.
CODE_PATHS=(
  CLAUDE.md
  README.md
  LICENSE
  .claude/skills
  .claude/agents
  .claude/settings.json
  scripts/process-inbox.sh
  scripts/com.meal-ai.inbox.plist
  scripts/session-welcome.sh
  scripts/update-from-template.sh
  reference/portion-guide.md
  reference/vacation-mode.md
)

cd "$(git rev-parse --show-toplevel)"

if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
  echo "Нет remote '$REMOTE'. Добавь его, например:" >&2
  echo "  git remote add $REMOTE ../Meal-AI-template" >&2
  exit 1
fi

echo "Тяну код из $REMOTE/$BRANCH…"
git fetch "$REMOTE"

# Берём только пути, реально существующие в шаблоне, чтобы checkout не падал.
existing=()
for p in "${CODE_PATHS[@]}"; do
  if git cat-file -e "$REMOTE/$BRANCH:$p" 2>/dev/null; then
    existing+=("$p")
  else
    echo "  пропуск (нет в шаблоне): $p"
  fi
done

if [ ${#existing[@]} -eq 0 ]; then
  echo "Нечего синхронизировать." >&2
  exit 1
fi

git checkout "$REMOTE/$BRANCH" -- "${existing[@]}"

if git diff --cached --quiet; then
  echo "Код уже актуален — изменений нет."
  exit 0
fi

echo "Изменения:"
git status --short
git commit -m "Обновление кода из шаблона ($REMOTE/$BRANCH)"
echo "Готово. Личные данные (дневник, вес, профиль, фото, foods.csv) не затронуты."
