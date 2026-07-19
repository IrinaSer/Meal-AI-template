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
# Фото моложе 1 минуты не считаем — файл может ещё докачиваться клиентом
# Яндекс.Диска; он попадёт в следующий 15-минутный цикл.
has_photos=$(find "$INBOX_PATH/photos" -type f -mmin +1 2>/dev/null | head -n1 || true)
has_notes=""
if [ -s "$INBOX_PATH/notes.md" ]; then has_notes=yes; fi
if [ -z "$has_photos" ] && [ -z "$has_notes" ]; then
  echo "$(ts) inbox empty — skip" >> "$LOG"
  exit 0
fi

# Лок от параллельных запусков: разбор с фото через claude -p может идти дольше
# 15 минут, и launchd запустит следующий цикл поверх текущего — два процесса
# начнут одновременно дописывать data/diary.jsonl. mkdir атомарен, поэтому
# годится как лок без гонок.
LOCK_DIR="$PROJECT_DIR/scripts/.process-inbox.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  # Лок старше 60 минут — остался от упавшего/убитого запуска, снимаем.
  if [ -n "$(find "$LOCK_DIR" -maxdepth 0 -mmin +60 2>/dev/null)" ]; then
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "$(ts) another run in progress — skip" >> "$LOG"
    exit 0
  fi
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT

echo "$(ts) processing inbox..." >> "$LOG"
cd "$PROJECT_DIR"

# Неинтерактивный запуск Claude Code. Разрешения на запись/перемещение файлов
# для headless-режима преднастроены в .claude/settings.json (секция permissions) —
# без них claude -p остановился бы на запросе прав.
"$CLAUDE_BIN" -p "Запусти скилл process-inbox: разбери облачный инбокс и обнови ответ.md с остатком калорий за сегодня." \
  >> "$LOG" 2>&1 || echo "$(ts) claude exited non-zero" >> "$LOG"

echo "$(ts) done" >> "$LOG"
