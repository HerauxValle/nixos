# &desc: "gamdl-wrapper real values -- enabled, off-by-default autoStart, srcDir/ports/arch. Schema + wiring live in modules/services/gamdl/."

{
  config.vars.services.gamdlWrapper = {
    enabled = true;

    # Off -- only needed while actually doing a lossless (ALAC) download;
    # start by hand with `systemctl --user start gamdl-wrapper`.
    autoStart = false;

    # Defaults (srcDir/httpPort/decryptPort/targetArch) from
    # modules/services/gamdl/default.nix are all fine as-is for this
    # single-machine, x86_64 setup -- nothing to override here yet.
  };
}
