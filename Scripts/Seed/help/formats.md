# Custom Format Guide

The parser engine is fully format-agnostic. A format is defined by a single `.ini` file.
Drop it in your img's `formats/` folder and reference it via shebang in your blueprint file.

---

## Quickstart

1. `sd create format myformat` — creates an empty `myformat.ini` in your active img
2. `sd edit format myformat` — define your ruleset
3. In your blueprint file, add `#!myformat` as the first line
4. The parser auto-loads your ruleset when reading that file

No Python knowledge needed. Just edit the `.ini` file.

---

## Default format

The built-in default format is `sdc` — defined in `core/parser/generic.ini`.
It is used when no shebang is present, or when `#!sdc` is specified.

---

## Sections

### [meta]

Info about the format. Not used by the parser, just for humans.

```ini
name        = myformat
version     = 1.0
description = My custom format
extension   = .myf
```

### [shebang]

First line of a blueprint file can declare which format to use.

```ini
enabled  = true      # look for shebang on line 1
marker   = #!        # shebang prefix
default  = sdc       # format to use if shebang says #!sdc
fallback = sdc       # format to use if no shebang found
required = false     # error if no shebang
```

Example file header: `#!myformat`

### [tokens]

Regex patterns for recognizing each line type.
Capture groups `(.+)` extract the meaningful part.

```ini
block_open       = \[(.+)\]:\[     # opens a block, captures name
block_close      = \]:             # closes nearest open block
block_chain      = true            # allow ]:]: to close multiple at once
declaration      = \[(.+)\]\s*=\s*(.+)  # top-level key=value
kv               = (.+?)\s*=\s*(.+)     # key=value inside block
kv_sep           = =               # separator character
kv_sep_strict    = false           # require spaces around separator
comment          = #               # rest of line ignored
ml_comment_open  = """             # start multiline comment
ml_comment_close = """             # end multiline comment
list_open        = [               # list start
list_close       = ]               # list end
list_sep         = ,               # list separator
list_trailing    = allow           # allow trailing comma
inline_comment   = true            # allow # after value on same line
```

### [whitespace]

```ini
indent          = ignore     # ignore, preserve, require
indent_char     = any        # space, tab, any
indent_size     = 4          # only used if indent = require
trailing        = strip      # strip trailing whitespace
blank_lines     = allow      # allow, deny, normalize
blank_lines_max = 2          # max consecutive blank lines if normalize
line_ending     = lf         # lf, crlf, any
```

### [values]

How raw string values are interpreted.

```ini
true           = true, yes, 1, on
false          = false, no, 0, off
none           = null, none, ~, nil
auto_int       = true      # "42" becomes integer 42
auto_float     = true      # "3.14" becomes float 3.14
auto_bool      = true
auto_none      = true
auto_list      = true      # "[a, b]" becomes list
string_quote   = "         # optional quote char
string_escape  = true      # honor \" inside quoted strings
multiline_char = \         # line ending with \ continues on next line
env_expand     = false     # expand $VAR in values at parse time
interpolation  = false     # expand ${key} from same block
```

### [blocks]

```ini
raw             = start, install   # raw lines, no kv parsing
kv_only         = meta, env        # kv lines only
case_sensitive  = false
unknown         = allow            # allow, deny, warn
nested          = true
max_depth       = 10
self_closing    = false
order           = loose            # strict = enforce block order
duplicates      = deny             # deny, allow, merge, override
empty           = allow
inherit         = false            # child blocks inherit parent kv
inherit_prefix  = _
```

### [structure]

```ini
requires       = services    # blocks that must exist at top level
entry          = services    # block that lists services to parse
min_services   = 1
max_services   = 0           # 0 = unlimited
```

### [validation]

```ini
unknown_key   = warn    # warn, deny, ignore
missing_key   = warn
type_mismatch = warn
empty_value   = allow
duplicate_key = deny
key_pattern   =         # regex keys must match (empty = any)
value_max_len = 0       # 0 = unlimited
raw_max_lines = 0       # 0 = unlimited
strict        = false   # true = all warn become deny
```

### [encoding]

```ini
charset    = utf-8
bom        = false
null_bytes = deny       # deny, strip, allow
```

### [debug]

```ini
trace_tokens  = false    # print every token as it is parsed
trace_tree    = false    # print the full parse tree
trace_ruleset = false    # print the loaded ruleset on startup
```

---

## Minimal example

```ini
[meta]
name      = myformat
extension = .myf

[tokens]
block_open  = \[(.+)\]:\[
block_close = \]:
kv          = (.+?)\s*=\s*(.+)
comment     = #

[blocks]
raw = script
```

That is all you need for a working format.

---

## Tips

- Missing keys always fall back to defaults — only specify what differs
- `raw` blocks store lines exactly as written — safe for bash, python, anything
- `block_chain = true` lets you write `]:]:]:` to close multiple blocks at once
- Set `strict = true` in `[validation]` to turn all warnings into errors
- Use `trace_tokens = true` in `[debug]` to troubleshoot a new format
- Custom formats live in your img's `formats/` folder — portable with the img
- Use `sd list formats` to see all formats in the active img