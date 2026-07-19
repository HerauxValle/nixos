/* &desc: "Implements file_name_color()/dir_name_color(), the kind-by-extension and role-by-folder-name colour lookups shared by render_ls.c and render_tree.c." */
#define _GNU_SOURCE
#include "render/namecolor.h"
#include "render/colors.h"
#include "scan/exttable.h"
#include <string.h>
#include <strings.h>
#include <sys/stat.h>

/* Case-insensitive "is `needle` any of these" -- used both for file
 * extensions (file_name_color()) and whole folder names
 * (dir_name_color()), so src/Src/SRC or NIX/nix/Nix all match their
 * category the same way. */
static bool matches_any(const char *needle, const char *const *list, size_t n) {
    for (size_t i = 0; i < n; i++) if (strcasecmp(needle, list[i]) == 0) return true;
    return false;
}

/* Extension lists lean toward "common enough to recognize on sight"
 * over exhaustive -- easy to extend a list below, not meant to
 * replicate a full LS_COLORS/dircolors database. */
const char *file_name_color(const Config *cfg, const char *name, mode_t mode) {
    if (cfg->no_colour) return NULL;
    if (mode & (S_IXUSR | S_IXGRP | S_IXOTH)) return ANSI_EXEC;

    const char *ext = file_ext(name);
    if (strcmp(ext, "(no ext)") == 0) return NULL;

    static const char *const archive[] = {
        "tar", "gz", "tgz", "zip", "xz", "txz", "bz2", "tbz2", "7z", "rar", "zst", "tzst",
        "lz", "lz4", "lzma", "deb", "rpm", "iso", "cab", "cpio", "ar", "jar", "war", "whl",
        "apk", "snap", "appimage", "dmg"
    };
    static const char *const image[] = {
        "png", "jpg", "jpeg", "gif", "svg", "webp", "ico", "bmp", "avif", "tiff", "tif",
        "heic", "heif", "psd", "ai", "eps", "raw", "cr2", "nef", "dng", "xcf"
    };
    static const char *const media[] = {
        "mp3", "mp4", "wav", "flac", "mkv", "mov", "avi", "ogg", "ogv", "webm", "m4a",
        "m4v", "wma", "wmv", "aac", "opus", "mid", "midi", "3gp", "aiff", "alac"
    };
    static const char *const doc[] = {
        "md", "markdown", "txt", "rst", "pdf", "adoc", "org", "tex", "rtf", "odt", "doc",
        "docx", "xls", "xlsx", "ppt", "pptx", "epub", "log", "csv", "tsv", "ipynb", "man"
    };
    static const char *const config[] = {
        "json", "jsonc", "yaml", "yml", "toml", "ini", "conf", "nix", "env", "lock", "cfg",
        "properties", "editorconfig", "hcl", "tf", "tfvars", "plist", "gradle", "cmake",
        "kdl"
    };
    static const char *const code[] = {
        "c", "h", "cpp", "cc", "cxx", "hpp", "hxx", "rs", "py", "pyw", "js", "mjs", "cjs",
        "ts", "tsx", "jsx", "go", "rb", "java", "kt", "kts", "swift", "php", "lua", "pl",
        "pm", "scala", "cs", "dart", "ex", "exs", "hs", "lhs", "clj", "cljs", "cljc", "r",
        "jl", "sh", "bash", "zsh", "fish", "nu", "ps1", "psm1", "sql", "vim", "el", "nim",
        "zig", "v", "asm", "s", "f90", "f95", "erl", "elm", "purs", "ml", "mli", "fs",
        "fsx", "groovy", "m", "mm", "proto", "qml", "vala", "d", "pas", "pp", "tcl", "scm",
        "lisp", "cl", "coffee", "graphql", "gql", "cr", "awk", "rkt", "jsonnet"
    };
    static const char *const markup[] = {
        "html", "htm", "xhtml", "css", "scss", "sass", "less", "xml", "xsl", "xsd", "vue",
        "svelte", "astro", "twig", "jinja", "j2", "hbs", "mustache", "ejs", "pug", "jade"
    };

    if (matches_any(ext, archive, sizeof(archive) / sizeof(*archive))) return ANSI_ARCHIVE;
    if (matches_any(ext, image, sizeof(image) / sizeof(*image)))       return ANSI_IMAGE;
    if (matches_any(ext, media, sizeof(media) / sizeof(*media)))       return ANSI_MEDIA;
    if (matches_any(ext, doc, sizeof(doc) / sizeof(*doc)))             return ANSI_DOC;
    if (matches_any(ext, config, sizeof(config) / sizeof(*config)))    return ANSI_CONFIG;
    if (matches_any(ext, code, sizeof(code) / sizeof(*code)))          return ANSI_CODE;
    if (matches_any(ext, markup, sizeof(markup) / sizeof(*markup)))    return ANSI_MARKUP;
    return NULL;
}

const char *dir_name_color(const Config *cfg, const char *name) {
    if (cfg->no_colour) return NULL;

    static const char *const src[] = {
        "src", "source", "srcs", "lib", "libs", "core", "cmd", "cli", "pkg", "packages",
        "internal", "app", "apps", "include", "includes"
    };
    static const char *const docs[] = { "docs", "doc", "documentation", "wiki", "man", "manual" };
    static const char *const test[] = { "test", "tests", "spec", "specs", "e2e", "__tests__" };
    static const char *const build[] = {
        "build", "dist", "out", "target", "release", "bin", "obj", "output"
    };
    static const char *const vendor[] = {
        "node_modules", "vendor", "vendored", "deps", "venv", ".venv", ".git", ".cache"
    };
    static const char *const assets[] = {
        "assets", "static", "public", "templates", "examples", "scripts", "tools",
        "utils", "config", "configs", "api", "resources"
    };

    if (matches_any(name, src, sizeof(src) / sizeof(*src)))          return ANSI_DIR_SRC;
    if (matches_any(name, docs, sizeof(docs) / sizeof(*docs)))       return ANSI_DIR_DOCS;
    if (matches_any(name, test, sizeof(test) / sizeof(*test)))       return ANSI_DIR_TEST;
    if (matches_any(name, build, sizeof(build) / sizeof(*build)))    return ANSI_DIR_BUILD;
    if (matches_any(name, vendor, sizeof(vendor) / sizeof(*vendor))) return ANSI_DIR_VENDOR;
    if (matches_any(name, assets, sizeof(assets) / sizeof(*assets))) return ANSI_DIR_ASSETS;
    return NULL;
}
