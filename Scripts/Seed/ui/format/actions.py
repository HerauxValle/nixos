"""
core/format/actions.py — add, edit, list, delete
"""

from orchestration.filemanager import add, edit, delete, list_files
from lib.variables.general import DIR_FORMATS as FOLDER

EXT = None



def format_add(name: str) -> None:
    add(FOLDER, EXT, name)


def format_edit(name: str, editor: str | None = None) -> None:
    edit(FOLDER, name, editor, EXT)


def format_delete(name: str) -> None:
    delete(FOLDER, name, EXT)


def format_list() -> None:
    list_files(FOLDER, EXT)