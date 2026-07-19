# &desc: "Passwordless sudo via keyfile -- wires the setuid-root PAM checker (./lib/checker, ./lib/checker-stub) and activation-time registration (./lib/register.nix) into PAM, security.wrappers, and system.activationScripts."

{ config, pkgs, lib, ... }:

let
  cfg = config.vars.security.sudoKeyfile;

  # The setuid-root wrapper's installed path -- this, not the raw
  # ${checker}/bin path, is what PAM and the self-test must actually
  # invoke, since only this one runs with root privilege.
  wrapperPath = "${config.security.wrapperDir}/sudo-keyfile-check";

  checker = import ./lib/checker { inherit pkgs cfg; };
  checkerStub = import ./lib/checker-stub { inherit pkgs checker; };
  registerScript = import ./lib/register.nix { inherit pkgs cfg checker; };
in

# Sudo keyfile auth
lib.mkIf cfg.enable {
  system.activationScripts.sudoKeyfile.text = registerScript;

  # Setuid-root wrapper around the (otherwise unprivileged) checker --
  # same mechanism NixOS uses for sudo/ping themselves. Required because
  # PAM's auth phase invokes this as the calling user, but reading the raw
  # block device and the root-owned hash/conf files needs real root.
  security.wrappers.sudo-keyfile-check = {
    source = "${checkerStub}/bin/sudo-keyfile-check-stub";
    owner = "root";
    group = "root";
    setuid = true;
  };

  security.pam.services.sudo.rules.auth.keyfile = {
    # Just before the standard `unix` (password) rule, so a present,
    # valid keyfile skips the password prompt entirely -- but a missing/
    # wrong one always falls through to it (`sufficient`, not
    # `required`; unix itself is untouched).
    order = config.security.pam.services.sudo.rules.auth.unix.order - 50;
    control = "sufficient";
    modulePath = "${pkgs.linux-pam}/lib/security/pam_exec.so";
    args = [ "quiet" wrapperPath ];
  };
}
