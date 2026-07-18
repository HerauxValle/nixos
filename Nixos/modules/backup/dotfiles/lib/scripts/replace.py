#!/usr/bin/env python3
# Swaps one exact literal string for another exact literal string, in a
# file already synced into the snapshot -- runs on every activation, on
# the CURRENT copy, same as redact.py above but without the masking/
# comment-out behavior: the replacement drops straight in and the line
# stays live, since (unlike a redacted value) the published result is
# meant to be a complete, valid stand-in, not a stripped one. Whole file
# content, not line-by-line -- there's no indentation to preserve here
# since nothing gets commented out. Python for exact literal
# substitution, not sed -- same reasoning as redact.py.
#
# <dir> <data-file> -- data-file is the JSON array of {file, find,
# replaceWith, line} entries (resolvedReplaceValues) written by
# ../default.nix, one process for the whole list instead of one per
# entry. `line` (see lines.py) is optional: null keeps the prior
# whole-file-content behavior (every occurrence of `find` replaced); a
# line number or list of them restricts replacement to just those lines,
# for a `find` that also appears, unrelated, elsewhere in the file.
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lines import line_set


def apply(path, find, replace_with, line=None):
    lines_wanted = line_set(line)
    with open(path, "r", encoding="utf-8", errors="surrogateescape") as fh:
        content = fh.read()
    if lines_wanted is None:
        content = content.replace(find, replace_with)
    else:
        file_lines = content.splitlines(keepends=True)
        for lineno in lines_wanted:
            idx = lineno - 1
            if 0 <= idx < len(file_lines):
                file_lines[idx] = file_lines[idx].replace(find, replace_with)
        content = "".join(file_lines)
    with open(path, "w", encoding="utf-8", errors="surrogateescape") as fh:
        fh.write(content)


def main():
    dir_, data_file = sys.argv[1], sys.argv[2]
    with open(data_file, encoding="utf-8") as fh:
        entries = json.load(fh)
    for entry in entries:
        path = os.path.join(dir_, entry["file"])
        if os.path.isfile(path):
            apply(path, entry["find"], entry["replaceWith"], entry.get("line"))


if __name__ == "__main__":
    main()
