# core/parser/engine/ruleset.py
# moved from core/parser/ruleset.py — no changes to content
"""
core/parser/ruleset.py — loads a .ini ruleset file into a Ruleset object
Missing keys fall back to DEFAULTS, never error.
"""

import configparser
import os

DEFAULTS = {
    "meta": {
        "name":        "unnamed",
        "version":     "1.0",
        "description": "",
        "author":      "",
        "extension":   "",
        "mimetype":    "",
    },
    "shebang": {
        "enabled":  "true",
        "marker":   "#!",
        "default":  "sdc",
        "fallback": "sdc",
        "required": "false",
    },
    "tokens": {
        "block_open":        r"\[(.+)\]:\[",
        "block_close":       r"\]:",
        "block_chain":       "true",
        "declaration":       r"\[(.+)\]\s*=\s*(.+)",
        "kv":                r"(.+?)\s*=\s*(.+)",
        "kv_sep":            "=",
        "kv_sep_strict":     "false",
        "comment":           "#",
        "ml_comment_open":   '"""',
        "ml_comment_close":  '"""',
        "list_open":         "[",
        "list_close":        "]",
        "list_sep":          ",",
        "list_trailing":     "allow",
        "inline_comment":    "true",
    },
    "whitespace": {
        "indent":           "ignore",
        "indent_char":      "any",
        "indent_size":      "4",
        "trailing":         "strip",
        "blank_lines":      "allow",
        "blank_lines_max":  "2",
        "line_ending":      "lf",
    },
    "values": {
        "true":           "true, yes, 1, on",
        "false":          "false, no, 0, off",
        "none":           "null, none, ~, nil",
        "auto_int":       "true",
        "auto_float":     "true",
        "auto_bool":      "true",
        "auto_none":      "true",
        "auto_list":      "true",
        "string_quote":   '"',
        "string_escape":  "true",
        "multiline_char": "\\",
        "env_expand":     "false",
        "interpolation":  "false",
    },
    "blocks": {
        "raw":             "start, install",
        "kv_only":         "meta, env",
        "any":             "*",
        "case_sensitive":  "false",
        "unknown":         "allow",
        "nested":          "true",
        "max_depth":       "10",
        "self_closing":    "false",
        "order":           "loose",
        "duplicates":      "deny",
        "empty":           "allow",
        "inherit":         "false",
        "inherit_prefix":  "_",
    },
    "structure": {
        "requires":        "services",
        "entry":           "services",
        "top_level_only":  "",
        "min_services":    "1",
        "max_services":    "0",
    },
    "validation": {
        "unknown_key":    "warn",
        "missing_key":    "warn",
        "type_mismatch":  "warn",
        "empty_value":    "allow",
        "duplicate_key":  "deny",
        "key_pattern":    "",
        "value_max_len":  "0",
        "raw_max_lines":  "0",
        "strict":         "false",
    },
    "encoding": {
        "charset":    "utf-8",
        "bom":        "false",
        "null_bytes": "deny",
    },
    "debug": {
        "trace_tokens":  "false",
        "trace_tree":    "false",
        "trace_ruleset": "false",
    },
}


def _unquote(s: str) -> str:
    s = s.strip()
    if len(s) >= 2:
        if (s.startswith('"') and s.endswith('"')) or \
           (s.startswith("'") and s.endswith("'")):
            return s[1:-1]
    return s


def _uq(cfg, section: str, key: str) -> str:
    return _unquote(cfg.get(section, key))


def _uqbool(cfg, section: str, key: str) -> bool:
    return _unquote(cfg.get(section, key)).lower() in ("true", "yes", "1", "on")


def _uqint(cfg, section: str, key: str) -> int:
    return int(_unquote(cfg.get(section, key)))


def _uqlist(cfg, section: str, key: str) -> list[str]:
    return [v.strip() for v in _unquote(cfg.get(section, key)).split(",") if v.strip()]


