#!/usr/bin/env python3
"""
Find localization entries where the key doesn't match the English translation.
"""

import json
import re
import sys
from pathlib import Path


def find_inconsistent_keys(xcstrings_path):
    """Find entries where key != English value."""
    with open(xcstrings_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    inconsistent = []
    
    for key, entry in data.get('strings', {}).items():
        # Skip special entries
        if 'shouldTranslate' in entry and not entry['shouldTranslate']:
            continue
        
        localizations = entry.get('localizations', {})
        en_value = None
        
        # Get English value
        if 'en' in localizations:
            en_unit = localizations['en'].get('stringUnit', {})
            en_value = en_unit.get('value')
        
        # If there's no explicit English localization, the key is the English value
        if en_value is None:
            continue
        
        # Check if key matches English value, ignoring the positional
        # specifiers Xcode writes for multi-argument keys (%1$@ for %@)
        if key != en_value and key != re.sub(r'%(\d+)\$', '%', en_value):
            inconsistent.append({
                'key': key,
                'en_value': en_value,
                'has_zh': 'zh-Hans' in localizations
            })
    
    return inconsistent


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 find_inconsistent_keys.py <path_to_Localizable.xcstrings>")
        sys.exit(1)
    
    xcstrings_path = Path(sys.argv[1])
    
    if not xcstrings_path.exists():
        print(f"Error: File not found: {xcstrings_path}")
        sys.exit(1)
    
    print(f"Checking: {xcstrings_path}\n")
    
    inconsistent = find_inconsistent_keys(xcstrings_path)
    
    if not inconsistent:
        print("✅ All keys match their English translations!")
        return
    
    print(f"Found {len(inconsistent)} inconsistent entries:\n")
    print("=" * 100)
    
    for i, item in enumerate(inconsistent, 1):
        print(f"\n{i}. Key: {item['key'][:80]}{'...' if len(item['key']) > 80 else ''}")
        print(f"   EN:  {item['en_value'][:80]}{'...' if len(item['en_value']) > 80 else ''}")
        if item['has_zh']:
            print(f"   Has Chinese translation: ✓")
        print("-" * 100)
    
    print(f"\n\nTotal: {len(inconsistent)} entries need to be updated")
    
    # Save to file for later use, outside the synchronized groups the app bundles
    output_file = Path(__file__).resolve().parents[3] / ".build" / "inconsistent_keys.json"
    output_file.parent.mkdir(parents=True, exist_ok=True)
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(inconsistent, f, ensure_ascii=False, indent=2)
    print(f"\nDetails saved to: {output_file}")


if __name__ == '__main__':
    main()

