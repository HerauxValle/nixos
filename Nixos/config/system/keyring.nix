
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

  # Keeps the keyring's own master password in sync with the account
  # password. `passwd` is the PAM service the real `passwd` command runs
  # through -- Scripts/Secrets/cmd/passwd.sh now calls it directly, which
  # (with this enabled) re-keys the login keyring in place via
  # pam_gnome_keyring's own chauthtok hook, no data lost.
  security.pam.services.passwd.enableGnomeKeyring = true;
}
