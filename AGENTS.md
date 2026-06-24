# Meal-AI — инструкции для OpenCode

Полные инструкции системы — в [CLAUDE.md](CLAUDE.md). Там же: форматы данных, конфигурация, скиллы.

## Скиллы и агент

Скиллы лежат в `.claude/skills/<name>/SKILL.md`, агент — в `.claude/agents/nutrition-coach.md`.
OpenCode читает `CLAUDE.md` из корня проекта автоматически, но не подключает
`.claude/skills/*/SKILL.md` как отдельные скиллы — они доступны только через Claude Code.

## Ключевые правила

- Язык общения — русский. Единицы: граммы и ккал.
- Дисклеймер об approximate оценке калорий по фото — всегда.
- Тон поддерживающий, без food-shaming.
- JSONL-файлы (`data/diary.jsonl`, `data/weight.jsonl`) — append-only, не перезаписывать целиком.
- Обновление кода из шаблона: `scripts/update-from-template.sh`. Личные данные (data/, profile.md, reference/foods.csv) не затрагиваются.
