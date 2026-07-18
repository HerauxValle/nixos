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
