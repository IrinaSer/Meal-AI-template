#!/usr/bin/env python3
"""Meal-AI — безопасная правка JSONL-журналов (data/diary.jsonl, data/weight.jsonl).

Зачем: раньше LLM правил файлы вручную — риск склеить строки, потерять
завершающий перевод строки или записать невалидный JSON. Хелпер делает всё сам:
  - атомарная запись (временный файл + os.replace) — файл не бывает полузаписан;
  - блокировка от параллельной записи (fcntl.flock на <file>.lock);
  - валидация JSON перед записью;
  - автопересчёт `total` из `items` (округление до 0.1) — руками считать не нужно;
  - гарантированный завершающий \n и отсутствие пустых строк.

Команды:
  jsonl-edit.py append  <file> '<json>'         добавить запись в конец
  jsonl-edit.py delete  <file> <key>            удалить одну запись
  jsonl-edit.py replace <file> <key> '<json>'   заменить одну запись

<key> — значение `id` (дневник) или `date` (вес/дневник за день), либо `line:N`
(номер строки, 1-based) для точного выбора. Если под ключ попадает несколько
записей — хелпер не трогает файл, а печатает кандидатов с номерами строк:
повтори с `line:N`.

Вывод: удалённая запись / «до» и «после» — на stdout. Ошибки — на stderr, код 1.
Битые строки (не-JSON) не блокируют работу: сохраняются как есть, с
предупреждением. Пустые строки внутри файла вычищаются.
"""
import fcntl
import json
import os
import sys

TOTAL_FIELDS = ("kcal", "protein", "fat", "carbs")


def die(msg):
    print(f"jsonl-edit: {msg}", file=sys.stderr)
    sys.exit(1)


def dumps(obj):
    return json.dumps(obj, ensure_ascii=False, separators=(",", ":"))


def num(x):
    """Число или 0 (страховка от null/строк в items)."""
    return x if isinstance(x, (int, float)) else 0


def recompute_total(obj):
    """Если есть items — пересчитать total как их сумму (до 0.1)."""
    items = obj.get("items")
    if isinstance(items, list) and items:
        total = {}
        for f in TOTAL_FIELDS:
            s = round(sum(num(i.get(f)) for i in items if isinstance(i, dict)), 1)
            total[f] = int(s) if s == int(s) else s
        obj["total"] = total
    return obj


def parse_record(raw):
    try:
        obj = json.loads(raw)
    except json.JSONDecodeError as e:
        die(f"переданный JSON не парсится: {e}")
    if not isinstance(obj, dict):
        die("запись должна быть JSON-объектом {...}")
    return recompute_total(obj)


def load(path):
    """[(строка, объект|None), ...] — None у битых строк, пустые выброшены."""
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        raw = f.read()
    rows = []
    for line in raw.splitlines():
        if not line.strip():
            continue
        try:
            rows.append((line, json.loads(line)))
        except json.JSONDecodeError:
            rows.append((line, None))
    broken = sum(1 for _, o in rows if o is None)
    if broken:
        print(f"jsonl-edit: внимание — {broken} битых строк, оставлены как есть",
              file=sys.stderr)
    return rows


def save(path, rows):
    """Атомарно: временный файл рядом + os.replace. Всегда завершающий \\n."""
    tmp = f"{path}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        for line, _ in rows:
            f.write(line + "\n")
    os.replace(tmp, path)


def find(rows, key):
    """Индекс единственной записи под ключ; иначе — понятная ошибка."""
    if key.startswith("line:"):
        try:
            n = int(key[5:])
        except ValueError:
            die(f"плохой номер строки: {key!r}")
        if not 1 <= n <= len(rows):
            die(f"строки {n} нет (в файле {len(rows)} непустых строк)")
        return n - 1
    hits = [i for i, (_, o) in enumerate(rows)
            if o and (o.get("id") == key or o.get("date") == key)]
    if not hits:
        die(f"запись с id/date {key!r} не найдена")
    if len(hits) > 1:
        lines = "\n".join(f"  line:{i + 1}  {rows[i][0]}" for i in hits)
        die(f"под {key!r} попадает {len(hits)} записей — уточни через line:N:\n{lines}")
    return hits[0]


def main(argv):
    if len(argv) < 3:
        die("использование: append <file> '<json>' | delete <file> <key> | "
            "replace <file> <key> '<json>'")
    cmd, path = argv[1], argv[2]

    # Лок живёт рядом с файлом (data/diary.jsonl.lock) и не удаляется —
    # так исключены гонки на пересоздании. Файл в .gitignore.
    lock = open(f"{path}.lock", "w")
    fcntl.flock(lock, fcntl.LOCK_EX)

    rows = load(path)

    if cmd == "append":
        if len(argv) != 4:
            die("append: нужно 2 аргумента — <file> '<json>'")
        obj = parse_record(argv[3])
        rows.append((dumps(obj), obj))
        save(path, rows)
        print(f"добавлено: {dumps(obj)}")
    elif cmd == "delete":
        if len(argv) != 4:
            die("delete: нужно 2 аргумента — <file> <key>")
        i = find(rows, argv[3])
        removed = rows.pop(i)
        save(path, rows)
        print(f"удалено: {removed[0]}")
    elif cmd == "replace":
        if len(argv) != 5:
            die("replace: нужно 3 аргумента — <file> <key> '<json>'")
        i = find(rows, argv[3])
        obj = parse_record(argv[4])
        old = rows[i][0]
        rows[i] = (dumps(obj), obj)
        save(path, rows)
        print(f"до:     {old}\nпосле:  {dumps(obj)}")
    else:
        die(f"неизвестная команда {cmd!r} (append | delete | replace)")


if __name__ == "__main__":
    main(sys.argv)
