#!/usr/bin/env python3
"""
Check for untranslated strings across all supported languages.
Reports strings that are missing or have empty values.
Exit codes:
    0 - All strings are properly translated
    1 - Found untranslated strings (or file errors)
"""

import sys

from i18n_tools import (
    default_file_path,
    find_untranslated,
    load_strings,
)

EXCEPTIONS: set[str] = {"%@", "%lld"}


if __name__ == "__main__":
    file_path = sys.argv[1] if len(sys.argv) > 1 else default_file_path()

    print(f"📝 Checking for untranslated strings in: {file_path}\n")
    data = load_strings(file_path)

    untranslated = find_untranslated(
        data,
        exceptions=EXCEPTIONS,
    )

    if untranslated:
        print(f"❌ Found {len(untranslated)} untranslated strings in {file_path}:\n")
        for item in untranslated:
            print(f"  Key: {item['key']}")
            print(f"  Missing: {', '.join(item['missing'])}\n")
        sys.exit(1)

    print(f"✅ All strings are properly translated in {file_path}")
    sys.exit(0)

