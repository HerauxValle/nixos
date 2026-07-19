# &desc: "VS Code editor behavior -- cursor, scrolling, formatting, guides, inlay hints, and diff view."

{ config, ... }:

{
  # Home-manager-only programs.* (not a NixOS system option, so it can't go
  # through config.vars.packages.programs -> modules/packages/programs/programs.nix
  # like the rest of this directory).
  config.home-manager.users.${config.vars.identity.username}.programs.vscode.profiles.default.userSettings =
    {
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
      "editor.fontLigatures" = true;
      "editor.fontVariations" = true;
      "editor.cursorWidth" = 2;
      "editor.cursorStyle" = "line";
      "editor.guides.indentation" = true;
      "editor.guides.highlightActiveIndentation" = true;
      "editor.selectionHighlight" = true;
      "editor.semanticHighlighting.enabled" = true;
      "editor.inlayHints.enabled" = "on";
      "editor.parameterHints.enabled" = true;
      "editor.matchBrackets" = "always";
      "diffEditor.ignoreTrimWhitespace" = false;
    };
}
