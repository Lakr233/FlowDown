#!/usr/bin/env python3
"""
Update missing i18n translations in Localizable.xcstrings.
This script adds missing English localizations and fixes 'new' state translations.
"""

import sys

from i18n_tools import (
    DEFAULT_KEEP_LANGUAGES,
    default_file_path,
    load_strings,
    print_update_summary,
    save_strings,
    update_missing_translations,
)

# Populate this map with explicit translations when introducing new keys.
# Format: {"Key": {"zh-Hans": "示例", "es": "Ejemplo"}}
NEW_STRINGS: dict[str, dict[str, str]] = {
    "Reasoning Effort": {
        "de": "Reasoning-Aufwand",
        "es": "Esfuerzo de razonamiento",
        "fr": "Effort de raisonnement",
        "ja": "推論の労力",
        "ko": "추론 노력",
        "zh-Hans": "推理强度",
    },
    "Calendar & Reminders": {
        "de": "Kalender & Erinnerungen",
        "es": "Calendario y Recordatorios",
        "fr": "Calendrier et Rappels",
        "ja": "カレンダーとリマインダー",
        "ko": "캘린더 및 미리 알림",
        "zh-Hans": "日历和提醒事项",
    },
    "Allows LLM to access your calendar and reminders.": {
        "de": "Erlaubt dem LLM Zugriff auf deinen Kalender und deine Erinnerungen.",
        "es": "Permite que el LLM acceda a tu calendario y recordatorios.",
        "fr": "Autorise le LLM à accéder à votre calendrier et vos rappels.",
        "ja": "LLM がカレンダーとリマインダーにアクセスできるようにします。",
        "ko": "LLM이 캘린더와 미리 알림에 접근할 수 있도록 허용합니다。",
        "zh-Hans": "允许大语言模型访问您的日历和提醒事项。",
    },
}

if __name__ == "__main__":
    file_path = sys.argv[1] if len(sys.argv) > 1 else default_file_path()

    data = load_strings(file_path)
    counts = update_missing_translations(
        data,
        new_strings=NEW_STRINGS,
        keep_languages=DEFAULT_KEEP_LANGUAGES,
    )
    save_strings(file_path, data)

    print_update_summary(file_path, counts)
