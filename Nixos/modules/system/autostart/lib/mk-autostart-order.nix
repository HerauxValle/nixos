
{ lib }:

# &desc: "Asserts config.vars.system.autostart.jobs has no dependsOn cycles or unknown job references."

# Pure validation, no execution -- the actual dispatch scripts (see
# ./mk-autostart-dispatch.nix) resolve dependencies lazily at runtime
# via `systemctl <verb> autostart@<dep>`, which only works because this
# function has already proven, at eval time, that following those
# dependsOn edges can never loop back on itself. A cycle here fails
# `nixos-rebuild switch` outright via config.assertions, before
# anything is built or applied -- never a partial apply.
#
# Checked independently per action (execStart/execRestart/execStop) --
# nothing requires the three to share one graph; a job can legitimately
# have different dependents for "come up" than for "go down". Callers
# are expected to have already filtered `jobs` down to enabled ones --
# a dependsOn pointing at a disabled (or nonexistent) sibling is exactly
# as invalid as one pointing at an id that was never declared.
{ jobs }:

let
  ids = builtins.attrNames jobs;
  actionNames = [ "execStart" "execRestart" "execStop" ];

  edgesFor = actionName:
    lib.mapAttrs
      (_: job: if job.${actionName} == null then [ ] else job.${actionName}.dependsOn)
      jobs;

  unknownRefs = actionName:
    let edges = edgesFor actionName; in
    lib.concatLists (lib.mapAttrsToList
      (id: deps: map (dep: { inherit actionName id dep; }) (lib.subtractLists ids deps))
      edges);

  # DFS with the current path as the "visited" set -- fine at this
  # scale (a handful of jobs), no need for a linear-time visited/stack
  # pair. `path` closing back to `id` is the cycle itself, reported
  # in the assertion message so it's obvious what to fix.
  hasCycle = actionName:
    let
      edges = edgesFor actionName;
      visit = path: id:
        if lib.elem id path then path ++ [ id ]
        else lib.findFirst (c: c != null) null (map (visit (path ++ [ id ])) (edges.${id} or [ ]));
    in
    lib.findFirst (c: c != null) null (map (visit [ ]) ids);

  cycleAssertions = map
    (actionName:
      let cycle = hasCycle actionName; in
      {
        assertion = cycle == null;
        message =
          "config.vars.system.autostart.jobs: ${actionName} dependsOn cycle -- "
          + lib.concatStringsSep " -> " (if cycle == null then [ ] else cycle) + ".";
      })
    actionNames;

  refAssertions = lib.concatMap
    (actionName: map
      (bad: {
        assertion = false;
        message = "config.vars.system.autostart.jobs.${bad.id}.${bad.actionName}.dependsOn references unknown/disabled job '${bad.dep}'.";
      })
      (unknownRefs actionName))
    actionNames;
in
{
  assertions = cycleAssertions ++ refAssertions;
}
