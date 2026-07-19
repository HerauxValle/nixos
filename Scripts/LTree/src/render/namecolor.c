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
 * category the same way. Full-string comparison, never substring, so
 * even a short/generic-looking name like "base" or "core" only matches
 * a folder literally named that -- never a false-positive hit inside
 * a longer name like "database". */
static bool matches_any(const char *needle, const char *const *list, size_t n) {
    for (size_t i = 0; i < n; i++) if (strcasecmp(needle, list[i]) == 0) return true;
    return false;
}

/* Extension lists aim for "every mainstream/niche kind someone's
 * actually likely to have on disk", not a literal LS_COLORS/dircolors
 * database -- long, but each list is still just one category, so
 * adding one more extension anywhere is a one-line change. No
 * extension appears in more than one list (an entry only ever needs
 * one home) -- where a real-world extension is genuinely ambiguous
 * (.pp is both Puppet and Pascal, .m is both MATLAB and Objective-C,
 * .v is both Coq and Verilog and V) it just picks the one home and
 * leaves it there. */
const char *file_name_color(const Config *cfg, const char *name, mode_t mode) {
    if (cfg->no_colour) return NULL;
    if (mode & (S_IXUSR | S_IXGRP | S_IXOTH)) return ANSI_EXEC;

    const char *ext = file_ext(name);
    if (strcmp(ext, "(no ext)") == 0) return NULL;

    static const char *const archive[] = {
        "tar", "gz", "tgz", "zip", "xz", "txz", "bz2", "tbz2", "tbz", "7z", "rar", "zst",
        "tzst", "lz", "lz4", "lzma", "deb", "rpm", "iso", "cab", "cpio", "ar", "jar", "war",
        "whl", "apk", "snap", "appimage", "dmg", "shar", "arj", "lha", "lzh", "z", "vmdk",
        "qcow2", "vdi", "cbz", "cbr", "cba", "img"
    };
    static const char *const image[] = {
        "png", "jpg", "jpeg", "gif", "svg", "webp", "ico", "bmp", "avif", "tiff", "tif",
        "heic", "heif", "psd", "ai", "eps", "raw", "cr2", "nef", "dng", "xcf", "jxl", "jp2",
        "jpx", "pbm", "pgm", "ppm", "xpm", "cur", "icns", "dds", "exr", "hdr"
    };
    static const char *const media[] = {
        "mp3", "mp4", "wav", "flac", "mkv", "mov", "avi", "ogg", "ogv", "webm", "m4a",
        "m4v", "wma", "wmv", "aac", "opus", "mid", "midi", "3gp", "aiff", "alac", "ape",
        "dsf", "amr", "ac3", "dts", "mpg", "mpeg", "vob", "rm", "rmvb", "asf", "divx",
        "mts", "m2ts"
    };
    static const char *const doc[] = {
        "md", "markdown", "txt", "rst", "pdf", "adoc", "org", "tex", "rtf", "odt", "doc",
        "docx", "xls", "xlsx", "ppt", "pptx", "epub", "log", "csv", "tsv", "ipynb", "man",
        "djvu", "mobi", "azw", "azw3", "fb2", "pages", "numbers", "textile", "nfo"
    };
    static const char *const config[] = {
        "json", "jsonc", "yaml", "yml", "toml", "ini", "conf", "nix", "env", "lock", "cfg",
        "properties", "editorconfig", "hcl", "tf", "tfvars", "plist", "gradle", "cmake",
        "kdl", "dhall", "cue", "hocon", "reg", "service", "rules", "desktop", "htaccess",
        "gitattributes", "dockerignore", "npmrc", "nvmrc", "babelrc", "prettierrc",
        "eslintrc", "stylelintrc"
    };
    static const char *const code[] = {
        "c", "h", "cpp", "cc", "cxx", "hpp", "hxx", "rs", "py", "pyw", "js", "mjs", "cjs",
        "ts", "tsx", "jsx", "go", "rb", "java", "kt", "kts", "swift", "php", "lua", "pl",
        "pm", "scala", "cs", "dart", "ex", "exs", "hs", "lhs", "clj", "cljs", "cljc", "r",
        "jl", "sh", "bash", "zsh", "fish", "nu", "ps1", "psm1", "sql", "vim", "el", "nim",
        "zig", "v", "asm", "s", "f90", "f95", "erl", "elm", "purs", "ml", "mli", "fs",
        "fsx", "groovy", "m", "mm", "proto", "qml", "vala", "d", "pas", "pp", "tcl", "scm",
        "lisp", "cl", "coffee", "graphql", "gql", "cr", "awk", "rkt", "jsonnet", "haxe",
        "hx", "sol", "move", "cairo", "ada", "adb", "ads", "cob", "cbl", "for", "f77",
        "pro", "sv", "svh", "vhd", "vhdl", "oct", "gleam", "roc", "idr", "agda", "lean",
        "bzl", "bazel", "mk", "mak", "sbt", "cabal", "nims", "re", "rei", "res", "fsi",
        "fsproj", "csproj", "vbproj", "sln", "gemspec", "rake", "podfile", "cartfile"
    };
    static const char *const markup[] = {
        "html", "htm", "xhtml", "css", "scss", "sass", "less", "xml", "xsl", "xsd", "vue",
        "svelte", "astro", "twig", "jinja", "j2", "hbs", "mustache", "ejs", "pug", "jade",
        "mjml", "liquid", "njk", "latte", "blade", "haml", "slim"
    };
    static const char *const font[] = {
        "ttf", "otf", "woff", "woff2", "eot", "fon", "fnt", "pfb", "pfm", "ttc"
    };
    static const char *const cert[] = {
        "pem", "crt", "cer", "key", "pub", "p12", "pfx", "csr", "gpg", "asc", "sig", "der",
        "jks", "keystore", "pgp"
    };
    static const char *const database[] = {
        "db", "sqlite", "sqlite3", "db3", "mdb", "accdb", "dbf", "frm", "ibd", "myd",
        "myi", "rdb", "ndb"
    };

    if (matches_any(ext, archive, sizeof(archive) / sizeof(*archive)))    return ANSI_ARCHIVE;
    if (matches_any(ext, image, sizeof(image) / sizeof(*image)))         return ANSI_IMAGE;
    if (matches_any(ext, media, sizeof(media) / sizeof(*media)))         return ANSI_MEDIA;
    if (matches_any(ext, doc, sizeof(doc) / sizeof(*doc)))               return ANSI_DOC;
    if (matches_any(ext, config, sizeof(config) / sizeof(*config)))      return ANSI_CONFIG;
    if (matches_any(ext, code, sizeof(code) / sizeof(*code)))            return ANSI_CODE;
    if (matches_any(ext, markup, sizeof(markup) / sizeof(*markup)))      return ANSI_MARKUP;
    if (matches_any(ext, font, sizeof(font) / sizeof(*font)))            return ANSI_FONT;
    if (matches_any(ext, cert, sizeof(cert) / sizeof(*cert)))            return ANSI_CERT;
    if (matches_any(ext, database, sizeof(database) / sizeof(*database))) return ANSI_DATABASE;
    return NULL;
}

