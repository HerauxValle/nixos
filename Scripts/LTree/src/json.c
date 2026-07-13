#define _GNU_SOURCE
#include "json.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* ===================== writer =========================================== */
static void json_node(SBuf *sb, Node *n, int indent) {
    for (int i = 0; i < indent; i++) sbuf_append(sb, "  ");
    sbuf_append(sb, "{\n");
    for (int i = 0; i < indent + 1; i++) sbuf_append(sb, "  ");
    sbuf_append(sb, "\"name\": "); sbuf_append_json_string(sb, n->name); sbuf_append(sb, ",\n");
    for (int i = 0; i < indent + 1; i++) sbuf_append(sb, "  ");
    sbuf_appendf(sb, "\"type\": \"%s\",\n", n->is_dir ? "dir" : "file");
    for (int i = 0; i < indent + 1; i++) sbuf_append(sb, "  ");
    sbuf_appendf(sb, "\"symlink\": %s,\n", n->is_symlink ? "true" : "false");
    for (int i = 0; i < indent + 1; i++) sbuf_append(sb, "  ");
    sbuf_appendf(sb, "\"lines\": %ld,\n", n->lines);
    for (int i = 0; i < indent + 1; i++) sbuf_append(sb, "  ");
    sbuf_appendf(sb, "\"chars\": %ld,\n", n->chars);
    for (int i = 0; i < indent + 1; i++) sbuf_append(sb, "  ");
    char modebuf[11];
    mode_string(n->mode, n->is_dir, n->is_symlink, modebuf);
    sbuf_append(sb, "\"mode\": "); sbuf_append_json_string(sb, modebuf); sbuf_append(sb, ",\n");
    for (int i = 0; i < indent + 1; i++) sbuf_append(sb, "  ");
    sbuf_appendf(sb, "\"size\": %lld,\n", (long long)n->size_bytes);
    for (int i = 0; i < indent + 1; i++) sbuf_append(sb, "  ");
    sbuf_appendf(sb, "\"mtime\": %lld,\n", (long long)n->mtime);
    for (int i = 0; i < indent + 1; i++) sbuf_append(sb, "  ");
    if (n->hash_len > 0) {
        char hex[HASH_MAX_BYTES * 2 + 1];
        hex_encode(n->hash, n->hash_len, hex);
        sbuf_append(sb, "\"hash\": "); sbuf_append_json_string(sb, hex);
    } else {
        sbuf_append(sb, "\"hash\": null");
    }
    if (n->diff_checked) {
        sbuf_append(sb, ",\n");
        for (int i = 0; i < indent + 1; i++) sbuf_append(sb, "  ");
        sbuf_appendf(sb, "\"modified\": %s", n->modified ? "true" : "false");
    }

    if (n->is_dir) {
        sbuf_append(sb, ",\n");
        for (int i = 0; i < indent + 1; i++) sbuf_append(sb, "  ");
        if (n->truncated) {
            sbuf_append(sb, "\"truncated\": true,\n");
            for (int i = 0; i < indent + 1; i++) sbuf_append(sb, "  ");
        }
        sbuf_append(sb, "\"children\": [");
        if (n->nchildren) {
            sbuf_append(sb, "\n");
            for (size_t i = 0; i < n->nchildren; i++) {
                json_node(sb, n->children[i], indent + 2);
                sbuf_append(sb, (i + 1 < n->nchildren) ? ",\n" : "\n");
            }
            for (int i = 0; i < indent + 1; i++) sbuf_append(sb, "  ");
        }
        sbuf_append(sb, "]\n");
    } else {
        sbuf_append(sb, "\n");
    }
    for (int i = 0; i < indent; i++) sbuf_append(sb, "  ");
    sbuf_append(sb, "}");
}

