# &desc: "Session variables from default apps -- EDITOR, VISUAL, BROWSER from config.vars.desktop.default.apps."

{
  config,
  ...
}:

let
  apps = config.vars.desktop.default.apps;
in
{
  environment.sessionVariables = {
    EDITOR = apps.editor;
    VISUAL = apps.editor;
    BROWSER = apps.browser;
  };
}
