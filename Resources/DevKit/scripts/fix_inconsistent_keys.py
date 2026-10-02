#!/usr/bin/env python3
"""
Fix localization entries where the English translation doesn't match the key.

Swift looks strings up by key, so keys are never renamed. Xcode writes
positional specifiers into the English value of multi-argument keys
(`%@ • %@` -> `%1$@ • %2$@`); those entries are consistent and left alone.
Other mismatches are reported, and only with --apply is the English value
reset to the key. Review the list first: some entries, such as
"Duck Duck Go Search", override the English text on purpose.
"""

import json
import sys
from pathlib import Path

from i18n_tools import inconsistent_english_value, save_strings


def fix_inconsistent_keys(xcstrings_path, dry_run=False):
    """Fix entries where key != English value by resetting the English value to the key."""
    with open(xcstrings_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    strings = data.get('strings', {})
    fixed = []

    for key, entry in strings.items():
        en_value = inconsistent_english_value(key, entry)
        if en_value is None:
            continue
        fixed.append({
            'key': key,
            'old_value': en_value
        })
        if not dry_run:
            entry['localizations']['en']['stringUnit']['value'] = key
    
    if not fixed:
        print("✅ All keys already match their English translations!")
        return []
    
    if not dry_run:
        save_strings(xcstrings_path, data)
        
        print(f"✅ Fixed {len(fixed)} entries in {xcstrings_path}")
    else:
        print(f"🔍 DRY RUN: Would fix {len(fixed)} entries")
    
    return fixed


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 fix_inconsistent_keys.py <path_to_Localizable.xcstrings> [--apply]")
        sys.exit(1)
    
    xcstrings_path = Path(sys.argv[1])
    dry_run = '--apply' not in sys.argv or '--dry-run' in sys.argv
    
    if not xcstrings_path.exists():
        print(f"Error: File not found: {xcstrings_path}")
        sys.exit(1)
    
    print(f"{'[DRY RUN] ' if dry_run else ''}Fixing: {xcstrings_path}\n")
    
    fixed = fix_inconsistent_keys(xcstrings_path, dry_run)
    
    if fixed:
        print(f"\nFixed {len(fixed)} entries:")
        print("=" * 100)
        
        for i, item in enumerate(fixed, 1):
            print(f"\n{i}.")
            print(f"   Key:       {item['key'][:70]}{'...' if len(item['key']) > 70 else ''}")
            print(f"   Old value: {item['old_value'][:70]}{'...' if len(item['old_value']) > 70 else ''}")
            print("-" * 100)
        
        if dry_run:
            print("\nRe-run with --apply to reset these English values to their keys.")


if __name__ == '__main__':
    main()