void json_render(SBuf *sb, Node *root, const char *display_path,
                  const Totals *tot, const ExtTable *ext, const Config *cfg,
                  const DebugStats *dbg) {
    sbuf_append(sb, "{\n");
    sbuf_append(sb, "  \"path\": "); sbuf_append_json_string(sb, display_path); sbuf_append(sb, ",\n");

    char nowbuf[32];
    format_datetime_local(time(NULL), nowbuf, sizeof(nowbuf));
    sbuf_append(sb, "  \"generated_at\": "); sbuf_append_json_string(sb, nowbuf); sbuf_append(sb, ",\n");

    sbuf_append(sb, "  \"hash_algo\": ");
    sbuf_append_json_string(sb, hash_algo_name(cfg->hash_algo));
    sbuf_append(sb, ",\n");

    sbuf_append(sb, "  \"total\": {\n");
    sbuf_appendf(sb, "    \"dirs\": %ld,\n", tot->dirs);
    sbuf_appendf(sb, "    \"files\": %ld,\n", tot->files);
    sbuf_appendf(sb, "    \"lines\": %ld,\n", tot->lines);
    sbuf_appendf(sb, "    \"chars\": %ld\n", tot->chars);
    sbuf_append(sb, "  },\n");

    if (dbg) debug_json_append(sb, dbg);

    ExtStat *sorted = NULL;
    if (ext->n) {
        sorted = (ExtStat *)malloc(sizeof(ExtStat) * ext->n);
        memcpy(sorted, ext->items, sizeof(ExtStat) * ext->n);
        qsort(sorted, ext->n, sizeof(ExtStat), extstat_cmp_desc_lines);
    }
    sbuf_append(sb, "  \"by_extension\": [");
    if (ext->n) {
        sbuf_append(sb, "\n");
        for (size_t i = 0; i < ext->n; i++) {
            sbuf_append(sb, "    {\"ext\": ");
            sbuf_append_json_string(sb, sorted[i].ext);
            sbuf_appendf(sb, ", \"files\": %ld, \"lines\": %ld, \"chars\": %ld}",
                         sorted[i].files, sorted[i].lines, sorted[i].chars);
            sbuf_append(sb, (i + 1 < ext->n) ? ",\n" : "\n");
        }
        sbuf_append(sb, "  ");
    }
    sbuf_append(sb, "],\n");
    free(sorted);

    sbuf_append(sb, "  \"tree\": \n");
    json_node(sb, root, 1);
    sbuf_append(sb, "\n}\n");
}

void print_json(Node *root, const char *display_path, const Totals *tot,
                 const ExtTable *ext, const Config *cfg, const DebugStats *dbg) {
    SBuf sb;
    sbuf_init(&sb);
    json_render(&sb, root, display_path, tot, ext, cfg, dbg);
    fwrite(sb.data, 1, sb.len, stdout);
    sbuf_free(&sb);
}

/* ===================== minimal generic JSON reader ======================
 * Recursive-descent parser for exactly the JSON we ourselves emit
 * above: objects, arrays, strings (with the handful of escapes
 * sbuf_append_json_string can produce), numbers, true/false/null.
 * Not hardened against adversarial input -- these files only ever
 * come from our own --save-output. */
typedef struct { const char *p; } JCursor;

static void jc_skip_ws(JCursor *c) {
    while (*c->p == ' ' || *c->p == '\t' || *c->p == '\n' || *c->p == '\r') c->p++;
}

static JVal *jval_new(JType t) {
    JVal *v = (JVal *)calloc(1, sizeof(JVal));
    v->type = t;
    return v;
}

static char *jc_parse_raw_string(JCursor *c) {
    /* assumes *c->p == '"' */
    c->p++;
    size_t cap = 64, len = 0;
    char *out = (char *)malloc(cap);
    while (*c->p && *c->p != '"') {
        char ch = *c->p;
        if (ch == '\\') {
            c->p++;
            switch (*c->p) {
                case '"':  ch = '"';  break;
                case '\\': ch = '\\'; break;
                case '/':  ch = '/';  break;
                case 'n':  ch = '\n'; break;
                case 'r':  ch = '\r'; break;
                case 't':  ch = '\t'; break;
                case 'u': {
                    /* \uXXXX -- we only ever emit this for control
                     * chars < 0x20, so a single-byte passthrough of
                     * the low byte is sufficient for round-tripping
                     * our own output. */
                    unsigned int cp = 0;
                    for (int k = 1; k <= 4; k++) {
                        char hc = c->p[k];
                        cp <<= 4;
                        if (hc >= '0' && hc <= '9') cp |= (unsigned)(hc - '0');
                        else if (hc >= 'a' && hc <= 'f') cp |= (unsigned)(hc - 'a' + 10);
                        else if (hc >= 'A' && hc <= 'F') cp |= (unsigned)(hc - 'A' + 10);
                    }
                    c->p += 4;
                    ch = (char)(cp & 0xFF);
                    break;
                }
                default: ch = *c->p; break;
            }
            c->p++;
        } else {
            c->p++;
        }
        if (len + 1 >= cap) { cap *= 2; out = (char *)realloc(out, cap); }
        out[len++] = ch;
    }
    if (*c->p == '"') c->p++;
    out[len] = '\0';
    return out;
}

