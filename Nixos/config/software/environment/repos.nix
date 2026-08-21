# &desc: "Personal git push-target registry -- test repo (HerauxValle/test) and YoutubeDLP declared to exercise modules/packages/repos/gitctl end-to-end."

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

    youtubedlp = {
      path = "~/Projects/YoutubeDLP";
      # history mode: real commits, no force-push -- requires ~/Projects/YoutubeDLP
      # to already be `git init`'d (gitctl stages+commits, but never creates
      # the repo itself; see modules/packages/repos/lib/push.sh).
      remotes = {
        origin = {
          url = "git@github.com:HerauxValle/YoutubeDLP.git";
          mode = "history";
        };
      };
      githubRepo = "HerauxValle/YoutubeDLP";
    };
  };
}
