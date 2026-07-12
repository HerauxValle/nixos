{ lib, pkgs }:

# Shared builder every per-service module (./ollama, ./comfyui, ...) calls
# for the part that's genuinely identical across all of them: a live
# systemd unit, plus a manual-only reconciliation oneshot for services that
# need one. Each service module owns everything actually specific to it
# (its own typed options, its own package/fetch logic, its own
# reconciliation script content) and calls these with just the handful of
# values that differ. Adding a new service means writing one subfolder
# module against this, not a new engine -- this file is deliberately the
# only place the "how" of running a systemd unit is written.
#
# Plain function library, not a NixOS module itself (no `config`/`options`)
# -- imported directly by each service subfolder: `import ../self-hosted.nix
# { inherit lib pkgs; }`.
#
# Split into ./lib/{service,venv}/mk-*.nix, one function per file, once
# this file grew past ~400 lines -- this file itself is now just wiring
# those together (cross-references passed explicitly, e.g.
# mkSelfHostedService needs mkTeardownActivationScript) and re-exporting
# the same flat set of names as before the split. Nothing about the
# public shape changed -- every caller still does
# `selfHosted.mkSelfHostedService { ... }` exactly as before.
#
# ./lib/service/ -- systemd-unit builders (the live service, its
# disabled-teardown counterpart, the manual-action dispatch unit).
# ./lib/venv/ -- the Python FHS+pip lifecycle (sandbox, install, the
# idempotent preStart wrapper, the pip-compile update/diff logic).
# ./lib/mk-from-native/ -- the opposite of ./lib/service/: wrap a real,
# already-mature nixpkgs/NUR module or package instead of building a
# service from scratch (Immich's services.immich, the first and only
# caller so far). See its own README.md for the full category list.
# ./lib/acl-traversal/ -- the one deliberate exception to "plain function
# library, never a NixOS module" above: mk-acl-traversal.nix is a plain
# function (re-exported below, same as everything else), but the
# directory *also* holds a real options/config module (its own
# default.nix + acl-traversal.nix) declaring
# vars.selfHosted.aclTraversal -- a flat, machine-level array of "which
# dedicated system user needs traversal rights into which restrictive
# ancestor directory it doesn't own" grants, wired into
# modules/services/self-hosted/default.nix's own imports (unlike every
# other lib/ function, which only ever gets consumed by a service's own
# wiring file, never imported as a module itself). Real caller:
# config/self-hosted/acl-traversal.nix grants qbittorrent -- the
# dedicated qbittorrent user can't traverse /run/media/<user> (0750
# root:root) -- ProtectHome=tmpfs+BindPaths, Immich's own fix for a
# similar-looking problem, doesn't help here since /run/media isn't
# /home at all.
#
# No mkUninstallScript / @uninstall action anymore -- deliberately
# removed, not just narrowed. Everything it used to do is now either
# already automatic (nodes/models removal via preStart, venv
# rebuild-on-lock-change via mkVenvEnsureScript) or was never actually
# safe to script in the first place: dataDir also holds genuinely
# precious content no reconciliation touches (ComfyUI's output/, for
# one -- real generated images, not disposable cruft), which deserves
# the exact same protection storage-backed data already gets. A wipe
# of "whatever's not currently declared" is always a deliberate,
# by-hand `rm -rf`, never a maintained action someone can fat-finger.

let
  mkTeardownActivationScript = import ./lib/service/mk-teardown-activation-script.nix { inherit lib; };
  mkSelfHostedService = import ./lib/service/mk-self-hosted-service.nix { inherit lib pkgs mkTeardownActivationScript; };
  mkActionService = import ./lib/service/mk-action-service.nix { inherit lib pkgs; };
  mkFHSVenv = import ./lib/venv/mk-fhs-venv.nix { inherit pkgs; };
  mkVenvInstallScript = import ./lib/venv/mk-venv-install-script.nix { inherit lib; };
  mkVenvEnsureScript = import ./lib/venv/mk-venv-ensure-script.nix { inherit lib mkVenvInstallScript; };
  mkDepsUpdateScript = import ./lib/venv/mk-deps-update-script.nix;
  mkFromNativeService = import ./lib/mk-from-native/services.nix { inherit lib pkgs; };
  mkAclTraversal = import ./lib/acl-traversal/mk-acl-traversal.nix { inherit lib pkgs; };
in
{
  inherit
    mkSelfHostedService
    mkTeardownActivationScript
    mkFHSVenv
    mkVenvInstallScript
    mkVenvEnsureScript
    mkDepsUpdateScript
    mkActionService
    mkFromNativeService
    mkAclTraversal;
}
