"""
common/renderers/json_.py — JsonRenderer (-j flag)
Uses to_public() transform: internal IR → clean public JSON.
"""
import sys
import json
from common.ir import to_public


class JsonRenderer:
    def render(self, ir: dict, file=sys.stdout) -> None:
        print(json.dumps(to_public(ir), indent=2, default=str), file=file)