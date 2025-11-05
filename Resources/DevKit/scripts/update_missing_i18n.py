#!/usr/bin/env python3
"""
Update missing i18n translations in Localizable.xcstrings.
This script adds missing English localizations and fixes 'new' state translations.
"""

import json
import sys
import os

# New localization keys that must exist in Localizable.xcstrings
NEW_KEYS: dict[str, dict[str, str]] = {
    "Chat Templates": {
        "en": "Chat Templates",
        "zh-Hans": "聊天模板",
    },
    "Sync saved prompt templates across devices.": {
        "en": "Sync saved prompt templates across devices.",
        "zh-Hans": "在所有设备间同步已保存的提示模板。",
    },
}

def update_translations(file_path):
    """Update missing translations in the xcstrings file."""
    
    # Read the file
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"❌ File not found: {file_path}")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"❌ JSON decode error in {file_path}: {e}")
        sys.exit(1)
    
    strings = data['strings']

    # Determine all languages present in the file (excluding ones marked shouldTranslate=false)
    languages: set[str] = set()
    for value in strings.values():
        locs = value.get('localizations', {})
        for lang in locs.keys():
            languages.add(lang)

    # Ensure English is always part of the language set
    languages.add('en')

    # Count changes
    added_count = 0
    fixed_count = 0
    filled_count = 0
    new_key_count = 0

    # Ensure required new keys exist with translations
    for key, translations in NEW_KEYS.items():
        entry = strings.setdefault(key, {
            'shouldTranslate': True,
            'localizations': {},
        })

        if 'localizations' not in entry:
            entry['localizations'] = {}

        locs = entry['localizations']
        # Track whether this key was newly created
        if not locs:
            new_key_count += 1

        for lang, value in translations.items():
            locs[lang] = {
                'stringUnit': {
                    'state': 'translated',
                    'value': value,
                }
            }
    
    # Iterate through all strings
    for key, value in strings.items():
        # Skip strings marked as shouldTranslate=false
        if not value.get('shouldTranslate', True):
            continue
        
        # Ensure dictionary exists for modifications
        if 'localizations' not in value:
            value['localizations'] = {}

        locs = value['localizations']

        # Check if 'en' localization is missing
        if 'en' not in locs:
            locs['en'] = {
                'stringUnit': {
                    'state': 'translated',
                    'value': key
                }
            }
            added_count += 1

        # Ensure English localization is properly marked
        en_loc = locs['en']
        en_string_unit = en_loc.setdefault('stringUnit', {})
        if en_string_unit.get('state') == 'new':
            if not en_string_unit.get('value', '').strip():
                en_string_unit['value'] = key
            en_string_unit['state'] = 'translated'
            fixed_count += 1
        english_value = en_string_unit.get('value', key)

        # Fill missing localizations for other languages using English as fallback
        for language in languages:
            if language == 'en':
                continue

            string_unit = locs.get(language, {}).get('stringUnit')
            current_value = string_unit.get('value').strip() if string_unit and string_unit.get('value') else ''
            current_state = string_unit.get('state') if string_unit else None

            if language not in locs or not current_value:
                locs[language] = {
                    'stringUnit': {
                        'state': 'translated',
                        'value': english_value
                    }
                }
                filled_count += 1
            elif current_state == 'new':
                locs[language]['stringUnit']['state'] = 'translated'
                if not current_value:
                    locs[language]['stringUnit']['value'] = english_value
                filled_count += 1
    
    # Write the updated file
    try:
        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        print(f"✅ Successfully updated {file_path}")
        print(f"   - Added {added_count} missing English localizations")
        print(f"   - Fixed {fixed_count} 'new' state translations")
        print(f"   - Filled {filled_count} fallback localizations")
        if new_key_count:
            print(f"   - Added {new_key_count} required keys")
        return True
    except Exception as e:
        print(f"❌ Error writing file: {e}")
        sys.exit(1)

if __name__ == '__main__':
    # Default path to the Localizable.xcstrings file
    default_file_path = os.path.join(
        os.path.dirname(__file__), 
        '..', '..', 
        'FlowDown', 
        'Resources', 
        'Localizable.xcstrings'
    )
    
    # Allow overriding the file path via command line argument
    file_path = sys.argv[1] if len(sys.argv) > 1 else default_file_path
    
    print(f"📝 Updating translations in: {file_path}")
    update_translations(file_path)
