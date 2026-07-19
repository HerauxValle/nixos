# &desc: "Test Python venv (python311 with six and tabulate) -- exercises venv builder before real use, pinning vs floating, manual and direnv activation."

{ ... }:

# Smallest possible venv to sanity-check modules/packages/venvs before
# trusting it with anything real. debug logLevel so a rebuild actually
# shows what build.sh is doing instead of staying silent on success.
{
  config.vars.packages.venvs = {
    logLevel = "debug";
    # basePath left at its default (~/.impure/python-venvs/nix-declared)

    venvs = {
      test = {
        python = "python311";
        packages = {
          six = "1.16.0"; # pinned, tiny, no deps of its own -- good pin-path check
          tabulate = "latest"; # floating -- checks the "installed once, update bumps it" path
        };
        # no activation block -- built, but not direnv-auto-activated;
        # exercises `venvctl activate test` / the fish shim instead.
        activation = {
          onEntry = true;
          paths = {
            "~/Dotfiles/test/" = "recursive";
          };
        };
      };
    };
  };
}
