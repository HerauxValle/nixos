# &desc: "Jellyfin .NET binary packaging -- fetches release tarball, patches native libs (fontconfig/libstdc++), autoPatchelfHook."

{ pkgs }:

# Pinned straight from jellyfin's own repo.jellyfin.org release tarballs --
# same reasoning as ollama/package.nix (own pin, not nixpkgs' `jellyfin`,
# which builds the whole .NET project from source via buildDotnetModule --
# heavier, and ties the version to nixpkgs' own unrelated schedule).
#
# A self-contained .NET publish, dynamically linked against a handful of
# native libs (confirmed via a real `ldd` on the extracted binary and its
# bundled libSkiaSharp.so/libSystem.*.so, not guessed): libstdc++ (the
# main apphost), libfontconfig (libSkiaSharp, subtitle/thumbnail
# rendering), plus icu/openssl/zlib/sqlite for the usual .NET runtime
# surface (globalization, TLS, compression, its own sqlite databases).
# autoPatchelfHook resolves all of it against buildInputs below and hard-
# fails the build if anything's still missing, so this list is verified
# by the build itself succeeding, not just plausible.

{ version, hash }:

pkgs.stdenv.mkDerivation {
  pname = "jellyfin";
  inherit version;

  src = pkgs.fetchurl {
    url = "https://repo.jellyfin.org/files/server/linux/latest-stable/amd64/jellyfin_${version}-amd64.tar.gz";
    inherit hash;
  };

  # The default fixupPhase's strip corrupts .NET's managed assemblies
  # (PE format, not ELF -- confirmed by a real build: the resulting
  # System.Private.CoreLib.dll's checksum differed from the untouched
  # tarball's copy, and the binary failed to start with "incorrect
  # format"). nixpkgs' own buildDotnetModule defaults dontStrip = true
  # for exactly this reason -- same fix here, not guessed.
  dontStrip = true;

  nativeBuildInputs = [ pkgs.autoPatchelfHook pkgs.makeWrapper ];
  buildInputs = [
    pkgs.stdenv.cc.cc.lib
    pkgs.fontconfig
    pkgs.icu
    pkgs.openssl
    pkgs.zlib
    pkgs.sqlite
  ];

  # liblttng-ust.so.0 -- wanted by libcoreclrtraceptprovider.so (.NET's
  # tracing/diagnostics provider). The live process runs with
  # DOTNET_EnableDiagnostics=0 (ported from the old launch.sh, which
  # explicitly disabled this: "disable dotnet diagnostics socket -- not
  # needed in prod") -- this code path is never exercised, so ignoring
  # the missing lib rather than pulling in a real dependency for a
  # feature that's deliberately off. Same reasoning as ollama/package.nix's
  # ignored libcuda.so.1/libvulkan.so.1.
  autoPatchelfIgnoreMissingDeps = [ "liblttng-ust.so.0" ];

  # The tarball's payload (jellyfin apphost + its hundreds of sibling
  # .dll files, a self-contained .NET publish -- they must stay
  # together, can't be split into bin/lib) goes under $out/lib/jellyfin/.
  # $out/bin/jellyfin is a real wrapper script (makeWrapper), not a thin
  # symlink -- has to be, to set LD_LIBRARY_PATH (see below).
  #
  # LD_LIBRARY_PATH -- confirmed by real runs, not guessed: several of
  # .NET's native interop shims dlopen() their target library by plain
  # SONAME at runtime rather than declaring it as a static ELF NEEDED
  # entry, so autoPatchelfHook's RPATH-based fixup (which handles every
  # other native dep here) never touches them. Found incrementally, each
  # confirmed by a real crash and a real clean run after the fix:
  # libSystem.Globalization.Native.so -> libicuuc.so/libicui18n.so
  # ("Couldn't find a valid ICU package"), and
  # libSystem.Security.Cryptography.Native.OpenSsl.so -> libssl.so/
  # libcrypto.so ("No usable version of libssl was found") -- the second
  # one only surfaced running under a *minimal* systemd unit environment,
  # not an interactive shell (which has enough ambient library paths to
  # accidentally paper over it) -- a real lesson: verify against the
  # actual systemd-run environment, not just an interactive `bin/jellyfin`
  # invocation that happens to work.
  installPhase = ''
    mkdir -p "$out/lib/jellyfin" "$out/bin"
    cp -r . "$out/lib/jellyfin"
    makeWrapper "$out/lib/jellyfin/jellyfin" "$out/bin/jellyfin" \
      --prefix LD_LIBRARY_PATH : "${pkgs.icu}/lib:${pkgs.openssl.out}/lib"
  '';

  meta.mainProgram = "jellyfin";
}