class Ruleset:
    def __init__(self, path: str | None):
        self._cfg = configparser.RawConfigParser()
        self._cfg.read_dict(DEFAULTS)
        if path and os.path.isfile(path):
            self._cfg.read(path, encoding="utf-8")
        self._build()

    def _build(self) -> None:
        c = self._cfg

        # meta
        self.name        = _uq(c, "meta", "name")
        self.version     = _uq(c, "meta", "version")
        self.description = _uq(c, "meta", "description")
        self.author      = _uq(c, "meta", "author")
        self.extension   = _uq(c, "meta", "extension")
        self.mimetype    = _uq(c, "meta", "mimetype")

        # shebang
        self.shebang_enabled  = _uqbool(c, "shebang", "enabled")
        self.shebang_marker   = _uq(c, "shebang", "marker")
        self.shebang_default  = _uq(c, "shebang", "default")
        self.shebang_fallback = _uq(c, "shebang", "fallback")
        self.shebang_required = _uqbool(c, "shebang", "required")

        # tokens
        self.tok_block_open       = _uq(c, "tokens", "block_open")
        self.tok_block_close      = _uq(c, "tokens", "block_close")
        self.tok_block_chain      = _uqbool(c, "tokens", "block_chain")
        self.tok_declaration      = _uq(c, "tokens", "declaration")
        self.tok_kv               = _uq(c, "tokens", "kv")
        self.tok_kv_sep           = _uq(c, "tokens", "kv_sep")
        self.tok_kv_sep_strict    = _uqbool(c, "tokens", "kv_sep_strict")
        self.tok_comment          = _uq(c, "tokens", "comment")
        self.tok_ml_comment_open  = _uq(c, "tokens", "ml_comment_open")
        self.tok_ml_comment_close = _uq(c, "tokens", "ml_comment_close")
        self.tok_list_open        = _uq(c, "tokens", "list_open")
        self.tok_list_close       = _uq(c, "tokens", "list_close")
        self.tok_list_sep         = _uq(c, "tokens", "list_sep")
        self.tok_list_trailing    = _uq(c, "tokens", "list_trailing")
        self.tok_inline_comment   = _uqbool(c, "tokens", "inline_comment")

        # whitespace
        self.ws_indent          = _uq(c, "whitespace", "indent")
        self.ws_indent_char     = _uq(c, "whitespace", "indent_char")
        self.ws_indent_size     = _uqint(c, "whitespace", "indent_size")
        self.ws_trailing        = _uq(c, "whitespace", "trailing")
        self.ws_blank_lines     = _uq(c, "whitespace", "blank_lines")
        self.ws_blank_lines_max = _uqint(c, "whitespace", "blank_lines_max")
        self.ws_line_ending     = _uq(c, "whitespace", "line_ending")

        # values
        self.val_true         = _uqlist(c, "values", "true")
        self.val_false        = _uqlist(c, "values", "false")
        self.val_none         = _uqlist(c, "values", "none")
        self.val_auto_int     = _uqbool(c, "values", "auto_int")
        self.val_auto_float   = _uqbool(c, "values", "auto_float")
        self.val_auto_bool    = _uqbool(c, "values", "auto_bool")
        self.val_auto_none    = _uqbool(c, "values", "auto_none")
        self.val_auto_list    = _uqbool(c, "values", "auto_list")
        self.val_quote        = _uq(c, "values", "string_quote")
        self.val_escape       = _uqbool(c, "values", "string_escape")
        self.val_multiline    = _uq(c, "values", "multiline_char")
        self.val_env_expand   = _uqbool(c, "values", "env_expand")
        self.val_interp       = _uqbool(c, "values", "interpolation")

        # blocks
        self.blk_raw            = _uqlist(c, "blocks", "raw")
        self.blk_kv_only        = _uqlist(c, "blocks", "kv_only")
        self.blk_any            = _uq(c, "blocks", "any")
        self.blk_case_sensitive = _uqbool(c, "blocks", "case_sensitive")
        self.blk_unknown        = _uq(c, "blocks", "unknown")
        self.blk_nested         = _uqbool(c, "blocks", "nested")
        self.blk_max_depth      = _uqint(c, "blocks", "max_depth")
        self.blk_self_closing   = _uqbool(c, "blocks", "self_closing")
        self.blk_order          = _uq(c, "blocks", "order")
        self.blk_duplicates     = _uq(c, "blocks", "duplicates")
        self.blk_empty          = _uq(c, "blocks", "empty")
        self.blk_inherit        = _uqbool(c, "blocks", "inherit")
        self.blk_inherit_prefix = _uq(c, "blocks", "inherit_prefix")

        # structure
        self.struct_requires       = _uqlist(c, "structure", "requires")
        self.struct_entry          = _uq(c, "structure", "entry")
        self.struct_top_level_only = _uqlist(c, "structure", "top_level_only")
        self.struct_min_services   = _uqint(c, "structure", "min_services")
        self.struct_max_services   = _uqint(c, "structure", "max_services")

        # validation
        self.vld_unknown_key   = _uq(c, "validation", "unknown_key")
        self.vld_missing_key   = _uq(c, "validation", "missing_key")
        self.vld_type_mismatch = _uq(c, "validation", "type_mismatch")
        self.vld_empty_value   = _uq(c, "validation", "empty_value")
        self.vld_duplicate_key = _uq(c, "validation", "duplicate_key")
        self.vld_key_pattern   = _uq(c, "validation", "key_pattern")
        self.vld_value_max_len = _uqint(c, "validation", "value_max_len")
        self.vld_raw_max_lines = _uqint(c, "validation", "raw_max_lines")
        self.vld_strict        = _uqbool(c, "validation", "strict")

        # encoding
        self.enc_charset    = _uq(c, "encoding", "charset")
        self.enc_bom        = _uqbool(c, "encoding", "bom")
        self.enc_null_bytes = _uq(c, "encoding", "null_bytes")

        # debug
        self.dbg_tokens  = _uqbool(c, "debug", "trace_tokens")
        self.dbg_tree    = _uqbool(c, "debug", "trace_tree")
        self.dbg_ruleset = _uqbool(c, "debug", "trace_ruleset")

        # apply strict mode — upgrade all warn to deny
        if self.vld_strict:
            for attr in ("vld_unknown_key", "vld_missing_key", "vld_type_mismatch", "vld_empty_value", "vld_duplicate_key"):
                if getattr(self, attr) == "warn":
                    setattr(self, attr, "deny")


def load(path: str) -> "Ruleset":
    return Ruleset(path)


def default() -> "Ruleset":
    try:
        from common.config import get_config_path
        return Ruleset(get_config_path("ruleset"))
    except Exception:
        return Ruleset(None)


def find_format(name: str, formats_dir: str) -> "Ruleset":
    """Find a ruleset by shebang name, then by filename, then default."""
    # try shebang scan in formats dir
    from common.config import _scan_dir
    found = _scan_dir(formats_dir)
    if name in found:
        return Ruleset(found[name])
    # fallback to filename
    path = os.path.join(formats_dir, f"{name}.ini")
    if os.path.isfile(path):
        return Ruleset(path)
    return default()