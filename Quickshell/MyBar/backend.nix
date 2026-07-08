{ stdenv, pkg-config, qt6, networkmanager, glib }:

# Builds the mybar-* backend binaries (appscanner/cpumonitor/memmonitor/
# netmonitor/notifserver) using the exact same recipe as
# scripts/build/compile.sh — that script is plain bash so it also runs
# standalone on non-Nix systems; this derivation just gives it a sandboxed
# build with qt6/networkmanager/glib wired onto PATH/PKG_CONFIG_PATH instead
# of relying on a distro package manager.
stdenv.mkDerivation {
  pname = "mybar-backend";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ qt6.qtbase networkmanager glib ];

  # These are plain CLI binaries (notifserver uses QtDBus/QtCore only, no
  # QML/plugins), not Qt GUI apps — nothing for wrapQtAppsHook to do.
  dontWrapQtApps = true;

  buildPhase = ''
    runHook preBuild
    bash scripts/build/compile.sh
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin binary/mybar-*
    runHook postInstall
  '';
}