/* Folder-role names -- same "long but organized into one-line-to-
 * extend categories" approach as the extensions above. No name
 * appears in more than one list. These lean heavily into "every
 * mainstream naming convention across every ecosystem" (JS/Node,
 * Python, Rust, Go, JVM, .NET, Ruby, PHP, mobile, infra/devops, ...)
 * specifically so a real project doesn't have to rename anything just
 * to get coloured -- ltree colours what exists. */
const char *dir_name_color(const Config *cfg, const char *name) {
    if (cfg->no_colour) return NULL;

    static const char *const src[] = {
        "src", "source", "srcs", "sources", "lib", "libs", "library", "libraries", "core",
        "cmd", "cmds", "cli", "pkg", "pkgs", "package", "packages", "internal", "app",
        "apps", "application", "backend", "frontend", "server", "client", "include",
        "includes", "inc", "modules", "module", "components", "component", "views", "view",
        "controllers", "controller", "models", "model", "entities", "entity", "services",
        "service", "handlers", "handler", "middleware", "middlewares", "routes", "route",
        "router", "routers", "plugins", "plugin", "extensions", "extension", "addons",
        "addon", "drivers", "driver", "providers", "provider", "repositories", "repository",
        "domain", "domains", "business", "kernel", "engine", "runtime", "common", "shared",
        "base"
    };
    static const char *const docs[] = {
        "docs", "doc", "documentation", "wiki", "man", "manual", "manuals", "guide",
        "guides", "tutorial", "tutorials", "help", "faq", "faqs", "readme", "changelog",
        "changelogs", "notes", "note", "reference", "references", "specification",
        "specifications", "design", "designs", "rfc", "rfcs", "proposal", "proposals",
        "adr", "adrs", "api-docs", "userguide", "user-guide", "developer-guide", "dev-docs",
        "knowledge-base", "kb", "handbook", "primer", "cookbook", "cheatsheet", "glossary",
        "appendix", "whitepaper", "whitepapers", "instructions", "howto", "how-to",
        "walkthrough", "overview"
    };
    static const char *const test[] = {
        "test", "tests", "spec", "specs", "e2e", "__tests__", "__mocks__", "mocks", "mock",
        "integration", "unit", "unittest", "unittests", "acceptance", "cypress",
        "playwright", "selenium", "jest", "mocha", "jasmine", "karma", "qa", "quality",
        "testdata", "test-data", "testsuite", "test-suite", "regression", "smoke",
        "smoketest", "e2e-tests", "integration-tests", "unit-tests", "snapshot",
        "snapshots", "__snapshots__", "benchmarks", "benchmark", "bench", "perf",
        "performance", "load-test", "stress-test", "sanity", "functional", "contract",
        "contracts", "testing", "features", "gherkin", "cucumber", "bdd", "tdd"
    };
    static const char *const build[] = {
        "build", "dist", "out", "target", "release", "bin", "obj", "output", "builds",
        "artifacts", "generated", "gen", "compiled", "_build", "cmake-build",
        "build-output", "publish", "wwwroot", "debug", "x64", "x86", ".next", ".nuxt",
        ".output", ".vercel", ".netlify", ".turbo", "classes", "bld", "objs", "out-tsc",
        ".angular", ".svelte-kit", ".docusaurus", "dist-newstyle", "_site",
        ".jekyll-cache", "public_html", "htdocs", "deployment", "generated-sources",
        "final", "packaged", "cdk.out", "tsc-out", ".webpack"
    };
    static const char *const vendor[] = {
        "node_modules", "vendor", "vendored", "deps", "dependencies", "venv", ".venv",
        "virtualenv", ".git", "third_party", "thirdparty", "external", "externals",
        "bower_components", "jspm_packages", ".bundle", "gems", "Pods", "Carthage",
        "DerivedData", ".cargo", ".yarn", ".pnpm-store", "elm-stuff", "vendors", ".tox",
        ".nox", "site-packages", ".eggs", "conan", ".conan", "vcpkg", "vcpkg_installed",
        ".stack-work", "_opam", ".cabal-sandbox", ".m2", ".ivy2", ".nuget", ".paket",
        ".terraform", ".serverless", ".aws-sam", "Godeps", ".glide"
    };
    static const char *const assets[] = {
        "assets", "static", "public", "templates", "examples", "scripts", "tools", "utils",
        "config", "configs", "api", "resources", "images", "img", "imgs", "videos",
        "video", "audio", "sounds", "sound", "media", "icons", "icon", "fonts", "font",
        "styles", "style", "stylesheets", "css", "layouts", "layout", "partials",
        "pictures", "photos", "graphics", "banners", "thumbnails", "thumbs", "uploads",
        "upload", "downloads", "download", "files", "attachments", "sprites", "textures",
        "shaders", "animations", "vectors", "svgs", "illustrations", "wallpapers",
        "themes", "theme", "skins", "skin", "brand", "branding", "marketing", "press",
        "presskit"
    };
    static const char *const data[] = {
        "data", "datasets", "dataset", "fixtures", "migrations", "migration", "seeds",
        "seed", "db", "database", "storage", "raw-data", "processed-data", "interim-data",
        "external-data", "warehouse", "datalake", "data-lake", "exports", "export",
        "imports", "import", "backups", "backup", "dumps", "dump", "records", "tables",
        "schemas", "schema", "etl", "pipelines", "pipeline", "datastore", "blob", "blobs",
        "corpus", "corpora", "catalog", "catalogs", "inventory"
    };
    static const char *const logs[] = {
        "logs", "log", "tmp", "temp", ".tmp", ".temp", "cache", ".cache", "coverage",
        ".nyc_output", ".pytest_cache", ".mypy_cache", ".ruff_cache", "__pycache__",
        ".sass-cache", ".eslintcache", "crashlogs", "crash-logs", "core-dumps",
        "coredumps", "debug-logs", "error-logs", "access-logs", "audit-logs", "scratch",
        "trash", ".trash", "recycle", "TempFiles", "temp-files", ".parcel-cache",
        ".webpack-cache", ".npm", ".yarn-cache", ".rollup-cache", ".esbuild-cache",
        ".swc", ".ipynb_checkpoints"
    };
    static const char *const ci[] = {
        ".github", ".gitlab", ".circleci", ".azure-pipelines", "workflows", "ci",
        ".buildkite", ".travis", ".drone", ".jenkins", "jenkins", ".teamcity",
        ".appveyor", ".codeship", ".semaphore", ".bitbucket-pipelines",
        "bitbucket-pipelines", ".concourse", ".woodpecker", ".cirrus", "azure-pipelines",
        "github-actions", "gitlab-ci", ".gitlab-ci", ".argo", ".tekton", "tekton",
        ".flux", "fluxcd", "continuous-integration", "continuous-deployment", "cd"
    };
    static const char *const ide[] = {
        ".vscode", ".idea", ".vs", ".eclipse", ".settings", ".fleet", ".nvim", ".vim",
        ".sublime", ".atom", ".zed", ".helix", ".nova", ".cursor", ".windsurf", ".xcode",
        ".metadata", ".project", ".clion", ".rider", ".webstorm", ".pycharm", ".goland",
        ".rubymine", ".datagrip", ".androidstudio", ".netbeans", ".code", ".theia",
        ".codelite"
    };
    static const char *const i18n[] = {
        "locale", "locales", "i18n", "l10n", "lang", "langs", "language", "languages",
        "translations", "translation", "messages", "gettext", "locale-data",
        "language-packs", "language-pack", "strings", "localizable", "lproj", "intl",
        "internationalization", "localization", "multilang", "nls", "resource-bundles",
        "i18n-data"
    };
    static const char *const secrets[] = {
        "secrets", ".secrets", "credentials", ".credentials", "keys", ".keys", "certs",
        "certificates", ".certs", ".ssh", "ssh-keys", "private", ".private", "sensitive",
        "vault", ".vault", "keystore", "keystores", "pki", "tls", "ssl", ".gnupg",
        "gpg-keys", ".aws", ".kube", "secure", "security", "password-store",
        ".password-store", "secrets-manager", "vault-data"
    };

    if (matches_any(name, src, sizeof(src) / sizeof(*src)))             return ANSI_DIR_SRC;
    if (matches_any(name, docs, sizeof(docs) / sizeof(*docs)))          return ANSI_DIR_DOCS;
    if (matches_any(name, test, sizeof(test) / sizeof(*test)))          return ANSI_DIR_TEST;
    if (matches_any(name, build, sizeof(build) / sizeof(*build)))       return ANSI_DIR_BUILD;
    if (matches_any(name, vendor, sizeof(vendor) / sizeof(*vendor)))    return ANSI_DIR_VENDOR;
    if (matches_any(name, assets, sizeof(assets) / sizeof(*assets)))    return ANSI_DIR_ASSETS;
    if (matches_any(name, data, sizeof(data) / sizeof(*data)))          return ANSI_DIR_DATA;
    if (matches_any(name, logs, sizeof(logs) / sizeof(*logs)))          return ANSI_DIR_LOGS;
    if (matches_any(name, ci, sizeof(ci) / sizeof(*ci)))                return ANSI_DIR_CI;
    if (matches_any(name, ide, sizeof(ide) / sizeof(*ide)))             return ANSI_DIR_IDE;
    if (matches_any(name, i18n, sizeof(i18n) / sizeof(*i18n)))          return ANSI_DIR_I18N;
    if (matches_any(name, secrets, sizeof(secrets) / sizeof(*secrets))) return ANSI_DIR_SECRETS;
    return NULL;
}
