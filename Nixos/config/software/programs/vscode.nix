# &desc: "VSCode configuration -- extensions, keybindings, and settings defined inline; personal setup with Nix, Python, Rust, C++ tooling."

{ config, pkgs, ... }:

{
  # Home-manager-only programs.* (not a NixOS system option, so it can't go
  # through config.vars.packages.programs -> modules/packages/programs/programs.nix
  # like the rest of this directory).
  config.home-manager.users.${config.vars.identity.username}.programs.vscode = {
    enable = false;
    mutableExtensionsDir = false;
    # `code --install-extension` can no
    # longer add anything outside the list
    # below -- add here and rebuild instead.
    profiles.default = {
      userSettings = {
        # ============================================================
        # Copilot
        # ============================================================
        "github.copilot.nextEditSuggestions.enabled" = false;
        "github.copilot.enable" = {
          "*" = false;
          plaintext = false;
          markdown = false;
          scminput = false;
        };
        # ============================================================
        # Appearance
        # ============================================================
        "workbench.iconTheme" = "material-icon-theme";
        "workbench.startupEditor" = "none";
        "workbench.editor.enablePreview" = true;
        "workbench.editor.enablePreviewFromQuickOpen" = true;
        "workbench.editor.highlightModifiedTabs" = true;
        "window.commandCenter" = false;
        "window.menuBarVisibility" = "toggle";
        "breadcrumbs.enabled" = true;
        # ============================================================
        # Explorer
        # ============================================================
        "explorer.compactFolders" = false;
        "explorer.confirmDelete" = false;
        "explorer.confirmDragAndDrop" = false;
        "explorer.sortOrder" = "type";
        # ============================================================
        # Editor
        # ============================================================
        "editor.mouseWheelZoom" = true;
        "editor.minimap.enabled" = false;
        "editor.smoothScrolling" = true;
        "editor.fastScrollSensitivity" = 5;
        "editor.mouseWheelScrollSensitivity" = 1.2;
        "editor.cursorSmoothCaretAnimation" = "on";
        "editor.cursorBlinking" = "smooth";
        "editor.cursorSurroundingLines" = 8;
        "editor.stickyScroll.enabled" = true;
        "editor.scrollBeyondLastLine" = false;
        "editor.linkedEditing" = true;
        "editor.bracketPairColorization.enabled" = true;
        "editor.guides.bracketPairs" = "active";
        "editor.occurrencesHighlight" = "singleFile";
        "editor.renderWhitespace" = "selection";
        "editor.renderLineHighlight" = "gutter";
        "editor.hover.delay" = 250;
        "editor.inlineSuggest.enabled" = true;
        "editor.quickSuggestions" = {
          comments = false;
          strings = true;
          other = true;
        };
        "editor.suggestSelection" = "recentlyUsed";
        "editor.codeLens" = false;
        "editor.detectIndentation" = true;
        "editor.tabSize" = 4;
        "editor.wordWrap" = "off";
        "editor.unicodeHighlight.ambiguousCharacters" = false;
        "editor.unicodeHighlight.invisibleCharacters" = false;
        "editor.formatOnSave" = true;
        "editor.formatOnPaste" = false;
        # ============================================================
        # Files
        # ============================================================
        "files.autoSave" = "afterDelay";
        "files.autoSaveDelay" = 1000;
        "files.trimTrailingWhitespace" = true;
        "files.insertFinalNewline" = true;
        # ============================================================
        # Terminal
        # ============================================================
        "terminal.integrated.smoothScrolling" = true;
        "terminal.integrated.cursorBlinking" = true;
        "terminal.integrated.gpuAcceleration" = "auto";
        # Uncomment if you use fish
        # "terminal.integrated.defaultProfile.linux" = "fish";
        # ============================================================
        # Git
        # ============================================================
        "git.autofetch" = true;
        "git.confirmSync" = false;
        "git.enableSmartCommit" = true;
        # ============================================================
        # Telemetry
        # ============================================================
        "telemetry.feedback.enabled" = false;
        "telemetry.telemetryLevel" = "off";
        # ============================================================
        # Extensions
        # ============================================================
        "extensions.autoCheckUpdates" = true;
        "extensions.autoUpdate" = "on";
        # ============================================================
        # Chat
        # ============================================================
        "chat.mcp.gallery.enabled" = true;
        # ============================================================
        # Todo Tree
        # ============================================================
        # Real store path instead of hardcoding the current system
        # generation's /run/current-system/sw/bin/rg, which breaks
        # under rollbacks or a standalone home-manager profile.
        "todo-tree.ripgrep.ripgrep" = "${pkgs.ripgrep}/bin/rg";
        # ============================================================
        # Nix
        # ============================================================
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "nil";
        "nix-embedded-languages.variableMarkers.suffix" = {
          Script = "shell";
        };
        "nix-embedded-languages.variableMarkers.prefix" = {
          py = "python";
        };
        "nix-embedded-languages.functionBindings" = {
          "writePython3|writePyPy3" = "python";
        };
        # ============================================================
        # EXTRA
        # ============================================================
        "editor.fontLigatures" = true;
        "editor.fontVariations" = true;
        "editor.cursorWidth" = 2;
        "editor.cursorStyle" = "line";
        "workbench.tree.renderIndentGuides" = "always";
        "workbench.tree.indent" = 16;
        "diffEditor.ignoreTrimWhitespace" = false;
        "files.simpleDialog.enable" = true;
        "search.quickOpen.includeHistory" = true;
        "editor.guides.indentation" = true;
        "editor.guides.highlightActiveIndentation" = true;
        "editor.selectionHighlight" = true;
        "editor.semanticHighlighting.enabled" = true;
        "editor.inlayHints.enabled" = "on";
        "editor.parameterHints.enabled" = true;
        "editor.matchBrackets" = "always";
        "workbench.activityBar.compact" = true;
        "workbench.activityBar.autoHide" = true;
        "workbench.activityBar.location" = "top";
        "telemetry.editStats.enabled" = false;
      };
      keybindings = [
        {
          key = "ctrl+t";
          command = "workbench.action.terminal.toggleTerminal";
        }
      ];
      extensions =
        (with pkgs.vscode-extensions; [
          # --- Original Extensions ---
          bbenoist.nix
          gruntfuggly.todo-tree
          jnoortheen.nix-ide
          ms-python.debugpy
          ms-python.python
          ms-python.vscode-pylance
          ms-python.vscode-python-envs
          pkief.material-icon-theme
          # Already handles your Rust LSP (rust-analyzer)
          rust-lang.rust-analyzer

          # --- C / C++ ---
          # C/C++ IntelliSense, debugging, and code browsing
          ms-vscode.cpptools
          # twxs.cmake         # (Optional) Uncomment if you use CMake

          # --- Go ---
          # Rich Go language support (uses gopls)
          golang.go

          # --- HTML / CSS / Web Development ---
          # HTML CSS Support
          ecmel.vscode-html-css
          formulahendry.auto-close-tag
          formulahendry.auto-rename-tag
          # bradlc.vscode-tailwindcss # (Optional) Uncomment if you use Tailwind CSS

          # --- General Productivity & Nix Integration ---
          # Loads development environment shell (highly recommended)
          mkhl.direnv
          # Standardizes editor configs across teams
          editorconfig.editorconfig
          # Opinionated code formatter (highly recommended)
          esbenp.prettier-vscode
          # Supercharged Git visualization (highly recommended)
          eamodio.gitlens

          # --- JSON, YAML, & Configs ---
          # Dictates strict formatting for JSON, JSONC, and markdown
          esbenp.prettier-vscode

          # Rich JSON Schema validation, autocompletion, and YAML support
          redhat.vscode-yaml
        ])
        ++ [
          # --- Custom Marketplace Extensions ---
          (pkgs.vscode-utils.extensionFromVscodeMarketplace {
            publisher = "dustypomerleau";
            name = "rust-syntax";
            version = "0.6.1";
            sha256 = "0rccp8njr13jzsbr2jl9hqn74w7ji7b2spfd4ml6r2i43hz9gn53";
          })
          (pkgs.vscode-utils.extensionFromVscodeMarketplace {
            publisher = "coopermaruyama";
            name = "nix-embedded-languages";
            version = "2.1.0";
            sha256 = "1vr5njvzxck2nx6gqw0zfghnjpwcmvli9fwx8cqj3sgk9283ya9r";
          })
        ];
    };
  };
}
