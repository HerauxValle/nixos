#!/usr/bin/env python3
# Replaces one exact literal value with same-length asterisks AND
# comments out the whole line it's on, in a file already synced into the
# snapshot -- runs on every activation, on the CURRENT copy (separate
# from the one-time history scrub, which only handles OLD commits). The
# comment is what makes this safe regardless of what Nix/type the
# original line held (a bare number, an enum, whatever) -- asterisks
# alone only stay valid if the original was already a quoted string; a
# commented-out line can never break syntax, full stop. Python for exact
# literal substitution, not sed -- avoids regex-escaping a MAC/email that
# may contain characters sed's search side treats specially.
#
# <dir> <data-file> -- data-file is the JSON array of {file, value}
# entries (resolvedRedactValues) written by ../default.nix, one process
# for the whole list instead of one per entry.
import json
import os
import sys


def apply(path, value):
    masked = "*" * len(value)
    with open(path, "r", encoding="utf-8", errors="surrogateescape") as fh:
        lines = fh.readlines()
    out = []
    for line in lines:
        if value in line:
            line = line.replace(value, masked)
            stripped = line.lstrip()
            indent = line[:len(line) - len(stripped)]
            line = indent + "# " + stripped
        out.append(line)
    with open(path, "w", encoding="utf-8", errors="surrogateescape") as fh:
        fh.writelines(out)


def main():
    dir_, data_file = sys.argv[1], sys.argv[2]
    with open(data_file, encoding="utf-8") as fh:
        entries = json.load(fh)
    for entry in entries:
        path = os.path.join(dir_, entry["file"])
        if os.path.isfile(path):
            apply(path, entry["value"])


if __name__ == "__main__":
    main()
