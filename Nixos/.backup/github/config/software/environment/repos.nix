# &desc: "Personal declarative git repos -- test repo (HerauxValle/test) declared to exercise modules/packages/repos end-to-end."

{ ... }:

# Personal picks -- which repos YOU want declaratively checked out/kept
# in sync (existence + local git config only -- see modules/packages/repos
# for exactly what "in sync" means and what it deliberately never touches).
# See glossar/software/repos.nix for every available field.
{
  config.vars.packages.repos.repos = {
    test = {
      url = "git@github.com:HerauxValle/test.git";
    };
  };
}
