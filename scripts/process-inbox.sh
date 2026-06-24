#!/bin/bash
# Meal-AI — фоновая обработка облачного инбокса (Фаза B).
# Запускается launchd-агентом раз в ~15 мин. Использует подписку Claude Code
# (claude -p), без отдельного API-ключа и сервера.
#
# ВНИМАНИЕ: загружать launchd-агент только ПОСЛЕ установки Яндекс.Диска и
# проверки INBOX_PATH. До этого скрипт просто тихо выходит.

set -euo pipefail

# Каталог проекта определяется по расположению самого скрипта — настраивать не нужно.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Полный путь к claude — launchd не наследует PATH. Автопоиск; при необходимости
# задайте вручную: CLAUDE_BIN="$HOME/.local/bin/claude" (узнать путь: `which claude`).
CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || echo "$HOME/.local/bin/claude")}"
# Должно совпадать с INBOX_PATH в CLAUDE.md (уточнить после установки Яндекс.Диска):
INBOX_PATH="${MEAL_AI_INBOX:-$HOME/Yandex.Disk.localized/Meal-AI-Inbox}"
LOG="$PROJECT_DIR/scripts/process-inbox.log"

ts() { date '+%Y-%m-%d %H:%M:%S'; }

# Инбокса ещё нет (клиент не установлен / не залогинен) — выходим тихо.
if [ ! -d "$INBOX_PATH" ]; then
  echo "$(ts) inbox not found ($INBOX_PATH) — skip" >> "$LOG"
  exit 0
fi

# Есть ли что обрабатывать: фото или непустой notes.md?
has_photos=$(find "$INBOX_PATH/photos" -type f 2>/dev/null | head -n1 || true)
has_notes=$( [ -s "$INBOX_PATH/notes.md" ] && echo yes || true )
if [ -z "$has_photos" ] && [ -z "$has_notes" ]; then
  echo "$(ts) inbox empty — skip" >> "$LOG"
  exit 0
fi

echo "$(ts) processing inbox..." >> "$LOG"
cd "$PROJECT_DIR"

# Неинтерактивный запуск Claude Code. Для фоновой работы нужны разрешения на
# запись/перемещение файлов — выдать заранее в .claude/settings.json
# (через скилл update-config), иначе headless-режим остановится на запросе прав.
"$CLAUDE_BIN" -p "Запусти скилл process-inbox: разбери облачный инбокс и обнови ответ.md с остатком калорий за сегодня." \
  >> "$LOG" 2>&1 || echo "$(ts) claude exited non-zero" >> "$LOG"

echo "$(ts) done" >> "$LOG"
