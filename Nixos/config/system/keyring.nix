
{ ... }:

# &desc: "Enables a system secret-service keyring so apps like Claude Desktop can persist logins instead of re-prompting every restart; keyring password stays declaratively in sync with the account password."

# Without a running org.freedesktop.secrets provider, Electron apps
# (Claude Desktop among them) can't persist credentials at all -- login
# works for the session but is gone on next launch/reboot. GNOME Keyring
# provides that service and works fine outside a GNOME session (used
# here with SDDM/Hyprland). enableGnomeKeyring on the sddm PAM service
# unlocks it automatically using the login password, so no extra prompt
# is added to the login flow.
{
  services.gnome.gnome-keyring.enable = false;
  security.pam.services.sddm.enableGnomeKeyring = true;

  # The login keyring's own master password is a SEPARATE secret from the
  # account password -- it's whatever it happened to be when the keyring
  # was first created, and nothing keeps it in sync automatically unless
  # something wires pam_gnome_keyring into the PAM stack that actually
  # changes your password. That's what this does: `passwd` is the PAM
  # service the real `passwd` command runs through (used by
  # Scripts/Secrets/cmd/passwd.sh as the second half of a password
  # change -- see that script). enableGnomeKeyring here adds
  # pam_gnome_keyring's chauthtok hook to `passwd`'s password stack,
  # which calls GNOME Keyring's own tested "change master password"
  # D-Bus method (org.gnome.keyring...ChangeWithMasterPassword) using
  # your just-typed current password as the old key and your new
  # password as the replacement. It DECRYPTS-then-reencrypts everything
  # already stored (Vivaldi logins, etc.) rather than wiping the keyring
  # -- and if the current password you type doesn't actually match the
  # keyring's real password (they can drift apart, e.g. if the keyring
  # was created before this option existed), the decrypt step just fails
  # and nothing is touched -- it never falls back to deleting/recreating.
  #
  # This only keeps things in sync GOING FORWARD, starting from whenever
  # the keyring's password and your account password next actually
  # match. If they're already out of sync right now, reconcile that once
  # by hand with Seahorse ("Passwords and Keys" -- pkgs.seahorse, see
  # config/software/packages/packages.nix): right-click the "Login"
  # keyring -> Change Password, enter the keyring's real current
  # password (not necessarily your login password) as the old one and
  # your current login password as the new one. After that one-time
  # reconciliation, every future `secrets passwd` run keeps both in sync
  # automatically.
  security.pam.services.passwd.enableGnomeKeyring = true;
}
