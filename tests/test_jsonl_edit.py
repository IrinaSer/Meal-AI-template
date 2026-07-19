"""Тесты scripts/jsonl-edit.py — единственного писателя JSONL-журналов.

Запуск: python3 -m unittest discover tests
Гоняют реальный скрипт как подпроцесс на временных файлах — так проверяется
и CLI-контракт (коды выхода, stdout/stderr), и итоговое содержимое файла.
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(__file__), "..", "scripts", "jsonl-edit.py")


def run(*args):
    return subprocess.run([sys.executable, SCRIPT, *args],
                          capture_output=True, text=True)


class Base(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.path = os.path.join(self.dir.name, "diary.jsonl")

    def write_lines(self, *lines):
        with open(self.path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")

    def read(self):
        with open(self.path, encoding="utf-8") as f:
            return f.read()


class TestAppend(Base):
    def test_append_to_new_file(self):
        r = run("append", self.path, '{"date":"2026-07-19","weight_kg":67}')
        self.assertEqual(r.returncode, 0)
        self.assertEqual(self.read(),
                         '{"date":"2026-07-19","weight_kg":67}\n')

    def test_append_recomputes_total_from_items(self):
        rec = {"id": "x", "items": [
            {"name": "a", "kcal": 100, "protein": 10, "fat": 5.1, "carbs": 1},
            {"name": "b", "kcal": 50, "protein": 2, "fat": 1, "carbs": 2},
        ], "total": {"kcal": 999}}   # заведомо неверный total — должен пересчитаться
        r = run("append", self.path, json.dumps(rec))
        self.assertEqual(r.returncode, 0)
        saved = json.loads(self.read())
        self.assertEqual(saved["total"],
                         {"kcal": 150, "protein": 12, "fat": 6.1, "carbs": 3})

    def test_append_rejects_invalid_json(self):
        r = run("append", self.path, "{сломано")
        self.assertEqual(r.returncode, 1)
        self.assertIn("не парсится", r.stderr)
        self.assertFalse(os.path.exists(self.path))

    def test_append_rejects_non_object(self):
        r = run("append", self.path, "[1,2]")
        self.assertEqual(r.returncode, 1)
        self.assertIn("JSON-объектом", r.stderr)

    def test_trailing_newline_and_blank_lines_cleaned(self):
        with open(self.path, "w", encoding="utf-8") as f:
            f.write('{"id":"a"}\n\n\n{"id":"b"}')   # пустые строки, нет \n в конце
        r = run("append", self.path, '{"id":"c"}')
        self.assertEqual(r.returncode, 0)
        self.assertEqual(self.read(), '{"id":"a"}\n{"id":"b"}\n{"id":"c"}\n')


class TestDelete(Base):
    def test_delete_by_id(self):
        self.write_lines('{"id":"a"}', '{"id":"b"}')
        r = run("delete", self.path, "a")
        self.assertEqual(r.returncode, 0)
        self.assertIn('{"id":"a"}', r.stdout)
        self.assertEqual(self.read(), '{"id":"b"}\n')

    def test_delete_by_date(self):
        self.write_lines('{"date":"2026-07-18","weight_kg":67}',
                         '{"date":"2026-07-19","weight_kg":66.8}')
        r = run("delete", self.path, "2026-07-18")
        self.assertEqual(r.returncode, 0)
        self.assertEqual(self.read(), '{"date":"2026-07-19","weight_kg":66.8}\n')

    def test_delete_missing_key_fails(self):
        self.write_lines('{"id":"a"}')
        r = run("delete", self.path, "nope")
        self.assertEqual(r.returncode, 1)
        self.assertIn("не найдена", r.stderr)
        self.assertEqual(self.read(), '{"id":"a"}\n')   # файл не тронут

    def test_ambiguous_key_lists_candidates_and_keeps_file(self):
        self.write_lines('{"date":"2026-07-19","meal":"lunch"}',
                         '{"date":"2026-07-19","meal":"dinner"}')
        before = self.read()
        r = run("delete", self.path, "2026-07-19")
        self.assertEqual(r.returncode, 1)
        self.assertIn("line:1", r.stderr)
        self.assertIn("line:2", r.stderr)
        self.assertEqual(self.read(), before)

    def test_delete_by_line_number(self):
        self.write_lines('{"date":"2026-07-19","meal":"lunch"}',
                         '{"date":"2026-07-19","meal":"dinner"}')
        r = run("delete", self.path, "line:2")
        self.assertEqual(r.returncode, 0)
        self.assertEqual(self.read(), '{"date":"2026-07-19","meal":"lunch"}\n')

    def test_line_number_out_of_range(self):
        self.write_lines('{"id":"a"}')
        r = run("delete", self.path, "line:5")
        self.assertEqual(r.returncode, 1)
        self.assertIn("строки 5 нет", r.stderr)


class TestReplace(Base):
    def test_replace_by_id_shows_before_after(self):
        self.write_lines('{"id":"a","note":"старая"}')
        r = run("replace", self.path, "a", '{"id":"a","note":"новая"}')
        self.assertEqual(r.returncode, 0)
        self.assertIn("до:", r.stdout)
        self.assertIn("после:", r.stdout)
        self.assertEqual(self.read(), '{"id":"a","note":"новая"}\n')

    def test_replace_recomputes_total(self):
        self.write_lines('{"id":"a"}')
        r = run("replace", self.path, "a",
                '{"id":"a","items":[{"name":"x","kcal":200}]}')
        self.assertEqual(r.returncode, 0)
        self.assertEqual(json.loads(self.read())["total"]["kcal"], 200)


class TestRobustness(Base):
    def test_broken_lines_preserved_with_warning(self):
        self.write_lines('{"id":"a"}', "{битая строка", '{"id":"b"}')
        r = run("append", self.path, '{"id":"c"}')
        self.assertEqual(r.returncode, 0)
        self.assertIn("битых строк", r.stderr)
        self.assertIn("{битая строка\n", self.read())   # сохранена как есть

    def test_failed_op_leaves_no_tmp_files(self):
        self.write_lines('{"id":"a"}')
        run("delete", self.path, "nope")
        leftovers = [f for f in os.listdir(self.dir.name) if ".tmp." in f]
        self.assertEqual(leftovers, [])

    def test_unknown_command(self):
        r = run("upsert", self.path, "x")
        self.assertEqual(r.returncode, 1)
        self.assertIn("неизвестная команда", r.stderr)

    def test_concurrent_appends_all_land(self):
        """Лок: параллельные append не теряют строки и не рвут файл."""
        procs = [subprocess.Popen(
            [sys.executable, SCRIPT, "append", self.path,
             json.dumps({"id": f"r{i}"})],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            for i in range(10)]
        for p in procs:
            p.wait()
        lines = self.read().splitlines()
        self.assertEqual(len(lines), 10)
        ids = {json.loads(l)["id"] for l in lines}   # каждая строка валидна
        self.assertEqual(ids, {f"r{i}" for i in range(10)})


if __name__ == "__main__":
    unittest.main()
