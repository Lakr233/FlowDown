#!/usr/bin/env python3
"""
Report translation completeness and optionally prune stale keys.
"""

import sys

from i18n_tools import (
    default_file_path,
    find_incomplete_translations,
    load_strings,
    save_strings,
)


if __name__ == "__main__":
    file_path = sys.argv[1] if len(sys.argv) > 1 else default_file_path()

    data = load_strings(file_path)
    languages, incomplete, removed = find_incomplete_translations(data)

    if removed:
        save_strings(file_path, data)
        print("Removed stale strings:")
        for key in removed:
            print(f"  - {key}")
    else:
        print("No stale strings found.")

    translatable_count = len(data["strings"])
    print(f"Found languages: {', '.join(languages)}")
    print(f"Total strings: {translatable_count}")
    print()

    if incomplete:
        print(f"Incomplete translations in {file_path}:")
        for key, lang, reason in incomplete:
            print(f"  {key} - {lang}: {reason}")
        sys.exit(1)

    print(f"All translations are complete in {file_path}.")
    sys.exit(0)