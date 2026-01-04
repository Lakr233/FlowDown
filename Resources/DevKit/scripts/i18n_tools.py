#!/usr/bin/env python3
"""
Shared helpers for FlowDown localization maintenance scripts.

These utilities keep the behavior between our translation scripts consistent
and remove duplication across per-locale entrypoints.
"""

import json
import os
import sys
from typing import Any, Dict, Iterable, List, Optional, Tuple

# Languages we keep without auto-filling from English
DEFAULT_KEEP_LANGUAGES = {"ja", "de", "fr", "es", "ko", "zh-Hans"}


def default_file_path() -> str:
    """Return the absolute path to FlowDown/Resources/Localizable.xcstrings."""
    return os.path.abspath(
        os.path.join(
            os.path.dirname(__file__),
            "..",
            "..",
            "FlowDown",
            "Resources",
            "Localizable.xcstrings",
        )
    )


def load_strings(file_path: str) -> Dict[str, Any]:
    """Load the xcstrings JSON with helpful error messages."""
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"❌ File not found: {file_path}")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"❌ JSON decode error in {file_path}: {e}")
        sys.exit(1)


def save_strings(file_path: str, data: Dict[str, Any]) -> None:
    """Persist the xcstrings JSON."""
    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(
            data,
            f,
            ensure_ascii=False,
            indent=2,
            separators=(",", " : "),
        )


def should_translate(entry: Dict[str, Any]) -> bool:
    """Return whether this entry should be translated based on JSON flag."""
    return entry.get("shouldTranslate", True) is not False


def merge_new_strings(strings: Dict[str, Any], new_strings: Dict[str, Dict[str, str]]) -> int:
    """
    Ensure explicitly provided translations exist, including English anchors.
    The structure mirrors NEW_STRINGS used by the legacy scripts:
    {
        "Key": {"es": "Valor", "zh-Hans": "示例"}
    }
    Returns the number of translations applied.
    """
    applied = 0
    for key, translations in new_strings.items():
        entry = strings.setdefault(key, {})
        if entry.get("shouldTranslate") is False:
            entry.pop("shouldTranslate", None)

        locs = entry.setdefault("localizations", {})
        locs.setdefault(
            "en",
            {
                "stringUnit": {
                    "state": "translated",
                    "value": key,
                }
            },
        )

        for language, value in translations.items():
            existing = locs.get(language, {}).get("stringUnit", {}).get("value", "")
            if existing != value:
                applied += 1
            locs[language] = {
                "stringUnit": {
                    "state": "translated",
                    "value": value,
                }
            }
    return applied


def collect_languages(strings: Dict[str, Any]) -> set:
    """Collect language codes present in any string entry."""
    languages = set()
    for value in strings.values():
        locs = value.get("localizations", {})
        languages.update(locs.keys())
    return languages


def update_missing_translations(
    data: Dict[str, Any],
    new_strings: Optional[Dict[str, Dict[str, str]]] = None,
    keep_languages: Optional[Iterable[str]] = None,
) -> Dict[str, int]:
    """
    Fill missing English anchors and apply explicit translations.

    This intentionally avoids clearing or adding placeholder entries so
    manual translation work is preserved.
    """
    new_strings = new_strings or {}
    strings = data["strings"]

    merged_count = merge_new_strings(strings, new_strings)

    counts = {
        "added_en": 0,
        "fixed_en_state": 0,
        "applied_translations": merged_count,
    }

    for key, value in strings.items():
        locs = value.setdefault("localizations", {})

        if "en" not in locs:
            locs["en"] = {
                "stringUnit": {
                    "state": "translated",
                    "value": key,
                }
            }
            counts["added_en"] += 1

        en_unit = locs["en"].setdefault("stringUnit", {})
        if en_unit.get("state") == "new":
            if not en_unit.get("value", "").strip():
                en_unit["value"] = key
            en_unit["state"] = "translated"
            counts["fixed_en_state"] += 1
        english_value = en_unit.get("value", key)

        for language, translation in new_strings.get(key, {}).items():
            current_unit = locs.get(language, {}).get("stringUnit", {})
            current_value = current_unit.get("value", "").strip()
            if current_value:
                if (
                    current_value == english_value
                    and translation
                    and translation != english_value
                ):
                    locs[language] = {
                        "stringUnit": {
                            "state": "translated",
                            "value": translation,
                        }
                    }
                    counts["applied_translations"] += 1
                continue

            locs[language] = {
                "stringUnit": {
                    "state": "translated",
                    "value": translation,
                }
            }
            counts["applied_translations"] += 1

    return counts


