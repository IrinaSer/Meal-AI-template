"""Тесты scripts/render-trends.py — графики трендов веса и калорий.

Запуск: python3 -m unittest discover tests
Скрипт получает песочницу через MEAL_AI_DIR; фикстуры генерируются детерминированно
(без random) на фиксированную «сегодняшнюю» дату не нужны — скрипт берёт период
от аргумента-даты, а данные строим относительно datetime.date.today().
"""
import datetime
import json
import os
import subprocess
import sys
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(__file__), "..", "scripts", "render-trends.py")
TODAY = datetime.date.today()


def day(days_ago):
    return (TODAY - datetime.timedelta(days=days_ago)).isoformat()


class Base(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        os.makedirs(os.path.join(self.dir.name, "data"))

    def write_jsonl(self, name, rows):
        with open(os.path.join(self.dir.name, "data", name), "w",
                  encoding="utf-8") as f:
            for r in rows:
                f.write((r if isinstance(r, str) else json.dumps(r)) + "\n")

    def write_norm(self, kcal):
        with open(os.path.join(self.dir.name, "data", "norms.json"), "w") as f:
            json.dump({"kcal": kcal}, f)

    def run_script(self, *args):
        env = dict(os.environ, MEAL_AI_DIR=self.dir.name,
                   INBOX_PATH="/nonexistent")
        return subprocess.run([sys.executable, SCRIPT, *args],
                              capture_output=True, text=True, env=env)

    def fill_month(self, weight_fn, kcal=1600):
        """29 дней дневника и взвешиваний; вес дня — weight_fn(дней_назад)."""
        self.write_jsonl("diary.jsonl", [
            {"date": day(i), "total": {"kcal": kcal}} for i in range(28, -1, -1)])
        self.write_jsonl("weight.jsonl", [
            {"date": day(i), "weight_kg": weight_fn(i)} for i in range(28, -1, -1)])


class TestPlateau(Base):
    def test_plateau_with_deficit_warns_and_suggests_recalc(self):
        # неделя снижения, потом три недели ровно 67.0 — плато при дефиците
        self.fill_month(lambda i: 68.0 - (28 - i) * 0.1 if i > 21 else 67.0)
        self.write_norm(1750)
        r = self.run_script(day(29))
        self.assertEqual(r.returncode, 0)
        self.assertIn("Похоже на плато", r.stdout)
        self.assertIn("setup-profile", r.stdout)

    def test_steady_loss_no_plateau_warning(self):
        self.fill_month(lambda i: 68.5 - (28 - i) * 0.07)
        self.write_norm(1750)
        r = self.run_script(day(29))
        self.assertEqual(r.returncode, 0)
        self.assertNotIn("Похоже на плато", r.stdout)
        self.assertIn("Если при заявленном дефиците", r.stdout)

    def test_smoothed_sparkline_present(self):
        self.fill_month(lambda i: 68.5 - (28 - i) * 0.07)
        self.write_norm(1750)
        r = self.run_script(day(29))
        self.assertIn("среднее за 7 дн.", r.stdout)


class TestGraceful(Base):
    def test_empty_data_friendly_stub(self):
        r = self.run_script()
        self.assertEqual(r.returncode, 0)
        self.assertIn("Пока нет данных", r.stdout)

    def test_broken_lines_skipped_with_warning(self):
        self.write_jsonl("diary.jsonl", [
            {"date": day(1), "total": {"kcal": 1500}},
            "{битая строка",
            {"date": day(0), "total": {"kcal": 1600}}])
        r = self.run_script(day(5))
        self.assertEqual(r.returncode, 0)
        self.assertIn("битых строк", r.stderr)
        self.assertIn("1600", r.stdout)   # валидные строки посчитаны

    def test_no_norm_no_mark(self):
        self.write_jsonl("diary.jsonl", [{"date": day(0), "total": {"kcal": 1500}}])
        r = self.run_script(day(5))
        self.assertEqual(r.returncode, 0)
        self.assertNotIn("▲ норма", r.stdout)
        self.assertIn("setup-profile", r.stdout)   # подсказка настроить нормы

    def test_single_weighing_honest_message(self):
        self.write_jsonl("diary.jsonl", [{"date": day(0), "total": {"kcal": 1500}}])
        self.write_jsonl("weight.jsonl", [{"date": day(0), "weight_kg": 67}])
        r = self.run_script(day(5))
        self.assertIn("нужно хотя бы 2", r.stdout)

    def test_missing_total_summed_from_items(self):
        self.write_jsonl("diary.jsonl", [
            {"date": day(0), "items": [{"name": "x", "kcal": 300},
                                       {"name": "y", "kcal": 200}]}])
        r = self.run_script(day(5))
        self.assertIn("500", r.stdout)

    def test_bad_date_argument_fails(self):
        r = self.run_script("не-дата")
        self.assertEqual(r.returncode, 1)
        self.assertIn("YYYY-MM-DD", r.stderr)

    def test_overshoot_marked(self):
        self.write_jsonl("diary.jsonl", [{"date": day(0), "total": {"kcal": 2100}}])
        self.write_norm(1750)
        r = self.run_script(day(5))
        self.assertIn("⚠", r.stdout)

    def test_output_file_written(self):
        self.write_jsonl("diary.jsonl", [{"date": day(0), "total": {"kcal": 1500}}])
        self.run_script(day(5))
        out = os.path.join(self.dir.name, "data", "summary", "тренды.md")
        self.assertTrue(os.path.exists(out))


if __name__ == "__main__":
    unittest.main()
