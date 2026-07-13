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
# replaceWith} entries (resolvedReplaceValues) written by ../default.nix,
# one process for the whole list instead of one per entry.
import json
import os
import sys


def apply(path, find, replace_with):
    with open(path, "r", encoding="utf-8", errors="surrogateescape") as fh:
        content = fh.read()
    with open(path, "w", encoding="utf-8", errors="surrogateescape") as fh:
        fh.write(content.replace(find, replace_with))


def main():
    dir_, data_file = sys.argv[1], sys.argv[2]
    with open(data_file, encoding="utf-8") as fh:
        entries = json.load(fh)
    for entry in entries:
        path = os.path.join(dir_, entry["file"])
        if os.path.isfile(path):
            apply(path, entry["find"], entry["replaceWith"])


if __name__ == "__main__":
    main()
