# Meal-AI — инструкции для OpenCode

Полные инструкции системы — в [CLAUDE.md](CLAUDE.md). Там же: форматы данных, конфигурация, скиллы.

## Скиллы и агент

Скиллы лежат в `.claude/skills/<name>/SKILL.md`, агент — в `.claude/agents/nutrition-coach.md`.
OpenCode пока не поддерживает `.claude/` автоматически — при необходимости скопируй нужный SKILL.md контекст вручную.

## Ключевые правила

- Язык общения — русский. Единицы: граммы и ккал.
- Дисклеймер об approximate оценке калорий по фото — всегда.
- Тон поддерживающий, без food-shaming.
- JSONL-файлы (`data/diary.jsonl`, `data/weight.jsonl`) — append-only, не перезаписывать целиком.
