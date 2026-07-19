# &desc: "Personal declarative git repos -- currently empty, see modules/packages/repos/default.nix for the schema."

{ ... }:

# Personal picks -- which repos YOU want declaratively checked out/kept
# in sync (existence + local git config only -- see modules/packages/repos
# for exactly what "in sync" means and what it deliberately never touches).
# Nothing declared here yet. Example shape:
#
#   config.vars.packages.repos.repos = {
#     some-project = {
#       url = "git@github.com:someuser/some-project.git";
#       # path = "~/Projects/some-project";  # default: basePath/<name>
#       # initialBranch = "main";
#       # userEmail = "you@example.com";
#     };
#   };
{
  config.vars.packages.repos.repos = { };
}
