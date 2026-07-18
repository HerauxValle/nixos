
{ ... }:

# &desc: "Enables a system secret-service keyring so apps like Claude Desktop can persist logins instead of re-prompting every restart."

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
}