def apply_translation_map(
    data: Dict[str, Any],
    translation_map: Dict[str, str],
    target_language: str = "zh-Hans",
) -> int:
    """Apply a one-to-one English → target language translation map."""
    strings = data["strings"]
    applied = 0

    for english_key, translation in translation_map.items():
        if english_key not in strings:
            continue

        value = strings[english_key]
        locs = value.setdefault("localizations", {})
        target_unit = locs.get(target_language, {}).get("stringUnit")
        current_value = target_unit.get("value", "").strip() if target_unit else ""

        if current_value:
            continue

        locs[target_language] = {
            "stringUnit": {
                "state": "translated",
                "value": translation,
            }
        }
        applied += 1

    return applied


def find_untranslated(
    data: Dict[str, Any],
    target_langs: Optional[Iterable[str]] = None,
    exceptions: Optional[Iterable[str]] = None,
) -> List[Dict[str, Any]]:
    """Return entries where target languages are missing or have empty values."""
    target_langs = set(target_langs or DEFAULT_KEEP_LANGUAGES)
    exceptions = set(exceptions or [])
    strings = data["strings"]
    untranslated: List[Dict[str, Any]] = []

    for key, value in strings.items():
        if not should_translate(value):
            continue
        if key in exceptions:
            continue

        locs = value.get("localizations", {})
        missing_langs: List[str] = []

        for lang in target_langs:
            target_unit = locs.get(lang, {}).get("stringUnit", {})
            target_value = target_unit.get("value", "").strip()

            # Report if target is missing or empty
            if not target_value:
                missing_langs.append(lang)

        if missing_langs:
            untranslated.append({"key": key, "missing": sorted(missing_langs)})

    return untranslated


def prune_stale_strings(data: Dict[str, Any]) -> List[str]:
    """Remove entries marked extractionState=stale; returns removed keys."""
    strings = data["strings"]
    removed: List[str] = []
    for key in list(strings.keys()):
        if strings[key].get("extractionState") == "stale":
            removed.append(key)
            del strings[key]
    return removed


def find_incomplete_translations(
    data: Dict[str, Any],
    clean_stale: bool = True,
) -> Tuple[List[str], List[Tuple[str, str, str]], List[str]]:
    """
    Find missing/empty/non-translated entries.
    Returns (languages, incomplete list, removed_stale_keys)
    """
    removed = prune_stale_strings(data) if clean_stale else []
    strings = data["strings"]
    translatable = {k: v for k, v in strings.items() if should_translate(v)}

    languages = sorted(collect_languages(translatable))
    incomplete: List[Tuple[str, str, str]] = []

    for key, value in translatable.items():
        locs = value.get("localizations", {})
        for lang in languages:
            unit = locs.get(lang, {}).get("stringUnit")
            if not unit:
                incomplete.append((key, lang, "missing localization"))
                continue

            state = unit.get("state")
            val = unit.get("value", "").strip()
            if state != "translated":
                incomplete.append((key, lang, f"state: {state}"))
            elif not val:
                incomplete.append((key, lang, "empty value"))

    return languages, incomplete, removed


def print_update_summary(file_path: str, counts: Dict[str, int]) -> None:
    print(f"✅ Updated {file_path}")
    print(f"   - Added {counts['added_en']} missing English localizations")
    print(f"   - Fixed {counts['fixed_en_state']} 'new' English states")
    print(f"   - Applied {counts['applied_translations']} provided translations")


def print_apply_summary(applied: int, file_path: str, target_language: str) -> None:
    if applied:
        print(f"✅ Added {applied} {target_language} translations in {file_path}")
    else:
        print(f"ℹ️ No {target_language} translations needed in {file_path}")

