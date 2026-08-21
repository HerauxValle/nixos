"""
common/errors.py — shared error handling
"""

from common.emit import emit

import sys


class SDError(Exception):
    def __init__(self, code: str, msg: str, *details: str):
        self.code    = code
        self.msg     = msg
        self.details = details
        super().__init__(msg)


def error(code: str, msg: str, *details: str) -> None:
    emit("error", code, msg, *details)
    sys.exit(1)


def warn(msg: str, *details: str) -> None:
    emit("error", "WARN", msg, *details)