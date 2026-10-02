#!/usr/bin/env python3
"""Regression tests for find_inconsistent_keys.py and fix_inconsistent_keys.py.

Run with: python3 -m unittest discover -s Resources/DevKit/tests
"""

import json
import os
import sys
import tempfile
import unittest

SCRIPTS_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "scripts"))
sys.path.insert(0, SCRIPTS_DIR)

import find_inconsistent_keys  # noqa: E402
import fix_inconsistent_keys  # noqa: E402


def entry(en_value, zh_value):
    return {
        "localizations": {
            "en": {"stringUnit": {"state": "translated", "value": en_value}},
            "zh-Hans": {"stringUnit": {"state": "translated", "value": zh_value}},
        }
    }


class InconsistentKeysTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.directory.name, "Localizable.xcstrings")

    def tearDown(self):
        self.directory.cleanup()

    def write_catalog(self, strings):
        with open(self.path, "w", encoding="utf-8") as handle:
            json.dump(
                {"sourceLanguage": "en", "strings": strings, "version": "1.0"},
                handle,
                ensure_ascii=False,
                indent=2,
                separators=(",", " : "),
            )
        with open(self.path, encoding="utf-8") as handle:
            return handle.read()

    def read_catalog(self):
        with open(self.path, encoding="utf-8") as handle:
            raw = handle.read()
        return raw, json.loads(raw)["strings"]

    def test_positional_english_value_keeps_key(self):
        before = self.write_catalog(
            {
                "%@ • %@": entry("%1$@ • %2$@", "%1$@ • %2$@"),
                "%lld servers imported successfully, %lld failed.": entry(
                    "%1$lld servers imported successfully, %2$lld failed.",
                    "成功导入了 %1$lld 个服务器，%2$lld 失败。",
                ),
                "%1$lld servers imported successfully, %2$lld failed.": entry(
                    "%1$lld servers imported successfully, %2$lld failed.",
                    "成功导入了 %1$lld 个服务器，%2$lld 失败。",
                ),
            }
        )

        self.assertEqual(fix_inconsistent_keys.fix_inconsistent_keys(self.path), [])

        raw, _ = self.read_catalog()
        self.assertEqual(raw, before)

    def test_mismatch_resets_english_value_without_moving_key(self):
        self.write_catalog({"A": entry("B", "甲"), "B": entry("B", "乙")})

        fixed = fix_inconsistent_keys.fix_inconsistent_keys(self.path)

        self.assertEqual(fixed, [{"key": "A", "old_value": "B"}])
        raw, strings = self.read_catalog()
        self.assertEqual(list(strings), ["A", "B"])
        self.assertEqual(strings["A"]["localizations"]["en"]["stringUnit"]["value"], "A")
        self.assertEqual(strings["A"]["localizations"]["zh-Hans"]["stringUnit"]["value"], "甲")
        self.assertEqual(strings["B"]["localizations"]["zh-Hans"]["stringUnit"]["value"], "乙")
        self.assertIn('"strings" : {', raw)

    def test_dry_run_leaves_catalog_untouched(self):
        before = self.write_catalog({"A": entry("B", "甲")})

        fixed = fix_inconsistent_keys.fix_inconsistent_keys(self.path, dry_run=True)

        self.assertEqual(fixed, [{"key": "A", "old_value": "B"}])
        raw, _ = self.read_catalog()
        self.assertEqual(raw, before)

    def test_find_ignores_positional_english_value(self):
        self.write_catalog(
            {
                "Set %@ to %@": entry("Set %1$@ to %2$@", "将 %1$@ 设为 %2$@"),
                "Duck Duck Go Search": entry("DuckDuckGo Search", "DuckDuckGo 搜索"),
            }
        )

        inconsistent = find_inconsistent_keys.find_inconsistent_keys(self.path)

        self.assertEqual([item["key"] for item in inconsistent], ["Duck Duck Go Search"])


if __name__ == "__main__":
    unittest.main()
