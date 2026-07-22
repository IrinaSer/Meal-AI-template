#!/usr/bin/env python3
"""Meal-AI — тренды веса и калорий: Unicode-графики в терминале и в Markdown.

Без API и внешних зависимостей: голый python3 читает data/diary.jsonl,
data/weight.jsonl и норму из data/norms.json (фолбэк — grep по profile.md)
и рисует:
  - калории по дням — горизонтальные бары с меткой нормы и подсветкой перебора;
  - вес — спарклайн, дельта и сглаженный тренд (среднее за 7 дней);
  - недельную сводку «средний калораж ↔ изменение веса» — работает ли дефицит.

Запуск: scripts/render-trends.py [YYYY-MM-DD]   # нижняя граница периода
        без аргумента — последние 30 дней.

Печатает на stdout и пишет data/summary/тренды.md; если существует облачный
инбокс (INBOX_PATH) — кладёт копию туда, чтобы смотреть с телефона.
Грейсфул: пустой дневник → понятная заглушка; битые JSONL-строки пропускаются
с предупреждением; без нормы бары рисуются без метки; < 2 взвешиваний —
честно так и пишет.
"""
import datetime
import json
import os
import re
import shutil
import sys

BAR_W = 28                 # ширина бара калорий в клетках
SPARK = "▁▂▃▄▅▆▇█"         # градации спарклайна веса
PLATEAU_WEEKS = 3          # столько последних недель почти без движения веса — плато
PLATEAU_EPS_KG = 0.3       # «почти без движения» — размах веса в пределах этого
MEASURE_FIELDS = [("waist_cm", "Талия"), ("hips_cm", "Бёдра"), ("chest_cm", "Грудь")]
# Корень проекта: по расположению скрипта; MEAL_AI_DIR переопределяет (тесты).
PROJECT_DIR = os.environ.get(
    "MEAL_AI_DIR", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
INBOX_PATH = os.environ.get(
    "INBOX_PATH", os.path.expanduser("~/Yandex.Disk.localized/Meal-AI-Inbox"))


def p(path):
    return os.path.join(PROJECT_DIR, path)


def load_jsonl(path):
    """Записи файла; битые строки пропускаются с предупреждением."""
    rows, broken = [], 0
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            if not line.strip():
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                broken += 1
    if broken:
        print(f"render-trends: {broken} битых строк в {os.path.basename(path)} — "
              f"пропущены", file=sys.stderr)
    return rows


def load_norm():
    """Норма ккал: data/norms.json, фолбэк — строка «- Калории: N» в profile.md."""
    try:
        n = json.load(open(p("data/norms.json"), encoding="utf-8")).get("kcal")
        if isinstance(n, (int, float)) and n > 0:
            return round(n)
    except Exception:
        pass
    try:
        for line in open(p("profile.md"), encoding="utf-8"):
            m = re.match(r"^- Калории:\D*(\d+)", line)
            if m:
                return int(m.group(1))
    except Exception:
        pass
    return None


def entry_kcal(e):
    """Ккал записи: total, а если его нет — сумма по items (правило CLAUDE.md)."""
    t = e.get("total")
    if isinstance(t, dict) and isinstance(t.get("kcal"), (int, float)):
        return t["kcal"]
    items = e.get("items")
    if isinstance(items, list):
        return sum(i.get("kcal", 0) for i in items
                   if isinstance(i, dict) and isinstance(i.get("kcal"), (int, float)))
    return 0


def valid_date(s):
    try:
        return datetime.date.fromisoformat(s)
    except (TypeError, ValueError):
        return None


def fmt_kg(v):
    return f"{v:g}"


def section_kcal(kcal_by_day, norm):
    out = ["## Калории по дням" + (f" (норма {norm} ккал)" if norm else ""), "```"]
    days = sorted(kcal_by_day)
    mx = max(max(kcal_by_day.values()), norm or 0)
    for d in days:
        k = round(kcal_by_day[d])
        bar = "█" * max(1, round(k / mx * BAR_W)) if k else ""
        mark = " ⚠" if norm and k > norm else ""
        out.append(f"{d.strftime('%d.%m')} {bar:<{BAR_W}} {k}{mark}")
    if norm:
        out.append(" " * (6 + round(norm / mx * BAR_W) - 1) + "▲ норма")
    # средние за период
    avg = round(sum(kcal_by_day.values()) / len(days))
    line = f"в среднем {avg} ккал/день за {len(days)} дн. с записями"
    if norm:
        line += f" ({avg - norm:+} к норме)"
    out += ["", line, "```"]
    return out


def smooth(ws, i, days=7):
    """Среднее взвешиваний за `days` дней, заканчивая датой ws[i]."""
    end = ws[i][0]
    start = end - datetime.timedelta(days=days - 1)
    vals = [v for d, v in ws if start <= d <= end]
    return sum(vals) / len(vals)


def section_weight(ws):
    out = ["## Вес", "```"]
    if len(ws) < 2:
        got = f"пока {len(ws)}" if ws else "пока нет"
        out += [f"Взвешиваний {got} — для тренда нужно хотя бы 2.",
                "Пиши вес раз в 1–3 дня («мой вес 68») — тренд появится здесь.", "```"]
        return out
    vals = [v for _, v in ws]
    lo, hi = min(vals), max(vals)
    spark = "".join(SPARK[round((v - lo) / (hi - lo or 1) * 7)] for v in vals)
    delta = vals[-1] - vals[0]
    span = (ws[-1][0] - ws[0][0]).days
    out.append(f"{fmt_kg(vals[0])} → {fmt_kg(vals[-1])} кг ({delta:+.1f}) "
               f"за {span} дн. · {len(ws)} взвешиваний")
    out.append(f"{spark}   (min {fmt_kg(lo)} · max {fmt_kg(hi)})")
    # Сглаженный тренд: сырой вес скачет от воды и еды, смотрим среднее за 7 дней.
    if len(ws) >= 5:
        sm = [smooth(ws, i) for i in range(len(ws))]
        slo, shi = min(sm), max(sm)
        sspark = "".join(SPARK[round((v - slo) / (shi - slo or 1) * 7)] for v in sm)
        out.append(f"{sspark}   среднее за 7 дн.: {sm[0]:.1f} → {sm[-1]:.1f} кг "
                   f"({sm[-1] - sm[0]:+.1f})")
    out.append("```")
    return out


def section_measurements(ms):
    """Обмеры тела: по каждому полю (талия/бёдра/грудь) — свой тренд,
    отдельно от других, т.к. мерят их не всегда все разом."""
    if not ms:
        return []
    lines = []
    for field, label in MEASURE_FIELDS:
        pts = sorted((d, m[field]) for d, m in ms if field in m)
        if len(pts) < 2:
            continue
        vals = [v for _, v in pts]
        lo, hi = min(vals), max(vals)
        spark = "".join(SPARK[round((v - lo) / (hi - lo or 1) * 7)] for v in vals)
        delta = vals[-1] - vals[0]
        span = (pts[-1][0] - pts[0][0]).days
        lines.append(f"{label}: {fmt_kg(vals[0])} → {fmt_kg(vals[-1])} см "
                     f"({delta:+.1f}) за {span} дн. · {spark}")
    out = ["## Обмеры", "```"]
    if lines:
        out += lines
    else:
        out.append("Мерь раз в 1–2 недели — для тренда по каждому обмеру нужно "
                    "хотя бы 2 записи.")
    out.append("```")
    return out


def section_weeks(kcal_by_day, ws, norm):
    """Недели: средний калораж против изменения веса — работает ли дефицит."""
    weeks = {}
    for d, k in kcal_by_day.items():
        y, w, _ = d.isocalendar()
        weeks.setdefault((y, w), []).append(k)
    if len(weeks) < 2:
        return []
    # последнее взвешивание каждой недели (включая недели вне периода калорий)
    w_last = {}
    for d, v in ws:
        y, w, _ = d.isocalendar()
        w_last[(y, w)] = v   # ws отсортирован по дате — останется последнее
    out = ["## Недели: калораж ↔ вес", "```"]
    prev_w = None
    for wk in sorted(weeks):
        avg = round(sum(weeks[wk]) / len(weeks[wk]))
        line = f"W{wk[1]:02d}  ср. {avg} ккал/д"
        if norm:
            line += f" ({avg - norm:+} к норме)"
        if wk in w_last and prev_w is not None:
            line += f"   вес {w_last[wk] - prev_w:+.1f} кг"
        elif wk in w_last:
            line += f"   вес {fmt_kg(w_last[wk])} кг"
        prev_w = w_last.get(wk, prev_w)
        out.append(line)
    out.append("```")
    # Плато: последние PLATEAU_WEEKS недель с взвешиваниями вес стоит на месте.
    recent_wks = sorted(w_last)[-PLATEAU_WEEKS:]
    recent = [w_last[wk] for wk in recent_wks]
    if len(recent) >= PLATEAU_WEEKS and max(recent) - min(recent) <= PLATEAU_EPS_KG:
        kcals = [k for wk in recent_wks for k in weeks.get(wk, [])]
        note = (f"⚠ Похоже на плато: вес почти не меняется {PLATEAU_WEEKS} недели подряд"
                f" (размах ≤ {fmt_kg(PLATEAU_EPS_KG)} кг).")
        if norm and kcals and sum(kcals) / len(kcals) < norm:
            note += (" При этом дневник показывает дефицит — вероятно, порции"
                     " недооцениваются, либо норма устарела: пересчитай её"
                     " (setup-profile).")
        else:
            note += " Если цель — снижение веса, стоит пересмотреть рацион или нормы."
        out.append(note)
    else:
        out += ["_Если при заявленном дефиците вес стоит несколько недель — порции,_",
                "_скорее всего, недооцениваются, либо норму пора пересчитать._"]
    return out


def main():
    since = valid_date(sys.argv[1]) if len(sys.argv) > 1 else \
        datetime.date.today() - datetime.timedelta(days=30)
    if since is None:
        print("render-trends: плохая дата, нужен формат YYYY-MM-DD", file=sys.stderr)
        sys.exit(1)

    diary = load_jsonl(p("data/diary.jsonl"))
    weights = load_jsonl(p("data/weight.jsonl"))
    measurements = load_jsonl(p("data/measurements.jsonl"))
    norm = load_norm()

    kcal_by_day = {}
    for e in diary:
        d = valid_date(e.get("date"))
        if d and d >= since:
            kcal_by_day[d] = kcal_by_day.get(d, 0) + entry_kcal(e)
    ws = sorted(((valid_date(w.get("date")), w.get("weight_kg")) for w in weights),
                key=lambda x: (x[0] or datetime.date.min))
    ws = [(d, v) for d, v in ws if d and d >= since and isinstance(v, (int, float))]
    ms = [(d, m) for d, m in
          ((valid_date(m.get("date")), m) for m in measurements)
          if d and d >= since]

    gen = datetime.datetime.now().strftime("%d.%m.%Y %H:%M")
    lines = ["# 📈 Тренды веса и калорий",
             f"_обновлено {gen} · период с {since.strftime('%d.%m.%Y')}_", ""]
    if not kcal_by_day and not ws and not ms:
        lines += ["Пока нет данных за период. Запиши приём пищи (пришли фото) и вес",
                  "(«мой вес 68») — здесь появятся графики."]
    else:
        if kcal_by_day:
            lines += section_kcal(kcal_by_day, norm) + [""]
        else:
            lines += ["## Калории по дням", "Записей еды за период нет.", ""]
        lines += section_weight(ws)
        sm = section_measurements(ms)
        if sm:
            lines += [""] + sm
        wk = section_weeks(kcal_by_day, ws, norm)
        if wk:
            lines += [""] + wk
        if not norm:
            lines += ["", "_Нормы не настроены — запусти setup-profile, и на графиках_",
                      "_появятся метка нормы и сравнение с целью._"]

    text = "\n".join(lines) + "\n"
    print(text, end="")

    out = p("data/summary/тренды.md")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"render-trends: сохранено → {out}", file=sys.stderr)
    if os.path.isdir(INBOX_PATH):
        try:
            shutil.copy(out, os.path.join(INBOX_PATH, "тренды.md"))
            print("render-trends: копия в инбокс", file=sys.stderr)
        except OSError:
            pass


if __name__ == "__main__":
    main()
