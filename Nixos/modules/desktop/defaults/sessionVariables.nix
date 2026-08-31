# &desc: "Session variables from default apps -- EDITOR, VISUAL, BROWSER from config.vars.desktop.default.apps; ANDROID_SDK_ROOT/ANDROID_HOME pointing Android Studio at the custom-composed SDK."

{
  config,
  ...
}:

let
  apps = config.vars.desktop.default.apps;
  androidSdk = config.vars.packages.environment.sources.custom.androidSdk;
in
{
  environment.sessionVariables = {
    EDITOR = apps.editor;
    VISUAL = apps.editor;
    BROWSER = apps.browser;

    # Points Android Studio (and adb/sdkmanager on PATH) at our
    # declaratively-composed SDK (API 28, see packages/registry.nix)
    # instead of the read-only SDK bundled inside android-studio-full,
    # which the SDK Manager UI can't write new platforms into.
    ANDROID_SDK_ROOT = "${androidSdk}/libexec/android-sdk";
    ANDROID_HOME = "${androidSdk}/libexec/android-sdk";
  };
}
