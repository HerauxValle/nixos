# &desc: "Personal git push-target registry -- test repo (HerauxValle/test) declared to exercise modules/packages/repos/gitctl end-to-end."

{ ... }:

# Personal picks -- which EXISTING local dirs you want `gitctl
# push`/`release` to push, and where. Never clones/creates `path` itself
# -- see modules/packages/repos for exactly what this does and doesn't
# touch, and glossar/software/repos.nix for every available field.
{
  config.vars.packages.repos.repos = {
    test = {
      path = "~/Projects/test";
      remotes = {
        origin = {
          url = "git@github.com:HerauxValle/test.git";
          mode = "squash";
        };
      };
      githubRepo = "HerauxValle/test";
    };
  };
}