static JVal *jc_parse_value(JCursor *c);

static JVal *jc_parse_object(JCursor *c) {
    JVal *v = jval_new(JSON_OBJECT);
    c->p++; /* { */
    jc_skip_ws(c);
    size_t cap = 8;
    v->keys = (char **)malloc(sizeof(char *) * cap);
    v->items = (JVal **)malloc(sizeof(JVal *) * cap);
    v->n = 0;
    if (*c->p == '}') { c->p++; return v; }
    while (1) {
        jc_skip_ws(c);
        char *key = jc_parse_raw_string(c);
        jc_skip_ws(c);
        if (*c->p == ':') c->p++;
        jc_skip_ws(c);
        JVal *val = jc_parse_value(c);
        if (v->n == cap) {
            cap *= 2;
            v->keys = (char **)realloc(v->keys, sizeof(char *) * cap);
            v->items = (JVal **)realloc(v->items, sizeof(JVal *) * cap);
        }
        v->keys[v->n] = key;
        v->items[v->n] = val;
        v->n++;
        jc_skip_ws(c);
        if (*c->p == ',') { c->p++; continue; }
        if (*c->p == '}') { c->p++; break; }
        break; /* malformed -- bail gracefully */
    }
    return v;
}

static JVal *jc_parse_array(JCursor *c) {
    JVal *v = jval_new(JSON_ARRAY);
    c->p++; /* [ */
    jc_skip_ws(c);
    size_t cap = 8;
    v->items = (JVal **)malloc(sizeof(JVal *) * cap);
    v->n = 0;
    if (*c->p == ']') { c->p++; return v; }
    while (1) {
        jc_skip_ws(c);
        JVal *val = jc_parse_value(c);
        if (v->n == cap) { cap *= 2; v->items = (JVal **)realloc(v->items, sizeof(JVal *) * cap); }
        v->items[v->n++] = val;
        jc_skip_ws(c);
        if (*c->p == ',') { c->p++; continue; }
        if (*c->p == ']') { c->p++; break; }
        break;
    }
    return v;
}

static JVal *jc_parse_value(JCursor *c) {
    jc_skip_ws(c);
    if (*c->p == '{') return jc_parse_object(c);
    if (*c->p == '[') return jc_parse_array(c);
    if (*c->p == '"') {
        JVal *v = jval_new(JSON_STRING);
        v->str = jc_parse_raw_string(c);
        return v;
    }
    if (strncmp(c->p, "true", 4) == 0) { c->p += 4; JVal *v = jval_new(JSON_BOOL); v->b = true; return v; }
    if (strncmp(c->p, "false", 5) == 0) { c->p += 5; JVal *v = jval_new(JSON_BOOL); v->b = false; return v; }
    if (strncmp(c->p, "null", 4) == 0) { c->p += 4; return jval_new(JSON_NULL); }
    /* number */
    char *end;
    double num = strtod(c->p, &end);
    c->p = end;
    JVal *v = jval_new(JSON_NUMBER);
    v->num = num;
    return v;
}

JVal *json_parse(const char *text) {
    JCursor c = { .p = text };
    return jc_parse_value(&c);
}

void json_free(JVal *v) {
    if (!v) return;
    if (v->type == JSON_STRING) free(v->str);
    if (v->type == JSON_OBJECT) {
        for (size_t i = 0; i < v->n; i++) { free(v->keys[i]); json_free(v->items[i]); }
        free(v->keys);
        free(v->items);
    } else if (v->type == JSON_ARRAY) {
        for (size_t i = 0; i < v->n; i++) json_free(v->items[i]);
        free(v->items);
    }
    free(v);
}

JVal *json_obj_get(JVal *obj, const char *key) {
    if (!obj || obj->type != JSON_OBJECT) return NULL;
    for (size_t i = 0; i < obj->n; i++)
        if (strcmp(obj->keys[i], key) == 0) return obj->items[i];
    return NULL;
}

const char *json_as_string(JVal *v) {
    return (v && v->type == JSON_STRING) ? v->str : NULL;
}

double json_as_number(JVal *v) {
    return (v && v->type == JSON_NUMBER) ? v->num : 0.0;
}

size_t json_arr_len(JVal *v) {
    return (v && v->type == JSON_ARRAY) ? v->n : 0;
}

JVal *json_arr_get(JVal *v, size_t i) {
    if (!v || v->type != JSON_ARRAY || i >= v->n) return NULL;
    return v->items[i];
}
