"""
core/parser/processing/storage.py — storage block mini-parser
Parses [storage]:[ key = /mount ... ]: into StorageNode list.
"""

import re
from parser.processing.types import StorageNode


def parse_storage(node) -> list[StorageNode]:
    """
    Parse storage from a Node's kv and children.
    Each entry: name = /mount/path
    Nested: [subgroup]:[ name = /path ]:
    """
    nodes = []

    # flat kv entries: models = /models
    for k, v in node.kv.items():
        nodes.append(StorageNode(name=k, mount=str(v)))

    # nested blocks: [models]:[ checkpoints = /models/checkpoints ]:
    for child in node.children:
        for k, v in child.kv.items():
            nodes.append(StorageNode(
                name=f"{child.name}/{k}",
                mount=str(v)
            ))

    return nodes